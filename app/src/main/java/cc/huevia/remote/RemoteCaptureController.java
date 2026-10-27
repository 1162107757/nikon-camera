package cc.huevia.remote;

import android.content.Context;
import android.content.SharedPreferences;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import cc.huevia.album.*;
import cc.huevia.connection.CameraConnectionRuntime;
import cc.huevia.ncp.PhotoHistogram;
import cc.huevia.ptp.PtpResponseException;
import java.io.IOException;
import java.util.*;

/** Application-owned capture state. Activities only observe; a pending shutter survives navigation. */
public final class RemoteCaptureController {
    private static RemoteCaptureController instance;
    public static synchronized RemoteCaptureController get(Context context){if(instance==null){CameraConnectionRuntime runtime=CameraConnectionRuntime.get(context);instance=new RemoteCaptureController(context.getApplicationContext(),runtime,runtime.album);}return instance;}
    public enum Outcome { IDLE, PREPARING, CAPTURING, CONFIRMED, UNKNOWN }
    public static final class Frame {
        public final long sequence,receivedAt;
        public final Bitmap bitmap;
        public final PhotoHistogram histogram;
        public final RemoteLiveFrame wire;
        Frame(long id,Bitmap bitmap,PhotoHistogram histogram,RemoteLiveFrame wire){sequence=id;receivedAt=SystemClock.elapsedRealtime();this.bitmap=bitmap;this.histogram=histogram;this.wire=wire;}
    }
    public static final class State {
        public final boolean connected,opening,liveEnabled,viewPaused,transfer,working,canCapture,canFocus,canPointFocus;
        public final String model,message,viewMessage,connectionStatus;
        public final boolean importing;
        public final PhotoTransferProgress.Snapshot importProgress;
        public final Map<Integer,Long> parameters;
        public final long parametersAt;
        public final Outcome outcome;
        public final Frame frame;
        public final Bitmap thumbnail;
        public final NikonRemoteCamera.CapturedPhoto recent;
        public final DownloadedPhoto imported;
        State(RemoteCaptureController c){
            connected=c.access!=null&&c.access.isActive();opening=c.opening;liveEnabled=c.liveEnabled;viewPaused=c.viewPaused;
            transfer=c.transfer;working=c.userWork||c.pending();model=c.model;message=c.message;viewMessage=c.viewMessage;
            connectionStatus=opening?"连接中":connected?"已连接":c.runtime.wifiSession.isRouteUnavailable()?"Wi-Fi 已断开":c.runtime.wifiSession.isConnected()?"会话已断开":"连接已断开";
            importing=c.importing;importProgress=importing?c.importProgress.snapshot(PhotoTransferProgress.now()):PhotoTransferProgress.Snapshot.EMPTY;
            parameters=Collections.unmodifiableMap(new HashMap<>(connected&&SystemClock.elapsedRealtime()-c.parametersAt<5000?c.parameters:Collections.emptyMap()));parametersAt=c.parametersAt;
            outcome=c.outcome;frame=c.frame;thumbnail=c.thumbnail;recent=c.recent;imported=c.imported;minimumHistogramSequence=c.minimumHistogramSequence;
            boolean fresh=connected&&SystemClock.elapsedRealtime()-parametersAt<5000;
            Long mode=parameters.get(0x5013),shutter=parameters.get(0x500d);
            boolean still=mode!=null&&mode==1&&shutter!=null&&shutter>0&&shutter<0xfffffffeL;
            canCapture=fresh&&still&&c.captureSupported&&!working&&outcome!=Outcome.UNKNOWN;
            canFocus=connected&&c.focusSupported&&!Long.valueOf(4).equals(parameters.get(0xd061))&&liveEnabled&&!viewPaused&&frame!=null&&SystemClock.elapsedRealtime()-frame.receivedAt<2000&&!working&&outcome!=Outcome.UNKNOWN;
            canPointFocus=canFocus&&c.pointSupported&&frame.wire.afWidth>0;
        }
        public String value(int code){Long v=parameters.get(code);if(v==null)return "—";
            if(code==0x500d)return RemoteProperty.shutter(v);if(code==0x5007)return RemoteProperty.aperture(v);
            if(code==0x5010)return RemoteProperty.compensation(v);if(code==0x500f)return v==65535||Long.valueOf(1).equals(parameters.get(0xd054))?"自动":Long.toString(v);
            return Long.toString(v);
        }
        public String mode(){Long v=parameters.get(0x500e);return v==null?"—":v==1?"M":v==2?"P":v==3?"A":v==4?"S":"自动";}
        public String focus(){Long v=parameters.get(0xd061);if(v!=null)return v==0?"AF-S":v==1?"AF-C":v==4?"MF":"—";v=parameters.get(0xd161);return v==null?"—":v==0?"AF-S":v==1?"AF-C":v==4?"MF":"—";}
        public String release(){Long v=parameters.get(0x5013);return v==null?"—":v==1?"单张":v==2?"连拍":"其他释放模式";}
        public String quality(){Long v=parameters.get(0x5004);if(v==null)return "—";switch(v.intValue()){case 0:return "JPEG BASIC";case 1:return "JPEG NORMAL";case 2:return "JPEG FINE";case 3:return "TIFF";case 4:return "RAW";case 5:return "RAW + JPEG BASIC";case 6:return "RAW + JPEG NORMAL";case 7:return "RAW + JPEG FINE";default:return "请在机身查看";}}
        public boolean histogramFresh(){return connected&&liveEnabled&&!viewPaused&&frame!=null&&frame.sequence>=minimumHistogramSequence&&outcome!=Outcome.CAPTURING&&outcome!=Outcome.PREPARING&&SystemClock.elapsedRealtime()-frame.receivedAt<2000;}
        public String compactMessage(){
            if(outcome==Outcome.UNKNOWN)return "拍摄待确认 · 核对";
            if(opening||!connected)return connectionStatus;
            if(importing)return importProgress.compact(PhotoTransferProgress.now());
            if(message.startsWith("正在准备拍摄"))return "准备拍摄";
            if(message.startsWith("正在拍摄"))return "拍摄中";
            if(message.startsWith("正在对焦"))return "对焦中";
            if(message.startsWith("对焦请求已发送"))return "已请求对焦";
            if(message.startsWith("RAW 已保存"))return "等待 JPEG";
            if(message.startsWith("已保存到相机 ·"))return "已存相机";
            if(message.startsWith("已传入 App ·"))return "已传入 App";
            if(message.startsWith("照片已保存到相机，传入未完成"))return "传入失败 · 详情";
            if(message.startsWith("照片已保存，预览暂不可用"))return "预览不可用 · 详情";
            if(message.startsWith("已保存到相机，本次未取得 JPEG"))return "未取得 JPEG · 详情";
            if(message.equals("相机未开放遥控快门能力"))return "快门暂不可用 · 详情";
            if(message.equals("请在相机上切换为单张拍摄"))return "请切换单张";
            if(message.equals("请在相机上设置普通快门时间"))return "请调整快门";
            if(message.equals("已连接，可以拍摄")||message.equals("已完成手动核对，可以继续拍摄"))return "可拍摄";
            return "查看状态详情";
        }
        private final long minimumHistogramSequence;
    }
    private final AlbumController album;
    private final CameraConnectionRuntime runtime;
    private final SharedPreferences journal;
    private final Handler main=new Handler(Looper.getMainLooper());
    private final Set<Runnable> observers=new LinkedHashSet<>();
    private AlbumController.RemoteAccess access;
    private CameraConnectionRuntime.OperationLease service;
    private boolean visible,opening,workPending,userWork,liveEnabled=true,viewStarted,viewMayBeRunning,viewPaused,transfer,captureSupported,focusSupported,pointSupported;
    private Runnable deferred;
    private String model="相机",message="正在读取相机能力…",viewMessage="等待实时画面…";
    private String sessionIdentity="";
    private Map<Integer,Long> parameters=new HashMap<>();
    private long parametersAt,sequence,deadline,nextCaptureCheck,minimumHistogramSequence,rawObservedAt,actionMessageUntil;
    private boolean expectJpeg;
    private Frame frame;
    private Bitmap thumbnail;
    private NikonRemoteCamera.CapturedPhoto recent;
    private DownloadedPhoto imported;
    private boolean importing;
    private final PhotoTransferProgress importProgress=new PhotoTransferProgress();
    private Outcome outcome=Outcome.IDLE;
    private Set<Long> baseline=new LinkedHashSet<>();
    private boolean checkedUnknown,baselineValid=true;
    private int generation;
    public RemoteCaptureController(Context context,CameraConnectionRuntime runtime,AlbumController album){
        this.runtime=runtime;this.album=album;journal=context.getSharedPreferences("remote-capture-journal",Context.MODE_PRIVATE);
        if(journal.getBoolean("pending",false)){outcome=Outcome.UNKNOWN;message="拍摄结果待确认 · 查看相机照片";baseline=readBaseline();}
        runtime.addObserver(()->{if(access!=null&&!access.isActive())lost("相机已断开，请重新连接。");});
    }
    public State state(){return new State(this);}
    public void addObserver(Runnable observer){observers.add(observer);}
    public void removeObserver(Runnable observer){observers.remove(observer);}
    private void changed(){for(Runnable observer:new ArrayList<>(observers))observer.run();}
    public void setVisible(boolean value){visible=value;if(value)start();else if(!pending())stop();}
    private boolean pending(){return outcome==Outcome.PREPARING||outcome==Outcome.CAPTURING;}
    public void start(){
        if(opening||access!=null&&access.isActive()){schedule(0);return;}
        if(workPending)return;
        opening=true;viewStarted=false;viewMayBeRunning=false;parameters.clear();parametersAt=0;frame=null;checkedUnknown=false;
        if(outcome!=Outcome.UNKNOWN)message="正在读取相机能力…";
        try{if(service==null)service=runtime.beginOperation();}catch(RuntimeException error){opening=false;message="无法保持相机任务，请返回同步后重试。";changed();return;}
        changed();final int ticket=++generation;
        album.openRemoteCapture(new AlbumController.Callback<AlbumController.RemoteAccess>(){
            @Override public void onSuccess(AlbumController.RemoteAccess value){
                if(ticket!=generation){value.close();return;}opening=false;access=value;model=PhotoCaptureInfo.friendly(value.camera.model);
                if(!sessionIdentity.equals(value.camera.identity)){recent=null;thumbnail=null;imported=null;sessionIdentity=value.camera.identity;}
                captureSupported=value.camera.capture;focusSupported=value.camera.autoFocus;pointSupported=value.camera.pointFocus;
                viewPaused=!value.camera.liveView;viewMessage=viewPaused?"相机未开放实时取景":"等待实时画面…";
                if(journal.getBoolean("pending",false)){outcome=Outcome.UNKNOWN;baseline=readBaseline();message=journal.getString("camera","").equals(value.camera.identity)?"拍摄结果待确认 · 查看相机照片":"上次拍摄属于另一台相机，请先连接原相机核对";}
                else message=captureSupported?"正在读取当前参数…":"相机未开放遥控快门能力";
                changed();if(visible||pending())schedule(0);else stop();
            }
            @Override public void onError(String error){if(ticket!=generation)return;opening=false;access=null;message=error;viewPaused=true;viewMessage="相机已断开";releaseService();changed();}
        });
    }
    private final Runnable polling=this::poll;
    private void schedule(long millis){main.removeCallbacks(polling);if(visible||pending())main.postDelayed(polling,millis);}
    private void poll(){
        if(workPending||opening)return;
        if(access==null||!access.isActive()){lost("相机已断开，请重新连接。");return;}
        if(!visible&&!pending()){stop();return;}
        if(!liveEnabled&&(viewStarted||viewMayBeRunning)&&!viewPaused){run(camera->{camera.stopView();return null;},none->{viewStarted=false;viewMayBeRunning=false;changed();schedule(250);},error->{viewStarted=false;viewPaused=true;viewMessage=error;changed();schedule(800);});return;}
        if(outcome==Outcome.CAPTURING){
            if(SystemClock.elapsedRealtime()>deadline){outcome=Outcome.UNKNOWN;message="拍摄结果待确认 · 查看相机照片";changed();if(!visible)stop();else schedule(500);return;}
            if(SystemClock.elapsedRealtime()>=nextCaptureCheck){checkCapture(false);return;}
        }
        final boolean getParameters=SystemClock.elapsedRealtime()-parametersAt>=1500;
        final boolean getFrame=visible&&liveEnabled&&!viewPaused&&!pending();
        final boolean shouldStart=getFrame&&!viewStarted;
        if(getFrame)viewMayBeRunning=true;
        run(camera->{
            Map<Integer,Long> p=getParameters?camera.parameters():null;
            Frame f=null;boolean started=false;
            if(getFrame){
                if(shouldStart){Long prohibit=p==null?parameters.get(0xd1a4):p.get(0xd1a4);if(prohibit!=null&&prohibit!=0)throw new IOException("机身当前禁止取景，请检查电量、温度和相机拍摄模式。");camera.startView();started=true;}
                RemoteLiveFrame wire=camera.frame();if(wire==null)return new PollResult(p,null,started);BitmapFactory.Options options=new BitmapFactory.Options();
                options.inSampleSize=1;while(wire.width/options.inSampleSize>1280||wire.height/options.inSampleSize>1280)options.inSampleSize*=2;
                Bitmap bitmap=BitmapFactory.decodeByteArray(wire.jpeg,0,wire.jpeg.length,options);
                if(bitmap==null)throw new IOException("实时画面无法解码，请重试取景。");
                if(wire.rotation!=0){android.graphics.Matrix matrix=new android.graphics.Matrix();matrix.postRotate(wire.rotation);Bitmap rotated=Bitmap.createBitmap(bitmap,0,0,bitmap.getWidth(),bitmap.getHeight(),matrix,true);if(rotated!=bitmap)bitmap.recycle();bitmap=rotated;}
                PhotoHistogram.Builder histogram=new PhotoHistogram.Builder();int[] row=new int[bitmap.getWidth()];
                for(int y=0;y<bitmap.getHeight();y++){bitmap.getPixels(row,0,row.length,0,y,row.length,1);histogram.addArgb(row,0,row.length);}
                f=new Frame(++sequence,bitmap,histogram.build(),wire);
            }
            return new PollResult(p,f,started);
        },result->{
            if(result.parameters!=null){parameters=result.parameters;parametersAt=SystemClock.elapsedRealtime();}
            if(result.started)viewStarted=true;
            if(result.frame!=null){frame=result.frame;viewMessage="";}
            if(outcome==Outcome.IDLE||outcome==Outcome.CONFIRMED){
                if(!captureSupported)message="相机未开放遥控快门能力";
                else if(!Long.valueOf(1).equals(parameters.get(0x5013)))message="请在相机上切换为单张拍摄";
                else if(!parameters.containsKey(0x500d)||parameters.get(0x500d)>=0xfffffffeL)message="请在相机上设置普通快门时间";
                else if(outcome==Outcome.IDLE&&SystemClock.elapsedRealtime()>=actionMessageUntil)message="已连接，可以拍摄";
            }
            changed();schedule(250);
        },error->{
            if(access==null||!access.isActive()){lost(error);return;}
            if(getFrame){viewPaused=true;viewMessage=error;viewStarted=false;}
            else{parameters.clear();parametersAt=0;message=error;}
            changed();schedule(800);
        });
    }
    private static final class PollResult {final Map<Integer,Long> parameters;final Frame frame;final boolean started;PollResult(Map<Integer,Long> p,Frame f,boolean s){parameters=p;frame=f;started=s;}}
    private interface Success<T>{void accept(T value);}
    private interface Failure{void accept(String error);}
    private <T> void run(AlbumController.RemoteWork<T> work,Success<T> success,Failure failure){
        if(access==null){failure.accept("相机已断开。");return;}workPending=true;final int ticket=generation;
        access.execute(work,new AlbumController.Callback<T>(){
            @Override public void onSuccess(T value){if(ticket!=generation)return;workPending=false;success.accept(value);drainDeferred();}
            @Override public void onError(String error){if(ticket!=generation)return;workPending=false;failure.accept(error);drainDeferred();}
        });
    }
    private void drainDeferred(){if(!workPending&&deferred!=null){Runnable next=deferred;deferred=null;next.run();}}
    public void capture(){
        if(!state().canCapture)return;
        outcome=Outcome.PREPARING;message="正在准备拍摄…";checkedUnknown=false;changed();
        if(workPending){deferred=this::dispatchCapture;return;}dispatchCapture();
    }
    private void dispatchCapture(){
        minimumHistogramSequence=frame==null?sequence+1:frame.sequence+1;
        rawObservedAt=0;
        run(camera->{
            Map<Integer,Long> current=camera.parameters();Long shutter=current.get(0x500d);
            if(!Long.valueOf(1).equals(current.get(0x5013))||shutter==null||shutter<=0||shutter>=0xfffffffeL)throw new IOException("请在机身使用单张拍摄和普通快门时间后重试。");
            Set<Long> before=camera.inventory();StringBuilder handles=new StringBuilder();for(long h:before)handles.append(h).append(',');
            Long quality=current.get(0x5004);boolean jpeg=quality!=null&&(quality<=2||quality>=5&&quality<=7);
            if(!journal.edit().putBoolean("pending",true).putString("camera",camera.identity).putString("baseline",handles.toString()).putBoolean("jpegExpected",jpeg).putLong("time",System.currentTimeMillis()).commit())throw new IOException("无法保存拍摄核对记录，本次未发送快门。");
            try{camera.release();}catch(PtpResponseException response){int code=response.responseCode();if(code==0x2019||code==0x2005||code==0x2006||code==0x200f||code==0x201d){if(!journal.edit().clear().commit())throw new IOException("相机拒绝了快门，但核对记录未清除，请核对后继续。",response);}throw response;}
            return before;
        },before->{baseline=before;baselineValid=true;expectJpeg=journal.getBoolean("jpegExpected",false);outcome=Outcome.CAPTURING;deadline=SystemClock.elapsedRealtime()+60000;nextCaptureCheck=0;message="正在拍摄，请等待相机结果…";changed();schedule(350);},error->{
            if(journal.getBoolean("pending",false)){baseline=readBaseline();outcome=Outcome.UNKNOWN;message="拍摄结果待确认 · 查看相机照片";}
            else{outcome=Outcome.IDLE;actionMessage(error);}changed();if(visible)schedule(250);else stop();
        });
    }
    private Set<Long> readBaseline(){Set<Long> result=new LinkedHashSet<>();baselineValid=journal.contains("baseline");for(String h:journal.getString("baseline","").split(","))try{if(!h.isEmpty()){long value=Long.parseLong(h);if(value<=0||value>=0xffffffffL)baselineValid=false;else result.add(value);}}catch(NumberFormatException ignored){baselineValid=false;}return result;}
    private void checkCapture(boolean explicit){
        if(access==null||!access.isActive()||workPending)return;
        if(!journal.getString("camera","").equals(access.camera.identity)){message="请连接上次拍摄的相机后核对";changed();return;}
        if(!baselineValid){checkedUnknown=true;message="上次拍摄记录不完整，请在相机上手动核对最近照片";changed();return;}
        run(camera->camera.newPhotos(baseline),photos->{
            if(NikonRemoteCamera.oneExposure(photos)){
                boolean jpeg=false;for(NikonRemoteCamera.CapturedPhoto photo:photos)if(photo.jpeg())jpeg=true;
                if(outcome==Outcome.CAPTURING&&expectJpeg&&!jpeg){
                    if(rawObservedAt==0)rawObservedAt=SystemClock.elapsedRealtime();
                    if(SystemClock.elapsedRealtime()-rawObservedAt<10000){message="RAW 已保存，等待配套 JPEG…";nextCaptureCheck=SystemClock.elapsedRealtime()+350;changed();schedule(250);return;}
                }
                confirmed(photos);return;
            }
            if(explicit){checkedUnknown=true;message=photos.isEmpty()?"未发现新照片；请核对相机后再恢复拍摄":"检测到多次拍摄，请核对相机最近照片后再继续";}
            nextCaptureCheck=SystemClock.elapsedRealtime()+800;changed();schedule(250);
        },error->{if(explicit){checkedUnknown=true;message=error;}else if(access==null||!access.isActive()){lost(error);return;}nextCaptureCheck=SystemClock.elapsedRealtime()+1200;changed();schedule(500);});
    }
    private void confirmed(List<NikonRemoteCamera.CapturedPhoto> photos){
        if(!journal.edit().clear().commit()){outcome=Outcome.UNKNOWN;message="新照片已找到，核对记录保存失败，请重试核对";changed();return;}
        recent=photos.get(0);for(NikonRemoteCamera.CapturedPhoto photo:photos)if(photo.jpeg())recent=photo;
        outcome=Outcome.CONFIRMED;imported=null;message="已保存到相机 · "+recent.object.filename();parametersAt=0;
        NikonRemoteCamera.CapturedPhoto photo=recent;
        run(camera->{try{return camera.thumbnail(photo.handle);}catch(IOException unavailable){return null;}},jpeg->{
            thumbnail=decodeThumbnail(jpeg);changed();
            if(transfer&&photo.jpeg())importRecent();else{if(transfer&&!photo.jpeg())message="已保存到相机，本次未取得 JPEG";if(!visible)stop();else schedule(0);}
        },error->{message="照片已保存，预览暂不可用";changed();if(visible)schedule(0);else stop();});changed();
    }
    private static Bitmap decodeThumbnail(byte[] jpeg){if(jpeg==null)return null;BitmapFactory.Options options=new BitmapFactory.Options();options.inJustDecodeBounds=true;BitmapFactory.decodeByteArray(jpeg,0,jpeg.length,options);if(options.outWidth<=0||options.outHeight<=0||options.outWidth>60000||options.outHeight>60000)return null;options.inJustDecodeBounds=false;options.inSampleSize=1;while(options.outWidth/options.inSampleSize>512||options.outHeight/options.inSampleSize>512)options.inSampleSize*=2;return BitmapFactory.decodeByteArray(jpeg,0,jpeg.length,options);}
    public void verifyUnknown(){if(outcome==Outcome.UNKNOWN){checkedUnknown=false;message="正在核对相机最近照片…";changed();if(workPending)deferred=()->checkCapture(true);else checkCapture(true);}}
    public boolean mayAcknowledge(){return outcome==Outcome.UNKNOWN&&checkedUnknown&&!workPending;}
    public void acknowledgeChecked(){if(!mayAcknowledge())return;if(!journal.edit().clear().commit()){message="无法保存核对结果，请重试。";changed();return;}outcome=Outcome.IDLE;checkedUnknown=false;message="已完成手动核对，可以继续拍摄";changed();schedule(0);}
    private void actionMessage(String value){message=value;actionMessageUntil=SystemClock.elapsedRealtime()+4000;}
    public void focus(Double x,Double y){if(!state().canFocus)return;RemoteLiveFrame wire=frame.wire;userWork=true;message="正在对焦…";changed();Runnable operation=()->run(camera->{camera.focus(wire,x,y);return null;},none->{userWork=false;actionMessage("对焦请求已发送");changed();schedule(0);},error->{userWork=false;actionMessage(error);changed();schedule(250);});if(workPending)deferred=operation;else operation.run();}
    public void retryView(){if(access==null||!access.isActive()){start();return;}viewPaused=false;viewStarted=false;minimumHistogramSequence=frame==null?sequence+1:frame.sequence+1;viewMessage="正在恢复实时画面…";changed();schedule(0);}
    public void setLiveEnabled(boolean enabled){if(liveEnabled==enabled)return;liveEnabled=enabled;viewPaused=false;
        if(!enabled){viewMessage="实时取景已关闭";}
        else{viewStarted=false;viewMessage="等待实时画面…";}changed();schedule(0);
    }
    public void setTransfer(boolean enabled){transfer=enabled;changed();}
    public void importRecent(){
        if(recent==null||!recent.jpeg()||imported!=null||userWork||pending())return;
        if(access==null||!access.isActive()){message="相机已断开，请重连后传入 JPEG。";changed();return;}
        userWork=true;if(workPending){deferred=this::dispatchImport;changed();return;}dispatchImport();
    }
    private void dispatchImport(){
        workPending=true;importing=true;importProgress.reset();message="正在传入 App…";changed();final int ticket=generation;
        album.downloadRemoteCaptured(access,recent,new AlbumController.DownloadCallback(){
            @Override public void onStarted(long total){if(ticket!=generation)return;importProgress.start(total,PhotoTransferProgress.now());changed();}
            @Override public void onProgress(long done,long total){if(ticket!=generation)return;importProgress.update(done,total,PhotoTransferProgress.now());message="正在传入 App · "+(total>0?Math.round(done*100.0/total)+"%":"读取中");changed();}
            @Override public void onSuccess(DownloadedPhoto photo){if(ticket!=generation)return;importing=false;workPending=false;userWork=false;imported=photo;message="已传入 App · "+photo.filename();changed();drainDeferred();if(visible)schedule(0);else stop();}
            @Override public void onError(String error){if(ticket!=generation)return;importing=false;workPending=false;userWork=false;message="照片已保存到相机，传入未完成："+error;changed();drainDeferred();if(visible)schedule(500);else stop();}
        });
    }
    public void disconnect(){if(pending())outcome=Outcome.UNKNOWN;stop();runtime.disconnect();lost("相机已断开。");}
    public void reconnect(){if(opening||workPending)return;stop();message="正在重新连接相机…";opening=true;changed();
        ConnectionInfo last=album.lastRemoteConnection();if(last==null){opening=false;message="请返回同步，在设置中重新连接相机 Wi-Fi";changed();return;}
        album.connectCamera(last.host(),last.port(),CameraProtocol.NIKON,new AlbumController.Callback<ConnectionInfo>(){
            @Override public void onSuccess(ConnectionInfo value){opening=false;start();}
            @Override public void onError(String error){opening=false;message=error;changed();}
        });
    }
    private void lost(String error){if(journal.getBoolean("pending",false))outcome=Outcome.UNKNOWN;else if(pending())outcome=Outcome.IDLE;checkedUnknown=false;parameters.clear();parametersAt=0;viewPaused=true;viewMessage="相机已断开";message=outcome==Outcome.UNKNOWN?"拍摄结果待确认 · 重连后核对":error;closeAccess();changed();}
    private void releaseService(){if(service!=null){service.close();service=null;}}
    private void closeAccess(){generation++;opening=false;importing=false;workPending=false;userWork=false;deferred=null;if(access!=null){access.close();access=null;}viewStarted=false;viewMayBeRunning=false;releaseService();main.removeCallbacks(polling);}
    public void stop(){if(pending())return;closeAccess();}
}
