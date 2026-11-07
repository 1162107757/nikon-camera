package cc.huevia.syncpolishqa;

import android.app.*;
import android.content.*;
import android.graphics.*;
import android.net.Uri;
import android.os.*;
import android.provider.MediaStore;
import android.view.*;
import android.widget.*;
import org.json.*;
import java.io.*;
import java.lang.reflect.*;
import java.util.*;
import java.util.concurrent.atomic.AtomicReference;

/** Production native album UI, isolated owned fixtures, emulator only. */
public final class AlbumOverviewProbe extends Instrumentation {
    private Activity activity; private Object album,repository; private ClassLoader loader; private Bundle args;
    private File output,fixtureDir; private String priorAppearance;
    private final List<File> files=new ArrayList<>(); private final List<Uri> media=new ArrayList<>(); private final JSONArray checks=new JSONArray();
    @Override public void onCreate(Bundle values){super.onCreate(values);args=values==null?new Bundle():values;start();}
    @Override public void onStart(){
        JSONObject report=new JSONObject();Bundle result=new Bundle();
        try {
            check(Build.HARDWARE.equals("ranchu")||Build.HARDWARE.equals("goldfish"),"emulator-only");
            loader=getTargetContext().getClassLoader(); priorAppearance=(String)stat("ui.AppAppearance","mode",getTargetContext());
            stat("ui.AppAppearance","setMode",getTargetContext(),"dark".equals(args.getString("mode"))?"dark":"light");
            output=new File(getTargetContext().getExternalFilesDir(null),"album-floating141/"+args.getString("mode","phone"));output.mkdirs();
            makeFixtures();
            activity=startActivitySync(new Intent(Intent.ACTION_MAIN).setComponent(new ComponentName("cc.huevia","cc.huevia.MainActivity")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK|Intent.FLAG_ACTIVITY_CLEAR_TASK));
            until(()->(Boolean)get(activity,"ready"),"main ready");
            ui(()->{set(activity,"busy",false);set(activity,"catalogLoaded",true);call(activity,"switchRoot",3);});
            album=get(activity,"localAlbum");repository=get(album,"repository");until(()->!(Boolean)get(album,"loadingApp"),"initial App scan");
            ui(()->{List<File> dirs=(List<File>)get(repository,"photoDirectories");dirs.clear();dirs.add(fixtureDir);call(album,"refreshApp");});
            until(()->!(Boolean)get(album,"loadingApp")&&((List<?>)get(album,"appPhotos")).size()>=3,"owned App fixture scan");settle();
            View sources=findTag(root(),"local-album-sources"),track=findTag(root(),"local-album-source-track"),summary=findTag(root(),"local-album-summary"),more=findTag(root(),"local-album-more");
            check(sources!=null&&track!=null&&summary!=null&&more!=null,"source-summary-and-title-action-present");
            check(((ViewGroup)sources).getChildCount()==1&&((ViewGroup)track).getChildCount()==2,"source-row-only-has-two-segments");
            check(bottom(more)<=top(sources)&&bottom(sources)<=top(summary),"more-source-and-actions-have-separate-rows");
            check(("共 "+((List<?>)get(album,"appPhotos")).size()+" 张").contentEquals(((TextView)findTag(root(),"local-album-count")).getText()),"App-shows-total-count");
            View picker=findTag(root(),"local-album-picker"),select=findTag(root(),"local-album-select");
            check(picker.getVisibility()==View.GONE&&!hasText(root(),"添加照片"),"App-has-no-persistent-add-action");
            check(select.isShown()&&select.isClickable(),"App-selection-remains-directly-accessible");
            for(String tag:new String[]{"local-album-source-app","local-album-source-phone","local-album-select","local-album-more"})accessible(findTag(root(),tag),tag);
            check(((TextView)select).getCurrentTextColor()==((TextView)findTag(root(),"local-album-count")).getCurrentTextColor(),"selection-shares-secondary-count-color");
            until(()->((android.util.LruCache<?,?>)get(album,"thumbnails")).size()>0,"decoded App thumbnails");
            check(firstPhotoVisible(),"first-photo-tile-is-fully-visible");capture("01-app");
            View firstBefore=firstTile();int firstWidth=firstBefore.getWidth(),firstHeight=firstBefore.getHeight();
            ui(()->select.performClick());settle();
            check((Boolean)get(album,"selecting")&&((View)get(album,"selectionBar")).isShown(),"selection-opens-batch-actions");
            assertDock(false);
            check(firstTile().getWidth()==firstWidth&&firstTile().getHeight()==firstHeight,"selection-keeps-thumbnail-size");
            check(!((Button)get(album,"batchButton")).isEnabled()&&!((Button)get(album,"exportButton")).isEnabled()&&"未选择".contentEquals(((TextView)get(album,"selectionCount")).getText()),"zero-selection-disables-edit-and-save");capture("02-zero-selection");
            ui(()->((Button)get(album,"phoneTab")).performClick());check(!(Boolean)get(album,"phone"),"source-click-cannot-discard-active-selection");
            chooseFirst(3);
            check(((Set<?>)get(album,"selected")).size()==3&&((Button)get(album,"batchButton")).isEnabled()&&((Button)get(album,"exportButton")).isEnabled(),"selected-photos-enable-edit-and-save");
            assertDock(false);capture("02-selection");
            Object editor=get(activity,"localPhotoEditor");ui(()->((Button)get(album,"exportButton")).performClick());
            until(()->get(editor,"batchQuickSaveDialog")!=null&&((Dialog)get(editor,"batchQuickSaveDialog")).isShowing(),"real save settings opened");
            Dialog saveSettings=(Dialog)get(editor,"batchQuickSaveDialog");View closeSave=findDescription(saveSettings.getWindow().getDecorView(),"取消保存，返回照片");check(closeSave!=null,"save-settings-cancel-action-is-reachable");ui(()->closeSave.performClick());until(()->!saveSettings.isShowing(),"save settings cancelled");settle();
            check((Boolean)get(album,"selecting")&&((Set<?>)get(album,"selected")).size()==3&&((View)get(album,"selectionDock")).isShown(),"cancel-save-settings-keeps-selected-photos-and-dock");
            ui(()->clickText("取消"));settle();check(!(Boolean)get(album,"selecting")&&((Set<?>)get(album,"selected")).isEmpty(),"cancel-clears-selection-and-restores-browsing");
            check(findTag(root(),"root-floating-navigation")!=null&&((View)get(album,"summaryRow")).isShown(),"cancel-restores-navigation-and-summary");
            ui(()->findTag(root(),"local-album-select").performClick());settle();systemBackGesture();until(()->!(Boolean)get(album,"selecting"),"system back gesture exits selection");settle();
            check(!(Boolean)get(album,"selecting")&&findTag(root(),"root-floating-navigation")!=null,"system-back-exits-selection-and-restores-navigation");
            ui(()->{findTag(root(),"local-album-select").performClick();call(album,"beginImport");});settle();
            int pending=((Number)get(album,"importRequest")).intValue();check("准备中".contentEquals(((TextView)get(album,"selectionCount")).getText()),"preparing-state-stays-in-single-dock");
            ui(()->findTag(root(),"local-album-cancel-selection").performClick());settle();
            check(!(Boolean)get(album,"importing")&&!(Boolean)get(album,"selecting")&&(Boolean)call(album,"cancelImport",pending)&&findTag(root(),"root-floating-navigation")!=null,"cancel-preparation-invalidates-request-and-restores-navigation");
            ui(()->findTag(root(),"local-album-more").performClick());settle();
            android.view.accessibility.AccessibilityNodeInfo popup=getUiAutomation().getRootInActiveWindow();
            check(popup!=null&&!popup.findAccessibilityNodeInfosByText("刷新").isEmpty()&&!popup.findAccessibilityNodeInfosByText("RAW 显影").isEmpty(),"title-overflow-keeps-refresh-and-RAW");capture("03-more");tapTitleOutsidePopup();settle();
            ui(()->{((List<File>)get(repository,"photoDirectories")).clear();call(album,"refreshApp");});until(()->!(Boolean)get(album,"loadingApp")&&((List<?>)get(album,"appPhotos")).isEmpty(),"empty App source");settle();
            check(findTag(root(),"local-album-picker").getVisibility()==View.GONE&&hasText(root(),"浏览手机照片"),"empty-App-offers-source-navigation-not-import");
            View recovery=(View)get(album,"permissionButton");Rect recoveryVisible=new Rect();
            check(recovery.getGlobalVisibleRect(recoveryVisible)&&recoveryVisible.height()>=recovery.getHeight()-1&&recoveryVisible.width()>=recovery.getWidth()-1&&recovery.getHeight()>=48*density()-.5f,"empty-App-recovery-label-and-entire-target-visible");capture("04-app-empty");
            ui(()->((Button)get(album,"permissionButton")).performClick());
            until(()->(Boolean)get(album,"phone")&&!(Boolean)get(album,"loadingPhone"),"phone source via empty-state action");settle();atRest();
            String access=call(repository,"access").toString();report.put("access",access);
            if("NONE".equals(access)){check(hasText(root(),"允许访问照片")&&((List<?>)get(album,"phonePhotos")).isEmpty()&&findTag(root(),"local-album-picker").isShown(),"denied-phone-access-keeps-explicit-authorization-and-picker");accessible(findTag(root(),"local-album-picker"),"permission-only-picker");}
            else {check(((List<?>)get(album,"phonePhotos")).size()>=3,"phone-source-reads-owned-published-media");check(findTag(root(),"local-album-picker").getVisibility()==View.GONE,"authorized-phone-has-no-persistent-picker");}
            if("PARTIAL".equals(access))check("手机 · 部分".contentEquals(((TextView)findTag(root(),"local-album-source-phone")).getText()),"limited-permission-scope-is-visible-in-source-label");
            for(String tag:new String[]{"local-album-source-app","local-album-source-phone","local-album-picker","local-album-select"}){View v=findTag(root(),tag);if(v.isShown())textFits((TextView)v,tag);}
            capture("05-phone");
            if("NONE".equals(access)){cancelPicker();check(!(Boolean)get(album,"importing")&&call(repository,"access").toString().equals(access),"cancelled-picker-imports-nothing-and-keeps-access");}
            else {
                ui(()->findTag(root(),"local-album-select").performClick());settle();chooseFirst(3);assertDock(true);capture("06-phone-selection");
                ListView photosList=(ListView)get(album,"list");ui(()->photosList.setSelection(photosList.getAdapter().getCount()-1));settle();
                List<?> phoneItems=(List<?>)call(album,"current");View lastPhoto=findDescription(root(),(String)call(phoneItems.get(phoneItems.size()-1),"name"));Rect lastVisible=new Rect();
                check(lastPhoto!=null&&lastPhoto.getGlobalVisibleRect(lastVisible)&&lastVisible.height()>=lastPhoto.getHeight()-1&&bottom(lastPhoto)<=top((View)get(album,"selectionDock"))-8*density(),"last-phone-photo-scrolls-fully-above-floating-dock");
                ui(()->photosList.setSelection(0));settle();
                ui(()->((Button)get(album,"batchButton")).performClick());
                until(()->get(editor,"workspaceActions")!=null&&((Dialog)get(editor,"workspaceActions")).isShowing(),"real phone batch editor menu opened");
                check(!(Boolean)get(album,"importing")&&!(Boolean)get(album,"selecting"),"real-batch-dispatch-finishes-preparation-once");Dialog workspace=(Dialog)get(editor,"workspaceActions");ui(()->findTag(workspace.getWindow().getDecorView(),"batch-actions-close").performClick());settle();
                check(findTag(root(),"root-floating-navigation")!=null,"dismiss-batch-menu-restores-normal-gallery-navigation");
            }
            report.put("pass",true);
        }catch(Throwable failure){try{StringWriter trace=new StringWriter();failure.printStackTrace(new PrintWriter(trace));report.put("pass",false).put("failure",trace.toString());if(output!=null&&activity!=null)capture("failure");}catch(Exception ignored){}}
        finally{
            try{if(activity!=null){ui(()->activity.finish());waitForIdleSync();}if(priorAppearance!=null)stat("ui.AppAppearance","setMode",getTargetContext(),priorAppearance);}catch(Exception ignored){}
            for(Uri uri:media)try{getTargetContext().getContentResolver().delete(uri,null,null);}catch(Exception ignored){}for(File file:files)file.delete();
            try{report.put("checks",checks);if(output!=null)try(OutputStream out=new FileOutputStream(new File(output,"report.json"))){out.write(report.toString(2).getBytes(java.nio.charset.StandardCharsets.UTF_8));}result.putString("report",report.toString());}catch(Exception ignored){}
            finish(report.optBoolean("pass")?Activity.RESULT_OK:Activity.RESULT_CANCELED,result);
        }
    }
    private void makeFixtures()throws Exception{
        fixtureDir=new File(getTargetContext().getFilesDir(),"pictures/camera-album");fixtureDir.mkdirs();
        Bitmap image;try(InputStream in=getContext().getAssets().open("astronaut.png")){image=BitmapFactory.decodeStream(in);}
        try{for(int i=1;i<=9;i++){
            int quality=88+((i-1)%3+1)*3;
            if(i<=3){String name="QA_ALBUM141_"+i+"_"+UUID.randomUUID()+".JPG";File file=new File(fixtureDir,name);files.add(file);try(OutputStream out=new FileOutputStream(file)){image.compress(Bitmap.CompressFormat.JPEG,quality,out);}}
            ContentValues values=new ContentValues();values.put(MediaStore.Images.Media.DISPLAY_NAME,"QA_ALBUM141_"+UUID.randomUUID()+".JPG");values.put(MediaStore.Images.Media.MIME_TYPE,"image/jpeg");values.put(MediaStore.Images.Media.IS_PENDING,1);
            Uri uri=getTargetContext().getContentResolver().insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI,values);if(uri==null)throw new IOException("No fixture media URI");media.add(uri);
            try(OutputStream out=getTargetContext().getContentResolver().openOutputStream(uri)){image.compress(Bitmap.CompressFormat.JPEG,quality,out);}values.clear();values.put(MediaStore.Images.Media.IS_PENDING,0);getTargetContext().getContentResolver().update(uri,values,null,null);
        }}finally{image.recycle();}
    }
    private void cancelPicker()throws Exception{
        AtomicReference<Intent> observed=new AtomicReference<>();ActivityMonitor monitor=new ActivityMonitor(){@Override public ActivityResult onStartActivity(Intent intent){if(Intent.ACTION_OPEN_DOCUMENT.equals(intent.getAction())){observed.set(new Intent(intent));return new ActivityResult(Activity.RESULT_CANCELED,null);}return null;}};
        addMonitor(monitor);try{ui(()->findTag(root(),"local-album-picker").performClick());until(()->observed.get()!=null,"native document-picker dispatch");settle();}finally{removeMonitor(monitor);}
        Intent intent=observed.get();String[] mime=intent.getStringArrayExtra(Intent.EXTRA_MIME_TYPES);
        check(Intent.ACTION_OPEN_DOCUMENT.equals(intent.getAction())&&intent.hasCategory(Intent.CATEGORY_OPENABLE)&&intent.getBooleanExtra(Intent.EXTRA_ALLOW_MULTIPLE,false)&&mime!=null&&Arrays.asList(mime).containsAll(Arrays.asList("image/jpeg","image/png")),"small-picker-dispatches-openable-multiple-JPEG-PNG-intent");
    }
    private void systemBackGesture()throws Exception{
        int width=activity.getResources().getDisplayMetrics().widthPixels,y=activity.getResources().getDisplayMetrics().heightPixels/2;
        try(InputStream in=new ParcelFileDescriptor.AutoCloseInputStream(getUiAutomation().executeShellCommand("input swipe 1 "+y+" "+Math.max(120,width/3)+" "+y+" 250"))){byte[] buffer=new byte[256];while(in.read(buffer)!=-1){}}
    }
    private void tapTitleOutsidePopup()throws Exception{
        View title=findTag(root(),"local-album-titlebar");int[] xy=new int[2];title.getLocationOnScreen(xy);int x=xy[0]+Math.round(40*density()),y=xy[1]+title.getHeight()/2;
        try(InputStream in=new ParcelFileDescriptor.AutoCloseInputStream(getUiAutomation().executeShellCommand("input tap "+x+" "+y))){byte[] buffer=new byte[256];while(in.read(buffer)!=-1){}}
    }
    private View firstTile()throws Exception{Object item=((List<?>)call(album,"current")).get(0);return findDescription(root(),(String)call(item,"name"));}
    private void chooseFirst(int count)throws Exception{for(int i=0;i<count;i++){Object item=((List<?>)call(album,"current")).get(i);String name=(String)call(item,"name");View tile=findDescription(root(),name);check(tile!=null,"owned-photo-tile-is-reachable");ui(()->tile.performClick());settle();}}
    private boolean firstPhotoVisible()throws Exception{View tile=firstTile();if(tile==null)return false;Rect visible=new Rect();return tile.getGlobalVisibleRect(visible)&&visible.height()>=tile.getHeight()-1;}
    private void assertDock(boolean phone)throws Exception{
        View dock=(View)get(album,"selectionDock"),bar=(View)get(album,"selectionBar");Rect visible=new Rect();
        check(dock.isShown()&&dock.getParent()==get(album,"body")&&Math.abs(dock.getHeight()/density()-56)<.6&&dock.getGlobalVisibleRect(visible)&&visible.height()>=dock.getHeight()-1,"floating-dock-is56dp-and-fully-inside-safe-content");
        check(findTag(root(),"root-floating-navigation")==null&&findTag(root(),"local-album-more")==null&&((View)get(album,"summaryRow")).getVisibility()==View.GONE,"selection-replaces-navigation-and-removes-duplicate-top-controls");
        check(!((Button)get(album,"phoneTab")).isEnabled()&&!((Button)get(album,"appTab")).isEnabled()&&"相册".equals(call(album,"title")),"selection-locks-source-and-keeps-stable-title");
        check(bar instanceof LinearLayout&&((LinearLayout)bar).getOrientation()==LinearLayout.HORIZONTAL,"dock-actions-stay-on-one-row");
        View indicator=findTag(root(),"local-album-selection-indicator");check(indicator instanceof ImageView&&Math.abs(indicator.getWidth()/density()-22)<.6&&!hasText(root(),"选择"),"photo-selection-uses-small-circles-not-text-blocks");
        check(((View)get(album,"exportButton")).getVisibility()==(phone?View.GONE:View.VISIBLE)&&((Button)get(album,"batchButton")).getText().toString().equals(phone?"批量编辑":"编辑"),"source-specific-save-and-edit-actions-retained");
        for(String field:new String[]{"cancelButton","batchButton","exportButton"}){Button b=(Button)get(album,field);if(b.isShown()){accessible(b,field);check(top(b)>=top(dock)&&bottom(b)<=bottom(dock),"dock-target-stays-inside-material");}}
        TextView counter=(TextView)get(album,"selectionCount");textFits(counter,"selection-counter");check(counter.getCurrentTextColor()==((Button)get(album,"cancelButton")).getCurrentTextColor(),"dock-secondary-actions-share-counter-color");
    }
    private void accessible(View v,String label)throws Exception{check(v!=null&&v.getWidth()>=48*density()-.5f&&v.getHeight()>=48*density()-.5f&&v.isClickable(),"48dp-click-target-"+label);if(v instanceof TextView)textFits((TextView)v,label);}
    private void textFits(TextView v,String label)throws Exception{check(v.getLayout()!=null&&v.getLayout().getLineCount()==1&&v.getLayout().getEllipsisCount(0)==0&&v.getLayout().getLineWidth(0)<=v.getWidth()-v.getCompoundPaddingLeft()-v.getCompoundPaddingRight()+1,"single-line-label-fits-"+label);}
    private void atRest()throws Exception{View body=(View)get(activity,"transitioningContent");check(body!=null&&body.getAlpha()==1&&body.getTranslationX()==0,"source-switch-has-no-sideways-animation");}
    private float density(){return activity.getResources().getDisplayMetrics().density;}private int top(View v){int[]xy=new int[2];v.getLocationOnScreen(xy);return xy[1];}private int bottom(View v){return top(v)+v.getHeight();}private View root(){return activity.getWindow().getDecorView();}
    private View findTag(View v,String tag){if(tag.equals(v.getTag()))return v;if(v instanceof ViewGroup)for(int i=0;i<((ViewGroup)v).getChildCount();i++){View hit=findTag(((ViewGroup)v).getChildAt(i),tag);if(hit!=null)return hit;}return null;}
    private View findDescription(View v,String part){if(v.isShown()&&v.getContentDescription()!=null&&v.getContentDescription().toString().contains(part))return v;if(v instanceof ViewGroup)for(int i=0;i<((ViewGroup)v).getChildCount();i++){View hit=findDescription(((ViewGroup)v).getChildAt(i),part);if(hit!=null)return hit;}return null;}
    private TextView findText(View v,String text){if(v instanceof TextView&&text.contentEquals(((TextView)v).getText())&&v.isShown())return(TextView)v;if(v instanceof ViewGroup)for(int i=0;i<((ViewGroup)v).getChildCount();i++){TextView hit=findText(((ViewGroup)v).getChildAt(i),text);if(hit!=null)return hit;}return null;}
    private boolean hasText(View v,String text){return findText(v,text)!=null;}private void clickText(String text){View target=findText(root(),text);if(target==null)throw new AssertionError("Missing "+text);while(!target.isClickable()&&target.getParent() instanceof View)target=(View)target.getParent();target.performClick();}
    private void capture(String name)throws Exception{settle();android.view.accessibility.AccessibilityNodeInfo active=getUiAutomation().getRootInActiveWindow();if(active!=null&&!active.findAccessibilityNodeInfosByText("Viewing full screen").isEmpty()){for(android.view.accessibility.AccessibilityNodeInfo button:active.findAccessibilityNodeInfosByText("Got it"))button.performAction(android.view.accessibility.AccessibilityNodeInfo.ACTION_CLICK);settle();}Bitmap image=getUiAutomation().takeScreenshot();try(OutputStream out=new FileOutputStream(new File(output,name+".png"))){image.compress(Bitmap.CompressFormat.PNG,100,out);}finally{image.recycle();}}
    private interface Work{void run()throws Exception;}private interface Condition{boolean test()throws Exception;}
    private void settle()throws Exception{waitForIdleSync();SystemClock.sleep(350);}private void until(Condition test,String label)throws Exception{long end=SystemClock.uptimeMillis()+25000;while(SystemClock.uptimeMillis()<end){if(test.test())return;SystemClock.sleep(30);}throw new AssertionError("Timeout "+label);}
    private void check(boolean pass,String label)throws Exception{checks.put(new JSONObject().put("name",label).put("pass",pass));if(!pass)throw new AssertionError(label);}
    private void ui(Work work)throws Exception{AtomicReference<Throwable>error=new AtomicReference<>();runOnMainSync(()->{try{work.run();}catch(Throwable t){error.set(t);}});if(error.get()!=null)throw new RuntimeException(error.get());}
    private Class<?>cls(String name)throws Exception{return loader.loadClass("cc.huevia."+name);}private Field field(Class<?>type,String name)throws Exception{for(Class<?>c=type;c!=null;c=c.getSuperclass())try{Field f=c.getDeclaredField(name);f.setAccessible(true);return f;}catch(NoSuchFieldException ignored){}throw new NoSuchFieldException(name);}
    private Object get(Object target,String name)throws Exception{return field(target.getClass(),name).get(target);}private void set(Object target,String name,Object value)throws Exception{field(target.getClass(),name).set(target,value);}private Object call(Object target,String name,Object...args)throws Exception{return invoke(target.getClass(),target,name,args);}private Object stat(String type,String name,Object...args)throws Exception{return invoke(cls(type),null,name,args);}
    private Object invoke(Class<?>type,Object target,String name,Object[]args)throws Exception{for(Method method:type.getDeclaredMethods())if(method.getName().equals(name)&&method.getParameterCount()==args.length){method.setAccessible(true);try{return method.invoke(target,args);}catch(IllegalArgumentException mismatch){continue;}catch(InvocationTargetException error){throw new RuntimeException(error.getCause());}}throw new NoSuchMethodException(name);}
}
