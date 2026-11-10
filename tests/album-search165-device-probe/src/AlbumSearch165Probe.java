package cc.huevia.albumsearch165qa;

import android.app.*;
import android.content.*;
import android.graphics.*;
import android.graphics.drawable.BitmapDrawable;
import android.net.Uri;
import android.os.*;
import android.provider.MediaStore;
import android.util.LruCache;
import android.view.*;
import android.widget.*;
import java.io.*;
import java.lang.reflect.*;
import java.util.*;
import org.json.*;

/** Owned emulator only; seeds and removes only this run's MediaStore rows. No app data reset. */
public final class AlbumSearch165Probe extends Instrumentation {
    private Bundle args; private Activity activity; private File output;
    private final List<Uri> owned=new ArrayList<>(); private final JSONArray checks=new JSONArray();
    private JSONObject report=new JSONObject(); private Throwable failure; private String originalAppearance;
    @Override public void onCreate(Bundle value){args=value;start();}
    @Override public void onStart(){try {
        check("ranchu".equals(Build.HARDWARE)||"goldfish".equals(Build.HARDWARE),"owned-emulator");
        String run=args.getString("runId");check(run!=null&&run.matches("[A-Za-z0-9.-]{8,100}"),"safe-run-id");
        output=new File(getTargetContext().getExternalFilesDir(null),"album-search165/"+run);check(output.mkdirs(),"new-evidence-directory");
        long version=getTargetContext().getPackageManager().getPackageInfo("cc.huevia",0).getLongVersionCode();report.put("versionCode",version);report.put("sdk",Build.VERSION.SDK_INT);
        if(args.containsKey("appearance")){originalAppearance=cc.huevia.ui.AppAppearance.mode(getTargetContext());cc.huevia.ui.AppAppearance.setMode(getTargetContext(),args.getString("appearance"));}
        boolean visualOnly="true".equals(args.getString("visualOnly"));
        if(!visualOnly)seed(run);
        activity=startActivitySync(new Intent(Intent.ACTION_MAIN).setClassName("cc.huevia","cc.huevia.MainActivity").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK|Intent.FLAG_ACTIVITY_CLEAR_TASK));
        until(()->Boolean.TRUE.equals(get(activity,"ready")),"main-ready");
        report.put("dark",get(get(activity,"colors"),"dark"));
        if("dark".equals(args.getString("appearance")))check(Boolean.TRUE.equals(get(get(activity,"colors"),"dark")),"actual-app-dark-palette");
        if(visualOnly){
            ui(()->{set(activity,"settingsTab",false);set(activity,"albumTab",false);set(activity,"localAlbumTab",false);set(activity,"localTab",!"online".equals(args.getString("source")));call(activity,"render");});
            capture("presets-collapsed");
            ui(()->call(activity,"searchHomePresets"));SystemClock.sleep(300);
            EditText text=(EditText)get(activity,"homePresetSearchInput");check(text!=null&&text.hasFocus(),"inline-search-focus");
            ui(()->text.append(args.getString("query","胶片")));SystemClock.sleep(300);capture("presets-search-keyboard");
            ui(()->text.onEditorAction(android.view.inputmethod.EditorInfo.IME_ACTION_SEARCH));SystemClock.sleep(250);capture("presets-search-submitted");
            ui(()->call(activity,"goBack"));check(!Boolean.TRUE.equals(get(activity,"homePresetSearchExpanded")),"back-closes-search");return;
        }
        ui(()->{set(activity,"settingsTab",false);set(activity,"albumTab",false);set(activity,"localAlbumTab",true);call(activity,"render");});
        Object panel=get(activity,"localAlbum");ui(()->call(panel,"switchTab",true));
        until(()->!Boolean.TRUE.equals(get(panel,"loadingPhone"))&&((List<?>)get(panel,"phonePhotos")).size()>=36,"seed-visible-in-phone-album");
        ListView list=(ListView)get(panel,"list");
        ui(()->((LruCache<?,?>)get(panel,"thumbnails")).resize(2*1024*1024));
        SystemClock.sleep(1600);
        Map<String,View> previous=new HashMap<>(); Set<String> ready=new HashSet<>();int replacements=0,regressions=0,observed=0;
        long end=SystemClock.uptimeMillis()+6500;
        while(SystemClock.uptimeMillis()<end){
            Map<String,View> frame=new HashMap<>();ui(()->collect(list,frame));
            for(Map.Entry<String,View> e:frame.entrySet()){
                String key=e.getKey();View view=e.getValue();View old=previous.get(key);
                if(old!=null&&old!=view)replacements++;
                boolean bitmap=((ImageView)view).getDrawable() instanceof BitmapDrawable;
                if(ready.contains(key)&&!bitmap)regressions++;
                if(bitmap)ready.add(key);observed++;
            }
            previous=frame;SystemClock.sleep(70);
        }
        report.put("stationaryTileReplacements",replacements);report.put("readyToPlaceholderRegressions",regressions);report.put("observations",observed);report.put("readyKeys",ready.size());
        capture("phone-album-cache-pressure");
        if(version>=165){check(replacements==0,"cache-completions-keep-visible-tile-instances");check(regressions==0,"cache-eviction-does-not-clear-visible-photos");check(ready.size()>=6,"visible-thumbnails-eventually-complete");
            ui(()->list.setSelection(Math.min(8,list.getCount()-1)));SystemClock.sleep(1200);ui(()->list.setSelection(0));SystemClock.sleep(1200);
            Map<String,View> returned=new HashMap<>();ui(()->collect(list,returned));check(!returned.isEmpty(),"scroll-away-and-return-has-thumbnails");
            ui(()->{set(activity,"localAlbumTab",false);set(activity,"localTab",true);call(activity,"render");call(activity,"searchHomePresets");});
            EditText input=(EditText)get(activity,"homePresetSearchInput");check(input!=null&&input.isAttachedToWindow(),"search-expands-in-header");
            ui(()->input.setText("  no-match-165  "));SystemClock.sleep(400);
            check(get(activity,"homePresetSearchInput")==input,"live-search-keeps-input-instance");check(input.hasFocus(),"live-search-keeps-focus");check("  no-match-165  ".equals(get(activity,"homePresetQuery")),"raw-query-preserves-cursor-and-whitespace");
            check(find(activity.getWindow().getDecorView(),"preset-home-search-field")!=null,"inline-search-field-visible");capture("search-no-results");
            ui(()->((View)find(activity.getWindow().getDecorView(),"preset-home-search-clear")).performClick());SystemClock.sleep(250);check(input.length()==0,"clear-query");
            ui(()->input.append("film"));SystemClock.sleep(250);check(input.getSelectionEnd()==4,"typing-retains-cursor");capture("search-inline");
            ui(()->call(activity,"goBack"));check(!Boolean.TRUE.equals(get(activity,"homePresetSearchExpanded"))&&"".equals(get(activity,"homePresetQuery")),"back-collapses-and-clears-search");
            ui(()->call(activity,"searchHomePresets"));ui(()->find(activity.getWindow().getDecorView(),"preset-home-search-cancel").performClick());check(!Boolean.TRUE.equals(get(activity,"homePresetSearchExpanded")),"cancel-collapses-search");
        }
    }catch(Throwable t){failure=t;}finally{
        for(Uri uri:owned)try{getTargetContext().getContentResolver().delete(uri,null,null);}catch(Exception ignored){}
        if(originalAppearance!=null)cc.huevia.ui.AppAppearance.setMode(getTargetContext(),originalAppearance);
        try{report.put("pass",failure==null);report.put("checks",checks);report.put("failure",failure==null?JSONObject.NULL:failure.toString());if(output!=null)try(FileWriter out=new FileWriter(new File(output,"report.json"))){out.write(report.toString(2));}}catch(Exception ignored){}
        Bundle result=new Bundle();result.putString("stream",report.toString());finish(failure==null?Activity.RESULT_OK:Activity.RESULT_CANCELED,result);
    }}
    private void seed(String run)throws Exception{
        Bitmap image=Bitmap.createBitmap(1200,1000,Bitmap.Config.ARGB_8888);Canvas canvas=new Canvas(image);
        for(int n=0;n<42;n++){
            canvas.drawColor(Color.HSVToColor(new float[]{n*360f/42,.6f,.8f}));Paint p=new Paint();p.setColor(Color.WHITE);p.setTextSize(120);canvas.drawText("QA "+n,160,500,p);
            ContentValues values=new ContentValues();values.put(MediaStore.Images.Media.DISPLAY_NAME,"Huevia165-"+run+"-"+n+".jpg");values.put(MediaStore.Images.Media.MIME_TYPE,"image/jpeg");values.put(MediaStore.Images.Media.RELATIVE_PATH,"Pictures/Huevia165QA/"+run);values.put(MediaStore.Images.Media.IS_PENDING,1);
            Uri uri=getTargetContext().getContentResolver().insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI,values);if(uri==null)throw new IOException("seed insert");owned.add(uri);
            try(OutputStream out=getTargetContext().getContentResolver().openOutputStream(uri)){image.compress(Bitmap.CompressFormat.JPEG,90,out);}values.clear();values.put(MediaStore.Images.Media.IS_PENDING,0);getTargetContext().getContentResolver().update(uri,values,null,null);
        }image.recycle();
    }
    private void collect(View view,Map<String,View> result){
        if(view instanceof ImageView&&view.getTag() instanceof String&&view.getParent() instanceof View){String tag=(String)view.getTag();if(tag.contains("content://"))result.put(tag,view);}
        if(view instanceof ViewGroup)for(int i=0;i<((ViewGroup)view).getChildCount();i++)collect(((ViewGroup)view).getChildAt(i),result);
    }
    private View find(View v,String tag){if(tag.equals(v.getTag()))return v;if(v instanceof ViewGroup)for(int i=0;i<((ViewGroup)v).getChildCount();i++){View hit=find(((ViewGroup)v).getChildAt(i),tag);if(hit!=null)return hit;}return null;}
    private void capture(String name)throws Exception{
        waitForIdleSync();android.view.accessibility.AccessibilityNodeInfo active=getUiAutomation().getRootInActiveWindow();
        Bitmap image=getUiAutomation().takeScreenshot();try(OutputStream out=new FileOutputStream(new File(output,name+".png"))){image.compress(Bitmap.CompressFormat.PNG,100,out);}image.recycle();
        String text=accessibilityText(active);report.put(name+"ActivePackage",active==null?JSONObject.NULL:String.valueOf(active.getPackageName()));
        report.put(name+"WindowText",text.length()>700?text.substring(0,700):text);
        check(!text.contains("isn't responding")&&!text.contains("未响应"),"no-system-ANR-over-"+name);
    }
    private String accessibilityText(android.view.accessibility.AccessibilityNodeInfo node){if(node==null)return "";StringBuilder text=new StringBuilder();if(node.getText()!=null)text.append(node.getText()).append(' ');for(int i=0;i<node.getChildCount();i++)text.append(accessibilityText(node.getChild(i)));return text.toString();}
    private void check(boolean ok,String name)throws Exception{checks.put(new JSONObject().put("name",name).put("pass",ok));if(!ok)throw new AssertionError(name);}
    private interface Work{void run()throws Exception;}private interface Condition{boolean test()throws Exception;}
    private void ui(Work task)throws Exception{Throwable[] error={null};runOnMainSync(()->{try{task.run();}catch(Throwable t){error[0]=t;}});if(error[0]!=null)throw new RuntimeException(error[0]);}
    private void until(Condition task,String name)throws Exception{long end=SystemClock.uptimeMillis()+30000;while(SystemClock.uptimeMillis()<end){if(task.test())return;SystemClock.sleep(50);}throw new AssertionError("Timeout "+name);}
    private static Object get(Object target,String name)throws Exception{Field f=target.getClass().getDeclaredField(name);f.setAccessible(true);return f.get(target);}
    private static void set(Object target,String name,Object value)throws Exception{Field f=target.getClass().getDeclaredField(name);f.setAccessible(true);f.set(target,value);}
    private static Object call(Object target,String name,Object...values)throws Exception{for(Method m:target.getClass().getDeclaredMethods())if(m.getName().equals(name)&&m.getParameterCount()==values.length){m.setAccessible(true);return m.invoke(target,values);}throw new NoSuchMethodException(name);}
}
