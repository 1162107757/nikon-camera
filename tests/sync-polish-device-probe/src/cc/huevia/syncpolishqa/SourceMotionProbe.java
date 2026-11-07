package cc.huevia.syncpolishqa;

import android.animation.ValueAnimator;
import android.app.*;
import android.content.*;
import android.graphics.*;
import android.os.*;
import android.view.*;
import android.widget.*;
import java.io.*;
import java.lang.reflect.*;
import java.util.*;
import java.util.concurrent.atomic.*;
import java.util.function.*;
import org.json.*;

/** Real source handlers/input, held native intermediate frames, interruption, and animator-scale zero. */
public final class SourceMotionProbe extends Instrumentation {
    private Activity activity;private ClassLoader loader;private Bundle args;private File output;private String mode;
    private final JSONArray checks=new JSONArray(),frames=new JSONArray();
    @Override public void onCreate(Bundle values){super.onCreate(values);args=values==null?new Bundle():values;start();}
    @Override public void onStart(){JSONObject report=new JSONObject();Bundle result=new Bundle();try{
        check(Build.HARDWARE.equals("ranchu")||Build.HARDWARE.equals("goldfish"),"owned-emulator-only");loader=getTargetContext().getClassLoader();mode=args.getString("mode","phone");output=new File(getTargetContext().getExternalFilesDir(null),"source-motion150/"+mode);output.mkdirs();stat("ui.AppAppearance","setMode",getTargetContext(),mode.equals("dark")?"dark":"light");makePhoto();
        activity=startActivitySync(new Intent(Intent.ACTION_MAIN).setComponent(new ComponentName("cc.huevia","cc.huevia.MainActivity")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK|Intent.FLAG_ACTIVITY_CLEAR_TASK));until(()->(Boolean)get(activity,"ready"),"main ready");
        ui(()->{set(activity,"busy",false);set(activity,"catalogLoaded",true);call(activity,"switchRoot",0);call(activity,"selectPresetSource",false);});settle();
        if(mode.equals("reduced"))reduced();else if(args.getString("captureOnly","false").equals("true")){captureCycle();touchTargets();}else{preset();sync();album();touchTargets();}
        report.put("pass",true);
    }catch(Throwable failure){try{StringWriter stack=new StringWriter();failure.printStackTrace(new PrintWriter(stack));report.put("pass",false).put("failure",stack.toString());if(activity!=null)capture("failure");}catch(Exception ignored){}}
    finally{try{report.put("mode",mode).put("checks",checks).put("frames",frames);if(output!=null)try(OutputStream out=new FileOutputStream(new File(output,"report.json"))){out.write(report.toString(2).getBytes(java.nio.charset.StandardCharsets.UTF_8));}result.putString("report",report.toString());}catch(Exception ignored){}finish(report.optBoolean("pass")?Activity.RESULT_OK:Activity.RESULT_CANCELED,result);}}
    private View presets(){try{return (View)get(activity,"body");}catch(Exception e){throw new RuntimeException(e);}}
    private void preset()throws Exception{
        check(ValueAnimator.areAnimatorsEnabled(),"normal-motion-enabled");View root=presets();int[] anchor=anchor(root);float threshold=Math.max(dp(48),Math.min(dp(80),root.getWidth()*.12f));
        Drag shortDrag=down(root);move(shortDrag,-threshold*.72f);check(offset(root)<0&&!(Boolean)get(activity,"localTab"),"short-drag-follows-without-selecting");up(shortDrag,-threshold*.72f);Object rebound=pauseRebound(root);capture("01-short-return");ui(()->((ValueAnimator)rebound).resume());settle();clean(root,"short-return");check(!(Boolean)get(activity,"localTab"),"short-drag-returns-to-original-source");
        Drag longDrag=down(root);move(longDrag,-root.getWidth()*.40f);check(offset(root)<-dp(24)&&!(Boolean)get(activity,"localTab"),"long-drag-follows-before-source-change");check(Arrays.equals(anchor,anchor(root)),"preset-header-fixed-during-drag");capture("02-preset-follow");up(longDrag,-root.getWidth()*.40f);
        Object left=pauseMotion(this::presets,1,"preset-left");check((Boolean)get(activity,"localTab"),"left-release-selects-my-once");check(Arrays.equals(anchor,anchor(presets())),"preset-header-fixed-during-transition");capture("03-preset-slide-left");resume(left);settle();clean(presets(),"preset-left");
        click(presets(),"在线预设");Object right=pauseMotion(this::presets,-1,"preset-click-right");capture("04-preset-click-right");resume(right);settle();check(!(Boolean)get(activity,"localTab"),"preset-click-restores-online");
        click(presets(),"我的预设");Object first=pauseMotion(this::presets,1,"rapid-first");Bitmap oldFrame=(Bitmap)get(first,"frame");click(presets(),"在线预设");check(oldFrame.isRecycled(),"interrupted-transition-releases-old-snapshot");Object second=pauseMotion(this::presets,-1,"rapid-reverse");click(presets(),"在线预设");check(get(presets(),"motion")==second,"same-source-click-does-not-restart-motion");capture("05-rapid-reverse");resume(second);settle();clean(presets(),"rapid-reverse");
        Drag cancel=down(presets());move(cancel,-threshold);cancel(cancel);settle();check(!(Boolean)get(activity,"localTab"),"cancel-does-not-switch-source");clean(presets(),"cancel");
        click(presets(),"我的预设");Object interrupted=pauseMotion(this::presets,1,"navigate-away");Bitmap frame=(Bitmap)get(interrupted,"frame");ui(()->call(activity,"switchRoot",2));resume(interrupted);settle();check(frame.isRecycled(),"navigation-away-releases-snapshot");
    }
    private void sync()throws Exception{
        ui(()->call(activity,"switchRoot",1));settle();Object panel=get(activity,"album");ui(()->{set(panel,"localLoaded",true);call(panel,"chooseTab",false);});settle();Supplier<View> source=()->{try{return (View)get(panel,"root");}catch(Exception e){throw new RuntimeException(e);}};
        int[] anchor=anchor(source.get());click(source.get(),"边拍边传");Object live=pauseMotion(source,1,"sync-live");check((Boolean)get(panel,"liveTab"),"sync-click-selects-live");check(Arrays.equals(anchor,anchor(source.get())),"sync-selector-stays-fixed");capture("06-sync-live");resume(live);settle();
        click(source.get(),"已下载");Object downloaded=pauseMotion(source,1,"sync-downloaded");ui(()->call(panel,"changed"));resume(downloaded);SystemClock.sleep(30);ui(()->((ValueAnimator)get(downloaded,"animator")).pause());check(get(source.get(),"motion")==downloaded,"sync-data-rebuild-retains-transition");capture("07-sync-rebound-root");resume(downloaded);settle();clean(source.get(),"sync-downloaded");
        Drag edge=down(source.get());move(edge,-source.get().getWidth()*.45f);up(edge,-source.get().getWidth()*.45f);settle();check((Boolean)get(panel,"downloadedTab"),"sync-last-source-does-not-wrap");clean(source.get(),"sync-edge");
        click(source.get(),"相机照片");Object back=pauseMotion(source,-1,"sync-nonadjacent-right");capture("08-sync-right");resume(back);settle();check(!(Boolean)get(panel,"downloadedTab")&&!(Boolean)get(panel,"liveTab"),"nonadjacent-click-selects-camera-directly");
    }
    private void album()throws Exception{
        ui(()->call(activity,"switchRoot",3));settle();Object panel=get(activity,"localAlbum");ui(()->call(panel,"switchTab",false));settle();Supplier<View> source=()->{try{return (View)get(panel,"root");}catch(Exception e){throw new RuntimeException(e);}};
        View cached=source.get();int[] anchor=anchor(cached);click(source.get(),"手机相册");Object phone=pauseMotion(source,1,"album-phone");check((Boolean)get(panel,"phone"),"album-click-selects-phone");check(cached==source.get(),"cached-album-root-supported");check(Arrays.equals(anchor,anchor(source.get())),"album-source-strip-fixed");capture("09-album-phone");resume(phone);settle();
        Drag right=down(source.get());move(right,source.get().getWidth()*.40f);up(right,source.get().getWidth()*.40f);Object app=pauseMotion(source,-1,"album-app");capture("10-album-right");resume(app);settle();check(!(Boolean)get(panel,"phone"),"album-swipe-selects-application");clean(source.get(),"album-app");
        click(source.get(),"手机相册");Object selectionMotion=pauseMotion(source,1,"album-enter-selection");Bitmap selectionFrame=(Bitmap)get(selectionMotion,"frame");ui(()->{set(panel,"selecting",true);call(panel,"updateState");});resume(selectionMotion);settle();check(selectionFrame.isRecycled()&&get(source.get(),"motion")==null,"entering-selection-stops-inflight-page-motion");ui(()->{set(panel,"selecting",false);call(panel,"updateState");call(panel,"switchTab",false);});settle();
        ui(()->{set(panel,"selecting",true);call(panel,"updateState");});Drag disabled=down(source.get());move(disabled,-source.get().getWidth()*.40f);up(disabled,-source.get().getWidth()*.40f);settle();check(!(Boolean)get(panel,"phone")&&offset(source.get())==0,"selection-mode-has-no-page-motion");ui(()->{set(panel,"selecting",false);call(panel,"updateState");});
    }
    private void touchTargets()throws Exception{
        AtomicInteger index=new AtomicInteger(),taps=new AtomicInteger();AtomicReference<ViewGroup> root=new AtomicReference<>();AtomicReference<Dialog> dialog=new AtomicReference<>();
        try{
            ui(()->{Dialog window=new Dialog(activity);dialog.set(window);ViewGroup view=(ViewGroup)cls("ui.SubcategorySwipeLayout").getConstructor(Context.class,IntSupplier.class,int.class,IntConsumer.class,BooleanSupplier.class).newInstance(activity,(IntSupplier)index::get,2,(IntConsumer)index::set,(BooleanSupplier)()->true);root.set(view);TextView header=new TextView(activity);header.setText("QA pinned selector");view.addView(header,new LinearLayout.LayoutParams(-1,dp(48)));call(view,"setMotionAnchor",header);Button button=new Button(activity);button.setText("QA body action");button.setOnClickListener(v->taps.incrementAndGet());view.addView(button,new LinearLayout.LayoutParams(-1,0,1));window.setContentView(view);window.show();window.getWindow().setLayout(-1,dp(300));});settle();
            ui(()->stat("ui.SubcategorySwipeLayout","changeSource",root.get(),0,1,(Runnable)()->index.set(1),(Supplier<View>)root::get));Object value=pauseMotion(()->root.get(),1,"moving-body-tap");Drag moving=down(root.get());up(moving,0);check(taps.get()==0,"moving-body-does-not-deliver-stale-button-tap");resume(value);settle();Drag settled=down(root.get());up(settled,0);settle();check(taps.get()==1,"settled-body-action-receives-tap");
        }finally{ui(()->{if(dialog.get()!=null)dialog.get().dismiss();});}
    }
    private void captureCycle()throws Exception{
        click(presets(),"我的预设");Object preset=pauseMotion(this::presets,1,"preset-left");capture("03-preset-slide-left");resume(preset);settle();
        ui(()->call(activity,"switchRoot",1));settle();Object sync=get(activity,"album");ui(()->call(sync,"chooseTab",false));settle();Supplier<View> syncRoot=()->{try{return (View)get(sync,"root");}catch(Exception e){throw new RuntimeException(e);}};click(syncRoot.get(),"边拍边传");Object live=pauseMotion(syncRoot,1,"sync-live");capture("06-sync-live");resume(live);settle();
        ui(()->call(activity,"switchRoot",3));settle();Object album=get(activity,"localAlbum");ui(()->call(album,"switchTab",false));settle();Supplier<View> albumRoot=()->{try{return (View)get(album,"root");}catch(Exception e){throw new RuntimeException(e);}};click(albumRoot.get(),"手机相册");Object phone=pauseMotion(albumRoot,1,"album-phone");capture("09-album-phone");resume(phone);settle();clean(albumRoot.get(),"capture-album");
    }
    private void reduced()throws Exception{
        check(!ValueAnimator.areAnimatorsEnabled(),"system-disabled-animation-observed");Drag drag=down(presets());move(drag,-presets().getWidth()*.4f);check(offset(presets())==0,"disabled-motion-has-no-drag-translation");up(drag,-presets().getWidth()*.4f);settle();check((Boolean)get(activity,"localTab"),"disabled-motion-preserves-swipe-source-change");clean(presets(),"reduced-preset");
        ui(()->call(activity,"switchRoot",1));settle();Object sync=get(activity,"album");click((View)get(sync,"root"),"已下载");settle();check((Boolean)get(sync,"downloadedTab"),"disabled-motion-preserves-sync-click");clean((View)get(sync,"root"),"reduced-sync");
        ui(()->call(activity,"switchRoot",3));settle();Object album=get(activity,"localAlbum");click((View)get(album,"root"),"手机相册");settle();check((Boolean)get(album,"phone"),"disabled-motion-preserves-album-click");clean((View)get(album,"root"),"reduced-album");capture("11-reduced-motion");
    }
    private Object pauseMotion(Supplier<View> source,int direction,String name)throws Exception{
        AtomicReference<Object> paused=new AtomicReference<>();long limit=SystemClock.uptimeMillis()+1500;
        while(SystemClock.uptimeMillis()<limit&&paused.get()==null){ui(()->{Object value=get(source.get(),"motion");if(value!=null){ValueAnimator animator=(ValueAnimator)get(value,"animator");float p=((Number)get(value,"progress")).floatValue();if(animator!=null&&p>.015f&&p<.99f){animator.pause();source.get().invalidate();paused.set(value);frames.put(new JSONObject().put("name",name).put("progress",p).put("direction",get(value,"direction")).put("width",source.get().getWidth()).put("anchorBottom",((int[])anchor(source.get()))[3]).put("nativeFrameHeld",true));}}});if(paused.get()==null)SystemClock.sleep(8);}
        Object value=paused.get();check(value!=null,name+"-has-intermediate-motion");check(((Number)get(value,"direction")).intValue()==direction,name+"-correct-direction");Bitmap frame=(Bitmap)get(value,"frame");check((long)frame.getWidth()*frame.getHeight()<=2000000,name+"-snapshot-budget");return value;
    }
    private Object pauseRebound(View root)throws Exception{AtomicReference<ValueAnimator> value=new AtomicReference<>();until(()->{ui(()->{ValueAnimator animator=(ValueAnimator)get(root,"rebound");if(animator!=null&&animator.isStarted()&&animator.getCurrentPlayTime()>0){animator.pause();value.set(animator);}});return value.get()!=null;},"rebound starts");check(offset(root)<0,"short-release-animates-return");return value.get();}
    private void resume(Object motion)throws Exception{ui(()->{ValueAnimator animator=(ValueAnimator)get(motion,"animator");if(animator!=null)animator.resume();});}
    private void clean(View root,String name)throws Exception{check(get(root,"motion")==null&&get(root,"dragFrame")==null&&offset(root)==0,name+"-settles-without-snapshot-or-offset");}
    private float offset(View root)throws Exception{return ((Number)get(root,"dragOffset")).floatValue();}
    private int[] anchor(View root)throws Exception{View view=(View)get(root,"motionAnchor");int[] p=new int[2];view.getLocationOnScreen(p);return new int[]{p[0],p[1],view.getWidth(),p[1]+view.getHeight()};}
    private void click(View root,String label)throws Exception{ui(()->{View found=findText(root,label);while(found!=null&&!found.isClickable()&&found.getParent() instanceof View)found=(View)found.getParent();if(found==null||!found.performClick())throw new AssertionError("Missing click "+label);});}
    private View findText(View view,String text){if(view instanceof TextView&&text.contentEquals(((TextView)view).getText()))return view;if(view instanceof ViewGroup)for(int i=0;i<((ViewGroup)view).getChildCount();i++){View result=findText(((ViewGroup)view).getChildAt(i),text);if(result!=null)return result;}return null;}
    private static final class Drag{long down;float x,y;}
    private Drag down(View root)throws Exception{int[] p=new int[2];root.getLocationOnScreen(p);Drag drag=new Drag();drag.down=SystemClock.uptimeMillis();drag.x=p[0]+root.getWidth()*.5f;int top=((Number)call(root,"motionTop")).intValue();drag.y=p[1]+top+(root.getHeight()-top)*.62f;input(drag,MotionEvent.ACTION_DOWN,0);return drag;}
    private void move(Drag drag,float dx)throws Exception{for(int i=1;i<=8;i++){input(drag,MotionEvent.ACTION_MOVE,dx*i/8);SystemClock.sleep(12);}SystemClock.sleep(20);}
    private void up(Drag drag,float dx){input(drag,MotionEvent.ACTION_UP,dx);}
    private void cancel(Drag drag){input(drag,MotionEvent.ACTION_CANCEL,0);}
    private void input(Drag drag,int action,float dx){MotionEvent event=MotionEvent.obtain(drag.down,SystemClock.uptimeMillis(),action,drag.x+dx,drag.y,0);event.setSource(InputDevice.SOURCE_TOUCHSCREEN);getUiAutomation().injectInputEvent(event,true);event.recycle();}
    private void makePhoto()throws Exception{File dir=new File(getTargetContext().getFilesDir(),"pictures/camera-album");dir.mkdirs();try(InputStream in=getContext().getAssets().open("astronaut.png");OutputStream out=new FileOutputStream(new File(dir,"QA150__QA_SOURCE.JPG"))){Bitmap image=BitmapFactory.decodeStream(in);image.compress(Bitmap.CompressFormat.JPEG,95,out);image.recycle();}}
    private void capture(String name)throws Exception{waitForIdleSync();SystemClock.sleep(100);Bitmap image=getUiAutomation().takeScreenshot();try(OutputStream out=new FileOutputStream(new File(output,name+".png"))){image.compress(Bitmap.CompressFormat.PNG,100,out);}image.recycle();}
    private int dp(float value){return Math.round(value*activity.getResources().getDisplayMetrics().density);}private interface Work{void run()throws Exception;}private interface Condition{boolean test()throws Exception;}
    private void settle()throws Exception{waitForIdleSync();SystemClock.sleep(320);}private void until(Condition condition,String name)throws Exception{long limit=SystemClock.uptimeMillis()+40000;while(SystemClock.uptimeMillis()<limit){if(condition.test())return;SystemClock.sleep(8);}throw new AssertionError("Timeout "+name);}private void check(boolean ok,String name)throws Exception{checks.put(new JSONObject().put("name",name).put("pass",ok));if(!ok)throw new AssertionError(name);}
    private void ui(Work work)throws Exception{AtomicReference<Throwable> error=new AtomicReference<>();runOnMainSync(()->{try{work.run();}catch(Throwable t){error.set(t);}});if(error.get()!=null)throw new RuntimeException(error.get());}
    private Class<?> cls(String value)throws Exception{return loader.loadClass("cc.huevia."+value);}private Field field(Class<?> type,String name)throws Exception{for(Class<?> c=type;c!=null;c=c.getSuperclass())try{Field f=c.getDeclaredField(name);f.setAccessible(true);return f;}catch(NoSuchFieldException ignored){}throw new NoSuchFieldException(name);}private Object get(Object target,String name)throws Exception{return field(target.getClass(),name).get(target);}private void set(Object target,String name,Object value)throws Exception{field(target.getClass(),name).set(target,value);}private Object call(Object target,String name,Object...values)throws Exception{return invoke(target.getClass(),target,name,values);}private Object stat(String type,String name,Object...values)throws Exception{return invoke(cls(type),null,name,values);}
    private Object invoke(Class<?> type,Object target,String name,Object[] values)throws Exception{for(Method m:type.getDeclaredMethods())if(m.getName().equals(name)&&m.getParameterCount()==values.length){m.setAccessible(true);try{return m.invoke(target,values);}catch(IllegalArgumentException mismatch){}catch(InvocationTargetException e){throw new RuntimeException(e.getCause());}}throw new NoSuchMethodException(name);}
}
