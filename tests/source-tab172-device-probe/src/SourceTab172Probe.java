package cc.huevia.sourcetab172qa;

import android.app.*;
import android.content.*;
import android.graphics.*;
import android.os.*;
import android.view.*;
import android.widget.*;
import cc.huevia.ui.SubcategorySwipeLayout;
import java.io.*;
import java.lang.reflect.*;
import java.util.concurrent.atomic.AtomicInteger;
import org.json.*;

/** Real GPU bitmap and optional software-canvas failure fixtures, not a physical HarmonyOS run. */
public final class SourceTab172Probe extends Instrumentation {
    private Bundle args; private Activity activity; private File output; private boolean baseline;
    private final JSONObject report=new JSONObject(); private final JSONArray checks=new JSONArray();
    private Bitmap hardware,software; private SubcategorySwipeLayout fixture;
    private final AtomicInteger selection=new AtomicInteger(); private FrameLayout root;
    @Override public void onCreate(Bundle b){args=b;start();}
    @Override public void onStart(){Throwable failure=null;try{
        check("ranchu".equals(Build.HARDWARE)||"goldfish".equals(Build.HARDWARE),"owned-emulator");
        String run=args.getString("runId");check(run!=null&&run.matches("[A-Za-z0-9.-]{8,100}"),"safe-run-id");
        output=new File(getTargetContext().getExternalFilesDir(null),"source-tab172/"+run);check(output.mkdirs(),"new-evidence-directory");
        long version=getTargetContext().getPackageManager().getPackageInfo("cc.huevia",0).getLongVersionCode();baseline=version==171;
        check(version==171||version==172,"expected-baseline-or-fixed-version");report.put("versionCode",version);report.put("sdk",Build.VERSION.SDK_INT);report.put("baseline",baseline);
        activity=startActivitySync(new Intent(Intent.ACTION_MAIN).setClassName("cc.huevia","cc.huevia.MainActivity").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK|Intent.FLAG_ACTIVITY_CLEAR_TASK));
        until(()->Boolean.TRUE.equals(get(activity,"ready")),"main-ready");
        software=Bitmap.createBitmap(32,32,Bitmap.Config.ARGB_8888);software.eraseColor(Color.rgb(95,150,210));hardware=software.copy(Bitmap.Config.HARDWARE,false);
        check(hardware!=null&&hardware.getConfig()==Bitmap.Config.HARDWARE,"actual-hardware-bitmap");
        root=(FrameLayout)activity.getWindow().getDecorView();
        exercise("hardware-bitmap",0,baseline);
        exercise("software-canvas-runtime",1,baseline);
        exercise("memory-pressure",2,false);
        exercise("ordinary-software-bitmap",3,false);
        actualPresetTab();
        report.put("scope","Installed shared source-tab component and actual MainActivity online source button. Real Bitmap.Config.HARDWARE cannot be drawn by a software Canvas; runtime-only and OOM fixtures are explicitly injected. Baseline reproduces missing protection; fixed candidate changes pages without an optional snapshot. Normal software capture retains animation. No physical HarmonyOS device or user crash trace obtained.");
    }catch(Throwable t){failure=t;try{report.put("failure",android.util.Log.getStackTraceString(t));}catch(Exception ignored){}}
    finally{try{if(activity!=null)ui(()->{removeFixture();activity.finish();});}catch(Throwable ignored){}
        if(hardware!=null&&!hardware.isRecycled())hardware.recycle();if(software!=null&&!software.isRecycled())software.recycle();
        try{report.put("pass",failure==null);report.put("checks",checks);report.put("candidateSha256",args.getString("candidateSha256"));if(output!=null)try(Writer w=new OutputStreamWriter(new FileOutputStream(new File(output,"report.json")),"UTF-8")){w.write(report.toString(2));}}catch(Exception ignored){}
        Bundle result=new Bundle();result.putString("result",report.toString());finish(failure==null?-1:0,result);}
    }
    private void exercise(String name,int kind,boolean expectFailure)throws Exception{
        ui(()->{removeFixture();selection.set(0);fixture=new SubcategorySwipeLayout(activity,selection::get,2,i->{},()->true);
            TextView anchor=new TextView(activity);anchor.setText("QA source controls");fixture.addView(anchor,new LinearLayout.LayoutParams(-1,90));fixture.setMotionAnchor(anchor);
            View image;
            if(kind==0||kind==3){ImageView view=new ImageView(activity);view.setImageBitmap(kind==0?hardware:software);image=view;}
            else image=new View(activity){@Override protected void onDraw(Canvas c){if(!c.isHardwareAccelerated()){if(kind==1)throw new IllegalStateException("QA unsupported software capture");throw new OutOfMemoryError("QA bounded allocation failure");}c.drawColor(Color.rgb(95,150,210));}};
            fixture.addView(image,new LinearLayout.LayoutParams(-1,0,1));root.addView(fixture,new FrameLayout.LayoutParams(-1,-1));});
        until(()->fixture.getWidth()>0&&fixture.getHeight()>150,"fixture-layout-"+name);SystemClock.sleep(100);
        Throwable error=attempt(()->SubcategorySwipeLayout.changeSource(fixture,0,1,()->selection.set(1),()->fixture));
        report.put(name+"Error",error==null?JSONObject.NULL:android.util.Log.getStackTraceString(error));
        if(expectFailure){check(error!=null,"baseline-reproduces-"+name);check(selection.get()==0,"baseline-change-blocked-"+name);}
        else{check(error==null,"no-uncaught-error-"+name);check(selection.get()==1,"source-change-completes-"+name);
            if(kind==3)check(get(fixture,"motion")!=null,"ordinary-source-retains-animation");else check(get(fixture,"motion")==null,"failed-snapshot-skips-only-animation-"+name);}
        SystemClock.sleep(900);check(!activity.isFinishing(),"activity-alive-"+name);ui(this::removeFixture);
    }
    private void actualPresetTab()throws Exception{
        ui(()->{set(activity,"settingsTab",false);set(activity,"albumTab",false);set(activity,"localAlbumTab",false);set(activity,"localTab",true);set(activity,"homePresetQuery","");call(activity,"render");});
        ViewGroup body=(ViewGroup)get(activity,"body");ImageView[] image={null};
        ui(()->{image[0]=new ImageView(activity);image[0].setImageBitmap(hardware);body.addView(image[0],new LinearLayout.LayoutParams(-1,150));});
        until(()->image[0].getWidth()>0&&image[0].getHeight()>0,"main-hardware-fixture-visible");SystemClock.sleep(150);
        View label=findText(body,"在线预设");
        while(label!=null&&!label.isClickable()&&label.getParent() instanceof View)label=(View)label.getParent();
        final View button=label;check(button!=null&&button.isClickable(),"actual-online-tab-button-found");
        Throwable error=attempt(()->button.performClick());report.put("actualOnlineTabError",error==null?JSONObject.NULL:android.util.Log.getStackTraceString(error));
        if(baseline){check(error!=null,"actual-online-tab-reproduces-baseline-error");check(Boolean.TRUE.equals(get(activity,"localTab")),"baseline-tab-cannot-complete");}
        else{check(error==null,"actual-online-tab-no-uncaught-error");check(Boolean.FALSE.equals(get(activity,"localTab")),"actual-online-tab-switch-completes");}
        capture(baseline?"baseline-tab-error":"fixed-online-tab");check(!activity.isFinishing(),"actual-main-remains-alive");
    }
    private void removeFixture()throws Exception{if(fixture!=null){call(fixture,"clearMotion");root.removeView(fixture);fixture=null;}}
    private View findText(View v,String value){if(v instanceof TextView&&value.contentEquals(((TextView)v).getText()))return v;if(v instanceof ViewGroup)for(int i=0;i<((ViewGroup)v).getChildCount();i++){View r=findText(((ViewGroup)v).getChildAt(i),value);if(r!=null)return r;}return null;}
    private void capture(String name)throws Exception{waitForIdleSync();Bitmap b=getUiAutomation().takeScreenshot();try(OutputStream out=new FileOutputStream(new File(output,name+".png"))){b.compress(Bitmap.CompressFormat.PNG,100,out);}b.recycle();}
    private interface Work{void run()throws Exception;}private interface Condition{boolean test()throws Exception;}
    private Throwable attempt(Work work){Throwable[] e={null};runOnMainSync(()->{try{work.run();}catch(Throwable t){e[0]=t;}});return e[0];}
    private void ui(Work work)throws Exception{Throwable t=attempt(work);if(t!=null)throw new RuntimeException(t);}
    private void until(Condition c,String name)throws Exception{long end=SystemClock.uptimeMillis()+30000;while(SystemClock.uptimeMillis()<end){if(c.test())return;SystemClock.sleep(40);}throw new AssertionError("Timeout "+name);}
    private void check(boolean ok,String name)throws Exception{checks.put(new JSONObject().put("name",name).put("pass",ok));if(!ok)throw new AssertionError(name);}
    private static Object get(Object o,String name)throws Exception{Field f=o.getClass().getDeclaredField(name);f.setAccessible(true);return f.get(o);}
    private static void set(Object o,String name,Object value)throws Exception{Field f=o.getClass().getDeclaredField(name);f.setAccessible(true);f.set(o,value);}
    private static Object call(Object o,String name,Object...values)throws Exception{for(Method m:o.getClass().getDeclaredMethods())if(m.getName().equals(name)&&m.getParameterCount()==values.length){m.setAccessible(true);return m.invoke(o,values);}throw new NoSuchMethodException(name);}
}
