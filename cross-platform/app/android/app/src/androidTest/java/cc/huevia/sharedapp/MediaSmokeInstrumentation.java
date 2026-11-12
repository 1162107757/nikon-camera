package cc.huevia.sharedapp;

import android.app.Instrumentation;
import android.app.Activity;
import android.graphics.*;
import android.media.ExifInterface;
import android.os.Bundle;
import cc.huevia.account.AccountRepository;
import cc.huevia.album.PhotoEditStore;
import cc.huevia.album.PhotoExportSpec;
import cc.huevia.album.PhotoPresetRenderer;
import cc.huevia.album.PhotoComposition;
import cc.huevia.ncp.PhotoGeometry;
import cc.huevia.album.RawDeveloper;
import cc.huevia.library.SharedJson;
import cc.huevia.shared.SharedRuntime;
import cc.huevia.shared.SharedExportModel;
import java.io.*;
import java.nio.file.Files;
import java.util.*;
import java.util.concurrent.*;

/** Real Android codecs, native RAW loading, original renderer and guarded output. */
public final class MediaSmokeInstrumentation extends Instrumentation {
    private int checks;
    private boolean integration;
    private void yes(boolean value,String name){checks++;if(!value)throw new AssertionError(name);}
    @Override public void onCreate(Bundle arguments){super.onCreate(arguments);integration=arguments!=null&&"true".equals(arguments.getString("integration"));start();}
    @Override public void onStart(){
        Bundle result=new Bundle();File workspace=null;
        try{
            if(integration){
                // Flutter can keep the main queue active while the tests run;
                // launch without startActivitySync's queue-idle barrier.
                runOnMainSync(()->getTargetContext().startActivity(new android.content.Intent().setClassName(getTargetContext(),"cc.huevia.sharedapp.MainActivity").addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)));
                Object pending=Class.forName("dev.flutter.plugins.integration_test.IntegrationTestPlugin",true,getTargetContext().getClassLoader()).getField("testResults").get(null);
                Map<?,?> results=(Map<?,?>)((Future<?>)pending).get(5,TimeUnit.MINUTES);
                result.putString("testResults",SharedJson.encode(results));
                yes(!results.isEmpty(),"Flutter native suite produced results");
                for(Object value:results.values())yes("success".equals(value),String.valueOf(value));
                result.putString("stream","PASS cross-platform Flutter/native pipeline: "+results.size()+" scenario(s)\n");finish(Activity.RESULT_OK,result);return;
            }
            pickerCancellationChecks();
            workspace=Files.createTempDirectory(getTargetContext().getFilesDir().toPath(),"migration-smoke-").toFile();
            SharedRuntime runtime=new SharedRuntime(workspace.getPath(),new AccountRepository.Store(){
                public byte[] read(){return null;} public void write(byte[] b){} public void clear(){}
            },(method,path,token,body)->{throw new IOException("Network is outside this codec test");});
            NativeMedia media=new NativeMedia(getTargetContext(),runtime);
            if(android.os.Build.VERSION.SDK_INT>=29)avatarPreparationChecks(workspace);
            File source=new File(workspace,"source.png");Bitmap image=Bitmap.createBitmap(256,192,Bitmap.Config.ARGB_8888);
            for(int y=0;y<192;y++)for(int x=0;x<256;x++)image.setPixel(x,y,Color.rgb(20+x/2,20+y/2,40+(x+y)/4));
            try(FileOutputStream out=new FileOutputStream(source)){yes(image.compress(Bitmap.CompressFormat.PNG,100,out),"source encode");}finally{image.recycle();}
            String before=PhotoEditStore.hashFile(source);
            Map<String,Object> request=SharedRuntime.map("path",source.getPath(),"owner","","size","full","recipe",SharedRuntime.map("schema",1));
            Map<String,Object> info=SharedJson.object(media.request("media.info",SharedJson.encode(request),()->false,p->{}));
            yes(((Number)info.get("width")).intValue()==256&&((Number)info.get("height")).intValue()==192,"inspect dimensions");
            yes(((Number)info.get("orientation")).intValue()==1,"Missing/undefined EXIF is neutral orientation");
            Map<String,Object> neutral=SharedJson.object(media.request("media.export",SharedJson.encode(request),()->false,p->{}));
            File output=new File((String)neutral.get("path"));yes(output.isFile()&&!output.equals(source),"private separate export");
            Map<String,Object> repeated=SharedJson.object(media.request("media.export",SharedJson.encode(request),()->false,p->{}));
            yes(output.getPath().equals(repeated.get("path"))&&Boolean.TRUE.equals(repeated.get("reused")),"same encoded effect reuses a verified saved version");
            yes(neutral.get("sha256").equals(PhotoEditStore.hashFile(output)),"saved version records actual JPEG digest");
            Map<String,Object> opened=SharedJson.object(runtime.request("version.open",SharedJson.encode(SharedRuntime.map("owner","","id",neutral.get("id")))));
            yes(opened.get("sha256").equals(neutral.get("sha256")),"saved version survives independent lookup");
            yes(((Number)neutral.get("width")).intValue()==256&&((Number)neutral.get("height")).intValue()==192,"full export dimensions");
            yes(!((String)neutral.get("model")).isEmpty(),"valid render model");
            cc.huevia.ncp.PresetPreviewProfile neutralProfile=runtime.originalView(source.getPath(),"").profile();
            PhotoExportSpec.Resolved fullSpec=PhotoExportSpec.full().resolve(256,192);
            yes(neutral.get("model").equals(PhotoPresetRenderer.modelVersion(neutralProfile,fullSpec)),"original Android full-export identity");
            yes(SharedExportModel.of(neutralProfile,fullSpec).equals(PhotoPresetRenderer.modelVersion(neutralProfile,fullSpec)),"portable full identity matches original renderer");
            for(PhotoExportSpec selected:new PhotoExportSpec[]{PhotoExportSpec.share(),PhotoExportSpec.custom(640,83)}){
                PhotoExportSpec.Resolved resolved=selected.resolve(256,192);
                yes(SharedExportModel.of(neutralProfile,resolved).equals(PhotoPresetRenderer.modelVersion(neutralProfile,resolved)),"portable resized/quality identity matches original renderer");
            }
            Bitmap decoded=BitmapFactory.decodeFile(output.getPath());yes(decoded!=null,"JPEG decode");
            yes(Math.abs(Color.red(decoded.getPixel(100,100))-70)<8,"neutral colour");decoded.recycle();
            int[] values=new int[17];values[1]=10;List<Integer> settings=new ArrayList<>();for(int v:values)settings.add(v);
            request.put("recipe",SharedRuntime.map("values",settings,"geometry",SharedRuntime.map("turns",1,"left",0,"top",0,"right",500000,"bottom",1000000)));
            Map<String,Object> changed=SharedJson.object(media.request("media.export",SharedJson.encode(request),()->false,p->{}));
            yes(((Number)changed.get("width")).intValue()==96&&((Number)changed.get("height")).intValue()==256,"rotated half crop");
            Map<String,Object> draft=SharedJson.object(runtime.request("draft.load",SharedJson.encode(SharedRuntime.map("path",source.getPath(),"owner",""))));
            yes(draft.get("recipe") instanceof Map,"original draft readable");
            Map<String,Object> originalView=SharedJson.object(media.request("media.originalPreview",SharedJson.encode(SharedRuntime.map("path",source.getPath(),"owner","")),()->false,p->{}));
            yes(((Number)originalView.get("width")).intValue()==256&&((Number)originalView.get("height")).intValue()==192,"original comparison ignores edited geometry");
            yes(draft.equals(SharedJson.object(runtime.request("draft.load",SharedJson.encode(SharedRuntime.map("path",source.getPath(),"owner",""))))),"original comparison preserves complete draft");
            Map<String,Object> atmosphere=SharedJson.object(media.request("media.atmosphere",SharedJson.encode(SharedRuntime.map("path",originalView.get("path"),"owner","")),()->false,p->{}));
            Bitmap background=BitmapFactory.decodeFile((String)atmosphere.get("path"));
            yes(background!=null&&background.getWidth()==64&&background.getHeight()==48,"editor atmosphere is bounded to original 64px sample");background.recycle();
            yes(draft.equals(SharedJson.object(runtime.request("draft.load",SharedJson.encode(SharedRuntime.map("path",source.getPath(),"owner",""))))),"atmosphere leaves effect draft intact");
            try{media.request("media.atmosphere",SharedJson.encode(SharedRuntime.map("path",source.getPath(),"owner","")),()->false,p->{});throw new AssertionError("Full source accepted as atmosphere");}catch(IOException expected){checks++;}
            int backgroundCount=new File(workspace,"previews").list().length;
            try{media.request("media.atmosphere",SharedJson.encode(SharedRuntime.map("path",originalView.get("path"),"owner","")),()->true,p->{});throw new AssertionError("Atmosphere cancellation ignored");}catch(InterruptedIOException expected){checks++;}
            yes(new File(workspace,"previews").list().length==backgroundCount,"cancelled atmosphere leaves no file");
            NativeGallery gallery=new NativeGallery(getTargetContext(),runtime);
            yes(SharedJson.object(gallery.access()).containsKey("access"),"gallery reports scoped access");
            try{gallery.request("gallery.import",SharedJson.encode(SharedRuntime.map("id","content://unlisted/photo")),()->false);throw new AssertionError("Unknown gallery URI accepted");}catch(IOException expected){checks++;}
            File large=new File(workspace,"large.jpg");Bitmap largeImage=Bitmap.createBitmap(3000,2000,Bitmap.Config.ARGB_8888);
            try(FileOutputStream out=new FileOutputStream(large)){largeImage.eraseColor(Color.rgb(120,130,140));if(!largeImage.compress(Bitmap.CompressFormat.JPEG,95,out))throw new IOException("large fixture encode");}finally{largeImage.recycle();}
            Map<String,Object> bounded=SharedJson.object(media.request("media.originalPreview",SharedJson.encode(SharedRuntime.map("path",large.getPath(),"owner","")),()->false,p->{}));
            yes(Math.max(((Number)bounded.get("width")).intValue(),((Number)bounded.get("height")).intValue())<=1280,"large original comparison is bounded");
            yes(SharedJson.object(runtime.request("draft.load",SharedJson.encode(SharedRuntime.map("path",large.getPath(),"owner","")))).get("recipe")==null,"original comparison never creates an edit");
            request.put("recipe",SharedRuntime.map("border",SharedRuntime.map("template",3)));
            Map<String,Object> framed=SharedJson.object(media.request("media.export",SharedJson.encode(request),()->false,p->{}));
            yes(((Number)framed.get("height")).intValue()==192+Math.round(256*.112f),"original border dimensions");
            File orient=new File(workspace,"orientation.jpg");Files.copy(output.toPath(),orient.toPath());ExifInterface exif=new ExifInterface(orient.getPath());exif.setAttribute(ExifInterface.TAG_ORIENTATION,"6");
            exif.setAttribute("Make","NIKON");exif.setAttribute("Model","NIKON Z 6_3");exif.setAttribute("FocalLength","50/1");exif.setAttribute("FNumber","1.8");exif.setAttribute("ExposureTime","0.008");exif.setAttribute("ISOSpeedRatings","200");exif.setAttribute("DateTimeOriginal","2026:11:11 12:34:56");exif.saveAttributes();
            request.put("path",orient.getPath());request.put("recipe",SharedRuntime.map("schema",1));
            Map<String,Object> capture=SharedJson.object(media.request("media.borderInfo",SharedJson.encode(request),()->false,p->{}));
            yes("NIKON".equals(capture.get("brand"))&&"NIKON Z 6_3".equals(capture.get("model")),"border reads actual original camera metadata");
            yes(Arrays.asList("50mm","F1.8","1/125s","ISO200","2026-11-11 12:34:56").equals(capture.get("fields")),"border capture field formatting matches original: "+SharedJson.encode(capture));
            request.put("maxEdge",128);Map<String,Object> thumbnail=SharedJson.object(media.request("media.preview",SharedJson.encode(request),()->false,p->{}));
            yes(((Number)thumbnail.get("width")).intValue()==96&&((Number)thumbnail.get("height")).intValue()==128,"bounded EXIF-oriented border thumbnail");
            request.put("maxEdge",127);try{media.request("media.preview",SharedJson.encode(request),()->false,p->{});throw new AssertionError("unbounded thumbnail accepted");}catch(IOException expected){checks++;}request.remove("maxEdge");
            for(int direction=1;direction<=8;direction++){
                File oriented=new File(workspace,"preview-exif-"+direction+".jpg");Files.copy(orient.toPath(),oriented.toPath());
                ExifInterface tags=new ExifInterface(oriented.getPath());tags.setAttribute("Orientation",Integer.toString(direction));tags.saveAttributes();
                Map<String,Object> frozen=SharedRuntime.map("path",oriented.getPath(),"owner","","size","full","recipe",SharedRuntime.map("schema",1));
                Map<String,Object> header=SharedJson.object(media.request("media.exportPreview",SharedJson.encode(frozen),()->false,p->{}));
                Map<String,Object> frame=SharedJson.object(media.request("media.exportPreviewFrame",SharedJson.encode(SharedRuntime.map("id",header.get("id"),"width",header.get("width"),"height",header.get("height"),"scale",1,"cx",.5,"cy",.5)),()->false,p->{}));
                File folder=new File((String)header.get("overview")).getParentFile();boolean exact=true;
                for(String[] pair:new String[][]{{"jpeg","encoded.jpg"},{"before","reference.png"}}){
                    Bitmap raw=BitmapFactory.decodeFile(new File(folder,pair[1]).getPath()),expected=PhotoComposition.apply(raw,PhotoGeometry.NONE,direction),actual=BitmapFactory.decodeFile((String)frame.get(pair[0]));
                    try{
                        if(expected.getWidth()!=actual.getWidth()||expected.getHeight()!=actual.getHeight()){exact=false;continue;}
                        int[] a=new int[expected.getWidth()*expected.getHeight()],b=new int[a.length];expected.getPixels(a,0,expected.getWidth(),0,0,expected.getWidth(),expected.getHeight());actual.getPixels(b,0,actual.getWidth(),0,0,actual.getWidth(),actual.getHeight());exact&=Arrays.equals(a,b);
                    }finally{if(expected!=raw)expected.recycle();raw.recycle();actual.recycle();}
                }
                yes(exact,"region preview exactly matches original composition for EXIF "+direction);
                media.request("media.exportPreviewClose",SharedJson.encode(SharedRuntime.map("id",header.get("id"))),()->false,p->{});
            }
            Map<String,Object> rotated=SharedJson.object(media.request("media.export",SharedJson.encode(request),()->false,p->{}));
            yes(((Number)rotated.get("width")).intValue()==192&&((Number)rotated.get("height")).intValue()==256,"EXIF orientation applied once");
            int count=new File(workspace,"exports").list().length;
            try{media.request("media.export",SharedJson.encode(request),()->true,p->{});throw new AssertionError("Cancellation ignored");}catch(InterruptedIOException expected){checks++;}
            yes(new File(workspace,"exports").list().length==count,"cancel leaves no partial output");
            yes(before.equals(PhotoEditStore.hashFile(source)),"original bytes unchanged");
            byte[] usbIdentity=NativeUsbCamera.describeDevice("NIKON CORPORATION","USB Nikon fixture","1","",new int[]{0x1004,0x1007,0x1008,0x1009},new int[0]);
            cc.huevia.ptp.PtpDeviceInfo usbInfo=cc.huevia.ptp.PtpDeviceInfo.parseRedacted(usbIdentity);
            yes(usbInfo.isNikonCamera(),"Android MTP identity uses the supported unknown vendor extension rather than an invented value");
            yes(usbInfo.supportsOperation(0x1009),"Android MTP identity preserves actual read operations");
            yes(!cc.huevia.ptp.PtpDeviceInfo.parseRedacted(NativeUsbCamera.describeDevice("OTHER","fixture","1","",new int[]{0x1009},new int[0])).isNikonCamera(),"Unknown USB vendor extension does not bypass the Nikon manufacturer check");
            yes(RawDeveloper.available(),"LibRaw loaded for device ABI");yes(RawDeveloper.libraryVersion().contains("0.22.3"),"original LibRaw version");
            final File smallStackRoot=workspace;
            android.content.Context boundedContext=new android.content.ContextWrapper(getTargetContext()){
                @Override public File getFilesDir(){return smallStackRoot;}
            };
            File rawInput=new File(workspace,"small-stack.dng");
            try(InputStream input=getContext().getAssets().open("raw-stack.dng")){Files.copy(input,rawInput.toPath());}
            String rawBefore=PhotoEditStore.hashFile(rawInput);
            FutureTask<int[]> boundedRaw=new FutureTask<>(()->{
                RawDeveloper.Info rawInfo=RawDeveloper.inspect(rawInput);
                RawDeveloper.Result developed=RawDeveloper.develop(boundedContext,rawInput,"small-stack-regression",cc.huevia.ncp.RawDevelopmentSettings.DEFAULT,()->false,p->{});
                Bitmap decodedRaw=BitmapFactory.decodeFile(developed.workingFile.getPath());
                if(decodedRaw==null)throw new IOException("Small-stack RAW output cannot decode");
                try{int white=decodedRaw.getPixel(decodedRaw.getWidth()*9/10,decodedRaw.getHeight()/2);return new int[]{rawInfo.width,rawInfo.height,Color.red(white),Color.green(white),Color.blue(white),developed.cached?1:0};}
                finally{decodedRaw.recycle();}
            });
            new Thread(null,boundedRaw,"huevia-raw-small-stack",512*1024L).start();
            int[] rawResult=boundedRaw.get(60,TimeUnit.SECONDS);
            yes(rawResult[0]==256&&rawResult[1]==192,"RAW inspection/development on a requested 512 KiB stack");
            yes(rawResult[5]==0,"Small-stack check executes the decoder without a prior development cache");
            yes(Math.min(rawResult[2],Math.min(rawResult[3],rawResult[4]))>220&&Math.max(rawResult[2],Math.max(rawResult[3],rawResult[4]))-Math.min(rawResult[2],Math.min(rawResult[3],rawResult[4]))<15,"Small-stack RAW saturated highlights stay white");
            double previousLight=-1;
            for(int ev:new int[]{-20,-10,0,10,20,30,50}){
                cc.huevia.ncp.RawDevelopmentSettings rawEvControls=cc.huevia.ncp.RawDevelopmentSettings.DEFAULT.withColorMode(cc.huevia.ncp.RawDevelopmentSettings.ColorMode.NEUTRAL).withExposure(ev);
                RawDeveloper.Result adjusted=RawDeveloper.develop(boundedContext,rawInput,"safe-ev-regression",rawEvControls,()->false,p->{});
                Bitmap pixels=BitmapFactory.decodeFile(adjusted.workingFile.getPath());yes(pixels!=null,"RAW EV output decodes");
                try{int middle=pixels.getPixel(pixels.getWidth()/5,pixels.getHeight()/2);double light=.2126*Color.red(middle)+.7152*Color.green(middle)+.0722*Color.blue(middle);
                    yes(light+1>=previousLight,"Increasing RAW EV preserves monotonic brightness");previousLight=light;
                    if(ev>=0){int white=pixels.getPixel(pixels.getWidth()*9/10,pixels.getHeight()/2);yes(Math.min(Color.red(white),Math.min(Color.green(white),Color.blue(white)))>220,"Positive RAW EV never turns saturated white black");}
                }finally{pixels.recycle();}
            }
            yes(rawBefore.equals(PhotoEditStore.hashFile(rawInput)),"Small-stack RAW source bytes unchanged");
            result.putString("stream","PASS "+checks+" Android media checks; codecs, original renderer, geometry, EXIF, draft, cancellation, unchanged source, LibRaw ABI\n");
            finish(Activity.RESULT_OK,result);
        }catch(Throwable failure){result.putString("stream","FAIL after "+checks+" checks: "+failure+"\n");finish(Activity.RESULT_CANCELED,result);}
        finally{if(workspace!=null)try{remove(workspace,workspace.getCanonicalFile());}catch(IOException ignored){}}
    }
    private void pickerCancellationChecks()throws Exception{
        List<Integer> requestCodes=new ArrayList<>();List<Object> first=new ArrayList<>(),second=new ArrayList<>();
        NativeImportPicker[] pickerHolder=new NativeImportPicker[1];
        runOnMainSync(()->pickerHolder[0]=new NativeImportPicker(new Activity(){@Override public void startActivityForResult(android.content.Intent intent,int request){requestCodes.add(request);}},Runnable::run));
        NativeImportPicker picker=pickerHolder[0];
        java.util.function.Function<List<Object>,io.flutter.plugin.common.MethodChannel.Result> reply=values->new io.flutter.plugin.common.MethodChannel.Result(){
            public void success(Object value){values.add(value);}public void error(String code,String message,Object details){values.add(code);}public void notImplemented(){values.add("not implemented");}
        };
        java.lang.reflect.Field flag=NativeImportPicker.class.getDeclaredField("cancelled");flag.setAccessible(true);
        java.lang.reflect.Method finish=NativeImportPicker.class.getDeclaredMethod("finish",int.class,String.class,Exception.class);finish.setAccessible(true);
        runOnMainSync(()->{picker.pick(false,"unused",reply.apply(first));picker.cancel();});waitForIdleSync();
        java.util.concurrent.atomic.AtomicBoolean old=(java.util.concurrent.atomic.AtomicBoolean)flag.get(picker);
        yes(first.size()==1&&String.valueOf(first.get(0)).contains("cancelled"),"Picker cancellation replies exactly once");
        runOnMainSync(()->picker.pick(true,"unused",reply.apply(second)));
        yes(old.get()&&flag.get(picker)!=old,"Reopened picker has an independent cancellation flag");
        yes(requestCodes.size()==2&&!requestCodes.get(0).equals(requestCodes.get(1))&&!picker.handles(requestCodes.get(0))&&picker.handles(requestCodes.get(1)),"Old system document result cannot claim a reopened picker");
        finish.invoke(picker,1,"old worker receipt",null);waitForIdleSync();
        yes(second.isEmpty(),"Old queued worker completion cannot finish a reopened picker");
        runOnMainSync(()->picker.result(Activity.RESULT_CANCELED,null));waitForIdleSync();
        yes(second.size()==1&&String.valueOf(second.get(0)).contains("cancelled"),"Reopened picker delivers its own result");
    }
    private void avatarPreparationChecks(File workspace)throws Exception{
        android.content.ContentResolver resolver=getTargetContext().getContentResolver();
        Bitmap fixture=Bitmap.createBitmap(1280,960,Bitmap.Config.ARGB_8888);
        try{
            int[] pixels=new int[1280*960];for(int y=0;y<960;y++)for(int x=0;x<1280;x++)pixels[y*1280+x]=Color.rgb(x*255/1279,y*255/959,((x/80+y/60)%2)*200+20);
            fixture.setPixels(pixels,0,1280,0,0,1280,960);
            File base=new File(workspace,"avatar-base.jpg");try(OutputStream output=new FileOutputStream(base)){if(!fixture.compress(Bitmap.CompressFormat.JPEG,94,output))throw new IOException("Avatar fixture encoding failed");}
            for(int orientation=1;orientation<=8;orientation++){
                File input=new File(workspace,"avatar-"+orientation+".jpg");Files.copy(base.toPath(),input.toPath());
                ExifInterface exif=new ExifInterface(input.getPath());exif.setAttribute(ExifInterface.TAG_ORIENTATION,String.valueOf(orientation));exif.setAttribute(ExifInterface.TAG_MAKE,"Owned QA");exif.setAttribute(ExifInterface.TAG_MODEL,"Avatar204");exif.setAttribute(ExifInterface.TAG_DATETIME_ORIGINAL,"2026:01:01 00:00:00");
                exif.setAttribute(ExifInterface.TAG_GPS_LATITUDE,"1/1,2/1,3/1");exif.setAttribute(ExifInterface.TAG_GPS_LATITUDE_REF,"N");exif.saveAttributes();
                String before=PhotoEditStore.hashFile(input);android.net.Uri uri=null;cc.huevia.account.AvatarImages.Prepared original=null;
                try{
                    android.content.ContentValues values=new android.content.ContentValues();values.put(android.provider.MediaStore.Images.Media.DISPLAY_NAME,"Huevia-QA-Avatar204-"+orientation+".jpg");values.put(android.provider.MediaStore.Images.Media.MIME_TYPE,"image/jpeg");values.put(android.provider.MediaStore.Images.Media.RELATIVE_PATH,"Pictures/HueviaQA204");values.put(android.provider.MediaStore.Images.Media.IS_PENDING,1);
                    uri=resolver.insert(android.provider.MediaStore.Images.Media.EXTERNAL_CONTENT_URI,values);if(uri==null)throw new IOException("Cannot publish owned avatar fixture");
                    try(InputStream source=new FileInputStream(input);OutputStream output=resolver.openOutputStream(uri)){if(output==null)throw new IOException("Cannot open owned avatar fixture");byte[] buffer=new byte[8192];int n;while((n=source.read(buffer))!=-1)output.write(buffer,0,n);}
                    values.clear();values.put(android.provider.MediaStore.Images.Media.IS_PENDING,0);resolver.update(uri,values,null,null);
                    original=cc.huevia.account.AvatarImages.prepare(getTargetContext(),uri);
                    byte[] actual=NativeAvatar.prepare(input,()->false);
                    yes(Arrays.equals(actual,original.jpeg),"Avatar JPEG matches original URI implementation at EXIF "+orientation);
                    ExifInterface clean=new ExifInterface(new ByteArrayInputStream(actual));
                    int marker=clean.getAttributeInt(ExifInterface.TAG_ORIENTATION,ExifInterface.ORIENTATION_UNDEFINED);
                    yes(clean.getAttribute(ExifInterface.TAG_GPS_LATITUDE)==null&&clean.getAttribute(ExifInterface.TAG_MAKE)==null&&clean.getAttribute(ExifInterface.TAG_MODEL)==null&&clean.getAttribute(ExifInterface.TAG_DATETIME_ORIGINAL)==null&&(marker==ExifInterface.ORIENTATION_NORMAL||marker==ExifInterface.ORIENTATION_UNDEFINED),"Avatar metadata removed and orientation normalized at EXIF "+orientation+"; output marker="+marker);
                    yes(before.equals(PhotoEditStore.hashFile(input)),"Avatar source unchanged at EXIF "+orientation);
                }finally{if(original!=null){original.close();original.preview.recycle();}if(uri!=null)resolver.delete(uri,null,null);}
            }
            File tiny=new File(workspace,"avatar-tiny.png");Bitmap small=Bitmap.createBitmap(32,32,Bitmap.Config.ARGB_8888);
            try(OutputStream output=new FileOutputStream(tiny)){small.compress(Bitmap.CompressFormat.PNG,100,output);}finally{small.recycle();}
            boolean rejected=false;try{NativeAvatar.prepare(tiny,()->false);}catch(IOException expected){rejected=true;}yes(rejected,"Avatar rejects a source below original 64 pixel minimum");
            rejected=false;try{NativeAvatar.prepare(base,()->true);}catch(InterruptedIOException expected){rejected=true;}yes(rejected,"Avatar cancellation stops before decoding");
        }finally{fixture.recycle();}
    }
    private static void remove(File file,File guard)throws IOException{
        if(!file.getCanonicalFile().toPath().startsWith(guard.toPath()))throw new IOException("Test cleanup outside workspace");
        File[] children=file.listFiles();if(children!=null)for(File child:children)remove(child,guard);if(file.exists()&&!file.delete())throw new IOException("Test cleanup failed");
    }
}
