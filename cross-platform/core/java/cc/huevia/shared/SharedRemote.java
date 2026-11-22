package cc.huevia.shared;

import cc.huevia.album.*;
import cc.huevia.ptp.*;
import cc.huevia.remote.*;
import java.io.*;
import java.nio.file.*;
import java.util.*;
import java.util.function.BooleanSupplier;
import java.util.function.LongSupplier;

/** A revocable remote grant on the existing album connection, with one durable shutter intent. */
public final class SharedRemote implements AutoCloseable {
    private static final int DEVICE_BUSY = 0x2019;
    private final File directory;
    private final SharedCameraMutationStore journal;
    private final LongSupplier clock;
    private NikonRemoteCamera camera;
    private RemoteTransport exposureTransport;
    private ExposureWrite exposureWrite;
    private AutoCloseable grant;
    private String session="",identity="",token="";
    private RemoteLiveFrame lastFrame;
    private boolean view;
    private int sequence;
    private Map<Integer,Long> parameters=new LinkedHashMap<>();
    interface ExposureWrite {
        void set(int code, long value, BooleanSupplier cancel) throws IOException;
    }
    public SharedRemote(File root)throws IOException {
        this(root,System::currentTimeMillis);
    }
    SharedRemote(File root,LongSupplier clock)throws IOException {
        directory=new File(root,"camera-remote");journal=new SharedCameraMutationStore(root,"remote");
        this.clock=clock;
        if(!directory.isDirectory()&&!directory.mkdirs())throw new IOException("无法创建取景缓存。");
    }
    public Object open(PhotoCameraClient client,PtpDeviceInfo device,String currentSession)throws IOException {
        if(!(client instanceof PtpIpClient))throw new IOException("此连接未提供尼康遥控授权。");
        PtpIpClient.RemoteOperations remote=((PtpIpClient)client).openRemoteOperations();
        try{return open(new RemoteTransport(){
            public byte[] data(int op,int maximum,long...p)throws IOException{return remote.data(op,maximum,p);}
            public void command(int op,long...p)throws IOException{remote.command(op,p);}
            public boolean isOpen(){return remote.isOpen();}
        },remote,remote.info,currentSession,SharedCameraLiveDiscovery.cameraId(client,device,currentSession),
            remote.info.supportsOperation(0x1016) ? remote::setExposure : null);}
        catch(IOException|RuntimeException error){remote.close();throw error;}
    }
    Object openWired(PhotoCameraClient client,SharedWiredRemote.Wire wire,String currentSession)throws IOException {
        if(wire==null)throw new IOException("此连接未提供 USB 遥控通道。");
        byte[] info=client.readAlbumDeviceInfo();
        PtpDeviceInfo device=PtpDeviceInfo.parseRedacted(info);
        try{device=PtpDeviceInfo.parse(info);}catch(PtpProtocolException optionalSerial){}
        SharedWiredRemote remote=new SharedWiredRemote(wire,device);
        return open(remote,remote,device,currentSession,SharedCameraLiveDiscovery.cameraId(client,device,currentSession),
                remote.canWriteExposure()?remote::setExposure:null);
    }
    Object open(RemoteTransport transport,AutoCloseable owner,PtpDeviceInfo device,String currentSession,String cameraIdentity)throws IOException {
        return open(transport, owner, device, currentSession, cameraIdentity, null);
    }
    Object open(RemoteTransport transport,AutoCloseable owner,PtpDeviceInfo device,String currentSession,String cameraIdentity,ExposureWrite write)throws IOException {
        close();grant=owner;session=currentSession;identity=cameraIdentity;token=UUID.randomUUID().toString();
        camera=new NikonRemoteCamera(transport,device,identity);parameters=camera.parameters();
        exposureTransport=transport;exposureWrite=write;
        return state();
    }
    public Object request(String op,Map<String,Object> p,BooleanSupplier cancel)throws IOException {
        if(op.equals("camera.remote.close")){if(!session.equals(p.get("session"))||!token.equals(p.get("remoteId")))throw new IOException("遥控会话已变化。");close();return SharedRuntime.map("closed",true);}
        require(p);check(cancel);
        if(op.equals("camera.remote.status")){parameters=camera.parameters();return state();}
        if(op.equals("camera.remote.view")){
            if(Boolean.TRUE.equals(p.get("enabled"))){camera.startView();view=true;}
            else{camera.stopView();view=false;lastFrame=null;}
            return state();
        }
        if(op.equals("camera.remote.frame")){
            if(!view)throw new IOException("请先开启实时取景。");
            RemoteLiveFrame frame=camera.frame();check(cancel);if(frame==null)return SharedRuntime.map("ready",false);
            lastFrame=frame;File target=new File(directory,"frame-"+(++sequence%2)+".jpg");Files.write(target.toPath(),frame.jpeg);
            return SharedRuntime.map("ready",true,"path",target.getPath(),"sequence",sequence,"width",frame.width,"height",frame.height,"rotation",frame.rotation,"pointFocus",camera.pointFocus&&frame.afWidth>0&&frame.afHeight>0,"focusKnown",frame.focusKnown,"focused",frame.focused);
        }
        if(op.equals("camera.remote.focus")){
            Double x=null,y=null;
            if(p.containsKey("x")||p.containsKey("y")){x=coordinate(p.get("x"));y=coordinate(p.get("y"));}
            return focus(x, y, cancel);
        }
        if(op.equals("camera.remote.exposure.options"))return exposureOptions(p, cancel);
        if(op.equals("camera.remote.exposure.set"))return setExposure(p, cancel);
        if(op.equals("camera.remote.capture"))return capture(cancel);
        if(op.equals("camera.remote.check"))return verify(cancel);
        if(op.equals("camera.remote.acknowledge")){
            Map<String,Object> pending=journal.read();
            boolean confirmed=Boolean.TRUE.equals(p.get("confirmedOnCamera"));
            boolean continueWithoutConfirming=Boolean.TRUE.equals(p.get("continueWithoutConfirming"));
            if(confirmed==continueWithoutConfirming||!(p.get("actionId") instanceof String)||!Objects.equals(p.get("actionId"),pending.get("actionId")))throw new IOException("拍摄记录已变化，请重新核对。");
            if(!Boolean.TRUE.equals(pending.get("pending")))return state(pending);
            // An explicit decision to start over retires the lock without
            // claiming a photo was saved or sending any camera command.
            pending.put("pending",false);
            pending.put("phase",confirmed?"manuallyChecked":"closedUnverified");
            journal.save(pending);
            return state(pending);
        }
        throw new IOException("未知的遥控操作。");
    }

    private Object focus(Double x, Double y, BooleanSupplier cancel) throws IOException {
        if (Long.valueOf(1).equals(parameters.get(0x500a))) {
            return notice("机身当前是手动对焦，请先切换到自动对焦。");
        }
        for (int attempt = 0; ; attempt++) {
            check(cancel);
            try {
                camera.focus(lastFrame, x, y);
                return state();
            } catch (PtpResponseException reply) {
                if (reply.responseCode() == 0x2019 && attempt == 0) {
                    waitForCamera(cancel);
                    continue;
                }
                switch (reply.responseCode()) {
                    case 0x2019: return notice("相机暂忙，对焦未完成。可稍候再试；若持续忙，可在机身试用 AF-S。");
                    case 0xa002: return notice("未能合焦，可将对焦点移到有纹理或较亮的位置。");
                    case 0xa004:
                    case 0xa00b: return notice("机身暂不能对焦，请确认实时取景已开启。");
                    default: throw reply;
                }
            }
        }
    }

    private Object exposureOptions(Map<String,Object> request, BooleanSupplier cancel) throws IOException {
        int code = exposureCode(request);
        if (exposureWrite == null) throw new IOException("相机未开放手机端曝光调节。");
        try {
            byte[] bytes = retryWhenBusy(cancel, () -> exposureTransport.data(0x1014, 65536, code));
            RemoteExposure descriptor = RemoteExposure.parse(code, bytes);
            return SharedRuntime.map("value", descriptor.current, "choices", descriptor.choices);
        } catch (PtpResponseException reply) {
            String message = exposureNotice(reply);
            if (message == null) throw reply;
            return SharedRuntime.map("choices", List.of(), "notice", message);
        } catch (IOException failure) {
            if (!camera.isOpen() || failure instanceof InterruptedIOException) throw failure;
            return SharedRuntime.map("choices", List.of(), "notice", "机身暂未提供可用档位。");
        }
    }

    private Object setExposure(Map<String,Object> request, BooleanSupplier cancel) throws IOException {
        int code = exposureCode(request);
        if (exposureWrite == null) throw new IOException("相机未开放手机端曝光调节。");
        if (Boolean.TRUE.equals(journal.read().get("pending"))) {
            return notice("请先核对拍摄结果，再调整曝光。");
        }
        Object raw = request.get("value");
        if (!(raw instanceof Number)) throw new IOException("曝光档位无效。");
        Number number = (Number)raw;
        long value = number.longValue();
        if (number.doubleValue() != value || !RemoteExposure.acceptsValue(code, value)) throw new IOException("相机参数档位无效。");
        try {
            boolean sent = retryWhenBusy(cancel, () -> {
                checkWiredReady();
                if (code == RemoteExposure.COLOR_TEMPERATURE &&
                        RemoteExposure.read(RemoteExposure.WHITE_BALANCE,
                                exposureTransport.data(0x1015, 16, RemoteExposure.WHITE_BALANCE))
                                != RemoteExposure.TEMPERATURE_MODE) {
                    return false;
                }
                exposureWrite.set(code, value, cancel);
                return true;
            });
            if (!sent) {
                return notice("请先将机身白平衡切换到色温。");
            }
        } catch (PtpResponseException reply) {
            String message = exposureNotice(reply);
            if (message == null) throw reply;
            return notice(message);
        } catch (IOException failure) {
            check(cancel);
            if (!camera.isOpen() || failure instanceof InterruptedIOException) throw failure;
            return notice(failure.getMessage() != null ? failure.getMessage() : "相机未接受调节。");
        }

        // Once the write is accepted, retry the readback only.
        long actual;
        try {
            byte[] bytes = retryWhenBusy(cancel, () -> exposureTransport.data(0x1015, 16, code));
            actual = RemoteExposure.read(code, bytes);
        } catch (IOException failure) {
            check(cancel);
            if (!camera.isOpen()) throw failure;
            return notice("相机已接收调整，暂未读回实际档位。请核对机身。");
        }
        parameters.put(code, actual);
        if (code == RemoteExposure.WHITE_BALANCE && actual != RemoteExposure.TEMPERATURE_MODE) {
            parameters.remove(RemoteExposure.COLOR_TEMPERATURE);
        }
        return actual == value ? state() : notice("机身返回了不同的档位，界面已显示实际值。");
    }

    private static int exposureCode(Map<String,Object> request) throws IOException {
        int code = SharedRuntime.integer(request, "code", -1);
        if (!RemoteExposure.allows(code)) throw new IOException("此参数不支持遥控调节。");
        return code;
    }

    private static String exposureNotice(PtpResponseException reply) {
        switch (reply.responseCode()) {
            case DEVICE_BUSY: return "相机暂忙，未能确认调节。请稍候再试。";
            case 0x2005:
            case 0x200a:
            case 0x200f:
            case 0x201c:
            case 0x201d:
            case 0xa005:
            case 0xa00a: return "相机当前模式或镜头不允许调节此项。";
            default: return null;
        }
    }

    private static void waitForCamera(BooleanSupplier cancel) throws IOException {
        check(cancel);
        try {
            Thread.sleep(220);
        } catch (InterruptedException interrupted) {
            Thread.currentThread().interrupt();
            throw new InterruptedIOException("遥控操作已取消。");
        }
        check(cancel);
    }

    private interface CameraOperation<T> {
        T run() throws IOException;
    }

    private static <T> T retryWhenBusy(BooleanSupplier cancel, CameraOperation<T> operation) throws IOException {
        check(cancel);
        try {
            return operation.run();
        } catch (PtpResponseException response) {
            if (response.responseCode() != DEVICE_BUSY) throw response;
            waitForCamera(cancel);
            return operation.run();
        }
    }

    private void checkWiredReady() throws IOException {
        if (exposureTransport instanceof SharedWiredRemote) {
            ((SharedWiredRemote)exposureTransport).checkReady();
        }
    }

    private Map<String,Object> notice(String message) throws IOException {
        Map<String,Object> result = state(journal.read());
        result.put("notice", message);
        return result;
    }
    private Object capture(BooleanSupplier cancel)throws IOException {
        Map<String,Object> previous=journal.read();if(Boolean.TRUE.equals(previous.get("pending")))throw new IOException("上次拍摄结果待确认，请先核对；本次未发送快门。");
        Set<Long> baseline;
        try {
            baseline = retryWhenBusy(cancel, () -> {
                checkWiredReady();
                parameters = camera.parameters();
                Long shutter = parameters.get(0x500d);
                if (!Long.valueOf(1).equals(parameters.get(0x5013)) ||
                        shutter == null || shutter <= 0 || shutter >= 0xfffffffeL) {
                    throw new IOException("请在机身使用单张拍摄和普通快门时间。");
                }
                Set<Long> inventory = camera.inventory();
                check(cancel);
                checkWiredReady();
                return inventory;
            });
        } catch (PtpResponseException response) {
            if (response.responseCode() != DEVICE_BUSY) throw response;
            return notice("相机暂忙，本次未发送快门。请稍候再拍。");
        }
        check(cancel);
        Long quality=parameters.get(0x5004);
        boolean jpegExpected=quality!=null&&(quality<=2||quality>=5&&quality<=7);
        Map<String,Object> pending=SharedRuntime.map("pending",true,"actionId",UUID.randomUUID().toString(),"cameraId",identity,"session",session,"baseline",new ArrayList<>(baseline),"phase","resultUnknown","time",clock.getAsLong(),"jpegExpected",jpegExpected);
        journal.save(pending); // Must be durable before the one and only shutter command.
        try{camera.release();pending.put("phase","acknowledged");journal.save(pending);}
        catch(PtpResponseException rejected){
            int code=rejected.responseCode();
            if (code == DEVICE_BUSY || code == 0x2005 || code == 0x2006 || code == 0x200f || code == 0x201d) {
                pending.put("pending", false);
                pending.put("phase", "rejected");
                journal.save(pending);
                return notice(code == DEVICE_BUSY
                        ? "相机暂忙，机身未接受快门。请稍候再拍。"
                        : "机身未接受快门，请检查相机的拍摄模式和状态。");
            }
            pending.put("message",rejected.getMessage());journal.save(pending);
        }catch(IOException failure){pending.put("message","快门响应未确认，请核对相机；不会自动重拍。");journal.save(pending);}
        return state();
    }
    private Object verify(BooleanSupplier cancel)throws IOException {
        Map<String,Object> pending=journal.read();
        if(!Boolean.TRUE.equals(pending.get("pending")))return state();
        if(!identity.equals(pending.get("cameraId")))throw new IOException("请连接上次拍摄的同一相机后核对。");
        Object saved=pending.get("baseline");if(!(saved instanceof List))throw new IOException("拍摄基线不完整，请在相机上手动核对。");
        Set<Long> baseline=new LinkedHashSet<>();for(Object item:(List<?>)saved){if(!(item instanceof Number))throw new IOException("拍摄基线无效。");baseline.add(((Number)item).longValue());}
        List<NikonRemoteCamera.CapturedPhoto> photos;
        try{photos=camera.newPhotos(baseline);}
        catch(PtpResponseException failure){
            // During a card update, a handle can disappear between enumeration
            // and GetObjectInfo. Keep the journal pending and re-read the list.
            int code=failure.responseCode();
            if(code==0x2019||code==0x2009)return state(pending);
            throw failure;
        }
        check(cancel);
        Map<String,Object> previous=new LinkedHashMap<>(pending);
        List<Object> rows=new ArrayList<>();
        for(NikonRemoteCamera.CapturedPhoto photo:photos)rows.add(SharedRuntime.map("handle",photo.handle,"name",photo.object.filename(),"raw",!photo.jpeg()));
        pending.put("photos",rows);pending.put("checked",true);
        if(photos.isEmpty())pending.put("phase","waitingForPhoto");
        else if(!NikonRemoteCamera.oneExposure(photos))pending.put("phase","multipleExposures");
        else if(photos.stream().anyMatch(photo->photo.object.compressedSize()==0))pending.put("phase","waitingForPhoto");
        else {
            boolean jpeg=photos.stream().anyMatch(NikonRemoteCamera.CapturedPhoto::jpeg);
            if(shouldWaitForJpeg(pending,jpeg))pending.put("phase","waitingForJpeg");
            else {pending.put("pending",false);pending.put("phase","verified");}
        }
        if(!pending.equals(previous))journal.save(pending);
        return state(pending);
    }
    private boolean shouldWaitForJpeg(Map<String,Object> pending,boolean jpeg){
        if(jpeg||!Boolean.TRUE.equals(pending.get("jpegExpected")))return false;
        long now=clock.getAsLong();
        Object saved=pending.get("rawObservedAt");
        if(!(saved instanceof Number)){pending.put("rawObservedAt",now);return true;}
        long elapsed=now-((Number)saved).longValue();
        return elapsed>=0&&elapsed<10_000;
    }
    private Object state()throws IOException {return state(journal.read());}
    private Map<String,Object> state(Map<String,Object> action){
        List<Object> values=new ArrayList<>();for(Map.Entry<Integer,Long> entry:parameters.entrySet())values.add(SharedRuntime.map("code",entry.getKey(),"value",entry.getValue(),"writable",false));
        Map<String,Object> summary=new LinkedHashMap<>();
        for(String field:new String[]{"actionId","pending","phase","photos","checked","message"}){
            if(action.containsKey(field))summary.put(field,action.get(field));
        }
        if(Boolean.TRUE.equals(action.get("pending"))){
            summary.put("canCheck",identity.equals(action.get("cameraId"))&&action.get("baseline") instanceof List);
        }
        return SharedRuntime.map("session",session,"remoteId",token,"model",camera==null?"":camera.model,"connected",camera!=null&&camera.isOpen(),"liveView",camera!=null&&camera.liveView,"capture",camera!=null&&camera.capture,"autoFocus",camera!=null&&camera.autoFocus,"pointFocus",camera!=null&&camera.pointFocus,"exposureControls",exposureWrite!=null,"viewing",view,"parameters",values,"action",summary);
    }
    private void require(Map<String,Object> p)throws IOException {if(camera==null||!camera.isOpen()||!session.equals(p.get("session"))||!token.equals(p.get("remoteId")))throw new IOException("遥控会话已结束，请返回相册重新打开。");}
    private static Double coordinate(Object value)throws IOException{if(!(value instanceof Number))throw new IOException("对焦坐标无效。");double number=((Number)value).doubleValue();if(!Double.isFinite(number)||number<0||number>1)throw new IOException("对焦坐标超出取景范围。");return number;}
    private static void check(BooleanSupplier cancel)throws IOException{if(cancel.getAsBoolean())throw new InterruptedIOException("遥控操作已取消。");}
    @Override public void close(){
        NikonRemoteCamera old=camera;camera=null;
        if(old!=null&&view)try{old.stopView();}catch(IOException ignored){}
        view=false;lastFrame=null;AutoCloseable previous=grant;grant=null;
        exposureTransport=null;exposureWrite=null;
        if(previous!=null)try{previous.close();}catch(Exception ignored){}
        token="";parameters.clear();
    }
}
