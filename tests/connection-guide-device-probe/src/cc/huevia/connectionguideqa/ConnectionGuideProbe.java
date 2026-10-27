package cc.huevia.connectionguideqa;

import android.app.Activity;
import android.app.AlertDialog;
import android.app.Instrumentation;
import android.content.Context;
import android.content.SharedPreferences;
import android.content.Intent;
import android.content.res.Configuration;
import android.graphics.Bitmap;
import android.graphics.Color;
import android.graphics.Rect;
import android.os.Build;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.EditText;
import android.widget.CheckBox;
import cc.huevia.album.AlbumController;
import cc.huevia.album.CameraProtocol;
import cc.huevia.album.PhotoCameraClient;
import cc.huevia.connection.CameraConnectionPreferences;
import cc.huevia.album.DownloadedPhoto;
import cc.huevia.album.PhotoLibraryCatalog;
import cc.huevia.album.PhotoPresetBatch;
import cc.huevia.album.PhotoSaveTarget;
import cc.huevia.album.PhotoLiveState;
import cc.huevia.album.PhotoTransferProgress;
import cc.huevia.ui.AlbumPanel;
import cc.huevia.ui.GlassBar;
import cc.huevia.ui.UiPalette;
import java.io.File;
import java.io.FileOutputStream;
import java.lang.reflect.Constructor;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;
import java.nio.file.Files;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import java.util.concurrent.atomic.AtomicInteger;
import org.json.JSONArray;
import org.json.JSONObject;

/** Production AlbumPanel component only. The real MainActivity implementation never executes. */
@SuppressWarnings({"deprecation", "unchecked"})
public final class ConnectionGuideProbe extends Instrumentation {
    private static String mode;
    private static float fontScale;
    private final JSONArray checks = new JSONArray(), screenshots = new JSONArray(), geometry = new JSONArray(), violations = new JSONArray();
    private final AtomicInteger socketAttempts = new AtomicInteger();
    private Bundle arguments;
    private ProbeActivity activity;
    private File output, fixture;
    private String fixtureSha;
    private int redirected;
    private Throwable failure;
    private java.util.Map<String, ?> savedPreferences;

    @Override public void onCreate(Bundle arguments) { this.arguments = arguments; mode = arguments.getString("mode", "phone"); fontScale = "large-font".equals(mode) ? 1.3f : "extra-large".equals(mode) ? 2f : 1f; start(); }
    @Override public Activity newActivity(ClassLoader loader, String className, Intent intent) throws InstantiationException, IllegalAccessException, ClassNotFoundException {
        if (className.equals("cc.huevia.MainActivity")) { redirected++; return new ProbeActivity(); }
        return super.newActivity(loader, className, intent);
    }
    @Override public void onStart() {
        try {
            require("owned-emulator", Set.of("ranchu", "goldfish").contains(Build.HARDWARE));
            require("supported-mode", Set.of("phone", "large-font", "extra-large", "rail").contains(mode));
            Context context = getTargetContext();
            require("expected-version", context.getPackageManager().getPackageInfo("cc.huevia", 0).getLongVersionCode() == 104);
            require("exact-apk", arguments.getString("candidateSha256").equals(sha(new File(context.getApplicationInfo().sourceDir))));
            require("no-real-account", !new File(context.getNoBackupFilesDir(), "account/session.enc").exists());
            savedPreferences = new java.util.HashMap<>(context.getSharedPreferences("camera-connection", Context.MODE_PRIVATE).getAll());
            require("fixture-preferences-reset", context.getSharedPreferences("camera-connection", Context.MODE_PRIVATE).edit().clear().commit());
            output = new File(context.getExternalFilesDir(null), "connection-guide-qa/" + arguments.getString("runId"));
            require("output-created", output.mkdirs() || output.isDirectory());
            activity = (ProbeActivity) startActivitySync(new Intent().setClassName("cc.huevia", "cc.huevia.MainActivity").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK));
            require("main-replaced-before-onCreate-no-network-startup", redirected == 1);
            ui(() -> activity.initialise());
            for (int attempt = 0; attempt < 160; attempt++) {
                boolean[] busy = {true}; ui(() -> busy[0] = (Boolean) get(activity.panel, "loadingDownloads") || (Boolean) get(activity.panel, "loadingLiveProjects"));
                if (!busy[0]) break; Thread.sleep(30);
            }
            waitForIdleSync();
            ui(() -> {
                require("local-initialisation-settled", !(Boolean) get(activity.panel, "loadingDownloads") && !(Boolean) get(activity.panel, "loadingLiveProjects"));
                Configuration c = activity.getResources().getConfiguration();
                require("actual-font", Math.abs(c.fontScale - fontScale) < .02f);
                require("actual-width-category", activity.rail ? c.screenWidthDp >= 600 : c.screenWidthDp < 600);
                require("actual-mode-rail", activity.rail == "rail".equals(mode));
            });
            guideCases();

            require("connection-remains-behind-host-gate", activity.connectStarts == 2 && !activity.controller.hasLiveSession());
            ui(() -> require("only-real-failure-notice-no-photo-save", activity.saveRequests == 0 && activity.targetSaveRequests == 0 && activity.feedbacks == 1));

            require("all-native-layout-bounds-pass", violations.length() == 0);
        } catch (Throwable problem) { failure = rootCause(problem); try { capture("failure"); } catch (Throwable ignored) { } }
        finally {
            try {
                if (activity != null) ui(() -> { AlertDialog dialog = (AlertDialog) get(activity.panel, "deleteDialog"); if (dialog != null) dialog.dismiss(); activity.panel.close(); activity.controller.close(); activity.finish(); });
                restorePreferences();
                if (fixture != null) {
                    File expected = new File(getTargetContext().getExternalFilesDir("Pictures"), "camera-album").getCanonicalFile();
                    require("fixture-owned-path", fixture.getName().startsWith("qa-album-layout-") && fixture.getCanonicalFile().getParentFile().equals(expected));
                    Files.deleteIfExists(fixture.toPath()); require("fixture-cleaned", !fixture.exists());
                }
            } catch (Throwable cleanup) { if (failure == null) failure = rootCause(cleanup); else failure.addSuppressed(cleanup); }
            try {
                JSONObject report = new JSONObject().put("pass", failure == null).put("failure", failure == null ? JSONObject.NULL : failure.toString())
                        .put("mode", mode).put("fontScale", fontScale).put("candidateSha256", arguments.getString("candidateSha256"))
                        .put("checks", checks).put("screenshots", screenshots).put("geometry", geometry).put("violations", violations).put("cameraSocketAttempts", socketAttempts.get())
                        .put("scope", "Real AlbumPanel and GlassBar in substitute Activity, calling MainActivity shared navigation height/inset helpers through reflection. Real connection guide, actual settings edits and cancellation; synthetic connection stages; no system Wi-Fi or physical camera claim. No real MainActivity startup, real camera, HTTP/download, destructive confirmation, or production deletion. MainActivity host wiring must also be reviewed separately.");
                if (output != null) Files.writeString(new File(output, "report.json").toPath(), report.toString(2) + "\n");
            } catch (Throwable write) { if (failure == null) failure = write; }
            Bundle result = new Bundle(); result.putString("summary", failure == null ? "PASS " + checks.length() + " checks" : "FAIL " + failure);
            finish(failure == null ? Activity.RESULT_OK : Activity.RESULT_CANCELED, result);
        }
    }

    private void guideCases() throws Exception {
        ui(() -> invoke(activity.panel,"showGuide")); settled();
        ui(() -> {
            require("default-settings-collapsed", !(Boolean)get(activity.panel,"connectionSettingsExpanded"));
            require("default-ip-hidden", findDescription(activity.frame,"相机 IPv4 地址")==null);
            require("default-port-hidden", findDescription(activity.frame,"相机无线连接端口")==null);
            assertComplete(findText(activity.frame,"连接相机"),"default-connect",8);
            assertComplete(findText(activity.frame,"连接设置"),"default-settings",8);
        }); capture("01-collapsed-nikon");
        ui(() -> findDescription(activity.frame,"相机类型：尼康").performClick()); settled();
        clickNativeText("富士"); settled();
        ui(() -> {
            require("native-protocol-choice", get(activity.panel,"cameraProtocol")==CameraProtocol.FUJIFILM_X_T20);
            require("fuji-default-port", get(activity.panel,"portText").equals("55740"));
            require("fuji-automatic-by-default", (Boolean)get(activity.panel,"fujiAutoAddress"));
            require("brand-keeps-settings-collapsed", findDescription(activity.frame,"相机 IPv4 地址")==null);
            findText(activity.frame,"连接设置").performClick();
        }); settled(); capture("02-settings-expanded");
        ui(() -> {
            require("settings-show-ip-and-port", findDescription(activity.frame,"相机 IPv4 地址")!=null && findDescription(activity.frame,"相机无线连接端口")!=null);
            CheckBox automatic=(CheckBox)findText(activity.frame,"自动识别相机地址"); require("automatic-control-preserved",automatic!=null && automatic.isChecked());
            require("automatic-ip-readonly",!findDescription(activity.frame,"相机 IPv4 地址").isEnabled()); automatic.performClick();
        }); settled();
        ui(() -> {
            require("manual-ip-editable",findDescription(activity.frame,"相机 IPv4 地址").isEnabled());
            ((EditText)findDescription(activity.frame,"相机 IPv4 地址")).setText("192.0.2.7");
            ((EditText)findDescription(activity.frame,"相机无线连接端口")).setText("55740");
            ((android.widget.ScrollView)get(activity.panel,"guideScroll")).scrollTo(0,0);
        }); settled();
        ui(() -> findText(activity.frame,"收起连接设置").performClick()); settled();
        ui(() -> {
            require("fold-removes-fields",findDescription(activity.frame,"相机 IPv4 地址")==null);
            require("fold-preserves-address",get(activity.panel,"cameraAddress").equals("192.0.2.7"));
            require("address-persisted",CameraConnectionPreferences.loadHost(activity,CameraProtocol.FUJIFILM_X_T20).equals("192.0.2.7"));
            require("manual-mode-persisted",!CameraConnectionPreferences.loadFujiAutoAddress(activity));
            findText(activity.frame,"连接设置").performClick();
        }); settled();
        ui(() -> {
            require("reopen-keeps-values",((EditText)findDescription(activity.frame,"相机 IPv4 地址")).getText().toString().equals("192.0.2.7"));
            ((android.widget.ScrollView)get(activity.panel,"guideScroll")).scrollTo(0,0);
        }); settled();ui(() -> findText(activity.frame,"收起连接设置").performClick());settled();
        ui(() -> findText(activity.frame,"连接相机").performClick()); settled();
        ui(() -> {
            require("wifi-first",findText(activity.frame,"连接 Wi-Fi")!=null);
            require("connect-held-before-system-wifi",activity.pendingConnect!=null);
            invoke(activity.panel,"updateConnectionStage",new Class<?>[]{PhotoCameraClient.ConnectionStage.class},PhotoCameraClient.ConnectionStage.CONNECTING_CAMERA);
            require("real-camera-phase-label",findText(activity.frame,"连接相机")!=null);
            invoke(activity.panel,"updateConnectionStage",new Class<?>[]{PhotoCameraClient.ConnectionStage.class},PhotoCameraClient.ConnectionStage.WAITING_CONFIRMATION);
        }); settled();
        ui(() -> {
            TextView hint=(TextView)findText(activity.frame,"请在相机按 OK"); assertComplete(hint,"confirmation-hint",8);
            require("confirmation-announced",hint.getAccessibilityLiveRegion()==View.ACCESSIBILITY_LIVE_REGION_POLITE);
            require("confirmation-auto-continue-explained",hint.getContentDescription().toString().contains("自动继续"));
            require("settings-not-forced-open",!(Boolean)get(activity.panel,"connectionSettingsExpanded"));
        }); capture("03-camera-confirmation");
        ui(() -> invoke(activity.panel,"updateConnectionStage",new Class<?>[]{PhotoCameraClient.ConnectionStage.class},PhotoCameraClient.ConnectionStage.READING_PHOTOS));settled();
        ui(() -> require("confirmation-clears-after-approval",findText(activity.frame,"读取照片")!=null && findText(activity.frame,"请在相机按 OK")==null));capture("04-reading-photos");
        Runnable[] obsolete={null};ui(() -> {obsolete[0]=activity.pendingConnect;findText(activity.frame,"取消连接").performClick();});settled();
        ui(() -> require("cancel-retires-pending-start",!(Boolean)get(activity.panel,"connecting") && get(activity.panel,"pendingConnectionStart")==null));
        ui(() -> {require("setup-no-duplicate-notice",activity.feedbacks==0);findText(activity.frame,"连接相机").performClick();});settled();
        ui(() -> activity.panel.connectionStartFailed("相机 Wi-Fi 尚未就绪，请重新选择网络。",activity.pendingConnect));settled();
        ui(() -> {require("start-failure-keeps-original-reason",get(activity.panel,"connectionError").equals("相机 Wi-Fi 尚未就绪，请重新选择网络。"));findText(activity.frame,"连接未完成 · 详情").performClick();});settled();
        require("start-failure-detail-original-message",nativeTextExists("相机 Wi-Fi 尚未就绪，请重新选择网络。"));capture("05-wifi-error-details");clickNativeText("关闭");settled();
        ui(() -> {set(activity.panel,"connectionError","等待相机确认超时，请在 X-T20 上按 OK。");invoke(activity.panel,"render");});settled();
        ui(() -> {assertComplete(findText(activity.frame,"确认超时 · 详情"),"error-short",8);findText(activity.frame,"确认超时 · 详情").performClick();});settled();capture("06-confirm-error-details");
        require("error-detail-original-message",nativeTextExists("等待相机确认超时，请在 X-T20 上按 OK。"));clickNativeText("关闭");
    }

    private boolean nativeTextExists(String value) {
        android.view.accessibility.AccessibilityNodeInfo root=getUiAutomation().getRootInActiveWindow();if(root==null)return false;
        return root.findAccessibilityNodeInfosByText(value).stream().anyMatch(n -> value.contentEquals(n.getText()));
    }
    private void clickNativeText(String value) throws Exception {
        android.view.accessibility.AccessibilityNodeInfo root=getUiAutomation().getRootInActiveWindow();
        if(root!=null)for(android.view.accessibility.AccessibilityNodeInfo node:root.findAccessibilityNodeInfosByText(value))if(value.contentEquals(node.getText())){
            if(node.performAction(android.view.accessibility.AccessibilityNodeInfo.ACTION_CLICK))return;
            if(node.getParent()!=null && node.getParent().performAction(android.view.accessibility.AccessibilityNodeInfo.ACTION_CLICK))return;
        }
        throw new IllegalStateException("Missing native option "+value);
    }
    private static View findDescription(View view,String value){if(view.getContentDescription()!=null&&value.contentEquals(view.getContentDescription()))return view;if(view instanceof ViewGroup)for(int i=0;i<((ViewGroup)view).getChildCount();i++){View found=findDescription(((ViewGroup)view).getChildAt(i),value);if(found!=null)return found;}return null;}
    private void restorePreferences() {
        if(savedPreferences==null)return;SharedPreferences.Editor editor=getTargetContext().getSharedPreferences("camera-connection",Context.MODE_PRIVATE).edit().clear();
        for(var item:savedPreferences.entrySet()){Object v=item.getValue();String key=item.getKey();if(v instanceof String)editor.putString(key,(String)v);else if(v instanceof Integer)editor.putInt(key,(Integer)v);else if(v instanceof Long)editor.putLong(key,(Long)v);else if(v instanceof Boolean)editor.putBoolean(key,(Boolean)v);else if(v instanceof Float)editor.putFloat(key,(Float)v);else if(v instanceof Set)editor.putStringSet(key,(Set<String>)v);else throw new IllegalStateException("Unknown preference type");}
        require("preferences-restored",editor.commit());
    }

    private void assertComplete(View view, String label, int gapDp) throws Exception {
        require(label + "-exists", view != null && view.isShown()); Rect full = bounds(view), visible = new Rect(); require(label + "-full-visible", view.getGlobalVisibleRect(visible) && visible.contains(full));
        Rect nav = bounds(activity.navigation);
        geometry.put(new JSONObject().put("name", label).put("view", full.toShortString()).put("nav", nav.toShortString()).put("insetPx", activity.bottomNavigationInset()));
        verify(label + "-clearance", activity.rail ? full.left >= nav.right : full.bottom <= nav.top - activity.dp(gapDp));
        if (view instanceof TextView) require(label + "-text-unclipped", noEllipsis((TextView) view));
    }
    private static boolean noEllipsis(TextView view) { if (view.getLayout() == null) return false; for (int i=0;i<view.getLayout().getLineCount();i++) if(view.getLayout().getEllipsisCount(i)>0)return false; return view.getLayout().getHeight() <= view.getHeight()-view.getCompoundPaddingTop()-view.getCompoundPaddingBottom(); }
    private Object idleClient() throws Exception {
        Class<?> connector = getTargetContext().getClassLoader().loadClass("cc.huevia.album.PtpIpClient$SocketConnector");
        Object guard = Proxy.newProxyInstance(connector.getClassLoader(), new Class<?>[]{connector}, (proxy, method, values) -> { socketAttempts.incrementAndGet(); throw new java.io.IOException("No camera I/O in native layout fixture"); });
        Object client = getTargetContext().getClassLoader().loadClass("cc.huevia.album.PtpIpClient").getConstructor(connector).newInstance(guard); set(client, "closed", false); set(client, "sessionOpen", true); return client;
    }
    private Object connection() throws Exception { Constructor<?> c = getTargetContext().getClassLoader().loadClass("cc.huevia.album.ConnectionInfo").getDeclaredConstructor(String.class,String.class,int.class,int.class); c.setAccessible(true); return c.newInstance("QA Nikon", "192.0.2.1", 15740, 1); }
    private Object remotePhoto() throws Exception {
        ClassLoader l=getTargetContext().getClassLoader();Class<?> builder=l.loadClass("cc.huevia.ptp.PtpObjectInfo$Builder"),info=l.loadClass("cc.huevia.ptp.PtpObjectInfo");Object b=builder.getConstructor().newInstance();
        invoke(b,"storageId",new Class<?>[]{long.class},1L);invoke(b,"objectFormat",new Class<?>[]{int.class},0x3801);invoke(b,"compressedSize",new Class<?>[]{long.class},13672454L);invoke(b,"filename",new Class<?>[]{String.class},"QA_DSC_6199.JPG");
        Constructor<?> c=l.loadClass("cc.huevia.album.PhotoItem").getDeclaredConstructor(String.class,long.class,info);c.setAccessible(true);return c.newInstance("qa-retired-session",42L,invoke(b,"build"));
    }
    // A live status clock keeps scheduling frames. Flush bounded main-thread work rather than awaiting global idleness.
    private void settled() throws Exception { ui(() -> {}); Thread.sleep(180); ui(() -> {}); }
    private void capture(String name) throws Exception { if(activity==null||output==null)return;settled(); Bitmap image=getUiAutomation().takeScreenshot();require("screenshot-"+name,image!=null);try(FileOutputStream out=new FileOutputStream(new File(output,name+".png"))){image.compress(Bitmap.CompressFormat.PNG,100,out);screenshots.put(new JSONObject().put("file",name+".png").put("width",image.getWidth()).put("height",image.getHeight()));}finally{image.recycle();} }
    private void require(String name,boolean valid){if(!valid)throw new IllegalStateException(name);checks.put(name);}
    private void verify(String name,boolean valid){if(valid)checks.put(name);else violations.put(name);}
    private void ui(Checked work){Throwable[] problem={null};runOnMainSync(()->{try{work.run();}catch(Throwable error){problem[0]=error;}});if(problem[0]!=null)throw new RuntimeException(problem[0]);} private interface Checked{void run()throws Exception;}
    private static Rect bounds(View view){int[] at=new int[2];view.getLocationOnScreen(at);return new Rect(at[0],at[1],at[0]+view.getWidth(),at[1]+view.getHeight());}
    private static View findText(View view,String text){if(view instanceof TextView&&text.contentEquals(((TextView)view).getText())&&view.isShown())return view;if(view instanceof ViewGroup)for(int i=0;i<((ViewGroup)view).getChildCount();i++){View found=findText(((ViewGroup)view).getChildAt(i),text);if(found!=null)return found;}return null;}
    private static Object get(Object owner,String name)throws Exception{Field f=owner.getClass().getDeclaredField(name);f.setAccessible(true);return f.get(owner);}private static void set(Object owner,String name,Object value)throws Exception{Field f=owner.getClass().getDeclaredField(name);f.setAccessible(true);f.set(owner,value);}
    private static Object invoke(Object owner,String name)throws Exception{return invoke(owner,name,new Class<?>[0]);}private static Object invoke(Object owner,String name,Class<?>[] types,Object...values)throws Exception{Method m=owner.getClass().getDeclaredMethod(name,types);m.setAccessible(true);return m.invoke(owner,values);}
    private static Throwable rootCause(Throwable value){while(value.getCause()!=null)value=value.getCause();return value;}
    private static String sha(File file)throws Exception{MessageDigest d=MessageDigest.getInstance("SHA-256");try(var in=Files.newInputStream(file.toPath())){byte[]b=new byte[65536];int n;while((n=in.read(b))!=-1)d.update(b,0,n);}StringBuilder result=new StringBuilder();for(byte b:d.digest())result.append(String.format("%02x",b&255));return result.toString();}

    public static final class ProbeActivity extends Activity implements AlbumPanel.Host {
        AlbumPanel panel; AlbumController controller; FrameLayout frame; View navigation; boolean rail; int feedbacks,saveRequests,targetSaveRequests,connectStarts; PhotoSaveTarget requestedTarget; Runnable pendingConnect;
        @Override protected void attachBaseContext(Context base){Configuration c=new Configuration(base.getResources().getConfiguration());c.fontScale=fontScale;super.attachBaseContext(base.createConfigurationContext(c));}
        @Override protected void onCreate(Bundle state){super.onCreate(state);getWindow().setStatusBarColor(0xfffafaf8);getWindow().setNavigationBarColor(0xfffafaf8);frame=new FrameLayout(this);frame.setBackgroundColor(0xfffafaf8);frame.setOnApplyWindowInsetsListener((view,insets)->{if(Build.VERSION.SDK_INT>=30){android.graphics.Insets safe=insets.getInsets(android.view.WindowInsets.Type.systemBars()|android.view.WindowInsets.Type.displayCutout());view.setPadding(safe.left,safe.top,safe.right,safe.bottom);}else view.setPadding(insets.getSystemWindowInsetLeft(),insets.getSystemWindowInsetTop(),insets.getSystemWindowInsetRight(),insets.getSystemWindowInsetBottom());return insets.consumeSystemWindowInsets();});setContentView(frame);frame.requestApplyInsets();}
        void initialise(){rail=getResources().getConfiguration().screenWidthDp>=600;controller=new AlbumController(this);panel=new AlbumPanel(this,this,controller,new PhotoPresetBatch(this,controller));render();}
        int dp(float value){return Math.round(value*getResources().getDisplayMetrics().density);}
        int navHeight(){return mainNavigationHelper("floatingNavigationHeightDp",new Class<?>[]{float.class},getResources().getConfiguration().fontScale);}
        public int bottomNavigationInset(){Configuration c=getResources().getConfiguration();return mainNavigationHelper("floatingNavigationInsetPx",new Class<?>[]{int.class,float.class,float.class},c.screenWidthDp,c.fontScale,getResources().getDisplayMetrics().density);}
        private int mainNavigationHelper(String name,Class<?>[] types,Object...values){try{Class<?> main=getClassLoader().loadClass("cc.huevia.MainActivity");Method method=main.getDeclaredMethod(name,types);method.setAccessible(true);return (Integer)method.invoke(null,values);}catch(Exception failure){throw new IllegalStateException("Production navigation helper unavailable: "+name,failure);}}
        void render(){if(panel==null)return;frame.removeAllViews();LinearLayout pane=new LinearLayout(this);pane.setOrientation(LinearLayout.VERTICAL);FrameLayout.LayoutParams content=new FrameLayout.LayoutParams(-1,-1);if(rail)content.leftMargin=dp(80);frame.addView(pane,content);TextView title=new TextView(this);title.setText(panel.title());title.setTextSize(24);title.setTextColor(0xff282722);title.setPadding(dp(20),dp(16),dp(20),dp(12));pane.addView(title);pane.addView(panel.createView(),new LinearLayout.LayoutParams(-1,0,1));
            FrameLayout nav=rail?new FrameLayout(this):new GlassBar(this);if(nav instanceof GlassBar)((GlassBar)nav).setBackdrop(pane);else nav.setBackgroundColor(0xffe9e8e2);LinearLayout row=new LinearLayout(this);row.setOrientation(rail?LinearLayout.VERTICAL:LinearLayout.HORIZONTAL);row.setGravity(Gravity.CENTER);for(String label:List.of("预设","同步","相册","设置")){TextView item=new TextView(this);item.setText(label);item.setTextColor(0xff38352f);item.setTextSize(11);item.setGravity(Gravity.CENTER);row.addView(item,rail?new LinearLayout.LayoutParams(-1,dp(58)):new LinearLayout.LayoutParams(0,-1,1));}nav.addView(row,new FrameLayout.LayoutParams(-1,-1));FrameLayout.LayoutParams pos=new FrameLayout.LayoutParams(rail?dp(80):dp(Math.min(360,getResources().getConfiguration().screenWidthDp-48)),rail?-1:dp(navHeight()),rail?Gravity.START:Gravity.BOTTOM|Gravity.CENTER_HORIZONTAL);if(!rail)pos.bottomMargin=dp(14);frame.addView(nav,pos);navigation=nav;}
        @Override public void onChanged(){render();}@Override public void onMessage(String title,String message){feedbacks++;}@Override public void beforeSavePhotos(Runnable save){saveRequests++;throw new AssertionError("Destructive action forbidden");}
        @Override public void beforeConnect(Runnable connect){connectStarts++;pendingConnect=connect;}
        @Override public void beforeSavePhotos(PhotoSaveTarget target,Runnable save){targetSaveRequests++;requestedTarget=target;if(target!=PhotoSaveTarget.APP_ONLY)throw new AssertionError("App-only deletion must not request public album permissions");throw new AssertionError("Positive deletion path forbidden in cancel-only component probe");}
    }
}
