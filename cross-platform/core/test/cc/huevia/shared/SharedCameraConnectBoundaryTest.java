package cc.huevia.shared;

import cc.huevia.album.PhotoCameraClient;
import cc.huevia.library.SharedJson;
import java.io.*;
import java.net.SocketTimeoutException;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;
import java.util.function.*;

/** Real blocked transports are released by cancellation/deadline, not fake success. */
final class SharedCameraConnectBoundaryTest {
    private static int checks;
    private static void yes(boolean value){checks++;if(!value)throw new AssertionError("Connect budget "+checks);}
    static int run(Path temporary)throws Exception{
        checks=0;File root=temporary.resolve("connection-deadline").toFile();yes(root.mkdirs());
        Map<String,Object> payload=SharedRuntime.map("host","192.168.1.1","port",15740,"protocol","nikon");
        FakeClient peer=new FakeClient();peer.blockConnect=true;
        List<Double> phases=Collections.synchronizedList(new ArrayList<>());
        AtomicReference<Throwable> failure=new AtomicReference<>();
        SharedCamera camera=new SharedCamera(root.getPath(),(h,p,f)->null,(c,f)->peer);
        Thread worker=request(camera,payload,"phase",()->false,phases::add,failure);
        yes(peer.entered.await(3,TimeUnit.SECONDS));
        long until=System.nanoTime()+3_000_000_000L;
        while(!phases.contains(.2)&&System.nanoTime()<until)Thread.sleep(10);
        yes(phases.contains(.2));peer.proceed.countDown();worker.join(3000);
        yes(!worker.isAlive()&&failure.get()==null);yes(phases.contains(1.0));
        yes(peer.operations.equals(Collections.singletonList(0x1004)));
        camera.cancel("phase");yes(!peer.open);yes(Boolean.FALSE.equals(status(camera).get("connected")));
        camera.disconnect();

        FakeClient timeout=new FakeClient();timeout.blockConnect=true;
        AtomicLong clock=new AtomicLong();failure.set(null);
        camera=new SharedCamera(root.getPath(),(h,p,f)->null,(c,f)->timeout,clock::get);
        worker=request(camera,payload,"deadline",()->false,v->{},failure);
        yes(timeout.entered.await(3,TimeUnit.SECONDS));clock.set(75_000_000_000L);worker.join(3000);
        yes(!worker.isAlive());yes(timeout.closed.get()>0);yes(failure.get() instanceof SocketTimeoutException);
        yes(failure.get().getMessage().contains("等待相机确认连接"));
        yes(Boolean.FALSE.equals(status(camera).get("connected")));

        FakeClient inventory=new FakeClient();inventory.blockInventory=true;
        AtomicBoolean cancelled=new AtomicBoolean();failure.set(null);
        camera=new SharedCamera(root.getPath(),(h,p,f)->null,(c,f)->inventory);
        worker=request(camera,payload,"inventory",cancelled::get,v->{},failure);
        yes(inventory.entered.await(3,TimeUnit.SECONDS));cancelled.set(true);worker.join(3000);
        yes(!worker.isAlive());yes(inventory.closed.get()>0);
        yes(failure.get() instanceof InterruptedIOException);
        yes(inventory.operations.equals(Collections.singletonList(0x1004)));
        yes(Boolean.FALSE.equals(status(camera).get("connected")));

        FakeClient first=new FakeClient(),second=new FakeClient();AtomicInteger created=new AtomicInteger();
        camera=new SharedCamera(root.getPath(),(h,p,f)->null,(c,f)->created.getAndIncrement()==0?first:second);
        camera.request("camera.connect",SharedJson.encode(payload),"old",()->false,v->{});
        Map<String,Object> connected=SharedJson.object(camera.request("camera.connect",SharedJson.encode(payload),"new",()->false,v->{}));
        yes(!first.open&&second.open);camera.cancel("old");yes(second.open);
        camera.cancel("");yes(second.open);
        camera.request("camera.page",SharedJson.encode(SharedRuntime.map("session",connected.get("session"),"offset",0,"limit",24)),"page",()->false,v->{});
        camera.cancel("new");yes(second.open);
        // Page cancellation can also race completion delivery, after activeJob is cleared.
        camera.cancel("page");yes(!second.open);yes(Boolean.FALSE.equals(status(camera).get("connected")));
        camera.disconnect();
        System.out.println("PASS "+checks+" camera connection checks; phase, whole-attempt deadline, blocked IO cancel and job ownership");
        return checks;
    }
    private static Map<String,Object> status(SharedCamera camera)throws IOException{return SharedJson.object(camera.request("camera.status","{}","status",()->false,v->{}));}
    private static Thread request(SharedCamera camera,Map<String,Object> payload,String job,BooleanSupplier cancel,DoubleConsumer progress,AtomicReference<Throwable> failure){
        Thread worker=new Thread(()->{try{camera.request("camera.connect",SharedJson.encode(payload),job,cancel,progress);}catch(Throwable error){failure.set(error);}},"connect-boundary");
        worker.setDaemon(true);worker.start();return worker;
    }
    private static final class FakeClient implements PhotoCameraClient {
        volatile boolean open;boolean blockConnect,blockInventory;
        Consumer<ConnectionStage> listener;
        final AtomicInteger closed=new AtomicInteger();
        final CountDownLatch entered=new CountDownLatch(1),proceed=new CountDownLatch(1);
        final List<Integer> operations=new ArrayList<>();
        public void setConnectionStageListener(Consumer<ConnectionStage> value){listener=value;}
        public byte[] connect(String host,int port,byte[] guid,String name)throws IOException{
            open=true;if(listener!=null){listener.accept(ConnectionStage.CONNECTING_CAMERA);listener.accept(ConnectionStage.WAITING_CONFIRMATION);}
            if(blockConnect)await();if(!open)throw new IOException("Closed during handshake");
            if(listener!=null)listener.accept(ConnectionStage.CONNECTING_CAMERA);return info();
        }
        void await()throws IOException{entered.countDown();try{if(!proceed.await(3,TimeUnit.SECONDS))throw new IOException("Fixture did not unblock");}catch(InterruptedException e){Thread.currentThread().interrupt();throw new InterruptedIOException();}if(!open)throw new IOException("Transport closed");}
        public byte[] getData(int op,int limit,long...p)throws IOException{operations.add(op);if(op!=0x1004)throw new IOException("Unexpected PTP operation");if(blockInventory)await();return le32(0);}
        public boolean isOpen(){return open;}public boolean isProtocolUnconfirmed(){return false;}public String closeReason(){return "";}public String connectedHost(){return "192.168.1.1";}public int connectedPort(){return 15740;}public String cameraIdentity(){return "fixture";}
        public void setOnClosed(Runnable listener){}public void setOnObjectAdded(LongConsumer listener){}
        public byte[] readAlbumDeviceInfo(){return info();}
        public byte[] getLargeThumbnail(long handle)throws IOException{throw new IOException("No thumbnail request during connect");}
        public long readTo(int op,OutputStream out,long max,long expected,Progress progress,long...p)throws IOException{throw new IOException("No source download");}
        public void abortProtocol(IOException error){close();}public void close(){open=false;closed.incrementAndGet();proceed.countDown();}
    }
    private static byte[] info(){
        int[] operations={0x1001,0x1002,0x1003,0x1004,0x1007,0x1008,0x1009};ByteArrayOutputStream ops=new ByteArrayOutputStream();put(ops,le32(operations.length));for(int op:operations)put(ops,le16(op));
        return concat(le16(100),le32(10),le16(100),string("Fixture"),le16(0),ops.toByteArray(),le32(0),le32(0),le32(0),le32(0),string("NIKON CORPORATION"),string("Z 6_2"),string("1"),string(""));
    }
    private static byte[] string(String text){return text.isEmpty()?new byte[]{0}:concat(new byte[]{(byte)(text.length()+1)},(text+'\0').getBytes(StandardCharsets.UTF_16LE));}
    private static byte[] le16(long n){return new byte[]{(byte)n,(byte)(n>>>8)};}
    private static byte[] le32(long n){return new byte[]{(byte)n,(byte)(n>>>8),(byte)(n>>>16),(byte)(n>>>24)};}
    private static void put(ByteArrayOutputStream out,byte[] bytes){out.write(bytes,0,bytes.length);}
    private static byte[] concat(byte[]...parts){ByteArrayOutputStream out=new ByteArrayOutputStream();for(byte[] part:parts)put(out,part);return out.toByteArray();}
    public static void main(String[] args)throws Exception{run(Files.createTempDirectory("huevia-camera-connect-"));}
}
