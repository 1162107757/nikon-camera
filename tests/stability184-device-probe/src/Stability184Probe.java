package cc.huevia.stability184qa;

import android.app.*;
import android.content.*;
import android.graphics.*;
import android.os.*;
import android.view.*;
import cc.huevia.album.*;
import cc.huevia.ncp.*;
import java.io.*;
import java.lang.reflect.*;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicReference;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.Consumer;
import org.json.*;

/** Uses installed app classes and real Android codecs. Own synthetic private JPEGs only. */
public final class Stability184Probe extends Instrumentation {
    private Bundle args; private Activity activity; private File output;
    private final JSONArray checks = new JSONArray(), exports = new JSONArray();
    private final JSONObject report = new JSONObject();
    private final List<File> owned = new ArrayList<>();
    private long version;
    private String appearance;
    @Override public void onCreate(Bundle args) { this.args=args; start(); }
    @Override public void onStart() {
        Throwable failure=null;
        try {
            check("ranchu".equals(Build.HARDWARE)||"goldfish".equals(Build.HARDWARE),"owned-emulator");
            String run=args.getString("runId"); check(run!=null&&run.matches("[A-Za-z0-9.-]{8,100}"),"safe-run-id");
            version=getTargetContext().getPackageManager().getPackageInfo("cc.huevia",0).getLongVersionCode();
            check(version==183||version==184,"exact-baseline183-or-fixed184");
            output=new File(getTargetContext().getExternalFilesDir(null),"stability184/"+run);check(output.mkdirs(),"new-evidence-directory");
            report.put("versionCode",version).put("sdk",Build.VERSION.SDK_INT);
            appearance=cc.huevia.ui.AppAppearance.mode(getTargetContext());
            cc.huevia.ui.AppAppearance.setMode(getTargetContext(),args.getString("appearance","light"));
            activity=startActivitySync(new Intent(Intent.ACTION_MAIN).setClassName("cc.huevia","cc.huevia.MainActivity").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK|Intent.FLAG_ACTIVITY_CLEAR_TASK));
            until(()->Boolean.TRUE.equals(get(activity,"ready")),"actual-main-ready");
            for(int repeat=0;repeat<3;repeat++) for(int destination:new int[]{1,3,2,0}) {
                final int target=destination;ui(()->call(activity,"switchRoot",target));settle();
                check(!activity.isFinishing()&&!activity.isDestroyed(),"root-navigation-"+repeat+"-"+target);
            }
            for(int repeat=0;repeat<8;repeat++) {
                final boolean local=repeat%2==0;ui(()->call(activity,"selectPresetSource",local));settle();
                check(Boolean.valueOf(local).equals(get(activity,"localTab")),"preset-source-switch-"+repeat);
            }
            ui(()->{call(activity,"showPresetFilters");});settle();
            Dialog filter=(Dialog)get(activity,"presetFilterSheet");check(filter.isShowing(),"filter-dialog-opens-on-runtime");
            capture("01-filter-open");ui(filter::dismiss);settle();
            check(!filter.isShowing(),"filter-closes-without-crash");
            documentFailurePaths();
            previewArrayCopy();
            PhotoAdjustments manual=PhotoAdjustments.NONE.with(PhotoAdjustments.Parameter.EXPOSURE,1);
            PhotoGeometry crop=new PhotoGeometry(0,0,100000,100000,900000,900000);
            PhotoBorder frame=PhotoBorder.NONE.withTemplate(1);
            PhotoLocalEdits local=new PhotoLocalEdits(Collections.singletonList(PhotoLocalEdits.Mask.radial(.5,.5).parameters(5,0,0)),Collections.emptyList());
            runExport(run,"simple-full",manual,crop,frame,PhotoLocalEdits.NONE,PhotoExportSpec.full(),false);
            runExport(run,"local-crop-frame-full",manual,crop,frame,local,PhotoExportSpec.full(),true);
            runExport(run,"local-crop-frame-share",manual,crop,frame,local,PhotoExportSpec.share(),false);
            check(!((PhotoPresetBatch)get(get(activity,"connections"),"photoPresets")).isActive(),"no-export-left-active");
            // Test the concrete runtime-backed String path, rather than blaming source-only isBlank calls.
            check(RawEditorSource.jpegName(" ").equals("RAW.jpg"),"actual-D8-backported-string-path-on-runtime");
            Constructor<?> phoneConstructor=LocalPhotoRepository.PhonePhoto.class.getDeclaredConstructor(android.net.Uri.class,String.class,String.class,long.class,long.class,long.class);
            phoneConstructor.setAccessible(true);Object phone=phoneConstructor.newInstance(android.net.Uri.parse("content://stability184/photo"),"","image/jpeg",0L,0L,0L);
            check(phone!=null,"phone-metadata-constructs-on-runtime");
            if(version>=184) diagnosticsEvidence(run);
            capture("02-after-exports");
            report.put("scope","Actual installed MainActivity/root navigation/source/filter and PhotoPresetBatch, real synthetic JPEG codecs, simple/full and local+crop+border full/share. Baseline183 must reproduce its own model-limit error;184 must commit/reuse exact outputs. No physical Honor/camera or memory-pressure certification.");
        } catch(Throwable t) { failure=t; try{report.put("failure",android.util.Log.getStackTraceString(t));}catch(Exception ignored){} }
        finally {
            try{if(activity!=null)ui(activity::finish);if(appearance!=null)cc.huevia.ui.AppAppearance.setMode(getTargetContext(),appearance);}catch(Throwable ignored){}
            List<String> retained=new ArrayList<>();
            for(int i=owned.size()-1;i>=0;i--){File f=owned.get(i);if(f.exists()&&!f.delete())retained.add(f.getPath());}
            try{report.put("pass",failure==null).put("checks",checks).put("exports",exports).put("cleanupRemaining",new JSONArray(retained)).put("candidateSha256",args.getString("candidateSha256"));if(output!=null)try(Writer w=new OutputStreamWriter(new FileOutputStream(new File(output,"report.json")),"UTF-8")){w.write(report.toString(2));}}catch(Exception ignored){}
            Bundle result=new Bundle();result.putString("result",report.toString());finish(failure==null?-1:0,result);
        }
    }
    private void previewArrayCopy() throws Exception {
        PresetPreviewProfile original=AdjustedPreviewProfile.of(null,PhotoAdjustments.NONE);
        int[] pixels={0xff123456,0xffabcdef,0xff000000,0xffffffff};
        int[] saved=Arrays.copyOf(pixels,pixels.length);
        try {
            int[] result=original.render(pixels,2,2);
            check(Arrays.equals(saved,result)&&result!=pixels,"interface-default-preview-independent-pixel-copy");
            check(Arrays.equals(saved,pixels),"interface-default-preview-source-untouched");
            PresetPreviewProfile adjusted=AdjustedPreviewProfile.of(null,PhotoAdjustments.NONE.with(PhotoAdjustments.Parameter.EXPOSURE,1));
            for(PresetPreviewProfile profile:new PresetPreviewProfile[]{adjusted,StrengthPreviewProfile.of(adjusted,50)}) {
                int[] rendered=profile.render(pixels,2,2), expected=Arrays.copyOf(pixels,pixels.length);
                for(int i=0;i<expected.length;i++)expected[i]=profile.applyArgb(expected[i]);
                check(Arrays.equals(expected,rendered),"interface-default-preview-transform-"+profile.getClass().getSimpleName());
            }
            check(version!=183||Build.VERSION.SDK_INT!=31,"baseline183-android12-preview-must-reproduce-clone-error");
        } catch(IllegalAccessError error) {
            if(version!=183||Build.VERSION.SDK_INT!=31)throw error;
            check(error.getMessage().contains("clone"),"baseline183-android12-interface-array-clone-crash");
            report.put("baselinePreviewCrash",android.util.Log.getStackTraceString(error));
        }
    }
    private void documentFailurePaths()throws Exception {
        String saved=(String)get(activity,"report");
        try {
            for(boolean security:new boolean[]{false,true}) {
                ActivityMonitor monitor=new ActivityMonitor(){@Override public ActivityResult onStartActivity(Intent intent){
                    if(Intent.ACTION_CREATE_DOCUMENT.equals(intent.getAction())) {if(security)throw new SecurityException("QA blocked picker");throw new ActivityNotFoundException("QA absent picker");}return null;}};
                addMonitor(monitor);Throwable error=null;
                try{ui(()->{set(activity,"report","{}");call(activity,"exportReport");});}catch(Throwable caught){error=unwrap(caught);}finally{removeMonitor(monitor);}
                if(version==183)check(security?error instanceof SecurityException:error instanceof ActivityNotFoundException,"baseline-unguarded-report-picker-"+security);
                else {check(error==null,"report-picker-failure-contained-"+security);ui(()->call(get(activity,"topNotice"),"dismiss"));settle();check(!activity.isFinishing(),"picker-failure-keeps-main-alive-"+security);}
            }
            if(version>=184) {
                List<String> errors=new ArrayList<>();AtomicInteger fallbackCalls=new AtomicInteger();
                ActivityMonitor fallback=new ActivityMonitor(){@Override public ActivityResult onStartActivity(Intent intent){
                    if(Intent.ACTION_OPEN_DOCUMENT.equals(intent.getAction()))throw new ActivityNotFoundException("QA primary absent");
                    if(Intent.ACTION_GET_CONTENT.equals(intent.getAction())){fallbackCalls.incrementAndGet();if((intent.getFlags()&Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)!=0)throw new AssertionError("ephemeral fallback claims persistence");return new ActivityResult(Activity.RESULT_CANCELED,null);}return null;}};
                addMonitor(fallback);
                final Intent original=new Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("image/*").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION|Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION);
                final Object[] result={null};
                try{ui(()->result[0]=Class.forName("cc.huevia.SystemActivityLauncher").getMethod("document",Activity.class,Intent.class,int.class,Consumer.class).invoke(null,activity,original,9911,(Consumer<String>)errors::add));}finally{removeMonitor(fallback);}
                check(Boolean.TRUE.equals(result[0])&&fallbackCalls.get()==1&&errors.isEmpty(),"document-picker-supported-fallback");
                check(Intent.ACTION_OPEN_DOCUMENT.equals(original.getAction()),"fallback-does-not-mutate-original-intent");
                ActivityMonitor blocked=new ActivityMonitor(){@Override public ActivityResult onStartActivity(Intent intent){if(intent.getAction()!=null&&intent.getAction().startsWith("qa184."))throw new SecurityException("QA settings blocked");return null;}};
                addMonitor(blocked);errors.clear();
                try{ui(()->result[0]=Class.forName("cc.huevia.SystemActivityLauncher").getMethod("settings",Activity.class,Intent.class,Intent.class,Consumer.class).invoke(null,activity,new Intent("qa184.primary"),new Intent("qa184.fallback"),(Consumer<String>)errors::add));}finally{removeMonitor(blocked);}
                check(Boolean.FALSE.equals(result[0])&&errors.size()==1,"both-settings-entrypoints-blocked-with-one-recoverable-error");
            }
        }finally{ui(()->set(activity,"report",saved));}
    }
    private void diagnosticsEvidence(String run)throws Exception {
        check(Thread.getDefaultUncaughtExceptionHandler().getClass().getName().contains("AppCrashDiagnostics"),"app-installs-chained-crash-recorder");
        Class<?> diagnostics=Class.forName("cc.huevia.AppCrashDiagnostics");
        JSONObject snapshot=(JSONObject)diagnostics.getMethod("snapshot",Context.class).invoke(null,activity);
        check(snapshot.getInt("sdk")==Build.VERSION.SDK_INT&&!snapshot.has("collectionError"),"actual-platform-exit-history-collection");
        String appended=(String)diagnostics.getMethod("appendToReport",Context.class,String.class).invoke(null,activity,"{\"sentinel\":184}");
        JSONObject report=new JSONObject(appended);check(report.getInt("sentinel")==184&&report.has("appStability"),"diagnostics-export-preserves-original-report");
        File dir=new File(getTargetContext().getCacheDir(),"crash-recorder-qa184-"+run);check(!dir.exists(),"new-isolated-crash-fixture");owned.add(dir);
        Class<?> recorder=Class.forName("cc.huevia.AppCrashDiagnostics$CrashRecorder");Constructor<?> c=recorder.getDeclaredConstructor(File.class,String.class,Thread.UncaughtExceptionHandler.class);c.setAccessible(true);
        AtomicInteger chained=new AtomicInteger();Throwable original=new IllegalStateException("native QA recorder fixture");
        Thread.UncaughtExceptionHandler previous=(thread,error)->{if(error!=original)throw new AssertionError("wrong error delegated");chained.incrementAndGet();};
        ((Thread.UncaughtExceptionHandler)c.newInstance(dir,"fixture SDK="+Build.VERSION.SDK_INT,previous)).uncaughtException(Thread.currentThread(),original);
        File file=new File(dir,"last-crash.txt");owned.add(file);
        check(chained.get()==1&&file.isFile()&&file.length()<=65536,"native-recorder-is-bounded-and-keeps-original-handler");
        this.report.put("stabilitySnapshot",snapshot);
    }
    private static Throwable unwrap(Throwable error){while((error instanceof InvocationTargetException||error instanceof RuntimeException)&&error.getCause()!=null)error=error.getCause();return error;}
    private void runExport(String run,String label,PhotoAdjustments manual,PhotoGeometry geometry,PhotoBorder border,PhotoLocalEdits local,PhotoExportSpec spec,boolean baselineFailure)throws Exception {
        File dir=new File(new File(getTargetContext().getFilesDir(),"pictures"),"camera-album");if(!dir.isDirectory()&&!dir.mkdirs())throw new IOException("fixture directory");
        File original=new File(dir,"qa184-"+run+"-"+label+".jpg");check(!original.exists(),label+"-new-fixture");owned.add(original);writeFixture(original,label);
        String sourceHash=sha(original),owner="stability184-"+run+"-"+label;
        PhotoEditStore.Draft draft=new PhotoEditStore.Draft(sourceHash,null,"",100,manual,geometry,border,local,false);
        PhotoPresetRenderer.Dimensions dimensions=PhotoPresetRenderer.dimensions(original,draft.profile());
        PhotoExportSpec.Resolved resolved=spec.resolve(dimensions.width,dimensions.height);
        String model=PhotoPresetRenderer.modelVersion(draft.profile(),resolved);
        JSONObject row=new JSONObject().put("case",label).put("modelLength",model.length()).put("model",model);
        if(baselineFailure)check(model.length()>256,label+"-legitimate-model-over-old-limit");
        Constructor<DownloadedPhoto> photoConstructor=DownloadedPhoto.class.getDeclaredConstructor(File.class,String.class,String.class,String.class);
        photoConstructor.setAccessible(true);DownloadedPhoto source=photoConstructor.newInstance(original,original.getName(),"","");
        PhotoPresetBatch batch=(PhotoPresetBatch)get(get(activity,"connections"),"photoPresets");
        PhotoPresetBatch.Edit edit=PhotoPresetBatch.Edit.draft(PhotoPresetBatch.Source.local(source),draft,owner,spec);
        CountDownLatch done=new CountDownLatch(1);AtomicReference<PhotoPresetBatchState> complete=new AtomicReference<>();AtomicReference<String> startError=new AtomicReference<>();
        ui(()->batch.startEdits(Collections.singletonList(edit),PhotoSaveTarget.APP_ONLY,false,new AlbumController.Callback<Void>(){public void onSuccess(Void value){}public void onError(String value){startError.set(value);done.countDown();}},new AlbumController.Callback<PhotoPresetBatchState>(){public void onSuccess(PhotoPresetBatchState value){complete.set(value);done.countDown();}public void onError(String value){startError.set(value);done.countDown();}}));
        check(done.await(60,TimeUnit.SECONDS),label+"-batch-completes");
        check(startError.get()==null,label+"-request-accepted");PhotoPresetBatchState state=complete.get();check(state!=null&&!state.active,label+"-terminal-state");
        row.put("failed",state.failed).put("completed",state.completed).put("error",state.error).put("errors",new JSONArray(state.errors));
        if(version==183&&baselineFailure) {
            check(state.failed==1&&state.completed==0&&state.errors.toString().contains("效果模型无效"),label+"-baseline-reproduces-real-error");
        } else {
            check(state.failed==0&&state.completed==1&&state.results.size()==1,label+"-export-succeeds");
            File target=state.results.get(0).file();owned.add(target);String key=target.getName().substring(7,71);
            File records=new File(getTargetContext().getFilesDir(),"photo-preset-results");
            for(String suffix:new String[]{".source",".model",".record",".meta"})owned.add(new File(records,key+suffix));
            BitmapFactory.Options bounds=new BitmapFactory.Options();bounds.inJustDecodeBounds=true;BitmapFactory.decodeFile(target.getPath(),bounds);
            check(bounds.outWidth==resolved.width&&bounds.outHeight==resolved.height,label+"-real-output-dimensions");
            check(sourceHash.equals(sha(original)),label+"-original-unchanged");
            check(batch.findResult(edit)!=null,label+"-completed-output-found-with-same-identity");
            check(batch.sourceFor(state.results.get(0)).file().getCanonicalFile().equals(original.getCanonicalFile()),label+"-durable-source-link");
            try(DataInputStream in=new DataInputStream(new FileInputStream(new File(records,key+".model")))){check(in.readInt()==0x50454d31&&model.equals(in.readUTF())&&in.read()==-1,label+"-exact-model-record");}
            row.put("width",bounds.outWidth).put("height",bounds.outHeight).put("outputSha256",sha(target));
        }
        File draftDir=new File(getTargetContext().getFilesDir(),"photo-edit-drafts/"+hex(MessageDigest.getInstance("SHA-256").digest(owner.getBytes("UTF-8"))));
        File[] draftFiles=draftDir.listFiles();if(draftFiles!=null){owned.add(draftDir);owned.addAll(Arrays.asList(draftFiles));}
        exports.put(row);
    }
    private void writeFixture(File file,String label)throws Exception{Bitmap b=Bitmap.createBitmap(640,480,Bitmap.Config.ARGB_8888);try{int seed=label.hashCode();int[] row=new int[640];for(int y=0;y<480;y++){for(int x=0;x<640;x++)row[x]=Color.rgb((x*3+y+seed)&255,(y*5+x*2)&255,(x+y*2)&255);b.setPixels(row,0,640,0,y,640,1);}try(OutputStream out=new FileOutputStream(file)){if(!b.compress(Bitmap.CompressFormat.JPEG,100,out))throw new IOException("fixture JPEG");}}finally{b.recycle();}}
    private void capture(String name)throws Exception{settle();Bitmap b=getUiAutomation().takeScreenshot();try(OutputStream out=new FileOutputStream(new File(output,name+".png"))){b.compress(Bitmap.CompressFormat.PNG,100,out);}b.recycle();}
    private void settle()throws Exception{waitForIdleSync();CountDownLatch frame=new CountDownLatch(1);ui(()->activity.getWindow().getDecorView().postOnAnimation(()->activity.getWindow().getDecorView().postOnAnimation(frame::countDown)));if(!frame.await(3,TimeUnit.SECONDS))throw new AssertionError("draw timeout");SystemClock.sleep(100);}
    private static String sha(File file)throws Exception{MessageDigest d=MessageDigest.getInstance("SHA-256");try(InputStream in=new FileInputStream(file)){byte[] b=new byte[8192];int n;while((n=in.read(b))!=-1)d.update(b,0,n);}return hex(d.digest());}
    private static String hex(byte[] bytes){StringBuilder s=new StringBuilder();for(byte b:bytes)s.append(Character.forDigit((b>>>4)&15,16)).append(Character.forDigit(b&15,16));return s.toString();}
    private void check(boolean pass,String name)throws Exception{checks.put(new JSONObject().put("name",name).put("pass",pass));if(!pass)throw new AssertionError(name);}
    private interface Work{void run()throws Exception;}private interface Condition{boolean test()throws Exception;}
    private void ui(Work work)throws Exception{Throwable[] error={null};runOnMainSync(()->{try{work.run();}catch(Throwable t){error[0]=t;}});if(error[0]!=null)throw new RuntimeException(error[0]);}
    private void until(Condition c,String label)throws Exception{long end=SystemClock.uptimeMillis()+30000;while(SystemClock.uptimeMillis()<end){if(c.test())return;SystemClock.sleep(40);}throw new AssertionError("Timeout "+label);}
    private static Object get(Object target,String name)throws Exception{Field f=target.getClass().getDeclaredField(name);f.setAccessible(true);return f.get(target);}
    private static void set(Object target,String name,Object value)throws Exception{Field f=target.getClass().getDeclaredField(name);f.setAccessible(true);f.set(target,value);}
    private static Object call(Object target,String name,Object...args)throws Exception{for(Method m:target.getClass().getDeclaredMethods())if(m.getName().equals(name)&&m.getParameterCount()==args.length){m.setAccessible(true);return m.invoke(target,args);}throw new NoSuchMethodException(name);}
}
