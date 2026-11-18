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
    private final File directory;
    private final SharedCameraMutationStore journal;
    private final LongSupplier clock;
    private NikonRemoteCamera camera;
    private AutoCloseable grant;
    private String session="",identity="",token="";
    private RemoteLiveFrame lastFrame;
    private boolean view;
    private int sequence;
    private Map<Integer,Long> parameters=new LinkedHashMap<>();
    public SharedRemote(File root)throws IOException {
        this(root,System::currentTimeMillis);
    }
    SharedRemote(File root,LongSupplier clock)throws IOException {
        directory=new File(root,"camera-remote");journal=new SharedCameraMutationStore(root,"remote");
        this.clock=clock;
        if(!directory.isDirectory()&&!directory.mkdirs())throw new IOException("无法创建取景缓存。");
    }
    public Object open(PhotoCameraClient client,PtpDeviceInfo device,String currentSession)throws IOException {
        if(!(client instanceof PtpIpClient))throw new IOException("此连接未提供独立遥控授权，请使用尼康 Wi-Fi 连接。");
        PtpIpClient.RemoteOperations remote=((PtpIpClient)client).openRemoteOperations();
        try{return open(new RemoteTransport(){
            public byte[] data(int op,int maximum,long...p)throws IOException{return remote.data(op,maximum,p);}
            public void command(int op,long...p)throws IOException{remote.command(op,p);}
            public boolean isOpen(){return remote.isOpen();}
        },remote,remote.info,currentSession,SharedCameraLiveDiscovery.cameraId(client,device,currentSession));}
        catch(IOException|RuntimeException error){remote.close();throw error;}
    }
    Object open(RemoteTransport transport,AutoCloseable owner,PtpDeviceInfo device,String currentSession,String cameraIdentity)throws IOException {
        close();grant=owner;session=currentSession;identity=cameraIdentity;token=UUID.randomUUID().toString();
        camera=new NikonRemoteCamera(transport,device,identity);parameters=camera.parameters();return state();
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
            camera.focus(lastFrame,x,y);return state();
        }
        if(op.equals("camera.remote.capture"))return capture(cancel);
        if(op.equals("camera.remote.check"))return verify();
        if(op.equals("camera.remote.acknowledge")){
            Map<String,Object> pending=journal.read();
            if(!Boolean.TRUE.equals(p.get("confirmedOnCamera"))||!Objects.equals(p.get("actionId"),pending.get("actionId")))throw new IOException("请先在相机核对本次拍摄，再确认结果。");
            pending.put("pending",false);pending.put("phase","manuallyChecked");journal.save(pending);return state();
        }
        throw new IOException("未知的遥控操作。");
    }
    private Object capture(BooleanSupplier cancel)throws IOException {
        Map<String,Object> previous=journal.read();if(Boolean.TRUE.equals(previous.get("pending")))throw new IOException("上次拍摄结果待确认，请先核对；本次未发送快门。");
        parameters=camera.parameters();Long shutter=parameters.get(0x500d);
        if(!Long.valueOf(1).equals(parameters.get(0x5013))||shutter==null||shutter<=0||shutter>=0xfffffffeL)throw new IOException("请在机身使用单张拍摄和普通快门时间。");
        Set<Long> baseline=camera.inventory();check(cancel);
        Long quality=parameters.get(0x5004);
        boolean jpegExpected=quality!=null&&(quality<=2||quality>=5&&quality<=7);
        Map<String,Object> pending=SharedRuntime.map("pending",true,"actionId",UUID.randomUUID().toString(),"cameraId",identity,"session",session,"baseline",new ArrayList<>(baseline),"phase","resultUnknown","time",clock.getAsLong(),"jpegExpected",jpegExpected);
        journal.save(pending); // Must be durable before the one and only shutter command.
        try{camera.release();pending.put("phase","acknowledged");journal.save(pending);}
        catch(PtpResponseException rejected){
            int code=rejected.responseCode();
            if(code==0x2019||code==0x2005||code==0x2006||code==0x200f||code==0x201d){pending.put("pending",false);pending.put("phase","rejected");journal.save(pending);throw rejected;}
            pending.put("message",rejected.getMessage());journal.save(pending);
        }catch(IOException failure){pending.put("message","快门响应未确认，请核对相机；不会自动重拍。");journal.save(pending);}
        return state();
    }
    private Object verify()throws IOException {
        Map<String,Object> pending=journal.read();
        if(!Boolean.TRUE.equals(pending.get("pending")))return state();
        if(!identity.equals(pending.get("cameraId")))throw new IOException("请连接上次拍摄的同一相机后核对。");
        Object saved=pending.get("baseline");if(!(saved instanceof List))throw new IOException("拍摄基线不完整，请在相机上手动核对。");
        Set<Long> baseline=new LinkedHashSet<>();for(Object item:(List<?>)saved){if(!(item instanceof Number))throw new IOException("拍摄基线无效。");baseline.add(((Number)item).longValue());}
        List<NikonRemoteCamera.CapturedPhoto> photos;
        try{photos=camera.newPhotos(baseline);}
        catch(PtpResponseException busy){
            // Nikon can report DeviceBusy while it finalizes the file on the card.
            if(busy.responseCode()==0x2019)return state(pending);
            throw busy;
        }
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
    private Object state(Map<String,Object> action){
        List<Object> values=new ArrayList<>();for(Map.Entry<Integer,Long> entry:parameters.entrySet())values.add(SharedRuntime.map("code",entry.getKey(),"value",entry.getValue(),"writable",false));
        Map<String,Object> summary=new LinkedHashMap<>();
        for(String field:new String[]{"actionId","pending","phase","photos","checked","message"}){
            if(action.containsKey(field))summary.put(field,action.get(field));
        }
        return SharedRuntime.map("session",session,"remoteId",token,"model",camera==null?"":camera.model,"connected",camera!=null&&camera.isOpen(),"liveView",camera!=null&&camera.liveView,"capture",camera!=null&&camera.capture,"autoFocus",camera!=null&&camera.autoFocus,"pointFocus",camera!=null&&camera.pointFocus,"viewing",view,"parameters",values,"action",summary);
    }
    private void require(Map<String,Object> p)throws IOException {if(camera==null||!camera.isOpen()||!session.equals(p.get("session"))||!token.equals(p.get("remoteId")))throw new IOException("遥控会话已结束，请返回相册重新打开。");}
    private static Double coordinate(Object value)throws IOException{if(!(value instanceof Number))throw new IOException("对焦坐标无效。");double number=((Number)value).doubleValue();if(!Double.isFinite(number)||number<0||number>1)throw new IOException("对焦坐标超出取景范围。");return number;}
    private static void check(BooleanSupplier cancel)throws IOException{if(cancel.getAsBoolean())throw new InterruptedIOException("遥控操作已取消。");}
    @Override public void close(){
        NikonRemoteCamera old=camera;camera=null;
        if(old!=null&&view)try{old.stopView();}catch(IOException ignored){}
        view=false;lastFrame=null;AutoCloseable previous=grant;grant=null;
        if(previous!=null)try{previous.close();}catch(Exception ignored){}
        token="";parameters.clear();
    }
}
