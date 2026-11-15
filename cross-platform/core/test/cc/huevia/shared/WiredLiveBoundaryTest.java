package cc.huevia.shared;

import cc.huevia.album.PhotoCameraClient;
import cc.huevia.album.PhotoEditStore;
import cc.huevia.library.SharedJson;
import cc.huevia.ptp.PtpObjectInfo;
import cc.huevia.ptp.PtpResponseException;
import java.io.*;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.atomic.AtomicLong;
import java.util.function.LongConsumer;

/** USB fixtures exercise the production discovery/download path without a Wi-Fi connector. */
final class WiredLiveBoundaryTest {
    private static int checks;
    private static void yes(boolean value){checks++;if(!value)throw new AssertionError("Wired live "+checks);}
    private interface Action {void run()throws Exception;}
    private static void rejects(Action action)throws Exception{checks++;try{action.run();}catch(IOException expected){return;}throw new AssertionError("Unsafe USB live request accepted");}
    static int run(Path temporary)throws Exception{
        checks=0;
        for(boolean raw:new boolean[]{false,true})capture(temporary,raw);
        identity(temporary,"",false);identity(temporary,"000000",false);identity(temporary,"unknown",false);identity(temporary,"USB-SERIAL-17",true);
        System.out.println("PASS "+checks+" wired live checks; JPEG/NEF originals, baseline, missing events, catalog readiness, stable size, busy retry, soft stop, unplug and serial-scoped resume");
        return checks;
    }
    private static void capture(Path temporary,boolean raw)throws Exception{
        Peer peer=new Peer("USB-SERIAL-17");peer.put(1,raw);AtomicLong clock=new AtomicLong(10000000000L);
        SharedCamera camera=camera(temporary.resolve(raw?"wired-live-raw":"wired-live-jpeg"),peer,clock);
        Map<String,Object> status=connect(camera);String session=(String)status.get("session"),id=(String)status.get("cameraId");
        yes(Boolean.TRUE.equals(status.get("supportsLive")));yes(Boolean.TRUE.equals(status.get("trustedCamera")));yes(id.equals(status.get("downloadCameraId")));
        String format=raw?"raw":"jpeg";
        Map<String,Object> start=call(camera,"camera.live.start",SharedRuntime.map("session",session,"cameraId",id,"format",format));
        Map<String,Object> request=SharedRuntime.map("session",session,"watchId",start.get("watchId"),"format",format);
        yes(peer.reads==0);yes(((List<?>)map(start.get("cursor")).get("baseline")).size()==1);yes(items(call(camera,"camera.live.poll",request)).isEmpty());
        // No native event is necessary: periodic USB inventory discovers the new handle.
        peer.put(2,raw);peer.catalogReady=false;peer.sizes.put(2L,0L);clock.addAndGet(3100000000L);
        yes(items(call(camera,"camera.live.poll",request)).isEmpty());peer.sizes.put(2L,(long)peer.data.get(2L).length);
        clock.addAndGet(300000000L);yes(items(call(camera,"camera.live.poll",request)).isEmpty());
        clock.addAndGet(300000000L);yes(items(call(camera,"camera.live.poll",request)).isEmpty());yes(peer.reads==0);
        // A ready catalog still needs two matching descriptor samples.
        peer.catalogReady=true;peer.busy=true;
        clock.addAndGet(300000000L);yes(items(call(camera,"camera.live.poll",request)).isEmpty());
        clock.addAndGet(300000000L);yes(items(call(camera,"camera.live.poll",request)).isEmpty());
        clock.addAndGet(300000000L);Map<String,Object> found=call(camera,"camera.live.poll",request);yes(items(found).size()==1);
        Map<String,Object> item=map(items(found).get(0));yes(((Number)item.get("handle")).longValue()==2);yes(Boolean.valueOf(raw).equals(item.get("raw")));yes(peer.reads==0);
        Map<String,Object> download=SharedRuntime.map("session",session,"watchId",start.get("watchId"),"objectKey",item.get("objectKey"),"handle",2,"raw",raw);
        Map<String,Object> stale=new LinkedHashMap<>(download);stale.put("session","stale");rejects(()->call(camera,"camera.download",stale));yes(peer.reads==0);
        Map<String,Object> wrongFormat=new LinkedHashMap<>(download);wrongFormat.put("raw",!raw);rejects(()->call(camera,"camera.download",wrongFormat));yes(peer.reads==0);
        Map<String,Object> receipt=call(camera,"camera.download",download);byte[] expected=peer.data.get(2L);
        yes(Arrays.equals(expected,Files.readAllBytes(Paths.get((String)receipt.get("path")))));yes(PhotoEditStore.hash(expected).equals(receipt.get("sha256")));
        yes(id.equals(receipt.get("cameraId")));yes(start.get("watchId").equals(receipt.get("watchId")));yes(peer.reads==1);
        call(camera,"camera.live.ack",SharedRuntime.map("session",session,"watchId",start.get("watchId"),"objectKey",item.get("objectKey")));
        clock.addAndGet(3100000000L);yes(items(call(camera,"camera.live.poll",request)).isEmpty());rejects(()->call(camera,"camera.download",download));
        int calls=peer.calls;rejects(()->camera.request("camera.live.poll",SharedJson.encode(request),"cancel",()->true,v->{}));yes(peer.calls==calls&&peer.open);
        // Soft stop clears hints and leaves the same session available for manual originals.
        LongConsumer late=peer.listener;call(camera,"camera.live.stop",request);yes(peer.open&&peer.listener==null);late.accept(99);yes(peer.calls==calls);
        yes(session.equals(call(camera,"camera.keepAlive",Map.of()).get("session")));
        call(camera,"camera.page",SharedRuntime.map("session",session,"raw",raw));
        Map<String,Object> manual=call(camera,"camera.download",SharedRuntime.map("session",session,"handle",2,"raw",raw));yes(Arrays.equals(expected,Files.readAllBytes(Paths.get((String)manual.get("path")))));
        start=call(camera,"camera.live.start",SharedRuntime.map("session",session,"format",format));yes(items(call(camera,"camera.live.poll",SharedRuntime.map("session",session,"watchId",start.get("watchId")))).isEmpty());
        Map<String,Object> old=request;rejects(()->call(camera,"camera.live.stop",old));
        Map<String,Object> current=SharedRuntime.map("session",session,"watchId",start.get("watchId"));peer.open=false;rejects(()->call(camera,"camera.live.poll",current));camera.disconnect();
    }
    private static void identity(Path temporary,String serial,boolean trusted)throws Exception{
        Peer peer=new Peer(serial);peer.put(1,false);AtomicLong clock=new AtomicLong(10000000000L);
        SharedCamera camera=camera(temporary.resolve("wired-live-id-"+checks),peer,clock);
        Map<String,Object> status=connect(camera);String first=(String)status.get("session"),id=(String)status.get("cameraId");yes(Boolean.valueOf(trusted).equals(status.get("trustedCamera")));
        Map<String,Object> start=call(camera,"camera.live.start",SharedRuntime.map("session",first));Object cursor=start.get("cursor");camera.disconnect();peer.put(2,false);
        status=connect(camera);String session=(String)status.get("session");yes(!first.equals(session));yes(trusted==id.equals(status.get("cameraId")));
        Map<String,Object> resume=SharedRuntime.map("session",session,"cameraId",id,"cursor",cursor);
        if(trusted){
            start=call(camera,"camera.live.start",resume);Map<String,Object> poll=SharedRuntime.map("session",session,"watchId",start.get("watchId"));
            yes(items(call(camera,"camera.live.poll",poll)).isEmpty());clock.addAndGet(300000000L);yes(items(call(camera,"camera.live.poll",poll)).size()==1);
            call(camera,"camera.live.stop",poll);camera.disconnect();peer.serial="DIFFERENT-USB-SERIAL";status=connect(camera);resume.put("session",status.get("session"));rejects(()->call(camera,"camera.live.start",resume));yes(peer.listener==null);
        }else{
            rejects(()->call(camera,"camera.live.start",resume));
            resume.put("cameraId",status.get("cameraId"));rejects(()->call(camera,"camera.live.start",resume));yes(peer.listener==null);
        }
        camera.disconnect();
    }
    private static SharedCamera camera(Path root,Peer peer,AtomicLong clock)throws IOException{
        Files.createDirectories(root);return new SharedCamera(root.toString(),(h,p,f)->{throw new AssertionError("USB opened Wi-Fi");},new SharedCamera.WiredConnections(){
            public String devices(){return "{\"items\":[]}";}
            public PhotoCameraClient create(String id){return peer;}
        },clock::get);
    }
    private static Map<String,Object> connect(SharedCamera camera)throws IOException{return call(camera,"camera.connect",SharedRuntime.map("transport","usb","deviceId","fixture","protocol","nikon"));}
    private static Map<String,Object> call(SharedCamera camera,String op,Map<String,Object> p)throws IOException{return SharedJson.object(camera.request(op,SharedJson.encode(p),"wired-live-test",()->false,v->{}));}
    private static List<?> items(Map<String,Object> value){return (List<?>)value.get("items");}
    @SuppressWarnings("unchecked") private static Map<String,Object> map(Object value){return (Map<String,Object>)value;}
    private static final class Peer implements PhotoCameraClient {
        boolean open,catalogReady=true,busy;int reads,calls;String serial;LongConsumer listener;
        final Map<Long,byte[]> data=new LinkedHashMap<>();final Map<Long,Long> sizes=new LinkedHashMap<>();final Set<Long> raw=new HashSet<>();
        Peer(String serial){this.serial=serial;}
        void put(long handle,boolean nef){byte[] bytes=nef?CameraRawBoundaryTest.nef():new byte[]{(byte)255,(byte)216,1,2,3,4,(byte)255,(byte)217};data.put(handle,bytes);sizes.put(handle,(long)bytes.length);if(nef)raw.add(handle);}
        public byte[] connect(String h,int p,byte[] guid,String name){open=true;return info(serial);}
        public boolean isOpen(){return open;}public boolean isProtocolUnconfirmed(){return false;}public String closeReason(){return "USB detached";}
        public String connectedHost(){return "usb:fixture";}public int connectedPort(){return 0;}public String cameraIdentity(){return serial;}
        public void setOnClosed(Runnable listener){}public void setOnObjectAdded(LongConsumer value){listener=value;}public byte[] readAlbumDeviceInfo(){return info(serial);}
        public boolean canReadLiveObject(long handle,long expected){return catalogReady&&expected==data.get(handle).length;}
        public byte[] getData(int op,int max,long...p)throws IOException{
            calls++;if(!open)throw new IOException("USB detached");
            if(op==0x1004)return concat(le32(1),le32(1));
            if(op==0x1007){ByteArrayOutputStream out=new ByteArrayOutputStream();out.writeBytes(le32(data.size()));for(long h:data.keySet())out.writeBytes(le32((int)h));return out.toByteArray();}
            if(op==0x1008){if(busy&&p[0]==2){busy=false;throw new PtpResponseException(0x2019,0);}if(!data.containsKey(p[0]))throw new PtpResponseException(0x2009,0);
                return new PtpObjectInfo.Builder().storageId(1).objectFormat(raw.contains(p[0])?0xb103:0x3801).compressedSize(sizes.get(p[0])).imagePixWidth(4).imagePixHeight(3).filename("USB_"+p[0]+(raw.contains(p[0])?".NEF":".JPG")).build().toBytes();}
            throw new IOException("Unexpected USB operation "+op);
        }
        public byte[] getLargeThumbnail(long handle)throws IOException{throw new PtpResponseException(0x2005,0);}
        public long readTo(int op,OutputStream out,long max,long expected,Progress progress,long...p)throws IOException{reads++;byte[] bytes=data.get(p[0]);out.write(bytes);progress.onProgress(bytes.length,bytes.length);return bytes.length;}
        public void abortProtocol(IOException failure){close();}public void close(){open=false;listener=null;}
    }
    private static byte[] info(String serial){int[] ops={0x1001,0x1002,0x1003,0x1004,0x1007,0x1008,0x1009,0x100a};ByteArrayOutputStream out=new ByteArrayOutputStream();out.writeBytes(le32(ops.length));for(int op:ops)out.writeBytes(le16(op));return concat(le16(100),le32(10),le16(100),text(""),le16(0),out.toByteArray(),le32(0),le32(0),le32(0),le32(0),text("NIKON CORPORATION"),text("USB Fixture"),text("1"),text(serial));}
    private static byte[] text(String s){ByteArrayOutputStream out=new ByteArrayOutputStream();if(s.isEmpty()){out.write(0);return out.toByteArray();}out.write(s.length()+1);for(char c:s.toCharArray())out.writeBytes(le16(c));out.writeBytes(le16(0));return out.toByteArray();}
    private static byte[] le16(int n){return new byte[]{(byte)n,(byte)(n>>>8)};}private static byte[] le32(int n){return new byte[]{(byte)n,(byte)(n>>>8),(byte)(n>>>16),(byte)(n>>>24)};}
    private static byte[] concat(byte[]...parts){ByteArrayOutputStream out=new ByteArrayOutputStream();for(byte[] p:parts)out.writeBytes(p);return out.toByteArray();}
    public static void main(String[] args)throws Exception{run(Files.createTempDirectory("wired-live-"));}
}
