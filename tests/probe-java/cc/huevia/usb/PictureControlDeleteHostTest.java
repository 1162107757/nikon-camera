package cc.huevia.usb;
import cc.huevia.ptp.*;
import cc.huevia.picturecontrol.PictureControlData;
import android.hardware.usb.*;
import java.io.*;
import java.util.*;
import java.lang.reflect.Method;
import java.nio.charset.StandardCharsets;

/** Fault-injected deletion session and actual bounded USB transport, entirely synthetic. */
public final class PictureControlDeleteHostTest {
    private static int checks;
    public static void main(String[] args)throws Exception{
        for(String fault:List.of("ok","unsupported","wrong-camera","changed","race","active","reject","lost","occupied","neighbor","bad-data","wrong-tx","lost-readback")){
            Core core=new Core();core.fault=fault;PictureControlDeleteSession.Result result=new PictureControlDeleteSession.Result();
            PictureControlDeleteSession session=new PictureControlDeleteSession(core,confirmation(core),result);
            boolean success=false;try{session.run();success=true;}catch(IOException expected){}finally{session.closeSession();}
            check(success==fault.equals("ok"),"success boundary "+fault);
            check(result.verified==fault.equals("ok"),"only exact empty and unchanged neighbors verify "+fault);
            boolean noDelete=List.of("unsupported","wrong-camera","changed","race","active").contains(fault);
            check(core.deletes==(noDelete?0:1),"one attempt or none "+fault);
            check(core.commands.stream().allMatch(x->x==0x1002||x==0x1003||x==0x90ce),"never uploads, selects, deletes objects or resets "+fault);
            if(List.of("lost","wrong-tx","lost-readback").contains(fault))check(!core.commands.contains(0x1003),"uncertain framing sends no cleanup command "+fault);
            int count=core.deletes;try{session.run();throw new AssertionError("repeat accepted");}catch(IOException expected){}check(count==core.deletes,"same session cannot repeat "+fault);
        }
        for(PtpUsbTransport.Mode mode:PtpUsbTransport.Mode.values()){
            Core core=new Core();Peer peer=new Peer(core);UsbDevice device=new UsbDevice();PtpUsbTransport transport=new PtpUsbTransport(device,new UsbManager(device,peer),new ArrayList<>(),mode);
            try{
                rejects(()->transport.command(0x90ce,1,207));
                if(mode==PtpUsbTransport.Mode.DELETE_CONFIRMED_PC){
                    rejects(()->transport.authorizeDeletion(1));transport.authorizeDeletion(207);
                    rejects(()->transport.command(0x90ce,1,208));rejects(()->transport.command(0x100b,1,207));
                    rejects(()->transport.sendData(0x90cd,1,profile("WRITE"),207,0));
                    transport.command(0x90ce,1,207);rejects(()->transport.command(0x90ce,2,207));check(core.deletes==1,"USB transport only consumes once");
                }else rejects(()->transport.authorizeDeletion(207));
            }finally{transport.close();}
        }
        Core core=new Core();Peer peer=new Peer(core);UsbDevice device=new UsbDevice();PictureControlDeleteSession.Result result=new PictureControlDeleteSession.Result();
        new UsbPictureControlDelete().delete(device,new UsbManager(device,peer),confirmation(core),result);
        check(result.verified&&result.sessionClosed&&peer.closed&&peer.claims==1&&peer.releases==1,"real USB adapter executes guarded plan and releases once");
        check(core.deletes==1&&core.reads.get(207)==3&&result.after.size()==9,"USB plan twice observes target then verifies all nine");
        System.out.println("PASS: "+checks+" custom-slot deletion safety / USB checks");
    }
    static final class Core implements PictureControlDeleteSession.Operations{
        final Map<Integer,byte[]> slots=new LinkedHashMap<>();final Map<Integer,Integer> reads=new HashMap<>();final List<Integer> commands=new ArrayList<>();
        String fault="ok";int deletes;
        Core()throws Exception{for(int item=201;item<=209;item++)slots.put(item,profile("KEEP "+item));}
        public void authorizeDeletion(int item)throws IOException{if(item!=207)throw new IOException("wrong authorization");}
        public byte[] getData(int op,long tx,long...params)throws IOException{
            if(op==0x1001)return info(!fault.equals("unsupported"),fault.equals("wrong-camera")?"Different":"Z 6_2",fault.equals("active"));
            if(op==0x90cf)return new byte[28];
            if(op==0x1015)return new byte[]{(byte)207};
            if(op!=0x90cc)throw new IOException("bad read");int item=(int)params[0],n=reads.getOrDefault(item,0)+1;reads.put(item,n);
            try{if(item==207&&(fault.equals("changed")&&n==1||fault.equals("race")&&n==2))slots.put(item,profile("NEW OWNER"));}catch(Exception e){throw new IOException(e);}
            if(deletes>0&&fault.equals("lost-readback"))throw new IOException("lost readback");
            if(deletes>0&&fault.equals("bad-data"))return new byte[37];
            return slots.get(item).clone();
        }
        public PtpContainer command(int op,long tx,long...params)throws IOException{
            commands.add(op);if(op==0x90ce){deletes++;if(params.length!=1||params[0]!=207)throw new AssertionError("wrong destructive target");
                if(fault.equals("reject"))return PtpContainer.response(0x2019,tx);
                if(!fault.equals("occupied"))slots.put(207,new byte[36]);
                if(fault.equals("neighbor"))slots.put(201,new byte[36]);
                if(fault.equals("lost"))throw new IOException("lost delete ack");
                if(fault.equals("wrong-tx"))return PtpContainer.response(0x2001,tx+1);
            }
            return PtpContainer.response(0x2001,tx);
        }
    }
    static final class Peer extends UsbDeviceConnection{
        final Core core;byte[] incoming=new byte[0];int offset,claims,releases;boolean closed;
        Peer(Core core){this.core=core;}
        public boolean claimInterface(UsbInterface intf,boolean force){claims++;return !force;}
        public boolean releaseInterface(UsbInterface intf){releases++;return true;}public void close(){closed=true;}
        public int bulkTransfer(UsbEndpoint e,byte[] bytes,int length,int timeout){return bulkTransfer(e,bytes,0,length,timeout);}
        public int bulkTransfer(UsbEndpoint e,byte[] bytes,int start,int length,int timeout){
            if(closed)throw new AssertionError("I/O after close");
            if(e.getDirection()==128){int n=Math.min(length,incoming.length-offset);if(n==0)return -1;System.arraycopy(incoming,offset,bytes,start,n);offset+=n;return n;}
            try{
                if(offset!=incoming.length)throw new AssertionError("overlapping command");
                PtpContainer c=new PtpContainerReader(new ByteArrayInputStream(Arrays.copyOfRange(bytes,start,start+length)),1024*1024).read();
                if(c.type()!=PtpContainer.COMMAND)throw new AssertionError("unexpected upload");
                ByteArrayOutputStream response=new ByteArrayOutputStream();
                if(c.code()==0x1001||c.code()==0x90cf||c.code()==0x90cc||c.code()==0x1015){response.write(PtpContainer.data(c.code(),c.transactionId(),core.getData(c.code(),c.transactionId(),c.parameters())).toBytes());response.write(PtpContainer.response(0x2001,c.transactionId()).toBytes());}
                else response.write(core.command(c.code(),c.transactionId(),c.parameters()).toBytes());
                incoming=response.toByteArray();offset=0;return length;
            }catch(IOException error){throw new RuntimeException(error);}
        }
    }
    private static PictureControlDeleteSession.Confirmation confirmation(Core core)throws Exception{
        byte[] bytes=core.slots.get(207);UsbPictureControlProbe.ItemRecord item=new UsbPictureControlProbe.ItemRecord(207,bytes);item.parsed=true;item.basePictureControl=PictureControlData.parse(bytes).basePictureControl();return new PictureControlDeleteSession.Confirmation(item,"Z 6_2");
    }
    private static byte[] profile(String name)throws Exception{Method m=UsbPictureControlImportHostTest.class.getDeclaredMethod("syntheticProfile",String.class);m.setAccessible(true);return(byte[])m.invoke(null,name);}
    private static byte[] info(boolean deletion,String model,boolean active){
        try{ByteArrayOutputStream bytes=new ByteArrayOutputStream();DataOutputStream out=new DataOutputStream(bytes);
            u16(out,100);u32(out,10);u16(out,100);str(out,"");u16(out,0);int[] ops=active?new int[]{0x1001,0x1002,0x1003,0x90cc,0x90cf,0x1015}:new int[]{0x1001,0x1002,0x1003,0x90cc,0x90cf};
            u32(out,ops.length+(deletion?1:0));for(int op:ops)u16(out,op);if(deletion)u16(out,0x90ce);u32(out,0);u32(out,active?1:0);if(active)u16(out,0xd200);u32(out,0);u32(out,0);str(out,"Nikon");str(out,model);str(out,"1.0");str(out,"redacted");return bytes.toByteArray();
        }catch(IOException impossible){throw new AssertionError(impossible);}
    }
    private static void u16(DataOutputStream out,int v)throws IOException{out.writeByte(v);out.writeByte(v>>>8);}private static void u32(DataOutputStream out,int v)throws IOException{u16(out,v);u16(out,v>>>16);}private static void str(DataOutputStream out,String s)throws IOException{out.writeByte(s.length()+1);out.write(s.getBytes(StandardCharsets.UTF_16LE));u16(out,0);}
    private interface Work{void run()throws Exception;}private static void rejects(Work w)throws Exception{try{w.run();throw new AssertionError("unsafe request accepted");}catch(IOException expected){checks++;}}
    private static void check(boolean value,String name){if(!value)throw new AssertionError(name);checks++;}
}
