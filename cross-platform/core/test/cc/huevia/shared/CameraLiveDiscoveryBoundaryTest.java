package cc.huevia.shared;

import cc.huevia.album.PhotoCameraClient;
import cc.huevia.library.SharedJson;
import cc.huevia.ptp.PtpObjectInfo;
import cc.huevia.ptp.PtpResponseException;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.IOException;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicLong;
import java.util.function.LongConsumer;

/** Discovery is exercised through production SharedCamera and the original camera interface. */
final class CameraLiveDiscoveryBoundaryTest {
    private static int checks;
    private static void yes(boolean value){checks++;if(!value)throw new AssertionError("Camera live discovery "+checks);}
    private interface Action{void run()throws Exception;}
    private static void rejects(Action action)throws Exception{checks++;try{action.run();}catch(IOException expected){return;}throw new AssertionError("Unsafe live request accepted");}
    public static void main(String[] args)throws Exception{run(Files.createTempDirectory("huevia-live-discovery-"));}
    static int run(Path temporary)throws Exception{
        checks=0;Peer peer=new Peer();peer.put(1,1,"OLD.JPG",8);AtomicLong clock=new AtomicLong(10000000000L);
        File root=temporary.resolve("live-camera").toFile();yes(root.mkdirs());
        SharedCamera camera=new SharedCamera(root.getPath(),(h,p,f)->null,(c,f)->peer,clock::get);
        Map<String,Object> connected=connect(camera);String session=(String)connected.get("session"),cameraId=(String)connected.get("cameraId");
        yes(Boolean.TRUE.equals(connected.get("supportsLive")));yes(Boolean.TRUE.equals(connected.get("trustedCamera")));yes(cameraId.matches("[0-9a-f]{64}"));
        Map<String,Object> page=SharedRuntime.map("session",session,"offset",0,"limit",24,"raw",false);
        yes(items(call(camera,"camera.page",page)).size()==1);int metadata=peer.metadata;
        Map<String,Object> start=call(camera,"camera.live.start",SharedRuntime.map("session",session));String watch=(String)start.get("watchId");
        Map<String,Object> request=SharedRuntime.map("session",session,"watchId",watch,"limit",12);
        yes(peer.metadata==metadata);yes(baseline(start).size()==1);yes(peer.listener!=null);yes(peer.originals==0);
        rejects(()->call(camera,"camera.live.start",SharedRuntime.map("session",session)));
        peer.event(1);Map<String,Object> first=call(camera,"camera.live.poll",request);yes(items(first).isEmpty());yes(((List<?>)first.get("baselineUpdates")).size()==1);
        // Duplicate old notifications never import the old card, and event callbacks perform no PTP.
        int calls=peer.calls;for(int i=0;i<1000;i++)peer.event(1);yes(peer.calls==calls);yes(items(call(camera,"camera.live.poll",request)).isEmpty());
        peer.put(1,2,"NEW.JPG",0);peer.event(2);clock.addAndGet(300000000L);yes(items(call(camera,"camera.live.poll",request)).isEmpty());
        peer.put(1,2,"NEW.JPG",8);clock.addAndGet(300000000L);yes(items(call(camera,"camera.live.poll",request)).isEmpty());
        clock.addAndGet(300000000L);Map<String,Object> found=call(camera,"camera.live.poll",request);List<?> discovered=items(found);yes(discovered.size()==1);
        Map<String,Object> item=object(discovered.get(0));String key=(String)item.get("objectKey");yes(key.matches("[0-9a-f]{64}"));yes(((Number)item.get("handle")).longValue()==2);yes(((Number)item.get("storage")).longValue()==1);yes(Boolean.FALSE.equals(item.get("raw")));
        yes(peer.originals==0);yes(items(call(camera,"camera.live.poll",request)).size()==1);
        // A browsing refresh clears ordinary observed entries, not the explicitly live-authorized candidate.
        page.put("refresh",true);call(camera,"camera.page",page);
        Map<String,Object> download=SharedRuntime.map("session",session,"watchId",watch,"objectKey",key,"handle",2,"raw",false);
        Map<String,Object> receipt=call(camera,"camera.download",download);yes(peer.originals==1);yes(key.equals(receipt.get("objectKey")));yes(watch.equals(receipt.get("watchId")));yes(cameraId.equals(receipt.get("cameraId")));yes(Arrays.equals(Files.readAllBytes(new File((String)receipt.get("path")).toPath()),peer.jpeg));
        Map<String,Object> ack=SharedRuntime.map("session",session,"watchId",watch,"objectKey",key);yes(Boolean.TRUE.equals(call(camera,"camera.live.ack",ack).get("acknowledged")));
        peer.event(2);clock.addAndGet(300000000L);yes(items(call(camera,"camera.live.poll",request)).isEmpty());rejects(()->call(camera,"camera.download",download));
        // Missed events reconcile through periodic inventory, and NEFs remain manual-only.
        peer.put(1,3,"MISSED.JPG",8);peer.put(1,4,"RAW.NEF",30);clock.addAndGet(3100000000L);
        yes(items(call(camera,"camera.live.poll",request)).isEmpty());clock.addAndGet(300000000L);found=call(camera,"camera.live.poll",request);yes(items(found).size()==1);Map<String,Object> third=object(items(found).get(0));yes(((Number)third.get("handle")).longValue()==3);
        // A handle reused in the initial baseline is a new identity after its old descriptor was sampled.
        peer.put(1,1,"REUSED_BASELINE.JPG",8);peer.event(1);call(camera,"camera.live.poll",request);clock.addAndGet(300000000L);found=call(camera,"camera.live.poll",request);yes(items(found).stream().map(CameraLiveDiscoveryBoundaryTest::object).anyMatch(r->((Number)r.get("handle")).longValue()==1));
        // A currently authorized pending object disappearing is reported, even without a reconnect.
        peer.put(1,6,"ACTIVE_REMOVED.JPG",8);peer.event(6);call(camera,"camera.live.poll",request);clock.addAndGet(300000000L);found=call(camera,"camera.live.poll",request);Map<String,Object> sixth=find(found,6);yes(sixth!=null);
        peer.objects.remove(6L);clock.addAndGet(3100000000L);found=call(camera,"camera.live.poll",request);yes(unavailable(found,sixth.get("objectKey"),"missing"));yes(find(found,6)==null);found=call(camera,"camera.live.poll",request);yes(!unavailable(found,sixth.get("objectKey"),"missing"));
        // A deletion discovered by the original receive metadata check has the same durable notification.
        peer.put(1,7,"REMOVED_BEFORE_RECEIVE.JPG",8);peer.event(7);clock.addAndGet(300000000L);call(camera,"camera.live.poll",request);clock.addAndGet(300000000L);found=call(camera,"camera.live.poll",request);Map<String,Object> seventh=find(found,7);yes(seventh!=null);peer.objects.remove(7L);int beforeRemovedRead=peer.originals;
        Map<String,Object> removedRead=SharedRuntime.map("session",session,"watchId",watch,"objectKey",seventh.get("objectKey"),"handle",7);rejectCall(camera,"camera.download",removedRead);yes(peer.originals==beforeRemovedRead);found=call(camera,"camera.live.poll",request);yes(unavailable(found,seventh.get("objectKey"),"missing"));
        Map<String,Object> badLimit=SharedRuntime.map("session",session,"watchId",watch,"limit",61);rejectCall(camera,"camera.live.poll",badLimit);
        int beforeCancel=peer.calls;Map<String,Object> cancelRequest=request;
        rejects(()->camera.request("camera.live.poll",SharedJson.encode(cancelRequest),"cancelled",()->true,v->{}));yes(peer.calls==beforeCancel&&peer.open);
        // Stop leaves the camera usable; the old token cannot stop a replacement watcher.
        call(camera,"camera.live.stop",request);yes(peer.open);yes(peer.listener==null);rejectCall(camera,"camera.live.poll",request);
        start=call(camera,"camera.live.start",SharedRuntime.map("session",session));String replacement=(String)start.get("watchId");yes(!watch.equals(replacement));rejectCall(camera,"camera.live.stop",request);yes(peer.listener!=null);
        Map<String,Object> replacementRequest=SharedRuntime.map("session",session,"watchId",replacement);
        // Persisted handle-only cursor retains newly received rows as candidates after reconnect.
        Map<String,Object> cursor=object(start.get("cursor"));call(camera,"camera.live.stop",replacementRequest);
        peer.put(1,5,"OFFLINE.JPG",8);camera.disconnect();connected=connect(camera);String resumed=(String)connected.get("session");yes(cameraId.equals(connected.get("cameraId")));
        Map<String,Object> pending=SharedRuntime.map("storage",1,"handle",3,"objectKey",third.get("objectKey"));cursor.put("pending",Arrays.asList(pending));
        start=call(camera,"camera.live.start",SharedRuntime.map("session",resumed,"cameraId",cameraId,"cursor",cursor));request=SharedRuntime.map("session",resumed,"watchId",start.get("watchId"));
        yes(items(call(camera,"camera.live.poll",request)).isEmpty());clock.addAndGet(300000000L);found=call(camera,"camera.live.poll",request);yes(items(found).size()==2);yes(items(found).stream().map(CameraLiveDiscoveryBoundaryTest::object).anyMatch(r->((Number)r.get("handle")).longValue()==5));yes(items(found).stream().map(CameraLiveDiscoveryBoundaryTest::object).anyMatch(r->third.get("objectKey").equals(r.get("objectKey"))));
        // An unreadable card is preserved. Its first readable inventory is a baseline, not a flood of old files.
        peer.cardTwo=false;clock.addAndGet(3100000000L);found=call(camera,"camera.live.poll",request);yes(((Number)found.get("unavailableStorages")).intValue()==1);
        peer.cardTwo=true;peer.put(2,100,"OLD_CARD2.JPG",8);clock.addAndGet(3100000000L);found=call(camera,"camera.live.poll",request);yes(((List<?>)found.get("baselineUpdates")).stream().map(CameraLiveDiscoveryBoundaryTest::object).anyMatch(r->((Number)r.get("handle")).longValue()==100));yes(items(found).stream().map(CameraLiveDiscoveryBoundaryTest::object).noneMatch(r->((Number)r.get("handle")).longValue()==100));
        // Metadata mutation after discovery is rejected before any GetObject and must be re-probed.
        Map<String,Object> latest=object(items(found).get(0));long changed=((Number)latest.get("handle")).longValue();int originals=peer.originals;peer.put(1,changed,"REUSED.JPG",8);
        Map<String,Object> stale=SharedRuntime.map("session",resumed,"watchId",start.get("watchId"),"objectKey",latest.get("objectKey"),"handle",changed);
        rejects(()->call(camera,"camera.download",stale));yes(peer.originals==originals);
        found=call(camera,"camera.live.poll",request);yes(unavailable(found,latest.get("objectKey"),"changed"));found=call(camera,"camera.live.poll",request);yes(!unavailable(found,latest.get("objectKey"),"changed"));
        Map<String,Object> reconnectCursor=object(start.get("cursor"));reconnectCursor.put("pending",Arrays.asList(SharedRuntime.map("storage",1,"handle",changed,"objectKey",latest.get("objectKey"))));
        call(camera,"camera.live.stop",request);camera.disconnect();connected=connect(camera);String again=(String)connected.get("session");
        start=call(camera,"camera.live.start",SharedRuntime.map("session",again,"cameraId",cameraId,"cursor",reconnectCursor));request=SharedRuntime.map("session",again,"watchId",start.get("watchId"));found=call(camera,"camera.live.poll",request);yes(((List<?>)found.get("unavailable")).stream().map(CameraLiveDiscoveryBoundaryTest::object).anyMatch(r->latest.get("objectKey").equals(r.get("objectKey"))&&"changed".equals(r.get("reason"))));
        call(camera,"camera.live.stop",request);camera.disconnect();
        // Untrusted camera identity is scoped to one connection and cannot resume another session.
        peer.identity="00000000000000000000000000000000";connected=connect(camera);String unknown=(String)connected.get("session");yes(Boolean.FALSE.equals(connected.get("trustedCamera")));String ephemeral=(String)connected.get("cameraId");
        rejects(()->call(camera,"camera.live.start",SharedRuntime.map("session",unknown,"cameraId",cameraId,"cursor",cursor)));camera.disconnect();connected=connect(camera);yes(!ephemeral.equals(connected.get("cameraId")));camera.disconnect();
        // The original X-T20 adapter deliberately does not support photo-live.
        peer.fuji=true;connected=call(camera,"camera.connect",SharedRuntime.map("host","192.168.1.1","protocol","fujifilm"));String fuji=(String)connected.get("session");yes(Boolean.FALSE.equals(connected.get("supportsLive")));rejects(()->call(camera,"camera.live.start",SharedRuntime.map("session",fuji)));camera.disconnect();
        // The full supported card baseline needs no descriptor reads; overflow is rejected transactionally.
        peer.fuji=false;peer.identity="11223344556677889900aabbccddeeff";peer.objects.clear();for(long handle=1;handle<=20000;handle++)peer.put(1,handle,"BASELINE.JPG",8);
        connected=connect(camera);String big=(String)connected.get("session");int beforeBaseline=peer.metadata;start=call(camera,"camera.live.start",SharedRuntime.map("session",big));yes(baseline(start).size()==20000);yes(peer.metadata==beforeBaseline);call(camera,"camera.live.stop",SharedRuntime.map("session",big,"watchId",start.get("watchId")));
        start=call(camera,"camera.live.start",SharedRuntime.map("session",big,"cameraId",cameraId,"cursor",start.get("cursor")));yes(baseline(start).size()==20000);yes(peer.metadata==beforeBaseline);call(camera,"camera.live.stop",SharedRuntime.map("session",big,"watchId",start.get("watchId")));
        peer.put(1,20001,"OVERFLOW.JPG",8);rejects(()->call(camera,"camera.live.start",SharedRuntime.map("session",big)));yes(peer.listener==null&&peer.open);camera.disconnect();
        // A newly readable large card carries a complete paged cursor atomically, not a partial baseline.
        peer.objects.clear();peer.put(1,1,"OLD.JPG",8);peer.cardTwo=false;connected=connect(camera);String cards=(String)connected.get("session");start=call(camera,"camera.live.start",SharedRuntime.map("session",cards));
        for(long handle=1000;handle<3000;handle++)peer.put(2,handle,"OLD2.JPG",8);peer.cardTwo=true;clock.addAndGet(3100000000L);found=call(camera,"camera.live.poll",SharedRuntime.map("session",cards,"watchId",start.get("watchId")));
        yes(((List<?>)found.get("baselineUpdates")).size()==1000);yes(found.get("cursor") instanceof Map);yes(baseline(found).size()==2001);yes(items(found).isEmpty());camera.disconnect();
        System.out.println("PASS "+checks+" camera live discovery checks; handle baselines, event-only hints, stable descriptors, missed events, independent browsing, reconnect, storage recovery and scoped downloads");return checks;
    }
    private static void rejectCall(SharedCamera camera,String operation,Map<String,Object> p)throws Exception{rejects(()->call(camera,operation,p));}
    private static Map<String,Object> connect(SharedCamera camera)throws IOException{return call(camera,"camera.connect",SharedRuntime.map("host","192.168.1.1","protocol","nikon"));}
    private static Map<String,Object> call(SharedCamera camera,String operation,Map<String,Object> p)throws IOException{return SharedJson.object(camera.request(operation,SharedJson.encode(p),"live-test",()->false,v->{}));}
    @SuppressWarnings("unchecked") private static Map<String,Object> object(Object value){return (Map<String,Object>)value;}
    private static List<?> items(Map<String,Object> value){return (List<?>)value.get("items");}
    private static Map<String,Object> find(Map<String,Object> value,long handle){for(Object row:items(value)){Map<String,Object> item=object(row);if(((Number)item.get("handle")).longValue()==handle)return item;}return null;}
    private static boolean unavailable(Map<String,Object> value,Object key,String reason){for(Object raw:(List<?>)value.get("unavailable")){Map<String,Object> row=object(raw);if(key.equals(row.get("objectKey"))&&reason.equals(row.get("reason")))return true;}return false;}
    private static List<?> baseline(Map<String,Object> value){Map<String,Object> cursor=object(value.get("cursor"));List<Object> rows=new ArrayList<>((List<?>)cursor.get("baseline"));for(Object page:(List<?>)cursor.getOrDefault("baselinePages",new ArrayList<>()))rows.addAll((List<?>)page);return rows;}
    private static final class Peer implements PhotoCameraClient {
        boolean open,cardTwo,fuji;int metadata,originals,calls;String identity="11223344556677889900aabbccddeeff";LongConsumer listener;
        final Map<Long,PtpObjectInfo> objects=new LinkedHashMap<>();final byte[] jpeg={(byte)255,(byte)216,1,2,3,4,(byte)255,(byte)217};
        void put(long storage,long handle,String name,long size){objects.put(handle,new PtpObjectInfo.Builder().storageId(storage).objectFormat(name.endsWith("NEF")?0xb103:0x3801).filename(name).compressedSize(size).imagePixWidth(6000).imagePixHeight(4000).captureDate("20261112T200000").build());}
        void event(long handle){if(listener!=null)listener.accept(handle);}
        public byte[] connect(String h,int p,byte[] g,String n){open=true;return info(fuji);}
        public boolean isOpen(){return open;}public boolean isProtocolUnconfirmed(){return false;}public String closeReason(){return "";}public String connectedHost(){return "192.168.1.1";}public int connectedPort(){return 15740;}public String cameraIdentity(){return identity;}
        public void setOnClosed(Runnable r){}public void setOnObjectAdded(LongConsumer r){listener=r;}public byte[] readAlbumDeviceInfo(){return info(fuji);}
        public byte[] getData(int op,int max,long...p)throws IOException{
            calls++;
            if(op==0x1004)return concat(le32(2),le32(1),le32(2));
            if(op==0x1007){if(p[0]==2&&!cardTwo)throw new PtpResponseException(0x2013,1);List<Long> ids=new ArrayList<>();for(Map.Entry<Long,PtpObjectInfo> e:objects.entrySet())if(e.getValue().storageId()==p[0]&&(p[1]==0||e.getValue().objectFormat()==p[1]))ids.add(e.getKey());ByteArrayOutputStream out=new ByteArrayOutputStream();out.writeBytes(le32(ids.size()));for(long id:ids)out.writeBytes(le32(id));return out.toByteArray();}
            if(op==0x1008){metadata++;PtpObjectInfo value=objects.get(p[0]);if(value==null)throw new PtpResponseException(0x2009,1);return value.toBytes();}
            throw new IOException("Unexpected discovery operation "+op);
        }
        public byte[] getLargeThumbnail(long handle){return jpeg;}
        public long readTo(int op,OutputStream out,long max,long expected,Progress progress,long...p)throws IOException{originals++;progress.onProgress(0,jpeg.length);out.write(jpeg);progress.onProgress(jpeg.length,jpeg.length);return jpeg.length;}
        public void abortProtocol(IOException e){open=false;}public void close(){open=false;listener=null;}
    }
    private static byte[] info(boolean fuji){int[] operations={0x1001,0x1002,0x1003,0x1004,0x1007,0x1008,0x1009,0x100a,0x90c4};ByteArrayOutputStream ops=new ByteArrayOutputStream();ops.writeBytes(le32(operations.length));for(int op:operations)ops.writeBytes(le16(op));return concat(le16(100),le32(fuji?14:10),le16(100),string("Fixture"),le16(0),ops.toByteArray(),le32(0),le32(0),le32(0),le32(0),string(fuji?"FUJIFILM":"NIKON CORPORATION"),string(fuji?"X-T20":"Z 6_2"),string("1"),string(""));}
    private static byte[] string(String text){return text.isEmpty()?new byte[]{0}:concat(new byte[]{(byte)(text.length()+1)},(text+'\0').getBytes(StandardCharsets.UTF_16LE));}
    private static byte[] le16(long n){return new byte[]{(byte)n,(byte)(n>>>8)};}
    private static byte[] le32(long n){return new byte[]{(byte)n,(byte)(n>>>8),(byte)(n>>>16),(byte)(n>>>24)};}
    private static byte[] concat(byte[]...parts){ByteArrayOutputStream out=new ByteArrayOutputStream();for(byte[]part:parts)out.writeBytes(part);return out.toByteArray();}
}
