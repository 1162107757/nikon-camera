package cc.huevia.usb;

import android.hardware.usb.*;
import android.os.Looper;
import cc.huevia.ptp.*;
import java.io.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicReference;

/** Real production USB framing and wrapper lifecycle, with a scripted USB peer. */
public final class UsbDeviceInfo164Test {
    private static int checks;
    public static void main(String[] args)throws Exception{
        for(String model:new String[]{"Z 7_2","Z7II","NIKON Z 7II","NIKON D850"}){
            Camera camera=new Camera();camera.model=model;
            UsbPictureControlProbe.Result result=new UsbPictureControlProbe().probeDeviceInfo(camera.device,camera.manager);
            check(result.completed&&result.deviceInfoOnly&&result.deviceInfoRead,"ordinary identification completed "+model);
            check(result.model.equals(model)&&result.manufacturer.equals("Nikon Corporation"),"actual identity retained");
            check(!result.sessionOpened&&!result.sessionClosed&&!result.sessionRetained&&!result.capabilityRead&&!result.capabilityParsed&&result.items.isEmpty(),"connection makes no preset assertion");
            check(result.operations.length==1&&result.operations[0]==0x1001,"camera need not advertise any preset operation");
            check(PtpDeviceInfo.parseRedacted(camera.info()).serialNumber().isEmpty(),"standard device-info parser redacts serial before retaining identity");
            ordinaryOnly(camera);cleaned(camera);
        }
        Camera nonNikon=new Camera();nonNikon.maker="Canon";UsbPictureControlProbe.ProbeException wrong=failed(nonNikon);
        check(wrong.partialResult.deviceInfoRead&&!wrong.partialResult.completed&&wrong.getMessage().contains("Canon")&&wrong.getMessage().contains(nonNikon.model),"identity refusal reports actual device");ordinaryOnly(nonNikon);cleaned(nonNikon);
        Camera empty=new Camera();empty.model="";check(!failed(empty).partialResult.completed,"blank model cannot become connected");ordinaryOnly(empty);cleaned(empty);
        for(String fault:new String[]{"truncated-dataset","trailing-dataset","wrong-transaction","missing-response","busy"}){
            Camera camera=new Camera();camera.fault=fault;UsbPictureControlProbe.ProbeException error=failed(camera);
            check(!error.partialResult.completed&&error.partialResult.deviceInfoOnly,"wire or dataset failure cannot become connected "+fault);
            check(error.getMessage().contains("GetDeviceInfo"),"standard operation context retained "+fault);
            if(fault.equals("busy"))check(Integer.valueOf(0x2019).equals(error.responseCode)&&error.partialResult.failedTransactionId==0,"standard PTP response context");
            ordinaryOnly(camera);cleaned(camera);
        }
        Camera closeFailure=new Camera();closeFailure.failClose=true;check(!failed(closeFailure).partialResult.completed,"USB release failure cannot become connected");ordinaryOnly(closeFailure);cleaned(closeFailure);
        Camera claimFailure=new Camera();claimFailure.allowClaim=false;check(!failed(claimFailure).partialResult.completed,"unclaimed interface cannot become connected");check(claimFailure.commands.isEmpty()&&claimFailure.closes==1&&claimFailure.releases==0,"claim failure closes without I/O");
        UsbPictureControlProbe preClosed=new UsbPictureControlProbe();preClosed.close();Camera unopened=new Camera();boolean rejected=false;try{preClosed.probeDeviceInfo(unopened.device,unopened.manager);}catch(IOException expected){rejected=true;}check(rejected&&unopened.claims==0,"pre-cancelled probe performs no USB I/O");
        Camera mainThread=new Camera();Looper.setMainThreadForTest(true);rejected=false;try{new UsbPictureControlProbe().probeDeviceInfo(mainThread.device,mainThread.manager);}catch(IllegalStateException expected){rejected=true;}finally{Looper.setMainThreadForTest(false);}check(rejected&&mainThread.claims==0,"main-thread USB I/O rejected");
        Camera blocked=new Camera();blocked.blockRead=true;UsbPictureControlProbe probe=new UsbPictureControlProbe();AtomicReference<Throwable> failure=new AtomicReference<>();Thread worker=new Thread(()->{try{probe.probeDeviceInfo(blocked.device,blocked.manager);}catch(Throwable error){failure.set(error);}});worker.start();check(blocked.reading.await(2,TimeUnit.SECONDS)&&probe.isProbingDevice(blocked.device),"active ordinary probe tracked for detach/cancel");
        rejected=false;try{probe.probeDeviceInfo(blocked.device,blocked.manager);}catch(IllegalStateException expected){rejected=true;}check(rejected,"concurrent reuse rejected");probe.close();worker.join(3000);check(!worker.isAlive()&&failure.get() instanceof UsbPictureControlProbe.ProbeException&&!probe.isProbingDevice(blocked.device),"cancel unblocks I/O and releases lifecycle");ordinaryOnly(blocked);cleaned(blocked);
        Camera policy=new Camera();PtpUsbTransport transport=new PtpUsbTransport(policy.device,policy.manager,new ArrayList<>(),PtpUsbTransport.Mode.DEVICE_INFO_ONLY);
        for(int operation:new int[]{0x90ca,0x90cf,0x90cc,0x1004,0x1009}){denied(()->transport.getData(operation,0));}
        denied(()->transport.getData(0x1001,1));denied(()->transport.getData(0x1001,0,1));denied(()->transport.command(0x1002,0,1));denied(()->transport.command(0x1003,1));denied(()->transport.sendData(0x90cd,1,new byte[36],201,0));
        check(policy.commands.isEmpty(),"transport policy refuses all non-identification operations before I/O");check(PtpDeviceInfo.parseRedacted(transport.getData(0x1001,0)).model().equals(policy.model),"policy refusals leave permitted identification usable");transport.close();ordinaryOnly(policy);cleaned(policy);
        check(UsbPictureControlProbe.cameraIdentity("Nikon","NIKON Z 7II").equals("NIKON Z 7II"),"identity avoids duplicated manufacturer prefix");
        check(UsbPictureControlProbe.cameraIdentity("Nikon\nCorporation","Z 7_2").equals("Nikon Corporation · Z 7_2"),"visible identity uses actual bounded single-line fields");
        System.out.println("PASS UsbDeviceInfo164Test "+checks+" checks; standard1001-only, no session/vendor/slot/write, cleanup/cancel/failures and Z7II aliases.");
    }
    private interface Work{void run()throws Exception;}
    private static void denied(Work work)throws Exception{boolean failed=false;try{work.run();}catch(IOException expected){failed=true;}check(failed,"forbidden transport operation rejected");}
    private static UsbPictureControlProbe.ProbeException failed(Camera camera)throws Exception{try{new UsbPictureControlProbe().probeDeviceInfo(camera.device,camera.manager);}catch(UsbPictureControlProbe.ProbeException expected){return expected;}throw new AssertionError("Expected failed ordinary identification");}
    private static void ordinaryOnly(Camera camera){check(camera.commands.size()==1&&camera.commands.get(0).code()==0x1001&&camera.commands.get(0).transactionId()==0&&camera.commands.get(0).parameters().length==0,"exactly standard GetDeviceInfo txn0 only");}
    private static void cleaned(Camera camera){check(camera.claims==1&&camera.releases==1&&camera.closes==1,"claimed interface and connection released once");}
    private static void check(boolean pass,String name){checks++;if(!pass)throw new AssertionError(name);}
    private static final class Camera extends UsbDeviceConnection {
        final UsbDevice device=new UsbDevice();final UsbManager manager=new UsbManager(device,this);final List<PtpContainer> commands=new ArrayList<>();
        final CountDownLatch reading=new CountDownLatch(1),closedSignal=new CountDownLatch(1);
        String maker="Nikon Corporation",model="Z 7_2",fault="";boolean allowClaim=true,failClose,blockRead;volatile boolean closed;int claims,releases,closes;byte[] incoming=new byte[0];int offset;
        @Override public boolean claimInterface(UsbInterface intf,boolean force){check(!force,"USB claim is unforced");claims++;return allowClaim;}
        @Override public boolean releaseInterface(UsbInterface intf){releases++;return true;}
        @Override public void close(){closed=true;closes++;closedSignal.countDown();if(failClose)throw new IllegalStateException("scripted USB close failure");}
        @Override public int bulkTransfer(UsbEndpoint endpoint,byte[] bytes,int length,int timeout){return bulkTransfer(endpoint,bytes,0,length,timeout);}
        @Override public int bulkTransfer(UsbEndpoint endpoint,byte[] bytes,int start,int length,int timeout){
            if(closed)return -1;check(timeout>0,"bounded USB transfer timeout");
            if(endpoint.getDirection()==128){if(blockRead){reading.countDown();try{closedSignal.await(2,TimeUnit.SECONDS);}catch(InterruptedException cancelled){Thread.currentThread().interrupt();}return -1;}int count=Math.min(Math.min(length,17),incoming.length-offset);if(count==0)return -1;System.arraycopy(incoming,offset,bytes,start,count);offset+=count;return count;}
            try{PtpContainer command=new PtpContainerReader(new ByteArrayInputStream(Arrays.copyOfRange(bytes,start,start+length)),1024).read();commands.add(command);if(command.code()!=0x1001)throw new AssertionError("Unexpected operation "+command.code());
                byte[] data=info();if(fault.equals("truncated-dataset"))data=Arrays.copyOf(data,data.length-3);if(fault.equals("trailing-dataset"))data=Arrays.copyOf(data,data.length+1);
                ByteArrayOutputStream response=new ByteArrayOutputStream();if(!fault.equals("busy"))response.write(PtpContainer.data(0x1001,command.transactionId(),data).toBytes());
                if(!fault.equals("missing-response"))response.write(PtpContainer.response(fault.equals("busy")?0x2019:0x2001,command.transactionId()+(fault.equals("wrong-transaction")?1:0)).toBytes());incoming=response.toByteArray();offset=0;return length;
            }catch(IOException error){throw new AssertionError(error);}
        }
        byte[] info(){Writer w=new Writer().u16(100).u32(10).u16(100).string("").u16(0).u32(1).u16(0x1001);for(int i=0;i<4;i++)w.u32(0);return w.string(maker).string(model).string("QA164").string("PRIVATE-SERIAL-164").bytes();}
    }
    private static final class Writer {
        private final ByteArrayOutputStream out=new ByteArrayOutputStream();Writer u16(int v){out.write(v);out.write(v>>8);return this;}Writer u32(long v){for(int i=0;i<4;i++)out.write((int)(v>>(8*i)));return this;}
        Writer string(String value){out.write(value.length()+1);for(char c:value.toCharArray())u16(c);u16(0);return this;}byte[] bytes(){return out.toByteArray();}
    }
}
