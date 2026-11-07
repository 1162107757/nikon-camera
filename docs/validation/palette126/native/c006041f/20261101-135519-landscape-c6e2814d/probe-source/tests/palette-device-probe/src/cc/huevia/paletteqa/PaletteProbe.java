package cc.huevia.paletteqa;

import android.app.*;
import android.content.*;
import android.content.pm.ActivityInfo;
import android.graphics.*;
import android.os.*;
import android.view.*;
import android.widget.*;
import java.io.*;
import java.lang.reflect.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;
import java.util.function.Consumer;
import org.json.*;

/** Android-only instrumentation: every app symbol is resolved from the installed candidate. */
public final class PaletteProbe extends Instrumentation {
    private Bundle args;
    private Activity activity;
    private ClassLoader loader;
    private File output, fixtureFile, draftFile;
    private Object editor, panel;
    private Bitmap source;
    private String sourceSha, stage="start";
    private Throwable failure;
    private int screenshots;
    private boolean fixtureRemoved=true;
    private final JSONArray checks=new JSONArray(), measurements=new JSONArray();
    private final List<Dialog> dialogs=new ArrayList<>();
    private final List<Bitmap> owned=new ArrayList<>();
    private interface Work {void run() throws Exception;}
    private interface Condition {boolean test() throws Exception;}

    @Override public void onCreate(Bundle value) {args=value;start();}
    @Override public void onStart() {
        try {
            loader=getTargetContext().getClassLoader();
            check("owned-emulator",Build.HARDWARE.equals("ranchu")||Build.HARDWARE.equals("goldfish"));
            check("exact-installed-candidate",sha(new File(getTargetContext().getApplicationInfo().sourceDir)).equals(args.getString("candidateSha256")));
            String run=args.getString("runId");
            check("safe-run-id",run!=null&&run.matches("[a-zA-Z0-9.-]+"));
            output=new File(getTargetContext().getExternalFilesDir(null),"palette126/"+run);
            output.getParentFile().mkdirs();check("new-evidence-directory",output.mkdir());
            activity=startActivitySync(new Intent().setClassName("cc.huevia","cc.huevia.MainActivity").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            until(()->(Boolean)get(activity,"ready"),"activity-ready");
            boolean landscape="landscape".equals(args.getString("mode"));
            ui(()->activity.setRequestedOrientation(landscape?ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE:ActivityInfo.SCREEN_ORIENTATION_PORTRAIT));
            until(()->activity.getResources().getConfiguration().orientation==(landscape?2:1),"requested-orientation");
            source=Bitmap.createBitmap(960,720,Bitmap.Config.ARGB_8888);
            int[] pixels=new int[960*720];
            for(int y=0;y<720;y++)for(int x=0;x<960;x++) {
                int r=24+x*195/960,g=32+y*175/720,b=38+(x+y)*140/1680;
                if(x>360&&x<600&&y>180&&y<540) {r=190+(x%23);g=114+(y%29);b=77+(x+y)%19;}
                pixels[y*960+x]=0xff000000|(r<<16)|(g<<8)|b;
            }
            source.setPixels(pixels,0,960,0,0,960,720);sourceSha=bitmapSha(source);
            standaloneCase();
            mainEditorCase();
            check("borrowed-source-pixels-unchanged",sourceSha.equals(bitmapSha(source)));
        } catch(Throwable error) {
            failure=unwrap(error);try {screenshot("failure");} catch(Throwable ignored) {}
        } finally {
            try {ui(()->{for(Dialog d:dialogs)if(d.isShowing())d.dismiss();});} catch(Throwable ignored) {}
            try {cleanupEditor();} catch(Throwable cleanup) {if(failure==null)failure=unwrap(cleanup);}
            try {ui(()->{if(activity!=null){activity.setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED);activity.finish();}});} catch(Throwable ignored) {}
            if(source!=null&&!source.isRecycled())source.recycle();
            for(Bitmap bitmap:owned)if(bitmap!=null&&!bitmap.isRecycled())bitmap.recycle();
        }
        Bundle result=new Bundle();
        try {
            JSONObject report=new JSONObject().put("pass",failure==null).put("stage",stage)
                .put("mode",args.getString("mode")).put("scope",args.getString("scope"))
                .put("candidateSha256",args.getString("candidateSha256"))
                .put("checks",checks).put("measurements",measurements).put("screenshots",screenshots)
                .put("persistentFixturesCreated",fixtureFile!=null).put("privateFixtureRemoved",fixtureRemoved);
            if(failure!=null)report.put("failure",failure.toString()).put("stack",android.util.Log.getStackTraceString(failure));
            if(output!=null)Files.write(new File(output,"report.json").toPath(),report.toString(2).getBytes(StandardCharsets.UTF_8));
            result.putString("stream",(failure==null?"PASS":"FAIL")+" "+checks.length()+" checks "+stage+" "+(failure==null?"":failure));
        } catch(Throwable error) {result.putString("stream","FAIL report "+error);}
        finish(failure==null?Activity.RESULT_OK:Activity.RESULT_CANCELED,result);
    }

    private void standaloneCase() throws Exception {
        stage="dialog-live-drag-and-transaction";
        Object initial=basicSettings();
        AtomicReference<Object> committed=new AtomicReference<>();
        AtomicInteger renderCalls=new AtomicInteger();
        Dialog dialog=open(initial,committed,renderCalls);
        View pad=tag(dialog,"palette-pad"), photo=tag(dialog,"palette-photo");
        check("palette-pad-visible",pad.isShown()&&pad.getWidth()>0&&pad.getHeight()>0);
        bounds(dialog,pad,photo);
        screenshot("01-palette-open");
        Bitmap originalPreview=(Bitmap)get(photo,"photo");
        String basePreview=bitmapSha(originalPreview);
        int rendered=renderCalls.get();
        long down=SystemClock.uptimeMillis();
        padTouch(dialog,down,MotionEvent.ACTION_DOWN,.5f,.5f);
        padTouch(dialog,down,MotionEvent.ACTION_MOVE,.85f,.22f);
        Object livePalette=get(settings(dialog),"palette");
        check("live-drag-color-updates-before-up",integer(livePalette,"color")>=60);
        check("live-drag-tone-updates-before-up",integer(livePalette,"tone")>=50);
        check("live-drag-old-sliders-preserved",sameBasic(initial,settings(dialog)));
        until(()->renderCalls.get()>rendered&&!basePreview.equals(bitmapSha((Bitmap)get(photo,"photo"))),"live-photo-before-up");
        screenshot("02-live-drag-before-up");
        padTouch(dialog,down,MotionEvent.ACTION_CANCEL,.85f,.22f);
        check("touch-cancel-restores-full-gesture-start",initial.equals(settings(dialog)));
        until(()->basePreview.equals(bitmapSha((Bitmap)get(photo,"photo"))),"cancel-restores-photo");
        check("cancel-does-not-commit",committed.get()==null);

        int historyBefore=historySize(dialog,"history");
        drag(dialog,.5f,.5f,.81f,.25f);
        Object colored=settings(dialog), selected=get(colored,"palette");
        check("one-complete-drag-one-undo",historySize(dialog,"history")==historyBefore+1);
        check("completed-drag-keeps-color-and-tone",integer(selected,"color")>=50&&integer(selected,"tone")>=45);
        click(dialog,"palette-undo");
        check("dialog-undo-restores-baseline",initial.equals(settings(dialog)));
        click(dialog,"palette-redo");
        check("dialog-redo-restores-drag",colored.equals(settings(dialog)));

        stage="strength-zero-and-accessible-input";
        SeekBar strength=(SeekBar)tag(dialog,"palette-strength");
        check("strength-control-keyboard-focusable",strength.isFocusable());
        setSeekByTouch(strength,0);
        Object zero=get(settings(dialog),"palette");
        check("strength-zero-retains-color",integer(zero,"color")==integer(selected,"color"));
        check("strength-zero-retains-tone",integer(zero,"tone")==integer(selected,"tone"));
        check("strength-zero-value",integer(zero,"amount")==0);
        until(()->basePreview.equals(bitmapSha((Bitmap)get(photo,"photo"))),"strength-zero-photo-identity");
        setSeekByTouch(strength,1);
        check("strength-full-value",integer(get(settings(dialog),"palette"),"amount")==100);
        check("strength-restores-axes",integer(get(settings(dialog),"palette"),"color")==integer(selected,"color"));
        click(dialog,"palette-value-0");
        until(()->getTopExact()!=null,"exact-color-input-visible");
        Dialog exact=getTopExact();
        EditText input=(EditText)tag(exact,"palette-exact-input");
        ui(()->input.setText("-23"));
        ui(()->((AlertDialog)exact).getButton(AlertDialog.BUTTON_POSITIVE).performClick());
        check("exact-color-applied",integer(get(settings(dialog),"palette"),"color")==-23);
        int toneBefore=integer(get(settings(dialog),"palette"),"tone");
        ui(()->{pad.requestFocus();pad.dispatchKeyEvent(new KeyEvent(KeyEvent.ACTION_DOWN,KeyEvent.KEYCODE_DPAD_UP));pad.dispatchKeyEvent(new KeyEvent(KeyEvent.ACTION_UP,KeyEvent.KEYCODE_DPAD_UP));});
        check("keyboard-pad-adjusts-tone",integer(get(settings(dialog),"palette"),"tone")==toneBefore+1);
        check("keyboard-keeps-color",integer(get(settings(dialog),"palette"),"color")==-23);
        ui(()->{if(!pad.performAccessibilityAction(0x7f0f7304,null))throw new AssertionError("Tone accessibility action not handled");});
        check("talkback-tone-action-adjusts-five",integer(get(settings(dialog),"palette"),"tone")==toneBefore-4);
        Object beforeInterruption=settings(dialog);
        long interrupted=SystemClock.uptimeMillis();
        padTouch(dialog,interrupted,MotionEvent.ACTION_DOWN,.6f,.6f);
        padTouch(dialog,interrupted,MotionEvent.ACTION_MOVE,.95f,.8f);
        // Exercise the real Dialog callback with an unfinished touch transaction.
        ui(()->dialog.onWindowFocusChanged(false));
        check("window-focus-loss-rolls-back-unfinished-stroke",beforeInterruption.equals(settings(dialog)));
        ui(()->dialog.onWindowFocusChanged(true));
        click(dialog,"palette-reset");
        waitPalette(dialog);
        check("palette-reset-only-palette",initial.equals(settings(dialog)));
        check("reset-preserves-original-basic-values",sameBasic(initial,settings(dialog)));
        screenshot("03-reset-clean-preview");
        ui(dialog::dismiss);
        check("dismiss-cancels-without-commit",committed.get()==null);

        Dialog applyDialog=open(initial,committed,new AtomicInteger());
        drag(applyDialog,.5f,.5f,.24f,.72f);
        Object expected=settings(applyDialog);
        click(applyDialog,"palette-apply");
        until(()->!applyDialog.isShowing(),"apply-dismissed");
        check("standalone-apply-exact-settings",expected.equals(committed.get()));
        check("apply-retains-other-manual-tools",sameBasic(initial,committed.get()));
        check("dialog-borrowed-source-unmodified",sourceSha.equals(bitmapSha(source)));
    }

    private void mainEditorCase() throws Exception {
        stage="main-editor-owned-fixture";
        File folder=new File(getTargetContext().getExternalFilesDir(Environment.DIRECTORY_PICTURES),"camera-album");
        folder.mkdirs();fixtureFile=new File(folder,"palette-qa-"+args.getString("runId")+".JPG");
        check("owned-fixture-not-existing",!fixtureFile.exists());fixtureRemoved=false;
        Bitmap fixture=Bitmap.createScaledBitmap(source,1601,1103,true);
        try(OutputStream out=new FileOutputStream(fixtureFile)){fixture.compress(Bitmap.CompressFormat.JPEG,98,out);}finally{fixture.recycle();}
        android.media.ExifInterface metadata=new android.media.ExifInterface(fixtureFile.getPath());
        metadata.setAttribute("ImageDescription","Palette QA "+UUID.randomUUID());metadata.saveAttributes();
        String fixtureHash=sha(fixtureFile);
        Constructor<?> ctor=loader.loadClass("cc.huevia.album.DownloadedPhoto").getDeclaredConstructor(File.class,String.class);ctor.setAccessible(true);
        Object photo=ctor.newInstance(fixtureFile,"PALETTE_SELECTION.JPG");panel=get(activity,"album");
        ui(()->{set(activity,"albumTab",true);set(activity,"settingsTab",false);call(panel,"openLocalWorkspace",Collections.singletonList(photo),0);});
        until(()->{Object value=get(panel,"filterEditor");return value!=null&&(Boolean)call(value,"isReady")&&fixtureHash.equals(get(value,"sourceSha"));},"main-editor-ready");
        editor=get(panel,"filterEditor");waitEditor();
        String owner=(String)callStatic("cc.huevia.ui.PhotoFilterEditor","accountOwner",activity);
        Object store=loader.loadClass("cc.huevia.album.PhotoEditStore").getConstructor(File.class,String.class).newInstance(activity.getFilesDir(),owner);
        draftFile=new File((File)get(store,"root"),fixtureHash+".draft");
        Object initial=basicSettings();
        ui(()->{set(editor,"adjustments",initial);call(editor,"edited");call(editor,"setAdjustmentMode",true);});waitEditor();
        View entry=find((View)get(editor,"dock"),"editor-palette");
        check("main-palette-entry-present",entry!=null);
        if(entry!=null)ui(()->entry.requestRectangleOnScreen(new Rect(0,0,entry.getWidth(),entry.getHeight()),true));
        int undoBefore=historySize(editor,"undo");
        Bitmap before=(Bitmap)get(editor,"current");String beforePixels=bitmapSha(before);
        String settingsBefore=(String)call(initial,"identity");
        Dialog dialog=showEditorPalette();
        check("main-transaction-initial-settings",initial.equals(settings(dialog)));
        drag(dialog,.5f,.5f,.82f,.25f);
        Object expected=settings(dialog);
        check("main-dialog-not-mutating-live-editor",initial.equals(get(editor,"adjustments")));
        check("main-dialog-no-history-before-apply",historySize(editor,"undo")==undoBefore);
        click(dialog,"palette-cancel");
        awaitDismiss(dialog,"main-cancel-dismissed");
        check("main-cancel-retains-settings",settingsBefore.equals(call(get(editor,"adjustments"),"identity")));
        check("main-cancel-retains-preview",beforePixels.equals(bitmapSha((Bitmap)get(editor,"current"))));
        check("main-cancel-retains-history",historySize(editor,"undo")==undoBefore);

        dialog=showEditorPalette();drag(dialog,.5f,.5f,.82f,.25f);expected=settings(dialog);
        screenshot("04-main-palette-before-apply");
        click(dialog,"palette-apply");waitEditor();
        check("main-apply-persists-palette",expected.equals(get(editor,"adjustments")));
        check("main-apply-one-undo",historySize(editor,"undo")==undoBefore+1);
        check("main-final-preview-changed",!beforePixels.equals(bitmapSha((Bitmap)get(editor,"current"))));
        ui(()->call(editor,"restoreHistory",false));waitEditor();
        check("main-undo-whole-palette-transaction",initial.equals(get(editor,"adjustments")));
        ui(()->call(editor,"restoreHistory",true));waitEditor();
        check("main-redo-whole-palette-transaction",expected.equals(get(editor,"adjustments")));
        drainEditor();
        check("main-draft-created",draftFile.isFile());
        String draftBefore=sha(draftFile);
        dialog=showEditorPalette();click(dialog,"palette-cancel");drainEditor();
        check("cancel-does-not-rewrite-draft",draftBefore.equals(sha(draftFile)));
        zeroStrengthReset(false);
        regionCase();
        check("owned-jpeg-unchanged",fixtureHash.equals(sha(fixtureFile)));
    }

    private void regionCase() throws Exception {
        stage="selected-region-palette-and-clean-final-photo";
        Object region=callStatic("cc.huevia.ncp.AdjustmentRegion","create","调色测试区域");
        Object stroke=loader.loadClass("cc.huevia.ncp.PhotoPortrait$Stroke").getConstructor(double[].class,double.class,double.class,boolean.class)
            .newInstance(new double[]{.3,.5,.7,.5},.085,.5,false);
        region=call(region,"addStroke",stroke);
        Object none=loader.loadClass("cc.huevia.ncp.PhotoLocalEdits").getField("NONE").get(null);
        Object local=call(none,"addRegion",region),global=get(editor,"adjustments");
        String id=(String)get(region,"id");Object selectedRegion=region;
        ui(()->{set(editor,"localEdits",local);set(editor,"selectedRegionId",id);call(editor,"edited");});waitEditor();
        Bitmap baseline=(Bitmap)get(editor,"current");String globalBefore=(String)call(global,"identity");
        int undoBefore=historySize(editor,"undo");
        Dialog dialog=showEditorPalette();
        check("region-dialog-starts-region-settings",get(selectedRegion,"adjustments").equals(settings(dialog)));
        drag(dialog,.5f,.5f,.92f,.15f);
        Object expected=settings(dialog);
        click(dialog,"palette-apply");waitEditor();
        Object applied=call(editor,"activeRegion");
        check("region-palette-applied-to-selected-region",expected.equals(get(applied,"adjustments")));
        check("region-palette-keeps-global-settings",globalBefore.equals(call(get(editor,"adjustments"),"identity")));
        check("region-apply-one-undo",historySize(editor,"undo")==undoBefore+1);
        Bitmap finalPhoto=(Bitmap)get(editor,"current");
        int w=baseline.getWidth(),h=baseline.getHeight();
        check("region-final-preview-same-dimensions",w==finalPhoto.getWidth()&&h==finalPhoto.getHeight());
        int[] original=new int[w*h],result=new int[w*h];baseline.getPixels(original,0,w,0,0,w,h);finalPhoto.getPixels(result,0,w,0,0,w,h);
        int changed=0;long protectedPixels=0;
        double ax=w*.3,bx=w*.7,cy=h*.5,radius=.085*Math.min(w,h)+3;
        for(int y=0;y<h;y++)for(int x=0;x<w;x++){
            int at=y*w+x;double nearest=Math.max(ax,Math.min(bx,x+.5));
            if(Math.hypot(x+.5-nearest,y+.5-cy)>radius){protectedPixels++;if(original[at]!=result[at])throw new AssertionError("Regional palette escaped brush mask at "+x+","+y);}
            if(original[at]!=result[at])changed++;
        }
        check("region-palette-has-visible-selected-effect",changed>100);
        check("region-final-preview-has-no-selection-overlay",call(editor,"preview")==finalPhoto);
        measurements.put(new JSONObject().put("case","native-region-final-image").put("width",w).put("height",h).put("protectedPixels",protectedPixels).put("outsideDifferences",0).put("changedPixels",changed));
        screenshot("05-region-applied-clean-photo");
        ui(()->call(editor,"restoreHistory",false));waitEditor();
        check("region-undo-restores-palette-neutral",get(call(editor,"activeRegion"),"adjustments").equals(get(selectedRegion,"adjustments")));
        check("region-undo-restores-pixels",bitmapSha(baseline).equals(bitmapSha((Bitmap)get(editor,"current"))));
        zeroStrengthReset(true);
    }

    private void zeroStrengthReset(boolean regional) throws Exception {
        String scope=regional?"region":"global";
        Object none=loader.loadClass("cc.huevia.ncp.PhotoAdjustments").getField("NONE").get(null);
        Object palette=loader.loadClass("cc.huevia.ncp.PhotoColorPalette").getConstructor(int.class,int.class,int.class).newInstance(63,-41,0);
        Object stored=call(none,"withPalette",palette);
        ui(()->{call(editor,"setEditingAdjustments",stored);call(editor,"edited");});waitEditor();
        check(scope+"-zero-strength-settings-neutral",(Boolean)call(stored,"isNeutral"));
        check(scope+"-zero-strength-coordinates-stored",(Boolean)call(get(stored,"palette"),"hasStoredState"));
        int undo=historySize(editor,"undo");
        ui(()->call(editor,"reset",false));waitEditor();
        Object target=regional?get(call(editor,"activeRegion"),"adjustments"):get(editor,"adjustments");
        check(scope+"-main-reset-clears-zero-strength-coordinates",none.equals(target));
        check(scope+"-main-reset-one-undo",historySize(editor,"undo")==undo+1);
        ui(()->call(editor,"restoreHistory",false));waitEditor();
        Object restored=regional?get(call(editor,"activeRegion"),"adjustments"):get(editor,"adjustments");
        check(scope+"-main-reset-undo-restores-zero-strength-coordinates",stored.equals(restored));
    }

    private Object basicSettings() throws Exception {
        Object none=loader.loadClass("cc.huevia.ncp.PhotoAdjustments").getField("NONE").get(null);
        Class<?> parameter=loader.loadClass("cc.huevia.ncp.PhotoAdjustments$Parameter");
        Object contrast=Enum.valueOf((Class)parameter,"CONTRAST"),temperature=Enum.valueOf((Class)parameter,"TEMPERATURE");
        return call(call(none,"with",contrast,17),"with",temperature,-12);
    }
    private boolean sameBasic(Object a,Object b) throws Exception {return Arrays.equals((int[])call(a,"values"),(int[])call(b,"values"))&&get(a,"curves").equals(get(b,"curves"))&&get(a,"hsl").equals(get(b,"hsl"));}
    private Dialog open(Object initial,AtomicReference<Object> committed,AtomicInteger renderCalls) throws Exception {
        Class<?> type=loader.loadClass("cc.huevia.ui.PhotoPaletteDialog"),settingsType=loader.loadClass("cc.huevia.ncp.PhotoAdjustments");
        Class<?> renderer=loader.loadClass("cc.huevia.ui.PhotoPaletteDialog$Renderer");
        Bitmap initialPhoto=render(initial,false);owned.add(initialPhoto);
        Object worker=Proxy.newProxyInstance(loader,new Class<?>[]{renderer},(proxy,method,values)->{
            if(method.getName().equals("render")){renderCalls.incrementAndGet();return render(values[0],(Boolean)values[1]);}
            if(method.getName().equals("toString"))return "NativePaletteRenderer";
            if(method.getName().equals("hashCode"))return System.identityHashCode(proxy);
            if(method.getName().equals("equals"))return proxy==values[0];
            return null;
        });
        Dialog[] result={null};ui(()->{result[0]=(Dialog)type.getConstructor(Activity.class,Bitmap.class,settingsType,String.class,renderer,Consumer.class)
            .newInstance(activity,initialPhoto,initial,"全图",worker,(Consumer<Object>)committed::set);dialogs.add(result[0]);result[0].show();});
        until(()->tag(result[0],"palette-pad").getWidth()>0&&((RectF)get(tag(result[0],"palette-pad"),"frame")).width()>0,"palette-pad-ready");
        return result[0];
    }
    private Bitmap render(Object settings,boolean fast) throws Exception {
        Bitmap base=fast?Bitmap.createScaledBitmap(source,480,360,true):source;
        try {Object profile=callStatic("cc.huevia.ncp.AdjustedPreviewProfile","of",null,settings);return (Bitmap)callStatic("cc.huevia.ui.PhotoFilterEditor","render",base,profile);}
        finally {if(base!=source)base.recycle();}
    }
    private Dialog showEditorPalette() throws Exception {
        View entry=find((View)get(editor,"dock"),"editor-palette");
        if(entry==null)throw new AssertionError("Missing main tool entry");
        ui(()->entry.requestRectangleOnScreen(new Rect(0,0,entry.getWidth(),entry.getHeight()),true));
        ui(()->{long t=SystemClock.uptimeMillis();touch(entry,t,MotionEvent.ACTION_DOWN,entry.getWidth()/2f,entry.getHeight()/2f);touch(entry,t,MotionEvent.ACTION_UP,entry.getWidth()/2f,entry.getHeight()/2f);});
        until(()->get(editor,"popup") instanceof Dialog&&((Dialog)get(editor,"popup")).isShowing(),"main-palette-shown");
        Dialog dialog=(Dialog)get(editor,"popup");dialogs.add(dialog);
        until(()->tag(dialog,"palette-pad").getWidth()>0&&((RectF)get(tag(dialog,"palette-pad"),"frame")).width()>0,"main-pad-ready");return dialog;
    }
    private Object settings(Dialog d) throws Exception {return call(d,"settings");}
    private void drag(Dialog d,float sx,float sy,float ex,float ey) throws Exception {
        long down=SystemClock.uptimeMillis();padTouch(d,down,MotionEvent.ACTION_DOWN,sx,sy);
        for(int n=1;n<=6;n++)padTouch(d,down,MotionEvent.ACTION_MOVE,sx+(ex-sx)*n/6,sy+(ey-sy)*n/6);
        padTouch(d,down,MotionEvent.ACTION_UP,ex,ey);
        waitPalette(d);
    }
    private void padTouch(Dialog d,long down,int action,float nx,float ny) throws Exception {
        ui(()->{View p=tag(d,"palette-pad");RectF frame=(RectF)get(p,"frame");touch(p,down,action,frame.left+frame.width()*nx,frame.top+frame.height()*ny);});
    }
    private void touch(View view,long down,int action,float x,float y) {MotionEvent e=MotionEvent.obtain(down,SystemClock.uptimeMillis(),action,x,y,0);try{view.dispatchTouchEvent(e);}finally{e.recycle();}}
    private void setSeekByTouch(SeekBar seek,double fraction) throws Exception {ui(()->{float x=(float)(seek.getPaddingLeft()+(seek.getWidth()-seek.getPaddingLeft()-seek.getPaddingRight())*fraction);long t=SystemClock.uptimeMillis();touch(seek,t,MotionEvent.ACTION_DOWN,x,seek.getHeight()/2f);touch(seek,t,MotionEvent.ACTION_UP,x,seek.getHeight()/2f);});}
    private void click(Dialog dialog,String tag) throws Exception {if("palette-apply".equals(tag))waitPalette(dialog);ui(()->{View view=tag(dialog,tag);if(!view.isEnabled())throw new AssertionError("Click disabled "+tag);if(!view.performClick())throw new AssertionError("Click not handled "+tag);});}
    private void awaitDismiss(Dialog dialog,String label) throws Exception {until(()->!dialog.isShowing(),label);}
    private Dialog getTopExact() throws Exception {for(Dialog d:dialogs){try{Object value=get(d,"exactDialog");if(value instanceof Dialog&&((Dialog)value).isShowing())return (Dialog)value;}catch(NoSuchFieldException ignored){}}return null;}
    private void bounds(Dialog d,View pad,View photo) throws Exception {
        Rect content=new Rect(),padBounds=new Rect(),photoBounds=new Rect();
        ui(()->{d.getWindow().getDecorView().getGlobalVisibleRect(content);pad.getGlobalVisibleRect(padBounds);photo.getGlobalVisibleRect(photoBounds);});
        float density=activity.getResources().getDisplayMetrics().density;
        check("pad-inside-window",content.contains(padBounds));check("photo-visible",photoBounds.width()>48*density&&photoBounds.height()>48*density);
        check("pad-reaches-useful-touch-size",padBounds.width()>=140*density&&padBounds.height()>=96*density);
        for(String name:new String[]{"palette-apply","palette-cancel","palette-reset","palette-undo","palette-redo"}){View view=tag(d,name);Rect r=new Rect();ui(()->view.getGlobalVisibleRect(r));check(name+"-visible",r.width()>0&&r.height()>0);check(name+"-touch-48dp",view.getWidth()>=48*density-.5&&view.getHeight()>=48*density-.5);}
        measurements.put(new JSONObject().put("case","native-layout").put("window",content.toShortString()).put("pad",padBounds.toShortString()).put("photo",photoBounds.toShortString()).put("fontScale",activity.getResources().getConfiguration().fontScale));
    }
    private void waitEditor() throws Exception {until(()->{ThreadPoolExecutor p=(ThreadPoolExecutor)get(editor,"previews");return (Boolean)call(get(editor,"previewQueue"),"isIdle")&&p.getActiveCount()==0&&p.getQueue().isEmpty();},"main-preview-idle");ui(()->{});}
    private void waitPalette(Dialog d) throws Exception {until(()->{ThreadPoolExecutor p=(ThreadPoolExecutor)get(d,"worker");return (Boolean)call(get(d,"previewQueue"),"isIdle")&&p.getActiveCount()==0&&p.getQueue().isEmpty();},"palette-preview-idle");ui(()->{});}
    private void drainEditor() throws Exception {if(editor==null)return;CountDownLatch done=new CountDownLatch(1);ui(()->call(editor,"afterPendingSaves",(Runnable)done::countDown));check("main-saves-drained",done.await(12,TimeUnit.SECONDS));}
    private void cleanupEditor() throws Exception {if(editor!=null){drainEditor();ui(()->call(editor,"unbind"));drainEditor();}if(draftFile!=null)Files.deleteIfExists(draftFile.toPath());if(fixtureFile!=null)Files.deleteIfExists(fixtureFile.toPath());fixtureRemoved=(draftFile==null||!draftFile.exists())&&(fixtureFile==null||!fixtureFile.exists());if(!fixtureRemoved)throw new AssertionError("Owned126 fixture/draft remains");}
    private int integer(Object o,String field) throws Exception {return ((Number)get(o,field)).intValue();}
    private int historySize(Object o,String field) throws Exception {return ((Collection<?>)get(o,field)).size();}
    private View tag(Dialog d,String value) {View v=find(d.getWindow().getDecorView(),value);if(v==null)throw new AssertionError("Missing tag "+value);return v;}
    private View find(View v,String value) {if(value.equals(v.getTag()))return v;if(v instanceof ViewGroup){ViewGroup group=(ViewGroup)v;for(int i=0;i<group.getChildCount();i++){View match=find(group.getChildAt(i),value);if(match!=null)return match;}}return null;}
    private void screenshot(String name) throws Exception {if("font1.3".equals(args.getString("mode")))return;Bitmap b=getUiAutomation().takeScreenshot();try(OutputStream out=new FileOutputStream(new File(output,name+".png"))){b.compress(Bitmap.CompressFormat.PNG,100,out);screenshots++;}finally{b.recycle();}}
    private void ui(Work work) throws Exception {AtomicReference<Throwable> error=new AtomicReference<>();runOnMainSync(()->{try{work.run();}catch(Throwable e){error.set(e);}});if(error.get()!=null)throw new RuntimeException(error.get());}
    private void until(Condition c,String label) throws Exception {long end=SystemClock.uptimeMillis()+12000;while(SystemClock.uptimeMillis()<end){if(c.test())return;SystemClock.sleep(10);}throw new AssertionError("Timeout "+label);}
    private void check(String label,boolean pass) throws Exception {checks.put(new JSONObject().put("name",label).put("pass",pass));if(!pass)throw new AssertionError(label);}
    private Object get(Object o,String name) throws Exception {for(Class<?> c=o.getClass();c!=null;c=c.getSuperclass())try{Field f=c.getDeclaredField(name);f.setAccessible(true);return f.get(o);}catch(NoSuchFieldException ignored){}throw new NoSuchFieldException(name);}
    private void set(Object o,String name,Object value) throws Exception {for(Class<?> c=o.getClass();c!=null;c=c.getSuperclass())try{Field f=c.getDeclaredField(name);f.setAccessible(true);f.set(o,value);return;}catch(NoSuchFieldException ignored){}throw new NoSuchFieldException(name);}
    private Object call(Object o,String name,Object...arguments) throws Exception {for(Class<?> c=o.getClass();c!=null;c=c.getSuperclass())for(Method m:c.getDeclaredMethods())if(m.getName().equals(name)&&m.getParameterCount()==arguments.length){m.setAccessible(true);try{return m.invoke(o,arguments);}catch(IllegalArgumentException ignored){}}throw new NoSuchMethodException(name);}
    private Object callStatic(String type,String name,Object...arguments) throws Exception {for(Method m:loader.loadClass(type).getDeclaredMethods())if(m.getName().equals(name)&&m.getParameterCount()==arguments.length){m.setAccessible(true);try{return m.invoke(null,arguments);}catch(IllegalArgumentException ignored){}}throw new NoSuchMethodException(type+"."+name);}
    private String sha(File f) throws Exception {return hex(MessageDigest.getInstance("SHA-256").digest(Files.readAllBytes(f.toPath())));}
    private String bitmapSha(Bitmap b) throws Exception {int[] p=new int[b.getWidth()*b.getHeight()];b.getPixels(p,0,b.getWidth(),0,0,b.getWidth(),b.getHeight());MessageDigest d=MessageDigest.getInstance("SHA-256");for(int v:p){d.update((byte)(v>>>24));d.update((byte)(v>>>16));d.update((byte)(v>>>8));d.update((byte)v);}return hex(d.digest());}
    private String hex(byte[] bytes) {StringBuilder s=new StringBuilder();for(byte b:bytes)s.append(String.format(Locale.ROOT,"%02x",b&255));return s.toString();}
    private Throwable unwrap(Throwable e) {while(e.getCause()!=null)e=e.getCause();return e;}
}
