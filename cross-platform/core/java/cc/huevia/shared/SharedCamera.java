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
    public interface WiredConnections {
        String devices()throws IOException;
        PhotoCameraClient create(String id)throws IOException;
        default SharedSlots.Transport openSlots(String id)throws IOException{throw new IOException("此设备未提供原始 PTP 优化校准通道。");}
    }
    private WiredConnections wired;
    private String transport="wifi";
    interface Clients { PhotoCameraClient create(PtpIpClient.SocketConnector connector,boolean fuji); }
    private final File root;
    private final Connectors connectors;
    private final Clients clients;
    private final SharedCameraPreviews previews;
    private final LongSupplier clock;
    private SharedCameraLiveDiscovery live;
    private SharedRemote remote;
    private volatile SharedSlots slots;
    private SharedCameraRawPairing rawPairing;
    private String slotsSession="",slotsHost="",slotsDevice="",slotsCameraId="",slotsTransport="";
    private int slotsPort;
    private volatile PhotoCameraClient client;
    private ActiveRequest activeRequest;
    private static final class ActiveRequest {
        final String job;final boolean transportWork;volatile boolean cancelled;boolean transportFinished;
        ActiveRequest(String job,String operation){this.job=job==null?"":job;transportWork=!operation.equals("camera.status")&&!operation.equals("camera.diagnostics")&&!operation.equals("camera.usb.devices")&&!operation.equals("camera.slots.status");}
    }
    // Only memory ownership transitions hold this lock; wire I/O and close run outside.
    private final Object transportOwnership=new Object();
    private volatile long transportRevision;
    private int transportsClosing;
    private String session="";
    private String downloadCameraId="";
    private boolean downloadTrusted;
    private List<Long> resolveHandles;
    private PtpDeviceInfo device;
    private boolean largeThumbnailUnavailable;
    private boolean indexedRaw,indexReady;
    private int unavailableStorages;
    private final List<Long> handles=new ArrayList<>();
    private final Map<Long,PtpObjectInfo> observed=new LinkedHashMap<>();
    public SharedCamera(String root,Connectors connectors)throws IOException{this(root,connectors,(connector,fuji)->fuji?new FujifilmPhotoClient(connector):new PtpIpClient(connector));ConnectionTrace.configure(new File(this.root,"camera-trace.log"));}
    public SharedCamera(String root,Connectors connectors,WiredConnections wired)throws IOException{this(root,connectors);this.wired=wired;}
    SharedCamera(String root,Connectors connectors,Clients clients)throws IOException{this(root,connectors,clients,System::nanoTime);}
    SharedCamera(String root,Connectors connectors,Clients clients,LongSupplier clock)throws IOException{this.root=new File(root).getCanonicalFile();this.connectors=connectors;this.clients=clients;this.clock=clock;previews=new SharedCameraPreviews(this.root);}
    public void cancel(String job){if(job!=null&&!job.isEmpty())abortTransport(job);}
    /** Can run from the host lifecycle thread without changing worker-owned indexes. */
    public void closeTransport(){abortTransport(null);}
    private void abortTransport(String expectedJob){
        PhotoCameraClient current;SharedSlots.Transport channel;
        synchronized(transportOwnership){
            ActiveRequest request=activeRequest;
            if(expectedJob!=null){
                if(request==null||!expectedJob.equals(request.job)||request.cancelled)return;
                request.cancelled=true;if(!request.transportWork||request.transportFinished)return;
            }else if(request!=null)request.cancelled=true;
            // Detach before closing so no later operation can reuse an in-flight owner.
            transportRevision++;current=client;client=null;channel=slots==null?null:slots.transportSnapshot();
            if(channel!=null)slots.detachTransport(channel);
            if(current!=null||channel!=null)transportsClosing++;
        }
        if(current==null&&channel==null)return;
        try{try{if(current!=null)current.close();}finally{if(channel!=null)channel.close();}}
        finally{synchronized(transportOwnership){transportsClosing--;transportOwnership.notifyAll();}}
    }
    public synchronized String request(String operation,String json,String job,BooleanSupplier cancel,DoubleConsumer progress)throws IOException{
        ActiveRequest request=new ActiveRequest(job,operation);
        synchronized(transportOwnership){
            // Native wired factories may return the same facade after its close completes.
            long deadline=System.nanoTime()+5_000_000_000L;
            while(transportsClosing>0){check(cancel);if(System.nanoTime()>=deadline)throw new java.net.SocketTimeoutException("等待上一相机通道关闭超时，请重试。");try{transportOwnership.wait(100);}catch(InterruptedException e){Thread.currentThread().interrupt();throw new InterruptedIOException("等待相机通道关闭已取消。");}}
            activeRequest=request;
        }
        BooleanSupplier stopped=()->cancel.getAsBoolean()||request.cancelled;
        String stage=operation.equals("camera.connect")?"SHARED_CONNECT":operation.equals("camera.page")?"SHARED_PHOTO_PAGE":operation.equals("camera.thumbnail")?"SHARED_THUMBNAIL":operation.equals("camera.download")?"SHARED_DOWNLOAD":"SHARED_CAMERA_REQUEST";
        boolean traced=operation.equals("camera.connect")||operation.equals("camera.page")||operation.equals("camera.download")||operation.equals("camera.thumbnail");
        if(traced)ConnectionTrace.mark(stage+"_BEGIN");
        try{Object value;try{value=execute(operation,SharedJson.object(json),stopped,progress);}finally{synchronized(transportOwnership){request.transportFinished=true;}}check(stopped);String result=SharedJson.encode(value);if(traced)ConnectionTrace.mark(stage+"_COMPLETE");return result;}
        catch(IOException|RuntimeException failure){if(traced)ConnectionTrace.mark(stage+"_FAILED");throw failure;}
        finally{synchronized(transportOwnership){if(activeRequest==request)activeRequest=null;}}
    }
    private Object execute(String operation,Map<String,Object> p,BooleanSupplier cancel,DoubleConsumer progress)throws IOException{
        if(operation.equals("camera.usb.devices")){if(wired==null)throw new IOException("本平台未提供 USB 相机接口。");return SharedJson.object(wired.devices());}
        if(operation.equals("camera.diagnostics"))return SharedRuntime.map("connected",client!=null&&client.isOpen(),"totalHandles",handles.size(),"observedObjects",observed.size(),"trace",ConnectionTrace.snapshot());
        if(operation.equals("camera.disconnect")){disconnect();return SharedRuntime.map("connected",false);}
        if(operation.equals("camera.connect")){
            String selected=SharedRuntime.text(p,"transport",16);boolean usb=selected.equals("usb");
            if(!selected.isEmpty()&&!selected.equals("wifi")&&!usb)throw new IOException("相机连接方式无效。");
            String host=usb?"usb":SharedRuntime.text(p,"host",253);int port=usb?0:SharedRuntime.integer(p,"port",15740);
            if(!usb&&(host.isEmpty()||port<1||port>65535))throw new IOException("相机地址或端口无效。");
            String protocol=SharedRuntime.text(p,"protocol",32);if(!protocol.equals("nikon")&&!protocol.equals("fujifilm")||usb&&!protocol.equals("nikon"))throw new IOException("请选择受支持的相机协议。");
            if(usb&&wired==null)throw new IOException("本平台未提供 USB 相机接口。");
            if(usb&&live!=null)throw new IOException("请先停止边拍边传，再切换为有线连接。");
            String usbId=usb?SharedRuntime.text(p,"deviceId",256):"";if(usb&&usbId.isEmpty())throw new IOException("请选择 USB 相机。");
            disconnect();boolean fuji=protocol.equals("fujifilm");transport=usb?"usb":"wifi";
            ConnectAttempt attempt=new ConnectAttempt(cancel,progress);PhotoCameraClient next=null;
            try{
                attempt.stage(usb?"等待外接相机授权":"检查相机 Wi-Fi 通道",.05);check(attempt);
                next=usb?wired.create(usbId):clients.create(connectors.create(host,port,fuji),fuji);attempt.owned=next;client=next;check(attempt);
                attempt.stage(usb?"打开外接相机会话并准备目录":"连接相机通道",usb?.4:.1);
                final int[] channels={0};
                next.setConnectionStageListener(stage->{
                    if(stage==PhotoCameraClient.ConnectionStage.WAITING_CONFIRMATION)attempt.stage("等待相机确认连接",.2);
                    else if(stage==PhotoCameraClient.ConnectionStage.READING_PHOTOS)attempt.stage("读取相机信息",.55);
                    else attempt.stage(channels[0]++==0?"连接相机通道":"建立事件通道与相机会话",channels[0]==1?.1:.4);
                });
                byte[] guid=guid(),info=next.connect(host,port,guid,"Huevia");device=PtpDeviceInfo.parseRedacted(info);
                check(attempt);attempt.stage("检查相机读取能力",.6);
                if(!fuji&&!device.isNikonCamera())throw new IOException("相机未确认尼康协议身份。");
                for(int op:new int[]{0x1004,0x1007,0x1008,0x1009})if(!device.supportsOperation(op))throw new IOException("相机未提供照片读取能力。");
                session=UUID.randomUUID().toString();PtpDeviceInfo identityInfo=device;
                try{identityInfo=PtpDeviceInfo.parse(info);}catch(PtpProtocolException optionalSerial){}
                downloadIdentity(next,identityInfo);resolveHandles=null;largeThumbnailUnavailable=false;
                attempt.stage("相机连接已建立",.7);check(attempt);
                progress.accept(1);return status();
            }catch(IOException|RuntimeException failure){if(next!=null)next.close();client=null;session="";attempt.rethrowIfStopped();throw failure;}
            finally{attempt.close();if(next!=null)next.setConnectionStageListener(null);}
        }
        if(operation.equals("camera.status"))return status();
        // Remote and Picture Control each own a separate, explicitly granted state machine.
        if(operation.equals("camera.slots.open"))return openSlots(p,cancel);
        if(operation.startsWith("camera.slots.")){
            if(slots==null)throw new IOException("预设槽位尚未读取。");
            if(operation.equals("camera.slots.close")){
                long revision=transportRevision;
                PhotoCameraClient album=slots.releaseAlbum(SharedRuntime.text(p,"session",64));
                Object closed=slots.request(operation,p,cancel);slots=null;
                if(restoreAlbum(album,revision,cancel))slotsSession="";return closed;
            }
            return slots.request(operation,p,cancel);
        }
        if(operation.equals("camera.remote.open")){
            require(p);if(live!=null)throw new IOException("请先停止边拍边传，再打开遥控拍摄。");
            if(remote!=null){remote.close();remote=null;}
            SharedRemote next=new SharedRemote(root);
            try{Object opened=next.open(client,device,session);remote=next;return opened;}
            catch(IOException|RuntimeException error){next.close();throw error;}
        }
        if(operation.startsWith("camera.remote.")){
            if(remote==null)throw new IOException("遥控会话尚未打开。");
            Object result=remote.request(operation,p,cancel);if(operation.equals("camera.remote.close"))remote=null;return result;
        }
        if(remote!=null)throw new IOException("遥控正在使用此会话，请返回相册后再操作。");
        require(p);PhotoCameraClient current=client;
        if(operation.equals("camera.resolve"))return resolve(p,cancel);
        if(operation.equals("camera.raw.pair")){
            if(live!=null)throw new IOException("请先停止边拍边传，再核对 RAW 原文件。");
            long handle=number(p,"handle");PtpObjectInfo jpeg=observed.get(handle);if(jpeg==null)throw new IOException("请从当前相机照片选择 JPEG。");
            SharedCameraRawPairing next=new SharedCameraRawPairing(current,session,downloadTrusted,downloadCameraId);
            Object result=next.open(handle,jpeg,cancel);rawPairing=next;return result;
        }
        if(operation.startsWith("camera.raw.")){
            if(rawPairing==null)throw new IOException("RAW 配对库存尚未读取。");
            if(operation.equals("camera.raw.page"))return rawPairing.page(p);
            if(operation.equals("camera.raw.select")){PtpObjectInfo selected=rawPairing.select(p,cancel);long handle=number(p,"handle");observed.put(handle,selected);return SharedRuntime.map("session",session,"item",SharedCameraRawPairing.row(handle,selected));}
            throw new IOException("未知的 RAW 配对操作。");
        }
        if(operation.equals("camera.live.start")){
            if(transport.equals("usb"))throw new IOException("有线连接请从相机照片中接收原文件，边拍边传请使用 Wi-Fi。");
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
            if(liveDownload&&p.containsKey("queueId"))throw new IOException("边拍边传与手动接收队列不能混用。");
            SharedDownloads.validateTransfer(root,p,downloadCameraId,downloadTrusted,session,before);
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
                result.put("downloadCameraId",downloadCameraId);result.put("downloadTrusted",downloadTrusted);result.put("descriptor",SharedCameraMutationStore.sha(before.toBytes()));result.put("storage",before.storageId());result.put("capturedAt",before.captureDate());
                if(liveDownload){result.put("cameraId",live.cameraId());result.put("watchId",live.watchId());result.put("session",session);result.put("objectKey",p.get("objectKey"));result.put("storage",before.storageId());result.put("handle",handle);}
                SharedDownloads.recordTransfer(root,p,result);
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
    private Object openSlots(Map<String,Object> p,BooleanSupplier cancel)throws IOException {
        String requested=SharedRuntime.text(p,"session",64);check(cancel);
        if(slots!=null&&slots.isConnected()){
            if(!slotsSession.equals(requested))throw new IOException("槽位会话已变化。");
            return slots.request("camera.slots.status",p,cancel);
        }
        PhotoCameraClient original=client;boolean photo=original!=null&&original.isOpen();
        if(photo){
            require(p);if(live!=null||remote!=null)throw new IOException("请先停止边拍边传或遥控，再读取预设槽位。");
            SharedSlots.requireReadCapabilities(device);
            slotsTransport=transport;slotsHost=original.connectedHost();slotsPort=original.connectedPort();
            slotsDevice=slotsTransport.equals("usb")?slotsHost.substring(slotsHost.indexOf(':')+1):"";
            slotsCameraId=downloadCameraId;
        }else if(slotsSession.isEmpty()||!slotsSession.equals(requested))throw new IOException("请先连接相机，再读取槽位。");
        if(slots==null)slots=new SharedSlots(root);else slots.close();
        slotsSession=requested;
        long revision=transportRevision;BooleanSupplier stopped=()->cancel.getAsBoolean()||revision!=transportRevision;
        String nextSession=UUID.randomUUID().toString();boolean adopted=false;SharedSlots.Transport dedicated=null;
        try{
            if(photo){
                if(slotsTransport.equals("wifi")&&original instanceof PtpIpClient){
                    // The original API only transfers ownership here; it sends no PTP packet.
                    synchronized(transportOwnership){check(stopped);dedicated=SharedSlots.fromAlbum((PtpIpClient)original);client=null;slots.stage(dedicated,nextSession,slotsCameraId);slotsSession=nextSession;adopted=true;}
                }else{synchronized(transportOwnership){check(stopped);client=null;}original.close();session="";}
                handles.clear();observed.clear();resolveHandles=null;indexReady=false;
            }
            check(stopped);
            if(dedicated==null)dedicated=slotsTransport.equals("usb")?wired.openSlots(slotsDevice):SharedSlots.wifi(connectors.create(slotsHost,slotsPort,false),slotsHost,slotsPort,guid());
            if(!adopted){synchronized(transportOwnership){check(stopped);slots.stage(dedicated,nextSession,slotsCameraId);slotsSession=nextSession;adopted=true;}}
            Object opened=slots.openStagedSession(stopped);
            check(stopped);slotsSession=nextSession;return opened;
        }catch(IOException|RuntimeException failure){
            if(!adopted&&dedicated!=null)dedicated.close();
            PhotoCameraClient album=null;
            if(adopted&&!stopped.getAsBoolean())try{album=slots.releaseAlbum(nextSession);}catch(IOException recovery){failure.addSuppressed(recovery);}
            slots.close();
            if(restoreAlbum(album,revision,stopped))slotsSession="";
            throw failure;
        }
    }
    private boolean restoreAlbum(PhotoCameraClient album,long revision,BooleanSupplier cancel){
        if(album==null)return false;
        boolean stopped=cancel.getAsBoolean(),accepted;
        synchronized(transportOwnership){accepted=!stopped&&revision==transportRevision&&album.isOpen();if(accepted){if(session.isEmpty())session=UUID.randomUUID().toString();handles.clear();observed.clear();resolveHandles=null;indexReady=false;client=album;}}
        if(!accepted)album.close();return accepted;
    }
    private Object status(){boolean photos=client!=null&&client.isOpen(),slot=slots!=null&&slots.isConnected();return SharedRuntime.map("connected",photos||slot,"mode",photos?"photos":slot?"slots":"none","photoConnected",photos,"slotsConnected",slot,"inventoryReady",photos&&indexReady,"session",photos?session:slot?slotsSession:"","model",device==null?"":device.model(),"manufacturer",device==null?"":device.manufacturer(),"totalHandles",handles.size(),"cameraId",photos&&device!=null?SharedCameraLiveDiscovery.cameraId(client,device,session):"","trustedCamera",photos&&SharedCameraLiveDiscovery.trusted(client),"downloadCameraId",photos?downloadCameraId:"","downloadTrusted",photos&&downloadTrusted,"transport",transport,"supportsLive",photos&&device!=null&&device.isNikonCamera()&&!transport.equals("usb"),"live",live!=null);}
    private void require(Map<String,Object> p)throws IOException{if(client==null||!client.isOpen()||!session.equals(SharedRuntime.text(p,"session",64)))throw new IOException("相机会话已改变，请重新读取照片。");}
    public void disconnect(){synchronized(transportOwnership){transportRevision++;}rawPairing=null;resolveHandles=null;downloadCameraId="";downloadTrusted=false;if(remote!=null){remote.close();remote=null;}if(slots!=null){slots.close();slots=null;}slotsSession="";if(live!=null){live.stop();live=null;}PhotoCameraClient current=client;client=null;if(current!=null)current.close();session="";device=null;handles.clear();observed.clear();indexReady=false;indexedRaw=false;unavailableStorages=0;}
    /** Per-phase PTP deadlines do not form a total deadline. This watchdog only
     * closes transport; the worker remains the sole owner of protocol/index state. */
    private final class ConnectAttempt implements BooleanSupplier {
        private final BooleanSupplier caller;
        private final long started=clock.getAsLong();
        private volatile boolean finished,timedOut,cancelled;
        private volatile String waiting="相机连接";
        private volatile double value=.05;
        private volatile PhotoCameraClient owned;
        private final Thread watchdog;
        ConnectAttempt(BooleanSupplier caller,DoubleConsumer progress){
            this.caller=caller;
            watchdog=new Thread(()->{
                while(!finished){
                    if(caller.getAsBoolean())cancelled=true;
                    if(clock.getAsLong()-started>=75_000_000_000L)timedOut=true;
                    if(cancelled||timedOut){PhotoCameraClient transport=owned;if(transport!=null)transport.close();}
                    else try{progress.accept(value);}catch(RuntimeException ignored){}
                    try{Thread.sleep(100);}catch(InterruptedException done){return;}
                }
            },"camera-connect-deadline");watchdog.setDaemon(true);watchdog.start();
        }
        void stage(String text,double value){waiting=text;this.value=value;}
        public boolean getAsBoolean(){return timedOut||cancelled||caller.getAsBoolean();}
        void rethrowIfStopped()throws IOException{
            if(timedOut)throw new java.net.SocketTimeoutException(waiting+"超时（本次连接已达 75 秒），已关闭相机通道。请核对 Wi-Fi、本地网络权限及机身确认后重试。");
            if(cancelled||caller.getAsBoolean())throw new InterruptedIOException("相机连接已取消。");
        }
        void close(){finished=true;watchdog.interrupt();}
    }
    private static void check(BooleanSupplier cancel)throws IOException{if(cancel.getAsBoolean())throw new InterruptedIOException("相机操作已取消。");}
    private PtpObjectInfo downloadInfo(PhotoCameraClient current,long handle,boolean liveDownload)throws IOException{
        try{return PtpObjectInfo.parse(current.getData(0x1008,65536,handle));}
        catch(PtpResponseException failure){if(liveDownload&&failure.responseCode()==0x2009)live.missing(handle);throw failure;}
    }
    private byte[] guid()throws IOException{File file=new File(root,"camera-client-guid.bin");if(file.isFile()){byte[] value=Files.readAllBytes(file.toPath());if(value.length==16)return value;}byte[] value=new byte[16];new SecureRandom().nextBytes(value);Files.write(file.toPath(),value);return value;}
    private static long number(Map<String,Object> p,String key)throws IOException{Object value=p.get(key);if(!(value instanceof Number)||((Number)value).doubleValue()!=((Number)value).longValue()||((Number)value).longValue()<1||((Number)value).longValue()>=0xffffffffL)throw new IOException("相机照片索引无效。");return ((Number)value).longValue();}
    private static Object row(long handle,PtpObjectInfo info){return SharedRuntime.map("handle",handle,"name",info.filename(),"bytes",info.compressedSize(),"width",info.imagePixWidth(),"height",info.imagePixHeight(),"capturedAt",info.captureDate(),"storage",info.storageId(),"descriptor",SharedCameraMutationStore.sha(info.toBytes()),"raw",photoFormat(info)==PhotoFormat.NEF);}
    private void downloadIdentity(PhotoCameraClient current,PtpDeviceInfo info){
        String identity=current.cameraIdentity(),serial=SharedCameraMutationStore.serial(info.serialNumber());
        if(SharedCameraLiveDiscovery.trusted(current)){identity="guid:"+identity.toLowerCase(Locale.ROOT);downloadTrusted=true;}
        else if(!serial.isEmpty()){identity="serial:"+serial;downloadTrusted=true;}
        else{identity="session:"+session;downloadTrusted=false;}
        downloadCameraId=SharedCameraMutationStore.sha(("huevia-download-camera-v1\n"+identity+"\n"+info.manufacturer()+"\n"+info.model()).getBytes(java.nio.charset.StandardCharsets.UTF_8));
    }
    public String downloadCameraId(){return downloadCameraId;}
    public boolean downloadTrusted(){return downloadTrusted;}
    private Object resolve(Map<String,Object> p,BooleanSupplier cancel)throws IOException {
        if(live!=null)throw new IOException("请先停止边拍边传，再恢复手动接收队列。");
        String descriptor=SharedRuntime.text(p,"descriptor",64);if(!descriptor.matches("[0-9a-f]{64}"))throw new IOException("下载描述符无效。");
        int offset=SharedRuntime.integer(p,"offset",0);if(offset<0)throw new IOException("下载核对位置无效。");
        if(offset==0&&p.containsKey("handle")){
            long handle=number(p,"handle");PtpObjectInfo info=resolveInfo(handle,cancel);
            if(info!=null&&descriptor.equals(SharedCameraMutationStore.sha(info.toBytes()))){observed.put(handle,info);return SharedRuntime.map("match",row(handle,info),"nextOffset",0,"hasMore",false);}
        }
        if(resolveHandles==null){LinkedHashSet<Long> all=new LinkedHashSet<>();long[] storage=PtpStorageIds.parse(client.getData(0x1004,4096));if(storage.length>64)throw new IOException("相机存储空间数量过多。");
            for(long id:storage){check(cancel);long[] found;try{found=PtpObjectHandles.parse(client.getData(0x1007,1024*1024,id,0,0));}catch(PtpResponseException missing){if(missing.responseCode()!=0x2013)throw missing;continue;}
                for(long handle:found){if(handle<1||handle>=0xffffffffL)throw new IOException("相机库存索引无效。");all.add(handle);if(all.size()>20000)throw new IOException("下载恢复最多核对 20000 个对象。");}}
            resolveHandles=new ArrayList<>(all);
        }
        if(offset>resolveHandles.size())throw new IOException("下载恢复库存已变化，请重新核对。");int end=Math.min(resolveHandles.size(),offset+128);
        for(int cursor=offset;cursor<end;cursor++){long handle=resolveHandles.get(cursor);PtpObjectInfo info=resolveInfo(handle,cancel);if(info!=null&&descriptor.equals(SharedCameraMutationStore.sha(info.toBytes()))){observed.put(handle,info);return SharedRuntime.map("match",row(handle,info),"nextOffset",cursor+1,"hasMore",false);}}
        return SharedRuntime.map("match",null,"nextOffset",end,"hasMore",end<resolveHandles.size());
    }
    private PtpObjectInfo resolveInfo(long handle,BooleanSupplier cancel)throws IOException{check(cancel);try{return PtpObjectInfo.parse(client.getData(0x1008,65536,handle));}catch(PtpResponseException missing){if(missing.responseCode()!=0x2009)throw missing;return null;}}
    static PhotoFormat photoFormat(PtpObjectInfo info){PhotoFormat format=PhotoFormat.of(info);if(format!=PhotoFormat.OTHER||info.objectFormat()==0x3001||info.associationType()!=0)return format;String name=info.filename().toLowerCase(Locale.ROOT);return name.matches("[^/\\\\\\p{Cntrl}]+\\.(jpg|jpeg)")?PhotoFormat.JPEG:PhotoFormat.OTHER;}
    private static final class TransferSizeChanged extends RuntimeException {private static final long serialVersionUID=1L;}
    private static void same(PtpObjectInfo a,PtpObjectInfo b)throws IOException{if(!Arrays.equals(a.toBytes(),b.toBytes()))throw new IOException("相机原文件已发生变化，未接收。");}
    private static boolean sameBytes(File a,File b)throws IOException{if(a.length()!=b.length())return false;try(InputStream aa=new FileInputStream(a);InputStream bb=new FileInputStream(b)){byte[] x=new byte[65536],y=new byte[65536];while(true){int n=aa.read(x);if(n==-1)return bb.read()==-1;int off=0;while(off<n){int m=bb.read(y,off,n-off);if(m<1)return false;off+=m;}for(int i=0;i<n;i++)if(x[i]!=y[i])return false;}}}
    private static void validateJpeg(File file)throws IOException{try(RandomAccessFile input=new RandomAccessFile(file,"r")){if(input.readUnsignedShort()!=0xffd8)throw new IOException("相机原文件不是 JPEG。");input.seek(input.length()-2);if(input.readUnsignedShort()!=0xffd9)throw new IOException("相机 JPEG 原文件不完整。");}}
}
