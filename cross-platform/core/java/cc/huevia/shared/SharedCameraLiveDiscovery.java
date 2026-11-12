package cc.huevia.shared;

import cc.huevia.album.PhotoCameraClient;
import cc.huevia.album.PhotoFormat;
import cc.huevia.ptp.PtpDeviceInfo;
import cc.huevia.ptp.PtpObjectHandles;
import cc.huevia.ptp.PtpObjectInfo;
import cc.huevia.ptp.PtpResponseException;
import cc.huevia.ptp.PtpStorageIds;
import java.io.IOException;
import java.io.InterruptedIOException;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashSet;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.function.BooleanSupplier;
import java.util.function.LongSupplier;

/** Worker-owned discovery only. Event callbacks enqueue bounded hints and never issue PTP I/O. */
final class SharedCameraLiveDiscovery {
    static final int MAX_HANDLES=20000,MAX_HINTS=512,MAX_PENDING=128;
    private static final long SCAN_NANOS=3000000000L,STABLE_NANOS=250000000L;
    private final PhotoCameraClient client;
    private final String session,cameraId,watchId=UUID.randomUUID().toString();
    private final boolean trusted;
    private final LongSupplier clock;
    private final Map<Long,Long> references=new LinkedHashMap<>();
    private final Map<Long,Baseline> baseline=new LinkedHashMap<>();
    private final Set<Long> initialized=new LinkedHashSet<>(),unavailable=new LinkedHashSet<>();
    private final LinkedHashSet<Long> hints=new LinkedHashSet<>(),inspect=new LinkedHashSet<>();
    private final Map<Long,Probe> probes=new LinkedHashMap<>();
    private final Map<Long,Ready> ready=new LinkedHashMap<>();
    private final Map<Long,String> acknowledged=new LinkedHashMap<>();
    private final Map<Long,String> restored=new LinkedHashMap<>();
    private final List<Object> updates=new ArrayList<>(),removed=new ArrayList<>();
    private final Map<String,Object> unavailableObjects=new LinkedHashMap<>();
    private long lastScan;
    private int idleCursor,offerCursor;
    private volatile boolean stopped;
    private static final class Baseline {
        final long storage;String key;
        Baseline(long storage,String key){this.storage=storage;this.key=key;}
    }
    private static final class Probe {
        final String key;final long at;
        Probe(String key,long at){this.key=key;this.at=at;}
    }
    private static final class Ready {
        final String key;final PtpObjectInfo info;
        Ready(String key,PtpObjectInfo info){this.key=key;this.info=info;}
    }
    SharedCameraLiveDiscovery(PhotoCameraClient client,PtpDeviceInfo device,String session,LongSupplier clock){
        this.client=client;this.session=session;this.clock=clock;trusted=trusted(client);cameraId=cameraId(client,device,session);
    }
    static boolean trusted(PhotoCameraClient client){String id=client.cameraIdentity();return id!=null&&id.matches("[0-9a-fA-F]{32}")&&!id.matches("0+");}
    static String cameraId(PhotoCameraClient client,PtpDeviceInfo device,String session){
        String identity=trusted(client)?client.cameraIdentity().toLowerCase(java.util.Locale.ROOT):"session:"+session;
        return hash(("huevia-live-camera-v1\n"+identity+"\n"+device.manufacturer()+"\n"+device.model()).getBytes(StandardCharsets.UTF_8));
    }
    Map<String,Object> start(Map<String,Object> p,BooleanSupplier cancel)throws IOException{
        check(cancel);
        if(p.containsKey("cameraId")&&!cameraId.equals(p.get("cameraId")))throw new IOException("相机身份已改变，未开始边拍边传。");
        Object cursor=p.get("cursor");
        if(cursor!=null){
            if(!trusted||!cameraId.equals(p.get("cameraId")))throw new IOException("相机身份未确认，不能继续旧边拍边传记录。");
            if(!(cursor instanceof Map))throw new IOException("边拍边传基线无效。");
            restore((Map<?,?>)cursor);
        }
        client.setOnObjectAdded(this::hint);
        try{
            scan(cancel,cursor==null);
            if(unavailable.size()>0&&references.isEmpty())throw new IOException("相机存储卡暂不可读取，请确认存储卡后重试。");
            if(cursor!=null)for(long handle:restored.keySet())enqueue(handle);
            return SharedRuntime.map("session",session,"watchId",watchId,"cameraId",cameraId,"trustedCamera",trusted,"cursor",cursor(),"unavailableStorages",unavailable.size());
        }catch(IOException|RuntimeException failure){stop();throw failure;}
    }
    private void restore(Map<?,?> cursor)throws IOException{
        Object rows=cursor.get("baseline"),storages=cursor.get("initializedStorages"),pending=cursor.get("pending");
        if(!(rows instanceof List)||((List<?>)rows).size()>4096||!(storages instanceof List)||((List<?>)storages).size()>256)throw new IOException("边拍边传基线超出范围。");
        List<Object> complete=new ArrayList<>((List<?>)rows);Object pages=cursor.get("baselinePages");
        if(pages!=null){
            if(!(pages instanceof List)||((List<?>)pages).size()>20)throw new IOException("边拍边传基线分页无效。");
            for(Object page:(List<?>)pages){if(!(page instanceof List)||((List<?>)page).size()>1000)throw new IOException("边拍边传基线分页无效。");complete.addAll((List<?>)page);if(complete.size()>MAX_HANDLES)throw new IOException("边拍边传基线超出范围。");}
        }
        for(Object value:(List<?>)storages){long storage=id(value);if(!initialized.add(storage))throw new IOException("边拍边传存储卡基线重复。");}
        for(Object value:complete){
            if(!(value instanceof Map))throw new IOException("边拍边传基线无效。");Map<?,?> row=(Map<?,?>)value;
            long handle=id(row.get("handle")),storage=id(row.get("storage"));String key=optionalKey(row.get("objectKey"));
            if(!initialized.contains(storage)||baseline.put(handle,new Baseline(storage,key))!=null)throw new IOException("边拍边传基线重复或存储卡无效。");
        }
        if(pending!=null){
            if(!(pending instanceof List)||((List<?>)pending).size()>MAX_PENDING)throw new IOException("待接收照片数量超出范围。");
            for(Object value:(List<?>)pending){
                if(!(value instanceof Map))throw new IOException("待接收照片记录无效。");Map<?,?> row=(Map<?,?>)value;
                long handle=id(row.get("handle")),storage=id(row.get("storage"));String key=requiredKey(row.get("objectKey"));
                if(!initialized.contains(storage)||restored.put(handle,key)!=null)throw new IOException("待接收照片记录重复或存储卡无效。");
            }
        }
    }
    Map<String,Object> poll(Map<String,Object> p,BooleanSupplier cancel)throws IOException{
        require(p);check(cancel);int limit=SharedRuntime.integer(p,"limit",12);if(limit<1||limit>60)throw new IOException("边拍边传读取数量无效。");
        updates.clear();removed.clear();
        List<Long> events;
        synchronized(hints){events=new ArrayList<>(hints);hints.clear();}
        boolean unknown=false;for(long handle:events)if(!references.containsKey(handle))unknown=true;
        long now=clock.getAsLong();
        if(unknown||now-lastScan>=SCAN_NANOS)scan(cancel,false);
        for(long handle:events)if(references.containsKey(handle))enqueue(handle);
        for(long handle:references.keySet())if(!baseline.containsKey(handle)&&!acknowledged.containsKey(handle)&&!ready.containsKey(handle)&&!unavailable.contains(references.get(handle)))enqueue(handle);
        // Descriptor sampling of old handles is low priority, matching the original controller.
        if(inspect.isEmpty()&&!references.isEmpty()){
            List<Long> keys=new ArrayList<>(references.keySet());long handle=keys.get(idleCursor%keys.size());idleCursor=(idleCursor+1)%keys.size();enqueue(handle);
        }
        List<Long> work=new ArrayList<>(inspect);int reads=0;
        client.beginPhotoPage();try{
            for(long handle:work){
                if(reads>=limit)break;
                if(!ready.containsKey(handle)&&!restored.containsKey(handle)&&outstanding()>=MAX_PENDING)continue;
                check(cancel);Long storage=references.get(handle);
                if(storage==null){inspect.remove(handle);continue;}
                if(unavailable.contains(storage))continue;
                Probe previous=probes.get(handle);if(previous!=null&&now-previous.at<STABLE_NANOS)continue;
                inspect.remove(handle);reads++;inspect(handle,storage,now,cancel);
            }
        }finally{client.endPhotoPage();}
        List<Object> items=new ArrayList<>();List<Long> keys=new ArrayList<>(ready.keySet());
        for(int i=0;i<keys.size()&&items.size()<limit;i++){
            long handle=keys.get((offerCursor+i)%keys.size());Ready value=ready.get(handle);
            if(unavailable.contains(value.info.storageId()))continue;
            items.add(row(handle,value));
        }
        if(!keys.isEmpty())offerCursor=(offerCursor+Math.max(1,items.size()))%keys.size();
        Map<String,Object> result=SharedRuntime.map("session",session,"watchId",watchId,"cameraId",cameraId,"items",items,"baselineUpdates",new ArrayList<>(updates.subList(0,Math.min(1000,updates.size()))),"baselineRemoved",new ArrayList<>(removed.subList(0,Math.min(1000,removed.size()))),"initializedStorages",new ArrayList<>(initialized),"unavailable",new ArrayList<>(unavailableObjects.values()),"unavailableStorages",unavailable.size(),"pending",ready.size(),"inspecting",inspect.size(),"totalHandles",references.size());
        if(updates.size()>1000||removed.size()>1000)result.put("cursor",cursor());
        unavailableObjects.clear();return result;
    }
    private void inspect(long handle,long storage,long now,BooleanSupplier cancel)throws IOException{
        PtpObjectInfo info;
        try{info=PtpObjectInfo.parse(client.getData(0x1008,65536,handle));}
        catch(PtpResponseException failure){
            if(failure.responseCode()==0x2009){markUnavailable(handle,"missing");ready.remove(handle);probes.remove(handle);return;}
            if(failure.responseCode()==0x2002||failure.responseCode()==0x2019||failure.responseCode()==0x2013){enqueue(handle);return;}
            throw failure;
        }
        check(cancel);if(info.storageId()!=storage)throw new IOException("照片存储位置与边拍边传索引不一致。");
        String key=objectKey(cameraId,handle,info);String expected=restored.get(handle);
        if(expected!=null&&!expected.equals(key))markUnavailable(handle,"changed");
        Ready previousReady=ready.get(handle);if(previousReady!=null&&!previousReady.key.equals(key))markUnavailable(handle,"changed");
        if(SharedCamera.photoFormat(info)!=PhotoFormat.JPEG){acknowledged.put(handle,key);ready.remove(handle);return;}
        Baseline old=baseline.get(handle);
        if(old!=null&&expected==null){
            if(old.key.isEmpty()){old.key=key;updates.add(baselineRow(handle,old));return;}
            if(old.key.equals(key)){ready.remove(handle);return;}
        }
        if(key.equals(acknowledged.get(handle))){ready.remove(handle);return;}
        if(info.compressedSize()<4||info.compressedSize()>512L*1024*1024||info.imagePixWidth()<1||info.imagePixHeight()<1){ready.remove(handle);probes.remove(handle);enqueue(handle);return;}
        Ready offered=ready.get(handle);if(offered!=null&&offered.key.equals(key))return;
        Probe previous=probes.get(handle);
        if(previous==null||!previous.key.equals(key)){probes.put(handle,new Probe(key,now));ready.remove(handle);enqueue(handle);return;}
        if(now-previous.at<STABLE_NANOS){enqueue(handle);return;}
        ready.put(handle,new Ready(key,info));probes.remove(handle);restored.remove(handle);
    }
    private void markUnavailable(long handle,String reason)throws IOException{
        String restoredKey=restored.get(handle);Ready offered=ready.get(handle);Set<String> keys=new LinkedHashSet<>();
        if(restoredKey!=null)keys.add(restoredKey);if(offered!=null)keys.add(offered.key);
        int additions=0;for(String key:keys)if(!unavailableObjects.containsKey(key))additions++;
        if(unavailableObjects.size()+additions>MAX_PENDING)throw new IOException("相机照片变化记录已满，请先读取当前收片状态。");
        restored.remove(handle);ready.remove(handle);probes.remove(handle);
        for(String key:keys)unavailableObjects.put(key,SharedRuntime.map("objectKey",key,"reason",reason));
    }
    private int outstanding(){Set<Long> handles=new HashSet<>(ready.keySet());handles.addAll(restored.keySet());return handles.size();}
    private void scan(BooleanSupplier cancel,boolean fresh)throws IOException{
        check(cancel);
        long[] storages=PtpStorageIds.parse(client.getData(0x1004,4096));if(storages.length>64)throw new IOException("边拍边传存储空间数量过多。");
        Map<Long,Long> next=new LinkedHashMap<>();Set<Long> available=new LinkedHashSet<>(),missing=new LinkedHashSet<>();
        for(long storage:storages){
            check(cancel);id(storage);long[] values;
            try{
                boolean filtered=true;
                try{values=PtpObjectHandles.parse(client.getData(0x1007,1024*1024,storage,0x3801,0));}
                catch(PtpResponseException unsupported){if(unsupported.responseCode()!=0x2014)throw unsupported;filtered=false;values=PtpObjectHandles.parse(client.getData(0x1007,1024*1024,storage,0,0));}
                if(filtered&&values.length==0)values=PtpObjectHandles.parse(client.getData(0x1007,1024*1024,storage,0,0));
            }catch(PtpResponseException failure){if(failure.responseCode()==0x2013){missing.add(storage);continue;}throw failure;}
            available.add(storage);
            for(long handle:values){id(handle);Long other=next.put(handle,storage);if(other!=null&&other.longValue()!=storage)throw new IOException("不同存储卡返回重复边拍边传索引。");if(next.size()>MAX_HANDLES)throw new IOException("边拍边传最多读取 20000 个对象。");}
        }
        // Missing/unreadable cards retain old references; their recovery cannot import old pictures.
        for(Map.Entry<Long,Long> entry:references.entrySet())if(!available.contains(entry.getValue())){missing.add(entry.getValue());Long other=next.putIfAbsent(entry.getKey(),entry.getValue());if(other!=null&&!other.equals(entry.getValue()))throw new IOException("不同存储卡返回重复边拍边传索引。");}
        if(next.size()>MAX_HANDLES)throw new IOException("边拍边传最多读取 20000 个对象。");
        for(Map.Entry<Long,Baseline> entry:new ArrayList<>(baseline.entrySet())){
            if(available.contains(entry.getValue().storage)&&!Long.valueOf(entry.getValue().storage).equals(next.get(entry.getKey()))){removed.add(SharedRuntime.map("handle",entry.getKey(),"storage",entry.getValue().storage));baseline.remove(entry.getKey());acknowledged.remove(entry.getKey());probes.remove(entry.getKey());ready.remove(entry.getKey());markUnavailable(entry.getKey(),"missing");}
        }
        for(Map.Entry<Long,Long> entry:next.entrySet())if(fresh||!initialized.contains(entry.getValue())&&available.contains(entry.getValue())){
            Baseline value=new Baseline(entry.getValue(),"");baseline.put(entry.getKey(),value);updates.add(baselineRow(entry.getKey(),value));
        }
        for(long handle:new ArrayList<>(restored.keySet()))if(!next.containsKey(handle))markUnavailable(handle,"missing");
        for(long handle:new ArrayList<>(ready.keySet()))if(!next.containsKey(handle))markUnavailable(handle,"missing");
        initialized.addAll(available);if(initialized.size()>256)throw new IOException("边拍边传存储卡历史数量过多。");
        references.clear();references.putAll(next);unavailable.clear();unavailable.addAll(missing);
        acknowledged.keySet().retainAll(next.keySet());probes.keySet().retainAll(next.keySet());ready.keySet().retainAll(next.keySet());inspect.retainAll(next.keySet());lastScan=clock.getAsLong();
    }
    Map<String,Object> ack(Map<String,Object> p)throws IOException{
        require(p);String key=requiredKey(p.get("objectKey"));
        for(Iterator<Map.Entry<Long,Ready>> it=ready.entrySet().iterator();it.hasNext();){Map.Entry<Long,Ready> entry=it.next();if(entry.getValue().key.equals(key)){acknowledged.put(entry.getKey(),key);it.remove();return SharedRuntime.map("acknowledged",true);}}
        return SharedRuntime.map("acknowledged",false);
    }
    PtpObjectInfo authorize(Map<String,Object> p,long handle)throws IOException{
        require(p);String key=requiredKey(p.get("objectKey"));Ready candidate=ready.get(handle);
        if(candidate==null||!candidate.key.equals(key))throw new IOException("边拍边传照片已改变或未确认，未下载。");return candidate.info;
    }
    void invalidate(long handle)throws IOException{markUnavailable(handle,"changed");enqueue(handle);}
    void missing(long handle)throws IOException{markUnavailable(handle,"missing");}
    Map<String,Object> cursor(){
        List<Object> rows=new ArrayList<>();for(Map.Entry<Long,Baseline> entry:baseline.entrySet())rows.add(baselineRow(entry.getKey(),entry.getValue()));
        List<Object> first=new ArrayList<>(rows.subList(0,Math.min(1000,rows.size()))),pages=new ArrayList<>();
        for(int offset=1000;offset<rows.size();offset+=1000)pages.add(new ArrayList<>(rows.subList(offset,Math.min(offset+1000,rows.size()))));
        Map<String,Object> value=SharedRuntime.map("baseline",first,"baselineCount",rows.size(),"initializedStorages",new ArrayList<>(initialized));if(!pages.isEmpty())value.put("baselinePages",pages);return value;
    }
    void require(Map<String,Object> p)throws IOException{if(stopped||!watchId.equals(p.get("watchId")))throw new IOException("边拍边传会话已改变，请重新开始。");}
    void stop(){stopped=true;client.setOnObjectAdded(null);synchronized(hints){hints.clear();}inspect.clear();ready.clear();probes.clear();}
    String cameraId(){return cameraId;}
    String watchId(){return watchId;}
    private void hint(long handle){if(handle<1||handle>=0xffffffffL)return;synchronized(hints){if(!stopped&&hints.size()<MAX_HINTS)hints.add(handle);}}
    private void enqueue(long handle){if(inspect.size()<MAX_HINTS)inspect.add(handle);}
    private static Map<String,Object> baselineRow(long handle,Baseline row){Map<String,Object> value=SharedRuntime.map("storage",row.storage,"handle",handle);if(!row.key.isEmpty())value.put("objectKey",row.key);return value;}
    private static Map<String,Object> row(long handle,Ready value){PtpObjectInfo info=value.info;return SharedRuntime.map("objectKey",value.key,"storage",info.storageId(),"handle",handle,"name",info.filename(),"bytes",info.compressedSize(),"width",info.imagePixWidth(),"height",info.imagePixHeight(),"capturedAt",info.captureDate(),"raw",false);}
    static String objectKey(String camera,long handle,PtpObjectInfo info){MessageDigest digest=digest();digest.update((camera+"\n"+info.storageId()+"\n"+handle+"\n").getBytes(StandardCharsets.UTF_8));digest.update(info.toBytes());return hex(digest.digest());}
    private static long id(Object value)throws IOException{if(!(value instanceof Number)||((Number)value).doubleValue()!=((Number)value).longValue()||((Number)value).longValue()<1||((Number)value).longValue()>=0xffffffffL)throw new IOException("边拍边传照片或存储卡索引无效。");return ((Number)value).longValue();}
    private static String optionalKey(Object value)throws IOException{if(value==null)return "";return requiredKey(value);}
    private static String requiredKey(Object value)throws IOException{if(!(value instanceof String)||!((String)value).matches("[0-9a-f]{64}"))throw new IOException("边拍边传照片标识无效。");return (String)value;}
    private static void check(BooleanSupplier cancel)throws IOException{if(cancel.getAsBoolean())throw new InterruptedIOException("边拍边传读取已停止。");}
    private static String hash(byte[] value){return hex(digest().digest(value));}
    private static MessageDigest digest(){try{return MessageDigest.getInstance("SHA-256");}catch(NoSuchAlgorithmException impossible){throw new AssertionError(impossible);}}
    private static String hex(byte[] value){StringBuilder text=new StringBuilder(value.length*2);for(byte b:value)text.append(String.format(java.util.Locale.ROOT,"%02x",b&255));return text.toString();}
}
