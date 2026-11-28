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
        yes(peer.operations.isEmpty());yes(Boolean.FALSE.equals(status(camera).get("inventoryReady")));
        camera.cancel("phase");yes(peer.open);yes(Boolean.TRUE.equals(status(camera).get("connected")));
        camera.closeTransport();yes(!peer.open);
        camera.disconnect();

        FakeClient timeout=new FakeClient();timeout.blockConnect=true;
        AtomicLong clock=new AtomicLong();failure.set(null);
        camera=new SharedCamera(root.getPath(),(h,p,f)->null,(c,f)->timeout,clock::get);
        worker=request(camera,payload,"deadline",()->false,v->{},failure);
        yes(timeout.entered.await(3,TimeUnit.SECONDS));clock.set(75_000_000_000L);worker.join(3000);
        yes(!worker.isAlive());yes(timeout.closed.get()>0);yes(failure.get() instanceof SocketTimeoutException);
        yes(failure.get().getMessage().contains("等待相机确认连接"));
        yes(Boolean.FALSE.equals(status(camera).get("connected")));

        FakeClient inventory=new FakeClient();inventory.blockConnect=true;
        AtomicBoolean cancelled=new AtomicBoolean();failure.set(null);
        camera=new SharedCamera(root.getPath(),(h,p,f)->null,(c,f)->inventory);
        worker=request(camera,payload,"inventory",cancelled::get,v->{},failure);
        yes(inventory.entered.await(3,TimeUnit.SECONDS));cancelled.set(true);worker.join(3000);
        yes(!worker.isAlive());yes(inventory.closed.get()>0);
        yes(failure.get() instanceof InterruptedIOException);
        yes(inventory.operations.isEmpty());
        yes(Boolean.FALSE.equals(status(camera).get("connected")));

        FakeClient first=new FakeClient(),second=new FakeClient();AtomicInteger created=new AtomicInteger();
        camera=new SharedCamera(root.getPath(),(h,p,f)->null,(c,f)->created.getAndIncrement()==0?first:second);
        camera.request("camera.connect",SharedJson.encode(payload),"old",()->false,v->{});
        Map<String,Object> connected=SharedJson.object(camera.request("camera.connect",SharedJson.encode(payload),"new",()->false,v->{}));
        yes(!first.open&&second.open);camera.cancel("old");yes(second.open);
        camera.cancel("");yes(second.open);
        camera.request("camera.page",SharedJson.encode(SharedRuntime.map("session",connected.get("session"),"offset",0,"limit",24)),"page",()->false,v->{});
        camera.cancel("new");yes(second.open);
        // A late cancellation only suppresses delivery; it cannot close a completed session.
        camera.cancel("page");yes(second.open);yes(Boolean.TRUE.equals(status(camera).get("connected")));
        camera.disconnect();
        retiredClockCannotCloseSuccess(root,payload);
        expiredCompletionCannotPublish(root,payload);
        timeoutCloseBlocksSameFacadeReuse(root,payload);
        fujiDefaultEndpoint(root);
        fujiSelectedWifiRelease(root);
        System.out.println("PASS "+checks+" camera connection checks; phase, whole-attempt deadline, blocked IO cancel and job ownership");
        return checks;
    }
    private static void fujiDefaultEndpoint(File root)throws Exception{
        AtomicReference<String> endpoint=new AtomicReference<>();FakeClient peer=new FakeClient();
        SharedCamera camera=new SharedCamera(root.getPath(),(host,port,fuji)->{yes(fuji);endpoint.set(host+":"+port);return null;},(connector,fuji)->peer);
        camera.request("camera.connect",SharedJson.encode(SharedRuntime.map("protocol","fujifilm","host","")),"fuji-empty",()->false,v->{});
        yes("192.168.0.1:55740".equals(endpoint.get()));yes(Boolean.TRUE.equals(status(camera).get("connected")));camera.disconnect();
        endpoint.set(null);final FakeClient explicit=new FakeClient();
        camera=new SharedCamera(root.getPath(),(host,port,fuji)->{endpoint.set(host+":"+port);return null;},(connector,fuji)->explicit);
        camera.request("camera.connect",SharedJson.encode(SharedRuntime.map("protocol","fujifilm","host","192.168.0.2","port",55741)),"fuji-explicit",()->false,v->{});
        yes("192.168.0.2:55741".equals(endpoint.get()));camera.disconnect();
        final FakeClient automatic=new FakeClient();
        camera=new SharedCamera(root.getPath(),(host,port,fuji)->{throw new IOException("Should use the bound hotspot route");},(connector,fuji)->automatic);
        camera.setFujifilmRoute(port->{yes(port==55740);return new SharedCamera.WifiEndpoint("192.168.186.1",null);});
        camera.request("camera.connect",SharedJson.encode(SharedRuntime.map("protocol","fujifilm","host","192.168.0.1","automaticHost",true)),"fuji-gateway",()->false,v->{});
        yes("192.168.186.1".equals(automatic.requestedHost));camera.disconnect();
    }
    private static void fujiSelectedWifiRelease(File root)throws Exception{
        FakeClient first=new FakeClient(),second=new FakeClient();second.blockConnect=true;
        AtomicInteger created=new AtomicInteger(),released=new AtomicInteger();
        SharedCamera camera=new SharedCamera(root.getPath(),
                (host,port,fuji)->{throw new IOException("The selected network must supply its own connector");},
                (connector,fuji)->created.getAndIncrement()==0?first:second);
        camera.setFujifilmWifiJoin((ssid,password,port,cancel)->{
            yes("FUJIFILM-X-T20".equals(ssid)&&password.isEmpty()&&port==55740);
            return new SharedCamera.WifiEndpoint("192.168.186.1",null,released::incrementAndGet);
        });
        Map<String,Object> params=SharedRuntime.map("protocol","fujifilm","wifiSsid","FUJIFILM-X-T20",
                "host","192.168.0.1","automaticHost",true);
        camera.request("camera.connect",SharedJson.encode(params),"explicit-first",()->false,v->{});
        yes("192.168.186.1".equals(first.requestedHost)&&first.open&&released.get()==0);
        camera.closeTransport();
        yes(!first.open&&released.get()==1);
        AtomicReference<Throwable> failure=new AtomicReference<>();
        Thread worker=request(camera,params,"explicit-cancel",()->false,v->{},failure);
        yes(second.entered.await(3,TimeUnit.SECONDS));
        camera.cancel("explicit-cancel");worker.join(3000);
        yes(failure.get() instanceof InterruptedIOException&&!worker.isAlive());
        yes(!second.open&&released.get()==2);
    }
    private static void retiredClockCannotCloseSuccess(File parent,Map<String,Object> payload)throws Exception{
        File root=new File(parent,"retired-clock");yes(root.mkdirs());PausedWatchdogClock clock=new PausedWatchdogClock();FakeClient peer=new FakeClient();peer.blockConnect=true;
        SharedCamera camera=new SharedCamera(root.getPath(),(h,p,f)->null,(c,f)->peer,clock);
        AtomicReference<Throwable> failure=new AtomicReference<>();Thread worker=request(camera,payload,"retired-clock",()->false,v->{},failure);
        yes(peer.entered.await(3,TimeUnit.SECONDS));yes(clock.entered.await(3,TimeUnit.SECONDS));peer.proceed.countDown();worker.join(3000);
        yes(!worker.isAlive());yes(failure.get()==null);yes(peer.open);yes(peer.closed.get()==0);
        clock.release.countDown();clock.owner.get().join(3000);yes(!clock.owner.get().isAlive());yes(!clock.holdExpired);
        yes(peer.open);yes(peer.closed.get()==0);yes(Boolean.TRUE.equals(status(camera).get("connected")));camera.disconnect();
    }
    private static void timeoutCloseBlocksSameFacadeReuse(File parent,Map<String,Object> payload)throws Exception{
        File root=new File(parent,"timeout-reuse");yes(root.mkdirs());PausedWatchdogClock clock=new PausedWatchdogClock();FakeClient peer=new FakeClient();peer.blockConnect=true;peer.blockClose=true;AtomicInteger creations=new AtomicInteger();
        SharedCamera camera=new SharedCamera(root.getPath(),(h,p,f)->null,(c,f)->{if(creations.getAndIncrement()>0){peer.blockConnect=false;peer.blockClose=false;}return peer;},clock);
        AtomicReference<Throwable> failure=new AtomicReference<>();Thread worker=request(camera,payload,"timeout-owner",()->false,v->{},failure);
        yes(peer.entered.await(3,TimeUnit.SECONDS));yes(clock.entered.await(3,TimeUnit.SECONDS));clock.release.countDown();yes(peer.closeEntered.await(3,TimeUnit.SECONDS));worker.join(3000);
        yes(!worker.isAlive());yes(failure.get() instanceof SocketTimeoutException);yes(clock.owner.get().isAlive());
        AtomicReference<Throwable> nextFailure=new AtomicReference<>();Thread next=request(camera,payload,"replacement",()->false,v->{},nextFailure);
        long until=System.nanoTime()+1_000_000_000L;while(next.isAlive()&&next.getState()!=Thread.State.TIMED_WAITING&&System.nanoTime()<until)Thread.sleep(1);
        yes(next.isAlive());yes(creations.get()==1);peer.closeRelease.countDown();clock.owner.get().join(3000);next.join(3000);
        yes(!clock.owner.get().isAlive()&&!next.isAlive());yes(nextFailure.get()==null);yes(creations.get()==2);yes(peer.open);yes(!peer.closeWaitExpired&&!clock.holdExpired);
        camera.cancel("timeout-owner");yes(peer.open);yes(Boolean.TRUE.equals(status(camera).get("connected")));camera.disconnect();
    }
    private static void expiredCompletionCannotPublish(File parent,Map<String,Object> payload)throws Exception{
        File root=new File(parent,"expired-completion");yes(root.mkdirs());PausedWatchdogClock clock=new PausedWatchdogClock();FakeClient peer=new FakeClient();peer.blockConnect=true;
        SharedCamera camera=new SharedCamera(root.getPath(),(h,p,f)->null,(c,f)->peer,clock);AtomicReference<Throwable> failure=new AtomicReference<>();Thread worker=request(camera,payload,"expired-completion",()->false,v->{},failure);
        yes(peer.entered.await(3,TimeUnit.SECONDS));yes(clock.entered.await(3,TimeUnit.SECONDS));clock.callerTime.set(75_000_000_000L);peer.proceed.countDown();worker.join(3000);
        yes(!worker.isAlive());yes(failure.get() instanceof SocketTimeoutException);yes(!peer.open);yes(Boolean.FALSE.equals(status(camera).get("connected")));
        int closes=peer.closed.get();clock.release.countDown();clock.owner.get().join(3000);yes(!clock.owner.get().isAlive());yes(peer.closed.get()==closes);camera.disconnect();
    }
    private static boolean awaitUninterruptibly(CountDownLatch latch,long nanos){
        boolean interrupted=false;long deadline=System.nanoTime()+nanos;
        try{while(true){long remaining=deadline-System.nanoTime();if(remaining<=0)return false;try{return latch.await(remaining,TimeUnit.NANOSECONDS);}catch(InterruptedException e){interrupted=true;}}}
        finally{if(interrupted)Thread.currentThread().interrupt();}
    }
    private static final class PausedWatchdogClock implements LongSupplier{
        final AtomicReference<Thread> owner=new AtomicReference<>();final AtomicLong callerTime=new AtomicLong();final CountDownLatch entered=new CountDownLatch(1),release=new CountDownLatch(1);volatile boolean holdExpired;
        public long getAsLong(){Thread current=Thread.currentThread();if(!current.getName().equals("camera-connect-deadline"))return callerTime.get();owner.compareAndSet(null,current);if(owner.get()!=current)return callerTime.get();entered.countDown();holdExpired=!awaitUninterruptibly(release,5_000_000_000L);return 75_000_000_000L;}
    }
    private static Map<String,Object> status(SharedCamera camera)throws IOException{return SharedJson.object(camera.request("camera.status","{}","status",()->false,v->{}));}
    private static Thread request(SharedCamera camera,Map<String,Object> payload,String job,BooleanSupplier cancel,DoubleConsumer progress,AtomicReference<Throwable> failure){
        Thread worker=new Thread(()->{try{camera.request("camera.connect",SharedJson.encode(payload),job,cancel,progress);}catch(Throwable error){failure.set(error);}},"connect-boundary");
        worker.setDaemon(true);worker.start();return worker;
    }
    private static final class FakeClient implements PhotoCameraClient {
        volatile boolean open;boolean blockConnect,blockInventory;volatile boolean blockClose,closeWaitExpired;
        Consumer<ConnectionStage> listener;
        final AtomicInteger closed=new AtomicInteger();
        final CountDownLatch entered=new CountDownLatch(1),proceed=new CountDownLatch(1);
        final CountDownLatch closeEntered=new CountDownLatch(1),closeRelease=new CountDownLatch(1);final AtomicBoolean closing=new AtomicBoolean();
        final List<Integer> operations=new ArrayList<>();
        String requestedHost;
        public void setConnectionStageListener(Consumer<ConnectionStage> value){listener=value;}
        public byte[] connect(String host,int port,byte[] guid,String name)throws IOException{
            requestedHost=host;
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
        public void abortProtocol(IOException error){close();}public void close(){boolean hold=blockClose&&closing.compareAndSet(false,true);open=false;closed.incrementAndGet();proceed.countDown();if(hold){closeEntered.countDown();closeWaitExpired=!awaitUninterruptibly(closeRelease,5_000_000_000L);}open=false;}
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
    public static void main(String[] args)throws Exception{Path root=args.length==0?Files.createTempDirectory("huevia-camera-connect-"):Paths.get(args[0]);Files.createDirectories(root);run(root);}
}
