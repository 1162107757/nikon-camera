package cc.huevia.rawdevelopmentqa;
import android.app.*;
import android.content.*;
import android.graphics.*;
import android.net.Uri;
import android.os.*;
import android.provider.MediaStore;
import android.view.*;
import android.widget.*;
import java.io.*;
import java.lang.reflect.*;
import java.nio.file.*;
import java.security.*;
import java.util.*;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.BooleanSupplier;
import org.json.*;

/** Exact app-only group deletion through the native album, preserving actual MediaStore bytes. */
public final class AlbumDeleteChecks {
    public static void run(RawDevelopmentProbe probe,Context context,File directory,JSONArray checks)throws Exception{
        ClassLoader loader=context.getClassLoader();Class<?> repositoryType=Class.forName("cc.huevia.album.LocalPhotoRepository",true,loader),photoType=Class.forName("cc.huevia.album.DownloadedPhoto",true,loader);
        File pictures=new File(context.getFilesDir(),"pictures/camera-album").getCanonicalFile();pictures.mkdirs();String nonce=UUID.randomUUID().toString();
        File original=new File(pictures,"QA180-delete-"+nonce+".jpg"),alias=new File(pictures,"QA180-alias-"+nonce+".jpg"),keep=new File(pictures,"QA180-keep-"+nonce+".jpg"),extra=new File(pictures,"QA180-extra-"+nonce+".jpg");
        File effect=null;List<File> own=new ArrayList<>(Arrays.asList(original,alias,keep,extra));Uri media=null;Activity activity=null;Object controller=null;Runnable observer=null;
        try{
            jpeg(original,nonce.hashCode());Files.copy(original.toPath(),alias.toPath());jpeg(keep,nonce.hashCode()+1);String keepSha=sha(keep),originalSha=sha(original);
            Constructor<?> photoConstructor=photoType.getDeclaredConstructor(File.class,String.class);photoConstructor.setAccessible(true);
            Object source=photoConstructor.newInstance(original,original.getName());String preset="a".repeat(64),model=(String)Class.forName("cc.huevia.album.PhotoPresetRenderer",true,loader).getField("MODEL_VERSION").get(null);
            String effectKey=hash((originalSha+"\n"+preset+"\n"+model).getBytes(java.nio.charset.StandardCharsets.UTF_8));effect=new File(pictures,"effect-"+effectKey+"__Effect.JPG");jpeg(effect,nonce.hashCode()+2);own.add(effect);
            File records=new File(context.getFilesDir(),"photo-preset-results");records.mkdirs();File record=new File(records,effectKey+".record");own.add(record);own.add(new File(records,effectKey+".source"));own.add(new File(records,effectKey+".meta"));
            try(DataOutputStream output=new DataOutputStream(new FileOutputStream(record))){output.writeInt(0x50424531);output.writeLong(effect.length());output.writeUTF(sha(effect));}
            Class<?> linksType=Class.forName("cc.huevia.album.PhotoPresetSources",true,loader);Constructor<?> linksConstructor=linksType.getDeclaredConstructor(File.class,File.class);linksConstructor.setAccessible(true);
            Object links=linksConstructor.newInstance(context.getFilesDir(),context.getExternalFilesDir("Pictures"));Object derived=photoConstructor.newInstance(effect,effect.getName());
            call(links,"bind",new Class<?>[]{photoType,photoType,String.class,String.class,BooleanSupplier.class},derived,source,preset,"测试效果",(BooleanSupplier)()->false);
            Object repository=repositoryType.getConstructor(Context.class).newInstance(context);List<?> groups=(List<?>)repositoryType.getMethod("appPhotos",BooleanSupplier.class).invoke(repository,(BooleanSupplier)()->false);
            Object selected=groupFor(groups,original);checks.put(new JSONObject().put("name","fixture-group-shape").put("passed",true).put("found",selected!=null).put("members",selected==null?-1:((List<?>)call(selected,"photos",new Class<?>[]{})).size()).put("versions",selected==null?-1:((List<?>)get(selected,"versions")).size()).put("groups",groups.size()));check(checks,"whole-group-contains-original-alias-and-effect",selected!=null&&((List<?>)call(selected,"photos",new Class<?>[]{})).size()==3&&((List<?>)get(selected,"versions")).size()==2);
            Files.copy(original.toPath(),extra.toPath());boolean rejected=false;
            try{repositoryType.getMethod("deleteAppPhotos",List.class).invoke(repository,List.of(selected));}catch(InvocationTargetException expected){rejected=expected.getCause() instanceof IOException;}
            check(checks,"new-version-after-snapshot-stops-delete",rejected&&original.isFile()&&alias.isFile()&&effect.isFile());Files.delete(extra.toPath());
            Class<?> tasks=Class.forName("cc.huevia.album.PhotoLocalTasks",true,loader);Method use=tasks.getDeclaredMethod("use");use.setAccessible(true);Object lease=use.invoke(null);
            try{rejected=false;try{repositoryType.getMethod("deleteAppPhotos",List.class).invoke(repository,List.of(selected));}catch(InvocationTargetException expected){rejected=expected.getCause() instanceof IOException;}check(checks,"active-photo-processing-blocks-delete",rejected&&original.isFile()&&effect.isFile());}finally{call(lease,"close",new Class<?>[]{});}
            ContentValues values=new ContentValues();values.put(MediaStore.Images.Media.DISPLAY_NAME,"QA180-public-"+nonce+".jpg");values.put(MediaStore.Images.Media.MIME_TYPE,"image/jpeg");values.put(MediaStore.Images.Media.RELATIVE_PATH,"Pictures/Huevia-QA180/");
            media=context.getContentResolver().insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI,values);check(checks,"public-photo-fixture-created",media!=null);
            try(InputStream in=new FileInputStream(original);OutputStream out=context.getContentResolver().openOutputStream(media)){in.transferTo(out);}
            activity=probe.startActivitySync(new Intent().setClassName("cc.huevia","cc.huevia.MainActivity").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));final Activity host=activity;
            until(probe,()->Boolean.TRUE.equals(get(host,"ready")),"album-main-ready",checks);controller=get(get(host,"connections"),"album");AtomicInteger events=new AtomicInteger();observer=events::incrementAndGet;controller.getClass().getMethod("addPhotoLibraryObserver",Runnable.class).invoke(controller,observer);
            ui(probe,()->call(host,"switchRoot",new Class<?>[]{int.class},3));Object album=get(host,"localAlbum");
            until(probe,()->!Boolean.TRUE.equals(get(album,"loadingApp"))&&findItem(album,original)!=null,"native-app-album-ready",checks);
            ui(probe,()->call(album,"toggle",new Class<?>[]{findItem(album,original).getClass()},findItem(album,original)));
            Button delete=(Button)get(album,"deleteButton");check(checks,"delete-visible-only-in-app-selection",delete.isShown()&&delete.isEnabled()&&delete.getContentDescription().toString().contains("删除"));
            check(checks,"delete-retains-48dp-target",delete.getWidth()/delete.getResources().getDisplayMetrics().density>=47.9&&delete.getHeight()/delete.getResources().getDisplayMetrics().density>=47.9);
            TextView counter=(TextView)get(album,"selectionCount");CharSequence previousCounter=counter.getText();ui(probe,()->counter.setText("100 张"));check(checks,"maximum-count-label-fits",counter.getWidth()-counter.getCompoundPaddingLeft()-counter.getCompoundPaddingRight()>=counter.getPaint().measureText("100 张"));ui(probe,()->counter.setText(previousCounter));View bar=(View)get(album,"selectionBar");check(checks,"delete-selection-toolbar-fits",delete.getRight()<=bar.getWidth()&&((View)get(album,"batchButton")).getRight()<=bar.getWidth());capture(probe,"app-delete-selection.png");
            ui(probe,delete::performClick);AlertDialog dialog=(AlertDialog)get(album,"deleteDialog");check(checks,"explicit-confirmation-shown",dialog!=null&&dialog.isShowing());capture(probe,"app-delete-confirmation.png");
            ui(probe,()->dialog.getButton(DialogInterface.BUTTON_NEGATIVE).performClick());check(checks,"cancel-preserves-all-versions",original.isFile()&&alias.isFile()&&effect.isFile());
            ui(probe,()->{call(album,"cancelSelection",new Class<?>[]{});call(album,"switchTab",new Class<?>[]{boolean.class},true);});
            until(probe,()->Boolean.TRUE.equals(get(album,"phone")),"phone-source-selected",checks);check(checks,"phone-album-does-not-offer-app-deletion",((View)get(album,"deleteButton")).getVisibility()==View.GONE);SystemClock.sleep(300);
            ui(probe,()->call(album,"switchTab",new Class<?>[]{boolean.class},false));until(probe,()->!Boolean.TRUE.equals(get(album,"phone"))&&findItem(album,original)!=null,"app-source-restored",checks);
            ui(probe,()->call(album,"toggle",new Class<?>[]{findItem(album,original).getClass()},findItem(album,original)));delete=(Button)get(album,"deleteButton");final Button action=delete;ui(probe,action::performClick);
            AlertDialog confirmed=(AlertDialog)get(album,"deleteDialog");
            java.util.concurrent.CountDownLatch gateEntered=new java.util.concurrent.CountDownLatch(1),gateRelease=new java.util.concurrent.CountDownLatch(1);
            ((java.util.concurrent.ExecutorService)get(album,"worker")).execute(()->{gateEntered.countDown();try{gateRelease.await();}catch(InterruptedException stopped){Thread.currentThread().interrupt();}});
            if(!gateEntered.await(5,java.util.concurrent.TimeUnit.SECONDS))throw new AssertionError("delete worker gate unavailable");
            try{
                ui(probe,()->confirmed.getButton(DialogInterface.BUTTON_POSITIVE).performClick());int request=(Integer)get(album,"importRequest");
                check(checks,"cancel-disabled-during-confirmed-delete",Boolean.TRUE.equals(get(album,"deleting"))&&!((View)get(album,"cancelButton")).isEnabled());
                ui(probe,()->call(album,"goBack",new Class<?>[]{}));check(checks,"back-preserves-confirmed-delete-and-result-callback",Boolean.TRUE.equals(get(album,"deleting"))&&request==(Integer)get(album,"importRequest"));capture(probe,"app-delete-working.png");
            }finally{gateRelease.countDown();}
            final File effectFile=effect;until(probe,()->!original.exists()&&!alias.exists()&&!effectFile.exists()&&!Boolean.TRUE.equals(get(album,"importing"))&&findItem(album,original)==null,"confirm-deletes-all-three-private-members",checks);
            check(checks,"other-app-photo-untouched",keep.isFile()&&keepSha.equals(sha(keep)));try(InputStream in=context.getContentResolver().openInputStream(media)){check(checks,"public-MediaStore-original-retained-exactly",in!=null&&originalSha.equals(hash(in)));}
            check(checks,"deletion-notifies-shared-photo-library",events.get()>0);capture(probe,"app-delete-complete.png");
        }finally{
            if(controller!=null&&observer!=null)controller.getClass().getMethod("removePhotoLibraryObserver",Runnable.class).invoke(controller,observer);
            if(activity!=null){final Activity host=activity;ui(probe,host::finish);SystemClock.sleep(250);}
            if(media!=null)context.getContentResolver().delete(media,null,null);
            for(File file:own)Files.deleteIfExists(file.toPath());
        }
    }
    private static Object groupFor(List<?> groups,File file)throws Exception{for(Object group:groups)if(call(group,"findByFile",new Class<?>[]{File.class},file)!=null)return group;return null;}
    private static Object findItem(Object album,File file)throws Exception{for(Object item:(List<?>)get(album,"appPhotos")){Object photo=get(item,"photo");if(photo!=null&&file.equals(call(photo,"file",new Class<?>[]{})))return item;Object group=get(item,"group");if(group!=null&&call(group,"findByFile",new Class<?>[]{File.class},file)!=null)return item;}return null;}
    private static Object get(Object owner,String name)throws Exception{Field f=owner.getClass().getDeclaredField(name);f.setAccessible(true);return f.get(owner);}
    private static Object call(Object owner,String name,Class<?>[] types,Object...args)throws Exception{Method m=owner.getClass().getDeclaredMethod(name,types);m.setAccessible(true);try{return m.invoke(owner,args);}catch(InvocationTargetException e){if(e.getCause() instanceof Exception)throw(Exception)e.getCause();throw new AssertionError(e.getCause());}}
    private interface Work{void run()throws Exception;}private interface Condition{boolean test()throws Exception;}
    private static void ui(Instrumentation p,Work work)throws Exception{Throwable[] failure={null};p.runOnMainSync(()->{try{work.run();}catch(Throwable error){failure[0]=error;}});if(failure[0]!=null)throw new Exception(failure[0]);p.waitForIdleSync();}
    private static void until(Instrumentation p,Condition condition,String name,JSONArray checks)throws Exception{long end=SystemClock.uptimeMillis()+15000;while(SystemClock.uptimeMillis()<end){p.waitForIdleSync();try{if(condition.test()){check(checks,name,true);return;}}catch(Exception ignored){}SystemClock.sleep(30);}check(checks,name,false);}
    private static void check(JSONArray checks,String name,boolean pass)throws Exception{checks.put(new JSONObject().put("name",name).put("passed",pass));if(!pass)throw new AssertionError(name);}
    private static void jpeg(File file,int seed)throws Exception{int[] pixels=new int[96*64];Random random=new Random(seed);for(int i=0;i<pixels.length;i++)pixels[i]=0xff000000|random.nextInt(0x1000000);Bitmap bitmap=Bitmap.createBitmap(pixels,96,64,Bitmap.Config.ARGB_8888);try(OutputStream out=new FileOutputStream(file)){if(!bitmap.compress(Bitmap.CompressFormat.JPEG,95,out))throw new IOException("Fixture encoding");}finally{bitmap.recycle();}}
    private static String sha(File f)throws Exception{try(InputStream in=new FileInputStream(f)){return hash(in);}}private static String hash(InputStream in)throws Exception{MessageDigest digest=MessageDigest.getInstance("SHA-256");byte[] b=new byte[65536];int n;while((n=in.read(b))!=-1)digest.update(b,0,n);return hex(digest.digest());}private static String hash(byte[] bytes)throws Exception{return hex(MessageDigest.getInstance("SHA-256").digest(bytes));}private static String hex(byte[] bytes){StringBuilder result=new StringBuilder();for(byte b:bytes)result.append(String.format(Locale.ROOT,"%02x",b&255));return result.toString();}
    private static void capture(RawDevelopmentProbe p,String name)throws Exception{p.waitForIdleSync();Bitmap bitmap=p.getUiAutomation().takeScreenshot();try(OutputStream out=new FileOutputStream(new File(p.output,name))){if(bitmap==null||!bitmap.compress(Bitmap.CompressFormat.PNG,100,out))throw new IOException("Screenshot");}finally{if(bitmap!=null)bitmap.recycle();}}
}
