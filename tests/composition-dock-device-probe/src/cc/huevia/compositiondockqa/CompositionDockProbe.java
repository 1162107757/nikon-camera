package cc.huevia.compositiondockqa;

import android.accessibilityservice.AccessibilityServiceInfo;
import android.app.Activity;
import android.app.Dialog;
import android.app.Instrumentation;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ActivityInfo;
import android.content.pm.PackageInfo;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Rect;
import android.media.ExifInterface;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.os.SystemClock;
import android.text.Layout;
import android.view.InputDevice;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.view.accessibility.AccessibilityNodeInfo;
import android.view.accessibility.AccessibilityWindowInfo;
import android.widget.Button;
import android.widget.ImageView;
import android.widget.SeekBar;
import android.widget.TextView;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.lang.reflect.Field;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.Deque;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import org.json.JSONArray;
import org.json.JSONObject;

/** Android API-only probe. Application classes are loaded from the exact installed candidate. */
public final class CompositionDockProbe extends Instrumentation {
    private Bundle args;
    private Activity activity;
    private ClassLoader loader;
    private Object panel, editor, photo, store;
    private File output, original, draftRoot;
    private String sourceSha, stage="start";
    private Throwable failure;
    private boolean fixtureRemoved, ownsDraft;
    private int screenshotCount;
    private final JSONArray checks=new JSONArray(), measurements=new JSONArray(), cleanupErrors=new JSONArray();
    private final JSONObject fixtureIdentity=new JSONObject();
    private final List<Dialog> dialogs=new ArrayList<>();
    private interface Work { void run() throws Exception; }
    private interface Condition { boolean test() throws Exception; }

    @Override public void onCreate(Bundle value) { args=value; start(); }

    @Override public void onStart() {
        try {
            loader=getTargetContext().getClassLoader();
            check("owned-emulator",Build.HARDWARE.equals("ranchu")||Build.HARDWARE.equals("goldfish"));
            PackageInfo version=getTargetContext().getPackageManager().getPackageInfo("cc.huevia",0);
            check("exact-installed-apk",sha(new File(getTargetContext().getApplicationInfo().sourceDir)).equals(args.getString("candidateSha256")));
            check("runner-version-code",Long.parseLong(args.getString("expectedVersionCode"))==version.getLongVersionCode());
            check("runner-version-name",version.versionName.equals(args.getString("expectedVersionName")));
            String run=args.getString("runId");
            check("safe-run-id",run!=null&&run.matches("[a-zA-Z0-9.-]+"));
            File destination=new File(getTargetContext().getExternalFilesDir(null),"composition-dock/"+run);
            destination.getParentFile().mkdirs();
            check("fresh-evidence-directory",destination.mkdir());
            output=destination;
            activity=startActivitySync(new Intent().setClassName("cc.huevia","cc.huevia.MainActivity").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            until(()->(Boolean)get(activity,"ready"),"main-ready");
            boolean landscape=args.getString("mode","phone").equals("landscape");
            ui(()->activity.setRequestedOrientation(landscape?ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE:ActivityInfo.SCREEN_ORIENTATION_PORTRAIT));
            until(()->activity.getResources().getConfiguration().orientation==(landscape?2:1),"actual-requested-orientation");
            check("actual-font-scale",Math.abs(activity.getResources().getConfiguration().fontScale-(args.getString("mode").equals("font1.3")?1.3f:1f))<.02f);
            panel=get(activity,"album");
            String owner=(String)staticCall(type("cc.huevia.ui.PhotoFilterEditor"),"accountOwner",new Class<?>[]{Context.class},activity);
            store=type("cc.huevia.album.PhotoEditStore").getConstructor(File.class,String.class).newInstance(activity.getFilesDir(),owner);
            draftRoot=(File)get(store,"root");
            photo=createFixture(run);
            ui(()->{
                set(activity,"albumTab",true); set(activity,"settingsTab",false);
                call(panel,"openLocalWorkspace",new Class<?>[]{List.class,int.class},List.of(photo),0);
            });
            until(()->{Object value=get(panel,"filterEditor");return value!=null&&(Boolean)call(value,"isReady")&&sourceSha.equals(get(value,"sourceSha"));},"real-local-photo-editor-ready");
            editor=get(panel,"filterEditor");
            seedPreservationMarkers();
            waitEditor(); drain();
            acknowledgeImmersive();

            stage="composition-dock";
            click((View)get(editor,"filterModeButton"));
            awaitPanelHeight(176,"initial-filter-height");
            Rect filterStage=bounds(activityTag("editor-photo-stage"));
            String before=identity(get(editor,"geometry"));
            String[] preserved=preserved();
            int initialHistory=historySize();
            click(editorTag("composition-mode"));
            until(()->(Boolean)get(editor,"compositionMode"),"composition-tab-selected");
            awaitPanelHeight(112,"composition-content-height");
            verifyDock(landscape,filterStage);
            capture("01-composition-dock",activity.getWindow().getDecorView());

            stage="crop-entry";
            Dialog crop=openEntry("editor-open-composition");
            check("crop-entry-keeps-geometry",before.equals(identity(call(crop,"geometry"))));
            check("crop-entry-keeps-main-state",before.equals(identity(get(editor,"geometry"))));
            cancel(crop);
            check("crop-cancel-keeps-history",initialHistory==historySize());

            stage="rotate-entry-cancel";
            int originalTurns=(Integer)get(get(editor,"geometry"),"turns");
            Dialog rotate=openEntry("editor-composition-rotate");
            check("rotate-entry-stages-one-quarter-turn",(Integer)get(call(rotate,"geometry"),"turns")==((originalTurns+1)%4));
            check("rotate-entry-is-tentative",before.equals(identity(get(editor,"geometry"))));
            cancel(rotate);
            check("rotate-cancel-preserves-main-state",before.equals(identity(get(editor,"geometry")))&&initialHistory==historySize());

            stage="rotate-entry-apply";
            rotate=openEntry("editor-composition-rotate");
            String rotated=identity(call(rotate,"geometry"));
            click(requireButton(rotate,"应用"));
            waitEditor(); drain();
            check("rotate-apply-commits-staged-geometry",rotated.equals(identity(get(editor,"geometry"))));
            check("rotate-apply-one-history-step",historySize()==initialHistory+1);
            samePreserved(preserved,"rotate");
            performHistory(false);
            check("rotate-undo-restores-prior-geometry",before.equals(identity(get(editor,"geometry"))));
            performHistory(true);
            check("rotate-redo-restores-applied-geometry",rotated.equals(identity(get(editor,"geometry"))));

            stage="straighten-entry";
            Dialog straight=openEntry("editor-composition-straighten");
            until(()->(Integer)get(straight,"transformMode")==0&&((SeekBar)get(straight,"slider")).hasFocus(),"straighten-default-mode-and-slider-focus");
            check("straighten-open-keeps-geometry",rotated.equals(identity(call(straight,"geometry"))));
            cancel(straight);

            stage="perspective-entry";
            Dialog perspective=openEntry("editor-composition-perspective");
            check("perspective-default-horizontal-mode",(Integer)get(perspective,"transformMode")==1);
            click((View)get(perspective,"transformChoice"));
            clickNativeMenu("垂直透视");
            until(()->(Integer)get(perspective,"transformMode")==2,"native-vertical-perspective-selected");
            untilExternal(()->!hasNativeMenu("垂直透视"),"perspective-popup-dismissed-before-keyboard");
            until(()->perspective.getWindow().getDecorView().hasWindowFocus(),"perspective-dialog-regains-window-focus");
            focusWithKeyboard((SeekBar)get(perspective,"slider"));
            sendKeyDownUpSync(KeyEvent.KEYCODE_DPAD_RIGHT);
            sendKeyDownUpSync(KeyEvent.KEYCODE_DPAD_RIGHT);
            sendKeyDownUpSync(KeyEvent.KEYCODE_DPAD_RIGHT);
            until(()->(Integer)get(call(perspective,"geometry"),"verticalPerspective")!=0,"perspective-native-slider-changes-temporary-geometry");
            check("perspective-remains-tentative",rotated.equals(identity(get(editor,"geometry"))));
            capture("02-composition-workspace",perspective.getWindow().getDecorView());
            cancel(perspective);
            check("perspective-cancel-keeps-applied-rotation",rotated.equals(identity(get(editor,"geometry"))));

            stage="reset-composition";
            int resetHistory=historySize();
            click(editorTag("editor-composition-reset"));
            waitEditor(); drain();
            check("reset-clears-only-geometry",(Boolean)call(get(editor,"geometry"),"isNeutral"));
            check("reset-adds-one-history-step",historySize()==resetHistory+1);
            samePreserved(preserved,"reset");
            performHistory(false);
            drain();
            check("undo-reset-restores-geometry",rotated.equals(identity(get(editor,"geometry"))));
            samePreserved(preserved,"undo-reset");

            stage="restore-other-mode-heights";
            click((View)get(editor,"filterModeButton"));
            awaitPanelHeight(176,"restored-filter-content-height");
            if(!landscape)check("filter-restores-exact-stage-bounds",filterStage.equals(bounds(activityTag("editor-photo-stage"))));
            click((View)get(editor,"adjustmentModeButton"));
            awaitPanelHeight(176,"restored-adjustment-content-height");
            if(!landscape)check("adjustment-restores-exact-stage-bounds",filterStage.equals(bounds(activityTag("editor-photo-stage"))));
            check("source-jpeg-bytes-preserved",sourceSha.equals(sha(original)));
            check("exactly-two-success-screenshots",screenshotCount==2);
            stage="complete";
        } catch(Throwable error) {
            failure=unwrap(error);
        } finally {
            cleanup(); report();
            Bundle result=new Bundle();
            result.putString("summary",failure==null?"PASS "+checks.length()+" checks; "+screenshotCount+" screenshots":"FAIL "+stage+" "+failure);
            finish(failure==null?Activity.RESULT_OK:Activity.RESULT_CANCELED,result);
        }
    }

    private Object createFixture(String run) throws Exception {
        int resource=getTargetContext().getResources().getIdentifier("preset_template","drawable","cc.huevia");
        Bitmap sample=BitmapFactory.decodeResource(getTargetContext().getResources(),resource);
        if(sample==null)throw new java.io.IOException("Shipping preset_template photo unavailable");
        int sourceWidth=sample.getWidth(),sourceHeight=sample.getHeight();
        double scale=Math.min(1,Math.min(960.0/sourceWidth,640.0/sourceHeight));
        Bitmap image=Bitmap.createScaledBitmap(sample,Math.max(1,(int)Math.round(sourceWidth*scale)),Math.max(1,(int)Math.round(sourceHeight*scale)),true);
        if(image!=sample)sample.recycle();
        fixtureIdentity.put("resource","app/src/main/res/drawable-nodpi/preset_template.png").put("resourceSourceSha256","067e391dcb5a61c20021dc9a4a7eb4c324829592a5de747dd1f4a958ce44c8d9").put("sourceWidth",sourceWidth).put("sourceHeight",sourceHeight).put("fixtureWidth",image.getWidth()).put("fixtureHeight",image.getHeight());
        File folder=new File(getTargetContext().getExternalFilesDir(Environment.DIRECTORY_PICTURES),"camera-album");
        folder.mkdirs();File target=new File(folder,"composition-qa-"+run+"__COMPOSITION.JPG");
        check("fixture-name-reserved-exclusively",target.createNewFile());
        original=target;
        try(FileOutputStream out=new FileOutputStream(original)){check("private-jpeg-created",image.compress(Bitmap.CompressFormat.JPEG,98,out));}
        finally{image.recycle();}
        ExifInterface exif=new ExifInterface(original.getPath());
        exif.setAttribute("Orientation","1");
        exif.setAttribute("ImageDescription","Composition dock fixture "+run+" "+UUID.randomUUID());
        exif.saveAttributes();
        sourceSha=sha(original);
        check("fixture-has-no-prior-draft",call(store,"read",new Class<?>[]{String.class},sourceSha)==null);
        ownsDraft=true;
        // DownloadedPhoto constructors are package-private; public-only lookup cannot resolve them.
        java.lang.reflect.Constructor<?> constructor=type("cc.huevia.album.DownloadedPhoto").getDeclaredConstructor(File.class,String.class,String.class,String.class,long.class);
        constructor.setAccessible(true);
        return constructor.newInstance(original,"COMPOSITION.JPG","","",original.lastModified());
    }

    /** Distinct private fixture markers make reset preservation meaningful without opening unrelated tools. */
    @SuppressWarnings({"unchecked","rawtypes"})
    private void seedPreservationMarkers() throws Exception {
        Class<?> adjustments=type("cc.huevia.ncp.PhotoAdjustments"),parameter=type("cc.huevia.ncp.PhotoAdjustments$Parameter");
        Object colour=call(adjustments.getField("NONE").get(null),"with",new Class<?>[]{parameter,int.class},Enum.valueOf((Class)parameter,"EXPOSURE"),4);
        Class<?> edits=type("cc.huevia.ncp.PhotoLocalEdits"),mask=type("cc.huevia.ncp.PhotoLocalEdits$Mask");
        Object radial=staticCall(mask,"radial",new Class<?>[]{double.class,double.class},.4,.5);
        radial=call(radial,"parameters",new Class<?>[]{int.class,int.class,int.class},4,3,5);
        Object local=call(edits.getField("NONE").get(null),"add",new Class<?>[]{mask},radial);
        Class<?> border=type("cc.huevia.ncp.PhotoBorder");
        Object frame=call(border.getField("NONE").get(null),"withTemplate",new Class<?>[]{int.class},1);
        ui(()->{set(editor,"adjustments",colour);set(editor,"localEdits",local);set(editor,"border",frame);call(editor,"edited");});
        check("non-neutral-colour-fixture",!(Boolean)call(colour,"isNeutral"));
        check("non-neutral-local-fixture",!(Boolean)call(local,"isNeutral"));
        check("non-neutral-border-fixture",!(Boolean)call(frame,"isNone"));
    }

    private void verifyDock(boolean landscape,Rect priorStage) throws Exception {
        ui(()->{
            View panels=editorTag("editor-tool-panels"),dock=(View)get(editor,"dock");
            float scale=Math.max(1,activity.getResources().getConfiguration().fontScale);
            check("composition-content-is-112fp",Math.abs(panels.getHeight()-dp(112*scale))<=1);
            if(!landscape)check("composition-dock-is-160fp",Math.abs(dock.getHeight()-dp(160*scale))<=2);
            String[] tags={"editor-open-composition","editor-composition-rotate","editor-composition-straighten","editor-composition-perspective"};
            String[] labels={"裁剪","旋转","拉直","透视"};
            for(int i=0;i<tags.length;i++){
                View target=editorTag(tags[i]);Rect visible=bounds(target);
                check(tags[i]+"-48dp-touch-target",target.getWidth()>=dp(48)&&target.getHeight()>=dp(48));
                check(tags[i]+"-fully-visible",visible.width()>=target.getWidth()-1&&visible.height()>=target.getHeight()-1);
                check(tags[i]+"-keyboard-focusable",target.isFocusable()&&target.isClickable());
                check(tags[i]+"-accessible-name",target.getContentDescription()!=null&&target.getContentDescription().length()>0);
                check(tags[i]+"-has-icon",hasIcon(target));
                TextView label=findText(target,labels[i]);
                check(tags[i]+"-visible-caption",label!=null);
                checkSingleLine(label,tags[i]);
            }
            View reset=editorTag("editor-composition-reset");
            check("reset-48dp-touch-target",reset.getWidth()>=dp(48)&&reset.getHeight()>=dp(48));
            check("reset-accessible-name",reset.getContentDescription()!=null&&reset.getContentDescription().toString().contains("重置构图"));
            check("reset-has-small-icon",hasIcon(reset)&&reset.getWidth()<=dp(48)+1&&findText(reset,"重置")==null);
            Rect resetBounds=bounds(reset);
            for(String tag:tags){Rect intersection=new Rect(resetBounds);check("reset-does-not-overlap-"+tag,!intersection.intersect(bounds(editorTag(tag))));}
            check("composition-summary-exists",editorTag("editor-composition-summary") instanceof TextView);
            check("old-large-open-label-removed",findText(dock,"打开构图")==null);
            Rect nextStage=bounds(activityTag("editor-photo-stage"));
            if(!landscape){check("composition-gives-photo-more-height",nextStage.height()>=priorStage.height()+dp(64*scale)-2);check("composition-keeps-photo-width",nextStage.width()==priorStage.width());}
            measurements.put(new JSONObject().put("mode",args.getString("mode")).put("fontScale",scale).put("contentHeightPx",panels.getHeight()).put("dockHeightPx",dock.getHeight()).put("filterStage",rect(priorStage)).put("compositionStage",rect(nextStage)));
        });
    }

    private void checkSingleLine(TextView label,String name) {
        Layout layout=label.getLayout();
        check(name+"-single-line-caption",layout!=null&&layout.getLineCount()==1);
        check(name+"-caption-not-ellipsized",layout.getEllipsisCount(0)==0);
        check(name+"-caption-fits-width",layout.getLineWidth(0)<=label.getWidth()-label.getCompoundPaddingLeft()-label.getCompoundPaddingRight()+1);
        check(name+"-caption-fits-height",layout.getHeight()<=label.getHeight()-label.getCompoundPaddingTop()-label.getCompoundPaddingBottom()+1);
    }

    private Dialog openEntry(String name) throws Exception {
        click(editorTag(name));
        until(()->{Object d=get(editor,"popup");return d instanceof Dialog&&d.getClass().getSimpleName().equals("PhotoCropDialog")&&((Dialog)d).isShowing()&&((View)get(d,"crop")).getWidth()>0;},name+"-opens-native-crop-workspace");
        Dialog dialog=(Dialog)get(editor,"popup");dialogs.add(dialog);
        committed(dialog.getWindow().getDecorView());
        return dialog;
    }

    private void cancel(Dialog dialog) throws Exception {
        click(requireButton(dialog,"取消"));
        until(()->!dialog.isShowing()&&get(editor,"popup")==null,"crop-dialog-cancelled");
        committed(activity.getWindow().getDecorView());
    }

    /** History controls belong to the adjustment panel; use their real visible UI context. */
    private void performHistory(boolean forward) throws Exception {
        click((View)get(editor,"adjustmentModeButton"));
        awaitPanelHeight(176,forward?"redo-opens-adjustment-panel":"undo-opens-adjustment-panel");
        click((View)get(editor,forward?"redoButton":"undoButton"));
        waitEditor();
        click(editorTag("composition-mode"));
        until(()->(Boolean)get(editor,"compositionMode"),"history-returns-to-composition-tab");
        awaitPanelHeight(112,"history-restores-composition-content-height");
    }

    /** Inject at the real visible screen position, rather than invoking the app listener. */
    private void click(View view) throws Exception {
        acknowledgeImmersive();
        Rect[] target={null};
        ui(()->{check("real-click-target-visible",view.isShown()&&view.isEnabled());target[0]=bounds(view);check("real-click-target-nonempty",!target[0].isEmpty());});
        long now=SystemClock.uptimeMillis();
        MotionEvent down=MotionEvent.obtain(now,now,MotionEvent.ACTION_DOWN,target[0].exactCenterX(),target[0].exactCenterY(),0);
        MotionEvent up=MotionEvent.obtain(now,now+30,MotionEvent.ACTION_UP,target[0].exactCenterX(),target[0].exactCenterY(),0);
        down.setSource(InputDevice.SOURCE_TOUCHSCREEN);up.setSource(InputDevice.SOURCE_TOUCHSCREEN);
        try{sendPointerSync(down);sendPointerSync(up);}finally{down.recycle();up.recycle();}
        waitForIdleSync();
    }

    private void clickNativeMenu(String label) throws Exception {
        acknowledgeImmersive();
        long end=SystemClock.uptimeMillis()+5000;
        while(SystemClock.uptimeMillis()<end){
            AccessibilityNodeInfo node=findWindowNode("cc.huevia",label);
            if(node!=null&&clickAccessible(node,"cc.huevia")){waitForIdleSync();check("native-menu-click-"+label,true);return;}
            SystemClock.sleep(40);
        }
        check("native-menu-click-"+label,false);
    }

    private void focusWithKeyboard(View target) {
        for(int i=0;i<16;i++){
            boolean[] focused={false};ui(()->focused[0]=target.hasFocus());
            if(focused[0]){check("native-keyboard-focuses-perspective-slider",true);return;}
            sendKeyDownUpSync(KeyEvent.KEYCODE_TAB);waitForIdleSync();
        }
        check("native-keyboard-focuses-perspective-slider",false);
    }

    private void acknowledgeImmersive() throws Exception {
        AccessibilityNodeInfo teaching=findWindowNode("com.android.systemui","Got it");
        if(teaching!=null){check("systemui-immersive-teaching-real-click",clickAccessible(teaching,"com.android.systemui"));untilExternal(()->findWindowNode("com.android.systemui","Got it")==null,"systemui-teaching-dismissed");}
    }

    private boolean hasNativeMenu(String label) { return findWindowNode("cc.huevia",label)!=null; }
    private AccessibilityNodeInfo findWindowNode(String packageName,String label) {
        AccessibilityServiceInfo info=getUiAutomation().getServiceInfo();
        info.flags|=AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS;getUiAutomation().setServiceInfo(info);
        List<AccessibilityWindowInfo> windows=getUiAutomation().getWindows();
        for(AccessibilityWindowInfo window:windows){AccessibilityNodeInfo root=window.getRoot();AccessibilityNodeInfo node=findNode(root,packageName,label);if(node!=null)return node;}
        return findNode(getUiAutomation().getRootInActiveWindow(),packageName,label);
    }
    private static AccessibilityNodeInfo findNode(AccessibilityNodeInfo root,String pkg,String label) {
        if(root==null)return null;
        if(root.getPackageName()!=null&&pkg.contentEquals(root.getPackageName())&&root.getText()!=null&&label.contentEquals(root.getText()))return root;
        for(int i=0;i<root.getChildCount();i++){AccessibilityNodeInfo found=findNode(root.getChild(i),pkg,label);if(found!=null)return found;}
        return null;
    }
    private static boolean clickAccessible(AccessibilityNodeInfo node,String pkg) {
        for(int i=0;node!=null&&i<6;i++,node=node.getParent()){
            if(node.getPackageName()==null||!pkg.contentEquals(node.getPackageName()))return false;
            if(node.isClickable()&&node.performAction(AccessibilityNodeInfo.ACTION_CLICK))return true;
        }
        return false;
    }

    private void awaitPanelHeight(int logical,String name) throws Exception {
        until(()->Math.abs(editorTag("editor-tool-panels").getHeight()-dp(logical*Math.max(1,activity.getResources().getConfiguration().fontScale)))<=1,name);
        committed(activity.getWindow().getDecorView());
        if(logical==176&&!args.getString("mode").equals("landscape"))check(name+"-dock-224fp",Math.abs(((View)get(editor,"dock")).getHeight()-dp(224*Math.max(1,activity.getResources().getConfiguration().fontScale)))<=2);
    }

    /** A completed GPU frame is the screenshot boundary, with an animation-frame fallback on pre-29. */
    private void committed(View root) throws Exception {
        CountDownLatch rendered=new CountDownLatch(1);
        ui(()->{
            if(Build.VERSION.SDK_INT>=29&&root.isHardwareAccelerated())root.getViewTreeObserver().registerFrameCommitCallback(rendered::countDown);
            else root.postOnAnimation(()->root.postOnAnimation(rendered::countDown));
            root.postInvalidateOnAnimation();
        });
        check("visible-frame-committed",rendered.await(5,TimeUnit.SECONDS));
        waitForIdleSync();
    }
    private void capture(String name,View root) throws Exception {
        acknowledgeImmersive();
        committed(root);
        Bitmap screenshot=getUiAutomation().takeScreenshot();check("screenshot-"+name,screenshot!=null);
        try{
            boolean stable=false;long end=SystemClock.uptimeMillis()+5000;
            while(SystemClock.uptimeMillis()<end){
                committed(root);
                Bitmap next=getUiAutomation().takeScreenshot();check("screenshot-next-frame-"+name,next!=null);
                stable=screenshot.sameAs(next);screenshot.recycle();screenshot=next;
                if(stable)break;
            }
            check("screenshot-pixels-settled-"+name,stable);
            check("screenshot-no-system-teaching-"+name,findWindowNode("com.android.systemui","Got it")==null);
            try(FileOutputStream out=new FileOutputStream(new File(output,name+".png"))){check("screenshot-written-"+name,screenshot.compress(Bitmap.CompressFormat.PNG,100,out));}
        }finally{screenshot.recycle();}screenshotCount++;
    }

    private String[] preserved() throws Exception { return new String[]{identity(get(editor,"adjustments")),identity(get(editor,"localEdits")),identity(get(editor,"border"))}; }
    private void samePreserved(String[] prior,String prefix) throws Exception {
        String[] next=preserved();String[] labels={"colour","local","border"};
        for(int i=0;i<prior.length;i++)check(prefix+"-preserves-"+labels[i],prior[i].equals(next[i]));
    }
    private int historySize() throws Exception { return ((Deque<?>)get(editor,"undo")).size(); }
    private void waitEditor() throws Exception {
        until(()->{ThreadPoolExecutor worker=(ThreadPoolExecutor)get(editor,"previews");return worker.getActiveCount()==0&&worker.getQueue().isEmpty();},"editor-preview-settled");
        committed(activity.getWindow().getDecorView());
    }
    private void drain() throws Exception {
        CountDownLatch done=new CountDownLatch(1);
        ui(()->call(editor,"afterPendingSaves",new Class<?>[]{Runnable.class},(Runnable)done::countDown));
        check("editor-saves-drained",done.await(15,TimeUnit.SECONDS));
    }
    private void cleanupStep(String label,Work work) {
        try{work.run();}catch(Throwable error){cleanupErrors.put(label+": "+unwrap(error));if(failure==null)failure=unwrap(error);}
    }
    private void cleanup() {
        for(Dialog dialog:dialogs)cleanupStep("dismiss owned dialog",()->{if(dialog.isShowing())ui(dialog::dismiss);});
        if(editor!=null){cleanupStep("drain fixture saves",this::drain);cleanupStep("unbind fixture editor",()->ui(()->call(editor,"unbind")));cleanupStep("drain final fixture saves",this::drain);}
        cleanupStep("remove fixture draft",()->{if(ownsDraft&&draftRoot!=null&&sourceSha!=null)Files.deleteIfExists(new File(draftRoot,sourceSha+".draft").toPath());});
        cleanupStep("remove owned JPEG",()->{if(original!=null)Files.deleteIfExists(original.toPath());fixtureRemoved=original==null||!original.exists();});
        cleanupStep("finish owned activity",()->{if(activity!=null)ui(()->{activity.setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED);activity.finish();});});
    }
    private void report() {
        try{
            if(output==null)return;
            PackageInfo p=getTargetContext().getPackageManager().getPackageInfo("cc.huevia",0);
            JSONObject report=new JSONObject().put("pass",failure==null).put("stage",stage).put("apkSha256",sha(new File(getTargetContext().getApplicationInfo().sourceDir))).put("versionCode",p.getLongVersionCode()).put("versionName",p.versionName).put("mode",args.getString("mode")).put("checks",checks).put("measurements",measurements).put("fixture",fixtureIdentity).put("screenshots",screenshotCount).put("fixtureRemoved",fixtureRemoved).put("cleanupErrors",cleanupErrors).put("failure",failure==null?JSONObject.NULL:failure.toString()).put("scope","Actual installed MainActivity/AlbumPanel/local-photo editor; owned JPEG derived from the shipping preset_template photo with its aspect ratio retained and a unique EXIF description; native pointer clicks on four composition entries, reset and history; native perspective menu/keyboard; temporary versus committed geometry; independent seeded colour/local/border preservation markers; font/orientation layout and committed-frame screenshots. No camera, account transition, publication, physical-device or TalkBack certification.");
            try(FileOutputStream out=new FileOutputStream(new File(output,"report.json"))){out.write(report.toString(2).getBytes(StandardCharsets.UTF_8));}
        }catch(Throwable error){if(failure==null)failure=unwrap(error);}
    }

    private View editorTag(String name) throws Exception { View found=((View)get(editor,"dock")).findViewWithTag(name);if(found==null)throw new AssertionError("Missing editor tag "+name);return found; }
    private View activityTag(String name) { View found=activity.getWindow().getDecorView().findViewWithTag(name);if(found==null)throw new AssertionError("Missing activity tag "+name);return found; }
    private static TextView findText(View root,String text) { if(root instanceof TextView&&text.contentEquals(((TextView)root).getText()))return(TextView)root;if(root instanceof ViewGroup)for(int i=0;i<((ViewGroup)root).getChildCount();i++){TextView found=findText(((ViewGroup)root).getChildAt(i),text);if(found!=null)return found;}return null; }
    private static boolean hasIcon(View root) { if(drawableHasIcon(root.getBackground()))return true;if(root instanceof ImageView&&((ImageView)root).getDrawable()!=null)return true;if(root instanceof TextView)for(android.graphics.drawable.Drawable icon:((TextView)root).getCompoundDrawables())if(icon!=null)return true;if(root instanceof ViewGroup)for(int i=0;i<((ViewGroup)root).getChildCount();i++)if(hasIcon(((ViewGroup)root).getChildAt(i)))return true;return false; }
    private static boolean drawableHasIcon(android.graphics.drawable.Drawable drawable) { if(drawable==null)return false;if(drawable.getClass().getName().equals("cc.huevia.ui.AppIcon"))return true;if(drawable instanceof android.graphics.drawable.LayerDrawable){android.graphics.drawable.LayerDrawable layers=(android.graphics.drawable.LayerDrawable)drawable;for(int i=0;i<layers.getNumberOfLayers();i++)if(drawableHasIcon(layers.getDrawable(i)))return true;}if(drawable instanceof android.graphics.drawable.InsetDrawable)return drawableHasIcon(((android.graphics.drawable.InsetDrawable)drawable).getDrawable());return false; }
    private static Button requireButton(Dialog dialog,String label) { TextView found=findText(dialog.getWindow().getDecorView(),label);if(!(found instanceof Button))throw new AssertionError("Missing button "+label);return(Button)found; }
    private static Rect bounds(View view) { Rect rect=new Rect();view.getGlobalVisibleRect(rect);return rect; }
    private static JSONArray rect(Rect value) { return new JSONArray().put(value.left).put(value.top).put(value.right).put(value.bottom); }
    private int dp(float value) { return Math.round(value*activity.getResources().getDisplayMetrics().density); }
    private String identity(Object value) throws Exception { return (String)call(value,"identity"); }
    private void until(Condition condition,String label) throws Exception { long end=SystemClock.uptimeMillis()+20000;while(SystemClock.uptimeMillis()<end){boolean[] ready={false};ui(()->ready[0]=condition.test());if(ready[0]){check(label,true);return;}SystemClock.sleep(40);}check(label,false); }
    private void untilExternal(Condition condition,String label) throws Exception { long end=SystemClock.uptimeMillis()+5000;while(SystemClock.uptimeMillis()<end){if(condition.test()){check(label,true);return;}SystemClock.sleep(40);}check(label,false); }
    private void check(String label,boolean pass) { try{checks.put(new JSONObject().put("name",label).put("pass",pass));}catch(Exception impossible){throw new AssertionError(impossible);}if(!pass)throw new AssertionError(label); }
    private void ui(Work work) { Throwable[] error={null};runOnMainSync(()->{try{work.run();}catch(Throwable failure){error[0]=failure;}});if(error[0]!=null)throw new RuntimeException(error[0]); }
    private Class<?> type(String name) throws ClassNotFoundException { return Class.forName(name,true,loader); }
    private static Object get(Object target,String name) throws Exception { for(Class<?> c=target.getClass();c!=null;c=c.getSuperclass())try{Field field=c.getDeclaredField(name);field.setAccessible(true);return field.get(target);}catch(NoSuchFieldException ignored){}throw new NoSuchFieldException(target.getClass().getName()+"."+name); }
    private static void set(Object target,String name,Object value) throws Exception { for(Class<?> c=target.getClass();c!=null;c=c.getSuperclass())try{Field field=c.getDeclaredField(name);field.setAccessible(true);field.set(target,value);return;}catch(NoSuchFieldException ignored){}throw new NoSuchFieldException(name); }
    private static Method method(Class<?> type,String name,Class<?>[] parameters) throws Exception { for(Class<?> c=type;c!=null;c=c.getSuperclass())try{Method method=c.getDeclaredMethod(name,parameters);method.setAccessible(true);return method;}catch(NoSuchMethodException ignored){}throw new NoSuchMethodException(type.getName()+"."+name); }
    private static Object call(Object target,String name) throws Exception { return call(target,name,new Class<?>[0]); }
    private static Object call(Object target,String name,Class<?>[] parameters,Object... values) throws Exception { return method(target.getClass(),name,parameters).invoke(target,values); }
    private static Object staticCall(Class<?> type,String name,Class<?>[] parameters,Object... values) throws Exception { return method(type,name,parameters).invoke(null,values); }
    private static Throwable unwrap(Throwable error) { while(error.getCause()!=null&&(error instanceof InvocationTargetException||error instanceof RuntimeException))error=error.getCause();return error; }
    private static String sha(File file) throws Exception { MessageDigest digest=MessageDigest.getInstance("SHA-256");try(InputStream in=new FileInputStream(file)){byte[] bytes=new byte[65536];int count;while((count=in.read(bytes))!=-1)digest.update(bytes,0,count);}StringBuilder hex=new StringBuilder();for(byte value:digest.digest())hex.append(Character.forDigit((value>>>4)&15,16)).append(Character.forDigit(value&15,16));return hex.toString(); }
}
