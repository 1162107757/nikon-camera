package cc.huevia.shared;

import cc.huevia.album.PtpIpClient;
import cc.huevia.album.PhotoCameraClient;
import cc.huevia.library.SharedJson;
import cc.huevia.ptp.PtpResponseException;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicReference;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicBoolean;

/** Runs the real PTP/IP state machine against bounded synthetic socket bytes. */
public final class CameraSessionBoundaryTest {
    private static int checks;
    private static void yes(boolean value){checks++;if(!value)throw new AssertionError("Camera ownership "+checks);}
    private interface Action{void run()throws Exception;}
    private static Throwable rejects(Action action)throws Exception{try{action.run();throw new AssertionError("Expected camera refusal");}catch(IOException expected){checks++;return expected;}}
    public static void main(String[] args)throws Exception{Path root=Paths.get(args[0]);Files.createDirectories(root);run(root);}
    static int run(Path temporary)throws Exception {
        checks=0;File root=temporary.resolve("camera-session-ownership").toFile();yes(root.mkdirs());
        // A correctly constructed standalone slot client must reach the connector.
        int[] connects={0};IOException sentinel=new IOException("Expected connector fixture refusal");
        Throwable failure=rejects(()->SharedSlots.wifi((h,p,t)->{connects[0]++;throw sentinel;},"192.168.1.1",15740,new byte[16]));
        yes(failure==sentinel);yes(connects[0]==1);

        Peer peer=new Peer();SharedCamera camera=peer.camera(root);Map<String,Object> connection=connect(camera);
        String photoSession=(String)connection.get("session");
        yes(Boolean.TRUE.equals(connection.get("connected")));yes(connection.get("mode").equals("photos"));
        yes(Boolean.TRUE.equals(connection.get("photoConnected")));yes(Boolean.FALSE.equals(connection.get("slotsConnected")));
        yes(Boolean.FALSE.equals(connection.get("inventoryReady")));yes(!peer.operations.contains(0x1004)&&!peer.operations.contains(0x1007));
        yes(peer.sockets.size()==2);yes(peer.count(0x1002)==1);
        camera.cancel("connect");yes(Boolean.TRUE.equals(status(camera).get("connected")));
        Map<String,Object> opened=call(camera,"camera.slots.open",scope(photoSession),"slots-open");String slotSession=(String)opened.get("session");
        yes(((List<?>)opened.get("items")).size()==9);yes(!slotSession.equals(photoSession));
        Map<String,Object> slotStatus=status(camera);yes(slotStatus.get("mode").equals("slots"));yes(slotStatus.get("session").equals(slotSession));
        yes(Boolean.TRUE.equals(slotStatus.get("connected")));yes(Boolean.FALSE.equals(slotStatus.get("photoConnected")));yes(Boolean.TRUE.equals(slotStatus.get("slotsConnected")));
        yes(Boolean.FALSE.equals(slotStatus.get("inventoryReady")));yes(peer.sockets.size()==2&&peer.count(0x1002)==1&&peer.count(0x1003)==0);yes(peer.closed()==0);
        int reads=peer.operations.size();Map<String,Object> again=call(camera,"camera.slots.open",scope(slotSession),"slots-again");
        yes(again.get("session").equals(slotSession));yes(reads==peer.operations.size());
        camera.cancel("connect");camera.cancel("slots-open");yes(Boolean.TRUE.equals(status(camera).get("slotsConnected")));
        SharedCamera openedCamera=camera;rejects(()->call(openedCamera,"camera.slots.close",scope("stale"),"stale-close"));yes(peer.closed()==0);
        call(camera,"camera.slots.close",scope(slotSession),"slots-close");Map<String,Object> restored=status(camera);
        yes(restored.get("mode").equals("photos"));yes(restored.get("session").equals(photoSession));yes(Boolean.TRUE.equals(restored.get("photoConnected")));yes(Boolean.FALSE.equals(restored.get("inventoryReady")));
        yes(peer.closed()==0&&peer.count(0x1002)==1&&peer.count(0x1003)==0);
        call(camera,"camera.page",SharedRuntime.map("session",photoSession,"offset",0,"limit",24),"page");
        yes(peer.count(0x1004)==1);yes(Boolean.TRUE.equals(status(camera).get("inventoryReady")));
        camera.cancel("page");yes(Boolean.TRUE.equals(status(camera).get("photoConnected")));
        yes(peer.orderedTransactions());camera.closeTransport();yes(peer.closed()==2);yes(status(camera).get("mode").equals("none"));camera.disconnect();

        // A denied capability must not destroy a usable photo session.
        Peer unsupported=new Peer();unsupported.supportsSlots=false;camera=unsupported.camera(new File(root,"unsupported"));
        SharedCamera missingCamera=camera;connection=connect(camera);String unsupportedSession=(String)connection.get("session");
        rejects(()->call(missingCamera,"camera.slots.open",scope(unsupportedSession),"slots-unsupported"));
        yes(Boolean.TRUE.equals(status(camera).get("photoConnected")));yes(unsupported.closed()==0);yes(unsupported.count(0x90cc)==0);camera.disconnect();

        // Known Nikon busy/unsupported responses consume their transaction, not the channel.
        for(int response:new int[]{0x2019,0x2005}){
            Peer busy=new Peer();busy.slotResponse=response;camera=busy.camera(new File(root,"read-"+response));
            SharedCamera current=camera;connection=connect(camera);String token=(String)connection.get("session");
            Throwable rejected=rejects(()->call(current,"camera.slots.open",scope(token),"slots-business"));yes(rejected instanceof PtpResponseException);
            yes(((PtpResponseException)rejected).responseCode()==response);yes(Boolean.TRUE.equals(status(camera).get("photoConnected")));yes(busy.closed()==0&&busy.count(0x1002)==1);
            call(camera,"camera.page",SharedRuntime.map("session",token,"offset",0,"limit",24),"after-busy-page");yes(busy.count(0x1004)==1);yes(busy.orderedTransactions());camera.disconnect();
        }
        Peer malformed=new Peer();malformed.wrongTransaction=true;camera=malformed.camera(new File(root,"malformed"));
        SharedCamera malformedCamera=camera;connection=connect(camera);String malformedToken=(String)connection.get("session");
        rejects(()->call(malformedCamera,"camera.slots.open",scope(malformedToken),"slots-malformed"));yes(malformed.closed()==2);yes(Boolean.FALSE.equals(status(camera).get("connected")));camera.disconnect();

        Peer blocked=new Peer();blocked.blockSlots=true;camera=blocked.camera(new File(root,"cancel"));SharedCamera blockedCamera=camera;connection=connect(camera);String blockedToken=(String)connection.get("session");
        AtomicReference<Throwable> blockedError=new AtomicReference<>();Thread worker=new Thread(()->{try{call(blockedCamera,"camera.slots.open",scope(blockedToken),"active-slots");}catch(Throwable e){blockedError.set(e);}},"slot-cancel-boundary");worker.setDaemon(true);worker.start();
        yes(blocked.entered.await(3,TimeUnit.SECONDS));camera.cancel("connect");yes(blocked.closed()==0);camera.cancel("active-slots");worker.join(3000);
        yes(!worker.isAlive());yes(blockedError.get() instanceof IOException);yes(blocked.closed()==2);yes(Boolean.FALSE.equals(status(camera).get("connected")));camera.disconnect();

        // Only acknowledged, exact readback allows the original verified handoff API.
        for(int mode=0;mode<3;mode++){
            Peer writer=new Peer();writer.writeMode=mode;camera=writer.camera(new File(root,"write-"+mode));connection=connect(camera);
            opened=call(camera,"camera.slots.open",scope((String)connection.get("session")),"write-open");String token=(String)opened.get("session");
            Map<String,Object> plan=call(camera,"camera.slots.prepare",SharedRuntime.map("session",token,"kind","write","source",201,"target",202),"write-prepare");
            Map<String,Object> result=call(camera,"camera.slots.execute",SharedRuntime.map("session",token,"confirmationId",plan.get("confirmationId"),"confirmed",true),"write-execute");
            yes(writer.writes==1);
            if(mode==0){yes(map(result.get("action")).get("phase").equals("verified"));yes(Arrays.equals(writer.items.get(201),writer.items.get(202)));}
            if(mode==1)yes(Boolean.TRUE.equals(map(result.get("action")).get("pending")));
            if(mode==2)yes(map(result.get("action")).get("phase").equals("rejected"));
            call(camera,"camera.slots.close",scope(token),"write-close");
            if(mode==0){yes(Boolean.TRUE.equals(status(camera).get("photoConnected")));yes(writer.closed()==0);yes(writer.count(0x1002)==1);}
            else {yes(Boolean.FALSE.equals(status(camera).get("connected")));yes(writer.closed()==2);}
            camera.disconnect();
        }
        // Cancelling a pure query discards its result without closing a camera.
        ProbeClient queryPeer=new ProbeClient();File queryRoot=new File(root,"query");yes(queryRoot.mkdirs());
        SharedCamera queryCamera=new SharedCamera(queryRoot.getPath(),(h,p,f)->null,(c,f)->queryPeer);connect(queryCamera);
        for(String operation:new String[]{"camera.status","camera.diagnostics"}){
            queryPeer.probe=()->queryCamera.cancel("query");
            rejects(()->call(queryCamera,operation,SharedRuntime.map(),"query"));yes(queryPeer.open);
            yes(Boolean.TRUE.equals(status(queryCamera).get("connected")));
        }
        queryCamera.disconnect();

        // A slow close captured by an old cancellation must not follow global slots.
        ProbeClient old=new ProbeClient();Peer next=new Peer();AtomicInteger creations=new AtomicInteger();
        File raceRoot=new File(root,"cancel-race");yes(raceRoot.mkdirs());
        SharedCamera raceCamera=new SharedCamera(raceRoot.getPath(),(h,p,f)->next::socket,(connector,f)->{if(creations.getAndIncrement()>0){old.blockInventory=false;old.blockClose=false;}return old;});
        String oldSession=(String)connect(raceCamera).get("session");old.blockInventory=true;old.blockClose=true;
        AtomicReference<Throwable> pageError=new AtomicReference<>();
        Thread page=new Thread(()->{try{call(raceCamera,"camera.page",SharedRuntime.map("session",oldSession,"offset",0,"limit",24),"old-page");}catch(Throwable e){pageError.set(e);}},"old-page-boundary");page.setDaemon(true);page.start();
        yes(old.entered.await(3,TimeUnit.SECONDS));Thread cancelThread=new Thread(()->raceCamera.cancel("old-page"),"old-cancel-boundary");cancelThread.setDaemon(true);cancelThread.start();
        yes(old.closeEntered.await(3,TimeUnit.SECONDS));page.join(3000);yes(!page.isAlive());yes(pageError.get() instanceof IOException);
        AtomicReference<Map<String,Object>> replacement=new AtomicReference<>();AtomicReference<Throwable> replacementError=new AtomicReference<>();CountDownLatch replacementStarted=new CountDownLatch(1);
        Thread replacementThread=new Thread(()->{replacementStarted.countDown();try{replacement.set(connect(raceCamera));}catch(Throwable e){replacementError.set(e);}},"same-object-replacement");replacementThread.setDaemon(true);replacementThread.start();yes(replacementStarted.await(3,TimeUnit.SECONDS));
        long waitUntil=System.nanoTime()+1_000_000_000L;while(replacementThread.isAlive()&&replacementThread.getState()!=Thread.State.TIMED_WAITING&&System.nanoTime()<waitUntil)Thread.sleep(1);
        yes(replacementThread.isAlive());yes(creations.get()==1);yes(cancelThread.isAlive());old.closeRelease.countDown();cancelThread.join(3000);replacementThread.join(3000);
        yes(!cancelThread.isAlive()&&!replacementThread.isAlive());yes(replacementError.get()==null);yes(Boolean.TRUE.equals(replacement.get().get("connected")));yes(old.open);yes(creations.get()==2);
        String newSession=(String)replacement.get().get("session");call(raceCamera,"camera.slots.open",scope(newSession),"new-slots");yes(next.closed()==0);yes(Boolean.TRUE.equals(status(raceCamera).get("slotsConnected")));raceCamera.disconnect();

        // A lifecycle close while a local connector is unpublished cannot resurrect it.
        Peer unpublished=new Peer();unpublished.blockSocket=true;File localRoot=new File(root,"unpublished");yes(localRoot.mkdirs());
        ProbeClient localPhoto=new ProbeClient();SharedCamera localCamera=new SharedCamera(localRoot.getPath(),(h,p,f)->unpublished::socket,(c,f)->localPhoto);
        String localToken=(String)connect(localCamera).get("session");AtomicReference<Throwable> localError=new AtomicReference<>();
        Thread localWorker=new Thread(()->{try{call(localCamera,"camera.slots.open",scope(localToken),"unpublished-open");}catch(Throwable e){localError.set(e);}},"unpublished-slot-connector");localWorker.setDaemon(true);localWorker.start();
        yes(unpublished.socketEntered.await(3,TimeUnit.SECONDS));localCamera.closeTransport();unpublished.socketRelease.countDown();localWorker.join(3000);
        yes(!localWorker.isAlive());yes(localError.get() instanceof IOException);yes(unpublished.sockets.size()==2);yes(unpublished.closed()==2);yes(Boolean.FALSE.equals(status(localCamera).get("connected")));localCamera.disconnect();
        System.out.println("PASS "+checks+" camera session ownership checks; lazy inventory, real PTP/IP handoff, recovery, stale/active cancel and verified-write guards");return checks;
    }
    private static Map<String,Object> connect(SharedCamera camera)throws IOException{return call(camera,"camera.connect",SharedRuntime.map("host","192.168.1.1","port",15740,"protocol","nikon"),"connect");}
    private static Map<String,Object> status(SharedCamera camera)throws IOException{return call(camera,"camera.status",SharedRuntime.map(),"status");}
    private static Map<String,Object> scope(String session){return SharedRuntime.map("session",session);}
    private static Map<String,Object> call(SharedCamera camera,String op,Map<String,Object> p,String job)throws IOException{return SharedJson.object(camera.request(op,SharedJson.encode(p),job,()->false,v->{}));}
    private static Map<String,Object> map(Object value)throws IOException{return SharedJson.object(SharedJson.encode(value));}

    private static final class ProbeClient implements PhotoCameraClient {
        volatile boolean open,blockInventory,blockClose;volatile Runnable probe;
        final AtomicBoolean closing=new AtomicBoolean();final CountDownLatch entered=new CountDownLatch(1),readRelease=new CountDownLatch(1),closeEntered=new CountDownLatch(1),closeRelease=new CountDownLatch(1);
        public byte[] connect(String h,int p,byte[] g,String n){open=true;return info(true);}
        public boolean isOpen(){Runnable action=probe;probe=null;if(action!=null)action.run();return open;}
        public boolean isProtocolUnconfirmed(){return false;}public String closeReason(){return "";}public String connectedHost(){return "192.168.1.1";}public int connectedPort(){return 15740;}public String cameraIdentity(){return "probe";}
        public void setOnClosed(Runnable r){}public void setOnObjectAdded(java.util.function.LongConsumer c){}public byte[] readAlbumDeviceInfo(){return info(true);}
        public byte[] getData(int op,int max,long...p)throws IOException{if(op!=0x1004)throw new IOException("Unexpected probe read");if(blockInventory){entered.countDown();try{if(!readRelease.await(3,TimeUnit.SECONDS))throw new IOException("Probe read did not unblock");}catch(InterruptedException e){Thread.currentThread().interrupt();throw new InterruptedIOException();}}if(!open)throw new IOException("Probe closed");return le32(0);}
        public byte[] getLargeThumbnail(long h)throws IOException{throw new IOException("No probe thumbnail");}public long readTo(int op,OutputStream out,long max,long expected,Progress progress,long...p)throws IOException{throw new IOException("No probe download");}public void abortProtocol(IOException error){close();}
        public void close(){if(closing.compareAndSet(false,true)&&blockClose){readRelease.countDown();closeEntered.countDown();try{closeRelease.await(3,TimeUnit.SECONDS);}catch(InterruptedException e){Thread.currentThread().interrupt();}}open=false;readRelease.countDown();}
    }

    private static final class Peer {
        final List<FakeSocket> sockets=new ArrayList<>();final List<Integer> operations=new ArrayList<>();final List<Long> transactions=new ArrayList<>();
        final Map<Integer,byte[]> items=new LinkedHashMap<>();final CountDownLatch entered=new CountDownLatch(1);final ByteArrayOutputStream upload=new ByteArrayOutputStream();
        boolean supportsSlots=true,wrongTransaction,blockSlots,blockSocket;int slotResponse,writeMode,writes,lastOperation,target;long lastTransaction;
        final CountDownLatch socketEntered=new CountDownLatch(1),socketRelease=new CountDownLatch(1);
        Peer(){for(int i=201;i<=209;i++)items.put(i,i==201?profile():new byte[36]);}
        SharedCamera camera(File root)throws IOException{Files.createDirectories(root.toPath());return new SharedCamera(root.getPath(),(h,p,f)->this::socket);}
        Socket socket(String host,int port,int timeout)throws IOException{if(blockSocket&&sockets.isEmpty()){socketEntered.countDown();try{if(!socketRelease.await(3,TimeUnit.SECONDS))throw new IOException("Unpublished connector did not release");}catch(InterruptedException e){Thread.currentThread().interrupt();throw new InterruptedIOException();}}if(sockets.size()>=2)throw new IOException("Unexpected extra physical camera connection");FakeSocket socket=new FakeSocket(this,!sockets.isEmpty());sockets.add(socket);return socket;}
        int count(int op){int result=0;for(int value:operations)if(value==op)result++;return result;}
        int closed(){int result=0;for(FakeSocket socket:sockets)if(socket.closed)result++;return result;}
        boolean orderedTransactions(){long previous=0;for(long tx:transactions){if(tx==0&&previous==0)continue;if(tx<=previous)return false;previous=tx;}return true;}
        void packet(FakeSocket socket,byte[] bytes)throws IOException{
            long type=u32(bytes,4);
            if(socket.event){if(type==3)socket.input.add(frame(4,new byte[0]));return;}
            if(type==1){socket.input.add(frame(2,concat(le32(1),new byte[16],"Fixture\0".getBytes(StandardCharsets.UTF_16LE),le32(0x10000))));return;}
            if(type==9)return;
            if(type==10||type==12){upload.write(bytes,12,bytes.length-12);if(type==12){writes++;if(writeMode!=2)items.put(target,upload.toByteArray());if(writeMode==1)throw new IOException("Synthetic lost write acknowledgement");socket.input.add(response(lastTransaction,writeMode==2?0x200f:0x2001));}return;}
            if(type!=6)throw new IOException("Unexpected client frame");
            int op=u16(bytes,12);long tx=u32(bytes,14);operations.add(op);transactions.add(tx);lastOperation=op;lastTransaction=tx;
            if(op==0x1002||op==0x1003){socket.input.add(response(tx,0x2001));return;}
            if(op==0x90cd){target=(int)u32(bytes,18);upload.reset();return;}
            if(op==0x90cc){if(blockSlots){entered.countDown();return;}if(slotResponse!=0){socket.input.add(response(tx,slotResponse));return;}}
            byte[] data;
            if(op==0x1001)data=info(supportsSlots);
            else if(op==0x1004||op==0x1007)data=le32(0);
            else if(op==0x90cf)data=new byte[28];
            else if(op==0x90cc)data=items.get((int)u32(bytes,18));
            else if(op==0x1015)data=le16(1);
            else throw new IOException("Unexpected test operation "+Integer.toHexString(op));
            socket.input.add(frame(9,concat(le32(tx),le64(data.length))));socket.input.add(frame(12,concat(le32(tx),data)));
            socket.input.add(response(tx+(wrongTransaction&&op==0x90cf?1:0),0x2001));
        }
    }
    private static final class FakeSocket extends Socket {
        final Peer peer;final boolean event;final QueuedInput input=new QueuedInput();final ByteArrayOutputStream pending=new ByteArrayOutputStream();volatile boolean closed;
        FakeSocket(Peer peer,boolean event){this.peer=peer;this.event=event;}
        public InputStream getInputStream(){return input;}
        public OutputStream getOutputStream(){return new OutputStream(){public void write(int b)throws IOException{write(new byte[]{(byte)b});}public void write(byte[] b,int off,int length)throws IOException{if(closed)throw new IOException("Closed fixture socket");pending.write(b,off,length);while(pending.size()>=8){byte[] all=pending.toByteArray();int size=(int)u32(all,0);if(size<8||size>1048576)throw new IOException("Invalid client frame");if(all.length<size)return;pending.reset();pending.write(all,size,all.length-size);peer.packet(FakeSocket.this,Arrays.copyOf(all,size));}}};}
        public void setSoTimeout(int timeout){}public void setTcpNoDelay(boolean value){}public boolean isConnected(){return true;}public boolean isClosed(){return closed;}
        public void close(){closed=true;input.close();}
    }
    private static final class QueuedInput extends InputStream {
        final ArrayDeque<Byte> bytes=new ArrayDeque<>();boolean closed;
        synchronized void add(byte[] value){for(byte b:value)bytes.addLast(b);notifyAll();}
        public synchronized int read()throws IOException{while(bytes.isEmpty()&&!closed){try{wait(100);}catch(InterruptedException e){Thread.currentThread().interrupt();throw new InterruptedIOException();}if(bytes.isEmpty()&&!closed)throw new SocketTimeoutException("Fixture input wait");}return bytes.isEmpty()?-1:bytes.removeFirst()&255;}
        public synchronized int read(byte[] out,int off,int length)throws IOException{if(length==0)return 0;int first=read();if(first<0)return -1;out[off]=(byte)first;int count=1;while(count<length&&!bytes.isEmpty())out[off+count++]=bytes.removeFirst();return count;}
        public synchronized void close(){closed=true;bytes.clear();notifyAll();}
    }
    private static byte[] profile(){byte[] bytes=new byte[36];bytes[0]=1;byte[] name="SOURCE".getBytes(StandardCharsets.US_ASCII);System.arraycopy(name,0,bytes,2,name.length);return bytes;}
    private static byte[] info(boolean slots){int[] operations=slots?new int[]{0x1001,0x1002,0x1003,0x1004,0x1007,0x1008,0x1009,0x90cc,0x90cd,0x90ce,0x90cf,0x1015}:new int[]{0x1001,0x1002,0x1003,0x1004,0x1007,0x1008,0x1009};ByteArrayOutputStream ops=new ByteArrayOutputStream();put(ops,le32(operations.length));for(int op:operations)put(ops,le16(op));return concat(le16(100),le32(10),le16(100),text("Fixture"),le16(0),ops.toByteArray(),le32(0),le32(0),le32(0),le32(0),text("NIKON CORPORATION"),text("Z 6_2"),text("1"),text("SERIAL-FIXTURE"));}
    private static byte[] text(String s){return s.isEmpty()?new byte[]{0}:concat(new byte[]{(byte)(s.length()+1)},(s+'\0').getBytes(StandardCharsets.UTF_16LE));}
    private static byte[] response(long tx,int code){return frame(7,concat(le16(code),le32(tx)));}
    private static byte[] frame(long type,byte[] payload){return concat(le32(payload.length+8),le32(type),payload);}
    private static byte[] le16(long n){return new byte[]{(byte)n,(byte)(n>>>8)};}private static byte[] le32(long n){return new byte[]{(byte)n,(byte)(n>>>8),(byte)(n>>>16),(byte)(n>>>24)};}private static byte[] le64(long n){return concat(le32(n),le32(n>>>32));}
    private static long u32(byte[] b,int o){return (b[o]&255L)|(b[o+1]&255L)<<8|(b[o+2]&255L)<<16|(b[o+3]&255L)<<24;}private static int u16(byte[] b,int o){return (b[o]&255)|(b[o+1]&255)<<8;}
    private static void put(ByteArrayOutputStream out,byte[] b){out.write(b,0,b.length);}private static byte[] concat(byte[]...parts){ByteArrayOutputStream out=new ByteArrayOutputStream();for(byte[] part:parts)put(out,part);return out.toByteArray();}
}
