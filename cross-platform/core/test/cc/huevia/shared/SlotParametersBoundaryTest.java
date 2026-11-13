package cc.huevia.shared;

import cc.huevia.library.SharedJson;
import cc.huevia.ptp.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;

/** The legacy parameter controller runs only after an acknowledged and exact preset readback. */
public final class SlotParametersBoundaryTest {
    private static int checks;
    private static void yes(boolean value){checks++;if(!value)throw new AssertionError("Slot parameters "+checks);}
    private interface Action{void run()throws Exception;}
    private static void rejects(Action work)throws Exception{try{work.run();throw new AssertionError("Unsafe parameter action");}catch(IOException expected){checks++;}}
    static int run(Path root)throws Exception {
        checks=0;Files.createDirectories(root);
        for(String mode:new String[]{"none","ok","unsupported","readonly","lost","rejected","mismatch"}){
            Path directory=Files.createDirectory(root.resolve(mode));Peer peer=new Peer(directory);peer.mode=mode;SharedSlots slots=new SharedSlots(directory.toFile());slots.open(peer,"session","camera-fixture",()->false);
            Map<String,Object> payload=SharedRuntime.map("session","session","kind","write","source",201,"target",202);
            if(!mode.equals("none"))payload.put("parameters",SharedRuntime.map("whiteBalance",4));
            Map<String,Object> plan=map(slots.request("camera.slots.prepare",payload,()->false));yes(peer.presetWrites==0&&peer.parameterWrites==0);yes(plan.containsKey("parameterSummary"));
            Map<String,Object> state=map(slots.request("camera.slots.execute",SharedRuntime.map("session","session","confirmationId",plan.get("confirmationId"),"confirmed",true),()->false));
            Map<String,Object> action=map(state.get("action")),result=map(action.get("parameterResult"));
            yes(Boolean.TRUE.equals(action.get("presetVerified")));yes("verified".equals(action.get("phase")));yes(peer.presetWrites==1);yes(peer.otherSlotsIntact());
            boolean uncertain=mode.equals("lost")||mode.equals("mismatch");yes(Boolean.valueOf(uncertain).equals(result.get("uncertain")));yes(Boolean.valueOf(uncertain).equals(action.get("parametersPending"))||mode.equals("none")&&action.get("parametersPending")==null);
            if(mode.equals("none")||mode.equals("unsupported")||mode.equals("readonly")){yes(peer.parameterWrites==0);if(mode.equals("none"))yes(peer.propertyReads==0);}
            else {yes(peer.parameterWrites==1);yes(peer.evidenceBeforeParameterWrite);}
            if(mode.equals("ok")){yes(peer.whiteBalance==4);yes("已调整并核对".equals(map(((List<?>)result.get("changes")).get(0)).get("status")));}
            final String session="session";rejects(()->slots.request("camera.slots.execute",SharedRuntime.map("session",session,"confirmationId",plan.get("confirmationId"),"confirmed",true),()->false));
            if(mode.equals("lost")){
                // Reopening/reconcile sees the completed preset, but never repeats an uncertain property write.
                slots.close();Peer reopened=new Peer(directory);reopened.items.put(202,peer.items.get(202).clone());reopened.whiteBalance=peer.whiteBalance;
                slots.open(reopened,"new-session","camera-fixture",()->false);
                state=map(slots.request("camera.slots.reconcile",SharedRuntime.map("session","new-session"),()->false));action=map(state.get("action"));
                yes(Boolean.TRUE.equals(action.get("presetVerified")));yes(Boolean.TRUE.equals(action.get("parametersPending")));yes(reopened.parameterWrites==0&&reopened.presetWrites==0);
                rejects(()->slots.request("camera.slots.prepare",SharedRuntime.map("session","new-session","kind","write","source",201,"target",203,"parameters",SharedRuntime.map("whiteBalance",4)),()->false));
                state=map(slots.request("camera.slots.acknowledge",SharedRuntime.map("session","new-session","actionId",action.get("actionId"),"confirmedOnCamera",true),()->false));
                yes(Boolean.FALSE.equals(map(state.get("action")).get("parametersPending")));yes(reopened.parameterWrites==0&&reopened.presetWrites==0);
            }
            slots.close();
        }
        rejects(()->SharedSlotParameters.parse(SharedRuntime.map("whiteBalance",4.0)));
        rejects(()->SharedSlotParameters.parse(SharedRuntime.map("whiteBalance",4,"kelvin",5500)));
        rejects(()->SharedSlotParameters.parse(SharedRuntime.map("whiteBalance",0x8012)));
        rejects(()->SharedSlotParameters.parse(SharedRuntime.map("iso",100)));
        guardChecks();System.out.println("PASS "+checks+" slot parameter boundary checks");return checks;
    }
    private static void guardChecks()throws Exception{
        SharedSlotTransportGuard guard=new SharedSlotTransportGuard();guard.read(0x1001,0,new long[0]);guard.command(0x1002,0,new long[]{1});
        rejects(()->guard.read(0x1014,1,new long[]{0x5005}));rejects(()->guard.authorizeParameters(Collections.singletonMap(0x5005,le16(4))));
        byte[] target=profile();guard.send(0x90cd,1,target,new long[]{202,0});
        guard.observeReadback(0x90cc,target,new long[]{202,0});rejects(()->guard.authorizeParameters(Collections.singletonMap(0x5005,le16(4))));
        guard.observeWriteResponse(0x90cd,1,PtpContainer.response(0x2001,1));
        guard.observeReadback(0x90cc,target,new long[]{203,0});rejects(()->guard.authorizeParameters(Collections.singletonMap(0x5005,le16(4))));
        guard.observeReadback(0x90cc,new byte[36],new long[]{202,0});rejects(()->guard.authorizeParameters(Collections.singletonMap(0x5005,le16(4))));
        guard.observeReadback(0x90cc,target,new long[]{202,0});guard.read(0x1014,2,new long[]{0x5005});guard.authorizeParameters(Collections.singletonMap(0x5005,le16(4)));guard.send(0x1016,3,le16(4),new long[]{0x5005});yes(true);
        rejects(()->guard.send(0x1016,4,le16(4),new long[]{0x5005}));rejects(()->guard.send(0x1016,5,le16(4),new long[]{0x500f}));
    }
    @SuppressWarnings("unchecked") private static Map<String,Object> map(Object value){return (Map<String,Object>)value;}
    private static final class Peer implements SharedSlots.Transport {
        final Path root;final SharedSlotTransportGuard guard=new SharedSlotTransportGuard();final Map<Integer,byte[]> items=new LinkedHashMap<>();
        boolean open=true,evidenceBeforeParameterWrite;String mode="ok";int presetWrites,parameterWrites,propertyReads,whiteBalance=2;
        Peer(Path root){this.root=root;for(int i=201;i<=209;i++)items.put(i,i==201?profile():new byte[36]);}
        public boolean isOpen(){return open;}public void close(){open=false;}public void authorizeDeletion(int target)throws IOException{guard.authorizeDeletion(target);}public void authorizeParameters(Map<Integer,byte[]> values)throws IOException{guard.authorizeParameters(values);}
        public byte[] read(int op,long tx,long...p)throws IOException {
            guard.read(op,tx,p);byte[] value;
            if(op==0x1001)value=info(!mode.equals("unsupported"));else if(op==0x90cf)value=new byte[28];
            else if(op==0x90cc)value=items.get((int)p[0]).clone();
            else if(op==0x1014){propertyReads++;value=concat(le16((int)p[0]),le16(4),new byte[]{(byte)(mode.equals("readonly")?0:1)},le16(whiteBalance),le16(whiteBalance),new byte[]{2},le16(2),le16(2),le16(4));}
            else if(op==0x1015){propertyReads++;value=le16(mode.equals("mismatch")&&parameterWrites>0?2:whiteBalance);}else throw new IOException("Unexpected slot read");
            guard.observeReadback(op,value,p);return value;
        }
        public PtpContainer command(int op,long tx,long...p)throws IOException{guard.command(op,tx,p);return PtpContainer.response(0x2001,tx);}
        public PtpContainer send(int op,long tx,byte[] bytes,long...p)throws IOException {
            guard.send(op,tx,bytes,p);
            if(op==0x90cd){presetWrites++;items.put((int)p[0],bytes.clone());}
            else if(op==0x1016){
                parameterWrites++;Map<String,Object> saved=SharedJson.object(Files.readString(root.resolve("camera-actions/slots.json"),StandardCharsets.UTF_8));
                Map<String,Object> first=map(((List<?>)map(saved.get("parameterResult")).get("changes")).get(0));
                evidenceBeforeParameterWrite=Boolean.TRUE.equals(saved.get("presetVerified"))&&Boolean.TRUE.equals(saved.get("parametersPending"))&&((Number)first.get("before")).intValue()==2&&((Number)first.get("desired")).intValue()==4;
                if(mode.equals("rejected"))throw new PtpResponseException(0x2005,tx);
                whiteBalance=(bytes[0]&255)|((bytes[1]&255)<<8);if(mode.equals("lost"))throw new IOException("Lost ACK after changing device property");
            }else throw new IOException("Unexpected write");
            PtpContainer response=PtpContainer.response(0x2001,tx);guard.observeWriteResponse(op,tx,response);return response;
        }
        boolean otherSlotsIntact(){for(int i=203;i<=209;i++)if(!Arrays.equals(items.get(i),new byte[36]))return false;return Arrays.equals(items.get(201),profile());}
    }
    private static byte[] profile(){byte[] value=new byte[36];value[0]=1;value[2]='T';return value;}
    private static byte[] info(boolean parameters){return concat(le16(100),le32(10),le16(100),text(""),le16(0),array(parameters?new int[]{0x1001,0x1002,0x1003,0x90cc,0x90cd,0x90ce,0x90cf,0x1014,0x1015,0x1016}:new int[]{0x1001,0x1002,0x1003,0x90cc,0x90cd,0x90ce,0x90cf}),array(new int[0]),array(new int[]{0x5005}),array(new int[0]),array(new int[0]),text("NIKON CORPORATION"),text("NIKON TEST"),text("1"),text(""));}
    private static byte[] array(int[] values){ByteArrayOutputStream out=new ByteArrayOutputStream();out.writeBytes(le32(values.length));for(int value:values)out.writeBytes(le16(value));return out.toByteArray();}
    private static byte[] text(String value){ByteArrayOutputStream out=new ByteArrayOutputStream();if(value.isEmpty()){out.write(0);return out.toByteArray();}out.write(value.length()+1);for(char c:value.toCharArray())out.writeBytes(le16(c));out.writeBytes(le16(0));return out.toByteArray();}
    private static byte[] le16(long n){return new byte[]{(byte)n,(byte)(n>>>8)};}private static byte[] le32(long n){return new byte[]{(byte)n,(byte)(n>>>8),(byte)(n>>>16),(byte)(n>>>24)};}
    private static byte[] concat(byte[]...parts){ByteArrayOutputStream out=new ByteArrayOutputStream();for(byte[] part:parts)out.writeBytes(part);return out.toByteArray();}
    public static void main(String[] args)throws Exception{run(args.length==0?Files.createTempDirectory("slot-parameters-"):Paths.get(args[0]));}
}
