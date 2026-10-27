package cc.huevia.albumlayoutqa;

import android.app.Activity;
import android.app.AlertDialog;
import android.app.Instrumentation;
import android.content.Context;
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
import cc.huevia.album.AlbumController;
import cc.huevia.album.DownloadedPhoto;
import cc.huevia.album.PhotoLibraryCatalog;
import cc.huevia.album.PhotoPresetBatch;
import cc.huevia.album.PhotoSaveTarget;
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
public final class AlbumLayoutProbe extends Instrumentation {
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

    @Override public void onCreate(Bundle arguments) { this.arguments = arguments; mode = arguments.getString("mode", "phone"); fontScale = "large-font".equals(mode) ? 1.3f : 1f; start(); }
    @Override public Activity newActivity(ClassLoader loader, String className, Intent intent) throws InstantiationException, IllegalAccessException, ClassNotFoundException {
        if (className.equals("cc.huevia.MainActivity")) { redirected++; return new ProbeActivity(); }
        return super.newActivity(loader, className, intent);
    }
    @Override public void onStart() {
        try {
            require("owned-emulator", Set.of("ranchu", "goldfish").contains(Build.HARDWARE));
            require("supported-mode", Set.of("phone", "large-font", "rail").contains(mode));
            Context context = getTargetContext();
            require("expected-version", context.getPackageManager().getPackageInfo("cc.huevia", 0).getLongVersionCode() == 100);
            require("exact-apk", arguments.getString("candidateSha256").equals(sha(new File(context.getApplicationInfo().sourceDir))));
            require("no-real-account", !new File(context.getNoBackupFilesDir(), "account/session.enc").exists());
            output = new File(context.getExternalFilesDir(null), "album-layout-qa/" + arguments.getString("runId"));
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
            progress();
            selectionAndConfirmation();
            require("no-camera-sockets", socketAttempts.get() == 0);
            ui(() -> require("cancel-never-enters-either-save-overload", activity.saveRequests == 0 && activity.targetSaveRequests == 0 && activity.feedbacks == 0));
            require("fixture-bytes-unchanged-no-production-delete", fixtureSha.equals(sha(fixture)));
            require("all-native-layout-bounds-pass", violations.length() == 0);
        } catch (Throwable problem) { failure = rootCause(problem); try { capture("failure"); } catch (Throwable ignored) { } }
        finally {
            try {
                if (activity != null) ui(() -> { AlertDialog dialog = (AlertDialog) get(activity.panel, "deleteDialog"); if (dialog != null) dialog.dismiss(); activity.panel.close(); activity.controller.close(); activity.finish(); });
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
                        .put("scope", "Real AlbumPanel and GlassBar in substitute Activity, calling MainActivity shared navigation height/inset helpers through reflection. Cancel-only confirmation does not execute either beforeSavePhotos overload; APP_ONLY positive-path selection is a separate source review, not a dynamic claim of this probe. No real MainActivity startup, real camera, HTTP/download, destructive confirmation, or production deletion. MainActivity host wiring must also be reviewed separately.");
                if (output != null) Files.writeString(new File(output, "report.json").toPath(), report.toString(2) + "\n");
            } catch (Throwable write) { if (failure == null) failure = write; }
            Bundle result = new Bundle(); result.putString("summary", failure == null ? "PASS " + checks.length() + " checks" : "FAIL " + failure);
            finish(failure == null ? Activity.RESULT_OK : Activity.RESULT_CANCELED, result);
        }
    }

    private void progress() throws Exception {
        ui(() -> {
            set(activity.controller, "active", idleClient()); set(activity.controller, "session", "qa-current-session");
            Object connection = connection(); set(activity.controller, "cachedConnectionInfo", connection); set(activity.controller, "sessionConnectionInfo", connection);
            set(activity.panel, "connection", connection); set(activity.panel, "downloadedTab", false); set(activity.panel, "liveTab", false);
            ((List<Object>) get(activity.panel, "photos")).clear(); ((List<Object>) get(activity.panel, "photos")).add(remotePhoto());
            set(activity.panel, "downloading", true); set(activity.panel, "batchTotal", 1); set(activity.panel, "batchCompleted", 0); set(activity.panel, "batchFailed", 0);
            set(activity.panel, "receivedBytes", 2831155L); set(activity.panel, "expectedBytes", 13672454L); set(activity.panel, "currentFilename", "QA_DSC_6199.JPG");
            activity.render();
        });
        settled();
        ui(() -> {
            View region = activity.frame.findViewWithTag("album-transfer-panel"); require("progress-panel-present", region != null);
            TextView bytes = (TextView) activity.frame.findViewWithTag("album-transfer-bytes"); require("bytes-include-current-and-total", bytes.getText().toString().contains("/") && bytes.getText().toString().contains("MB"));
            assertComplete(bytes, "progress-bytes", 8); assertComplete(findText(region, "取消剩余下载"), "progress-cancel", 8);
            require("bytes-not-truncated", noEllipsis(bytes));
            require("progress-overlap-inset", ((Integer) invoke(activity.panel, "selectionCount")) == 0 && activity.bottomNavigationInset() == (activity.rail ? 0 : activity.dp(activity.navHeight()) + activity.dp(14)));
        });
        capture("01-progress");
    }

    private void selectionAndConfirmation() throws Exception {
        File directory = new File(getTargetContext().getExternalFilesDir("Pictures"), "camera-album"); require("fixture-directory", directory.mkdirs() || directory.isDirectory());
        fixture = new File(directory, "qa-album-layout-" + arguments.getString("runId") + ".JPG"); require("fixture-fresh", fixture.createNewFile());
        Bitmap pixels = Bitmap.createBitmap(240, 180, Bitmap.Config.ARGB_8888); pixels.eraseColor(0xff8b9b8d);
        try (FileOutputStream stream = new FileOutputStream(fixture)) { require("fixture-jpeg", pixels.compress(Bitmap.CompressFormat.JPEG, 90, stream)); } finally { pixels.recycle(); }
        fixtureSha = sha(fixture); Constructor<DownloadedPhoto> constructor = DownloadedPhoto.class.getDeclaredConstructor(File.class, String.class); constructor.setAccessible(true);
        DownloadedPhoto photo = constructor.newInstance(fixture, "QA_LOCAL.JPG");
        PhotoLibraryCatalog catalog = new PhotoLibraryCatalog(activity.getFilesDir(), activity.getExternalFilesDir("Pictures"));
        List<PhotoLibraryCatalog.PhotoGroup> groups = catalog.list(List.of(photo), () -> false);
        require("real-library-group", groups.size() == 1);
        ui(() -> {
            set(activity.panel, "downloading", false); set(activity.panel, "downloadedTab", true); set(activity.panel, "selectionMode", true); set(activity.panel, "loadingDownloads", false);
            set(activity.panel, "libraryCatalog", catalog); set(activity.panel, "localLoaded", true);
            for (String field : List.of("downloads", "rawDownloads", "allDownloads")) { List<Object> values = (List<Object>) get(activity.panel, field); values.clear(); values.add(photo); }
            List<Object> current = (List<Object>) get(activity.panel, "photoGroups"); current.clear(); current.addAll(groups);
            Set<String> selected = (Set<String>) get(activity.panel, "selectedLocal"); selected.clear(); selected.add(fixture.getAbsolutePath());
            activity.render();
        });
        settled();
        ui(() -> {
            View actions = activity.frame.findViewWithTag("album-selection-actions"); require("selection-actions-present", actions != null);
            assertComplete(findText(actions, "删除"), "downloaded-delete", 8);
            assertComplete(findText(actions, "批量导出"), "downloaded-export", 8);
            assertComplete(findText(actions, "套用效果"), "downloaded-effect", 8);
            require("selection-has-two-action-rows", ((ViewGroup) actions).getChildCount() >= 2);
            require("delete-real-click", findText(actions, "删除").performClick());
        });
        settled();
        ui(() -> {
            AlertDialog dialog = (AlertDialog) get(activity.panel, "deleteDialog"); require("real-delete-confirmation-shown", dialog != null && dialog.isShowing());
            TextView message = dialog.findViewById(android.R.id.message); String text = message.getText().toString();
            require("scope-is-app-copy", text.contains("App 内") && text.contains("相机和手机相册中的照片保留"));
            require("no-system-or-camera-delete-claim", !text.contains("删除相机") && !text.contains("删除系统相册") && !text.contains("及对应系统相册副本") && !text.contains("和系统相册副本"));
            require("confirmation-has-explicit-cancel", dialog.getButton(AlertDialog.BUTTON_NEGATIVE) != null);
            require("no-deletion-started", !activity.controller.isDeletingDownloadedPhotos());
        });
        capture("02-delete-confirmation");
        ui(() -> ((AlertDialog) get(activity.panel, "deleteDialog")).getButton(AlertDialog.BUTTON_NEGATIVE).performClick());
        settled(); capture("03-selection");
        ui(() -> require("cancel-did-not-start-delete", !activity.controller.isDeletingDownloadedPhotos() && fixture.isFile()));
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
    private void settled() throws Exception { waitForIdleSync(); Thread.sleep(180); waitForIdleSync(); }
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
        AlbumPanel panel; AlbumController controller; FrameLayout frame; View navigation; boolean rail; int feedbacks,saveRequests,targetSaveRequests; PhotoSaveTarget requestedTarget;
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
        @Override public void beforeSavePhotos(PhotoSaveTarget target,Runnable save){targetSaveRequests++;requestedTarget=target;if(target!=PhotoSaveTarget.APP_ONLY)throw new AssertionError("App-only deletion must not request public album permissions");throw new AssertionError("Positive deletion path forbidden in cancel-only component probe");}
    }
}
