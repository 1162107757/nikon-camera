package cc.huevia.albumpositionqa;

import android.app.*;import android.content.*;import android.content.pm.ActivityInfo;import android.graphics.*;import android.os.*;import android.view.*;import android.widget.*;
import cc.huevia.album.*;import cc.huevia.ncp.*;import cc.huevia.ui.*;
import java.io.*;import java.lang.reflect.*;import java.nio.file.Files;import java.security.MessageDigest;import java.util.*;import java.util.concurrent.*;import org.json.*;

/** Real MainActivity browse/edit/back regression, private owned JPEGs only. */
public final class AlbumPositionProbe extends Instrumentation {
    private Bundle args;private Activity activity;private Object album;private AlbumPanel workspace;private PhotoFilterEditor editor;
    private File output;private final List<File> owned=new ArrayList<>();private final JSONArray checks=new JSONArray(),cycles=new JSONArray();private Throwable failure;private String stage="start";
    @Override public void onCreate(Bundle args){this.args=args;start();}
    @Override public void onStart(){try{
        check("owned-emulator",Build.HARDWARE.matches("ranchu|goldfish"));check("exact-apk",sha(new File(getTargetContext().getApplicationInfo().sourceDir)).equals(args.getString("candidateSha256")));
        String run=args.getString("runId");check("safe-run",run.matches("[a-zA-Z0-9.-]+"));output=new File(getTargetContext().getExternalFilesDir(null),"album-position-108/"+run);output.mkdirs();
        activity=startActivitySync(new Intent().setClassName("cc.huevia","cc.huevia.MainActivity").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));until(()->(Boolean)get(activity,"ready"),"main-ready");check("guest-only",PhotoFilterEditor.accountOwner(activity).isEmpty());
        ui(()->activity.setRequestedOrientation(args.getString("mode","phone").equals("landscape")?ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE:ActivityInfo.SCREEN_ORIENTATION_PORTRAIT));
        until(()->activity.getResources().getConfiguration().orientation==(args.getString("mode","phone").equals("landscape")?2:1),"orientation");
        album=get(activity,"localAlbum");workspace=(AlbumPanel)get(activity,"localPhotoEditor");
        int id=activity.getResources().getIdentifier("preset_template","drawable","cc.huevia");Bitmap original=BitmapFactory.decodeResource(activity.getResources(),id),image=Bitmap.createScaledBitmap(original,480,320,true);if(original!=image)original.recycle();
        for(int i=0;i<90;i++)fixture(image,i,"2026:10:20 12:00:00");image.recycle();
        ui(()->invoke(activity,"switchRoot",new Class<?>[]{int.class},3));settle();until(()->((List<?>)get(album,"appPhotos")).size()>=90,"real-library-fixtures-loaded");settle();
        boolean baseline=args.getString("baseline","false").equals("true");
        for(int cycle=0;cycle<3;cycle++){
            stage="browse-edit-back-"+cycle;final int target=Math.max(2,Math.min(cycle==0?14:cycle==1?18:12,list().getCount()-list().getChildCount()-2));
            ui(()->list().setSelectionFromTop(target,-dp(37)));until(()->list().getFirstVisiblePosition()==target,"scrolled-below-top");SystemClock.sleep(120);
            final JSONObject before=snapshot();capture("before-"+cycle);
            ui(()->{View row=list().getChildAt(0);check("photo-row-clickable",row instanceof LinearLayout);View tile=((LinearLayout)row).getChildAt(0);check("native-photo-tap",tile.performClick());});
            until(()->workspace.isImmersive()&&get(workspace,"filterEditor")!=null&&((PhotoFilterEditor)get(workspace,"filterEditor")).isReady(),"native-editor-open");editor=(PhotoFilterEditor)get(workspace,"filterEditor");
            String source=(String)get(editor,"sourceSha");PhotoEditStore store=new PhotoEditStore(activity.getFilesDir(),"");File drafts=(File)get(store,"root");for(String suffix:new String[]{".draft",".draft.new",".draft.bak"})owned.add(new File(drafts,source+suffix));
            // Use the production edit/render/save path; network/catalog latency is outside this position regression.
            byte[] bytes=NcpCompatibilityFixtures.ncp();PresetPreviewProfile profile=PresetPreviewProfiles.fromPreset(bytes);
            ui(()->{set(editor,"selected",hex(bytes));set(editor,"selectedBytes",bytes);set(editor,"selectedProfile",profile);set(editor,"selectedName","QA NCP");set(editor,"strength",55);invoke(editor,"edited");});waitEditor();drain();
            if(cycle==2){int resource=activity.getResources().getIdentifier("preset_template","drawable","cc.huevia");Bitmap sample=BitmapFactory.decodeResource(activity.getResources(),resource);for(int n=91;n<109;n++)fixture(sample,n,"2026:10:21 12:00:00");sample.recycle();ui(()->((LocalAlbumPanel)album).refresh());until(()->!(Boolean)get(album,"loadingApp"),"hidden-library-refresh-complete");}
            ui(()->invoke(activity,"goBack"));settle();final JSONObject after=snapshot();capture("after-"+cycle);
            boolean same=hasKey(after,before.getString("key"))&&Math.abs(before.getInt("top")-after.getInt("top"))<=2;
            cycles.put(new JSONObject().put("cycle",cycle).put("before",before).put("after",after).put("sameAnchorAndPixelOffset",same));
            if(!baseline)check("return-keeps-photo-and-pixel-offset-"+cycle,same);
            check("draft-filter-saved",store.read(source)!=null&&store.read(source).strength==55);
            if(!baseline&&cycle==0){ui(()->{((Button)get(album,"phoneTab")).performClick();((Button)get(album,"appTab")).performClick();});settle();JSONObject switched=snapshot();check("app-position-survives-source-tab-switch",switched.getString("key").equals(after.getString("key"))&&Math.abs(switched.getInt("top")-after.getInt("top"))<=2);}
        }
    }catch(Throwable e){failure=e;try{StringWriter trace=new StringWriter();e.printStackTrace(new PrintWriter(trace));Files.writeString(new File(output,"failure-stack.txt").toPath(),trace.toString());capture("failure");}catch(Throwable ignored){}}
    finally{try{if(editor!=null){drain();ui(editor::unbind);drain();}if(activity!=null)ui(activity::finish);for(File file:owned)Files.deleteIfExists(file.toPath());}catch(Throwable e){if(failure==null)failure=e;}
        try{if(output!=null)Files.writeString(new File(output,"report.json").toPath(),new JSONObject().put("pass",failure==null).put("stage",stage).put("checks",checks).put("cycles",cycles).put("candidateSha256",args.getString("candidateSha256")).put("baseline",args.getString("baseline","false")).put("mode",args.getString("mode","phone")).put("fontScale",activity==null?0:activity.getResources().getConfiguration().fontScale).put("failure",failure==null?JSONObject.NULL:failure.toString()).put("ownedFilesRemoved",owned.stream().noneMatch(File::exists)).put("scope","Real MainActivity/local album/editor, 90 owned private JPEGs, native tile tap, actual production filter render/draft, native Back, real visible photo identity and exact pixel offset. No camera/MediaStore changes. Candidate identity is verified against the installed APK and recorded by the host runner.").toString(2));}catch(Throwable e){failure=e;}
        Bundle result=new Bundle();result.putString("summary",failure==null?"PASS "+checks.length():"FAIL "+stage+" "+failure);finish(failure==null?Activity.RESULT_OK:Activity.RESULT_CANCELED,result);
    }}
    private JSONObject snapshot()throws Exception{JSONObject[] value={null};ui(()->{ListView list=list();int first=list.getFirstVisiblePosition();Object row=((List<?>)get(album,"rows")).get(first);String header=(String)get(row,"header");List<?> items=(List<?>)get(row,"items");String key=header!=null?"date:"+header:"photo:"+get(items.get(0),"key");JSONArray keys=new JSONArray();if(header!=null)keys.put("date:"+header);else for(Object item:items)keys.put("photo:"+get(item,"key"));value[0]=new JSONObject().put("row",first).put("key",key).put("keys",keys).put("top",list.getChildAt(0).getTop()-list.getPaddingTop());});return value[0];}
    private boolean hasKey(JSONObject row,String key)throws Exception{JSONArray keys=row.getJSONArray("keys");for(int i=0;i<keys.length();i++)if(key.equals(keys.getString(i)))return true;return false;}
    private void fixture(Bitmap image,int index,String date)throws Exception{File folder=new File(activity.getExternalFilesDir(Environment.DIRECTORY_PICTURES),"camera-album");folder.mkdirs();File file=new File(folder,"scroll-qa-"+args.getString("runId")+"-"+index+"__SCROLL_QA_"+index+".JPG");owned.add(file);try(FileOutputStream out=new FileOutputStream(file)){image.compress(Bitmap.CompressFormat.JPEG,90,out);}android.media.ExifInterface exif=new android.media.ExifInterface(file.getPath());exif.setAttribute("ImageDescription","Owned scroll QA "+UUID.randomUUID());exif.setAttribute("DateTimeOriginal",date);exif.setAttribute("DateTime",date);exif.setAttribute("Orientation","1");exif.saveAttributes();}
    private ListView list()throws Exception{return(ListView)get(album,"list");}
    private void settle()throws Exception{until(()->!workspace.isImmersive()&&get(album,"list")!=null&&((View)get(album,"root")).isShown()&&!(Boolean)get(album,"loadingApp")&&list().getChildCount()>0&&!list().isLayoutRequested(),"visible-list-settled");SystemClock.sleep(200);ui(()->{});}
    private void waitEditor()throws Exception{until(()->{Object queue=get(editor,"previewQueue");return(Boolean)queue.getClass().getMethod("isIdle").invoke(queue);},"actual-filter-preview-ready");}
    private void drain()throws Exception{CountDownLatch latch=new CountDownLatch(1);ui(()->editor.afterPendingSaves(latch::countDown));check("draft-io-drained",latch.await(15,TimeUnit.SECONDS));}
    private void capture(String name)throws Exception{SystemClock.sleep(80);Bitmap screen=getUiAutomation().takeScreenshot();check("capture-"+name,screen!=null);try(FileOutputStream out=new FileOutputStream(new File(output,name+".png"))){screen.compress(Bitmap.CompressFormat.PNG,100,out);}screen.recycle();}
    private int dp(int n){return Math.round(n*activity.getResources().getDisplayMetrics().density);}
    private interface Work{void run()throws Exception;}private interface Condition{boolean ready()throws Exception;}
    private void ui(Work work){Throwable[] error={null};runOnMainSync(()->{try{work.run();}catch(Throwable e){error[0]=e;}});if(error[0]!=null)throw new RuntimeException(error[0]);}
    private void until(Condition condition,String name)throws Exception{long end=SystemClock.uptimeMillis()+20000;while(SystemClock.uptimeMillis()<end){boolean[] ready={false};ui(()->ready[0]=condition.ready());if(ready[0]){check(name,true);return;}SystemClock.sleep(40);}check(name,false);}
    private void check(String name,boolean ok){if(!ok)throw new AssertionError(name);checks.put(name);}
    private static Object get(Object o,String name)throws Exception{Field f=o.getClass().getDeclaredField(name);f.setAccessible(true);return f.get(o);}private static void set(Object o,String name,Object value)throws Exception{Field f=o.getClass().getDeclaredField(name);f.setAccessible(true);f.set(o,value);}
    private static void invoke(Object o,String name)throws Exception{invoke(o,name,new Class<?>[0]);}private static void invoke(Object o,String name,Class<?>[] types,Object...args)throws Exception{Method m=o.getClass().getDeclaredMethod(name,types);m.setAccessible(true);m.invoke(o,args);}
    private static String sha(File f)throws Exception{return hex(Files.readAllBytes(f.toPath()));}private static String hex(byte[] bytes)throws Exception{byte[] digest=MessageDigest.getInstance("SHA-256").digest(bytes);StringBuilder s=new StringBuilder();for(byte b:digest)s.append(String.format("%02x",b&255));return s.toString();}
}
