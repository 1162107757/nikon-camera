package cc.huevia.actionchoiceqa;
import android.app.*;import android.content.*;import android.graphics.*;import android.os.*;import android.view.*;import android.view.accessibility.AccessibilityNodeInfo;import android.widget.*;import java.io.*;import java.lang.reflect.*;import java.nio.charset.StandardCharsets;import java.security.MessageDigest;import java.util.*;import java.util.concurrent.atomic.*;import org.json.*;
public final class ActionChoiceProbe extends Instrumentation {
 private Activity activity;private ClassLoader loader;private Bundle args;private File output;private final JSONArray checks=new JSONArray();private String originalMode;private Object repo,oldSession,account,oldAccountSession,oldScreen;
 @Override public void onCreate(Bundle b){super.onCreate(b);args=b;start();}
 @Override public void onStart(){JSONObject report=new JSONObject();Bundle result=new Bundle();try{
  check(Build.HARDWARE.equals("ranchu")||Build.HARDWARE.equals("goldfish"),"owned-emulator");loader=getTargetContext().getClassLoader();
  String sha=digest(new File(getTargetContext().getApplicationInfo().sourceDir));check(sha.equals(args.getString("apkSha256")),"frozen-apk-sha");check(getTargetContext().getPackageManager().getPackageInfo("cc.huevia",0).getLongVersionCode()==161,"version-161");String mode=args.getString("mode","phone");
  output=new File(getTargetContext().getExternalFilesDir(null),"action-choice161/"+args.getString("runId")+"/"+mode);output.mkdirs();originalMode=(String)invoke(loader.loadClass("cc.huevia.ui.AppAppearance"),null,"mode",getTargetContext());invoke(loader.loadClass("cc.huevia.ui.AppAppearance"),null,"setMode",getTargetContext(),mode.equals("dark")?"dark":"light");
  activity=startActivitySync(new Intent(Intent.ACTION_MAIN).setComponent(new ComponentName("cc.huevia","cc.huevia.MainActivity")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK|Intent.FLAG_ACTIVITY_CLEAR_TASK));until(()->Boolean.TRUE.equals(get(activity,"ready")),"ready");Object personal=get(activity,"personal");repo=get(personal,"accounts");oldSession=get(repo,"session");account=get(activity,"account");oldAccountSession=get(account,"session");oldScreen=get(account,"screen");
  ui(()->{set(repo,"session",null);call(activity,"pickNcp",false);});until(()->activeHas("从文件导入"),"guest-import");check(activeHas("仅保存到本机")&&activeHas("登录同步"),"guest-choice-keeps-login-entry");inspect("添加预设");capture("01-import-guest");clickDescription("关闭添加预设");check(!activeHas("从文件导入"),"close-does-not-select-file");
  Object fake=fakeSession();ui(()->{set(repo,"session",fake);call(activity,"pickNcp",false);});until(()->activeHas("导入后自动同步至个人云端"),"logged-import");check(!activeHas("登录同步"),"logged-choice-no-extra-login-button");inspect("添加预设");capture("02-import-private-cloud");clickDescription("关闭添加预设");
  ui(()->{set(repo,"session",null);call(activity,"choosePreviewTemplate");});until(()->activeHas("从手机选择模板图"),"template-menu");inspect("预览模板");capture("03-template-actions");click("查看内置摄影样片");until(()->activeHas("内置摄影样片 ·"),"photo-source-list");inspect("内置摄影样片");capture("04-photograph-list");sendKeyDownUpSync(KeyEvent.KEYCODE_BACK);settle();
  AtomicInteger invoked=new AtomicInteger();Object menu=loader.loadClass("cc.huevia.ui.ActionChoiceDialog").getConstructor(Context.class,loader.loadClass("cc.huevia.ui.UiPalette"),String.class).newInstance(activity,get(activity,"colors"),"照片版本");Class<?> kind=loader.loadClass("cc.huevia.ui.AppIcon$Kind");Object icon=Enum.valueOf((Class)kind,"STACK");call(menu,"add",icon,"当前编辑","",(Runnable)()->invoked.incrementAndGet());call(menu,"add",icon,"Huevia_DSC_6192_original_full_resolution_photo_version.jpg","",(Runnable)()->invoked.addAndGet(10));ui(()->call(menu,"show"));until(()->activeHas("当前编辑"),"shared-choice");inspect("照片版本");capture("05-version-long-filename");click("当前编辑");check(invoked.get()==1,"selected-action-dispatched-once");
  rawMenus();
  if(mode.equals("phone")){
   AtomicReference<Intent> selected=new AtomicReference<>();ActivityMonitor monitor=new ActivityMonitor(){@Override public ActivityResult onStartActivity(Intent intent){if(Intent.ACTION_OPEN_DOCUMENT.equals(intent.getAction())||Intent.ACTION_GET_CONTENT.equals(intent.getAction())){selected.set(intent);return new ActivityResult(Activity.RESULT_CANCELED,null);}return null;}};addMonitor(monitor);try{ui(()->call(activity,"pickNcp",false));click("从文件导入");until(()->selected.get()!=null,"picker-started");check("*/*".equals(selected.get().getType())&&selected.get().hasCategory(Intent.CATEGORY_OPENABLE),"np3-and-ncp-not-filtered-out");}finally{removeMonitor(monitor);}
   ui(()->call(activity,"pickNcp",false));click("登录同步");until(()->Boolean.TRUE.equals(call(account,"isOpen")),"login-opens-account");check(Boolean.TRUE.equals(get(activity,"pendingPersonalPick")),"resume-import-after-login-preserved");until(()->!Boolean.TRUE.equals(get(account,"restoring")),"account-local-restore-complete");
   ui(()->{set(activity,"pendingPersonalPick",false);set(repo,"session",fake);set(account,"session",fake);set(account,"screen",Enum.valueOf((Class)oldScreen.getClass(),"PROFILE"));call(activity,"render");call(account,"showAvatarActions");});until(()->activeHas("恢复默认头像"),"avatar-actual-menu");inspect("修改头像");capture("06-avatar-actions");click("恢复默认头像");until(()->activeHas("恢复默认头像？"),"avatar-confirmation");check(activeHas("取消")&&activeHas("恢复"),"restore-still-requires-confirmation");sendKeyDownUpSync(KeyEvent.KEYCODE_BACK);settle();
  }
  report.put("pass",true).put("apkSha256",sha);
 }catch(Throwable e){try{report.put("pass",false).put("failure",e.toString());capture("failure");}catch(Exception ignored){}}finally{try{if(repo!=null)ui(()->{set(repo,"session",oldSession);set(account,"session",oldAccountSession);set(account,"screen",oldScreen);set(activity,"pendingPersonalPick",false);});if(originalMode!=null)invoke(loader.loadClass("cc.huevia.ui.AppAppearance"),null,"setMode",getTargetContext(),originalMode);if(activity!=null)ui(()->activity.finish());report.put("checks",checks).put("mode",args.getString("mode","phone")).put("scope","Installed product APK on an offline owned emulator. Actual preset import/template/avatar entry points, intent monitor for system chooser, shared action callbacks and text layout. Synthetic in-memory logged identity is restored; no login or upload performed.");if(output!=null)try(OutputStream out=new FileOutputStream(new File(output,"report.json"))){out.write(report.toString(2).getBytes(StandardCharsets.UTF_8));}result.putString("stream",(report.optBoolean("pass")?"PASS ":"FAIL ")+checks.length()+" action choice checks; "+report.optString("failure"));}catch(Exception e){result.putString("stream","FAIL report/cleanup "+e);}finish(report.optBoolean("pass")?Activity.RESULT_OK:Activity.RESULT_CANCELED,result);}}
 private void rawMenus()throws Exception{Object raw=get(get(activity,"album"),"rawPanel");List camera=(List)get(raw,"cameraFiles");List before=new ArrayList(camera);Object info=invoke(loader.loadClass("cc.huevia.ptp.PtpObjectInfo"),null,"file",1L,0L,"QA_DSC_0161.NEF",28315223L);Constructor<?> ctor=loader.loadClass("cc.huevia.album.PhotoItem").getDeclaredConstructor(String.class,long.class,info.getClass());ctor.setAccessible(true);Object photo=ctor.newInstance("qa-offline",161L,info);boolean local=(Boolean)get(raw,"local");try{ui(()->{camera.clear();camera.add(photo);set(raw,"local",false);call(raw,"chooseFile",0);});until(()->activeHas("下载原文件"),"raw-file-menu");inspect("QA_DSC_0161.NEF");capture("07-raw-file-actions");clickDescription("关闭QA_DSC_0161.NEF");Object controller=get(raw,"controller");if(Boolean.TRUE.equals(call(controller,"canOfferRawExport"))){AtomicInteger jpeg=new AtomicInteger();ui(()->call(raw,"chooseFormat",photo,null,(Runnable)()->jpeg.incrementAndGet()));until(()->activeHas("JPG（相机原图）"),"raw-format-menu");inspect("下载格式");capture("08-download-format");click("JPG（相机原图）");check(jpeg.get()==1,"jpg-callback-retained-without-camera-io");}}finally{ui(()->{camera.clear();camera.addAll(before);set(raw,"local",local);call(raw,"dismissFile");call(raw,"dismissFormat");});}}
 private Object fakeSession()throws Exception{Map<String,Object> u=new LinkedHashMap<>();u.put("id","00000000-0000-4000-8000-000000000161");u.put("username","qa_dialog");u.put("nickname","QA 本地界面验证");u.put("avatarUrl","");u.put("provider","password");u.put("status","active");for(String key:new String[]{"createdAt","lastLoginAt","updatedAt"})u.put(key,"2026-11-08T00:00:00.000Z");u.put("loginCount",java.math.BigDecimal.ONE);Map<String,Object> s=new LinkedHashMap<>();s.put("user",u);s.put("tokenType","Bearer");s.put("accessToken","_".repeat(43));s.put("expiresAt","2099-01-01T00:00:00.000Z");return invoke(repo.getClass(),null,"parseSession",s,false);}
 private void inspect(String title)throws Exception{ui(()->{boolean found=false;for(View root:android.view.inspector.WindowInspector.getGlobalWindowViews())if(root.hasWindowFocus()&&findContaining(root,title)!=null){found=true;textFits(root);for(View v:all(root))if(v instanceof Button&&v.getVisibility()==View.VISIBLE)throw new AssertionError("Old footer button visible");check(root.getWidth()<=getTargetContext().getResources().getDisplayMetrics().widthPixels,"dialog-fits-screen");}check(found,"actual-choice-window");});}
 private View findContaining(View root,String text){for(View v:all(root))if(v instanceof TextView&&((TextView)v).getText().toString().contains(text))return v;return null;}
 private List<View> all(View view){List<View> list=new ArrayList<>();list.add(view);if(view instanceof ViewGroup)for(int i=0;i<((ViewGroup)view).getChildCount();i++)list.addAll(all(((ViewGroup)view).getChildAt(i)));return list;}
 private void textFits(View view)throws Exception{for(View v:all(view)){if(v.getTag()!=null&&v.getTag().toString().startsWith("compact-action:"))check(v.getHeight()>=52*v.getResources().getDisplayMetrics().density-1,"action-target-at-least-52dp");if(v instanceof TextView){TextView t=(TextView)v;if(t.getLayout()==null||t.getText().length()==0)continue;check(t.getTextSize()/t.getResources().getDisplayMetrics().scaledDensity<=16.1,"normal-compact-type");for(int i=0;i<t.getLayout().getLineCount();i++){check(t.getLayout().getEllipsisCount(i)==0,"no-truncated-label");check(t.getLayout().getLineWidth(i)<=t.getWidth()-t.getPaddingLeft()-t.getPaddingRight()+2,"label-fits-column");}}}}
    private View findText(View view, String value) {
        if (view instanceof TextView && value.contentEquals(((TextView) view).getText())) return view;
        if (view instanceof android.view.ViewGroup) for (int i = 0; i < ((android.view.ViewGroup) view).getChildCount(); i++) {
            View found = findText(((android.view.ViewGroup) view).getChildAt(i), value); if (found != null) return found;
        }
        return null;
    }
    private boolean activeHas(String text) { AccessibilityNodeInfo root = getUiAutomation().getRootInActiveWindow(); return root != null && !root.findAccessibilityNodeInfosByText(text).isEmpty(); }
    private void click(String text) throws Exception {
        until(() -> activeHas(text), "touch-target " + text); AccessibilityNodeInfo root = getUiAutomation().getRootInActiveWindow();
        for (AccessibilityNodeInfo node : root.findAccessibilityNodeInfosByText(text)) if (node.getText() != null && text.contentEquals(node.getText()) && node.isVisibleToUser()) {
            Rect bounds = new Rect(); node.getBoundsInScreen(bounds); if (bounds.isEmpty()) continue;
            long now = SystemClock.uptimeMillis(); MotionEvent down = MotionEvent.obtain(now, now, MotionEvent.ACTION_DOWN, bounds.exactCenterX(), bounds.exactCenterY(), 0);
            MotionEvent up = MotionEvent.obtain(now, now + 60, MotionEvent.ACTION_UP, bounds.exactCenterX(), bounds.exactCenterY(), 0);
            try { sendPointerSync(down); sendPointerSync(up); } finally { down.recycle(); up.recycle(); } settle(); return;
        }
        throw new AssertionError("No visible touch target: " + text);
    }
    private void clickDescription(String description) throws Exception {
        until(() -> activeHas(description), "close action available"); AccessibilityNodeInfo root = getUiAutomation().getRootInActiveWindow();
        for (AccessibilityNodeInfo node : root.findAccessibilityNodeInfosByText(description)) {
            if (!description.contentEquals(node.getContentDescription()) || !node.isVisibleToUser()) continue;
            Rect bounds = new Rect(); node.getBoundsInScreen(bounds);
            check(bounds.width() >= 44 * getTargetContext().getResources().getDisplayMetrics().density - 1, "close-keeps-44dp-hit-area");
            long now = SystemClock.uptimeMillis(); MotionEvent down = MotionEvent.obtain(now, now, MotionEvent.ACTION_DOWN, bounds.exactCenterX(), bounds.exactCenterY(), 0);
            MotionEvent up = MotionEvent.obtain(now, now + 60, MotionEvent.ACTION_UP, bounds.exactCenterX(), bounds.exactCenterY(), 0);
            try { sendPointerSync(down); sendPointerSync(up); } finally { down.recycle(); up.recycle(); } settle(); return;
        }
        throw new AssertionError("Close action not visible");
    }
    private void tap(float x, float y) throws Exception {
        long now = SystemClock.uptimeMillis();
        MotionEvent down = MotionEvent.obtain(now, now, MotionEvent.ACTION_DOWN, x, y, 0);
        MotionEvent up = MotionEvent.obtain(now, now + 60, MotionEvent.ACTION_UP, x, y, 0);
        // The dimmed area is outside the dialog's target window; UiAutomation is the
        // supported device-level injection path for an actual outside touch.
        try {
            check(getUiAutomation().injectInputEvent(down, true), "mask-down-injected");
            check(getUiAutomation().injectInputEvent(up, true), "mask-up-injected");
        } finally { down.recycle(); up.recycle(); } settle();
    }
    private void capture(String name) throws Exception {
        settle(); Bitmap screenshot = getUiAutomation().takeScreenshot();
        try (OutputStream out = new FileOutputStream(new File(output, name + ".png"))) { screenshot.compress(Bitmap.CompressFormat.PNG, 100, out); }
        finally { screenshot.recycle(); }
    }
    private String digest(File file) throws Exception { MessageDigest hash = MessageDigest.getInstance("SHA-256"); try (InputStream in = new FileInputStream(file)) { byte[] data = new byte[65536]; int n; while ((n = in.read(data)) != -1) hash.update(data, 0, n); } StringBuilder text = new StringBuilder(); for (byte b : hash.digest()) text.append(String.format(Locale.ROOT, "%02x", b & 255)); return text.toString(); }
    private Field field(Class<?> type, String name) throws Exception { for (Class<?> current = type; current != null; current = current.getSuperclass()) try { Field field = current.getDeclaredField(name); field.setAccessible(true); return field; } catch (NoSuchFieldException ignored) {} throw new NoSuchFieldException(name); }
    private Object get(Object owner, String name) throws Exception { return field(owner.getClass(), name).get(owner); }
    private void set(Object owner, String name, Object value) throws Exception { field(owner.getClass(), name).set(owner, value); }
    private Object call(Object owner, String name, Object... args) throws Exception { return invoke(owner.getClass(), owner, name, args); }
    private Object invoke(Class<?> type, Object owner, String name, Object... args) throws Exception {
        for (Class<?> current = type; current != null; current = current.getSuperclass()) for (Method method : current.getDeclaredMethods()) if (method.getName().equals(name) && method.getParameterCount() == args.length) {
            Class<?>[] types = method.getParameterTypes(); boolean match = true;
            for (int i = 0; i < args.length; i++) if (args[i] != null && !types[i].isPrimitive() && !types[i].isAssignableFrom(args[i].getClass())) match = false;
            if (match) { method.setAccessible(true); try { return method.invoke(owner, args); } catch (InvocationTargetException failed) { throw new RuntimeException(name + ": " + failed.getCause(), failed.getCause()); } }
        }
        throw new NoSuchMethodException(name);
    }
    private void check(boolean condition, String label) { if (!condition) throw new AssertionError(label); checks.put(label); }
    private interface Condition { boolean test() throws Exception; }
    private interface Work { void run() throws Exception; }
    private void until(Condition condition, String label) throws Exception { long end = SystemClock.uptimeMillis() + 30000; while (SystemClock.uptimeMillis() < end) { if (condition.test()) return; SystemClock.sleep(60); } throw new AssertionError("Timeout " + label); }
    private void ui(Work work) throws Exception { AtomicReference<Throwable> failure = new AtomicReference<>(); runOnMainSync(() -> { try { work.run(); } catch (Throwable error) { failure.set(error); } }); if (failure.get() != null) throw new RuntimeException(failure.get()); }
    private void settle() { waitForIdleSync(); SystemClock.sleep(250); }
}
