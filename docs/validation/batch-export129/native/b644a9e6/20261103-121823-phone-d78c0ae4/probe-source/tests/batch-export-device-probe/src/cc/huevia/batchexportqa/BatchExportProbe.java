package cc.huevia.batchexportqa;

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
import org.json.*;

/** Reflection only: exercises the installed local-album selection and existing export worker. */
public final class BatchExportProbe extends Instrumentation {
    private Bundle args; private Activity activity; private ClassLoader loader; private File output;
    private Object local, panel, batch, store; private String owner, stage="start"; private Throwable failure;
    private final JSONArray checks=new JSONArray(); private int screenshots;
    private final List<File> fixtures=new ArrayList<>(), resultFiles=new ArrayList<>();
    private final List<String> sourceShas=new ArrayList<>(); private final List<Dialog> dialogs=new ArrayList<>();
    private File parked; private Object frozenA, frozenB, newerA, photoA, photoB;
    private interface Work { void run() throws Exception; } private interface Condition { boolean test() throws Exception; }
    @Override public void onCreate(Bundle value){args=value;start();}
    @Override public void onStart(){
        try {
            loader=getTargetContext().getClassLoader();check("owned-emulator",Build.HARDWARE.equals("ranchu")||Build.HARDWARE.equals("goldfish"));
            check("exact-installed-candidate",sha(new File(getTargetContext().getApplicationInfo().sourceDir)).equals(args.getString("candidateSha256")));
            String run=args.getString("runId");check("safe-run-id",run!=null&&run.matches("[a-zA-Z0-9.-]+"));output=new File(getTargetContext().getExternalFilesDir(null),"batch-export129/"+run);output.getParentFile().mkdirs();check("new-evidence-directory",output.mkdir());
            activity=startActivitySync(new Intent().setClassName("cc.huevia","cc.huevia.MainActivity").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));until(()->(Boolean)get(activity,"ready"),"activity ready");
            boolean landscape="landscape".equals(args.getString("mode"));ui(()->activity.setRequestedOrientation(landscape?ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE:ActivityInfo.SCREEN_ORIENTATION_PORTRAIT));until(()->activity.getResources().getConfiguration().orientation==(landscape?2:1),"orientation");
            local=get(activity,"localAlbum");panel=get(activity,"localPhotoEditor");batch=get(local,"photoPresets");owner=(String)stat("cc.huevia.ui.PhotoFilterEditor","accountOwner",activity);
            store=cls("album.PhotoEditStore").getConstructor(File.class,String.class).newInstance(activity.getFilesDir(),owner);
            File a=fixture("A",1),b=fixture("B",6);photoA=photo(a);photoB=photo(b);frozenA=draft(a,10,true);frozenB=draft(b,-10,false);newerA=draft(a,0,false);call(store,"save",frozenA);call(store,"save",frozenB);
            ui(()->{call(activity,"switchRoot",3);call(local,"refresh");});until(()->!((Boolean)get(local,"loadingApp"))&&ownedItems().size()==2,"two owned album groups");
            selectAndInspect();Dialog settings=openExport();List<?> previews=(List<?>)get(settings,"previewRequests");
            check("two-independent-preview-requests",previews.size()==2);Set<String> expected=new HashSet<>(Arrays.asList((String)call(frozenA,"identity"),(String)call(frozenB,"identity")));Set<String> actual=new HashSet<>();for(Object p:previews)actual.add((String)get(p,"identity"));check("each-photo-keeps-own-draft",actual.equals(expected));
            List<?> items=(List<?>)get(settings,"items");Set<String> sizes=new HashSet<>();for(Object item:items)sizes.add(get(item,"fullWidth")+"x"+get(item,"fullHeight"));check("crop-and-exif-dimensions-independent",sizes.equals(new HashSet<>(Arrays.asList("160x240","240x320"))));
            screenshot("02-batch-export-settings");ui(settings::dismiss);check("cancel-settings-keeps-selection",((Set<?>)get(local,"selected")).size()==2&&(Boolean)get(local,"selecting"));
            if(!"ui".equals(args.getString("scope")))exportAndRetry();
            stage="finished";
        }catch(Throwable t){failure=unwrap(t);try{screenshot("failure");}catch(Throwable ignored){}}
        finally {
            try {ui(()->{for(Dialog d:dialogs)if(d.isShowing())d.dismiss();Object p=panel==null?null:get(panel,"exportProgress");if(p instanceof Dialog)((Dialog)p).dismiss();});}catch(Throwable ignored){}
            try {if(batch!=null&&(Boolean)call(batch,"isActive")){ui(()->call(batch,"cancel"));until(()->!(Boolean)call(batch,"isActive"),"cancel owned job");}}catch(Throwable t){if(failure==null)failure=unwrap(t);}
            try {
                if(parked!=null&&parked.exists()){File original=fixtures.get(1);if(!original.exists())Files.move(parked.toPath(),original.toPath());}
                if(store!=null)for(String s:sourceShas)Files.deleteIfExists(new File((File)get(store,"root"),s+".draft").toPath());
                for(File f:resultFiles){String key=f.getName().replace("effect-","").replace("__Effect.JPG","");Files.deleteIfExists(f.toPath());for(String dir:new String[]{"photo-preset-results","photo-preset-sources"}){File record=new File(getTargetContext().getFilesDir(),dir+"/"+key+".record");Files.deleteIfExists(record.toPath());Files.deleteIfExists(new File(record+".bak").toPath());}}
                for(File f:fixtures)Files.deleteIfExists(f.toPath());check("owned-originals-and-results-cleaned",fixtures.stream().noneMatch(File::exists)&&resultFiles.stream().noneMatch(File::exists));
            }catch(Throwable t){if(failure==null)failure=unwrap(t);}
            try {ui(()->{if(activity!=null){activity.setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED);activity.finish();}});}catch(Throwable ignored){}
        }
        Bundle result=new Bundle();try{JSONObject report=new JSONObject().put("pass",failure==null).put("stage",stage).put("mode",args.getString("mode")).put("scope",args.getString("scope")).put("candidateSha256",args.getString("candidateSha256")).put("checks",checks).put("screenshots",screenshots).put("privateFixtureRemoved",fixtures.stream().noneMatch(File::exists)).put("privateResultsRemoved",resultFiles.stream().noneMatch(File::exists));if(failure!=null)report.put("failure",failure.toString()).put("stack",android.util.Log.getStackTraceString(failure));if(output!=null)Files.write(new File(output,"report.json").toPath(),report.toString(2).getBytes(StandardCharsets.UTF_8));result.putString("stream",(failure==null?"PASS":"FAIL")+" "+checks.length()+" checks "+stage+(failure==null?"":" "+failure));}catch(Throwable t){result.putString("stream","FAIL report "+t);}finish(failure==null?Activity.RESULT_OK:Activity.RESULT_CANCELED,result);
    }
    private void selectAndInspect()throws Exception {
        stage="selection-entry";List<?> items=ownedItems();Object first=items.get(0),second=items.get(1);
        View root=(View)get(local,"root");ui(()->tile(root,(String)call(first,"name")).performLongClick());ui(()->tile(root,(String)call(second,"name")).performClick());
        check("native-longpress-and-click-select-two",((Set<?>)get(local,"selected")).size()==2);
        Button export=(Button)find(root,"local-album-batch-export"),edit=(Button)find(root,"local-album-batch-edit");until(()->export.isShown()&&export.getWidth()>0,"selection layout");
        check("direct-export-and-edit-visible",export.isEnabled()&&edit.isEnabled()&&export.isShown()&&edit.isShown());Rect e=new Rect(),d=new Rect();export.getGlobalVisibleRect(e);edit.getGlobalVisibleRect(d);
        check("parallel-actions-no-overlap",!Rect.intersects(e,d));check("export-full-touch-target",e.height()>=Math.round(48*activity.getResources().getDisplayMetrics().density));
        check("export-label-unclipped",export.getLayout()!=null&&export.getLayout().getEllipsisCount(0)==0&&export.getLayout().getLineWidth(0)<=export.getWidth()-export.getCompoundPaddingLeft()-export.getCompoundPaddingRight()+1);
        screenshot("01-app-album-selection");
    }
    private Dialog openExport()throws Exception {
        stage="settings";ui(()->find((View)get(local,"root"),"local-album-batch-export").performClick());until(()->get(panel,"batchExportDialog") instanceof Dialog&&((Dialog)get(panel,"batchExportDialog")).isShowing(),"batch settings");Dialog d=(Dialog)get(panel,"batchExportDialog");dialogs.add(d);return d;
    }
    private void exportAndRetry()throws Exception {
        stage="frozen-export-partial-failure";Dialog d=openExport();Object appOnly=Enum.valueOf((Class)cls("album.PhotoSaveTarget"),"APP_ONLY");ui(()->{set(d,"destination",appOnly);call(d,"refresh");});until(()->!(Boolean)get(d,"availabilityChecking")&&find(d.getWindow().getDecorView(),"export-confirm").isEnabled(),"app-only availability");
        call(store,"save",newerA);parked=new File(fixtures.get(1).getParentFile(),"batch129-parked-"+UUID.randomUUID()+".tmp");Files.move(fixtures.get(1).toPath(),parked.toPath());
        ui(()->find(d.getWindow().getDecorView(),"export-confirm").performClick());until(()->{Object s=call(batch,"state");return !(Boolean)get(s,"active")&&((Number)get(s,"total")).intValue()==2;},"partial batch complete");
        Object firstState=call(batch,"state");check("partial-batch-one-success-one-failure",num(firstState,"completed")==1&&num(firstState,"failed")==1);
        for(Object p:(List<?>)get(firstState,"results"))resultFiles.add((File)call(p,"file"));
        check("frozen-accepted-draft-not-later-change",findResult(photoA,frozenA)!=null);check("later-independent-draft-kept",call(call(store,"read",sourceShas.get(0)),"identity").equals(call(newerA,"identity"))&&!(Boolean)get(call(store,"read",sourceShas.get(0)),"exported"));
        List<?> retry=(List<?>)call(batch,"retryEdits");check("retry-only-unfinished-photo",retry.size()==1&&call(get(retry.get(0),"draft"),"identity").equals(call(frozenB,"identity")));
        check("retry-keeps-destination-and-account",get(retry.get(0),"saveTarget")==appOnly&&(Boolean)get(retry.get(0),"accountBound")&&owner.equals(get(retry.get(0),"accountScope")));
        Files.move(parked.toPath(),fixtures.get(1).toPath());ui(()->{Object p=get(panel,"exportProgress");if(p instanceof Dialog)((Dialog)p).dismiss();call(panel,"startEditedExport",retry);});until(()->{Object s=call(batch,"state");return !(Boolean)get(s,"active")&&num(s,"total")==1&&num(s,"completed")==1;},"retry complete");
        Object secondState=call(batch,"state");check("retry-completed-without-reprocessing-success",num(secondState,"failed")==0&&num(secondState,"completed")==1);
        for(Object p:(List<?>)get(secondState,"results"))resultFiles.add((File)call(p,"file"));Object resultA=findResult(photoA,frozenA),resultB=findResult(photoB,frozenB);check("two-independent-finished-results",resultA!=null&&resultB!=null&&!call(resultA,"file").equals(call(resultB,"file")));
        File af=(File)call(resultA,"file"),bf=(File)call(resultB,"file");Bitmap a=BitmapFactory.decodeFile(af.getPath()),b=BitmapFactory.decodeFile(bf.getPath());try{int bo=new android.media.ExifInterface(bf.getPath()).getAttributeInt("Orientation",1);int bw=bo>=5?b.getHeight():b.getWidth(),bh=bo>=5?b.getWidth():b.getHeight();check("actual-jpeg-keeps-crop-and-orientation",a.getWidth()==160&&a.getHeight()==240&&bw==240&&bh==320);check("opposite-adjustments-produce-opposite-brightness",luma(a.getPixel(a.getWidth()/2,a.getHeight()/2))>luma(b.getPixel(b.getWidth()/2,b.getHeight()/2))+30);}finally{a.recycle();b.recycle();}
        check("original-bytes-unchanged",sha(fixtures.get(0)).equals(sourceShas.get(0))&&sha(fixtures.get(1)).equals(sourceShas.get(1)));check("successful-retry-draft-recorded-exported",(Boolean)get(call(store,"read",sourceShas.get(1)),"exported"));
    }
    private Object findResult(Object photo,Object draft)throws Exception{Object source=stat("cc.huevia.album.PhotoPresetBatch$Source","local",photo);Object edit=stat("cc.huevia.album.PhotoPresetBatch$Edit","draft",source,draft,owner);return call(batch,"findResult",edit);}
    private File fixture(String label,int orientation)throws Exception {File dir=new File(getTargetContext().getExternalFilesDir(Environment.DIRECTORY_PICTURES),"camera-album");dir.mkdirs();File f=new File(dir,"batch129-"+UUID.randomUUID()+"__"+label+".JPG");Bitmap b=Bitmap.createBitmap(320,240,Bitmap.Config.ARGB_8888);b.eraseColor(0xff777777);Canvas c=new Canvas(b);Paint p=new Paint();p.setColor(0xff896c58);c.drawRect(0,0,35,240,p);try(OutputStream out=new FileOutputStream(f)){b.compress(Bitmap.CompressFormat.JPEG,98,out);}finally{b.recycle();}android.media.ExifInterface e=new android.media.ExifInterface(f.getPath());e.setAttribute("Orientation",String.valueOf(orientation));e.setAttribute("ImageDescription","batch129 isolated "+UUID.randomUUID());e.saveAttributes();fixtures.add(f);sourceShas.add(sha(f));return f;}
    private Object photo(File f)throws Exception{Constructor<?> c=cls("album.DownloadedPhoto").getDeclaredConstructor(File.class,String.class);c.setAccessible(true);return c.newInstance(f,f.getName());}
    private Object draft(File f,int exposure,boolean crop)throws Exception{Object[] params=(Object[])cls("ncp.PhotoAdjustments$Parameter").getMethod("values").invoke(null);int[] values=new int[params.length];values[0]=exposure;Object adjustments=cls("ncp.PhotoAdjustments").getConstructor(int[].class).newInstance((Object)values);Object geometry=cls("ncp.PhotoGeometry").getConstructor(int.class,int.class,int.class,int.class,int.class,int.class).newInstance(0,0,0,0,crop?500000:1000000,1000000);return cls("album.PhotoEditStore$Draft").getConstructor(String.class,byte[].class,String.class,int.class,cls("ncp.PhotoAdjustments"),cls("ncp.PhotoGeometry"),boolean.class).newInstance(sha(f),new byte[0],"batch129",0,adjustments,geometry,false);}
    private List<Object> ownedItems()throws Exception{List<Object> found=new ArrayList<>();for(Object item:(List<?>)get(local,"appPhotos")){Object photo=get(item,"photo");if(photo!=null&&fixtures.contains((File)call(photo,"file")))found.add(item);}return found;}
    private View tile(View v,String filename){if(v.isLongClickable()&&v.getContentDescription()!=null&&v.getContentDescription().toString().startsWith(filename))return v;if(v instanceof ViewGroup)for(int i=0;i<((ViewGroup)v).getChildCount();i++){View r=tile(((ViewGroup)v).getChildAt(i),filename);if(r!=null)return r;}return null;}
    private View find(View v,String tag){if(tag.equals(v.getTag()))return v;if(v instanceof ViewGroup)for(int i=0;i<((ViewGroup)v).getChildCount();i++){View r=find(((ViewGroup)v).getChildAt(i),tag);if(r!=null)return r;}return null;}
    private int luma(int p){return(Color.red(p)+Color.green(p)+Color.blue(p))/3;}private int num(Object o,String f)throws Exception{return((Number)get(o,f)).intValue();}
    private Class<?> cls(String name)throws Exception{return loader.loadClass("cc.huevia."+name);}
    private void screenshot(String name)throws Exception{CountDownLatch frames=new CountDownLatch(1);ui(()->Choreographer.getInstance().postFrameCallback(t->Choreographer.getInstance().postFrameCallback(n->frames.countDown())));frames.await(2,TimeUnit.SECONDS);Bitmap b=getUiAutomation().takeScreenshot();try(OutputStream out=new FileOutputStream(new File(output,name+".png"))){b.compress(Bitmap.CompressFormat.PNG,100,out);screenshots++;}finally{b.recycle();}}
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
