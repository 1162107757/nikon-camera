package cc.huevia.remotecaptureqa;

import android.app.*;
import android.content.*;
import android.graphics.Bitmap;
import android.os.*;
import android.view.*;
import android.widget.*;
import cc.huevia.connection.*;
import cc.huevia.album.*;
import cc.huevia.ptp.PtpDeviceInfo;
import java.io.*;
import java.lang.reflect.*;
import java.util.concurrent.atomic.AtomicReference;
import org.json.*;

/** Real production Activities and activity results. Camera protocol data is an in-process fixture. */
public final class ConnectionReturnProbe extends Instrumentation {
    private Activity source, guide;
    private Bundle args;
    private File output;
    private final JSONArray checks = new JSONArray();
    private CameraConnectionRuntime runtime;
    private FakeNikonPeer peer;
    private String previousAppearance;
    @Override public void onCreate(Bundle values) { args = values == null ? new Bundle() : values; start(); }
    @Override public void onStart() {
        Bundle result = new Bundle(); JSONObject report = new JSONObject();
        try {
            check(Build.HARDWARE.equals("ranchu") || Build.HARDWARE.equals("goldfish"), "owned-emulator-only");
            check(getTargetContext().getPackageManager().getPackageInfo("cc.huevia",0).getLongVersionCode()==156,"candidate-version-156");
            byte[] candidate = java.nio.file.Files.readAllBytes(new File(getTargetContext().getApplicationInfo().sourceDir).toPath());
            StringBuilder digest = new StringBuilder(); for(byte value:java.security.MessageDigest.getInstance("SHA-256").digest(candidate)) digest.append(String.format("%02x",value&255));
            check(digest.toString().equals(args.getString("candidateSha256")),"exact-candidate-apk");
            previousAppearance=cc.huevia.ui.AppAppearance.mode(getTargetContext());
            cc.huevia.ui.AppAppearance.setMode(getTargetContext(),args.getString("mode","phone").equals("dark")?"dark":"light");
            output = new File(getTargetContext().getExternalFilesDir(null), "connection-return156/" + args.getString("mode","phone")); output.mkdirs();
            runtime = CameraConnectionRuntime.get(getTargetContext());
            ui(() -> runtime.disconnect());
            source = startActivitySync(new Intent(Intent.ACTION_MAIN).setClassName("cc.huevia","cc.huevia.MainActivity").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK|Intent.FLAG_ACTIVITY_CLEAR_TASK));
            until(() -> (Boolean)get(source,"ready"),"main ready");
            check(cc.huevia.ui.AppAppearance.isDark(source)==args.getString("mode","phone").equals("dark"),"actual-app-theme");
            check(Math.abs(source.getResources().getConfiguration().fontScale-(args.getString("mode","").equals("font1.3")?1.3f:1f))<.02f,"actual-font-scale");
            until(()->(source.getResources().getConfiguration().orientation==2)==args.getString("mode","").equals("landscape"),"actual-orientation-settled");
            check((source.getResources().getConfiguration().orientation==2)==args.getString("mode","").equals("landscape"),"actual-orientation");
            ui(() -> { call(source,"switchRoot",1); set(get(source,"album"),"liveTab",false); call(source,"render"); }); settle();

            // A real disconnected remote-entry click goes straight to the guide, with no prerequisite modal.
            open(() -> findTag(source.getWindow().getDecorView(),"sync-remote-capture").performClick());
            check("进入遥控拍摄".equals(get(guide,"connectionOperation")),"remote-entry-direct-route");
            commonGuideChecks(); capture("01-disconnected-guide");
            ui(() -> call(guide,"goBack")); until(() -> (Boolean)get(source,"activityVisible"),"cancel returns");
            check(!source.isFinishing() && (Boolean)get(source,"albumTab"),"cancel-retains-sync-source");

            Object album = get(source,"album"), raw = get(album,"rawPanel");
            open(() -> call(raw,"open",false));
            check((Boolean)call(raw,"isOpen"),"raw-source-open");
            check("查看 RAW 文件".equals(get(guide,"connectionOperation")),"raw-direct-route");
            commonGuideChecks();
            // Recreating the connector must keep the Activity result target and operation label.
            Activity previous = guide; ActivityMonitor monitor = addMonitor("cc.huevia.MainActivity",null,false);
            ui(() -> guide.recreate()); guide = monitor.waitForActivityWithTimeout(15000); removeMonitor(monitor);
            check(guide != null && guide != previous,"guide-recreated"); until(() -> (Boolean)get(guide,"ready"),"recreated ready");
            check("查看 RAW 文件".equals(get(guide,"connectionOperation")),"recreated-operation-preserved");
            injectCamera();
            until(() -> findTag(guide.getWindow().getDecorView(),"connection-return-action") != null,"return action ready");
            settle(); returnGeometry();
            capture("02-connected-return");
            ui(() -> findTag(guide.getWindow().getDecorView(),"connection-return-action").performClick());
            until(() -> (Boolean)get(source,"activityVisible"),"success returns"); settle();
            check((Boolean)call(raw,"isOpen") && !(Boolean)get(source,"settingsTab"),"success-retains-original-raw-page");
            check(peer.shutters==0,"connection-return-never-fires-shutter");
            capture("03-returned-raw");

            ui(() -> { call(raw,"goBack"); runtime.disconnect(); }); settle();
            ui(() -> {set(album,"downloadedTab",true);set(album,"liveTab",false);call(source,"render");});settle();
            open(() -> call(album,"chooseTab",false));
            check("浏览相机照片".equals(get(guide,"connectionOperation")),"camera-tab-direct-route");
            ui(() -> call(guide,"goBack"));until(() -> (Boolean)get(source,"activityVisible"),"camera tab cancel");settle();
            // Each camera-photo operation uses the same request workspace and returns to the original root.
            for (String operation : new String[]{"浏览相机照片","下载相机原图","继续未完成下载","下载照片并套用预设","重试接收照片","查看相机详情"}) {
                open(() -> call(source,"showConnectionRequired",operation));
                check(operation.equals(get(guide,"connectionOperation")),"operation-remembered-"+operation);
                check(!"查看相机详情".equals(operation) || "any".equals(get(guide,"connectionTransport")),"details-offers-usb-and-wifi");
                ui(() -> call(guide,"goBack")); until(() -> (Boolean)get(source,"activityVisible"),"operation cancel"); settle();
            }

            ui(() -> call(source,"showPhotoLiveConnectionRequired")); settle();
            check((Boolean)get(source,"settingsTab") && (Boolean)call(album,"isConnectionGuide"),"photo-live-direct-guide");
            check(((PhotoLiveContinuation)get(source,"photoLiveContinuation")).isPending(),"photo-live-return-intent-kept");
            ui(() -> call(source,"goBack")); settle();
            check((Boolean)get(source,"albumTab") && !((PhotoLiveContinuation)get(source,"photoLiveContinuation")).isPending(),"photo-live-cancel-returns-once");

            // A successful remote-entry request opens the remote workspace once, without taking a photo.
            open(() -> call(album,"openRemoteCapture")); injectCamera();
            until(() -> findTag(guide.getWindow().getDecorView(),"connection-return-action") != null,"remote return ready");
            ActivityMonitor remoteMonitor = addMonitor("cc.huevia.RemoteCaptureActivity",null,false);
            ui(() -> findTag(guide.getWindow().getDecorView(),"connection-return-action").performClick());
            Activity remote = remoteMonitor.waitForActivityWithTimeout(10000); removeMonitor(remoteMonitor); check(remote!=null,"success-opens-requested-remote-workspace");
            until(() -> ((cc.huevia.remote.RemoteCaptureController)get(remote,"controller")).state().connected,"remote fixture ready");
            check(peer.shutters==0,"remote-entry-does-not-replay-capture");
            ui(() -> runtime.disconnect());
            until(() -> !((cc.huevia.remote.RemoteCaptureController)get(remote,"controller")).state().connected,"remote disconnected"); settle();
            open(() -> ((View)get(get(get(remote,"surface"),"stage"),"retry")).performClick());
            check("继续遥控拍摄".equals(get(guide,"connectionOperation")),"remote-reconnect-direct-route");
            capture("04-remote-reconnect-guide");
            ui(() -> call(guide,"goBack")); settle();
            check(!remote.isFinishing(),"remote-cancel-retains-workspace"); ui(remote::finish); settle();

            ActivityMonitor diagnostics = addMonitor("cc.huevia.DiagnosticsActivity",null,false);
            ui(() -> source.startActivity(new Intent().setClassName("cc.huevia","cc.huevia.DiagnosticsActivity")));
            Activity lab = diagnostics.waitForActivityWithTimeout(10000); removeMonitor(diagnostics); check(lab!=null,"diagnostics-opened"); settle();
            ActivityMonitor next = addMonitor("cc.huevia.MainActivity",null,false);
            ui(() -> { Object action = Enum.valueOf((Class)getTargetContext().getClassLoader().loadClass("cc.huevia.DiagnosticsActivity$UsbAction"),"CAPABILITIES"); call(lab,"detectCamera",action); });
            guide = next.waitForActivityWithTimeout(10000); removeMonitor(next); check(guide!=null,"diagnostics-direct-route");
            until(() -> (Boolean)get(guide,"ready"),"USB guide ready");
            check("usb".equals(get(guide,"connectionTransport")),"diagnostics-usb-only"); capture("05-usb-guide");
            ui(() -> call(guide,"goBack")); settle(); check(!lab.isFinishing(),"diagnostics-cancel-keeps-existing-screen"); ui(lab::finish);
            until(() -> (Boolean)get(source,"activityVisible"),"diagnostics returns to main");settle();
            ui(() -> call(source,"switchRoot",3));settle();
            Object localEditorHost=get(get(source,"localPhotoEditor"),"host");
            open(() -> call(localEditorHost,"onConnectionRequired","下载 RAW 原文件"));
            check("下载 RAW 原文件".equals(get(guide,"connectionOperation")),"local-editor-raw-callback-direct-route");
            ui(() -> call(guide,"goBack"));until(() -> (Boolean)get(source,"activityVisible"),"local editor cancel");settle();
            check((Boolean)get(source,"localAlbumTab"),"local-editor-return-keeps-local-album-root");
            report.put("pass",true); result.putString("status","PASS");
        } catch(Throwable failure) {
            try { report.put("pass",false).put("error",failure.toString()); } catch(Exception ignored) {}
            result.putString("status","FAIL: "+failure);
            StringWriter stack=new StringWriter();failure.printStackTrace(new PrintWriter(stack));result.putString("stack",stack.toString());
        } finally {
            try { ui(() -> runtime.disconnect()); if(peer!=null)peer.close(); if(previousAppearance!=null)cc.huevia.ui.AppAppearance.setMode(getTargetContext(),previousAppearance); report.put("candidateSha256",args.getString("candidateSha256")).put("checks",checks).put("scope","Production navigation; in-process PTP fixture, no physical camera or USB hardware claim"); if(output!=null)try(FileOutputStream out=new FileOutputStream(new File(output,"report.json"))){out.write(report.toString(2).getBytes("UTF-8"));} } catch(Exception ignored){}
            finish(Activity.RESULT_OK,result);
        }
    }
    private void commonGuideChecks() throws Exception {
        check("连接相机".equals(((TextView)get(guide,"title")).getText().toString()),"connection-title");
        check(findTag(guide.getWindow().getDecorView(),"root-floating-navigation")==null,"guide-has-no-root-navigation");
        check(findTag(guide.getWindow().getDecorView(),"connection-return-action")==null,"no-success-return-before-connection");
        check(!source.isFinishing(),"source-kept-on-back-stack");
    }
    private void open(Work action) throws Exception {
        ActivityMonitor monitor=addMonitor("cc.huevia.MainActivity",null,false); ui(action);
        guide=null; long end=SystemClock.uptimeMillis()+12000;
        while(SystemClock.uptimeMillis()<end){Activity candidate=monitor.waitForActivityWithTimeout(500);if(candidate!=null&&candidate!=source&&!candidate.isFinishing()){guide=candidate;break;}}
        removeMonitor(monitor);check(guide!=null,"guide-opened-without-second-tap");
        until(()->(Boolean)get(guide,"ready"),"guide ready");settle();
    }
    private void injectCamera() throws Exception {
        if (peer != null) peer.close();
        Bitmap bitmap=Bitmap.createBitmap(40,30,Bitmap.Config.ARGB_8888);ByteArrayOutputStream jpeg=new ByteArrayOutputStream();bitmap.compress(Bitmap.CompressFormat.JPEG,90,jpeg);bitmap.recycle();
        peer=new FakeNikonPeer(jpeg.toByteArray(),40,30);PtpIpClient client=new PtpIpClient(peer);client.connect("fixture-only",15740,new byte[16],"Connection return QA");
        Constructor<ConnectionInfo> c=ConnectionInfo.class.getDeclaredConstructor(String.class,String.class,int.class,int.class,CameraProtocol.class);c.setAccessible(true);ConnectionInfo info=c.newInstance("NIKON Z 6_2","fixture-only",15740,1,CameraProtocol.NIKON);
        ui(()->{set(runtime.album,"active",client);set(runtime.album,"sessionConnectionInfo",info);set(runtime.album,"cachedConnectionInfo",info);set(runtime.album,"deviceInfo",PtpDeviceInfo.parse(peer.info));set(runtime.album,"session","connection-return-qa");set(runtime.album,"handles",new long[]{10});runtime.changed();});
    }
    private void returnGeometry() throws Exception {
        View button=findTag(guide.getWindow().getDecorView(),"connection-return-action");
        float density=guide.getResources().getDisplayMetrics().density;
        check(button.getWidth()>=48*density && button.getHeight()>=48*density,"return-target-at-least-48dp");
        android.graphics.Rect visible=new android.graphics.Rect();
        check(button.getGlobalVisibleRect(visible)&&visible.height()==button.getHeight(),"return-button-fully-visible");
    }
    private void capture(String name) throws Exception { settle();Bitmap image=getUiAutomation().takeScreenshot();try(FileOutputStream out=new FileOutputStream(new File(output,name+".png"))){image.compress(Bitmap.CompressFormat.PNG,100,out);}image.recycle(); }
    private View findTag(View root,String tag){if(tag.equals(root.getTag()))return root;if(root instanceof ViewGroup group)for(int i=0;i<group.getChildCount();i++){View found=findTag(group.getChildAt(i),tag);if(found!=null)return found;}return null;}
    private void check(boolean value,String name) throws Exception{checks.put(new JSONObject().put("name",name).put("pass",value));if(!value)throw new AssertionError(name);}
    private interface Work{void run() throws Exception;} private interface Condition{boolean test() throws Exception;}
    private void ui(Work work)throws Exception{AtomicReference<Throwable> error=new AtomicReference<>();runOnMainSync(()->{try{work.run();}catch(Throwable e){error.set(e);}});if(error.get()!=null)throw new RuntimeException(error.get());}
    private void until(Condition condition,String name)throws Exception{long end=SystemClock.uptimeMillis()+20000;while(SystemClock.uptimeMillis()<end){if(condition.test())return;SystemClock.sleep(40);}throw new AssertionError("Timeout "+name);}
    private void settle(){waitForIdleSync();SystemClock.sleep(200);}
    private Field field(Class<?> c,String name)throws Exception{for(;c!=null;c=c.getSuperclass())try{Field f=c.getDeclaredField(name);f.setAccessible(true);return f;}catch(NoSuchFieldException ignored){}throw new NoSuchFieldException(name);}
    private Object get(Object target,String name)throws Exception{return field(target.getClass(),name).get(target);}
    private void set(Object target,String name,Object value)throws Exception{field(target.getClass(),name).set(target,value);}
    private Object call(Object target,String name,Object... values)throws Exception{for(Class<?> c=target.getClass();c!=null;c=c.getSuperclass())for(Method m:c.getDeclaredMethods())if(m.getName().equals(name)&&m.getParameterCount()==values.length){m.setAccessible(true);try{return m.invoke(target,values);}catch(IllegalArgumentException ignored){}catch(InvocationTargetException e){throw new RuntimeException(e.getCause());}}throw new NoSuchMethodException(name);}
}
