package cc.huevia.connection164qa;

import android.app.*;
import android.content.*;
import android.os.*;
import android.graphics.Bitmap;
import android.view.*;
import android.widget.*;
import cc.huevia.album.*;
import cc.huevia.connection.*;
import cc.huevia.ptp.*;
import cc.huevia.usb.UsbPictureControlProbe;
import java.io.*;
import java.lang.reflect.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.atomic.AtomicReference;
import org.json.*;

/** Exact installed Activity flow. Synthetic PTP/IP peer only; never claims physical USB success. */
public final class Connection164Probe extends Instrumentation {
    private Bundle args;private Activity source,guide;private File output;private CameraConnectionRuntime runtime;private FakeNikonPeer peer;private Dialog dialog;private Throwable failure;
    private final JSONArray checks=new JSONArray();
    @Override public void onCreate(Bundle args){this.args=args;start();}
    @Override public void onStart(){try{
        check("ranchu".equals(Build.HARDWARE)||"goldfish".equals(Build.HARDWARE),"owned-emulator");
        check(getTargetContext().getPackageManager().getPackageInfo("cc.huevia",0).getLongVersionCode()==164,"installed164");
        check(sha(new File(getTargetContext().getApplicationInfo().sourceDir)).equals(args.getString("candidateSha256")),"exact-installed-APK");
        String run=args.getString("runId");check(run.matches("[A-Za-z0-9.-]{8,100}"),"safe-evidence-id");output=new File(getTargetContext().getExternalFilesDir(null),"connection164/"+run);check(output.mkdirs(),"new-evidence-directory");
        runtime=CameraConnectionRuntime.get(getTargetContext());ui(runtime::disconnect);
        source=startActivitySync(new Intent(Intent.ACTION_MAIN).setClassName("cc.huevia","cc.huevia.MainActivity").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK|Intent.FLAG_ACTIVITY_CLEAR_TASK));until(()->(Boolean)get(source,"ready"),"main-ready");
        check(!((Boolean)call(source,"currentConnectionReady",false)),"no-device-not-connected");
        UsbPictureControlProbe.Result info=new UsbPictureControlProbe.Result();info.deviceInfoOnly=true;info.deviceInfoRead=true;info.completed=true;info.manufacturer="Nikon Corporation";info.model="Z 7_2";info.operations=new int[]{0x1001};
        Method validate=source.getClass().getDeclaredMethod("validateUsbConnectionInfo",UsbPictureControlProbe.Result.class);validate.setAccessible(true);validate.invoke(null,info);check(true,"ordinary-connection-validator-needs-no-preset-ops");
        boolean rejected=false;try{call(source,"validateSnapshot",info);}catch(Exception expected){rejected=true;}check(rejected,"device-info-only-cannot-be-used-as-preset-snapshot");
        for(String flag:new String[]{"completed","deviceInfoRead","deviceInfoOnly"}){set(info,flag,false);rejected=false;try{validate.invoke(null,info);}catch(InvocationTargetException expected){rejected=true;}check(rejected,"incomplete-info-cannot-connect-"+flag);set(info,flag,true);}
        info.protocolPhaseUnconfirmed=true;rejected=false;try{validate.invoke(null,info);}catch(InvocationTargetException expected){rejected=true;}check(rejected,"unconfirmed-protocol-cannot-connect");info.protocolPhaseUnconfirmed=false;
        JSONObject json=info.toJson();check("nikon_device_info_only".equals(json.getString("probeMode"))&&json.getBoolean("deviceInfoOnly")&&!json.getBoolean("serialNumberCollected")&&json.isNull("shootingMenu"),"real-Android-report-schema-distinguishes-identification");
        Constructor<UsbPictureControlProbe.ProbeException> errorConstructor=UsbPictureControlProbe.ProbeException.class.getDeclaredConstructor(String.class,Integer.class,UsbPictureControlProbe.Result.class,Throwable.class);errorConstructor.setAccessible(true);
        Exception error=errorConstructor.newInstance("相机未声明预设读取接口",null,info,new IOException("fixture capability refusal"));
        String readable=(String)call(source,"readable",error);check(readable.contains(info.manufacturer)&&readable.contains(info.model)&&!readable.contains("仅支持"),"capability-error-shows-actual-maker-model");
        // Real connection Activity result flow, without an attached USB device.
        ActivityMonitor monitor=addMonitor("cc.huevia.MainActivity",null,false);ui(()->CameraConnectionRequest.open(source,"查看相机详情",CameraConnectionRequest.USB));guide=monitor.waitForActivityWithTimeout(15000);removeMonitor(monitor);check(guide!=null,"USB-guide-opens");until(()->(Boolean)get(guide,"ready"),"USB-guide-ready");
        ui(()->{set(guide,"verifiedUsbId",17);set(guide,"usbModel","Z 7_2");set(guide,"usbManufacturer","Nikon Corporation");});check(!(Boolean)call(guide,"requestedConnectionReady"),"unattached-id-never-marks-USB-connected");check((Integer)get(guide,"verifiedUsbId")==-1&&"".equals(get(guide,"usbManufacturer")),"detached-identity-cleared");
        ui(()->call(guide,"render"));check(findTag(guide.getWindow().getDecorView(),"connection-return-action")==null,"no-success-return-without-device");capture("01-usb-disconnected-guide");ui(()->call(guide,"goBack"));until(()->(Boolean)get(source,"activityVisible"),"USB-cancel-returns-source");
        // Peer provides Z7II device info but no Picture Control read/register operations.
        peer=new FakeNikonPeer(new byte[0],40,30);PtpIpClient client=new PtpIpClient(peer);byte[] raw=client.connect("fixture-only",15740,new byte[16],"Connection164 QA");PtpDeviceInfo parsed=PtpDeviceInfo.parseRedacted(raw);
        check(parsed.model().equals("Z 7_2")&&parsed.manufacturer().equals("Nikon Corporation"),"standard-PTPIP-reads-Z7II-identity");check(!parsed.supportsOperation(0x90cf)&&!parsed.supportsOperation(0x90cc)&&!parsed.supportsOperation(0x90cd),"peer-has-no-preset-capability");
        Constructor<ConnectionInfo> ctor=ConnectionInfo.class.getDeclaredConstructor(String.class,String.class,int.class,int.class,CameraProtocol.class,String.class);ctor.setAccessible(true);ConnectionInfo identity=ctor.newInstance(parsed.model(),"fixture-only",15740,0,CameraProtocol.NIKON,parsed.manufacturer());
        ui(()->{set(runtime.album,"active",client);set(runtime.album,"sessionConnectionInfo",identity);set(runtime.album,"cachedConnectionInfo",null);set(runtime.album,"deviceInfo",parsed);set(runtime.album,"session","");set(runtime.album,"handles",new long[0]);runtime.changed();});
        until(()->(Boolean)call(source,"currentConnectionReady",false),"ordinary-WiFi-session-not-gated-by-preset-capability");
        Object album=get(source,"album");check(call(album,"connectionManufacturer").equals(parsed.manufacturer())&&call(album,"connectionModel").equals(parsed.model()),"actual-session-identity-reaches-UI");
        monitor=addMonitor("cc.huevia.MainActivity",null,false);ui(()->CameraConnectionRequest.open(source,"查看相机详情",CameraConnectionRequest.ANY));guide=monitor.waitForActivityWithTimeout(15000);removeMonitor(monitor);check(guide!=null,"shared-connection-guide-opens");until(()->(Boolean)get(guide,"ready")&&findTag(guide.getWindow().getDecorView(),"connection-return-action")!=null,"Z7II-connected-return-visible");check(!getUiAutomation().getRootInActiveWindow().findAccessibilityNodeInfosByText("Z 7_2").isEmpty()&&!getUiAutomation().getRootInActiveWindow().findAccessibilityNodeInfosByText("Nikon Corporation").isEmpty(),"connected-guide-shows-real-maker-and-model");capture("02-z7ii-connected-return");
        ui(()->findTag(guide.getWindow().getDecorView(),"connection-return-action").performClick());until(()->(Boolean)get(source,"activityVisible"),"connected-return-source-preserved");
        ui(()->call(source,"showCameraDetails"));until(()->getUiAutomation().getRootInActiveWindow()!=null&&!getUiAutomation().getRootInActiveWindow().findAccessibilityNodeInfosByText("Nikon Corporation").isEmpty(),"details-show-real-manufacturer");
        check(!getUiAutomation().getRootInActiveWindow().findAccessibilityNodeInfosByText("Z 7_2").isEmpty(),"details-show-real-model");capture("03-z7ii-details");getUiAutomation().performGlobalAction(android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_BACK);waitForIdleSync();
        ui(()->{dialog=new cc.huevia.ui.AppDialog.Builder(source).setTitle("预设暂不可用").setMessage(readable).setPositiveButton("关闭",null).show();});capture("04-actual-camera-capability-error");ui(dialog::dismiss);
        for(int op:peer.operations)check(op!=0x90cf&&op!=0x90cc&&op!=0x90cd,"ordinary-connection-never-reads-or-writes-PC-"+Integer.toHexString(op));check(peer.shutters==0,"connection-check-never-shoots");
    }catch(Throwable error){failure=unwrap(error);}finally{try{if(dialog!=null&&dialog.isShowing())ui(dialog::dismiss);if(guide!=null&&!guide.isFinishing())ui(guide::finish);if(runtime!=null)ui(runtime::disconnect);if(peer!=null)peer.close();if(source!=null&&!source.isFinishing())ui(source::finish);}catch(Throwable cleanup){if(failure==null)failure=unwrap(cleanup);}writeReport();Bundle result=new Bundle();result.putString("pass",String.valueOf(failure==null));result.putInt("checks",checks.length());if(failure!=null)result.putString("failure",failure.toString());finish(failure==null?0:1,result);}}
    private void writeReport(){try{if(output!=null)Files.write(new File(output,"report.json").toPath(),new JSONObject().put("pass",failure==null).put("apkSha256",args.getString("candidateSha256")).put("checks",checks).put("failure",failure==null?JSONObject.NULL:failure.toString()).put("scope","Installed164 Activity navigation, no-device USB guard, identification-vs-preset validators, Android JSON report, actual model/manufacturer display and error copy. Synthetic byte-framed PTP/IP client handshake; connected fixture session injected into shared controller only for UI return verification. No physical USB or camera success claim; host test owns real USB transport framing/lifecycle with scripted peer.").toString(2).getBytes(StandardCharsets.UTF_8));}catch(Exception error){failure=error;}}
    private void capture(String name)throws Exception{waitForIdleSync();SystemClock.sleep(450);Bitmap b=getUiAutomation().takeScreenshot();try(FileOutputStream file=new FileOutputStream(new File(output,name+".png"))){check(b!=null&&b.compress(Bitmap.CompressFormat.PNG,100,file),"captured-"+name);}finally{if(b!=null)b.recycle();}}
    private interface Work{void run()throws Exception;}private interface Condition{boolean test()throws Exception;}
    private void ui(Work work)throws Exception{AtomicReference<Throwable> error=new AtomicReference<>();runOnMainSync(()->{try{work.run();}catch(Throwable failure){error.set(failure);}});if(error.get()!=null)throw new RuntimeException(error.get());}
    private void until(Condition condition,String name)throws Exception{long end=SystemClock.uptimeMillis()+15000;while(SystemClock.uptimeMillis()<end){if(condition.test()){check(true,name);return;}SystemClock.sleep(40);}throw new AssertionError(name);}
    private void check(boolean pass,String name)throws Exception{checks.put(new JSONObject().put("name",name).put("pass",pass));if(!pass)throw new AssertionError(name);}
    private static Field field(Class<?> type,String name)throws Exception{for(Class<?> c=type;c!=null;c=c.getSuperclass())try{Field f=c.getDeclaredField(name);f.setAccessible(true);return f;}catch(NoSuchFieldException ignored){}throw new NoSuchFieldException(name);}
    private static Object get(Object object,String name)throws Exception{return field(object.getClass(),name).get(object);}private static void set(Object object,String name,Object value)throws Exception{field(object.getClass(),name).set(object,value);}
    private static Object call(Object object,String name,Object...args)throws Exception{for(Class<?> c=object.getClass();c!=null;c=c.getSuperclass())for(Method m:c.getDeclaredMethods())if(m.getName().equals(name)&&m.getParameterCount()==args.length){m.setAccessible(true);try{return m.invoke(object,args);}catch(IllegalArgumentException ignored){}catch(InvocationTargetException wrapped){throw new Exception(wrapped.getCause());}}throw new NoSuchMethodException(name);}
    private static View findTag(View view,String tag){if(tag.equals(view.getTag()))return view;if(view instanceof ViewGroup)for(int i=0;i<((ViewGroup)view).getChildCount();i++){View child=findTag(((ViewGroup)view).getChildAt(i),tag);if(child!=null)return child;}return null;}
    private static String sha(File f)throws Exception{byte[] value=MessageDigest.getInstance("SHA-256").digest(Files.readAllBytes(f.toPath()));StringBuilder out=new StringBuilder();for(byte b:value)out.append(String.format(Locale.ROOT,"%02x",b&255));return out.toString();}
    private static Throwable unwrap(Throwable t){while(t.getCause()!=null&&(t instanceof java.lang.reflect.InvocationTargetException||t instanceof RuntimeException))t=t.getCause();return t;}
}
