package cc.huevia.livepreviewqa;

import android.app.*;
import android.content.*;
import android.content.pm.ActivityInfo;
import android.graphics.*;
import android.graphics.drawable.BitmapDrawable;
import android.os.*;
import android.view.*;
import android.widget.*;
import cc.huevia.album.*;
import cc.huevia.ncp.*;
import cc.huevia.ui.*;
import java.io.*;
import java.lang.reflect.*;
import java.nio.file.Files;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.*;
import org.json.*;

/** Held native gestures on the real editor. Measures changed photo pixels BEFORE ACTION_UP. */
public final class LivePreviewProbe extends Instrumentation {
    private Bundle args; private Activity activity; private AlbumPanel panel; private PhotoFilterEditor editor;
    private File output,fixture; private DownloadedPhoto photo; private String sourceSha,stage="start";
    private PhotoEditStore store; private Throwable failure; private boolean baseline;
    private final List<File> cleanup=new ArrayList<>(); private final JSONArray checks=new JSONArray(),measurements=new JSONArray();
    @Override public void onCreate(Bundle args){this.args=args;start();}
    @Override public void onStart(){try{
        baseline=args.getString("baseline","false").equals("true");
        check("owned-emulator",Build.HARDWARE.matches("ranchu|goldfish"));
        check("exact-installed-apk",sha(new File(getTargetContext().getApplicationInfo().sourceDir)).equals(args.getString("candidateSha256")));
        String run=args.getString("runId");check("safe-run-id",run.matches("[a-zA-Z0-9.-]+"));
        output=new File(getTargetContext().getExternalFilesDir(null),"live-preview-107/"+run);output.mkdirs();
        activity=startActivitySync(new Intent().setClassName("cc.huevia","cc.huevia.MainActivity").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
        until(()->(Boolean)get(activity,"ready"),"main-ready");check("guest-fixtures-only",PhotoFilterEditor.accountOwner(activity).isEmpty());
        boolean landscape=args.getString("mode","phone").equals("landscape");
        ui(()->activity.setRequestedOrientation(landscape?ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE:ActivityInfo.SCREEN_ORIENTATION_PORTRAIT));
        until(()->activity.getResources().getConfiguration().orientation==(landscape?2:1),"orientation");
        panel=(AlbumPanel)get(activity,"album");photo=fixture();store=new PhotoEditStore(activity.getFilesDir(),"");
        cleanup.add(new File((File)get(store,"root"),sourceSha+".draft"));
        ui(()->{set(activity,"albumTab",true);set(activity,"localAlbumTab",false);set(activity,"settingsTab",false);panel.openLocalWorkspace(Collections.singletonList(photo),0);});
        until(()->get(panel,"filterEditor")!=null&&((PhotoFilterEditor)get(panel,"filterEditor")).isReady(),"real-editor-ready");
        editor=(PhotoFilterEditor)get(panel,"filterEditor");waitEditor();
        // A realistic expensive edit makes render starvation observable, without changing the renderer.
        ui(()->{set(editor,"adjustments",PhotoAdjustments.NONE.with(PhotoAdjustments.Parameter.CLARITY,70).with(PhotoAdjustments.Parameter.SHARPENING,70));invoke(editor,"edited");invoke(editor,"setAdjustmentMode",new Class<?>[]{boolean.class},true);});waitEditor();
        stage="basic-held-gesture";int undo=undoSize();
        gesture("basic",(View)get(editor,"adjustmentSlider"),()->(Bitmap)get(editor,"current"),false);
        waitEditor();check("basic-one-undo",undoSize()==undo+1);check("basic-final-full-resolution",((Bitmap)get(editor,"current")).getWidth()==((Bitmap)get(editor,"original")).getWidth());
        if(!baseline){alignment();capture("01-editor-adjustment");}
        ui(()->{set(editor,"adjustments",((PhotoAdjustments)get(editor,"adjustments")).with(PhotoAdjustments.Parameter.EXPOSURE,0));invoke(editor,"edited");});waitEditor();
        String unchanged=((PhotoAdjustments)get(editor,"adjustments")).identity();
        stage="hsl-held-gesture";ui(()->editor.showColor(false));PhotoColorDialog hsl=(PhotoColorDialog)get(editor,"popup");waitColour(hsl);
        ui(()->((Button[])get(hsl,"bands"))[0].performClick());
        for(int a=0;a<(baseline?1:3);a++){
            final int axis=a;SeekBar slider=((SeekBar[])get(hsl,"sliders"))[axis];
            gesture("hsl-"+a,slider,()->bitmap((ImageView)get(hsl,"photo")),false);waitColour(hsl);
            check("hsl-final-full-"+a,bitmap((ImageView)get(hsl,"photo")).getWidth()==((Bitmap)get(editor,"original")).getWidth());
        }
        if(!baseline){Button band=((Button[])get(hsl,"bands"))[5];check("hsl-dot-top-padding",band.getPaddingTop()>=dp(8));capture("02-hsl");}
        ui(hsl::dismiss);check("hsl-cancel-no-parent-edit",((PhotoAdjustments)get(editor,"adjustments")).identity().equals(unchanged));
        stage="curve-held-gesture";ui(()->editor.showColor(true));PhotoColorDialog curves=(PhotoColorDialog)get(editor,"popup");waitColour(curves);
        gesture("curve",(View)get(curves,"graph"),()->bitmap((ImageView)get(curves,"photo")),true);waitColour(curves);
        if(!baseline)capture("03-curves");undo=undoSize();ui(()->((Button)get(curves,"apply")).performClick());waitEditor();check("curve-apply-one-undo",undoSize()==undo+1);
        if(!baseline){
            stage="filter-held-gesture";byte[] bytes=NcpCompatibilityFixtures.ncp();PresetPreviewProfile profile=PresetPreviewProfiles.fromPreset(bytes);
            ui(()->{set(editor,"selected","own-live-qa");set(editor,"selectedBytes",bytes);set(editor,"selectedProfile",profile);set(editor,"selectedName","QA NCP");invoke(editor,"edited");invoke(editor,"setAdjustmentMode",new Class<?>[]{boolean.class},false);});waitEditor();undo=undoSize();
            gesture("filter-strength",(View)get(editor,"slider"),()->(Bitmap)get(editor,"current"),false);waitEditor();check("filter-one-undo",undoSize()==undo+1);
            stage="border-held-gesture";ui(()->{set(editor,"border",PhotoBorder.NONE.withTemplate(1));invoke(editor,"edited");});waitEditor();
            Object borders=get(editor,"borderControls");ui(()->invoke(borders,"showSettings",new Class<?>[]{int.class},2));
            Dialog borderDialog=(Dialog)get(borders,"popup");View seek=borderDialog.getWindow().getDecorView().findViewWithTag("border-appearance-0");
            check("appearance-real-native-slider",seek instanceof SeekBar);undo=undoSize();
            gesture("border-appearance",seek,()->(Bitmap)get(editor,"current"),false);waitEditor();check("border-one-undo",undoSize()==undo+1);capture("04-border");ui(()->((PhotoBorderPanel)borders).dismiss());
            stage="crop-held-gesture";ui(()->editor.showComposition());until(()->get(editor,"popup") instanceof PhotoCropDialog,"crop-ready");
            PhotoCropDialog crop=(PhotoCropDialog)get(editor,"popup");SeekBar angle=(SeekBar)get(crop,"slider");View canvas=(View)get(crop,"crop");
            gesture("crop-angle",angle,()->draw(canvas),false);check("crop-angle-changed-before-dismiss",crop.geometry().angle!=0);ui(crop::dismiss);
            stage="actual-album-version-badge";albumBadge();
        }
        check("original-bytes-preserved",sha(fixture).equals(sourceSha));
    }catch(Throwable e){failure=e;try{if(output!=null){StringWriter trace=new StringWriter();e.printStackTrace(new PrintWriter(trace));Files.writeString(new File(output,"failure-stack.txt").toPath(),trace.toString());}capture("failure");}catch(Throwable ignored){}}
    finally{
        try{if(editor!=null){drain();ui(()->{editor.dismissPopup();editor.unbind();});drain();}for(File file:cleanup)Files.deleteIfExists(file.toPath());if(activity!=null)ui(activity::finish);}catch(Throwable e){if(failure==null)failure=e;}
        try{if(output!=null)Files.writeString(new File(output,"report.json").toPath(),new JSONObject().put("pass",failure==null).put("baseline",baseline).put("stage",stage).put("checks",checks).put("measurements",measurements).put("candidateSha256",args.getString("candidateSha256")).put("mode",args.getString("mode")).put("fontScale",activity==null?0:activity.getResources().getConfiguration().fontScale).put("failure",failure==null?JSONObject.NULL:failure.toString()).put("fixtureRemoved",fixture==null||!fixture.exists()).put("scope","Real MainActivity/editor/native gestures; changed rendered photo pixels sampled before ACTION_UP, own JPEG and actual source/effect ledgers. Emulator only; not physical-device FPS or camera throughput.").toString(2));}catch(Throwable e){failure=e;}
        Bundle result=new Bundle();result.putString("summary",failure==null?"PASS "+checks.length()+" checks":"FAIL "+stage+" "+failure);finish(failure==null?Activity.RESULT_OK:Activity.RESULT_CANCELED,result);
    }}
    private interface Image {Bitmap read()throws Exception;}
    private void gesture(String name,View view,Image image,boolean curve)throws Exception{
        until(()->view.getWidth()>0&&view.getHeight()>0,"laid-out-"+name);int[] initialProgress={-1};if(view instanceof SeekBar)initialProgress[0]=((SeekBar)view).getProgress();
        long start=SystemClock.uptimeMillis();Set<Long> pixels=new HashSet<>();long[] first={-1},last={-1},previous={Long.MIN_VALUE};int[] frames={0};
        long[] before={0};ui(()->before[0]=signature(image.read()));
        float initialX=curve?view.getWidth()*.5f:dp(18);float initialY=curve?view.getHeight()*.5f:view.getHeight()/2f;
        ui(()->touch(view,start,MotionEvent.ACTION_DOWN,initialX,initialY));
        for(int n=0;n<90;n++){
            final int i=n;ui(()->{float fraction=.08f+.82f*i/89;float x=curve?view.getWidth()*.5f:dp(18)+(view.getWidth()-dp(36))*fraction;float y=curve?view.getHeight()*(.75f-.5f*i/89):view.getHeight()/2f;touch(view,start,MotionEvent.ACTION_MOVE,x,y);Bitmap current=image.read();long sig=signature(current);pixels.add(sig);if(sig!=before[0]&&sig!=previous[0]){frames[0]++;long elapsed=SystemClock.uptimeMillis()-start;if(first[0]<0)first[0]=elapsed;last[0]=elapsed;}previous[0]=sig;if(name.equals("crop-angle")&&current!=null)current.recycle();});SystemClock.sleep(16);
        }
        long held=SystemClock.uptimeMillis()-start;
        check("held-view-retained-"+name,view.getParent()!=null);
        if(view instanceof SeekBar)check("native-progress-changed-"+name,((SeekBar)view).getProgress()!=initialProgress[0]);
        measurements.put(new JSONObject().put("control",name).put("heldMs",held).put("pixelChangesBeforeUp",frames[0]).put("distinctPhotoPixelSignatures",pixels.size()).put("firstChangedFrameMs",first[0]).put("lastChangedFrameMs",last[0]));
        if(!baseline)check("multiple-photo-frames-before-up-"+name,frames[0]>=2&&pixels.size()>=2);
        ui(()->touch(view,start,MotionEvent.ACTION_UP,curve?view.getWidth()*.5f:view.getWidth()-dp(24),curve?view.getHeight()*.25f:view.getHeight()/2f));
    }
    private void alignment()throws Exception{ui(()->{
        Map<?,?> advanced=(Map<?,?>)get(editor,"advancedControls"),parameters=(Map<?,?>)get(editor,"parameterControls");LinearLayout basic=(LinearLayout)parameters.values().iterator().next();
        int expected=baseline(basic.getChildAt(1)),iconY=y(basic.getChildAt(0));for(Object option:advanced.values()){LinearLayout entry=(LinearLayout)option;TextView label=(TextView)entry.getChildAt(1);check("advanced-inactive-"+label.getText(),!entry.isSelected()&&label.getCurrentTextColor()==0x99ffffff);check("advanced-caption-aligned-"+label.getText(),Math.abs(baseline(label)-expected)<=1);check("advanced-icon-aligned-"+label.getText(),y(entry.getChildAt(0))==iconY);}
    });}
    private void albumBadge()throws Exception{
        PhotoEditStore.Draft effectDraft=new PhotoEditStore.Draft(sourceSha,null,"",0,PhotoAdjustments.NONE.with(PhotoAdjustments.Parameter.CONTRAST,20),PhotoGeometry.NONE,PhotoBorder.NONE,true);
        String model=PhotoPresetRenderer.modelVersion(effectDraft.profile());Method keyMethod=PhotoPresetBatch.class.getDeclaredMethod("key",String.class,String.class,String.class);keyMethod.setAccessible(true);String key=(String)keyMethod.invoke(null,sourceSha,effectDraft.effectPresetSha(),model);
        File effect=new File(fixture.getParentFile(),"effect-"+key+"__Effect.JPG");cleanup.add(effect);new PhotoPresetRenderer(activity.getAssets()).render(fixture,effect,effectDraft.profile(),()->false,null);
        File records=new File(activity.getFilesDir(),"photo-preset-results");records.mkdirs();for(String suffix:new String[]{".record",".model",".source",".meta"})for(String tail:new String[]{"",".bak",".new"})cleanup.add(new File(records,key+suffix+tail));
        try(DataOutputStream out=new DataOutputStream(new FileOutputStream(new File(records,key+".record")))){out.writeInt(0x50424531);out.writeLong(effect.length());out.writeUTF(sha(effect));}
        Class<?> cls=Class.forName("cc.huevia.album.PhotoPresetSources",true,getTargetContext().getClassLoader());Constructor<?> c=cls.getDeclaredConstructor(File.class,File.class);c.setAccessible(true);Object links=c.newInstance(activity.getFilesDir(),activity.getExternalFilesDir(Environment.DIRECTORY_PICTURES));
        Method remember=cls.getDeclaredMethod("rememberModel",String.class,String.class);remember.setAccessible(true);remember.invoke(links,key,model);Method bind=cls.getDeclaredMethod("bind",DownloadedPhoto.class,DownloadedPhoto.class,String.class,String.class,String.class,java.util.function.BooleanSupplier.class);bind.setAccessible(true);bind.invoke(links,downloaded(effect,"QA_Effect.JPG"),photo,effectDraft.effectPresetSha(),"QA Effect",model,(java.util.function.BooleanSupplier)()->false);
        Object album=get(activity,"localAlbum");ui(()->{set(activity,"albumTab",false);set(activity,"localAlbumTab",true);set(activity,"settingsTab",false);set(album,"phone",false);invoke(activity,"render");invoke(album,"refreshApp");});
        until(()->activity.getWindow().getDecorView().findViewWithTag("photo-version-badge")!=null,"real-catalog-grouped-badge");SystemClock.sleep(300);
        View badge=activity.getWindow().getDecorView().findViewWithTag("photo-version-badge"),face=badge.findViewWithTag("photo-version-badge-face");
        check("version-touch-target",badge.getWidth()>=dp(48)&&badge.getHeight()>=dp(48));check("version-face-compact",face.getHeight()<=dp(26)&&face.getWidth()<dp(60));check("version-face-in-photo",badge.getParent() instanceof FrameLayout);capture("05-album-version");
        ui(badge::performClick);SystemClock.sleep(150);android.view.accessibility.AccessibilityNodeInfo root=getUiAutomation().getRootInActiveWindow();check("version-opens-existing-chooser",contains(root,"选择照片版本"));capture("06-version-chooser");sendKeyDownUpSync(KeyEvent.KEYCODE_BACK);
    }
    private DownloadedPhoto fixture()throws Exception{int id=getTargetContext().getResources().getIdentifier("preset_template","drawable","cc.huevia");Bitmap source=BitmapFactory.decodeResource(getTargetContext().getResources(),id);check("shipping-photo-fixture",source!=null);Bitmap image=Bitmap.createScaledBitmap(source,1200,800,true);if(image!=source)source.recycle();File folder=new File(getTargetContext().getExternalFilesDir(Environment.DIRECTORY_PICTURES),"camera-album");folder.mkdirs();fixture=new File(folder,"live-qa-"+args.getString("runId")+"__PHOTO.JPG");cleanup.add(fixture);try(FileOutputStream out=new FileOutputStream(fixture)){image.compress(Bitmap.CompressFormat.JPEG,98,out);}image.recycle();android.media.ExifInterface exif=new android.media.ExifInterface(fixture.getPath());exif.setAttribute("Orientation","1");exif.setAttribute("ImageDescription","Own live QA "+UUID.randomUUID());exif.saveAttributes();sourceSha=sha(fixture);return downloaded(fixture,"DSC_LIVE_QA.JPG");}
    private DownloadedPhoto downloaded(File file,String name)throws Exception{Constructor<DownloadedPhoto> c=DownloadedPhoto.class.getDeclaredConstructor(File.class,String.class);c.setAccessible(true);return c.newInstance(file,name);}
    private void waitColour(PhotoColorDialog dialog)throws Exception{until(()->((Button)get(dialog,"apply")).isEnabled(),"colour-final-ready");}
    private void waitEditor()throws Exception{until(()->{try{Object queue=get(editor,"previewQueue");Method idle=queue.getClass().getMethod("isIdle");return(Boolean)idle.invoke(queue);}catch(NoSuchFieldException old){ThreadPoolExecutor p=(ThreadPoolExecutor)get(editor,"previews");return p.getActiveCount()==0&&p.getQueue().isEmpty();}},"editor-final-ready");ui(()->{});}
    private int undoSize()throws Exception{return((Deque<?>)get(editor,"undo")).size();}
    private void drain()throws Exception{CountDownLatch latch=new CountDownLatch(1);ui(()->editor.afterPendingSaves(latch::countDown));check("pending-saves-drained",latch.await(15,TimeUnit.SECONDS));}
    private static Bitmap bitmap(ImageView view){return view.getDrawable() instanceof BitmapDrawable?((BitmapDrawable)view.getDrawable()).getBitmap():null;}
    private static long signature(Bitmap bitmap){if(bitmap==null||bitmap.isRecycled())return 0;long hash=0xcbf29ce484222325L;for(int y=1;y<10;y++)for(int x=1;x<10;x++){hash^=bitmap.getPixel(bitmap.getWidth()*x/10,bitmap.getHeight()*y/10);hash*=0x100000001b3L;}return hash;}
    private static Bitmap draw(View v){Bitmap b=Bitmap.createBitmap(Math.max(1,v.getWidth()),Math.max(1,v.getHeight()),Bitmap.Config.ARGB_8888);v.draw(new Canvas(b));return b;}
    private void touch(View view,long start,int action,float x,float y){MotionEvent event=MotionEvent.obtain(start,SystemClock.uptimeMillis(),action,x,y,0);view.dispatchTouchEvent(event);event.recycle();}
    private int dp(int n){return Math.round(n*activity.getResources().getDisplayMetrics().density);}private static int y(View v){int[] p=new int[2];v.getLocationOnScreen(p);return p[1];}private static int baseline(View v){return y(v)+((TextView)v).getBaseline();}
    private void capture(String name)throws Exception{android.view.accessibility.AccessibilityNodeInfo root=getUiAutomation().getRootInActiveWindow();clickGuide(root);SystemClock.sleep(200);ui(()->{});Bitmap screen=getUiAutomation().takeScreenshot();check("screenshot-"+name,screen!=null);try(FileOutputStream out=new FileOutputStream(new File(output,name+".png"))){screen.compress(Bitmap.CompressFormat.PNG,100,out);}screen.recycle();}
    private void clickGuide(android.view.accessibility.AccessibilityNodeInfo node){if(node==null)return;if(node.getText()!=null&&node.getText().toString().equalsIgnoreCase("Got it")){node.performAction(16);SystemClock.sleep(250);return;}for(int i=0;i<node.getChildCount();i++)clickGuide(node.getChild(i));}
    private boolean contains(android.view.accessibility.AccessibilityNodeInfo n,String text){if(n==null)return false;if(n.getText()!=null&&n.getText().toString().contains(text))return true;for(int i=0;i<n.getChildCount();i++)if(contains(n.getChild(i),text))return true;return false;}
    private interface Checked{void run()throws Exception;}private interface Check{boolean test()throws Exception;}
    private void ui(Checked work){Throwable[] error={null};runOnMainSync(()->{try{work.run();}catch(Throwable e){error[0]=e;}});if(error[0]!=null)throw new RuntimeException(error[0]);}
    private void until(Check work,String name)throws Exception{long end=SystemClock.uptimeMillis()+20000;while(SystemClock.uptimeMillis()<end){boolean[] ready={false};ui(()->ready[0]=work.test());if(ready[0]){check(name,true);return;}SystemClock.sleep(40);}check(name,false);}
    private void check(String name,boolean value){if(!value)throw new AssertionError(name);checks.put(name);}
    private static Object get(Object value,String name)throws Exception{Field f=value.getClass().getDeclaredField(name);f.setAccessible(true);return f.get(value);}private static void set(Object value,String name,Object next)throws Exception{Field f=value.getClass().getDeclaredField(name);f.setAccessible(true);f.set(value,next);}
    private static void invoke(Object value,String name)throws Exception{invoke(value,name,new Class<?>[0]);}private static void invoke(Object value,String name,Class<?>[] types,Object...args)throws Exception{Method m=value.getClass().getDeclaredMethod(name,types);m.setAccessible(true);m.invoke(value,args);}
    private static String sha(File file)throws Exception{MessageDigest digest=MessageDigest.getInstance("SHA-256");try(InputStream in=Files.newInputStream(file.toPath())){byte[] bytes=new byte[65536];int n;while((n=in.read(bytes))!=-1)digest.update(bytes,0,n);}StringBuilder text=new StringBuilder();for(byte b:digest.digest())text.append(String.format("%02x",b&255));return text.toString();}
}
