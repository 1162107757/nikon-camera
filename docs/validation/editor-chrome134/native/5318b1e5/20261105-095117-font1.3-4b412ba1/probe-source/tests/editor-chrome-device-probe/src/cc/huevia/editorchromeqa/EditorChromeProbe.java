package cc.huevia.editorchromeqa;
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
public final class EditorChromeProbe extends Instrumentation {
    private Activity activity;private ClassLoader loader;private Bundle args;private File output,fixture,draftFile;private String sourceSha,stage="start";private Object editor,panel;private Dialog parent;private Throwable failure;private int screenshots;
    private List<?> syntheticBlemishes;
    private int fixtureNumber;
    private final List<File> extraFiles=new ArrayList<>(),extraDrafts=new ArrayList<>();
    private final JSONArray checks=new JSONArray();private final List<Dialog> dialogs=new ArrayList<>();
    private interface Work{void run()throws Exception;}private interface Condition{boolean test()throws Exception;}
    @Override public void onCreate(Bundle b){args=b;start();}
    @Override public void onStart(){
        try{
            loader=getTargetContext().getClassLoader();check("owned-emulator",Build.HARDWARE.equals("ranchu")||Build.HARDWARE.equals("goldfish"));check("exact-installed-candidate",sha(new File(getTargetContext().getApplicationInfo().sourceDir)).equals(args.getString("candidateSha256")));
            String run=args.getString("runId");check("safe-run-id",run!=null&&run.matches("[a-zA-Z0-9.-]+"));output=new File(getTargetContext().getExternalFilesDir(null),"editor-chrome134/"+run);output.getParentFile().mkdirs();check("new-evidence-directory",output.mkdir());
            activity=startActivitySync(new Intent().setClassName("cc.huevia","cc.huevia.MainActivity").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));until(()->(Boolean)get(activity,"ready"),"ready");boolean land="landscape".equals(args.getString("mode"));ui(()->activity.setRequestedOrientation(land?ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE:ActivityInfo.SCREEN_ORIENTATION_PORTRAIT));until(()->activity.getResources().getConfiguration().orientation==(land?2:1),"orientation");
            fixture=fixture();sourceSha=sha(fixture);panel=get(activity,"album");Object photo=photo();ui(()->{set(activity,"albumTab",true);set(activity,"settingsTab",false);call(panel,"openLocalWorkspace",Collections.singletonList(photo),0);});until(()->get(panel,"filterEditor")!=null&&(Boolean)call(get(panel,"filterEditor"),"isReady")&&sourceSha.equals(get(get(panel,"filterEditor"),"sourceSha")),"editor");editor=get(panel,"filterEditor");waitEditor();
            store();chromeFlow();

        }catch(Throwable t){failure=unwrap(t);try{screenshot("failure");}catch(Throwable ignored){}}
        finally{
            try{ui(()->{for(Dialog d:dialogs)if(d.isShowing())d.dismiss();});if(editor!=null){drain();ui(()->call(editor,"unbind"));drain();}if(draftFile!=null)Files.deleteIfExists(draftFile.toPath());if(fixture!=null)Files.deleteIfExists(fixture.toPath());for(File f:extraFiles)Files.deleteIfExists(f.toPath());for(File f:extraDrafts)Files.deleteIfExists(f.toPath());check("owned-fixture-and-draft-cleaned",(fixture==null||!fixture.exists())&&(draftFile==null||!draftFile.exists()));}catch(Throwable t){if(failure==null)failure=unwrap(t);}
            try{ui(()->{if(activity!=null){activity.setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED);activity.finish();}});}catch(Throwable ignored){}
        }
        Bundle b=new Bundle();try{JSONObject r=new JSONObject().put("pass",failure==null).put("stage",stage).put("candidateSha256",args.getString("candidateSha256")).put("mode",args.getString("mode")).put("scope",args.getString("scope")).put("checks",checks).put("screenshots",screenshots).put("privateFixtureRemoved",fixture==null||!fixture.exists()).put("privateDraftRemoved",draftFile==null||!draftFile.exists());if(failure!=null)r.put("failure",failure.toString()).put("stack",android.util.Log.getStackTraceString(failure));if(output!=null)Files.write(new File(output,"report.json").toPath(),r.toString(2).getBytes(StandardCharsets.UTF_8));b.putString("stream",(failure==null?"PASS":"FAIL")+" "+checks.length()+" checks "+stage+(failure==null?"":" "+failure));}catch(Throwable t){b.putString("stream","FAIL report "+t);}finish(failure==null?Activity.RESULT_OK:Activity.RESULT_CANCELED,b);
    }
    private View mainTag(String name){View v=find(activity.getWindow().getDecorView(),name);if(v==null)throw new AssertionError("Missing main "+name);return v;}
    private void mainClick(String name)throws Exception{ui(()->mainTag(name).performClick());}
    private void waitQuick()throws Exception{until(()->!(Boolean)get(editor,"quickBusy"),"quick analysis");waitEditor();}
    private void chromeFlow()throws Exception{
        stage="compact-compare";
        mainClick("editor-primary-3");frameFence();
        Button button=(Button)mainTag("editor-compare-original");
        until(()->button.isEnabled(),"comparison original ready");
        check("compare-48dp-target",button.getWidth()==dp(48)&&button.getHeight()==dp(48));
        check("compare-48dp-mount",((View)button.getParent()).getWidth()==dp(48));
        check("compare-no-long-label",button.getText().length()==0);
        check("compare-22dp-artwork",button.getCompoundDrawables()[0]!=null&&button.getCompoundDrawables()[0].getBounds().width()==dp(22));
        check("compare-unclipped",unclipped(button));
        check("compare-accessible-hold-instruction",button.getContentDescription().toString().contains("按住"));
        drag((SeekBar)get(editor,"adjustmentSlider"));waitEditor();frameFence();
        Object adjustments=get(editor,"adjustments"),comparison=get(panel,"viewerComparison"),image=get(panel,"viewerImage");
        Bitmap effect=(Bitmap)get(comparison,"effect"),original=(Bitmap)get(comparison,"original");
        check("distinct-original-and-effect",effect!=original&&effect!=null&&original!=null);
        int history=((Deque<?>)get(editor,"undo")).size();
        check("effect-shown-before-hold",get(image,"photo")==effect);
        screenshot("01-editor");
        Rect bounds=new Rect();ui(()->button.getGlobalVisibleRect(bounds));
        long t=SystemClock.uptimeMillis();input(t,MotionEvent.ACTION_DOWN,bounds.exactCenterX(),bounds.exactCenterY());
        check("hold-shows-original",(Boolean)get(comparison,"showingOriginal")&&get(image,"photo")==original&&button.isSelected());
        check("held-control-stays-icon-only",button.getText().length()==0);
        screenshot("02-held-original");input(t,MotionEvent.ACTION_UP,bounds.exactCenterX(),bounds.exactCenterY());
        check("release-restores-effect",!(Boolean)get(comparison,"showingOriginal")&&get(image,"photo")==effect&&!button.isSelected());
        t=SystemClock.uptimeMillis();input(t,MotionEvent.ACTION_DOWN,bounds.exactCenterX(),bounds.exactCenterY());input(t,MotionEvent.ACTION_MOVE,bounds.left-dp(5),bounds.exactCenterY());
        check("move-outside-restores-effect",!(Boolean)get(comparison,"showingOriginal")&&get(image,"photo")==effect);input(t,MotionEvent.ACTION_UP,bounds.left-dp(5),bounds.exactCenterY());
        t=SystemClock.uptimeMillis();input(t,MotionEvent.ACTION_DOWN,bounds.exactCenterX(),bounds.exactCenterY());input(t,MotionEvent.ACTION_CANCEL,bounds.exactCenterX(),bounds.exactCenterY());
        check("cancel-restores-effect",!(Boolean)get(comparison,"showingOriginal")&&get(image,"photo")==effect);
        ui(button::performClick);check("accessibility-click-shows-original",get(image,"photo")==original);ui(button::performClick);check("accessibility-second-click-restores-effect",get(image,"photo")==effect);
        ui(()->{button.onKeyDown(KeyEvent.KEYCODE_ENTER,new KeyEvent(KeyEvent.ACTION_DOWN,KeyEvent.KEYCODE_ENTER));button.onKeyUp(KeyEvent.KEYCODE_ENTER,new KeyEvent(KeyEvent.ACTION_UP,KeyEvent.KEYCODE_ENTER));});
        check("keyboard-activation-shows-original",get(image,"photo")==original);ui(()->call(comparison,"release"));
        check("explicit-release-restores-effect",get(image,"photo")==effect);
        ui(()->call(comparison,"setUnavailable"));check("unavailable-icon-disabled",!button.isEnabled()&&button.getText().length()==0&&get(image,"photo")==effect);
        ui(()->call(comparison,"setOriginal",original));check("restored-icon-ready",button.isEnabled()&&button.getText().length()==0);
        check("comparison-does-not-add-undo",((Deque<?>)get(editor,"undo")).size()==history);
        stage="deduplicated-more";
        AtomicReference<Menu> menu=new AtomicReference<>();ui(()->{PopupMenu p=new PopupMenu(activity,mainTag("editor-photo-more"));call(editor,"addMenuItems",p.getMenu());menu.set(p.getMenu());});
        String[] expected={"查看照片细节","复制调整到其他照片","撤销上次批量复制","重置调节，保留滤镜","全部重置"};
        check("editor-more-only-five-utilities",menu.get().size()==expected.length);
        for(int i=0;i<expected.length;i++)check("utility-menu-entry-"+i,menu.get().getItem(i).getTitle().toString().equals(expected[i]));
        mainClick("editor-photo-more");until(()->getUiAutomation().getRootInActiveWindow()!=null&&!getUiAutomation().getRootInActiveWindow().findAccessibilityNodeInfosByText("直方图").isEmpty(),"actual more popup");
        check("actual-popup-keeps-photo-utilities",!getUiAutomation().getRootInActiveWindow().findAccessibilityNodeInfosByText("照片版本").isEmpty());
        for(String duplicate:new String[]{"调节工具","局部与修复","人像精修","构图（裁剪、旋转、拉直）","曲线","HSL 分色","保存当前为我的配方","参数说明","重置当前参数"})check("no-duplicate-"+duplicate,getUiAutomation().getRootInActiveWindow().findAccessibilityNodeInfosByText(duplicate).isEmpty());
        screenshot("03-more-menu");sendKeyDownUpSync(KeyEvent.KEYCODE_BACK);frameFence();
        check("direct-tools-retained",mainTag("editor-curves").hasOnClickListeners()&&mainTag("editor-hsl").hasOnClickListeners()&&((Map<?,?>)get(editor,"parameterControls")).size()==17);
        check("chrome-keeps-adjustments",adjustments.equals(get(editor,"adjustments")));
        check("original-file-unchanged",sha(fixture).equals(sourceSha));stage="complete";
    }
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
    private File fixture()throws Exception{Bitmap b;try(InputStream in=getContext().getAssets().open("astronaut.png")){b=BitmapFactory.decodeStream(in);}if(++fixtureNumber>1){Matrix mirror=new Matrix();mirror.setScale(-1,1);Bitmap flipped=Bitmap.createBitmap(b,0,0,b.getWidth(),b.getHeight(),mirror,true);if(flipped!=b)b.recycle();b=flipped;}File dir=new File(getTargetContext().getExternalFilesDir(Environment.DIRECTORY_PICTURES),"camera-album");dir.mkdirs();File f=new File(dir,"editor-chrome134-"+UUID.randomUUID()+"__Skin.JPG");try(OutputStream out=new FileOutputStream(f)){b.compress(Bitmap.CompressFormat.JPEG,97,out);}finally{b.recycle();}android.media.ExifInterface e=new android.media.ExifInterface(f.getPath());e.setAttribute("ImageDescription","editor-chrome134 private QA "+UUID.randomUUID());e.saveAttributes();return f;}
    private Object photo()throws Exception{Constructor<?> c=cls("album.DownloadedPhoto").getDeclaredConstructor(File.class,String.class);c.setAccessible(true);return c.newInstance(fixture,"CHROME134.JPG");}
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
