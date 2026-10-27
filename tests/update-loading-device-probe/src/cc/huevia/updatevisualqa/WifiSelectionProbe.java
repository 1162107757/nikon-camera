package cc.huevia.updatevisualqa;

import android.app.Activity;
import android.app.AlertDialog;
import android.app.Instrumentation;
import android.content.Intent;
import android.content.IntentFilter;
import android.os.Bundle;
import android.os.SystemClock;
import android.provider.Settings;
import android.view.View;
import android.view.ViewGroup;
import android.widget.EditText;
import java.io.File;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.nio.file.Files;
import java.security.MessageDigest;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.Consumer;
import org.json.JSONArray;
import org.json.JSONObject;

/** Real MainActivity Wi-Fi entry, intercepted system-settings launch; never joins a camera network. */
public final class WifiSelectionProbe extends Instrumentation {
    private Bundle args;
    private Activity activity;
    private final JSONArray checks=new JSONArray();
    private Throwable failure;
    private ActivityMonitor monitor;
    @Override public void onCreate(Bundle args){this.args=args;start();}
    @Override public void onStart(){
        File output=null;
        try {
            check("owned-emulator",android.os.Build.HARDWARE.equals("ranchu")||android.os.Build.HARDWARE.equals("goldfish"));
            check("exact-apk",sha(new File(getTargetContext().getApplicationInfo().sourceDir)).equals(args.getString("candidateSha256")));
            output=new File(getTargetContext().getExternalFilesDir(null),"wifi-system-105/"+args.getString("runId"));check("output-created",output.mkdirs());
            activity=startActivitySync(new Intent().setClassName("cc.huevia","cc.huevia.MainActivity").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK|Intent.FLAG_ACTIVITY_CLEAR_TASK));
            for(int i=0;i<120;i++){boolean[] ready={false};ui(()->ready[0]=(Boolean)field(activity,"ready"));if(ready[0])break;SystemClock.sleep(50);}
            ui(()->check("main-ready",(Boolean)field(activity,"ready")));
            ui(()->{Object wifi=field(activity,"wifi");Method connected=wifi.getClass().getMethod("connectedWifiNetwork");check("no-wifi-fixture",connected.invoke(wifi)==null);});
            IntentFilter filter=new IntentFilter();filter.addAction(Settings.ACTION_WIFI_SETTINGS);filter.addAction(Settings.Panel.ACTION_WIFI);
            monitor=addMonitor(filter,new ActivityResult(Activity.RESULT_CANCELED,null),true);
            AtomicInteger connectedCalls=new AtomicInteger(),failedCalls=new AtomicInteger();
            ui(()->{Method ensure=activity.getClass().getDeclaredMethod("ensureCameraWifi",Runnable.class,Consumer.class);ensure.setAccessible(true);ensure.invoke(activity,(Runnable)connectedCalls::incrementAndGet,(Consumer<String>)value->failedCalls.incrementAndGet());});
            SystemClock.sleep(200);ui(()->{});
            check("system-selector-opened-without-extra-tap",monitor.getHits()==1);
            ui(()->{AlertDialog dialog=(AlertDialog)field(activity,"cameraWifiDialog");check("retry-dialog-retained",dialog!=null&&dialog.isShowing());View root=dialog.getWindow().getDecorView();check("no-ssid-password-input",countInputs(root)==0);check("no-manual-entry",!contains(root,"手动填写")&&!contains(root,"手动连接相机 Wi-Fi"));dialog.getButton(AlertDialog.BUTTON_NEGATIVE).performClick();});
            ui(()->{}); // AlertDialog dispatches its button callback through a posted Handler message.
            check("no-camera-connect-before-selection",connectedCalls.get()==0);
            check("cancel-delivered-once",failedCalls.get()==1);
            ui(()->check("pending-system-wait-cleared",field(activity,"pendingSystemWifiReturn")==null&&field(activity,"cameraWifiDialog")==null));
            ui(()->{
                set(activity,"localTab",false);set(activity,"loadingCatalog",true);
                set(activity,"catalogEpoch",((Integer)field(activity,"catalogEpoch"))+1);
                ((java.util.List<?>)field(activity,"catalog")).clear();
                invoke(activity,"render");
                check("real-main-uses-animated-loader",activity.getWindow().getDecorView().findViewWithTag("catalog-loading-animation")!=null);
                check("no-static-loading-empty-message",!contains(activity.getWindow().getDecorView(),"正在加载在线预设"));
            });
            capture(output,"main-loading.png");
            ui(()->{set(activity,"loadingCatalog",false);set(field(activity,"updates"),"open",true);invoke(activity,"render");check("real-main-update-heading",contains(activity.getWindow().getDecorView(),"应用更新"));});
            capture(output,"main-update-current.png");
        } catch(Throwable error){failure=error;}
        finally{
            try{if(monitor!=null)removeMonitor(monitor);if(activity!=null)ui(()->{Method cancel=activity.getClass().getDeclaredMethod("cancelPendingCameraWifi");cancel.setAccessible(true);cancel.invoke(activity);activity.finish();});}catch(Throwable cleanup){if(failure==null)failure=cleanup;}
            try{if(output!=null)Files.writeString(new File(output,"report.json").toPath(),new JSONObject().put("pass",failure==null).put("checks",checks).put("candidateSha256",args.getString("candidateSha256")).put("scope","Real MainActivity; system settings intent is intercepted and returned cancelled. No actual network selection, camera handshake or phone test.").put("failure",failure==null?JSONObject.NULL:failure.toString()).toString(2));}catch(Throwable write){failure=write;}
            Bundle result=new Bundle();result.putString("summary",failure==null?"PASS "+checks.length()+" checks":"FAIL "+failure);finish(failure==null?Activity.RESULT_OK:Activity.RESULT_CANCELED,result);
        }
    }
    private static int countInputs(View view){int n=view instanceof EditText?1:0;if(view instanceof ViewGroup)for(int i=0;i<((ViewGroup)view).getChildCount();i++)n+=countInputs(((ViewGroup)view).getChildAt(i));return n;}
    private void capture(File output,String name)throws Exception{SystemClock.sleep(450);ui(()->{});android.graphics.Bitmap bitmap=getUiAutomation().takeScreenshot();check("screenshot-"+name,bitmap!=null);try(var stream=new java.io.FileOutputStream(new File(output,name))){bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,stream);}finally{bitmap.recycle();}}
    private static boolean contains(View view,String text){if(view instanceof android.widget.TextView&&((android.widget.TextView)view).getText().toString().contains(text))return true;if(view instanceof ViewGroup)for(int i=0;i<((ViewGroup)view).getChildCount();i++)if(contains(((ViewGroup)view).getChildAt(i),text))return true;return false;}
    private void check(String name,boolean valid){if(!valid)throw new AssertionError(name);checks.put(name);}
    private interface Checked{void run()throws Exception;}
    private void ui(Checked work){Throwable[] error={null};runOnMainSync(()->{try{work.run();}catch(Throwable e){error[0]=e;}});if(error[0]!=null)throw new RuntimeException(error[0]);}
    private static Object field(Object value,String name)throws Exception{Field field=value.getClass().getDeclaredField(name);field.setAccessible(true);return field.get(value);}
    private static void set(Object value,String name,Object next)throws Exception{Field field=value.getClass().getDeclaredField(name);field.setAccessible(true);field.set(value,next);}
    private static void invoke(Object value,String name)throws Exception{Method method=value.getClass().getDeclaredMethod(name);method.setAccessible(true);method.invoke(value);}
    private static String sha(File file)throws Exception{MessageDigest digest=MessageDigest.getInstance("SHA-256");try(var in=Files.newInputStream(file.toPath())){byte[] bytes=new byte[65536];int n;while((n=in.read(bytes))!=-1)digest.update(bytes,0,n);}StringBuilder result=new StringBuilder();for(byte b:digest.digest())result.append(String.format("%02x",b&255));return result.toString();}
}
