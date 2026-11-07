package cc.huevia.cleanupqa;

import android.app.*;
import android.animation.Animator;
import android.animation.ValueAnimator;
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
public final class CleanupProbe extends Instrumentation {
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
    private final List<File> fixtureFiles=new ArrayList<>(), draftFiles=new ArrayList<>();
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
            output=new File(getTargetContext().getExternalFilesDir(null),"cleanup127/"+run);
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
            if("animations-off".equals(args.getString("mode")))paletteV2DisabledCase();
            else {paletteV2Case();cleanupCase();}
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
                .put("persistentFixturesCreated",!fixtureFiles.isEmpty()).put("ownedFixtureCount",fixtureFiles.size()).put("ownedDraftCount",draftFiles.size()).put("privateFixtureRemoved",fixtureRemoved);
            if(failure!=null)report.put("failure",failure.toString()).put("stack",android.util.Log.getStackTraceString(failure));
            if(output!=null)Files.write(new File(output,"report.json").toPath(),report.toString(2).getBytes(StandardCharsets.UTF_8));
            result.putString("stream",(failure==null?"PASS":"FAIL")+" "+checks.length()+" checks "+stage+" "+(failure==null?"":failure));
        } catch(Throwable error) {result.putString("stream","FAIL report "+error);}
        finish(failure==null?Activity.RESULT_OK:Activity.RESULT_CANCELED,result);
    }









    private Object basicSettings() throws Exception {
        Object none=loader.loadClass("cc.huevia.ncp.PhotoAdjustments").getField("NONE").get(null);
        Class<?> parameter=loader.loadClass("cc.huevia.ncp.PhotoAdjustments$Parameter");
        Object contrast=Enum.valueOf((Class)parameter,"CONTRAST"),temperature=Enum.valueOf((Class)parameter,"TEMPERATURE");
        return call(call(none,"with",contrast,17),"with",temperature,-12);
    }
    private void paletteV2Case() throws Exception {
        stage="palette-v2-square-and-pressed-light";
        Object initial=basicSettings();AtomicReference<Object> committed=new AtomicReference<>();
        Dialog dialog=open(initial,committed,new AtomicInteger());View pad=tag(dialog,"palette-pad"),photo=tag(dialog,"palette-photo");
        bounds(dialog,pad,photo);RectF frame=new RectF((RectF)get(pad,"frame"));
        double aspect=frame.width()/frame.height();check("palette-v2-near-square-field",aspect>=1/1.18&&aspect<=1.18);
        screenshot("01-palette-v2-layout");
        String basePhoto=bitmapSha((Bitmap)get(photo,"photo"));Bitmap idle=padBitmap(dialog);
        long down=SystemClock.uptimeMillis();padTouch(dialog,down,MotionEvent.ACTION_DOWN,.5f,.5f);
        until(()->decimal(pad,"pressProgress")>.55,"palette-v2-pressed-light-visible");
        Bitmap pressed=padBitmap(dialog);int changed=0;long protectedPixels=0;
        for(int y=0;y<idle.getHeight();y++)for(int x=0;x<idle.getWidth();x++){
            int a=idle.getPixel(x,y),b=pressed.getPixel(x,y);if(a!=b)changed++;
            if(!frame.contains(x+.5f,y+.5f)){protectedPixels++;if(a!=b)throw new AssertionError("Pressed optical effect escaped palette field");}
        }
        check("palette-v2-press-has-visible-optical-feedback",changed>80);
        check("palette-v2-press-does-not-alter-photo",basePhoto.equals(bitmapSha((Bitmap)get(photo,"photo"))));
        writePad("02-palette-v2-idle-field",idle);writePad("03-palette-v2-pressed-field",pressed);idle.recycle();pressed.recycle();
        padTouch(dialog,down,MotionEvent.ACTION_MOVE,.78f,.25f);
        check("palette-v2-cross-slop-enters-direct-drag",(Boolean)get(pad,"directDrag"));
        checkMarker(dialog,"palette-v2-drag-follows-pointer-without-delay");
        check("palette-v2-drag-has-no-marker-animation",!animating(pad,"markerAnimator"));
        padTouch(dialog,down,MotionEvent.ACTION_UP,.78f,.25f);waitPalette(dialog);waitMarker(dialog);
        until(()->decimal(pad,"pressProgress")==0,"palette-v2-release-light-hidden");
        checkMarker(dialog,"palette-v2-release-keeps-exact-position");
        Bitmap released=padBitmap(dialog);writePad("04-palette-v2-released-field",released);released.recycle();
        measurements.put(new JSONObject().put("case","palette-v2-press-field-only").put("aspect",aspect).put("outsideProtectedPixels",protectedPixels).put("outsideDifferences",0).put("pressedChangedPixels",changed));

        stage="palette-v2-distant-tap-versus-drag";
        double oldColor=decimal(pad,"markerColor"),oldTone=decimal(pad,"markerTone");int history=historySize(dialog,"history");
        long tap=SystemClock.uptimeMillis();padTouch(dialog,tap,MotionEvent.ACTION_DOWN,.15f,.85f);padTouch(dialog,tap,MotionEvent.ACTION_UP,.15f,.85f);
        Object selected=get(settings(dialog),"palette");int color=integer(selected,"color"),tone=integer(selected,"tone");
        check("palette-v2-distant-tap-logical-target-immediate",color<=-65&&tone<=-65);
        until(()->between(decimal(pad,"markerColor"),oldColor,color)&&between(decimal(pad,"markerTone"),oldTone,tone),"palette-v2-distant-tap-intermediate");
        check("palette-v2-distant-tap-has-short-movement",between(decimal(pad,"markerColor"),oldColor,color));
        waitMarker(dialog);waitPalette(dialog);checkMarker(dialog,"palette-v2-distant-tap-endpoint-exact");
        check("palette-v2-tap-one-undo",historySize(dialog,"history")==history+1);
        check("palette-v2-other-sliders-unchanged",sameBasic(initial,settings(dialog)));
        SeekBar strength=(SeekBar)tag(dialog,"palette-strength");setSeekByTouch(strength,0);waitPalette(dialog);
        check("palette-v2-zero-strength-retains-target",integer(get(settings(dialog),"palette"),"color")==color&&integer(get(settings(dialog),"palette"),"tone")==tone);
        check("palette-v2-zero-strength-photo-identical",basePhoto.equals(bitmapSha((Bitmap)get(photo,"photo"))));
        ui(dialog::dismiss);check("palette-v2-cancel-not-committed",committed.get()==null);
    }
    private void paletteV2DisabledCase() throws Exception {
        stage="palette-v2-system-animations-disabled";check("system-animations-disabled",!ValueAnimator.areAnimatorsEnabled());
        AtomicReference<Object> committed=new AtomicReference<>();Object initial=basicSettings();Dialog dialog=open(initial,committed,new AtomicInteger());
        View pad=tag(dialog,"palette-pad"),controls=(View)get(dialog,"controlsPanel");
        check("disabled-panel-static",controls.getAlpha()==1&&controls.getTranslationY()==0);
        long down=SystemClock.uptimeMillis();padTouch(dialog,down,MotionEvent.ACTION_DOWN,.85f,.2f);
        checkMarker(dialog,"disabled-distant-tap-immediate-coordinate");
        check("disabled-pressed-light-static",decimal(pad,"pressProgress")==1&&!animating(pad,"pressAnimator"));
        padTouch(dialog,down,MotionEvent.ACTION_MOVE,.65f,.35f);checkMarker(dialog,"disabled-v2-drag-immediate");
        padTouch(dialog,down,MotionEvent.ACTION_CANCEL,.65f,.35f);check("disabled-v2-cancel-restores-start",initial.equals(settings(dialog)));
        checkMarker(dialog,"disabled-v2-cancel-immediate-coordinate");
        drag(dialog,.5f,.5f,.8f,.2f);check("disabled-release-clears-press",decimal(pad,"pressProgress")==0);
        check("disabled-v2-never-creates-marker-animation",!animating(pad,"markerAnimator")&&!animating(pad,"pressAnimator"));
        Object expected=settings(dialog);click(dialog,"palette-apply");awaitDismiss(dialog,"disabled-v2-apply-dismissed");
        check("disabled-v2-apply-correct",expected.equals(committed.get()));
    }
    private void cleanupCase() throws Exception {
        stage="cleanup-real-original-analysis-and-global-image";
        File fixture=writeCleanupFixture("A",false);String originalHash=sha(fixture);
        if("phone".equals(args.getString("mode"))){
            AtomicInteger cancellations=new AtomicInteger();boolean cancelled=false;
            try{callStatic("cc.huevia.album.PhotoCleanupAnalyzer","analyze",fixture,originalHash,null,(java.util.function.BooleanSupplier)()->cancellations.incrementAndGet()>=4);}catch(Throwable error){cancelled=unwrap(error) instanceof InterruptedIOException;}
            check("original-analysis-cooperative-cancel",cancelled&&cancellations.get()>=4);
            check("cancelled-analysis-keeps-original-file",originalHash.equals(sha(fixture)));
            boolean mismatch=false;try{callStatic("cc.huevia.album.PhotoCleanupAnalyzer","analyze",fixture,"0".repeat(64),null,(java.util.function.BooleanSupplier)()->false);}catch(Throwable error){mismatch=unwrap(error) instanceof IOException;}
            check("original-analysis-rejects-wrong-source-sha",mismatch);
            cleanupExifCase();
        }
        openWorkspace(fixture);Object originalSettings=get(editor,"adjustments");
        Bitmap baseline=(Bitmap)get(editor,"current");String baselineHash=bitmapSha(baseline);
        check("cleanup-source-preview-smaller-than-original",baseline.getWidth()<3200&&baseline.getHeight()<2400);
        int undoBefore=historySize(editor,"undo");Dialog dialog=showCleanup();waitCleanup(dialog);
        Object analysis=get(get(settings(dialog),"cleanup"),"analysis");checkAnalysis(analysis,3200,2400,"global");
        check("cleanup-analysis-is-tentative",originalSettings.equals(get(editor,"adjustments"))&&historySize(editor,"undo")==undoBefore);
        cleanupBounds(dialog);screenshot("05-cleanup-default-layout");
        double varianceBefore=noiseVariance(baseline,.08,.12,.42,.34);
        setCleanup(dialog,100,0,100);Bitmap denoised=cleanupPhoto(dialog);
        double varianceAfter=noiseVariance(denoised,.08,.12,.42,.34);
        check("cleanup-native-denoise-reduces-flat-patch-variance",varianceAfter<varianceBefore*.995);
        double contrastBefore=meanLuma(baseline,.62,.15,.9,.4)-meanLuma(baseline,.08,.15,.38,.4);
        setCleanup(dialog,100,100,0);Bitmap dehazed=cleanupPhoto(dialog);
        double contrastAfter=meanLuma(dehazed,.62,.15,.9,.4)-meanLuma(dehazed,.08,.15,.38,.4);
        check("cleanup-native-dehaze-increases-hazy-patch-contrast",contrastAfter>contrastBefore+.5);
        screenshot("06-cleanup-advanced-layout");
        setCleanup(dialog,0,100,100);
        check("cleanup-native-zero-strength-exact-pixels",baselineHash.equals(bitmapSha(cleanupPhoto(dialog))));
        check("cleanup-zero-strength-retains-analysis",get(get(settings(dialog),"cleanup"),"analysis").equals(analysis));
        click(dialog,"cleanup-cancel");awaitDismiss(dialog,"cleanup-cancel-dismissed");
        check("cleanup-cancel-keeps-main-settings",originalSettings.equals(get(editor,"adjustments")));
        check("cleanup-cancel-keeps-main-history",historySize(editor,"undo")==undoBefore);
        check("cleanup-cancel-keeps-main-photo",baselineHash.equals(bitmapSha((Bitmap)get(editor,"current"))));
        dialog=showCleanup();waitCleanup(dialog);setCleanup(dialog,73,65,80);Object expected=settings(dialog);
        click(dialog,"cleanup-apply");waitEditor();
        check("cleanup-apply-exact-settings",expected.equals(get(editor,"adjustments")));
        check("cleanup-apply-one-main-undo",historySize(editor,"undo")==undoBefore+1);
        check("cleanup-apply-changes-visible-photo",!baselineHash.equals(bitmapSha((Bitmap)get(editor,"current"))));
        drainEditor();check("cleanup-draft-written",draftFile.isFile());
        Object stored=readDraft();check("cleanup-draft-restores-model-and-analysis",expected.equals(get(stored,"adjustments")));
        String draftBefore=sha(draftFile);dialog=showCleanup();waitCleanup(dialog);setCleanup(dialog,0,20,20);click(dialog,"cleanup-cancel");drainEditor();
        check("cleanup-cancel-does-not-rewrite-draft",draftBefore.equals(sha(draftFile)));
        ui(()->call(editor,"restoreHistory",false));waitEditor();
        check("cleanup-main-undo-restores-settings",originalSettings.equals(get(editor,"adjustments")));
        check("cleanup-main-undo-restores-pixels",baselineHash.equals(bitmapSha((Bitmap)get(editor,"current"))));
        ui(()->call(editor,"restoreHistory",true));waitEditor();check("cleanup-main-redo-restores-effect",expected.equals(get(editor,"adjustments")));
        measurements.put(new JSONObject().put("case","cleanup-native-image-quality").put("previewWidth",baseline.getWidth()).put("previewHeight",baseline.getHeight()).put("originalWidth",3200).put("originalHeight",2400).put("flatVarianceBefore",varianceBefore).put("flatVarianceDenoised",varianceAfter).put("hazyContrastBefore",contrastBefore).put("hazyContrastAfter",contrastAfter).put("zeroStrengthDifferences",0));
        cleanupRegionCase();
        if("phone".equals(args.getString("mode")))cleanupRebindCase();
        check("cleanup-original-jpeg-unchanged",originalHash.equals(sha(fixture)));
    }
    private void cleanupRegionCase() throws Exception {
        stage="cleanup-brush-region-outside-pixels-and-draft";
        Object region=callStatic("cc.huevia.ncp.AdjustmentRegion","create","去灰测试区域");
        Object stroke=loader.loadClass("cc.huevia.ncp.PhotoPortrait$Stroke").getConstructor(double[].class,double.class,double.class,boolean.class).newInstance(new double[]{.3,.5,.7,.5},.085,.5,false);
        region=call(region,"addStroke",stroke);Object originalRegion=region;
        Object none=loader.loadClass("cc.huevia.ncp.PhotoLocalEdits").getField("NONE").get(null),local=call(none,"addRegion",region);String id=(String)get(region,"id");
        ui(()->{set(editor,"localEdits",local);set(editor,"selectedRegionId",id);call(editor,"edited");});waitEditor();
        Object global=get(editor,"adjustments");Bitmap before=(Bitmap)get(editor,"current");String beforeHash=bitmapSha(before);int history=historySize(editor,"undo");
        Dialog dialog=showCleanup();waitCleanup(dialog);checkAnalysis(get(get(settings(dialog),"cleanup"),"analysis"),3200,2400,"region");
        setCleanup(dialog,84,100,100);Object expected=settings(dialog);click(dialog,"cleanup-apply");waitEditor();
        Object applied=call(editor,"activeRegion");
        check("cleanup-regional-apply-only-selected-settings",expected.equals(get(applied,"adjustments"))&&global.equals(get(editor,"adjustments")));
        check("cleanup-regional-apply-one-main-undo",historySize(editor,"undo")==history+1);
        Bitmap after=(Bitmap)get(editor,"current");int w=before.getWidth(),h=before.getHeight();check("cleanup-region-preview-dimensions-stable",w==after.getWidth()&&h==after.getHeight());
        int[] previousPixels=new int[w*h],nextPixels=new int[w*h];before.getPixels(previousPixels,0,w,0,0,w,h);after.getPixels(nextPixels,0,w,0,0,w,h);
        long protectedPixels=0;int changed=0;double ax=w*.3,bx=w*.7,cy=h*.5,radius=.085*Math.min(w,h)+3;
        for(int y=0;y<h;y++)for(int x=0;x<w;x++){int a=previousPixels[y*w+x],b=nextPixels[y*w+x];double nearest=Math.max(ax,Math.min(bx,x+.5));if(Math.hypot(x+.5-nearest,y+.5-cy)>radius){protectedPixels++;if(a!=b)throw new AssertionError("Cleanup escaped region at "+x+","+y);}if(a!=b)changed++;}
        check("cleanup-region-has-visible-selected-effect",changed>100);check("cleanup-region-no-selection-overlay-in-photo",call(editor,"preview")==after);
        drainEditor();Object saved=readDraft();Object savedLocal=get(saved,"localEdits");Object savedRegion=((List<?>)call(savedLocal,"regions")).get(0);
        check("cleanup-region-draft-restores-settings-and-analysis",expected.equals(get(savedRegion,"adjustments")));
        screenshot("07-cleanup-region-applied-photo");
        ui(()->call(editor,"restoreHistory",false));waitEditor();check("cleanup-region-undo-restores-settings",get(originalRegion,"adjustments").equals(get(call(editor,"activeRegion"),"adjustments")));
        check("cleanup-region-undo-restores-pixels",beforeHash.equals(bitmapSha((Bitmap)get(editor,"current"))));
        measurements.put(new JSONObject().put("case","cleanup-native-region-pixels").put("width",w).put("height",h).put("protectedPixels",protectedPixels).put("outsideDifferences",0).put("changedPixels",changed));
    }
    private void cleanupRebindCase() throws Exception {
        stage="cleanup-cancel-analysis-and-rebind-never-crosses-photo";
        Dialog dialog=showCleanup();waitCleanup(dialog);
        ExecutorService worker=(ExecutorService)get(dialog,"analysisWorker");CountDownLatch entered=new CountDownLatch(1),release=new CountDownLatch(1);
        worker.execute(()->{entered.countDown();try{release.await(8,TimeUnit.SECONDS);}catch(InterruptedException ignored){Thread.currentThread().interrupt();}});
        check("cleanup-analysis-worker-blocked",entered.await(3,TimeUnit.SECONDS));
        try{
            click(dialog,"cleanup-analyze");check("cleanup-explicit-reanalysis-pending",(Boolean)get(dialog,"analysisRunning"));
            File replacement=writeCleanupFixture("B",true);String hash=sha(replacement);openWorkspace(replacement);
            check("cleanup-old-dialog-disposed-on-rebind",(Boolean)get(dialog,"disposed"));
            release.countDown();SystemClock.sleep(220);ui(()->{});
            check("cleanup-rebind-source-identity-current",hash.equals(get(editor,"sourceSha")));
            Object clean=loader.loadClass("cc.huevia.ncp.PhotoCleanup").getField("NONE").get(null);
            check("cleanup-old-analysis-does-not-alter-new-photo",clean.equals(get(get(editor,"adjustments"),"cleanup")));
            check("cleanup-old-analysis-cannot-open-popup",get(editor,"popup")==null);
        }finally{release.countDown();}
    }
    private void cleanupExifCase() throws Exception {
        stage="cleanup-original-exif6-region-patch-mapping";
        File folder=new File(getTargetContext().getExternalFilesDir(Environment.DIRECTORY_PICTURES),"camera-album");
        File file=new File(folder,"cleanup-qa-"+args.getString("runId")+"-EXIF6.JPG");check("owned-exif-fixture-not-existing",!file.exists());fixtureFiles.add(file);
        Bitmap bitmap=Bitmap.createBitmap(800,600,Bitmap.Config.ARGB_8888);int[] row=new int[800];
        try{for(int y=0;y<600;y++){for(int x=0;x<800;x++){long seed=(x/3)*73428767L+(y/3)*91227153L+87137;int noise=x<400?(int)(((seed^(seed>>>13))*1274126177L>>>21)&31)-15:0;int value=(x<400?124:194)+noise;row[x]=0xff000000|(value<<16)|(value<<8)|value;}bitmap.setPixels(row,0,800,0,y,800,1);}try(OutputStream out=new FileOutputStream(file)){bitmap.compress(Bitmap.CompressFormat.JPEG,100,out);}}finally{bitmap.recycle();}
        android.media.ExifInterface metadata=new android.media.ExifInterface(file.getPath());metadata.setAttribute("Orientation","6");metadata.setAttribute("ImageDescription","Owned cleanup EXIF6 QA "+UUID.randomUUID());metadata.saveAttributes();String hash=sha(file);
        Object top=analysisRegion("EXIF上部",.22),bottom=analysisRegion("EXIF下部",.78);
        Object upper=callStatic("cc.huevia.album.PhotoCleanupAnalyzer","analyze",file,hash,top,(java.util.function.BooleanSupplier)()->false);
        Object lower=callStatic("cc.huevia.album.PhotoCleanupAnalyzer","analyze",file,hash,bottom,(java.util.function.BooleanSupplier)()->false);
        checkAnalysis(upper,600,800,"exif6-upper");checkAnalysis(lower,600,800,"exif6-lower");
        double high=decimal(upper,"lumaNoise"),low=decimal(lower,"lumaNoise");
        check("exif6-oriented-mask-selects-raw-left-noise-versus-right-flat",high>low);
        check("exif6-original-file-unchanged",hash.equals(sha(file)));
        measurements.put(new JSONObject().put("case","exif6-original-region-mapping").put("rawWidth",800).put("rawHeight",600).put("orientedWidth",600).put("orientedHeight",800).put("upperRegionLumaNoise",high).put("lowerRegionLumaNoise",low));
    }
    private Object analysisRegion(String label,double y) throws Exception {
        Object region=callStatic("cc.huevia.ncp.AdjustmentRegion","create",label);Object stroke=loader.loadClass("cc.huevia.ncp.PhotoPortrait$Stroke").getConstructor(double[].class,double.class,double.class,boolean.class).newInstance(new double[]{.25,y,.75,y},.16,.2,false);return call(region,"addStroke",stroke);
    }
    private Dialog showCleanup() throws Exception {
        View entry=find((View)get(editor,"dock"),"editor-cleanup");if(entry==null)throw new AssertionError("Missing cleanup entry");
        ui(()->entry.requestRectangleOnScreen(new Rect(0,0,entry.getWidth(),entry.getHeight()),true));
        ui(()->{long t=SystemClock.uptimeMillis();touch(entry,t,MotionEvent.ACTION_DOWN,entry.getWidth()/2f,entry.getHeight()/2f);touch(entry,t,MotionEvent.ACTION_UP,entry.getWidth()/2f,entry.getHeight()/2f);});
        until(()->get(editor,"popup") instanceof Dialog&&((Dialog)get(editor,"popup")).isShowing(),"cleanup-dialog-opened");Dialog dialog=(Dialog)get(editor,"popup");dialogs.add(dialog);
        check("cleanup-workspace-tag",find(dialog.getWindow().getDecorView(),"cleanup-workspace")!=null);return dialog;
    }
    private void waitCleanup(Dialog dialog) throws Exception {untilLong(()->!(Boolean)get(dialog,"analysisRunning")&&(Boolean)get(dialog,"previewReady")&&(Boolean)call(get(dialog,"previewQueue"),"isIdle"),"cleanup-analysis-and-precision-preview-ready");ui(()->{});}
    private Bitmap cleanupPhoto(Dialog dialog) throws Exception{return (Bitmap)get(tag(dialog,"cleanup-photo"),"photo");}
    private void setCleanup(Dialog dialog,int amount,int haze,int noise) throws Exception {
        View advanced=tag(dialog,"cleanup-haze");if(!advanced.isShown())click(dialog,"cleanup-advanced");
        setSeekByTouch((SeekBar)tag(dialog,"cleanup-haze"),haze/100.0);setSeekByTouch((SeekBar)tag(dialog,"cleanup-noise"),noise/100.0);setSeekByTouch((SeekBar)tag(dialog,"cleanup-strength"),amount/100.0);waitCleanup(dialog);
    }
    private void checkAnalysis(Object analysis,int width,int height,String scope) throws Exception {
        check(scope+"-cleanup-analysis-present",analysis!=null);
        check(scope+"-analysis-original-oriented-dimensions",integer(analysis,"sourceWidth")==width&&integer(analysis,"sourceHeight")==height);
        int patches=integer(analysis,"patchCount"),pixels=integer(analysis,"patchPixels"),samples=integer(analysis,"noiseSamples");
        check(scope+"-analysis-real-patches-bounded",patches>0&&patches<=9&&pixels>0&&pixels<=9*96*96);
        check(scope+"-analysis-has-real-flat-noise-samples",samples>0&&samples<=pixels);
        measurements.put(new JSONObject().put("case",scope+"-original-analysis").put("sourceWidth",width).put("sourceHeight",height).put("patchCount",patches).put("patchPixels",pixels).put("noiseSamples",samples).put("hazeConfidence",decimal(analysis,"hazeConfidence")).put("noiseConfidence",decimal(analysis,"noiseConfidence")).put("lumaNoise",decimal(analysis,"lumaNoise")));
    }
    private Object readDraft() throws Exception {String owner=(String)callStatic("cc.huevia.ui.PhotoFilterEditor","accountOwner",activity);Object store=loader.loadClass("cc.huevia.album.PhotoEditStore").getConstructor(File.class,String.class).newInstance(activity.getFilesDir(),owner);return call(store,"read",get(editor,"sourceSha"));}
    private void cleanupBounds(Dialog dialog) throws Exception {
        View photo=tag(dialog,"cleanup-photo");Rect r=new Rect();ui(()->photo.getGlobalVisibleRect(r));float density=activity.getResources().getDisplayMetrics().density;
        check("cleanup-photo-visible",r.width()>100*density&&r.height()>100*density);
        for(String name:new String[]{"cleanup-apply","cleanup-cancel","cleanup-advanced","cleanup-undo","cleanup-redo"}){View v=tag(dialog,name);check(name+"-48dp",v.getWidth()>=48*density-.5&&v.getHeight()>=48*density-.5);}
    }
    private Bitmap padBitmap(Dialog dialog) throws Exception {Bitmap[] result={null};ui(()->{View pad=tag(dialog,"palette-pad");result[0]=Bitmap.createBitmap(pad.getWidth(),pad.getHeight(),Bitmap.Config.ARGB_8888);pad.draw(new Canvas(result[0]));});return result[0];}
    private void writePad(String name,Bitmap bitmap) throws Exception {if(!"phone".equals(args.getString("mode")))return;try(OutputStream out=new FileOutputStream(new File(output,name+".png"))){bitmap.compress(Bitmap.CompressFormat.PNG,100,out);screenshots++;}}
    private File writeCleanupFixture(String suffix,boolean alternate) throws Exception {
        File folder=new File(getTargetContext().getExternalFilesDir(Environment.DIRECTORY_PICTURES),"camera-album");folder.mkdirs();
        File fixture=new File(folder,"cleanup-qa-"+args.getString("runId")+"-"+suffix+".JPG");
        check("owned-fixture-not-existing-"+suffix,!fixture.exists());fixtureFiles.add(fixture);fixtureRemoved=false;
        int w=alternate?2640:3200,h=alternate?1980:2400;
        Bitmap bitmap=Bitmap.createBitmap(w,h,Bitmap.Config.ARGB_8888);int[] row=new int[w];
        try{
            for(int y=0;y<h;y++){
                for(int x=0;x<w;x++){
                    int band=x<w/2?(alternate?72:112):(alternate?180:194);
                    long seed=(x/3)*73428767L+(y/3)*91227153L+38197;
                    int noise=(int)(((seed^(seed>>>13))*1274126177L>>>21)&31)-15;
                    int r=Math.max(0,Math.min(255,band+noise)),g=Math.max(0,Math.min(255,band+noise+3)),b=Math.max(0,Math.min(255,band+noise+5));
                    row[x]=0xff000000|(r<<16)|(g<<8)|b;
                }
                bitmap.setPixels(row,0,w,0,y,w,1);
            }
            try(OutputStream out=new FileOutputStream(fixture)){bitmap.compress(Bitmap.CompressFormat.JPEG,100,out);}
        }finally{bitmap.recycle();}
        android.media.ExifInterface metadata=new android.media.ExifInterface(fixture.getPath());metadata.setAttribute("ImageDescription","Cleanup127 QA "+suffix+" "+UUID.randomUUID());metadata.saveAttributes();
        return fixture;
    }
    private Object photoFor(File fixture) throws Exception {
        Constructor<?> constructor=loader.loadClass("cc.huevia.album.DownloadedPhoto").getDeclaredConstructor(File.class,String.class);constructor.setAccessible(true);
        return constructor.newInstance(fixture,"CLEANUP_"+fixture.getName());
    }
    private void openWorkspace(File fixture) throws Exception {
        String hash=sha(fixture);Object photo=photoFor(fixture);panel=get(activity,"album");
        ui(()->{set(activity,"albumTab",true);set(activity,"settingsTab",false);call(panel,"openLocalWorkspace",Collections.singletonList(photo),0);});
        until(()->{Object value=get(panel,"filterEditor");return value!=null&&(Boolean)call(value,"isReady")&&hash.equals(get(value,"sourceSha"));},"cleanup-owned-editor-ready");
        editor=get(panel,"filterEditor");waitEditor();
        String owner=(String)callStatic("cc.huevia.ui.PhotoFilterEditor","accountOwner",activity);
        Object store=loader.loadClass("cc.huevia.album.PhotoEditStore").getConstructor(File.class,String.class).newInstance(activity.getFilesDir(),owner);
        File draft=new File((File)get(store,"root"),hash+".draft");if(!draftFiles.contains(draft))draftFiles.add(draft);
        draftFile=draft;fixtureFile=fixture;
        ui(()->call(editor,"setAdjustmentMode",true));
    }
    private double noiseVariance(Bitmap bitmap,double x0,double y0,double x1,double y1) {
        int left=(int)(bitmap.getWidth()*x0),top=(int)(bitmap.getHeight()*y0),right=(int)(bitmap.getWidth()*x1),bottom=(int)(bitmap.getHeight()*y1);
        double sum=0,squared=0;int count=0;
        for(int y=top;y<bottom;y++)for(int x=left;x<right;x++){double l=luma(bitmap.getPixel(x,y));sum+=l;squared+=l*l;count++;}
        return squared/count-(sum/count)*(sum/count);
    }
    private double meanLuma(Bitmap bitmap,double x0,double y0,double x1,double y1) {
        int left=(int)(bitmap.getWidth()*x0),top=(int)(bitmap.getHeight()*y0),right=(int)(bitmap.getWidth()*x1),bottom=(int)(bitmap.getHeight()*y1);
        double sum=0;int count=0;for(int y=top;y<bottom;y++)for(int x=left;x<right;x++){sum+=luma(bitmap.getPixel(x,y));count++;}return sum/count;
    }
    private double luma(int pixel){return ((pixel>>>16&255)*54+(pixel>>>8&255)*183+(pixel&255)*19)/256.0;}



    private boolean between(double value,double start,double end){double low=Math.min(start,end),high=Math.max(start,end);return value>low+.001&&value<high-.001;}
    private double decimal(Object value,String field) throws Exception{return ((Number)get(value,field)).doubleValue();}
    private boolean animating(Object value,String field) throws Exception{Object animator=get(value,field);return animator instanceof Animator&&((Animator)animator).isRunning();}
    private void checkMarker(Dialog d,String name) throws Exception {ui(()->{View pad=tag(d,"palette-pad");Object palette=get(settings(d),"palette");check(name,Math.abs(decimal(pad,"markerColor")-integer(palette,"color"))<.001&&Math.abs(decimal(pad,"markerTone")-integer(palette,"tone"))<.001);});}
    private void waitMarker(Dialog d) throws Exception{View pad=tag(d,"palette-pad");until(()->!animating(pad,"markerAnimator")&&!animating(pad,"pressAnimator"),"marker-animation-finished");ui(()->{});}
    private void capturePad(Dialog d,String name,JSONArray frames) throws Exception {
        ui(()->{View pad=tag(d,"palette-pad");long time=SystemClock.uptimeMillis();frames.put(new JSONObject().put("uptimeMs",time).put("markerColor",decimal(pad,"markerColor")).put("markerTone",decimal(pad,"markerTone")).put("pressProgress",decimal(pad,"pressProgress")));
            if("phone".equals(args.getString("mode"))){Bitmap bitmap=Bitmap.createBitmap(pad.getWidth(),pad.getHeight(),Bitmap.Config.ARGB_8888);try(OutputStream out=new FileOutputStream(new File(output,name+".png"))){pad.draw(new Canvas(bitmap));bitmap.compress(Bitmap.CompressFormat.PNG,100,out);screenshots++;}finally{bitmap.recycle();}}
        });
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
    private void click(Dialog dialog,String tag) throws Exception {if("palette-apply".equals(tag))waitPalette(dialog);if("cleanup-apply".equals(tag))waitCleanup(dialog);ui(()->{View view=tag(dialog,tag);if(!view.isEnabled())throw new AssertionError("Click disabled "+tag);if(!view.performClick())throw new AssertionError("Click not handled "+tag);});}
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
    private void cleanupEditor() throws Exception {if(editor!=null){drainEditor();ui(()->call(editor,"unbind"));drainEditor();}for(File draft:draftFiles)Files.deleteIfExists(draft.toPath());for(File fixture:fixtureFiles)Files.deleteIfExists(fixture.toPath());fixtureRemoved=true;for(File draft:draftFiles)fixtureRemoved&=!draft.exists();for(File fixture:fixtureFiles)fixtureRemoved&=!fixture.exists();if(!fixtureRemoved)throw new AssertionError("Owned127 fixture/draft remains");}
    private int integer(Object o,String field) throws Exception {return ((Number)get(o,field)).intValue();}
    private int historySize(Object o,String field) throws Exception {return ((Collection<?>)get(o,field)).size();}
    private View tag(Dialog d,String value) {View v=find(d.getWindow().getDecorView(),value);if(v==null)throw new AssertionError("Missing tag "+value);return v;}
    private View find(View v,String value) {if(value.equals(v.getTag()))return v;if(v instanceof ViewGroup){ViewGroup group=(ViewGroup)v;for(int i=0;i<group.getChildCount();i++){View match=find(group.getChildAt(i),value);if(match!=null)return match;}}return null;}
    private void screenshot(String name) throws Exception {if("font1.3".equals(args.getString("mode"))||"animations-off".equals(args.getString("mode")))return;Bitmap b=getUiAutomation().takeScreenshot();try(OutputStream out=new FileOutputStream(new File(output,name+".png"))){b.compress(Bitmap.CompressFormat.PNG,100,out);screenshots++;}finally{b.recycle();}}
    private void ui(Work work) throws Exception {AtomicReference<Throwable> error=new AtomicReference<>();runOnMainSync(()->{try{work.run();}catch(Throwable e){error.set(e);}});if(error.get()!=null)throw new RuntimeException(error.get());}
    private void until(Condition c,String label) throws Exception {long end=SystemClock.uptimeMillis()+12000;while(SystemClock.uptimeMillis()<end){if(c.test())return;SystemClock.sleep(10);}throw new AssertionError("Timeout "+label);}
    private void untilLong(Condition c,String label) throws Exception {long end=SystemClock.uptimeMillis()+45000;while(SystemClock.uptimeMillis()<end){if(c.test())return;SystemClock.sleep(20);}throw new AssertionError("Timeout "+label);}
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
