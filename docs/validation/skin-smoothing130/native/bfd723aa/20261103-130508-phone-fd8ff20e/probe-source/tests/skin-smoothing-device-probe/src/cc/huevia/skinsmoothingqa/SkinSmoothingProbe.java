package cc.huevia.skinsmoothingqa;
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

/** Installed production code only; NASA astronaut fixture is confined to this test APK. */
public final class SkinSmoothingProbe extends Instrumentation {
    private Activity activity;private ClassLoader loader;private Bundle args;private File output,fixture,draftFile;private String sourceSha,stage="start";private Object editor,panel;private Dialog parent;private Throwable failure;private int screenshots;
    private final JSONArray checks=new JSONArray();private final List<Dialog> dialogs=new ArrayList<>();
    private interface Work{void run()throws Exception;}private interface Condition{boolean test()throws Exception;}
    @Override public void onCreate(Bundle b){args=b;start();}
    @Override public void onStart(){
        try{
            loader=getTargetContext().getClassLoader();check("owned-emulator",Build.HARDWARE.equals("ranchu")||Build.HARDWARE.equals("goldfish"));check("exact-installed-candidate",sha(new File(getTargetContext().getApplicationInfo().sourceDir)).equals(args.getString("candidateSha256")));
            String run=args.getString("runId");check("safe-run-id",run!=null&&run.matches("[a-zA-Z0-9.-]+"));output=new File(getTargetContext().getExternalFilesDir(null),"skin-smoothing130/"+run);output.getParentFile().mkdirs();check("new-evidence-directory",output.mkdir());
            activity=startActivitySync(new Intent().setClassName("cc.huevia","cc.huevia.MainActivity").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));until(()->(Boolean)get(activity,"ready"),"ready");boolean land="landscape".equals(args.getString("mode"));ui(()->activity.setRequestedOrientation(land?ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE:ActivityInfo.SCREEN_ORIENTATION_PORTRAIT));until(()->activity.getResources().getConfiguration().orientation==(land?2:1),"orientation");
            fixture=fixture();sourceSha=sha(fixture);panel=get(activity,"album");Object photo=photo();ui(()->{set(activity,"albumTab",true);set(activity,"settingsTab",false);call(panel,"openLocalWorkspace",Collections.singletonList(photo),0);});until(()->get(panel,"filterEditor")!=null&&(Boolean)call(get(panel,"filterEditor"),"isReady")&&sourceSha.equals(get(get(panel,"filterEditor"),"sourceSha")),"editor");editor=get(panel,"filterEditor");waitEditor();
            parent=portrait();ui(()->tag(parent,"portrait-entry-skin").performClick());until(()->!(Boolean)get(parent,"globalSkinBusy")&&get(get(parent,"portrait"),"globalSkinMask")!=null,"automatic exposed skin");waitPortrait();Object mask=get(get(parent,"portrait"),"globalSkinMask");byte[] coverage=(byte[])call(mask,"copyCoverage");int covered=0;for(byte b:coverage)if((b&255)>0)covered++;check("automatic-skin-nonempty",covered>0);check("no-selected-face-required",((List<?>)call(get(parent,"portrait"),"faces")).isEmpty());
            check("skin-colour-and-smoothing-peers",tag(parent,"portrait-skin-tone").isShown()&&tag(parent,"portrait-skin-smoothing").isShown());ui(()->tag(parent,"portrait-skin-smoothing").performClick());waitPortrait();check("smoothing-default-zero",num(get(parent,"portrait"),"skinSmoothing")==0);check("face-controls-hidden",!((View)get(parent,"faceBar")).isShown());
            Bitmap before=((Bitmap)get(parent,"rendered")).copy(Bitmap.Config.ARGB_8888,false);SeekBar slider=(SeekBar)tag(parent,"portrait-axis-0");until(()->slider.getWidth()>0&&slider.isShown(),"slider layout");check("native-slider-enabled-after-detection",slider.isEnabled());screenshot("01-skin-smoothing");
            drag(slider);waitPortrait();int amount=num(get(parent,"portrait"),"skinSmoothing");check("native-gesture-adjusts-smoothing",amount>=50&&amount<=80);check("single-gesture-history",((Collection<?>)get(parent,"undo")).size()==1);
            Bitmap after=(Bitmap)get(parent,"rendered");int changed=0,outside=0;for(int y=0;y<after.getHeight();y++)for(int x=0;x<after.getWidth();x++){int a=before.getPixel(x,y),b=after.getPixel(x,y);double weight=((Number)call(mask,"weight",(x+.5)/after.getWidth(),(y+.5)/after.getHeight())).doubleValue();if(weight<=0){if(a!=b)outside++;}else if(a!=b)changed++;}check("only-detected-skin-pixels-changed",changed>0&&outside==0);screenshot("02-adjusted-skin");
            ui(()->tag(parent,"portrait-undo").performClick());waitPortrait();check("undo-restores-zero",num(get(parent,"portrait"),"skinSmoothing")==0);ui(()->tag(parent,"portrait-redo").performClick());waitPortrait();check("redo-restores-strength",num(get(parent,"portrait"),"skinSmoothing")==amount);
            if("ui".equals(args.getString("scope"))){before.recycle();stage="ui-complete";}else{verifyCommit(amount,before);before.recycle();stage="complete";}
        }catch(Throwable t){failure=unwrap(t);try{screenshot("failure");}catch(Throwable ignored){}}
        finally{
            try{ui(()->{for(Dialog d:dialogs)if(d.isShowing())d.dismiss();});if(editor!=null){drain();ui(()->call(editor,"unbind"));drain();}if(draftFile!=null)Files.deleteIfExists(draftFile.toPath());if(fixture!=null)Files.deleteIfExists(fixture.toPath());check("owned-fixture-and-draft-cleaned",(fixture==null||!fixture.exists())&&(draftFile==null||!draftFile.exists()));}catch(Throwable t){if(failure==null)failure=unwrap(t);}
            try{ui(()->{if(activity!=null){activity.setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED);activity.finish();}});}catch(Throwable ignored){}
        }
        Bundle b=new Bundle();try{JSONObject r=new JSONObject().put("pass",failure==null).put("stage",stage).put("candidateSha256",args.getString("candidateSha256")).put("mode",args.getString("mode")).put("scope",args.getString("scope")).put("checks",checks).put("screenshots",screenshots).put("privateFixtureRemoved",fixture==null||!fixture.exists()).put("privateDraftRemoved",draftFile==null||!draftFile.exists());if(failure!=null)r.put("failure",failure.toString()).put("stack",android.util.Log.getStackTraceString(failure));if(output!=null)Files.write(new File(output,"report.json").toPath(),r.toString(2).getBytes(StandardCharsets.UTF_8));b.putString("stream",(failure==null?"PASS":"FAIL")+" "+checks.length()+" checks "+stage+(failure==null?"":" "+failure));}catch(Throwable t){b.putString("stream","FAIL report "+t);}finish(failure==null?Activity.RESULT_OK:Activity.RESULT_CANCELED,b);
    }
    private void verifyCommit(int amount,Bitmap original)throws Exception{
        stage="apply-draft-and-full-render";ui(()->tag(parent,"portrait-apply").performClick());waitEditor();drain();Object local=get(editor,"localEdits");check("parent-apply-commits-smoothing",num(get(local,"portrait"),"skinSmoothing")==amount);
        String owner=(String)stat("cc.huevia.ui.PhotoFilterEditor","accountOwner",activity);Object store=cls("album.PhotoEditStore").getConstructor(File.class,String.class).newInstance(activity.getFilesDir(),owner);draftFile=new File((File)get(store,"root"),sourceSha+".draft");Object draft=call(store,"read",sourceSha);check("actual-draft-keeps-smoothing",num(get(get(draft,"localEdits"),"portrait"),"skinSmoothing")==amount);
        File jpeg=new File(output,"full.jpg"),png=new File(output,"reference.png");Object renderer=stat("cc.huevia.album.PhotoPresetRenderer","forContext",activity),spec=stat("cc.huevia.album.PhotoExportSpec","full");call(renderer,"renderWithReference",fixture,jpeg,png,call(draft,"profile"),spec,(BooleanSupplier)()->false,null);Bitmap full=BitmapFactory.decodeFile(png.getPath());check("full-jpeg-and-reference-written",jpeg.isFile()&&jpeg.length()>0&&full.getWidth()==original.getWidth()&&full.getHeight()==original.getHeight());
        Bitmap preview=(Bitmap)get(editor,"current");int mismatch=0;for(int y=0;y<full.getHeight();y++)for(int x=0;x<full.getWidth();x++)if(full.getPixel(x,y)!=preview.getPixel(x,y))mismatch++;full.recycle();check("committed-preview-equals-full-preencoding-render",mismatch==0);check("source-jpeg-unchanged",sha(fixture).equals(sourceSha));
        parent=portrait();ui(()->{tag(parent,"portrait-entry-skin").performClick();tag(parent,"portrait-skin-smoothing").performClick();});waitPortrait();check("reopen-restores-smoothing-and-mask",num(get(parent,"portrait"),"skinSmoothing")==amount&&get(get(parent,"portrait"),"globalSkinMask")!=null);ui(()->call(parent,"adjust",0,20));waitPortrait();ui(parent::dismiss);check("cancel-does-not-change-committed-smoothing",num(get(get(editor,"localEdits"),"portrait"),"skinSmoothing")==amount);
    }
    private Dialog portrait()throws Exception{ui(()->call(editor,"showPortrait"));until(()->get(editor,"popup") instanceof Dialog&&((Dialog)get(editor,"popup")).isShowing(),"portrait dialog");Dialog d=(Dialog)get(editor,"popup");dialogs.add(d);parent=d;waitPortrait();return d;}
    private void waitPortrait()throws Exception{until(()->get(parent,"completedPreview")!=null&&(Boolean)call(get(parent,"queue"),"isIdle")&&tag(parent,"portrait-apply").isEnabled(),"precision portrait preview");}
    private void waitEditor()throws Exception{until(()->(Boolean)call(get(editor,"previewQueue"),"isIdle"),"main preview");ui(()->{});}
    private void drain()throws Exception{CountDownLatch done=new CountDownLatch(1);ui(()->call(editor,"afterPendingSaves",(Runnable)done::countDown));if(!done.await(12,TimeUnit.SECONDS))throw new AssertionError("draft save drain timeout");}
    private File fixture()throws Exception{Bitmap b;try(InputStream in=getContext().getAssets().open("astronaut.png")){b=BitmapFactory.decodeStream(in);}File dir=new File(getTargetContext().getExternalFilesDir(Environment.DIRECTORY_PICTURES),"camera-album");dir.mkdirs();File f=new File(dir,"skin130-"+UUID.randomUUID()+"__Skin.JPG");try(OutputStream out=new FileOutputStream(f)){b.compress(Bitmap.CompressFormat.JPEG,97,out);}finally{b.recycle();}android.media.ExifInterface e=new android.media.ExifInterface(f.getPath());e.setAttribute("ImageDescription","skin130 private QA "+UUID.randomUUID());e.saveAttributes();return f;}
    private Object photo()throws Exception{Constructor<?> c=cls("album.DownloadedPhoto").getDeclaredConstructor(File.class,String.class);c.setAccessible(true);return c.newInstance(fixture,"SKIN130.JPG");}
    private View tag(Dialog d,String name){View v=find(d.getWindow().getDecorView(),name);if(v==null)throw new AssertionError("Missing "+name);return v;}
    private void drag(SeekBar s)throws Exception{long down=SystemClock.uptimeMillis();ui(()->{touch(s,down,MotionEvent.ACTION_DOWN,s.getWidth()*.08f);touch(s,down,MotionEvent.ACTION_MOVE,s.getWidth()*.30f);touch(s,down,MotionEvent.ACTION_MOVE,s.getWidth()*.66f);touch(s,down,MotionEvent.ACTION_UP,s.getWidth()*.66f);});}
    private void touch(View v,long down,int action,float x){MotionEvent e=MotionEvent.obtain(down,SystemClock.uptimeMillis(),action,x,v.getHeight()/2f,0);try{v.dispatchTouchEvent(e);}finally{e.recycle();}}
    private View find(View v,String tag){if(tag.equals(v.getTag()))return v;if(v instanceof ViewGroup)for(int i=0;i<((ViewGroup)v).getChildCount();i++){View r=find(((ViewGroup)v).getChildAt(i),tag);if(r!=null)return r;}return null;}
    private int luma(int p){return(Color.red(p)+Color.green(p)+Color.blue(p))/3;}private int num(Object o,String f)throws Exception{return((Number)get(o,f)).intValue();}
    private Class<?> cls(String name)throws Exception{return loader.loadClass("cc.huevia."+name);}
    private void screenshot(String name)throws Exception{SystemClock.sleep(450);CountDownLatch frames=new CountDownLatch(1);ui(()->Choreographer.getInstance().postFrameCallback(t->Choreographer.getInstance().postFrameCallback(n->frames.countDown())));frames.await(2,TimeUnit.SECONDS);Bitmap b=getUiAutomation().takeScreenshot();try(OutputStream out=new FileOutputStream(new File(output,name+".png"))){b.compress(Bitmap.CompressFormat.PNG,100,out);screenshots++;}finally{b.recycle();}}
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
