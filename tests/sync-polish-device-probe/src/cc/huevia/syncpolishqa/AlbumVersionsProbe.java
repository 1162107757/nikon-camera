package cc.huevia.syncpolishqa;

import android.app.*;
import android.content.*;
import android.database.Cursor;
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
import java.util.function.BooleanSupplier;

/** Real production date checkboxes, saved-version selection, renderer and MediaStore, emulator only. */
public final class AlbumVersionsProbe extends Instrumentation {
    private Activity activity;private Object local,sync,editor,repository,batch;private ClassLoader loader;private Bundle args;
    private File output;private Object original,warm,mono,second,secondEffect;private final List<Object> originals=new ArrayList<>();
    private final JSONArray checks=new JSONArray();private String mode;
    @Override public void onCreate(Bundle values){super.onCreate(values);args=values==null?new Bundle():values;start();}
    @Override public void onStart(){
        JSONObject report=new JSONObject();Bundle result=new Bundle();
        try{
            check(Build.HARDWARE.equals("ranchu")||Build.HARDWARE.equals("goldfish"),"emulator-only");loader=getTargetContext().getClassLoader();mode=args.getString("mode","phone");
            stat("ui.AppAppearance","setMode",getTargetContext(),mode.equals("dark")?"dark":"light");output=new File(getTargetContext().getExternalFilesDir(null),"album-versions142/"+mode);output.mkdirs();
            makeFixtures();activity=startActivitySync(new Intent(Intent.ACTION_MAIN).setComponent(new ComponentName("cc.huevia","cc.huevia.MainActivity")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK|Intent.FLAG_ACTIVITY_CLEAR_TASK));
            until(()->(Boolean)get(activity,"ready"),"main ready");
            ui(()->{set(activity,"busy",false);set(activity,"catalogLoaded",true);call(activity,"switchRoot",3);});
            local=get(activity,"localAlbum");editor=get(activity,"localPhotoEditor");sync=get(activity,"album");repository=get(local,"repository");
            until(()->!(Boolean)get(local,"loadingApp")&&((List<?>)get(local,"appPhotos")).size()>=4,"App catalog");settle();
            check(findTag(root(),"photo-date-group-check")!=null,"date-check-visible-before-selection");capture("01-album-browse");
            localDates(false);capture("02-album-selection");ui(()->call(local,"cancelSelection"));settle();
            Object group=groupOf(original);ui(()->call(local,"chooseVersion",group));settle();clickActiveText("暖调");
            until(()->get(editor,"filterEditor")!=null&&(Boolean)call(get(editor,"filterEditor"),"isReady"),"chosen version editor");settle();
            check(((File)call(get(editor,"localDetail"),"file")).equals(call(warm,"file")),"version-menu-opens-exact-chosen-file");
            Object filter=get(editor,"filterEditor");ui(()->call(filter,"showExport"));until(()->get(filter,"popup") instanceof Dialog&&((Dialog)get(filter,"popup")).isShowing(),"single save sheet");
            settle();Object session=get(filter,"versionExport");Dialog quick=(Dialog)get(filter,"popup");View decor=quick.getWindow().getDecorView();
            List<?> frozen=(List<?>)call(session,"edits");check(frozen.size()==1&&editFile(frozen.get(0)).equals(call(warm,"file"))&&get(frozen.get(0),"draft")==null,"single-default-is-selected-saved-version-not-original-or-draft");
            List<View> versionChecks=tagsStarting(decor,"export-version-check:");check(versionChecks.size()==3,"single-sheet-lists-three-versions-with-thumbnails");
            check(findText(decor,"暖调")!=null&&findText(decor,"当前")!=null,"single-sheet-names-current-version");
            TextView qualityLabel=(TextView)findTag(decor,"quick-save-quality-label");check(qualityLabel.getLayout().getLineCount()==1&&qualityLabel.getLayout().getEllipsisCount(0)==0&&qualityLabel.getLayout().getLineWidth(0)<=qualityLabel.getWidth()+1,"quality-caption-fits-one-line-on-narrow-large-text");
            for(View row:tagsStarting(decor,"export-version-row:")){check(row.getHeight()>=48*density()-.5,"version-row-has-full-touch-height");}
            capture("03-single-current");
            CheckBox warmCheck=versionCheck(decor,"暖调"),monoCheck=versionCheck(decor,"黑白"),originalCheck=versionCheck(decor,"原图");
            ui(()->{warmCheck.setChecked(false);originalCheck.setChecked(true);});
            frozen=(List<?>)call(session,"edits");check(frozen.size()==1&&editFile(frozen.get(0)).equals(call(original,"file")),"single-switch-changes-real-export-source");
            ui(()->{originalCheck.setChecked(false);warmCheck.setChecked(true);monoCheck.setChecked(true);});
            frozen=(List<?>)call(session,"edits");check(frozen.size()==2&&frozen.stream().allMatch(e->{try{return get(e,"draft")==null&&!editFile(e).equals(call(original,"file"));}catch(Exception x){throw new RuntimeException(x);}}),"multi-select-freezes-two-different-saved-files");
            capture("04-single-multiple");
            ui(()->findTag(decor,"quick-save-advanced").performClick());until(()->get(filter,"exportDialog") instanceof Dialog&&((Dialog)get(filter,"exportDialog")).isShowing(),"advanced version export");
            Dialog advanced=(Dialog)get(filter,"exportDialog");check(((List<?>)get(advanced,"previewRequests")).size()==2,"advanced-previews-correspond-to-both-selected-versions");capture("05-advanced-versions");
            ui(()->findTag(advanced.getWindow().getDecorView(),"export-change-versions").performClick());settle();
            quick=(Dialog)get(session,"quick");check(((List<?>)call(session,"edits")).size()==2,"advanced-return-keeps-version-checks");
            boolean full="true".equals(args.getString("full"));
            if(full){exportAndVerify(quick,session,2,"single-multiple");}else ui(()->call(session,"close"));
            ui(()->{call(editor,"goBack");call(activity,"switchRoot",3);call(local,"refreshApp");});until(()->!(Boolean)get(local,"loadingApp"),"return album");settle();
            Object refreshed=groupOf(original);check(((File)call(get(refreshed,"display"),"file")).equals(call(warm,"file")),"selected-version-persists-on-gallery-card");
            check(findDescription(root(),"当前版本 暖调")!=null,"gallery-card-names-current-version");
            batchExports(full);syncDates();
            ui(()->{call(activity,"switchRoot",3);call(local,"switchTab",true);});until(()->(Boolean)get(local,"phone")&&!(Boolean)get(local,"loadingPhone"),"phone album");settle();
            localDates(true);capture("08-phone-selection");ui(()->call(local,"cancelSelection"));
            if(full)verifyActiveDraftAndSingleVersion();
            report.put("pass",true);
        }catch(Throwable failure){try{StringWriter trace=new StringWriter();failure.printStackTrace(new PrintWriter(trace));report.put("pass",false).put("failure",trace.toString());if(activity!=null)capture("failure");}catch(Exception ignored){}}
        finally{try{report.put("checks",checks);if(output!=null)try(OutputStream out=new FileOutputStream(new File(output,"report.json"))){out.write(report.toString(2).getBytes(java.nio.charset.StandardCharsets.UTF_8));}result.putString("report",report.toString());}catch(Exception ignored){}finish(report.optBoolean("pass")?Activity.RESULT_OK:Activity.RESULT_CANCELED,result);}
    }
    private void localDates(boolean phone)throws Exception{
        View check=findTag(root(),"photo-date-group-check");check(check!=null&&check.getWidth()>=48*density()-.5&&check.getHeight()>=48*density()-.5,"date-checkbox-has-48dp-target-"+phone);
        ui(()->check.performClick());settle();
        int count=((Set<?>)get(local,"selected")).size();check((Boolean)get(local,"selecting")&&count>=2,"date-click-enters-selection-and-selects-group-"+phone);
        check(findTag(root(),"root-floating-navigation")==null&&((View)get(local,"selectionDock")).isShown(),"date-entry-retains-approved-floating-dock-"+phone);
        check("ALL".equals(call(findTag(root(),"photo-date-group-check"),"selectionState").toString()),"date-all-state-"+phone);
        Object first=((List<?>)call(local,"current")).get(0);ui(()->call(local,"toggle",first));settle();
        check(((Set<?>)get(local,"selected")).size()==count-1&&"PARTIAL".equals(call(findTag(root(),"photo-date-group-check"),"selectionState").toString()),"single-removal-makes-date-indeterminate-"+phone);
        ui(()->findTag(root(),"photo-date-group-check").performClick());settle();check(((Set<?>)get(local,"selected")).size()==count,"mixed-date-click-restores-whole-group-"+phone);
        ui(()->findTag(root(),"photo-date-group-check").performClick());settle();check(((Set<?>)get(local,"selected")).isEmpty()&&"NONE".equals(call(findTag(root(),"photo-date-group-check"),"selectionState").toString()),"whole-date-can-be-deselected-"+phone);
        ui(()->findTag(root(),"photo-date-group-check").performClick());settle();
    }
    private void batchExports(boolean full)throws Exception{
        List<Object> selected=Arrays.asList(warm,second);
        ui(()->call(editor,"exportLocalWorkspace",selected));until(()->get(editor,"batchQuickSaveDialog")!=null&&((Dialog)get(editor,"batchQuickSaveDialog")).isShowing(),"batch current sheet");
        settle();Object session=get(editor,"versionExport");Dialog quick=(Dialog)get(editor,"batchQuickSaveDialog");List<?> edits=(List<?>)call(session,"edits");
        Set<File> actual=new HashSet<>();for(Object edit:edits)actual.add(editFile(edit));check(actual.equals(new HashSet<>(Arrays.asList((File)call(warm,"file"),(File)call(second,"file")))),"batch-defaults-each-photos-own-current-file");
        CheckBox all=(CheckBox)findTag(quick.getWindow().getDecorView(),"export-all-versions");check(all!=null&&!all.isChecked(),"batch-all-versions-is-opt-in");capture("06-batch-current");
        if(full){exportAndVerify(quick,session,2,"batch-current");ui(()->call(editor,"exportLocalWorkspace",selected));until(()->((Dialog)get(editor,"batchQuickSaveDialog")).isShowing(),"batch reopen");session=get(editor,"versionExport");quick=(Dialog)get(editor,"batchQuickSaveDialog");all=(CheckBox)findTag(quick.getWindow().getDecorView(),"export-all-versions");}
        final CheckBox chooseAll=all;ui(()->chooseAll.setChecked(true));settle();edits=(List<?>)call(session,"edits");int allCount=((Number)get(get(session,"data"),"allCount")).intValue();check(edits.size()==allCount&&allCount>=5,"batch-all-versions-includes-every-current-catalog-result");
        Set<File> files=new HashSet<>();Set<String> names=new HashSet<>();for(Object edit:edits){files.add(editFile(edit));names.add((String)get(edit,"outputFilename"));check(get(edit,"draft")==null,"saved-version-does-not-load-latest-pending-draft");}
        check(files.size()==allCount&&names.size()==allCount,"all-versions-have-distinct-files-and-names");capture("07-batch-all");
        if(full)exportAndVerify(quick,session,allCount,"batch-all");else{final Object close=session;ui(()->call(close,"close"));}
    }
    private void syncDates()throws Exception{
        // Controller lists actual camera-received files. Isolate its view snapshot to these
        // real, completed app-owned JPEGs; no fake camera session or transport is installed.
        List<Object> groups=new ArrayList<>(),cards=new ArrayList<>();for(Object item:(List<?>)get(local,"appPhotos")){groups.add(get(item,"group"));cards.add(get(item,"photo"));}
        ui(()->{call(activity,"switchRoot",1);set(sync,"dateRequest",((Number)get(sync,"dateRequest")).intValue()+1);set(sync,"loadingDownloads",false);set(sync,"localLoaded",true);List<Object> target=(List<Object>)get(sync,"allDownloads");target.clear();target.addAll(cards);List<Object> catalog=(List<Object>)get(sync,"photoGroups");catalog.clear();catalog.addAll(groups);call(sync,"applyDownloadFilter");call(sync,"chooseTab",true);});settle();
        check(((List<?>)get(sync,"downloads")).size()>=4,"sync-completed-owned-photo-snapshot");
        View entry=findTag(root(),"photo-date-group-check");check(entry!=null&&entry.isShown(),"sync-date-entry-visible-in-browse");
        ui(()->entry.performClick());settle();int count=((Set<?>)get(sync,"selectedLocal")).size();check(count>=2&&(Boolean)get(sync,"selectionMode"),"sync-date-entry-selects-whole-current-group");
        Object first=((List<?>)get(sync,"downloads")).get(0);ui(()->call(sync,"toggleLocalSelection",first));settle();check("PARTIAL".equals(call(findTag(root(),"photo-date-group-check"),"selectionState").toString()),"sync-single-removal-shows-mixed-date");
        check(!(Boolean)get(sync,"downloading")&&!(Boolean)get(sync,"exporting"),"date-selection-starts-no-download-or-export");capture("09-sync-partial");
        ui(()->call(sync,"goBack"));settle();check(!(Boolean)get(sync,"selectionMode")&&((Set<?>)get(sync,"selectedLocal")).isEmpty(),"sync-exit-clears-all-selection");
    }
    private void exportAndVerify(Dialog quick,Object session,int count,String label)throws Exception{
        List<?> edits=(List<?>)call(session,"edits");Map<String,Integer> expected=new LinkedHashMap<>(),before=new LinkedHashMap<>();
        for(Object edit:edits){String name=(String)get(edit,"outputFilename");int color=pixel(editFile(edit));if(get(edit,"draft")!=null){Bitmap current=(Bitmap)get(get(editor,"filterEditor"),"current");color=current.getPixel(current.getWidth()/2,current.getHeight()/2);}expected.put(name,color);before.put(name,publicCount(name));}
        ui(()->findTag(quick.getWindow().getDecorView(),"quick-save-confirm").performClick());
        batch=get(editor,"photoPresets");until(()->!(Boolean)call(batch,"isActive")&&((Number)get(call(batch,"state"),"total")).intValue()==count,"actual export "+label);
        Object state=call(batch,"state");check(((Number)get(state,"completed")).intValue()==count&&((Number)get(state,"failed")).intValue()==0,"real-queue-completes-"+label);
        for(Map.Entry<String,Integer> wanted:expected.entrySet()){
            String stem=wanted.getKey().replaceFirst("\\.[^.]+$","");boolean found=false;
            try(Cursor cursor=getTargetContext().getContentResolver().query(MediaStore.Images.Media.EXTERNAL_CONTENT_URI,new String[]{"_id","_display_name"},"_display_name LIKE ?",new String[]{"Huevia_"+stem+"_%"},"_id DESC")){
                if(cursor!=null&&cursor.moveToFirst()){Uri uri=ContentUris.withAppendedId(MediaStore.Images.Media.EXTERNAL_CONTENT_URI,cursor.getLong(0));try(InputStream in=getTargetContext().getContentResolver().openInputStream(uri)){Bitmap image=BitmapFactory.decodeStream(in);int got=image.getPixel(image.getWidth()/2,image.getHeight()/2);image.recycle();found=distance(got,wanted.getValue())<18;}check(cursor.getString(1).contains(stem),"actual-public-name-includes-version-"+label);}
            }
            check(found,"actual-export-pixels-match-selected-version-"+label+"-"+stem);
            check(publicCount(wanted.getKey())==before.get(wanted.getKey())+1,"new-version-copy-does-not-overwrite-existing-names-"+label);
        }
        until(()->activeHasText("关闭"),"save result dialog");clickActiveText("关闭");settle();
    }
    private int publicCount(String name){String stem=name.replaceFirst("\\.[^.]+$","");try(Cursor cursor=getTargetContext().getContentResolver().query(MediaStore.Images.Media.EXTERNAL_CONTENT_URI,new String[]{"_id"},"_display_name LIKE ?",new String[]{"Huevia_"+stem+"_%"},null)){return cursor==null?0:cursor.getCount();}}
    private void verifyActiveDraftAndSingleVersion()throws Exception{
        Object data=stat("ui.PhotoVersionExport","prepare",getTargetContext(),Collections.singletonList(originals.get(3)),null,null,stat("ui.PhotoFilterEditor","accountOwner",getTargetContext()),(BooleanSupplier)()->false);
        check(!(Boolean)get(data,"hasVersions")&&((List<?>)get(data,"choices")).size()==1,"one-version-photo-adds-no-extra-selection-step");
        ui(()->call(editor,"openLocalWorkspace",Collections.singletonList(warm),0));until(()->get(editor,"filterEditor")!=null&&(Boolean)call(get(editor,"filterEditor"),"isReady"),"editing saved version");settle();
        Object filter=get(editor,"filterEditor");Bitmap previous=(Bitmap)get(filter,"current");ui(()->call(filter,"showExactValue"));settle();AlertDialog input=(AlertDialog)get(filter,"popup");EditText field=firstInput(input.getWindow().getDecorView());ui(()->{field.setText("25");input.getButton(DialogInterface.BUTTON_POSITIVE).performClick();});
        until(()->(Boolean)call(filter,"dirty")&&get(filter,"current")!=previous,"real brightness preview");settle();
        ui(()->call(filter,"showExport"));until(()->get(filter,"popup") instanceof Dialog&&((Dialog)get(filter,"popup")).isShowing(),"active edit export");settle();
        Object session=get(filter,"versionExport");Dialog quick=(Dialog)get(filter,"popup");List<?> edits=(List<?>)call(session,"edits");check(edits.size()==1&&get(edits.get(0),"draft")!=null,"explicit-current-edit-retains-frozen-profile");capture("10-active-edit");
        CheckBox active=versionCheck(quick.getWindow().getDecorView(),"当前编辑"),saved=versionCheck(quick.getWindow().getDecorView(),"暖调");ui(()->{active.setChecked(false);saved.setChecked(true);});edits=(List<?>)call(session,"edits");check(edits.size()==1&&get(edits.get(0),"draft")==null&&editFile(edits.get(0)).equals(call(warm,"file")),"saved-version-choice-ignores-a-different-active-draft");
        ui(()->{saved.setChecked(false);active.setChecked(true);});exportAndVerify(quick,session,1,"active-edit");
    }
    private EditText firstInput(View v){if(v instanceof EditText)return (EditText)v;if(v instanceof ViewGroup)for(int i=0;i<((ViewGroup)v).getChildCount();i++){EditText field=firstInput(((ViewGroup)v).getChildAt(i));if(field!=null)return field;}return null;}
    private File editFile(Object edit)throws Exception{return (File)call(call(get(edit,"source"),"localPhoto"),"file");}
    private int pixel(File file){Bitmap image=BitmapFactory.decodeFile(file.getPath());int color=image.getPixel(image.getWidth()/2,image.getHeight()/2);image.recycle();return color;}
    private int distance(int a,int b){return Math.max(Math.abs(Color.red(a)-Color.red(b)),Math.max(Math.abs(Color.green(a)-Color.green(b)),Math.abs(Color.blue(a)-Color.blue(b))));}
    private Object groupOf(Object photo)throws Exception{for(Object item:(List<?>)get(local,"appPhotos")){Object group=get(item,"group");if(call(group,"findByFile",call(photo,"file"))!=null)return group;}throw new AssertionError("missing photo group");}
    private CheckBox versionCheck(View decor,String label){for(View view:tagsStarting(decor,"export-version-check:"))if(view.getContentDescription().toString().startsWith("导出版本 "+label))return (CheckBox)view;throw new AssertionError("Missing version "+label);}
    private void makeFixtures()throws Exception{
        File dir=new File(getTargetContext().getFilesDir(),"pictures/camera-album");dir.mkdirs();Bitmap asset;try(InputStream in=getContext().getAssets().open("astronaut.png")){asset=BitmapFactory.decodeStream(in);}Bitmap source=Bitmap.createScaledBitmap(asset,500,620,true);asset.recycle();
        long today=System.currentTimeMillis()-60000,yesterday=today-86400000;
        original=photo(dir,"IMG142_001.JPG",source,today,0);second=photo(dir,"IMG142_002.JPG",source,today,1);Object third=photo(dir,"IMG142_003.JPG",source,yesterday,2),fourth=photo(dir,"IMG142_004.JPG",source,yesterday,3);originals.addAll(Arrays.asList(original,second,third,fourth));
        warm=effect(dir,original,"a","暖调",source,4);mono=effect(dir,original,"b","黑白",source,5);secondEffect=effect(dir,second,"c","冷调",source,6);source.recycle();
        Object catalog=cls("album.PhotoLibraryCatalog").getConstructor(File.class,File.class).newInstance(getTargetContext().getFilesDir(),getTargetContext().getExternalFilesDir(Environment.DIRECTORY_PICTURES));List<Object> all=new ArrayList<>(originals);all.addAll(Arrays.asList(warm,mono,secondEffect));List<?> groups=(List<?>)call(catalog,"list",all,(BooleanSupplier)()->false);
        for(Object group:groups)if(call(group,"findByFile",call(original,"file"))!=null)call(catalog,"selectDisplay",group,original);else if(call(group,"findByFile",call(second,"file"))!=null)call(catalog,"selectDisplay",group,second);
        Object gallery=cls("album.PhotoLiveGallery").getConstructor(Context.class).newInstance(getTargetContext());call(gallery,"publishNewCopy",original);call(gallery,"publishNewCopy",second);
    }
    private Object photo(File dir,String name,Bitmap source,long date,int tint)throws Exception{File file=new File(dir,"QA142-"+UUID.randomUUID()+"__"+name);writeImage(file,source,tint);file.setLastModified(date);return downloaded(file,name,date);}
    private Object effect(File dir,Object original,String preset,String label,Bitmap source,int tint)throws Exception{
        String sha=(String)stat("album.PhotoEditStore","hashFile",call(original,"file"));String key=(String)stat("album.PhotoPresetBatch","key",sha,preset.repeat(64));File file=new File(dir,"effect-"+key+"__Effect.JPG");writeImage(file,source,tint);Object effect=downloaded(file,"IMG142_"+label+".JPG",((Number)call(original,"photoDate")).longValue());
        File records=new File(getTargetContext().getFilesDir(),"photo-preset-results");records.mkdirs();try(DataOutputStream out=new DataOutputStream(new FileOutputStream(new File(records,key+".record")))){out.writeInt(0x50424531);out.writeLong(file.length());out.writeUTF((String)stat("album.PhotoEditStore","hashFile",file));}
        Constructor<?> c=cls("album.PhotoPresetSources").getDeclaredConstructor(File.class,File.class);c.setAccessible(true);Object sources=c.newInstance(getTargetContext().getFilesDir(),getTargetContext().getExternalFilesDir(Environment.DIRECTORY_PICTURES));call(sources,"bind",effect,original,preset.repeat(64),label,(BooleanSupplier)()->false);return effect;
    }
    private void writeImage(File file,Bitmap source,int tint)throws Exception{Bitmap copy=source.copy(Bitmap.Config.ARGB_8888,true);Canvas canvas=new Canvas(copy);if(tint>0){Paint p=new Paint();p.setColor(new int[]{0,0x1600ff00,0x200000ff,0x28ff0000,0x70952205,0x80002244,0x805511aa}[tint]);canvas.drawRect(0,0,copy.getWidth(),copy.getHeight(),p);}try(OutputStream out=new FileOutputStream(file)){copy.compress(Bitmap.CompressFormat.JPEG,95,out);}copy.recycle();}
    private Object downloaded(File file,String name,long date)throws Exception{Constructor<?> c=cls("album.DownloadedPhoto").getDeclaredConstructor(File.class,String.class,String.class,String.class,long.class);c.setAccessible(true);return c.newInstance(file.getCanonicalFile(),name,"","",date);}
    private List<View> tagsStarting(View root,String prefix){List<View> result=new ArrayList<>();collectTags(root,prefix,result);return result;}
    private void collectTags(View v,String prefix,List<View> out){if(v.getTag() instanceof String&&((String)v.getTag()).startsWith(prefix))out.add(v);if(v instanceof ViewGroup)for(int i=0;i<((ViewGroup)v).getChildCount();i++)collectTags(((ViewGroup)v).getChildAt(i),prefix,out);}
    private void clickActiveText(String text)throws Exception{android.view.accessibility.AccessibilityNodeInfo active=getUiAutomation().getRootInActiveWindow();if(active!=null)for(android.view.accessibility.AccessibilityNodeInfo node:active.findAccessibilityNodeInfosByText(text)){if(node.getText()!=null&&text.contentEquals(node.getText())){while(node!=null&&!node.isClickable())node=node.getParent();if(node!=null&&node.performAction(android.view.accessibility.AccessibilityNodeInfo.ACTION_CLICK)){settle();return;}}}throw new AssertionError("Missing active text "+text);}
    private boolean activeHasText(String text){android.view.accessibility.AccessibilityNodeInfo active=getUiAutomation().getRootInActiveWindow();return active!=null&&!active.findAccessibilityNodeInfosByText(text).isEmpty();}
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
