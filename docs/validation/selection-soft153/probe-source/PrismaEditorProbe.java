package cc.huevia.prismaqa;
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
import java.util.function.BooleanSupplier;
import org.json.*;

/** Installed production code only; Approved project photograph fixture is confined to this test APK. */
public final class PrismaEditorProbe extends Instrumentation {
    private Activity activity;private ClassLoader loader;private Bundle args;private File output,fixture,draftFile;private String sourceSha,stage="start";private Object editor,panel;private Dialog parent;private Throwable failure;private int screenshots;
    private List<?> syntheticBlemishes;
    private int fixtureNumber;private boolean retainRestartFixture;private JSONObject restartRecord;private final List<android.net.Uri> ownedMedia=new ArrayList<>();
    private final List<File> extraFiles=new ArrayList<>(),extraDrafts=new ArrayList<>();
    private final JSONObject layoutReport=new JSONObject();
    private final JSONArray checks=new JSONArray();private final List<Dialog> dialogs=new ArrayList<>();
    private interface Work{void run()throws Exception;}private interface Condition{boolean test()throws Exception;}
    @Override public void onCreate(Bundle b){args=b;start();}
    @Override public void onStart(){
        try{
            loader=getTargetContext().getClassLoader();check("owned-emulator",Build.HARDWARE.equals("ranchu")||Build.HARDWARE.equals("goldfish"));check("exact-installed-candidate",sha(new File(getTargetContext().getApplicationInfo().sourceDir)).equals(args.getString("candidateSha256")));
            String run=args.getString("runId");check("safe-run-id",run!=null&&run.matches("[a-zA-Z0-9.-]+"));output=new File(getTargetContext().getExternalFilesDir(null),"prisma-editor151/"+run);output.getParentFile().mkdirs();check("new-evidence-directory",output.mkdir());
            activity=startActivitySync(new Intent().setClassName("cc.huevia","cc.huevia.MainActivity").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));until(()->(Boolean)get(activity,"ready"),"ready");boolean land=args.getString("mode").contains("landscape");ui(()->activity.setRequestedOrientation(land?ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE:ActivityInfo.SCREEN_ORIENTATION_PORTRAIT));until(()->activity.getResources().getConfiguration().orientation==(land?2:1),"orientation");
            if("verify".equals(args.getString("restartPhase"))){restartRecord=new JSONObject(Files.readString(restartFile().toPath()));fixture=new File(restartRecord.getString("fixture"));File ownedRoot=new File(getTargetContext().getExternalFilesDir(Environment.DIRECTORY_PICTURES),"camera-album").getCanonicalFile();check("owned-restart-fixture",fixture.getCanonicalFile().getParentFile().equals(ownedRoot)&&fixture.getName().startsWith("prisma151-"));}else fixture=fixture();sourceSha=sha(fixture);panel=get(activity,"album");Object photo=photo();ui(()->{set(activity,"albumTab",true);set(activity,"settingsTab",false);call(panel,"openLocalWorkspace",Collections.singletonList(photo),0);});until(()->get(panel,"filterEditor")!=null&&(Boolean)call(get(panel,"filterEditor"),"isReady")&&sourceSha.equals(get(get(panel,"filterEditor"),"sourceSha")),"editor");editor=get(panel,"filterEditor");waitEditor();
            store();if(args.getString("scope").startsWith("selection-soft153"))selectionStyleFlow();else if("prepare".equals(args.getString("restartPhase")))restartPrepare();else if("verify".equals(args.getString("restartPhase")))restartVerify();else if(args.getString("scope").contains("baseline")){prepareLooks();waitEditor();resumeFlow();}else{chromeFlow();continuityFlow();}

        }catch(Throwable t){failure=unwrap(t);try{screenshot("failure");}catch(Throwable ignored){}}
        finally{
            try{ui(()->{for(Dialog d:dialogs)if(d.isShowing())d.dismiss();});if(editor!=null){drain();ui(()->call(editor,"unbind"));drain();}if(!retainRestartFixture){if(draftFile!=null)Files.deleteIfExists(draftFile.toPath());if(fixture!=null)Files.deleteIfExists(fixture.toPath());}for(android.net.Uri uri:ownedMedia)getTargetContext().getContentResolver().delete(uri,null,null);for(File f:extraFiles)Files.deleteIfExists(f.toPath());for(File f:extraDrafts)Files.deleteIfExists(f.toPath());check(retainRestartFixture?"owned-restart-fixture-retained":"owned-fixture-and-draft-cleaned",retainRestartFixture||(fixture==null||!fixture.exists())&&(draftFile==null||!draftFile.exists()));}catch(Throwable t){if(failure==null)failure=unwrap(t);}
            try{ui(()->{if(activity!=null){activity.setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED);activity.finish();}});}catch(Throwable ignored){}
        }
        Bundle b=new Bundle();try{JSONObject r=new JSONObject().put("pass",failure==null).put("stage",stage).put("candidateSha256",args.getString("candidateSha256")).put("mode",args.getString("mode")).put("scope",args.getString("scope")).put("checks",checks).put("screenshots",screenshots).put("privateFixtureRemoved",fixture==null||!fixture.exists()).put("privateDraftRemoved",draftFile==null||!draftFile.exists()).put("layout",layoutReport);if(failure!=null)r.put("failure",failure.toString()).put("stack",android.util.Log.getStackTraceString(failure));if(output!=null)Files.write(new File(output,"report.json").toPath(),r.toString(2).getBytes(StandardCharsets.UTF_8));b.putString("stream",(failure==null?"PASS":"FAIL")+" "+checks.length()+" checks "+stage+(failure==null?"":" "+failure));}catch(Throwable t){b.putString("stream","FAIL report "+t);}finish(failure==null?Activity.RESULT_OK:Activity.RESULT_CANCELED,b);
    }

    private void selectionStyleFlow()throws Exception{
        stage="selection-filter";prepareLooks();waitEditor();frameFence();screenshot("01-filter-selected");
        ui(()->call(editor,"showAll"));Dialog picker=popup("Dialog");screenshot("02-filter-picker");ui(()->call(editor,"dismissPopup"));
        Object dock=get(editor,"compactDock");ui(()->{call(editor,"chooseQuick",0);call(dock,"choose",0);});waitEditor();frameFence();check("quick-original-selected",((View[])get(dock,"cards"))[0].isSelected());screenshot("03-quick-selected");
        mainClick("editor-primary-7");frameFence();screenshot("04-border-selected");mainClick("editor-primary-2");
        Object portrait=get(get(editor,"localEdits"),"portrait");byte[] coverage=new byte[128*128];Arrays.fill(coverage,(byte)255);Object mask=cls("ncp.PhotoPortrait$BodySkinMask").getConstructor(byte[].class).newInstance((Object)coverage);Object seeded=call(portrait,"withGlobalSkinMask",mask);ui(()->{set(editor,"localEdits",call(get(editor,"localEdits"),"withPortrait",seeded));call(editor,"edited");});waitEditor();
        mainClick("editor-portrait-section-1");Dialog skin=popup("PhotoPortraitDialog");parent=skin;waitPortrait();frameFence();View original=tag(skin,"portrait-tone-preset-0");check("skin-original-selected-and-visible",original.isSelected()&&unclipped(original));screenshot("05-skin-original");
        ui(()->tag(skin,"portrait-tone-preset-1").performClick());waitPortrait();frameFence();check("skin-choice-updates-selected-state",tag(skin,"portrait-tone-preset-1").isSelected()&&!tag(skin,"portrait-tone-preset-0").isSelected());check("skin-choice-visible-and-labelled",unclipped(tag(skin,"portrait-tone-preset-1"))&&tag(skin,"portrait-tone-preset-1").getContentDescription().toString().contains("已选中"));screenshot("06-skin-selected");ui(skin::dismiss);
        check("source-photo-unchanged",sourceSha.equals(sha(fixture)));stage="complete-selection-style";
    }

    private View mainTag(String name){View v=find(activity.getWindow().getDecorView(),name);if(v==null)throw new AssertionError("Missing main "+name);return v;}
    private void mainClick(String name)throws Exception{ui(()->mainTag(name).performClick());}
    private void waitQuick()throws Exception{until(()->!(Boolean)get(editor,"quickBusy"),"quick analysis");waitEditor();}
    private void chromeFlow()throws Exception{
        stage="prototype-filter";prepareLooks();waitEditor();frameFence();
        Object dock=get(editor,"compactDock");View image=(View)get(panel,"viewerImage");
        String[] names={"滤镜","调节","裁切","人像","边框"};int[] ids={1,3,4,2,7};
        for(int i=0;i<ids.length;i++){Button tab=(Button)mainTag("editor-primary-"+ids[i]);check("visible-circle-tool-"+names[i],tab.isShown()&&unclipped(tab)&&tab.getText().toString().equals(names[i])&&tab.getCompoundDrawables()[1]!=null);check("tool-target-"+names[i],tab.getWidth()>=dp(48)&&tab.getHeight()>=dp(48));}
        check("filter-default",((Number)call(dock,"mode")).intValue()==1);
        check("filename-header",((TextView)get(panel,"viewerStatus")).getText().toString().equals("DSC_0728.JPG"));
        check("backdrop-sampled-off-thread",get(panel,"editorBackdrop")!=null&&get(get(panel,"editorBackdrop"),"sample") instanceof Bitmap);
        Bitmap blurred=(Bitmap)get(get(panel,"editorBackdrop"),"sample");check("bounded-backdrop",Math.max(blurred.getWidth(),blurred.getHeight())<=64);
        View navigation=mainTag("editor-primary-navigation"),panels=mainTag("compact-editor-panels");
        Rect navRect=global(navigation),panelRect=global(panels);check("tools-before-workspace",navRect.bottom<=panelRect.top+1);
        for(String tag:new String[]{"editor-top-bar","editor-save","editor-back","editor-photo-stage","editor-primary-navigation","compact-editor-panels"})check("unclipped-"+tag,unclipped(mainTag(tag)));
        check("export-yellow-action",paintedYellow(mainTag("editor-save")));
        LinearLayout strip=(LinearLayout)get(editor,"strip");Rect firstCard=global(strip.getChildAt(0)),secondCard=global(strip.getChildAt(1));check("rendered-filter-gap-14dp",Math.abs(secondCard.left-firstCard.right-dp(14))<=1);check("filter-card-name-unclipped",((ViewGroup)strip.getChildAt(0)).getChildAt(1).getBottom()<=strip.getChildAt(0).getHeight());
        RectF initialPhoto=(RectF)call(image,"visiblePhotoBounds");View workspace=mainTag("prototype-editor-workspace");float density=activity.getResources().getDisplayMetrics().density;layoutReport.put("density",density).put("fontScale",activity.getResources().getConfiguration().fontScale).put("workspaceWidthDp",workspace.getWidth()/density).put("workspaceHeightDp",workspace.getHeight()/density).put("topInsetDp",workspace.getPaddingTop()/density).put("bottomInsetDp",workspace.getPaddingBottom()/density).put("photoWidthDp",initialPhoto.width()/density).put("photoHeightDp",initialPhoto.height()/density).put("panelHeightDp",panels.getHeight()/density).put("primaryHeightDp",navigation.getHeight()/density);
        if("narrow".equals(args.getString("mode")))check("compact-photo-restored",initialPhoto.width()>=workspace.getWidth()*.55f&&initialPhoto.height()>=dp(220));
        screenshot("01-filters");
        SeekBar strength=(SeekBar)get(editor,"slider");setUserProgress(strength,40);waitEditor();check("native-strength-updates-model",((Number)get(editor,"strength")).intValue()==40);
        ui(()->((Button)get(dock,"undo")).performClick());waitEditor();check("undo-restores-strength",((Number)get(editor,"strength")).intValue()==70);
        ui(()->((Button)get(dock,"redo")).performClick());waitEditor();check("redo-restores-strength",((Number)get(editor,"strength")).intValue()==40);
        ui(()->((Button)get(dock,"undo")).performClick());waitEditor();

        stage="prototype-adjust-compare";mainClick("editor-primary-3");frameFence();
        Object parameter=get(editor,"parameter");check("exposure-first",parameter.toString().equals("EXPOSURE"));
        SeekBar exposure=(SeekBar)get(editor,"adjustmentSlider");setUserProgress(exposure,12-((Number)get(parameter,"min")).intValue());waitEditor();
        check("native-exposure-updates-settings",getParameter(get(editor,"adjustments"),"EXPOSURE")==12);
        Button compare=(Button)mainTag("editor-compare-original");until(compare::isEnabled,"comparison ready");
        check("compare-48dp",compare.getWidth()==dp(48)&&compare.getHeight()==dp(48));
        Rect stageRect=global(mainTag("editor-photo-stage")),cmpRect=global(compare);check("compare-top-right",cmpRect.top-stageRect.top<=dp(12)&&stageRect.right-cmpRect.right<=dp(12));
        ui(compare::performClick);check("split-opens",(Boolean)call(image,"isSplitComparison"));
        Bitmap displayed=(Bitmap)get(image,"photo"),current=(Bitmap)get(editor,"current"),reference=(Bitmap)get(editor,"comparisonPreview");
        check("split-keeps-effect-frame",displayed==current);check("comparison-aligned-dimensions",reference.getWidth()==current.getWidth()&&reference.getHeight()==current.getHeight());
        RectF bounds=(RectF)call(image,"visiblePhotoBounds");long down=SystemClock.uptimeMillis();float from=(bounds.left+bounds.width()*.5f)/image.getWidth(),to=(bounds.left+bounds.width()*.27f)/image.getWidth(),cy=bounds.centerY()/image.getHeight();
        ui(()->touch2(image,down,MotionEvent.ACTION_DOWN,from,cy));ui(()->touch2(image,down,MotionEvent.ACTION_MOVE,to,cy));ui(()->touch2(image,down,MotionEvent.ACTION_UP,to,cy));check("split-drag-changes-seam",((Number)call(image,"comparisonFraction")).floatValue()<.35f);
        Bundle progress=new Bundle();progress.putFloat(android.view.accessibility.AccessibilityNodeInfo.ACTION_ARGUMENT_PROGRESS_VALUE,70);ui(()->image.performAccessibilityAction(android.view.accessibility.AccessibilityNodeInfo.AccessibilityAction.ACTION_SET_PROGRESS.getId(),progress));check("split-accessible-progress",Math.abs(((Number)call(image,"comparisonFraction")).floatValue()-.7f)<.001);
        ui(()->image.onKeyDown(KeyEvent.KEYCODE_DPAD_LEFT,new KeyEvent(KeyEvent.ACTION_DOWN,KeyEvent.KEYCODE_DPAD_LEFT)));check("split-keyboard-progress",Math.abs(((Number)call(image,"comparisonFraction")).floatValue()-.65f)<.001);
        progress.putFloat(android.view.accessibility.AccessibilityNodeInfo.ACTION_ARGUMENT_PROGRESS_VALUE,50);ui(()->image.performAccessibilityAction(android.view.accessibility.AccessibilityNodeInfo.AccessibilityAction.ACTION_SET_PROGRESS.getId(),progress));screenshot("02-adjust-compare");
        ui(compare::performClick);check("split-closes",!(Boolean)call(image,"isSplitComparison"));
        ui(()->((Button)get(dock,"undo")).performClick());waitEditor();

        stage="prototype-crop";mainClick("editor-primary-4");frameFence();check("crop-grid-visible",(Boolean)get(image,"cropGridVisible"));screenshot("03-crop");
        mainClick("editor-crop-ratio-1");waitEditor();check("square-crop-live",((Bitmap)get(editor,"current")).getWidth()==((Bitmap)get(editor,"current")).getHeight());
        mainClick("editor-composition-rotate");waitEditor();check("rotate-keeps-square",((Number)get(get(editor,"geometry"),"turns")).intValue()==1&&((Bitmap)get(editor,"current")).getWidth()==((Bitmap)get(editor,"current")).getHeight());
        Bitmap beforeFlip=(Bitmap)get(editor,"current");mainClick("editor-composition-flip");waitEditor();Bitmap afterFlip=(Bitmap)get(editor,"current");check("mirror-state",(Boolean)get(get(editor,"geometry"),"mirrored"));
        boolean reflected=true;for(int i=1;i<=5;i++){int x=beforeFlip.getWidth()*i/6,y=beforeFlip.getHeight()*i/6;int a=beforeFlip.getPixel(beforeFlip.getWidth()-1-x,y),b=afterFlip.getPixel(x,y);if(Math.abs(Color.red(a)-Color.red(b))>3||Math.abs(Color.green(a)-Color.green(b))>3||Math.abs(Color.blue(a)-Color.blue(b))>3)reflected=false;}check("mirror-reverses-real-rendered-pixels",reflected);
        drain();Object stored=call(store(),"read",sourceSha);check("mirror-draft-reload",(Boolean)get(get(stored,"geometry"),"mirrored"));
        ui(()->((Button)get(dock,"undo")).performClick());waitEditor();check("mirror-undo",!(Boolean)get(get(editor,"geometry"),"mirrored"));
        mainClick("editor-composition-reset");waitEditor();check("crop-reset",(Boolean)call(get(editor,"geometry"),"isNeutral"));
        mainClick("editor-primary-1");check("grid-hides-outside-crop",!(Boolean)get(image,"cropGridVisible"));
        stage="existing-features";mainClick("editor-primary-2");check("portrait-entry-preserved",mainTag("editor-portrait-panel").isShown());
        mainClick("editor-primary-7");check("real-border-tools-preserved",mainTag("border-prototype-panel").isShown());mainClick("editor-primary-1");
        ui(()->call(editor,"showAll"));until(()->get(editor,"popup") instanceof Dialog&&((Dialog)get(editor,"popup")).isShowing(),"all-filter-picker");check("preset-picker-preserved",((Dialog)get(editor,"popup")).isShowing());ui(()->call(editor,"dismissPopup"));
        ui(()->((Button)get(panel,"viewerSave")).performClick());until(()->get(editor,"popup") instanceof Dialog&&((Dialog)get(editor,"popup")).isShowing(),"real-export-dialog");check("real-export-dialog-opens",((Dialog)get(editor,"popup")).isShowing());ui(()->call(editor,"dismissPopup"));
        check("source-file-unchanged",sourceSha.equals(sha(fixture)));stage="complete";
    }


    private File restartFile(){return new File(getTargetContext().getExternalFilesDir(null),"prisma-editor151/restart152.json");}
    private String bitmapHash(Bitmap b)throws Exception{java.nio.ByteBuffer bytes=java.nio.ByteBuffer.allocate(b.getByteCount());b.copyPixelsToBuffer(bytes);return hex(MessageDigest.getInstance("SHA-256").digest(bytes.array()));}
    private void restartPrepare()throws Exception{
        stage="process-restart-prepare";prepareLooks();waitEditor();mainClick("editor-primary-3");Object p=get(editor,"parameter");setUserProgress((SeekBar)get(editor,"adjustmentSlider"),12-num(p,"min"));waitEditor();mainClick("editor-primary-4");mainClick("editor-crop-ratio-1");waitEditor();mainClick("editor-composition-flip");waitEditor();
        Object local=get(editor,"localEdits"),portrait=get(local,"portrait"),shape=get(portrait,"bodyShape");Object adjusted=call(shape,"withArea",0,call(call(shape,"area",0),"withAmount",17));Object next=call(local,"withPortrait",call(portrait,"withBodyShape",adjusted));ui(()->{set(editor,"localEdits",next);call(editor,"edited");});waitEditor();drain();Object draft=call(store(),"read",sourceSha);JSONObject record=new JSONObject().put("fixture",fixture.getAbsolutePath()).put("sourceSha",sourceSha).put("identity",call(draft,"identity")).put("pixels",bitmapHash((Bitmap)get(editor,"current")));
        mainClick("editor-back");drain();Files.writeString(restartFile().toPath(),record.toString());retainRestartFixture=true;check("closed-draft-written-before-process-stop",restartFile().isFile());stage="process-restart-prepared";
    }
    private void restartVerify()throws Exception{
        stage="process-restart-verify";AtomicReference<Object> frozen=new AtomicReference<>();ui(()->call(editor,"freeze",(java.util.function.Consumer<Object>)frozen::set));until(()->frozen.get()!=null,"restored frozen draft");Object draft=get(frozen.get(),"draft");check("process-restart-restores-all-setting-identity",draft!=null&&restartRecord.getString("identity").equals(call(draft,"identity")));check("process-restart-restores-exact-preview-pixels",restartRecord.getString("pixels").equals(bitmapHash((Bitmap)get(editor,"current"))));check("process-restart-original-unchanged",sourceSha.equals(restartRecord.getString("sourceSha")));screenshot("restart-restored");Files.deleteIfExists(restartFile().toPath());stage="complete-process-restart";
    }

    private void openInPanel(Object target,Object item)throws Exception{
        panel=target;ui(()->call(panel,"openLocalWorkspace",Collections.singletonList(item),0));
        until(()->get(panel,"filterEditor")!=null&&(Boolean)call(get(panel,"filterEditor"),"isReady")&&sourceSha.equals(get(get(panel,"filterEditor"),"sourceSha")),"resumed editor");editor=get(panel,"filterEditor");waitEditor();
    }
    private void resumeFlow()throws Exception{
        stage="close-reopen-draft";Object expected=call(editor,"snapshot");mainClick("editor-back");
        check("close-returns-to-album",get(panel,"localDetail")==null);openInPanel(panel,photo());
        check("ordinary-open-restores-pending-draft",(Boolean)call(expected,"same",call(editor,"snapshot")));
        ui(()->call(editor,"bindSavedVersion",photo()));until(()->(Boolean)call(editor,"isReady"),"explicit saved version");
        check("explicit-saved-version-still-original",!(Boolean)call(editor,"dirty")&&((String)get(editor,"selected")).isEmpty());
        mainClick("editor-back");openInPanel(panel,photo());check("pending-draft-survives-explicit-version-view",(Boolean)call(expected,"same",call(editor,"snapshot")));
    }
    private Dialog popup(String type)throws Exception{until(()->get(editor,"popup") instanceof Dialog&&get(editor,"popup").getClass().getSimpleName().equals(type)&&((Dialog)get(editor,"popup")).isShowing(),type);Dialog d=(Dialog)get(editor,"popup");dialogs.add(d);return d;}
    private void styledDialog(Dialog d,String rootTag,String applyTag)throws Exception{
        frameFence();View root=tag(d,rootTag);check(rootTag+"-photo-atmosphere",root.getBackground().getClass().getSimpleName().equals("Backdrop"));
        if(applyTag!=null){Button apply=(Button)tag(d,applyTag);check(applyTag+"-yellow-pill",apply.getCurrentTextColor()==0xff191e17&&unclipped(apply));}
    }
    private void continuityFlow()throws Exception{
        stage="visible-more-menu";View more=mainTag("editor-photo-more");check("more-next-to-close-visible",unclipped(more)&&more.getWidth()>=dp(48)&&global(more).left>=global(mainTag("editor-back")).right);
        mainClick("editor-photo-more");until(()->get(panel,"photoActionsPopup") instanceof PopupWindow&&((PopupWindow)get(panel,"photoActionsPopup")).isShowing(),"more menu");
        View menu=((PopupWindow)get(panel,"photoActionsPopup")).getContentView();String menuText=textTree(menu);check("more-preserves-utilities",menuText.contains("照片版本")&&menuText.contains("直方图")&&menuText.contains("复制调色")&&menuText.contains("还原原图")&&menuText.contains("照片配方"));screenshot("04-more-menu");ui(()->call(panel,"dismissPhotoActions"));
        mainClick("editor-primary-2");checkCenteredReset();screenshot("05-portrait-controls");
        // Synthetic selection metadata avoids making an inference accuracy claim in a UI regression.
        Object portrait=get(get(editor,"localEdits"),"portrait"),settings=cls("ncp.PhotoPortrait$Settings").getField("NONE").get(null);Constructor<?> faceCtor=null;for(Constructor<?> c:cls("ncp.PhotoPortrait$Face").getConstructors())if(c.getParameterCount()==11)faceCtor=c;
        Object manualFace=faceCtor.newInstance(.5,.3,.12,.16,0d,190,145,120,true,settings,Collections.emptyList());
        byte[] coverage=new byte[128*128];Arrays.fill(coverage,(byte)255);Object mask=cls("ncp.PhotoPortrait$BodySkinMask").getConstructor(byte[].class).newInstance((Object)coverage);
        Object seeded=call(call(portrait,"addFace",manualFace),"withGlobalSkinMask",mask);ui(()->{set(editor,"localEdits",call(get(editor,"localEdits"),"withPortrait",seeded));call(editor,"edited");});waitEditor();
        stage="skin-style";mainClick("editor-portrait-section-1");Dialog skin=popup("PhotoPortraitDialog");parent=skin;waitPortrait();styledDialog(skin,"photo-portrait-workspace","portrait-apply");screenshot("06-skin");
        ui(()->tag(skin,"portrait-skin-smoothing").performClick());waitPortrait();SeekBar skinSlider=(SeekBar)tag(skin,"portrait-axis-0");setUserProgress(skinSlider,Math.min(skinSlider.getMax(),skinSlider.getProgress()+9));waitPortrait();ui(()->tag(skin,"portrait-apply").performClick());waitEditor();
        stage="face-style";mainClick("editor-portrait-section-2");Dialog face=popup("PhotoPortraitDialog");parent=face;waitPortrait();styledDialog(face,"photo-portrait-workspace","portrait-apply");screenshot("07-face");
        SeekBar faceSlider=(SeekBar)tag(face,"portrait-axis-0");setUserProgress(faceSlider,Math.min(faceSlider.getMax(),faceSlider.getProgress()+7));waitPortrait();ui(()->tag(face,"portrait-apply").performClick());waitEditor();
        stage="body-style";mainClick("editor-portrait-section-3");Dialog body=popup("PhotoBodyDialog");until(()->get(body,"completed")!=null&&(Boolean)call(get(body,"queue"),"isIdle"),"body render");styledDialog(body,"body-workspace","body-apply");concentricBackground(tag(body,"body-cancel"),"rectangular-body-back-target-has-circular-face");
        setUserProgress((SeekBar)tag(body,"body-strength"),17);until(()->get(body,"completed")!=null&&get(body,"completed").equals(get(body,"shape"))&&(Boolean)call(get(body,"queue"),"isIdle"),"changed body render");verifyBodyActions(body);screenshot("08-body");ui(()->tag(body,"body-apply").performClick());waitEditor();check("body-apply-reaches-parent",num(get(get(get(editor,"localEdits"),"portrait"),"bodyShape"),"backgroundProtection")==0&&!((Boolean)call(get(get(get(editor,"localEdits"),"portrait"),"bodyShape"),"isNeutral")));
        resumeFlow();Object expected=call(editor,"snapshot");
        stage="local-album-entry";mainClick("editor-back");ui(()->call(activity,"openLocalPhoto",photo()));panel=get(activity,"localPhotoEditor");until(()->(Boolean)call(get(panel,"filterEditor"),"isReady"),"local album editor");editor=get(panel,"filterEditor");waitEditor();check("app-album-entry-restores-all-edits",(Boolean)call(expected,"same",call(editor,"snapshot")));
        android.content.ContentValues media=new android.content.ContentValues();media.put(android.provider.MediaStore.Images.Media.DISPLAY_NAME,"continuity152-"+UUID.randomUUID()+".JPG");media.put(android.provider.MediaStore.Images.Media.MIME_TYPE,"image/jpeg");media.put(android.provider.MediaStore.Images.Media.RELATIVE_PATH,"Pictures/Huevia-QA152");media.put(android.provider.MediaStore.Images.Media.IS_PENDING,1);android.net.Uri uri=getTargetContext().getContentResolver().insert(android.provider.MediaStore.Images.Media.EXTERNAL_CONTENT_URI,media);check("owned-phone-fixture-inserted",uri!=null);ownedMedia.add(uri);try(OutputStream out=getTargetContext().getContentResolver().openOutputStream(uri)){Files.copy(fixture.toPath(),out);}media.clear();media.put(android.provider.MediaStore.Images.Media.IS_PENDING,0);getTargetContext().getContentResolver().update(uri,media,null,null);
        Object repository=cls("album.LocalPhotoRepository").getConstructor(android.content.Context.class).newInstance(getTargetContext());Object phonePhoto=call(repository,"importPhoto",call(repository,"describe",uri),(BooleanSupplier)()->false);File copy=(File)call(phonePhoto,"file");extraFiles.add(copy);extraFiles.add(new File(getTargetContext().getFilesDir(),"local-photo-sources/"+copy.getName().split("__")[0]+".source"));check("real-phone-import-keeps-original-bytes",sourceSha.equals(sha(copy)));
        mainClick("editor-back");ui(()->call(activity,"openLocalPhoto",phonePhoto));until(()->(Boolean)call(get(panel,"filterEditor"),"isReady")&&copy.equals(get(get(panel,"filterEditor"),"bound").getClass().getMethod("file").invoke(get(get(panel,"filterEditor"),"bound"))),"phone cache entry");editor=get(panel,"filterEditor");waitEditor();check("same-phone-photo-cache-restores-all-edits",(Boolean)call(expected,"same",call(editor,"snapshot")));screenshot("09-resumed-edits");
        // Recreate the entire Activity/editor; state must come from the durable store.
        mainClick("editor-back");drain();Instrumentation.ActivityMonitor monitor=addMonitor("cc.huevia.MainActivity",null,false);ui(activity::recreate);Activity fresh=waitForMonitorWithTimeout(monitor,20000);removeMonitor(monitor);check("activity-recreated",fresh!=null&&fresh!=activity);activity=fresh;until(()->(Boolean)get(activity,"ready"),"fresh activity");ui(()->call(activity,"openLocalPhoto",phonePhoto));panel=get(activity,"localPhotoEditor");until(()->(Boolean)call(get(panel,"filterEditor"),"isReady"),"fresh editor load");editor=get(panel,"filterEditor");waitEditor();check("fresh-editor-restores-all-edits",(Boolean)call(expected,"same",call(editor,"snapshot")));
        similarTools();
        check("original-and-phone-cache-unchanged",sourceSha.equals(sha(fixture))&&sourceSha.equals(sha(copy)));stage="complete-continuity";
    }



    private void waitBody(Dialog d)throws Exception{until(()->get(d,"completed")!=null&&get(d,"completed").equals(get(d,"shape"))&&(Boolean)call(get(d,"queue"),"isIdle"),"body action preview");}
    private void verifyBodyActions(Dialog d)throws Exception{
        frameFence();Button range=(Button)tag(d,"body-range-options"),reset=(Button)tag(d,"body-reset");check("body-five-circle-tool-rail",((ViewGroup)tag(d,"body-primary-tools")).getChildCount()==5);check("body-range-reset-visible-targets",unclipped(range)&&unclipped(reset)&&range.getWidth()>=dp(48)&&reset.getWidth()>=dp(48));
        ui(range::performClick);frameFence();check("body-range-parameters-expand",tag(d,"body-range-panel").isShown());ui(range::performClick);frameFence();check("body-range-parameters-collapse",!tag(d,"body-range-panel").isShown());
        ui(reset::performClick);waitBody(d);check("body-reset-current-amount",num(call(get(d,"shape"),"area",0),"amount")==0);ui(()->tag(d,"body-undo").performClick());waitBody(d);check("body-reset-undo-restores-amount",num(call(get(d,"shape"),"area",0),"amount")==17);
    }

    private void concentricBackground(View view,String name)throws Exception{
        int w=view.getWidth(),h=view.getHeight();Bitmap b=Bitmap.createBitmap(w,h,Bitmap.Config.ARGB_8888);Canvas canvas=new Canvas(b);ui(()->view.getBackground().draw(canvas));Rect bounds=new Rect(w,h,0,0);for(int y=0;y<h;y++)for(int x=0;x<w;x++)if(Color.alpha(b.getPixel(x,y))>16){bounds.left=Math.min(bounds.left,x);bounds.right=Math.max(bounds.right,x+1);bounds.top=Math.min(bounds.top,y);bounds.bottom=Math.max(bounds.bottom,y+1);}b.recycle();check(name,Math.abs(bounds.width()-bounds.height())<=1&&Math.abs(bounds.exactCenterX()-w/2f)<=.5f&&Math.abs(bounds.exactCenterY()-h/2f)<=.5f);
    }

    private void checkCenteredReset()throws Exception{
        Button reset=(Button)mainTag("editor-reset");android.graphics.drawable.LayerDrawable bg=(android.graphics.drawable.LayerDrawable)reset.getBackground();Rect target=bg.getBounds(),glyph=bg.getDrawable(1).getBounds();
        check("reset-glyph-centered-in-target",Math.abs(target.exactCenterX()-glyph.exactCenterX())<=.5f&&Math.abs(target.exactCenterY()-glyph.exactCenterY())<=.5f);
        int width=reset.getWidth(),height=reset.getHeight();for(int[] state:new int[][]{new int[]{android.R.attr.state_enabled},new int[]{android.R.attr.state_enabled,android.R.attr.state_pressed},new int[]{android.R.attr.state_enabled,android.R.attr.state_focused}}){
            android.graphics.drawable.Drawable face=bg.getDrawable(0);ui(()->face.setState(state));Bitmap pixels=Bitmap.createBitmap(width,height,Bitmap.Config.ARGB_8888);Canvas c=new Canvas(pixels);ui(()->face.draw(c));Rect painted=new Rect(width,height,0,0);for(int y=0;y<height;y++)for(int x=0;x<width;x++)if(Color.alpha(pixels.getPixel(x,y))>16){painted.left=Math.min(painted.left,x);painted.right=Math.max(painted.right,x+1);painted.top=Math.min(painted.top,y);painted.bottom=Math.max(painted.bottom,y+1);}pixels.recycle();
            check("reset-circle-concentric-state-"+state[state.length-1],Math.abs(painted.width()-painted.height())<=1&&Math.abs(painted.exactCenterX()-width/2f)<=.5f&&Math.abs(painted.exactCenterY()-height/2f)<=.5f);
        }ui(()->{bg.getDrawable(0).setState(reset.getDrawableState());bg.setState(reset.getDrawableState());reset.refreshDrawableState();});check("reset-state-restored-after-geometry-check",Arrays.equals(bg.getDrawable(0).getState(),reset.getDrawableState()));
    }

    private String textTree(View v){String s=v instanceof TextView?((TextView)v).getText().toString()+"\n":"";if(v instanceof ViewGroup)for(int i=0;i<((ViewGroup)v).getChildCount();i++)s+=textTree(((ViewGroup)v).getChildAt(i));return s;}
    private void similarTools()throws Exception{
        String[][] tools={{"showColor","PhotoColorDialog","photo-colour-workspace","colour-apply","10-curves"},{"showPalette","PhotoPaletteDialog","photo-palette-workspace","palette-apply","11-palette"},{"showCleanup","PhotoCleanupDialog","cleanup-workspace","cleanup-apply","12-cleanup"},{"showComposition","PhotoCropDialog","photo-crop-workspace","crop-apply","13-precision-crop"},{"showLocal","PhotoLocalEditDialog","photo-local-workspace","local-apply","14-local"}};
        for(String[] tool:tools){stage=tool[0];ui(()->{if(tool[0].equals("showColor"))call(editor,tool[0],true);else call(editor,tool[0]);});Dialog d=popup(tool[1]);if(tool[2]!=null)styledDialog(d,tool[2],tool[3]);if(tool[1].equals("PhotoLocalEditDialog")){TextView instructions=(TextView)tag(d,"local-selection");Rect instructionBounds=global(instructions),toolbarBounds=global(tag(d,"local-photo-toolbar"));check("local-instruction-separate-from-actions",unclipped(instructions)&&instructionBounds.bottom<toolbarBounds.top&&instructions.getLayout()!=null&&instructions.getLayout().getEllipsisCount(0)==0);check("local-creation-guidance-preserved",instructions.getText().toString().contains("拖动新建"));}screenshot(tool[4]);ui(d::dismiss);waitEditor();}
    }

    private Rect global(View view){Rect result=new Rect();view.getGlobalVisibleRect(result);return result;}
    private boolean paintedYellow(View view)throws Exception{frameFence();Bitmap b=getUiAutomation().takeScreenshot();try{Rect r=global(view);int count=0;for(int y=1;y<=5;y++)for(int x=1;x<=5;x++){int p=b.getPixel(r.left+r.width()*x/6,r.top+r.height()*y/6);if(Math.abs(Color.red(p)-255)<6&&Math.abs(Color.green(p)-227)<6&&Math.abs(Color.blue(p)-53)<6)count++;}return count>3;}finally{b.recycle();}}
    private void setUserProgress(SeekBar bar,int value)throws Exception{Bundle b=new Bundle();b.putFloat(android.view.accessibility.AccessibilityNodeInfo.ACTION_ARGUMENT_PROGRESS_VALUE,value);ui(()->{if(!bar.performAccessibilityAction(android.view.accessibility.AccessibilityNodeInfo.AccessibilityAction.ACTION_SET_PROGRESS.getId(),b))throw new AssertionError("Native slider accessible input");});}
    @SuppressWarnings({"rawtypes","unchecked"}) private void prepareLooks()throws Exception{
        String[] names={"晴日","旧时光","柔光","森野","银盐"},categories={"人像","胶片","人像","风光","黑白"};List prepared=new ArrayList();Bitmap original=(Bitmap)get(editor,"original");
        Constructor<?> constructor=null;for(Constructor<?> c:cls("library.PresetRecord").getDeclaredConstructors())if(c.getParameterCount()==10)constructor=c;if(constructor==null)throw new NoSuchMethodException("PresetRecord fixture");constructor.setAccessible(true);
        Constructor<?> entryConstructor=loader.loadClass("cc.huevia.ui.PhotoFilterEditor$Entry").getDeclaredConstructor(cls("library.PresetRecord"));entryConstructor.setAccessible(true);
        for(int i=0;i<names.length;i++){byte[] bytes=preset(i);String hash=hex(MessageDigest.getInstance("SHA-256").digest(bytes));Object record=constructor.newInstance(names[i],"QA_"+i+".NCP",hash,"local","","Hand-authored QA preset; not a real camera preset","0100",bytes.length,1L,categories[i]);Object entry=entryConstructor.newInstance(record);Object profile=stat("cc.huevia.ncp.PresetPreviewProfiles","fromPreset",bytes);set(entry,"bytes",bytes);set(entry,"profile",profile);set(entry,"image",stat("cc.huevia.ui.PhotoFilterEditor","renderColour",original,profile));prepared.add(entry);}
        ui(()->{call(editor,"setOnlineSource",false);List entries=(List)get(editor,"entries");entries.clear();entries.addAll(prepared);call(editor,"refresh");call(editor,"choose",prepared.get(0));set(editor,"strength",70);call(editor,"edited");});
    }
    private byte[] preset(int index){byte[] bytes=new byte[638];bytes[0]='N';bytes[1]='C';bytes[2]='P';bytes[7]=1;bytes[11]=36;byte[] version="0100".getBytes(StandardCharsets.US_ASCII);System.arraycopy(version,0,bytes,12,4);byte[] name=("PRISMA QA "+index).getBytes(StandardCharsets.US_ASCII);System.arraycopy(name,0,bytes,16,name.length);bytes[36]=3;bytes[37]=(byte)0xc2;bytes[39]=(byte)0xff;bytes[40]=(byte)0x82;bytes[41]=1;bytes[42]=1;bytes[43]=(byte)(index==0?0x82:index==1?0x7d:0x80);bytes[44]=(byte)(0x80+Math.min(index,3));bytes[45]=bytes[46]=bytes[47]=(byte)0xff;bytes[51]=2;bytes[54]=2;bytes[55]=0x42;bytes[56]=0x49;bytes[57]=0x30;bytes[59]=bytes[61]=(byte)0xff;bytes[62]=1;bytes[64]=2;bytes[67]=bytes[68]=(byte)0xff;for(int i=0;i<=256;i++){int value=Math.min(i*128,32767);bytes[120+2*i]=(byte)(value>>>8);bytes[121+2*i]=(byte)value;}return bytes;}
    private String hex(byte[] bytes){StringBuilder value=new StringBuilder();for(byte b:bytes)value.append(String.format(Locale.ROOT,"%02x",b&255));return value.toString();}

    private int dp(int v){return Math.round(v*activity.getResources().getDisplayMetrics().density);}
    private boolean unclipped(View v){Rect r=new Rect();return v.isShown()&&v.getGlobalVisibleRect(r)&&r.width()>=v.getWidth()-1&&r.height()>=v.getHeight()-1;}
    private void frameFence()throws Exception{CountDownLatch done=new CountDownLatch(1);ui(()->Choreographer.getInstance().postFrameCallback(t->Choreographer.getInstance().postFrameCallback(n->done.countDown())));if(!done.await(4,TimeUnit.SECONDS))throw new AssertionError("UI frame fence");}
    private void input(long down,int action,float x,float y){MotionEvent event=MotionEvent.obtain(down,SystemClock.uptimeMillis(),action,x,y,0);event.setSource(InputDevice.SOURCE_TOUCHSCREEN);getUiAutomation().injectInputEvent(event,true);event.recycle();}
    private Object store()throws Exception{String owner=(String)stat("cc.huevia.ui.PhotoFilterEditor","accountOwner",activity);Object store=cls("album.PhotoEditStore").getConstructor(File.class,String.class).newInstance(activity.getFilesDir(),owner);draftFile=new File((File)get(store,"root"),sourceSha+".draft");return store;}
    private int getParameter(Object retouch,String name)throws Exception{String type=retouch.getClass().getName().endsWith("PhotoAdjustments")?"ncp.PhotoAdjustments$Parameter":"ncp.PortraitRetouch$Parameter";Object p=Enum.valueOf((Class)cls(type),name);return((Number)call(retouch,"get",p)).intValue();}
    private Object face()throws Exception{return call(parent,"face");}
    private void click(String name)throws Exception{ui(()->tag(parent,name).performClick());}
    private void touch2(View v,long down,int action,float x,float y){MotionEvent event=MotionEvent.obtain(down,SystemClock.uptimeMillis(),action,v.getWidth()*x,v.getHeight()*y,0);try{v.dispatchTouchEvent(event);}finally{event.recycle();}}
    private Dialog portrait()throws Exception{ui(()->call(editor,"showPortrait"));until(()->get(editor,"popup") instanceof Dialog&&((Dialog)get(editor,"popup")).isShowing(),"portrait dialog");Dialog d=(Dialog)get(editor,"popup");dialogs.add(d);parent=d;waitPortrait();return d;}
    private void waitPortrait()throws Exception{until(()->get(parent,"completedPreview")!=null&&(Boolean)call(get(parent,"queue"),"isIdle")&&tag(parent,"portrait-apply").isEnabled(),"precision portrait preview");}
    private void waitEditor()throws Exception{until(()->(Boolean)call(get(editor,"previewQueue"),"isIdle"),"main preview");ui(()->{});}
    private void drain()throws Exception{CountDownLatch done=new CountDownLatch(1);ui(()->call(editor,"afterPendingSaves",(Runnable)done::countDown));if(!done.await(12,TimeUnit.SECONDS))throw new AssertionError("draft save drain timeout");}
    private File fixture()throws Exception{Bitmap b;try(InputStream in=getContext().getAssets().open("portrait.jpg")){b=BitmapFactory.decodeStream(in);}File dir=new File(getTargetContext().getExternalFilesDir(Environment.DIRECTORY_PICTURES),"camera-album");dir.mkdirs();File f=new File(dir,"prisma151-"+UUID.randomUUID()+"__DSC_0728.JPG");try(OutputStream out=new FileOutputStream(f)){b.compress(Bitmap.CompressFormat.JPEG,97,out);}finally{b.recycle();}return f;}
    private Object photo()throws Exception{Constructor<?> c=cls("album.DownloadedPhoto").getDeclaredConstructor(File.class,String.class);c.setAccessible(true);return c.newInstance(fixture,"DSC_0728.JPG");}
    private View tag(Dialog d,String name){View v=find(d.getWindow().getDecorView(),name);if(v==null)throw new AssertionError("Missing "+name);return v;}
    private void drag(SeekBar s)throws Exception{long down=SystemClock.uptimeMillis();ui(()->{touch(s,down,MotionEvent.ACTION_DOWN,s.getWidth()*.08f);touch(s,down,MotionEvent.ACTION_MOVE,s.getWidth()*.30f);touch(s,down,MotionEvent.ACTION_MOVE,s.getWidth()*.66f);touch(s,down,MotionEvent.ACTION_UP,s.getWidth()*.66f);});}
    private void touch(View v,long down,int action,float x){MotionEvent e=MotionEvent.obtain(down,SystemClock.uptimeMillis(),action,x,v.getHeight()/2f,0);try{v.dispatchTouchEvent(e);}finally{e.recycle();}}
    private View find(View v,String tag){if(tag.equals(v.getTag()))return v;if(v instanceof ViewGroup)for(int i=0;i<((ViewGroup)v).getChildCount();i++){View r=find(((ViewGroup)v).getChildAt(i),tag);if(r!=null)return r;}return null;}
    private int luma(int p){return(Color.red(p)+Color.green(p)+Color.blue(p))/3;}private int num(Object o,String f)throws Exception{return((Number)get(o,f)).intValue();}
    private Class<?> cls(String name)throws Exception{return loader.loadClass("cc.huevia."+name);}
    private void screenshot(String name)throws Exception{SystemClock.sleep(450);CountDownLatch frames=new CountDownLatch(1);ui(()->Choreographer.getInstance().postFrameCallback(t->Choreographer.getInstance().postFrameCallback(n->frames.countDown())));frames.await(2,TimeUnit.SECONDS);Bitmap b=getUiAutomation().takeScreenshot();try{if(name.equals("01-quick-editor")){Rect r=new Rect();ui(()->((View)get(panel,"viewerSave")).getGlobalVisibleRect(r));int painted=0;for(int y=1;y<=5;y++)for(int x=1;x<=5;x++){int c=b.getPixel(r.left+r.width()*x/6,r.top+r.height()*y/6);if(Color.red(c)>170&&Color.red(c)>Color.green(c)*1.15&&Color.green(c)>90)painted++;}check("first-frame-save-action-painted",painted>3);}try(OutputStream out=new FileOutputStream(new File(output,name+".png"))){b.compress(Bitmap.CompressFormat.PNG,100,out);screenshots++;}}finally{b.recycle();}}
    private void ui(Work w)throws Exception{AtomicReference<Throwable> e=new AtomicReference<>();runOnMainSync(()->{try{w.run();}catch(Throwable t){e.set(t);}});if(e.get()!=null)throw new RuntimeException(e.get());}
    private void until(Condition c,String label)throws Exception{long end=SystemClock.uptimeMillis()+25000;while(SystemClock.uptimeMillis()<end){if(c.test())return;SystemClock.sleep(25);}throw new AssertionError("Timeout "+label);}
    private void check(String name,boolean pass)throws Exception{checks.put(new JSONObject().put("name",name).put("pass",pass));if(!pass)throw new AssertionError(name);}
    private Object get(Object o,String name)throws Exception{for(Class<?> c=o.getClass();c!=null;c=c.getSuperclass())try{Field f=c.getDeclaredField(name);f.setAccessible(true);return f.get(o);}catch(NoSuchFieldException ignored){}throw new NoSuchFieldException(name);}
    private void set(Object o,String name,Object value)throws Exception{for(Class<?> c=o.getClass();c!=null;c=c.getSuperclass())try{Field f=c.getDeclaredField(name);f.setAccessible(true);f.set(o,value);return;}catch(NoSuchFieldException ignored){}throw new NoSuchFieldException(name);}
    private Object call(Object o,String name,Object...args)throws Exception{for(Class<?> c=o.getClass();c!=null;c=c.getSuperclass())for(Method m:c.getDeclaredMethods())if(m.getName().equals(name)&&m.getParameterCount()==args.length){m.setAccessible(true);try{return m.invoke(o,args);}catch(IllegalArgumentException ignored){}}throw new NoSuchMethodException(name);}
    private Object stat(String type,String name,Object...args)throws Exception{for(Method m:loader.loadClass(type).getDeclaredMethods())if(m.getName().equals(name)&&m.getParameterCount()==args.length){m.setAccessible(true);try{return m.invoke(null,args);}catch(IllegalArgumentException ignored){}}throw new NoSuchMethodException(type+"."+name);}
    private String sha(File f)throws Exception{byte[] bytes=MessageDigest.getInstance("SHA-256").digest(Files.readAllBytes(f.toPath()));StringBuilder s=new StringBuilder();for(byte b:bytes)s.append(String.format(Locale.ROOT,"%02x",b&255));return s.toString();}
    private Throwable unwrap(Throwable t){while(t.getCause()!=null)t=t.getCause();return t;}
}
