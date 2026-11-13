package cc.huevia.shared;

import cc.huevia.album.PhotoCameraClient;
import cc.huevia.library.SharedJson;
import cc.huevia.ptp.*;
import java.io.*;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;
import java.util.function.*;

/** Read-only idle maintenance uses the same actor and exact cancellation ownership. */
public final class CameraMaintenanceBoundaryTest {
    private static int checks;
    private static void yes(boolean value){checks++;if(!value)throw new AssertionError("Camera maintenance "+checks);}
    private static Map<String,Object> call(SharedCamera camera,String operation,Map<String,Object> payload,String job)throws IOException {
        return SharedJson.object(camera.request(operation,SharedJson.encode(payload),job,()->false,value->{}));
    }
    static int run(Path root)throws Exception {
        checks=0;Files.createDirectories(root);AtomicReference<Peer> next=new AtomicReference<>(new Peer());
        SharedCamera camera=new SharedCamera(root.toString(),(h,p,f)->(a,b,t)->{throw new IOException("No real network in fixture");},(connector,fuji)->next.get());
        AtomicInteger notifications=new AtomicInteger();
        camera.setMaintenanceObserver(()->{notifications.incrementAndGet();camera.setMaintenanceAllowed(camera.maintenanceActive());});
        yes(!camera.maintenanceActive());yes(!camera.maintain(()->false));
        // Observers may report protection synchronously; repeated allowed values must not recurse.
        camera.setMaintenanceObserver(notifications::incrementAndGet);
        camera.setMaintenanceAllowed(true);yes(!camera.maintenanceActive());
        Peer first=next.get();Map<String,Object> connected=connect(camera,"first");yes(camera.maintenanceActive());
        camera.setMaintenanceAllowed(false);yes(!camera.maintenanceActive());yes(first.isOpen());
        int before=first.reads.get();yes(camera.maintain(()->false));yes(first.reads.get()==before+1);yes(first.transfers.get()==0);yes(first.closed.get()==0);
        first.response=0x2019;try{camera.maintain(()->false);throw new AssertionError("Expected busy response");}catch(PtpResponseException expected){yes(first.isOpen());}first.response=0;
        first.block=true;AtomicReference<Throwable> failed=new AtomicReference<>();Object firstSession=connected.get("session");
        Thread work=new Thread(()->{try{call(camera,"camera.keepAlive",SharedRuntime.map("session",firstSession),"busy-read");}catch(Throwable error){failed.set(error);}});
        work.start();yes(first.entered.await(2,TimeUnit.SECONDS));before=first.reads.get();yes(!camera.maintain(()->false));yes(first.reads.get()==before);
        first.release.countDown();work.join(2000);yes(!work.isAlive());yes(failed.get()==null);first.block=false;
        // A real scheduled blocked read is cancelled immediately when foreground/protection ends.
        Peer held=new Peer();next.set(held);connected=connect(camera,"held");held.block=true;camera.setMaintenanceAllowed(true);
        yes(held.entered.await(5,TimeUnit.SECONDS));String retiredJob=camera.maintenanceJob();yes(!retiredJob.isEmpty());
        camera.setMaintenanceAllowed(false);yes(!camera.maintenanceActive());yes(held.closed.get()==1);
        Peer replacement=new Peer();next.set(replacement);connect(camera,"replacement");
        camera.cancelMaintenance(retiredJob);camera.cancel(retiredJob);yes(replacement.isOpen());yes(replacement.closed.get()==0);
        camera.setMaintenanceAllowed(true);camera.disconnect();yes(!camera.maintenanceActive());yes(!replacement.isOpen());
        Peer preparing=new Peer();preparing.holdConnect=true;next.set(preparing);failed.set(null);
        Thread opening=new Thread(()->{try{connect(camera,"preparing");}catch(Throwable error){failed.set(error);}});opening.start();
        yes(preparing.connectEntered.await(2,TimeUnit.SECONDS));yes(camera.maintenanceActive());yes(!camera.maintenanceConnection());yes(!camera.maintain(()->false));yes(preparing.reads.get()==0);
        preparing.connectRelease.countDown();opening.join(2000);yes(!opening.isAlive());yes(failed.get()==null);yes(camera.maintenanceActive());camera.disconnect();yes(!camera.maintenanceActive());
        slotReads(root.resolve("slots"));yes(notifications.get()>0);
        System.out.println("PASS "+checks+" camera maintenance boundary checks");return checks;
    }
    private static Map<String,Object> connect(SharedCamera camera,String job)throws IOException {
        return call(camera,"camera.connect",SharedRuntime.map("host","192.168.1.1","port",15740,"protocol","nikon"),job);
    }
    private static void slotReads(Path root)throws Exception {
        Files.createDirectories(root);Slots peer=new Slots();SharedSlots slots=new SharedSlots(root.toFile());
        Map<String,Object> opened=cast(slots.open(peer,"slot-session","fixture",()->false));String snapshot=(String)opened.get("snapshot");
        int reads=peer.reads;slots.keepAlive("slot-session",()->false);yes(peer.reads==reads+1);yes(peer.lastTarget==1);yes(peer.writes==0);
        Map<String,Object> after=cast(slots.request("camera.slots.status",SharedRuntime.map("session","slot-session"),()->false));yes(snapshot.equals(after.get("snapshot")));yes(Boolean.FALSE.equals(after.get("consumed")));
        for(int temporary:new int[]{0x2002,0x2019}){peer.response=temporary;slots.keepAlive("slot-session",()->false);yes(peer.open);}
        peer.wrongTransaction=true;try{slots.keepAlive("slot-session",()->false);throw new AssertionError("Mismatched response accepted");}catch(PtpProtocolException expected){yes(true);}
        peer.response=0;peer.wrongTransaction=false;reads=peer.reads;try{slots.keepAlive("old-session",()->false);throw new AssertionError("Stale session accepted");}catch(IOException expected){yes(peer.reads==reads);}
        try{slots.keepAlive("slot-session",()->true);throw new AssertionError("Cancelled tick accepted");}catch(InterruptedIOException expected){yes(peer.reads==reads);}
        peer.ioFailure=true;try{slots.keepAlive("slot-session",()->false);throw new AssertionError("I/O failure hidden");}catch(IOException expected){yes(!peer.open);}
        yes(peer.writes==0);slots.close();
    }
    @SuppressWarnings("unchecked") private static Map<String,Object> cast(Object value){return (Map<String,Object>)value;}
    private static final class Peer implements PhotoCameraClient {
        final AtomicInteger reads=new AtomicInteger(),closed=new AtomicInteger(),transfers=new AtomicInteger();
        final CountDownLatch entered=new CountDownLatch(1),release=new CountDownLatch(1);
        final CountDownLatch connectEntered=new CountDownLatch(1),connectRelease=new CountDownLatch(1);
        volatile boolean open,block,holdConnect;volatile int response;
        public byte[] connect(String h,int p,byte[] g,String n)throws IOException{if(holdConnect){connectEntered.countDown();try{if(!connectRelease.await(4,TimeUnit.SECONDS))throw new IOException("Connect fixture timed out");}catch(InterruptedException e){Thread.currentThread().interrupt();throw new InterruptedIOException();}}open=true;return info();}
        public byte[] getData(int op,int max,long...p)throws IOException{if(op==0x1004)return le32(0);throw new IOException("Unexpected photo operation");}
        public byte[] readAlbumDeviceInfo()throws IOException{
            reads.incrementAndGet();if(block){entered.countDown();try{if(!release.await(4,TimeUnit.SECONDS))throw new IOException("Read fixture timed out");}catch(InterruptedException e){Thread.currentThread().interrupt();throw new InterruptedIOException();}}
            if(!isOpen())throw new IOException("Closed read");if(response!=0)throw new PtpResponseException(response,1);return info();
        }
        public boolean isOpen(){return open;}public boolean isProtocolUnconfirmed(){return false;}public String closeReason(){return "";}public String connectedHost(){return "192.168.1.1";}public int connectedPort(){return 15740;}public String cameraIdentity(){return "fixture";}
        public void setConnectionStageListener(Consumer<ConnectionStage> listener){}public void setOnClosed(Runnable listener){}public void setOnObjectAdded(LongConsumer listener){}
        public byte[] getLargeThumbnail(long handle)throws IOException{throw new IOException("Unexpected thumbnail");}
        public long readTo(int op,OutputStream out,long max,long expected,Progress progress,long...p)throws IOException{transfers.incrementAndGet();throw new IOException("Unexpected original download");}
        public void abortProtocol(IOException error){close();}public void close(){closed.incrementAndGet();open=false;release.countDown();}
    }
    private static final class Slots implements SharedSlots.Transport {
        final SharedSlotTransportGuard guard=new SharedSlotTransportGuard();boolean open=true,wrongTransaction,ioFailure;int reads,writes,response,lastTarget;
        public boolean isOpen(){return open;}public void close(){open=false;}public void authorizeDeletion(int target)throws IOException{guard.authorizeDeletion(target);}
        public byte[] read(int op,long tx,long...p)throws IOException {
            guard.read(op,tx,p);reads++;if(op==0x1001)return info();if(op==0x90cf)return new byte[28];
            if(op==0x90cc){lastTarget=(int)p[0];if(ioFailure)throw new IOException("Lost event/command stream");if(response!=0)throw new PtpResponseException(response,wrongTransaction?tx+1:tx);return profile();}throw new IOException("Unexpected operation");
        }
        public PtpContainer command(int op,long tx,long...p)throws IOException{guard.command(op,tx,p);return PtpContainer.response(0x2001,tx);}
        public PtpContainer send(int op,long tx,byte[] b,long...p)throws IOException{writes++;throw new IOException("Heartbeat must never write");}
    }
    private static byte[] profile(){byte[] bytes=new byte[36];bytes[0]=1;bytes[2]='T';return bytes;}
    private static byte[] info(){return concat(le16(100),le32(10),le16(100),text(""),le16(0),array(new int[]{0x1001,0x1002,0x1003,0x1004,0x1007,0x1008,0x1009,0x90cc,0x90cd,0x90ce,0x90cf}),array(new int[0]),array(new int[0]),array(new int[0]),array(new int[0]),text("NIKON CORPORATION"),text("NIKON TEST"),text("1"),text(""));}
    private static byte[] array(int[] values){ByteArrayOutputStream out=new ByteArrayOutputStream();out.writeBytes(le32(values.length));for(int value:values)out.writeBytes(le16(value));return out.toByteArray();}
    private static byte[] text(String s){ByteArrayOutputStream out=new ByteArrayOutputStream();if(s.isEmpty()){out.write(0);return out.toByteArray();}out.write(s.length()+1);for(char c:s.toCharArray())out.writeBytes(le16(c));out.writeBytes(le16(0));return out.toByteArray();}
    private static byte[] le16(long n){return new byte[]{(byte)n,(byte)(n>>>8)};}private static byte[] le32(long n){return new byte[]{(byte)n,(byte)(n>>>8),(byte)(n>>>16),(byte)(n>>>24)};}
    private static byte[] concat(byte[]...parts){ByteArrayOutputStream out=new ByteArrayOutputStream();for(byte[] part:parts)out.writeBytes(part);return out.toByteArray();}
    public static void main(String[] args)throws Exception{run(args.length==0?Files.createTempDirectory("camera-maintenance-"):Paths.get(args[0]));}
}
