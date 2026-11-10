package cc.huevia.rawdevelopmentqa;

import android.app.Activity;
import android.app.Instrumentation;
import android.content.Context;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.SystemClock;
import android.view.View;
import android.view.ViewTreeObserver;
import android.view.accessibility.AccessibilityNodeInfo;
import android.widget.Button;
import android.widget.SeekBar;
import java.io.File;
import java.io.DataInputStream;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.nio.file.Files;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.TimeUnit;
import org.json.JSONArray;
import org.json.JSONObject;

/** Real RAW workspace checks sharing the decoder probe's generated, camera-free DNG fixture. */
public final class RawActivityChecks {
    private RawActivityChecks(){}
    public static void run(Instrumentation instrumentation,Context context,File source,JSONArray checks)throws Exception{
        ClassLoader loader=context.getClassLoader();Class<?> activityType=Class.forName("cc.huevia.RawDevelopActivity",true,loader),editor=Class.forName("cc.huevia.ui.PhotoFilterEditor",true,loader);
        String originalSha=sha(source);File retainedOriginal=new File(context.getFilesDir(),"raw-editor-sources/"+originalSha+".dng");boolean retainedBefore=retainedOriginal.exists();
        File cacheRoot=new File(context.getFilesDir(),"raw-development"),handoffRoot=new File(context.getFilesDir(),"raw-dng-handoff"),pictures=new File(context.getFilesDir(),"pictures/camera-album"),receipts=new File(context.getFilesDir(),"local-photo-sources"),drafts=new File(context.getFilesDir(),"photo-edit-drafts");
        Set<String> beforeCache=files(cacheRoot,2),beforeHandoffs=files(handoffRoot,1),beforeRepository=files(pictures,1),beforeDrafts=files(drafts,2);beforeRepository.addAll(files(receipts,1));List<File> ownCache=new ArrayList<>();File saved=new File(source.getParentFile(),"activity-output-"+UUID.randomUUID()+".png");Activity activity=null,mainActivity=null;
        try{
            mainActivity=instrumentation.startActivitySync(new Intent().setClassName("cc.huevia","cc.huevia.MainActivity").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));final Activity host=mainActivity;
            until(instrumentation,()->(Boolean)get(host,"ready"),"raw-return-main-ready",checks);
            String owner=(String)editor.getMethod("accountOwner",Context.class).invoke(null,context);
            RawDocumentPickerChecks.emptyEntry(instrumentation,host,owner,checks);
            Intent intent=new Intent().setClassName("cc.huevia",activityType.getName()).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK).putExtra("raw_source_path",source.getAbsolutePath()).putExtra("raw_source_sha",originalSha).putExtra("raw_owner",owner);
            // NEW_TASK is intentionally absent here: Android must deliver the actual result to Main.
            intent.setFlags(0);Instrumentation.ActivityMonitor monitor=instrumentation.addMonitor(activityType.getName(),null,false);
            try{ui(instrumentation,()->host.startActivityForResult(intent,7319));activity=instrumentation.waitForMonitorWithTimeout(monitor,10000);}finally{instrumentation.removeMonitor(monitor);}
            check(checks,"raw-ui-started-by-real-main-for-result",activity!=null);final Activity page=activity;until(instrumentation,()->ready(page),"raw-ui-initial-ready",checks);Object initial=get(page,"result");rememberCache(initial,ownCache);check(checks,"raw-ui-owner-preserved",owner.equals(get(page,"owner")));Object info=get(initial,"info");check(checks,"raw-ui-full-result-dimensions",integer(info,"width")==96&&integer(info,"height")==64);check(checks,"raw-ui-original-sha",originalSha.equals(get(initial,"sourceSha")));Bitmap shown=(Bitmap)get(page,"preview");check(checks,"raw-ui-real-preview-visible",shown!=null&&!shown.isRecycled()&&shown.getWidth()==96&&shown.getHeight()==64);double before=mean(shown);String initialIdentity=(String)get(initial,"cacheIdentity");capture(instrumentation,page,"raw-ui-initial.png");
            for(String name:new String[]{"colorMode","whiteBalance","highlights","quality"}){Button control=(Button)get(page,name);ui(instrumentation,()->{check(checks,"raw-color-control-single-line-fit-"+name,control.getPaint().measureText(control.getText().toString())<=control.getWidth()-control.getCompoundPaddingLeft()-control.getCompoundPaddingRight()+1);check(checks,"raw-color-control-touch-target-"+name,control.getHeight()/control.getResources().getDisplayMetrics().density>=44);});}
            Button color=(Button)get(page,"colorMode");ui(instrumentation,color::performClick);capture(instrumentation,page,"raw-ui-color-choice.png");clickAccessibilityText(instrumentation,"中性色彩");
            until(instrumentation,()->ready(page)&&!initialIdentity.equals(get(get(page,"result"),"cacheIdentity")),"raw-ui-neutral-color-ready",checks);Object neutralColor=get(page,"result");rememberCache(neutralColor,ownCache);check(checks,"raw-ui-neutral-color-setting",get(get(page,"settings"),"colorMode").toString().equals("NEUTRAL"));
            ui(instrumentation,color::performClick);clickAccessibilityText(instrumentation,"相机 JPEG 色彩（近似）");until(instrumentation,()->ready(page)&&initialIdentity.equals(get(get(page,"result"),"cacheIdentity")),"raw-ui-camera-color-restored",checks);check(checks,"raw-ui-camera-color-cache-reused",(Boolean)get(get(page,"result"),"cached"));
            RawDocumentPickerChecks.run(instrumentation,page,checks);
            SeekBar exposure=(SeekBar)get(page,"exposure");ui(instrumentation,()->{Bundle progress=new Bundle();progress.putFloat(AccessibilityNodeInfo.ACTION_ARGUMENT_PROGRESS_VALUE,60f);check(checks,"raw-ui-exposure-accessibility-action",exposure.performAccessibilityAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_SET_PROGRESS.getId(),progress));});until(instrumentation,()->ready(page)&&!initialIdentity.equals(get(get(page,"result"),"cacheIdentity")),"raw-ui-exposure-render-ready",checks);Object exposed=get(page,"result");rememberCache(exposed,ownCache);check(checks,"raw-ui-exposure-setting-applied",integer(get(page,"settings"),"exposureTenths")==10);check(checks,"raw-ui-exposure-changes-visible-pixels",Math.abs(mean((Bitmap)get(page,"preview"))-before)>.1);
            Button whiteBalance=(Button)get(page,"whiteBalance");ui(instrumentation,whiteBalance::performClick);clickAccessibilityText(instrumentation,"自动白平衡");String exposedIdentity=(String)get(exposed,"cacheIdentity");until(instrumentation,()->ready(page)&&!exposedIdentity.equals(get(get(page,"result"),"cacheIdentity")),"raw-ui-auto-wb-ready",checks);Object automatic=get(page,"result");rememberCache(automatic,ownCache);check(checks,"raw-ui-white-balance-applied",get(get(page,"settings"),"whiteBalance").toString().equals("AUTO"));capture(instrumentation,page,"raw-ui-auto-wb.png");
            ui(instrumentation,()->call(page,"writePng",new Class<?>[]{automatic.getClass(),Uri.class},automatic,Uri.fromFile(saved)));until(instrumentation,()->ready(page)&&saved.isFile(),"raw-ui-PNG-stream-save-completes",checks);check(checks,"raw-ui-PNG-bytes-exact",sha(saved).equals(get(automatic,"workingSha")));BitmapFactory.Options bounds=new BitmapFactory.Options();bounds.inJustDecodeBounds=true;BitmapFactory.decodeFile(saved.getPath(),bounds);check(checks,"raw-ui-PNG-full-dimensions",bounds.outWidth==96&&bounds.outHeight==64&&"image/png".equals(bounds.outMimeType));check(checks,"raw-ui-raw-preserved-after-save",originalSha.equals(sha(source)));
            Button edit=(Button)get(page,"edit");ui(instrumentation,edit::performClick);until(instrumentation,page::isFinishing,"raw-ui-edit-copy-finishes",checks);
            until(instrumentation,()->boundEditor(host,originalSha)!=null,"raw-system-result-reaches-real-editor",checks);
            Object boundEditor=boundEditor(host,originalSha),bound=get(boundEditor,"bound");File jpeg=(File)call(bound,"file",new Class<?>[]{});String jpegSha=sha(jpeg);
            check(checks,"raw-return-editor-bound-JPEG-sha",jpegSha.equals(get(boundEditor,"sourceSha"))&&jpegSha.equals(get(boundEditor,"displayedSha")));
            check(checks,"raw-return-editor-editable",(Boolean)get(boundEditor,"ready")&&!(Boolean)get(boundEditor,"unrecoverableSaved")&&owner.equals(get(boundEditor,"owner")));
            check(checks,"raw-return-local-album-root-selected",(Boolean)get(host,"localAlbumTab")&&!(Boolean)get(get(host,"localAlbum"),"importing"));
            bounds=new BitmapFactory.Options();bounds.inJustDecodeBounds=true;BitmapFactory.decodeFile(jpeg.getPath(),bounds);check(checks,"raw-return-imported-JPEG-full-dimensions",bounds.outWidth==96&&bounds.outHeight==64&&"image/jpeg".equals(bounds.outMimeType));
            String key="raw-dng-"+originalSha+"-"+jpegSha;File receipt=new File(receipts,key+".raw-development");check(checks,"raw-return-private-repository-path",inside(jpeg,pictures)&&jpeg.getName().startsWith(key+"__"));check(checks,"raw-return-identity-receipt-exists",receipt.isFile());
            try(DataInputStream input=new DataInputStream(new FileInputStream(receipt))){check(checks,"raw-return-receipt-raw-JPEG-working-identity",input.readInt()==0x52445731&&originalSha.equals(input.readUTF())&&jpegSha.equals(input.readUTF())&&get(automatic,"cacheIdentity").equals(input.readUTF())&&input.available()==0);}
            until(instrumentation,()->{Set<String> remaining=files(handoffRoot,1);remaining.removeAll(beforeHandoffs);return remaining.isEmpty();},"raw-return-consumed-handoff-removed",checks);
            check(checks,"raw-ui-raw-preserved-after-real-return",originalSha.equals(sha(source)));capture(instrumentation,host,"raw-ui-editor-return.png");
        }finally{
            if(activity!=null){Activity page=activity;ui(instrumentation,()->{if(!page.isFinishing())page.finish();});long end=SystemClock.uptimeMillis()+10000;while(!activity.isDestroyed()&&SystemClock.uptimeMillis()<end)SystemClock.sleep(20);check(checks,"raw-ui-activity-destroyed",activity.isDestroyed());}
            if(mainActivity!=null){Activity host=mainActivity;List<ExecutorService> photoWorkers=new ArrayList<>();Object album=get(host,"localAlbum"),panel=get(host,"localPhotoEditor"),filter=panel==null?null:get(panel,"filterEditor");collectWorkers(album,photoWorkers);collectWorkers(panel,photoWorkers);collectWorkers(filter,photoWorkers);ui(instrumentation,()->{if(!host.isFinishing())host.finish();});long end=SystemClock.uptimeMillis()+10000;while(!host.isDestroyed()&&SystemClock.uptimeMillis()<end)SystemClock.sleep(20);check(checks,"raw-return-main-destroyed-before-cleanup",host.isDestroyed());for(ExecutorService worker:photoWorkers)check(checks,"raw-return-photo-worker-terminated-before-cleanup",worker.awaitTermination(10,TimeUnit.SECONDS));}
            if(saved.isFile())check(checks,"raw-ui-owned-PNG-cleaned",saved.delete());
            for(File file:ownCache)if(!beforeCache.contains(file.getCanonicalPath())&&file.isFile()){if(!inside(file,cacheRoot)||!file.getName().matches("[a-f0-9]{64}\\.(png|record)"))throw new AssertionError("unsafe-raw-ui-cache-cleanup");check(checks,"raw-ui-owned-cache-cleaned",file.delete());}
            for(String path:files(handoffRoot,1))if(!beforeHandoffs.contains(path)){File file=new File(path);if(!inside(file,handoffRoot)||!file.getName().matches("[a-f0-9-]{36}\\.jpg"))throw new AssertionError("unsafe-raw-ui-handoff-cleanup");check(checks,"raw-ui-owned-handoff-cleaned",file.delete());}
            cleanupImported(pictures,receipts,drafts,beforeRepository,beforeDrafts,originalSha,checks);
            if(!retainedBefore&&retainedOriginal.isFile())check(checks,"raw-ui-owned-retained-source-cleaned",originalSha.equals(sha(retainedOriginal))&&retainedOriginal.delete());check(checks,"raw-ui-final-original-sha",originalSha.equals(sha(source)));
        }
    }
    private static void rememberCache(Object result,List<File> files)throws Exception{File png=(File)get(result,"workingFile");String identity=(String)get(result,"cacheIdentity");for(File file:new File[]{png,new File(png.getParentFile(),identity+".record")})if(!files.contains(file))files.add(file);}
    private static boolean ready(Activity activity)throws Exception{return (Boolean)call(activity,"ready",new Class<?>[]{});}
    private static void clickAccessibilityText(Instrumentation instrumentation,String text)throws Exception{long end=SystemClock.uptimeMillis()+5000;while(SystemClock.uptimeMillis()<end){AccessibilityNodeInfo root=instrumentation.getUiAutomation().getRootInActiveWindow();if(root!=null){List<AccessibilityNodeInfo> matches=root.findAccessibilityNodeInfosByText(text);for(AccessibilityNodeInfo node:matches){AccessibilityNodeInfo clickable=node;while(clickable!=null&&!clickable.isClickable())clickable=clickable.getParent();if(clickable!=null&&clickable.performAction(AccessibilityNodeInfo.ACTION_CLICK))return;}}SystemClock.sleep(50);}throw new AssertionError("raw-ui-choice-not-found-"+text);}
    private static Object boundEditor(Activity host,String rawSha)throws Exception{
        Object panel=get(host,"localPhotoEditor");if(panel==null)return null;Object editor=get(panel,"filterEditor");if(editor==null||!(Boolean)get(editor,"ready")||get(editor,"current")==null)return null;
        Object bound=get(editor,"bound");if(bound==null)return null;File file=(File)call(bound,"file",new Class<?>[]{});
        return file.isFile()&&file.getName().startsWith("raw-dng-"+rawSha+"-")?editor:null;
    }
    private static void collectWorkers(Object owner,List<ExecutorService> workers)throws Exception{if(owner==null)return;for(Field field:owner.getClass().getDeclaredFields()){field.setAccessible(true);Object value=field.get(owner);if(value instanceof ExecutorService&&!workers.contains(value))workers.add((ExecutorService)value);}}
    private static void cleanupImported(File pictures,File receipts,File drafts,Set<String> beforeRepository,Set<String> beforeDrafts,String rawSha,JSONArray checks)throws Exception{
        String prefix="raw-dng-"+rawSha+"-";Set<String> jpegShas=new HashSet<>();
        for(File directory:new File[]{pictures,receipts})for(String path:files(directory,1)){
            File file=new File(path);String name=file.getName();if(!name.startsWith(prefix))continue;
            if(!name.matches("raw-dng-"+rawSha+"-[a-f0-9]{64}(__bayer\\.jpg|\\.raw-development(\\.(bak|new))?)"))throw new AssertionError("unsafe-raw-return-repository-cleanup");
            jpegShas.add(name.substring(prefix.length(),prefix.length()+64));
            if(!beforeRepository.contains(path)){if(!inside(file,directory))throw new AssertionError("unsafe-raw-return-repository-parent");check(checks,"raw-return-owned-repository-file-cleaned",file.delete());}
        }
        for(String path:files(drafts,2))if(!beforeDrafts.contains(path)){
            File file=new File(path);String name=file.getName();boolean owned=false;for(String jpegSha:jpegShas)if(name.startsWith(jpegSha+"."))owned=true;
            if(owned){if(!inside(file,drafts))throw new AssertionError("unsafe-raw-return-draft-cleanup");check(checks,"raw-return-owned-draft-cleaned",file.delete());}
        }
        Set<String> remaining=files(pictures,1);remaining.addAll(files(receipts,1));remaining.removeAll(beforeRepository);for(String path:remaining)check(checks,"raw-return-no-fixture-repository-residue",!new File(path).getName().startsWith(prefix));
    }
    private static void capture(Instrumentation instrumentation,Activity activity,String name)throws Exception{
        Field field;try{field=instrumentation.getClass().getDeclaredField("output");field.setAccessible(true);}catch(NoSuchFieldException absent){return;}Object directory=field.get(instrumentation);if(!(directory instanceof File))return;
        View target=activity.getWindow().getDecorView();CountDownLatch committed=new CountDownLatch(1);Runnable[] hardware={null};ViewTreeObserver.OnDrawListener[] fallback={null};
        ui(instrumentation,()->{if(Build.VERSION.SDK_INT>=29&&target.isHardwareAccelerated()){hardware[0]=committed::countDown;target.getViewTreeObserver().registerFrameCommitCallback(hardware[0]);target.invalidate();}else{fallback[0]=new ViewTreeObserver.OnDrawListener(){boolean once;public void onDraw(){if(once)return;once=true;target.post(()->{if(target.getViewTreeObserver().isAlive())target.getViewTreeObserver().removeOnDrawListener(this);target.postOnAnimation(committed::countDown);});}};target.getViewTreeObserver().addOnDrawListener(fallback[0]);target.invalidate();}});
        if(!committed.await(10,TimeUnit.SECONDS)){ui(instrumentation,()->{ViewTreeObserver observer=target.getViewTreeObserver();if(!observer.isAlive())return;if(Build.VERSION.SDK_INT>=29&&hardware[0]!=null)observer.unregisterFrameCommitCallback(hardware[0]);if(fallback[0]!=null)observer.removeOnDrawListener(fallback[0]);});throw new AssertionError("raw-ui-frame-not-committed-"+name);}
        Bitmap screenshot=instrumentation.getUiAutomation().takeScreenshot();if(screenshot==null)throw new AssertionError("raw-ui-screenshot-null");try(FileOutputStream out=new FileOutputStream(new File((File)directory,name))){screenshot.compress(Bitmap.CompressFormat.PNG,100,out);}finally{screenshot.recycle();}
    }
    private static double mean(Bitmap bitmap){long total=0;int count=0;for(int y=0;y<bitmap.getHeight();y+=3)for(int x=0;x<bitmap.getWidth();x+=3){int p=bitmap.getPixel(x,y);total+=(p>>16&255)*3+(p>>8&255)*6+(p&255);count++;}return total/(count*10.0);}
    private static Set<String> files(File directory,int depth)throws Exception{Set<String> result=new HashSet<>();if(depth<1||!directory.isDirectory())return result;File[] children=directory.listFiles();if(children!=null)for(File child:children)if(child.isFile())result.add(child.getCanonicalPath());else if(child.isDirectory())result.addAll(files(child,depth-1));return result;}
    private static boolean inside(File child,File root)throws Exception{return child.getCanonicalPath().startsWith(root.getCanonicalPath()+File.separator);}
    private interface Work{void run()throws Exception;}private interface Condition{boolean test()throws Exception;}
    private static void ui(Instrumentation instrumentation,Work work){Throwable[] failure={null};instrumentation.runOnMainSync(()->{try{work.run();}catch(Throwable problem){failure[0]=problem;}});if(failure[0]!=null)throw new RuntimeException(failure[0]);}
    private static void until(Instrumentation instrumentation,Condition condition,String name,JSONArray checks)throws Exception{long end=SystemClock.uptimeMillis()+30000;while(SystemClock.uptimeMillis()<end){boolean[] ready={false};ui(instrumentation,()->ready[0]=condition.test());if(ready[0]){check(checks,name,true);return;}SystemClock.sleep(25);}check(checks,name,false);}
    private static void check(JSONArray checks,String name,boolean value)throws Exception{checks.put(new JSONObject().put("name",name).put("passed",value));if(!value)throw new AssertionError(name);}
    private static Object get(Object instance,String name)throws Exception{Field field=instance.getClass().getDeclaredField(name);field.setAccessible(true);return field.get(instance);}
    private static int integer(Object value,String name)throws Exception{return (Integer)get(value,name);}
    private static Object call(Object value,String name,Class<?>[] parameterTypes,Object...arguments)throws Exception{Method method=value.getClass().getDeclaredMethod(name,parameterTypes);method.setAccessible(true);return method.invoke(value,arguments);}
    private static String sha(File file)throws Exception{MessageDigest digest=MessageDigest.getInstance("SHA-256");try(InputStream input=Files.newInputStream(file.toPath())){byte[] bytes=new byte[65536];int n;while((n=input.read(bytes))!=-1)digest.update(bytes,0,n);}StringBuilder text=new StringBuilder();for(byte b:digest.digest())text.append(String.format(Locale.ROOT,"%02x",b&255));return text.toString();}
}
