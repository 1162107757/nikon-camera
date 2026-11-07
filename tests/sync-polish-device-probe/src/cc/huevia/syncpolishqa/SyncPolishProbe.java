package cc.huevia.syncpolishqa;

import android.app.*;
import android.content.*;
import android.graphics.*;
import android.os.*;
import android.view.*;
import android.widget.*;
import org.json.*;
import java.io.*;
import java.lang.reflect.*;
import java.util.*;
import java.util.concurrent.atomic.AtomicReference;

/** Emulator-only production Views, owned JPEG fixtures, no camera or server writes. */
public final class SyncPolishProbe extends Instrumentation {
    private Activity activity; private ClassLoader loader; private Object album; private Bundle args;
    private File output; private final List<File> fixtures=new ArrayList<>(); private final JSONArray checks=new JSONArray();
    private String priorAppearance; private SharedPreferences albumPreferences; private boolean hadOldFilter, oldFilter;
    @Override public void onCreate(Bundle values){super.onCreate(values);args=values==null?new Bundle():values;start();}
    @Override public void onStart(){
        JSONObject report=new JSONObject();Bundle result=new Bundle();
        try{
            check(Build.HARDWARE.equals("ranchu")||Build.HARDWARE.equals("goldfish"),"emulator-only");
            loader=getTargetContext().getClassLoader();
            priorAppearance=(String)stat("ui.AppAppearance","mode",getTargetContext());
            stat("ui.AppAppearance","setMode",getTargetContext(),"dark".equals(args.getString("mode"))?"dark":"light");
            albumPreferences=getTargetContext().getSharedPreferences("album-panel",Context.MODE_PRIVATE);
            hadOldFilter=albumPreferences.contains("starred-downloads");oldFilter=albumPreferences.getBoolean("starred-downloads",false);
            albumPreferences.edit().putBoolean("starred-downloads",true).commit();
            output=new File(getTargetContext().getExternalFilesDir(null),"sync-header139/"+args.getString("mode","phone"));output.mkdirs();
            activity=startActivitySync(new Intent(Intent.ACTION_MAIN).setComponent(new ComponentName("cc.huevia","cc.huevia.MainActivity")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK|Intent.FLAG_ACTIVITY_CLEAR_TASK));
            until(()->(Boolean)get(activity,"ready"),"main ready");album=get(activity,"album");
            check(!albumPreferences.contains("starred-downloads"),"old-star-only-filter-retired");
            ui(()->{set(activity,"busy",false);set(activity,"catalogLoaded",true);set(activity,"localTab",false);call(activity,"render");});settle();
            for(String source:new String[]{"我的预设","在线预设","我的预设","在线预设"})ui(()->{clickText(source);atRest("preset-source-"+source);});
            screenshot("01-preset-source");
            ui(()->call(activity,"switchRoot",1));settle();
            ui(()->call(album,"chooseTab",false));settle();
            View remote=findTag(root(),"sync-remote-capture"),connect=findTag(root(),"sync-connect-camera");
            check(remote!=null&&remote.isClickable(),"remote-entry-present-and-clickable");
            check(connect!=null&&connect.isClickable(),"connect-action-present-and-clickable");
            Object palette=get(album,"palette");
            Bitmap screen=getUiAutomation().takeScreenshot();try{
                check(backgroundSample(screen,remote,8,remote.getHeight()/density()/2)==(Integer)get(palette,"container"),"remote-uses-theme-container");
                check(backgroundSample(screen,connect,connect.getWidth()/density()/2,6)==(Integer)get(palette,"primaryContainer"),"connect-uses-soft-accent");
            }finally{screen.recycle();}
            screenshot("02-sync-camera");
            ui(()->{call(album,"choosePhotoLive");atRest("sync-live");});settle();
            ui(()->{call(album,"chooseTab",false);atRest("sync-camera");});settle();
            until(()->(Boolean)get(album,"starsReady")&&!(Boolean)get(album,"loadingDownloads"),"star and download readers idle");
            List<Object> photos=photos();
            ui(()->{
                List<Object> all=(List<Object>)get(album,"allDownloads");all.clear();all.addAll(photos);
                Set<String> stars=new HashSet<>();stars.add((String)call(album,"starKey",photos.get(0)));set(album,"starredKeys",stars);
                set(album,"localLoaded",true);call(album,"applyDownloadFilter");call(album,"chooseTab",true);atRest("sync-downloads");
            });settle();
            TextView count=(TextView)findTag(root(),"sync-photo-count");
            check(count!=null&&"共 3 张".contentEquals(count.getText()),"downloads-show-total-count");
            float scaled=activity.getResources().getDisplayMetrics().scaledDensity;
            check(Math.abs(count.getTextSize()/scaled-12)<.2&&(count.getTypeface()==null||!count.getTypeface().isBold()),"download-count-small-normal-weight");
            check(((List<?>)get(album,"downloads")).size()==3,"all-downloads-visible-with-existing-star-record");
            check(!containsText(root(),"星标")&&!containsText(root(),"筛选"),"download-list-has-no-star-filter");
            List<View> tiles=new ArrayList<>();collectTiles(root(),tiles);check(tiles.size()==3,"three-native-photo-tiles");
            for(View tile:tiles)check(((View)get(tile,"favorite")).getVisibility()==View.GONE,"download-thumbnail-no-star");
            TextView raw=(TextView)findTag(root(),"sync-raw-files"),select=(TextView)findTag(root(),"sync-select-photos");
            check(raw!=null&&"RAW 原片".contentEquals(raw.getText())&&select!=null&&"选择".contentEquals(select.getText()),"compact-header-actions-readable");
            check(raw.getCurrentTextColor()==count.getCurrentTextColor()&&select.getCurrentTextColor()==count.getCurrentTextColor(),"header-actions-share-count-text-color");
            for(TextView action:new TextView[]{raw,select}){
                check(action.getHeight()>=48*density()-.5f&&action.getWidth()>=48*density()-.5f,"header-action-accessible-touch-target");
                check(action.getLayout()!=null&&action.getLayout().getLineCount()==1&&action.getLayout().getLineWidth(0)<=action.getWidth()-action.getCompoundPaddingLeft()-action.getCompoundPaddingRight()+1,"header-action-text-fits-one-line");
            }
            check(count.getWidth()>count.getPaint().measureText(count.getText().toString()),"count-keeps-visible-width");
            screenshot("03-downloads");
            ui(()->select.performClick());settle();
            TextView cancel=(TextView)findTag(root(),"sync-select-photos");
            check((Boolean)get(album,"selectionMode")&&cancel!=null&&"取消".contentEquals(cancel.getText())&&cancel.isSelected(),"selection-button-enters-active-state");
            check(cancel.getCurrentTextColor()==count.getCurrentTextColor(),"cancel-shares-count-text-color");
            screenshot("05-selection");
            ui(()->cancel.performClick());settle();
            check(!(Boolean)get(album,"selectionMode")&&"选择".contentEquals(((TextView)findTag(root(),"sync-select-photos")).getText()),"cancel-restores-normal-browsing");
            ui(()->{call(album,"openLocal",photos.get(0));atRest("download-photo-open");});
            until(()->get(album,"viewerStar")!=null,"download photo viewer");settle();
            check(((View)get(album,"viewerStar")).getVisibility()==View.GONE,"download-detail-no-star-action");
            View more=findTag(root(),"editor-photo-more");
            if(more!=null){ui(()->more.performClick());settle();PopupWindow popup=(PopupWindow)get(album,"photoActionsPopup");
                check(popup!=null&&!containsText(popup.getContentView(),"收藏照片")&&!containsText(popup.getContentView(),"取消收藏"),"download-menu-no-favourite-action");ui(()->call(album,"dismissPhotoActions"));}
            screenshot("04-download-detail");
            ui(()->call(album,"goBack"));settle();
            ui(()->call(activity,"switchRoot",3));settle();
            Object local=get(activity,"localAlbum");
            ui(()->{call(local,"switchTab",true);atRest("album-phone-source");});settle();
            ui(()->{call(local,"switchTab",false);atRest("album-app-source");});settle();
            // A project still owns its star filter; the removed download filter never changes it.
            ui(()->{set(album,"liveTab",true);set(album,"downloadedTab",false);});
            check((Boolean)call(album,"showStarsForCurrentPhoto"),"project-star-context-retained");
            report.put("pass",true);
        }catch(Throwable error){try{StringWriter trace=new StringWriter();error.printStackTrace(new PrintWriter(trace));report.put("pass",false).put("failure",trace.toString());if(output!=null&&activity!=null)screenshot("failure");}catch(Exception ignored){}}
        finally{
            try{if(activity!=null){ui(()->activity.finish());waitForIdleSync();}if(priorAppearance!=null)stat("ui.AppAppearance","setMode",getTargetContext(),priorAppearance);if(albumPreferences!=null){SharedPreferences.Editor edit=albumPreferences.edit();if(hadOldFilter)edit.putBoolean("starred-downloads",oldFilter);else edit.remove("starred-downloads");edit.commit();}}catch(Exception ignored){}
            for(File fixture:fixtures)fixture.delete();
            try{report.put("checks",checks);if(output!=null)try(OutputStream out=new FileOutputStream(new File(output,"report.json"))){out.write(report.toString(2).getBytes(java.nio.charset.StandardCharsets.UTF_8));}result.putString("report",report.toString());}catch(Exception ignored){}
            finish(report.optBoolean("pass")?Activity.RESULT_OK:Activity.RESULT_CANCELED,result);
        }
    }
    private List<Object> photos()throws Exception{
        Bitmap image;try(InputStream in=getContext().getAssets().open("astronaut.png")){image=BitmapFactory.decodeStream(in);}
        File directory=new File(getTargetContext().getExternalFilesDir(Environment.DIRECTORY_PICTURES),"camera-album");directory.mkdirs();
        Constructor<?> ctor=cls("album.DownloadedPhoto").getDeclaredConstructor(File.class,String.class);ctor.setAccessible(true);List<Object> result=new ArrayList<>();
        try{for(int i=0;i<3;i++){File photo=new File(directory,"QA_SYNC139_"+UUID.randomUUID()+".JPG");fixtures.add(photo);try(OutputStream out=new FileOutputStream(photo)){image.compress(Bitmap.CompressFormat.JPEG,93,out);}photo.setLastModified(System.currentTimeMillis()-i*86400000L);result.add(ctor.newInstance(photo,"QA_SYNC139_"+(i+1)+".JPG"));}}finally{image.recycle();}return result;
    }
    private void atRest(String label)throws Exception{
        View body=(View)get(activity,"transitioningContent");Map<?,?> running=(Map<?,?>)field(cls("ui.PageTransitions"),"RUNNING").get(null);
        check(body!=null&&body.getTranslationX()==0&&body.getAlpha()==1&&!running.containsKey(body),"instant-internal-switch-"+label);
    }
    private int backgroundSample(Bitmap screenshot,View view,float xDp,float yDp){int[] xy=new int[2];view.getLocationOnScreen(xy);return screenshot.getPixel(xy[0]+Math.round(xDp*density()),xy[1]+Math.round(yDp*density()));}
    private float density(){return activity.getResources().getDisplayMetrics().density;}
    private View root(){return activity.getWindow().getDecorView();}
    private void clickText(String text){View target=findText(root(),text);if(target==null)throw new AssertionError("Missing "+text);while(!target.isClickable()&&target.getParent() instanceof View)target=(View)target.getParent();target.performClick();}
    private View findTag(View v,String tag){if(tag.equals(v.getTag()))return v;if(v instanceof ViewGroup)for(int i=0;i<((ViewGroup)v).getChildCount();i++){View result=findTag(((ViewGroup)v).getChildAt(i),tag);if(result!=null)return result;}return null;}
    private TextView findText(View v,String text){if(v instanceof TextView&&text.contentEquals(((TextView)v).getText()))return(TextView)v;if(v instanceof ViewGroup)for(int i=0;i<((ViewGroup)v).getChildCount();i++){TextView result=findText(((ViewGroup)v).getChildAt(i),text);if(result!=null)return result;}return null;}
    private boolean containsText(View v,String part){if(v.getVisibility()!=View.VISIBLE)return false;if(v instanceof TextView&&((TextView)v).getText().toString().contains(part))return true;if(v instanceof ViewGroup)for(int i=0;i<((ViewGroup)v).getChildCount();i++)if(containsText(((ViewGroup)v).getChildAt(i),part))return true;return false;}
    private void collectTiles(View v,List<View> out){if(v.getVisibility()!=View.VISIBLE)return;if(v.getClass().getSimpleName().equals("ThumbTile"))out.add(v);if(v instanceof ViewGroup)for(int i=0;i<((ViewGroup)v).getChildCount();i++)collectTiles(((ViewGroup)v).getChildAt(i),out);}
    private void screenshot(String name)throws Exception{
        settle();android.view.accessibility.AccessibilityNodeInfo active=getUiAutomation().getRootInActiveWindow();
        if(active!=null&&!active.findAccessibilityNodeInfosByText("Viewing full screen").isEmpty()){
            for(android.view.accessibility.AccessibilityNodeInfo button:active.findAccessibilityNodeInfosByText("Got it"))button.performAction(android.view.accessibility.AccessibilityNodeInfo.ACTION_CLICK);
            settle();
        }
        Bitmap image=getUiAutomation().takeScreenshot();try(OutputStream out=new FileOutputStream(new File(output,name+".png"))){image.compress(Bitmap.CompressFormat.PNG,100,out);}finally{image.recycle();}
    }
    private void settle()throws Exception{waitForIdleSync();SystemClock.sleep(450);}
    private interface Work{void run()throws Exception;}private interface Condition{boolean test()throws Exception;}
    private void ui(Work work)throws Exception{AtomicReference<Throwable> error=new AtomicReference<>();runOnMainSync(()->{try{work.run();}catch(Throwable t){error.set(t);}});if(error.get()!=null)throw new RuntimeException(error.get());}
    private void until(Condition condition,String label)throws Exception{long end=SystemClock.uptimeMillis()+25000;while(SystemClock.uptimeMillis()<end){if(condition.test())return;SystemClock.sleep(30);}throw new AssertionError("Timeout "+label);}
    private void check(boolean pass,String label)throws Exception{checks.put(new JSONObject().put("name",label).put("pass",pass));if(!pass)throw new AssertionError(label);}
    private Class<?> cls(String name)throws Exception{return loader.loadClass("cc.huevia."+name);}private Field field(Class<?> type,String name)throws Exception{for(Class<?> c=type;c!=null;c=c.getSuperclass())try{Field f=c.getDeclaredField(name);f.setAccessible(true);return f;}catch(NoSuchFieldException ignored){}throw new NoSuchFieldException(name);}
    private Object get(Object target,String name)throws Exception{return field(target.getClass(),name).get(target);}private void set(Object target,String name,Object value)throws Exception{field(target.getClass(),name).set(target,value);}
    private Object call(Object target,String name,Object...args)throws Exception{return invoke(target.getClass(),target,name,args);}private Object stat(String type,String name,Object...args)throws Exception{return invoke(cls(type),null,name,args);}
    private Object invoke(Class<?> type,Object target,String name,Object[] args)throws Exception{for(Method method:type.getDeclaredMethods())if(method.getName().equals(name)&&method.getParameterCount()==args.length){method.setAccessible(true);try{return method.invoke(target,args);}catch(IllegalArgumentException mismatch){continue;}catch(InvocationTargetException error){throw new RuntimeException(error.getCause());}}throw new NoSuchMethodException(name);}
}
