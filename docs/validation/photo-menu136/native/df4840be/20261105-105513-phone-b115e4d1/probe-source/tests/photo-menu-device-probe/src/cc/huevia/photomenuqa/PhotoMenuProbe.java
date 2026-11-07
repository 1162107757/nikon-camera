package cc.huevia.photomenuqa;
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
public final class PhotoMenuProbe extends Instrumentation {
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
            String run=args.getString("runId");check("safe-run-id",run!=null&&run.matches("[a-zA-Z0-9.-]+"));output=new File(getTargetContext().getExternalFilesDir(null),"photo-menu136/"+run);output.getParentFile().mkdirs();check("new-evidence-directory",output.mkdir());
            activity=startActivitySync(new Intent().setClassName("cc.huevia","cc.huevia.MainActivity").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));until(()->(Boolean)get(activity,"ready"),"ready");boolean land="landscape".equals(args.getString("mode"));ui(()->activity.setRequestedOrientation(land?ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE:ActivityInfo.SCREEN_ORIENTATION_PORTRAIT));until(()->activity.getResources().getConfiguration().orientation==(land?2:1),"orientation");
            fixture=fixture();sourceSha=sha(fixture);panel=get(activity,"album");Object photo=photo();ui(()->{set(activity,"albumTab",true);set(activity,"settingsTab",false);call(panel,"openLocalWorkspace",Collections.singletonList(photo),0);});until(()->get(panel,"filterEditor")!=null&&(Boolean)call(get(panel,"filterEditor"),"isReady")&&sourceSha.equals(get(get(panel,"filterEditor"),"sourceSha")),"editor");editor=get(panel,"filterEditor");waitEditor();
            store();menuSliderFlow();

        }catch(Throwable t){failure=unwrap(t);try{screenshot("failure");}catch(Throwable ignored){}}
        finally{
            try{ui(()->{if(panel!=null)call(panel,"dismissPhotoActions");for(Dialog d:dialogs)if(d.isShowing())d.dismiss();});if(editor!=null){drain();ui(()->call(editor,"unbind"));drain();}if(draftFile!=null)Files.deleteIfExists(draftFile.toPath());if(fixture!=null)Files.deleteIfExists(fixture.toPath());for(File f:extraFiles)Files.deleteIfExists(f.toPath());for(File f:extraDrafts)Files.deleteIfExists(f.toPath());check("owned-fixture-and-draft-cleaned",(fixture==null||!fixture.exists())&&(draftFile==null||!draftFile.exists()));}catch(Throwable t){if(failure==null)failure=unwrap(t);}
            try{ui(()->{if(activity!=null){activity.setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED);activity.finish();}});}catch(Throwable ignored){}
        }
        Bundle b=new Bundle();try{JSONObject r=new JSONObject().put("pass",failure==null).put("stage",stage).put("candidateSha256",args.getString("candidateSha256")).put("mode",args.getString("mode")).put("scope",args.getString("scope")).put("checks",checks).put("screenshots",screenshots).put("privateFixtureRemoved",fixture==null||!fixture.exists()).put("privateDraftRemoved",draftFile==null||!draftFile.exists());if(failure!=null)r.put("failure",failure.toString()).put("stack",android.util.Log.getStackTraceString(failure));if(output!=null)Files.write(new File(output,"report.json").toPath(),r.toString(2).getBytes(StandardCharsets.UTF_8));b.putString("stream",(failure==null?"PASS":"FAIL")+" "+checks.length()+" checks "+stage+(failure==null?"":" "+failure));}catch(Throwable t){b.putString("stream","FAIL report "+t);}finish(failure==null?Activity.RESULT_OK:Activity.RESULT_CANCELED,b);
    }
    private View mainTag(String name){View v=find(activity.getWindow().getDecorView(),name);if(v==null)throw new AssertionError("Missing main "+name);return v;}
    private void mainClick(String name)throws Exception{ui(()->mainTag(name).performClick());}
    private void waitQuick()throws Exception{until(()->!(Boolean)get(editor,"quickBusy"),"quick analysis");waitEditor();}
    private void menuSliderFlow()throws Exception{
        stage="polished-photo-menu";android.widget.PopupWindow menu=openMenu();
        String[][] labels={{"11","收藏照片"},{"10","直方图"},{"12","照片版本"},{"20","查看细节"},{"30","复制调色"},{"31","撤销复制"},{"40","重置调色"},{"41","还原原图"}};
        check("custom-photo-menu",menu.getContentView().getTag().equals("photo-actions-menu"));
        Rect all=bounds(menu.getContentView());check("menu-stays-on-screen",all.left>=0&&all.top>=0&&all.right<=activity.getResources().getDisplayMetrics().widthPixels&&all.bottom<=activity.getResources().getDisplayMetrics().heightPixels);
        screenshot("00-photo-menu");
        for(String[] pair:labels){int id=Integer.parseInt(pair[0]);View row=menuTag(menu,"photo-action-"+id);reveal(row);TextView title=(TextView)menuTag(menu,"photo-action-title-"+id);check("short-title-"+id,title.getText().toString().equals(pair[1])||id==11&&title.getText().toString().equals("取消收藏"));check("menu-title-visible-"+id,unclipped(title));check("menu-row-touch-target-"+id,row.getHeight()>=dp(48));check("menu-icon-"+id,((ImageView)((ViewGroup)row).getChildAt(0)).getDrawable()!=null);View hint=find(menu.getContentView(),"photo-action-hint-"+id);if(hint!=null){check("menu-hint-visible-"+id,unclipped(hint));check("menu-hint-not-truncated-"+id,((TextView)hint).getLayout().getEllipsisCount(((TextView)hint).getLayout().getLineCount()-1)==0);}}
        screenshot("01-grouped-actions");
        boolean histogram=(Boolean)call(editor,"isHistogramVisible");tapMenu(10);until(()->(Boolean)call(editor,"isHistogramVisible")!=histogram,"histogram callback");check("menu-histogram-dispatch",true);waitEditor();
        menu=openMenu();check("histogram-state-updated",menuTag(menu,"photo-action-10").createAccessibilityNodeInfo().isChecked()!=histogram);tapMenu(10);until(()->(Boolean)call(editor,"isHistogramVisible")==histogram,"histogram restore");waitEditor();
        stage="manual-slider-endpoints";mainClick("editor-primary-3");frameFence();SeekBar manual=(SeekBar)get(editor,"adjustmentSlider");
        driveEdge(manual,false,"02-adjust-min");check("manual-min-model",manual.getProgress()==0&&amount(get(editor,"adjustments"),"BRIGHTNESS")==-100);
        driveEdge(manual,true,"03-adjust-max");check("manual-max-model",manual.getProgress()==manual.getMax()&&amount(get(editor,"adjustments"),"BRIGHTNESS")==100);
        stage="quick-slider-endpoints";mainClick("editor-primary-0");mainClick("editor-quick-style-1");waitQuick();SeekBar quick=(SeekBar)mainTag("editor-quick-slider");
        driveEdge(quick,false,"04-quick-min");check("quick-min-model",(Integer)get(get(editor,"quickState"),"amount")==0);
        driveEdge(quick,true,"05-quick-max");check("quick-max-model",(Integer)get(get(editor,"quickState"),"amount")==100);
        mainClick("editor-primary-2");mainClick("editor-portrait-section-0");waitQuick();SeekBar portrait=(SeekBar)mainTag("editor-portrait-quick-slider");
        driveEdge(portrait,false,null);check("portrait-min-model",(Integer)get(get(editor,"quickState"),"amount")==0);
        driveEdge(portrait,true,null);check("portrait-max-model",(Integer)get(get(editor,"quickState"),"amount")==100);
        mainClick("editor-primary-1");frameFence();SeekBar filter=(SeekBar)get(editor,"slider");int filterBefore=filter.getProgress();ui(()->filter.setProgress(0));frameFence();thumbInside(filter,"filter-min");ui(()->filter.setProgress(filter.getMax()));frameFence();thumbInside(filter,"filter-max");ui(()->filter.setProgress(filterBefore));
        stage="menu-reset-and-delegates";mainClick("editor-primary-3");driveEdge(manual,true,null);Object before=get(editor,"adjustments"),local=get(editor,"localEdits");
        openMenu();tapMenu(40);waitEditor();check("reset-colour-callback",(Boolean)call(get(editor,"adjustments"),"isNeutral"));check("reset-colour-keeps-portrait",local.equals(get(editor,"localEdits")));
        ui(()->call(editor,"restoreHistory",false));waitEditor();check("reset-colour-undo",before.equals(get(editor,"adjustments")));
        openMenu();tapMenu(41);waitEditor();check("restore-original-clears-edit",(Boolean)call(get(editor,"adjustments"),"isNeutral")&&(Boolean)call(get(editor,"localEdits"),"isNeutral"));
        ui(()->call(editor,"restoreHistory",false));waitEditor();check("restore-original-undo",before.equals(get(editor,"adjustments"))&&local.equals(get(editor,"localEdits")));
        Object realHost=get(editor,"host");Class<?> host=cls("ui.PhotoFilterEditor$Host");AtomicReference<Object[]> copied=new AtomicReference<>();AtomicInteger undone=new AtomicInteger();
        Object proxy=java.lang.reflect.Proxy.newProxyInstance(loader,new Class<?>[]{host},(p,m,a)->{if(m.getName().equals("copyAdjustments")){copied.set(a);return null;}if(m.getName().equals("undoAdjustmentCopy")){undone.incrementAndGet();return null;}return m.invoke(realHost,a);});
        ui(()->set(editor,"host",proxy));try{openMenu();tapMenu(30);until(()->copied.get()!=null,"copy delegate");check("copy-uses-current-adjustments",before.equals(copied.get()[0]));openMenu();tapMenu(31);check("undo-copy-delegate",undone.get()==1);}finally{ui(()->set(editor,"host",realHost));}
        menu=openMenu();View stale=menuTag(menu,"photo-action-41");Object shown=get(panel,"localDetail");ui(()->{set(panel,"localDetail",null);try{stale.performClick();}finally{set(panel,"localDetail",shown);}});check("stale-photo-callback-suppressed",before.equals(get(editor,"adjustments"))&&local.equals(get(editor,"localEdits")));
        menu=openMenu();final android.widget.PopupWindow previous=menu;ui(()->call(panel,"renderDetail"));frameFence();check("menu-closes-with-anchor",!previous.isShowing());editor=get(panel,"filterEditor");until(()->(Boolean)call(editor,"isReady"),"editor after render");waitEditor();
        check("source-file-unchanged",sha(fixture).equals(sourceSha));stage="complete";
    }
    private android.widget.PopupWindow openMenu()throws Exception{mainClick("editor-photo-more");until(()->get(panel,"photoActionsPopup") instanceof android.widget.PopupWindow&&((android.widget.PopupWindow)get(panel,"photoActionsPopup")).isShowing(),"menu window");frameFence();return(android.widget.PopupWindow)get(panel,"photoActionsPopup");}
    private View menuTag(android.widget.PopupWindow p,String tag){View v=find(p.getContentView(),tag);if(v==null)throw new AssertionError("Missing menu "+tag);return v;}
    private void tapMenu(int id)throws Exception{android.widget.PopupWindow p=(android.widget.PopupWindow)get(panel,"photoActionsPopup");tap(menuTag(p,"photo-action-"+id));until(()->!p.isShowing(),"menu dismiss");}
    private void reveal(View target)throws Exception{ui(()->{for(android.view.ViewParent p=target.getParent();p instanceof View;p=p.getParent())if(p instanceof ScrollView){ScrollView sc=(ScrollView)p;sc.fling(0);ViewGroup c=(ViewGroup)sc.getChildAt(0);Rect r=new Rect();target.getDrawingRect(r);c.offsetDescendantRectToMyCoords(target,r);int y=sc.getScrollY();if(r.top<y)y=r.top;else if(r.bottom>y+sc.getHeight())y=r.bottom-sc.getHeight();sc.scrollTo(0,y);}});frameFence();until(()->unclipped(target),"menu row reachable");}
    private void tap(View target)throws Exception{reveal(target);Rect r=bounds(target);long t=SystemClock.uptimeMillis();input(t,MotionEvent.ACTION_DOWN,r.exactCenterX(),r.exactCenterY());SystemClock.sleep(40);input(t,MotionEvent.ACTION_UP,r.exactCenterX(),r.exactCenterY());frameFence();}
    private void driveEdge(SeekBar bar,boolean maximum,String screenshot)throws Exception{until(bar::isEnabled,"slider enabled");reveal(bar);Rect r=bounds(bar);long t=SystemClock.uptimeMillis();float x=maximum?r.right-1:r.left+1;input(t,MotionEvent.ACTION_DOWN,r.exactCenterX(),r.exactCenterY());input(t,MotionEvent.ACTION_MOVE,x,r.exactCenterY());frameFence();check("exact-endpoint-"+bar.getTag()+"-"+maximum,bar.getProgress()==(maximum?bar.getMax():0));thumbInside(bar,"pressed-"+bar.getTag()+"-"+maximum);if(screenshot!=null)screenshot(screenshot);input(t,MotionEvent.ACTION_UP,x,r.exactCenterY());waitEditor();}
    private void thumbInside(SeekBar bar,String name)throws Exception{Rect thumb=new Rect(bar.getThumb().getBounds());thumb.offset(bar.getPaddingLeft()-bar.getThumbOffset(),bar.getPaddingTop());check("complete-thumb-"+name,thumb.left>=1&&thumb.right<=bar.getWidth()-1&&thumb.top>=0&&thumb.bottom<=bar.getHeight());}
    private int amount(Object a,String name)throws Exception{Object p=Enum.valueOf((Class)cls("ncp.PhotoAdjustments$Parameter"),name);return((Number)call(a,"get",p)).intValue();}
    private int dp(int v){return Math.round(v*activity.getResources().getDisplayMetrics().density);}
    private Rect bounds(View v)throws Exception{Rect r=new Rect();ui(()->v.getGlobalVisibleRect(r));return r;}
    private boolean unclipped(View v){Rect r=new Rect();return v.isShown()&&v.getGlobalVisibleRect(r)&&r.width()>=v.getWidth()-1&&r.height()>=v.getHeight()-1;}
    private void frameFence()throws Exception{CountDownLatch done=new CountDownLatch(1);ui(()->Choreographer.getInstance().postFrameCallback(t->Choreographer.getInstance().postFrameCallback(n->done.countDown())));if(!done.await(4,TimeUnit.SECONDS))throw new AssertionError("UI frame fence");}
    private void input(long down,int action,float x,float y){MotionEvent e=MotionEvent.obtain(down,SystemClock.uptimeMillis(),action,x,y,0);e.setSource(InputDevice.SOURCE_TOUCHSCREEN);getUiAutomation().injectInputEvent(e,true);e.recycle();}
    private Object store()throws Exception{String owner=(String)stat("cc.huevia.ui.PhotoFilterEditor","accountOwner",activity);Object store=cls("album.PhotoEditStore").getConstructor(File.class,String.class).newInstance(activity.getFilesDir(),owner);draftFile=new File((File)get(store,"root"),sourceSha+".draft");return store;}
    private int getParameter(Object retouch,String name)throws Exception{String type=retouch.getClass().getName().endsWith("PhotoAdjustments")?"ncp.PhotoAdjustments$Parameter":"ncp.PortraitRetouch$Parameter";Object p=Enum.valueOf((Class)cls(type),name);return((Number)call(retouch,"get",p)).intValue();}
    private Object face()throws Exception{return call(parent,"face");}
    private void click(String name)throws Exception{ui(()->tag(parent,name).performClick());}
    private void touch2(View v,long down,int action,float x,float y){MotionEvent event=MotionEvent.obtain(down,SystemClock.uptimeMillis(),action,v.getWidth()*x,v.getHeight()*y,0);try{v.dispatchTouchEvent(event);}finally{event.recycle();}}
    private Dialog portrait()throws Exception{ui(()->call(editor,"showPortrait"));until(()->get(editor,"popup") instanceof Dialog&&((Dialog)get(editor,"popup")).isShowing(),"portrait dialog");Dialog d=(Dialog)get(editor,"popup");dialogs.add(d);parent=d;waitPortrait();return d;}
    private void waitPortrait()throws Exception{until(()->get(parent,"completedPreview")!=null&&(Boolean)call(get(parent,"queue"),"isIdle")&&tag(parent,"portrait-apply").isEnabled(),"precision portrait preview");}
    private void waitEditor()throws Exception{until(()->(Boolean)call(get(editor,"previewQueue"),"isIdle"),"main preview");ui(()->{});}
    private void drain()throws Exception{CountDownLatch done=new CountDownLatch(1);ui(()->call(editor,"afterPendingSaves",(Runnable)done::countDown));if(!done.await(12,TimeUnit.SECONDS))throw new AssertionError("draft save drain timeout");}
    private File fixture()throws Exception{Bitmap b;try(InputStream in=getContext().getAssets().open("astronaut.png")){b=BitmapFactory.decodeStream(in);}if(++fixtureNumber>1){Matrix mirror=new Matrix();mirror.setScale(-1,1);Bitmap flipped=Bitmap.createBitmap(b,0,0,b.getWidth(),b.getHeight(),mirror,true);if(flipped!=b)b.recycle();b=flipped;}File dir=new File(getTargetContext().getExternalFilesDir(Environment.DIRECTORY_PICTURES),"camera-album");dir.mkdirs();File f=new File(dir,"photo-menu136-"+UUID.randomUUID()+"__Skin.JPG");try(OutputStream out=new FileOutputStream(f)){b.compress(Bitmap.CompressFormat.JPEG,97,out);}finally{b.recycle();}android.media.ExifInterface e=new android.media.ExifInterface(f.getPath());e.setAttribute("ImageDescription","photo-menu136 private QA "+UUID.randomUUID());e.saveAttributes();return f;}
    private Object photo()throws Exception{Constructor<?> c=cls("album.DownloadedPhoto").getDeclaredConstructor(File.class,String.class);c.setAccessible(true);return c.newInstance(fixture,"MENU136.JPG");}
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
