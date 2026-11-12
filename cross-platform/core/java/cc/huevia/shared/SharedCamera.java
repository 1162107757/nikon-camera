package cc.huevia.shared;

import cc.huevia.album.*;
import cc.huevia.library.SharedJson;
import cc.huevia.ptp.*;
import java.io.*;
import java.nio.file.*;
import java.security.*;
import java.util.*;
import java.util.function.*;

/** Shared read-only Wi-Fi session. Handles are scoped to the connection that enumerated them. */
public final class SharedCamera {
    public interface Connectors { PtpIpClient.SocketConnector create(String host,int port,boolean fuji)throws IOException; }
    interface Clients { PhotoCameraClient create(PtpIpClient.SocketConnector connector,boolean fuji); }
    private final File root;
    private final Connectors connectors;
    private final Clients clients;
    private final SharedCameraPreviews previews;
    private final LongSupplier clock;
    private SharedCameraLiveDiscovery live;
    private volatile PhotoCameraClient client;
    private volatile String activeJob="";
    private String session="";
    private PtpDeviceInfo device;
    private boolean largeThumbnailUnavailable;
    private boolean indexedRaw,indexReady;
    private int unavailableStorages;
    private final List<Long> handles=new ArrayList<>();
    private final Map<Long,PtpObjectInfo> observed=new LinkedHashMap<>();
    public SharedCamera(String root,Connectors connectors)throws IOException{this(root,connectors,(connector,fuji)->fuji?new FujifilmPhotoClient(connector):new PtpIpClient(connector));ConnectionTrace.configure(new File(this.root,"camera-trace.log"));}
    SharedCamera(String root,Connectors connectors,Clients clients)throws IOException{this(root,connectors,clients,System::nanoTime);}
    SharedCamera(String root,Connectors connectors,Clients clients,LongSupplier clock)throws IOException{this.root=new File(root).getCanonicalFile();this.connectors=connectors;this.clients=clients;this.clock=clock;previews=new SharedCameraPreviews(this.root);}
    public void cancel(String job){if(job!=null&&job.equals(activeJob))closeTransport();}
    /** Can run from the host lifecycle thread without changing worker-owned indexes. */
    public void closeTransport(){PhotoCameraClient current=client;if(current!=null)current.close();}
    public synchronized String request(String operation,String json,String job,BooleanSupplier cancel,DoubleConsumer progress)throws IOException{
        activeJob=job;
        String stage=operation.equals("camera.connect")?"SHARED_CONNECT":operation.equals("camera.page")?"SHARED_PHOTO_PAGE":operation.equals("camera.thumbnail")?"SHARED_THUMBNAIL":operation.equals("camera.download")?"SHARED_DOWNLOAD":"SHARED_CAMERA_REQUEST";
        boolean traced=operation.equals("camera.connect")||operation.equals("camera.page")||operation.equals("camera.download")||operation.equals("camera.thumbnail");
        if(traced)ConnectionTrace.mark(stage+"_BEGIN");
        try{String result=SharedJson.encode(execute(operation,SharedJson.object(json),cancel,progress));if(traced)ConnectionTrace.mark(stage+"_COMPLETE");return result;}
        catch(IOException|RuntimeException failure){if(traced)ConnectionTrace.mark(stage+"_FAILED");throw failure;}
        finally{activeJob="";}
    }
    private Object execute(String operation,Map<String,Object> p,BooleanSupplier cancel,DoubleConsumer progress)throws IOException{
        if(operation.equals("camera.diagnostics"))return SharedRuntime.map("connected",client!=null&&client.isOpen(),"totalHandles",handles.size(),"observedObjects",observed.size(),"trace",ConnectionTrace.snapshot());
        if(operation.equals("camera.disconnect")){disconnect();return SharedRuntime.map("connected",false);}
        if(operation.equals("camera.connect")){
            disconnect();String host=SharedRuntime.text(p,"host",253);int port=SharedRuntime.integer(p,"port",15740);
            if(host.isEmpty()||port<1||port>65535)throw new IOException("相机地址或端口无效。");
            String protocol=SharedRuntime.text(p,"protocol",32);if(!protocol.equals("nikon")&&!protocol.equals("fujifilm"))throw new IOException("请选择受支持的相机协议。");
            boolean fuji=protocol.equals("fujifilm");PtpIpClient.SocketConnector connector=connectors.create(host,port,fuji);
            PhotoCameraClient next=clients.create(connector,fuji);client=next;
            try{
                byte[] guid=guid();device=PtpDeviceInfo.parseRedacted(next.connect(host,port,guid,"Huevia"));
                if(!fuji&&!device.isNikonCamera())throw new IOException("相机未确认尼康协议身份。");
                for(int op:new int[]{0x1004,0x1007,0x1008,0x1009})if(!device.supportsOperation(op))throw new IOException("相机未提供照片读取能力。");
                session=UUID.randomUUID().toString();largeThumbnailUnavailable=false;inventory(cancel,false);return status();
            }catch(IOException|RuntimeException failure){next.close();client=null;session="";throw failure;}
        }
        if(operation.equals("camera.status"))return status();
        require(p);PhotoCameraClient current=client;
        if(operation.equals("camera.live.start")){
            if(!device.isNikonCamera())throw new IOException("富士 X-T20 的无线模式暂不支持边拍边传，请拍摄后手动接收。");
            if(live!=null)throw new IOException("边拍边传已开启，请先停止当前拍摄项目。");
            SharedCameraLiveDiscovery next=new SharedCameraLiveDiscovery(current,device,session,clock);
            Map<String,Object> result=next.start(p,cancel);live=next;return result;
        }
        if(operation.startsWith("camera.live.")){
            if(live==null)throw new IOException("边拍边传尚未开启。");
            if(operation.equals("camera.live.poll"))return live.poll(p,cancel);
            if(operation.equals("camera.live.ack"))return live.ack(p);
            if(operation.equals("camera.live.stop")){live.require(p);live.stop();live=null;return SharedRuntime.map("stopped",true);}
            throw new IOException("未知的边拍边传操作。");
        }
        if(operation.equals("camera.page")){
            int offset=SharedRuntime.integer(p,"offset",0),limit=SharedRuntime.integer(p,"limit",24);
            boolean raw=Boolean.TRUE.equals(p.get("raw")),refresh=Boolean.TRUE.equals(p.get("refresh"));
            if(refresh||!indexReady||indexedRaw!=raw){if(offset!=0)throw new IOException("刷新或切换相机格式须从第一页开始。");inventory(cancel,raw);}
            if(offset<0||offset>handles.size()||limit<1||limit>60)throw new IOException("相机分页参数无效。");
            List<Object> rows=new ArrayList<>();int cursor=offset,scanned=0;
            current.beginPhotoPage();try{
                while(cursor<handles.size()&&rows.size()<limit&&scanned++<300){check(cancel);long handle=handles.get(cursor++);PtpObjectInfo info;
                    try{info=PtpObjectInfo.parse(current.getData(0x1008,65536,handle));}catch(PtpResponseException gone){if(gone.responseCode()==0x2009)continue;throw gone;}
                    PhotoFormat format=photoFormat(info);if(format!=(raw?PhotoFormat.NEF:PhotoFormat.JPEG))continue;
                    observed.put(handle,info);rows.add(row(handle,info));
                }
            }finally{current.endPhotoPage();}
            return SharedRuntime.map("session",session,"items",rows,"nextOffset",cursor,"hasMore",cursor<handles.size(),"totalHandles",handles.size(),"unavailableStorages",unavailableStorages);
        }
        if(operation.equals("camera.thumbnail")){
            check(cancel);long handle=number(p,"handle");PtpObjectInfo info=observed.get(handle);
            if(info==null)throw new IOException("照片不属于当前浏览会话。");
            String key=previews.key(session,handle,info.toBytes());File cached=Boolean.TRUE.equals(p.get("refresh"))?null:previews.cached(key);
            if(cached!=null)return SharedRuntime.map("session",session,"handle",handle,"path",cached.getPath());
            same(info,PtpObjectInfo.parse(current.getData(0x1008,65536,handle)));check(cancel);
            byte[] jpeg=null;
            if(device.isNikonCamera()&&device.supportsOperation(0x90c4)&&!largeThumbnailUnavailable){
                try{jpeg=current.getLargeThumbnail(handle);}
                catch(PtpResponseException unsupported){int code=unsupported.responseCode();if(code!=0x2005&&code!=0x2010)throw unsupported;if(code==0x2005)largeThumbnailUnavailable=true;}
            }
            if(jpeg==null){check(cancel);if(!device.supportsOperation(0x100a))throw new IOException("相机未提供缩略图，可接收原文件后查看。");jpeg=current.getData(0x100a,8*1024*1024,handle);}
            check(cancel);same(info,PtpObjectInfo.parse(current.getData(0x1008,65536,handle)));check(cancel);
            File preview=previews.store(key,jpeg,cancel);return SharedRuntime.map("session",session,"handle",handle,"path",preview.getPath());
        }
        if(operation.equals("camera.download")){
            long handle=number(p,"handle");boolean liveDownload=p.containsKey("objectKey")||p.containsKey("watchId");
            PtpObjectInfo before=liveDownload?(live==null?null:live.authorize(p,handle)):observed.get(handle);
            if(before==null)throw new IOException("照片不属于当前浏览会话。");
            PhotoFormat format=photoFormat(before);if(format==PhotoFormat.NEF&&!Boolean.TRUE.equals(p.get("raw")))throw new IOException("请明确选择下载 RAW 原文件。");
            if(before.compressedSize()<4||before.compressedSize()>512L*1024*1024)throw new IOException("相机照片大小超出范围。");
            PtpObjectInfo fresh=downloadInfo(current,handle,liveDownload);
            try{same(before,fresh);}catch(IOException changed){if(liveDownload)live.invalidate(handle);throw changed;}
            File directory=new File(root,"originals");if(!directory.isDirectory()&&!directory.mkdirs())throw new IOException("无法创建照片目录。");
            File temporary=File.createTempFile("camera-",".part",directory);MessageDigest digest;
            try{digest=MessageDigest.getInstance("SHA-256");}catch(NoSuchAlgorithmException impossible){throw new AssertionError(impossible);}
            try{
                try(FileOutputStream output=new FileOutputStream(temporary);OutputStream bytes=new BufferedOutputStream(new DigestOutputStream(output,digest),65536)){
                    try{current.readTo(0x1009,bytes,512L*1024*1024,before.compressedSize(),(received,total)->{
                        if(total!=before.compressedSize()||received<0||received>total){current.close();throw new TransferSizeChanged();}
                        if(cancel.getAsBoolean())current.close();progress.accept(received/(double)total);
                    },handle);}catch(TransferSizeChanged changed){throw new IOException("相机文件大小已变化，请刷新目录后重试。",changed);}
                    bytes.flush();output.getFD().sync();
                }
                check(cancel);if(temporary.length()!=before.compressedSize())throw new IOException("原文件接收不完整。");
                PtpObjectInfo after=downloadInfo(current,handle,liveDownload);
                try{same(before,after);}catch(IOException changed){if(liveDownload)live.invalidate(handle);throw changed;}
                if(format==PhotoFormat.NEF)PhotoFormat.validateNef(temporary,before.compressedSize());else validateJpeg(temporary);
                StringBuilder hash=new StringBuilder();for(byte value:digest.digest())hash.append(String.format(Locale.ROOT,"%02x",value&255));
                check(cancel);File target=new File(directory,hash+(format==PhotoFormat.NEF?".nef":".jpg"));
                if(target.exists()){if(!sameBytes(temporary,target))throw new IOException("已有原文件校验失败。");}else Files.move(temporary.toPath(),target.toPath(),StandardCopyOption.ATOMIC_MOVE);
                Map<String,Object> result=SharedRuntime.map("path",target.getPath(),"name",before.filename(),"sha256",hash.toString(),"bytes",target.length(),"raw",format==PhotoFormat.NEF);
                if(liveDownload){result.put("cameraId",live.cameraId());result.put("watchId",live.watchId());result.put("session",session);result.put("objectKey",p.get("objectKey"));result.put("storage",before.storageId());result.put("handle",handle);}
                return result;
            }finally{Files.deleteIfExists(temporary.toPath());}
        }
        throw new IOException("未知的相机操作。");
    }
    private void inventory(BooleanSupplier cancel,boolean raw)throws IOException{
        ConnectionTrace.mark("SHARED_INVENTORY_BEGIN");
        long[] storages=PtpStorageIds.parse(client.getData(0x1004,4096));if(storages.length>64)throw new IOException("相机存储空间数量过多。");Set<Long> unique=new LinkedHashSet<>();int unavailable=0;
        for(long storage:storages){check(cancel);long[] values;
            try{
                if(raw)values=PtpObjectHandles.parse(client.getData(0x1007,1024*1024,storage,0,0));
                else{
                    boolean filtered=true;
                    try{values=PtpObjectHandles.parse(client.getData(0x1007,1024*1024,storage,0x3801,0));}
                    catch(PtpResponseException unsupported){if(unsupported.responseCode()!=0x2014)throw unsupported;filtered=false;values=PtpObjectHandles.parse(client.getData(0x1007,1024*1024,storage,0,0));}
                    if(filtered&&values.length==0)values=PtpObjectHandles.parse(client.getData(0x1007,1024*1024,storage,0,0));
                }
            }catch(PtpResponseException error){if(error.responseCode()==0x2013){unavailable++;continue;}throw error;}
            for(long handle:values){if(handle==0||handle==0xffffffffL)throw new IOException("相机返回无效照片索引。");unique.add(handle);if(unique.size()>20000)throw new IOException("本版最多浏览 20000 个相机对象。");}}
        check(cancel);handles.clear();observed.clear();handles.addAll(unique);Collections.reverse(handles);
        indexedRaw=raw;indexReady=true;unavailableStorages=unavailable;
        ConnectionTrace.mark("SHARED_INVENTORY_COMPLETE");
    }
    private Object status(){boolean connected=client!=null&&client.isOpen();return SharedRuntime.map("connected",connected,"session",session,"model",device==null?"":device.model(),"manufacturer",device==null?"":device.manufacturer(),"totalHandles",handles.size(),"cameraId",connected&&device!=null?SharedCameraLiveDiscovery.cameraId(client,device,session):"","trustedCamera",connected&&SharedCameraLiveDiscovery.trusted(client),"supportsLive",connected&&device!=null&&device.isNikonCamera(),"live",live!=null);}
    private void require(Map<String,Object> p)throws IOException{if(client==null||!client.isOpen()||!session.equals(SharedRuntime.text(p,"session",64)))throw new IOException("相机会话已改变，请重新读取照片。");}
    public void disconnect(){if(live!=null){live.stop();live=null;}PhotoCameraClient current=client;client=null;if(current!=null)current.close();session="";device=null;handles.clear();observed.clear();indexReady=false;indexedRaw=false;unavailableStorages=0;}
    private static void check(BooleanSupplier cancel)throws IOException{if(cancel.getAsBoolean())throw new InterruptedIOException("相机操作已取消。");}
    private PtpObjectInfo downloadInfo(PhotoCameraClient current,long handle,boolean liveDownload)throws IOException{
        try{return PtpObjectInfo.parse(current.getData(0x1008,65536,handle));}
        catch(PtpResponseException failure){if(liveDownload&&failure.responseCode()==0x2009)live.missing(handle);throw failure;}
    }
    private byte[] guid()throws IOException{File file=new File(root,"camera-client-guid.bin");if(file.isFile()){byte[] value=Files.readAllBytes(file.toPath());if(value.length==16)return value;}byte[] value=new byte[16];new SecureRandom().nextBytes(value);Files.write(file.toPath(),value);return value;}
    private static long number(Map<String,Object> p,String key)throws IOException{Object value=p.get(key);if(!(value instanceof Number)||((Number)value).doubleValue()!=((Number)value).longValue()||((Number)value).longValue()<1||((Number)value).longValue()>=0xffffffffL)throw new IOException("相机照片索引无效。");return ((Number)value).longValue();}
    private static Object row(long handle,PtpObjectInfo info){return SharedRuntime.map("handle",handle,"name",info.filename(),"bytes",info.compressedSize(),"width",info.imagePixWidth(),"height",info.imagePixHeight(),"capturedAt",info.captureDate(),"raw",photoFormat(info)==PhotoFormat.NEF);}
    static PhotoFormat photoFormat(PtpObjectInfo info){PhotoFormat format=PhotoFormat.of(info);if(format!=PhotoFormat.OTHER||info.objectFormat()==0x3001||info.associationType()!=0)return format;String name=info.filename().toLowerCase(Locale.ROOT);return name.matches("[^/\\\\\\p{Cntrl}]+\\.(jpg|jpeg)")?PhotoFormat.JPEG:PhotoFormat.OTHER;}
    private static final class TransferSizeChanged extends RuntimeException {private static final long serialVersionUID=1L;}
    private static void same(PtpObjectInfo a,PtpObjectInfo b)throws IOException{if(!Arrays.equals(a.toBytes(),b.toBytes()))throw new IOException("相机原文件已发生变化，未接收。");}
    private static boolean sameBytes(File a,File b)throws IOException{if(a.length()!=b.length())return false;try(InputStream aa=new FileInputStream(a);InputStream bb=new FileInputStream(b)){byte[] x=new byte[65536],y=new byte[65536];while(true){int n=aa.read(x);if(n==-1)return bb.read()==-1;int off=0;while(off<n){int m=bb.read(y,off,n-off);if(m<1)return false;off+=m;}for(int i=0;i<n;i++)if(x[i]!=y[i])return false;}}}
    private static void validateJpeg(File file)throws IOException{try(RandomAccessFile input=new RandomAccessFile(file,"r")){if(input.readUnsignedShort()!=0xffd8)throw new IOException("相机原文件不是 JPEG。");input.seek(input.length()-2);if(input.readUnsignedShort()!=0xffd9)throw new IOException("相机 JPEG 原文件不完整。");}}
}
