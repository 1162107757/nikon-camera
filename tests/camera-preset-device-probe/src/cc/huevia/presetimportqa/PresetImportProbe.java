package cc.huevia.presetimportqa;

import android.app.*;
import android.content.*;
import android.content.pm.ActivityInfo;
import android.graphics.*;
import android.os.*;
import android.view.*;
import android.view.accessibility.AccessibilityNodeInfo;
import android.widget.*;
import org.json.*;
import java.io.*;
import java.lang.reflect.*;
import java.util.*;
import java.util.concurrent.atomic.AtomicReference;

/** Emulator-only real MainActivity views. Synthetic preset/slot data, no transport or camera writes. */
public final class PresetImportProbe extends Instrumentation {
    private Activity activity; private ClassLoader loader; private File output;
    private Bundle args; private final JSONArray checks = new JSONArray();
    private Object library, record, plan;
    @Override public void onCreate(Bundle values) { super.onCreate(values); args = values == null ? new Bundle() : values; start(); }
    @Override public void onStart() {
        Bundle result = new Bundle(); JSONObject report = new JSONObject();
        try {
            check(Build.HARDWARE.equals("ranchu") || Build.HARDWARE.equals("goldfish"), "emulator-only");
            output = new File(getTargetContext().getExternalFilesDir(null), "preset-import137/" + args.getString("run", "review") + "/" + args.getString("mode", "phone")); output.mkdirs();
            activity = startActivitySync(new Intent(Intent.ACTION_MAIN).setComponent(new ComponentName("cc.huevia", "cc.huevia.MainActivity")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK|Intent.FLAG_ACTIVITY_CLEAR_TASK));
            loader = getTargetContext().getClassLoader();
            long until = SystemClock.uptimeMillis()+20000;
            while (!(Boolean)get(activity,"ready") && SystemClock.uptimeMillis()<until) SystemClock.sleep(50);
            check((Boolean)get(activity,"ready"), "main-ready");
            ui(() -> activity.setRequestedOrientation("landscape".equals(args.getString("mode")) ? ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE : ActivityInfo.SCREEN_ORIENTATION_PORTRAIT)); SystemClock.sleep(900);
            byte[] bytes; try(InputStream in=getContext().getAssets().open("synthetic.np3")){bytes=in.readAllBytes();}
            library=get(activity,"library"); record=get(call(library,"importFile","QA Flexible.np3",bytes),"record");
            ui(()->{set(activity,"busy",false);call(activity,"openPreset",record,false);});
            check(findText(root(),"导入相机")!=null,"unified-np3-import-action");
            check(findText(root(),"NP3")==null,"no-format-badge");
            screenshot("01-preset");
            Object adaptation=stat("ncp.CameraPresetAdapter","initialPlan",bytes), conversion=get(adaptation,"conversion");
            Constructor<?> camera=cls("MainActivity$CameraConnection").getDeclaredConstructor(String.class,int.class,cls("usb.WirelessPictureControl"));camera.setAccessible(true);
            Object connection=camera.newInstance("演示连接",15740,null);
            Constructor<?> item=cls("usb.UsbPictureControlProbe$ItemRecord").getDeclaredConstructor(int.class,byte[].class);item.setAccessible(true);
            List<Object> slots=new ArrayList<>();
            for(int i=201;i<=209;i++){Object slot=item.newInstance(i,new byte[36]);set(slot,"empty",true);set(slot,"parsed",true);slots.add(slot);}
            Constructor<?> pending=cls("MainActivity$PendingConfirmation").getDeclaredConstructor(cls("MainActivity$CameraConnection"),String.class,cls("library.PresetRecord"),byte[].class,List.class);pending.setAccessible(true);
            plan=pending.newInstance(connection,"Nikon Z6II",record,bytes,slots);
            set(plan,"conversion",conversion);set(plan,"adaptation",adaptation);
            set(plan,"middle",((Number)call(conversion,"middleRangeSharpeningQuarter")).intValue());set(plan,"clarity",((Number)call(conversion,"clarityQuarter")).intValue());
            ui(()->{set(activity,"confirmation",plan);call(activity,"render");});
            TextView action=findText(root(),"导入到 C1");
            check(action!=null&&!action.isEnabled(),"partial-adaptation-needs-explicit-consent");
            screenshot("02-slots");
            CheckBox accept=(CheckBox)findTag(root(),"preset-approximation-consent");
            reveal(accept);check(accept!=null,"loss-disclosure-and-consent-reachable");
            for(String tag:new String[]{"preset-adaptation-edit","preset-parameters-edit"}){
                View link=findTag(root(),tag);int minimum=Math.round(48*activity.getResources().getDisplayMetrics().density);
                check(link!=null&&link.getWidth()>=minimum&&link.getHeight()>=minimum,"48dp-touch-target-"+tag);
            }
            check(findText(root(),"不调整")!=null,"camera-parameters-off-by-default");
            screenshot("03-adaptation");
            ui(()->accept.performClick());check(action.isEnabled(),"consent-enables-import");
            ui(()->call(activity,"editCameraParameters",plan));SystemClock.sleep(400);
            check(nodes("拍摄参数 · 可选").size()==1,"optional-parameter-dialog");
            screenshot("04-parameter-defaults");
            tapNode(nodes("不调整").get(0));tapChoice("指定色温");
            check(choiceNode("5000 K")!=null,"kelvin-visible-only-after-choice");
            screenshot("05-kelvin-choice");tapNode(nodes("保存选择").get(0));
            check("色温 5000 K".equals(call(get(plan,"parameters"),"summary")),"explicit-choice-saved");
            reveal(findText(root(),"拍摄参数"));screenshot("06-selected-parameters");
            ui(()->call(activity,"editCameraParameters",plan));tapNode(nodes("全部不调整").get(0));
            check((Boolean)call(get(plan,"parameters"),"isEmpty"),"all-off-resets-choice");
            ui(()->{set(activity,"confirmation",null);set(activity,"detailId","");set(activity,"detailOnline",null);set(activity,"localTab",false);set(activity,"catalogLoaded",true);set(activity,"catalogMessage","");set(activity,"onlineFormatFilter","");call(activity,"render");});
            check(findTag(root(),"online-preset-format-filter")==null,"online-format-filter-retired");
            check("".equals(stat("MainActivity","restoredOnlinePresetFormat","NP3")),"legacy-format-filter-cleared");
            check(findText(root(),"全部格式")==null,"normal-browser-has-no-format-category");
            verifyImmediateUsbOutcomes();
            report.put("pass",true);
        } catch(Throwable failure) {
            try { StringWriter trace=new StringWriter();failure.printStackTrace(new PrintWriter(trace));report.put("pass",false).put("failure",trace.toString());if(output!=null&&activity!=null)screenshot("failure"); }catch(Exception ignored){}
        } finally {
            try { if(activity!=null)ui(()->{call(get(activity,"connections"),"clearImportStatus");set(activity,"confirmation",null);set(activity,"importOutcome",null);set(activity,"busy",false);call(activity,"render");}); }catch(Exception ignored){}
            try { report.put("checks",checks);if(output!=null)try(OutputStream out=new FileOutputStream(new File(output,"report.json"))){out.write(report.toString(2).getBytes(java.nio.charset.StandardCharsets.UTF_8));}result.putString("report",report.toString()); }catch(Exception ignored){}
            finish(report.optBoolean("pass")?Activity.RESULT_OK:Activity.RESULT_CANCELED,result);
        }
    }
    private void verifyImmediateUsbOutcomes()throws Exception{
        Object runtime=get(activity,"connections");check(!(Boolean)call(runtime,"hasOperations"),"synthetic-usb-has-no-lease");
        Constructor<?> ctor=cls("connection.CameraConnectionRuntime$ImportStatus").getConstructor(String.class,String.class,String.class,String.class,int.class,boolean.class,boolean.class,String.class);
        for(boolean verified:new boolean[]{true,false})for(String state:new String[]{"已调整并核对","已跳过","相机未接受"}){
            String rows="拍摄参数\n白平衡："+state, detail=(verified?"预设已保存。":"预设结果待核对。")+"\n\n"+rows;
            Object status=ctor.newInstance(verified?"已保存到 C1 并核对":"结果待核对",detail,"合成 USB 结果","Z6II",201,verified,false,get(record,"sha256"));
            ui(()->{set(activity,"busy",true);call(runtime,"publishImportStatus",status);});waitForIdleSync();
            ui(()->{call(activity,"completeImportOutcome",status);call(activity,"render");});waitForIdleSync();
            check(detail.equals(get(get(activity,"importOutcome"),"detail")),"usb-immediate-full-result-"+verified+"-"+state);
            TextView shown=findContaining(root(),"白平衡："+state);check(shown!=null,"usb-immediate-parameter-row-"+verified+"-"+state);reveal(shown);
            Rect visible=new Rect();check(shown.getGlobalVisibleRect(visible)&&visible.height()>0,"usb-immediate-row-visible-"+verified+"-"+state);
            if(verified&&"已跳过".equals(state))screenshot("07-usb-partial-result");
        }
        ui(()->{call(runtime,"clearImportStatus");set(activity,"importOutcome",null);});
    }
    private List<AccessibilityNodeInfo> nodes(String text)throws Exception{
        long until=SystemClock.uptimeMillis()+3500;List<AccessibilityNodeInfo> found;
        do{AccessibilityNodeInfo root=getUiAutomation().getRootInActiveWindow();found=new ArrayList<>();if(root!=null)for(AccessibilityNodeInfo node:root.findAccessibilityNodeInfosByText(text))if(node.getText()!=null&&text.contentEquals(node.getText()))found.add(node);if(!found.isEmpty())return found;SystemClock.sleep(50);}while(SystemClock.uptimeMillis()<until);
        throw new AssertionError("Missing text: "+text);
    }
    private void tapNode(AccessibilityNodeInfo node){Rect r=new Rect();node.getBoundsInScreen(r);long t=SystemClock.uptimeMillis();for(int a:new int[]{MotionEvent.ACTION_DOWN,MotionEvent.ACTION_UP}){MotionEvent e=MotionEvent.obtain(t,SystemClock.uptimeMillis(),a,r.exactCenterX(),r.exactCenterY(),0);e.setSource(android.view.InputDevice.SOURCE_TOUCHSCREEN);getUiAutomation().injectInputEvent(e,true);e.recycle();}SystemClock.sleep(250);}
    private void tapChoice(String text)throws Exception{AccessibilityNodeInfo node=choiceNode(text);if(!node.performAction(AccessibilityNodeInfo.ACTION_CLICK))tapNode(node);SystemClock.sleep(400);}
    private AccessibilityNodeInfo choiceNode(String text)throws Exception{for(int i=0;i<8;i++){AccessibilityNodeInfo root=getUiAutomation().getRootInActiveWindow();for(AccessibilityNodeInfo node:root.findAccessibilityNodeInfosByText(text))if(node.getText()!=null&&text.contentEquals(node.getText()))return node;scrollNode(root);SystemClock.sleep(450);}throw new AssertionError("Missing scrollable choice: "+text);}
    private boolean scrollNode(AccessibilityNodeInfo node){if(node.isScrollable()&&node.performAction(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD))return true;for(int i=0;i<node.getChildCount();i++){AccessibilityNodeInfo child=node.getChild(i);if(child!=null&&scrollNode(child))return true;}return false;}
    private void reveal(View target)throws Exception{if(target==null)throw new AssertionError("Missing scroll target");ui(()->{for(android.view.ViewParent p=target.getParent();p instanceof View;p=p.getParent())if(p instanceof ScrollView){ScrollView scroll=(ScrollView)p;Rect rect=new Rect();target.getDrawingRect(rect);((ViewGroup)scroll.getChildAt(0)).offsetDescendantRectToMyCoords(target,rect);scroll.scrollTo(0,rect.bottom-scroll.getHeight());}});SystemClock.sleep(250);}
    private void screenshot(String name)throws Exception{waitForIdleSync();SystemClock.sleep(300);Bitmap bitmap=getUiAutomation().takeScreenshot();try(OutputStream out=new FileOutputStream(new File(output,name+".png"))){bitmap.compress(Bitmap.CompressFormat.PNG,100,out);}finally{bitmap.recycle();}}
    private View root(){return activity.getWindow().getDecorView();}
    private View findTag(View v,String tag){if(tag.equals(v.getTag()))return v;if(v instanceof ViewGroup)for(int i=0;i<((ViewGroup)v).getChildCount();i++){View found=findTag(((ViewGroup)v).getChildAt(i),tag);if(found!=null)return found;}return null;}
    private TextView findText(View v,String text){if(v instanceof TextView&&text.contentEquals(((TextView)v).getText()))return(TextView)v;if(v instanceof ViewGroup)for(int i=0;i<((ViewGroup)v).getChildCount();i++){TextView found=findText(((ViewGroup)v).getChildAt(i),text);if(found!=null)return found;}return null;}
    private TextView findContaining(View v,String text){if(v instanceof TextView&&((TextView)v).getText().toString().contains(text))return(TextView)v;if(v instanceof ViewGroup)for(int i=0;i<((ViewGroup)v).getChildCount();i++){TextView found=findContaining(((ViewGroup)v).getChildAt(i),text);if(found!=null)return found;}return null;}
    private void check(boolean pass,String label)throws Exception{checks.put(new JSONObject().put("name",label).put("pass",pass));if(!pass)throw new AssertionError(label);}
    private Class<?> cls(String name)throws Exception{return loader.loadClass("cc.huevia."+name);}
    private Object get(Object target,String name)throws Exception{Field f=target.getClass().getDeclaredField(name);f.setAccessible(true);return f.get(target);}
    private void set(Object target,String name,Object value)throws Exception{Field f=target.getClass().getDeclaredField(name);f.setAccessible(true);f.set(target,value);}
    private Object stat(String name,String method,Object...args)throws Exception{return invoke(cls(name),null,method,args);}
    private Object call(Object target,String method,Object...args)throws Exception{return invoke(target.getClass(),target,method,args);}
    private Object invoke(Class<?> type,Object target,String name,Object[] args)throws Exception{for(Method method:type.getDeclaredMethods())if(method.getName().equals(name)&&method.getParameterCount()==args.length){method.setAccessible(true);try{return method.invoke(target,args);}catch(IllegalArgumentException mismatch){continue;}catch(InvocationTargetException failed){throw new RuntimeException(failed.getCause());}}throw new NoSuchMethodException(name);}
    private interface Work{void run()throws Exception;}
    private void ui(Work work)throws Exception{AtomicReference<Throwable> error=new AtomicReference<>();runOnMainSync(()->{try{work.run();}catch(Throwable t){error.set(t);}});if(error.get()!=null)throw new RuntimeException(error.get());}
}
