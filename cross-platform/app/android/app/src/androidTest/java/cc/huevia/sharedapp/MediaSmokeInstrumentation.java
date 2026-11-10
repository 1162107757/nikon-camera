package cc.huevia.sharedapp;

import android.app.Instrumentation;
import android.app.Activity;
import android.graphics.*;
import android.media.ExifInterface;
import android.os.Bundle;
import cc.huevia.account.AccountRepository;
import cc.huevia.album.PhotoEditStore;
import cc.huevia.album.RawDeveloper;
import cc.huevia.library.SharedJson;
import cc.huevia.shared.SharedRuntime;
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
                startActivitySync(new android.content.Intent().setClassName(getTargetContext(),"cc.huevia.sharedapp.MainActivity").addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK));
                Object pending=Class.forName("dev.flutter.plugins.integration_test.IntegrationTestPlugin").getField("testResults").get(null);
                Map<?,?> results=(Map<?,?>)((Future<?>)pending).get(5,TimeUnit.MINUTES);
                yes(!results.isEmpty(),"Flutter native suite produced results");
                for(Object value:results.values())yes("success".equals(value),String.valueOf(value));
                result.putString("stream","PASS cross-platform Flutter/native pipeline: "+results.size()+" scenario(s)\n");finish(Activity.RESULT_OK,result);return;
            }
            workspace=Files.createTempDirectory(getTargetContext().getFilesDir().toPath(),"migration-smoke-").toFile();
            SharedRuntime runtime=new SharedRuntime(workspace.getPath(),new AccountRepository.Store(){
                public byte[] read(){return null;} public void write(byte[] b){} public void clear(){}
            },(method,path,token,body)->{throw new IOException("Network is outside this codec test");});
            NativeMedia media=new NativeMedia(getTargetContext(),runtime);
            File source=new File(workspace,"source.png");Bitmap image=Bitmap.createBitmap(256,192,Bitmap.Config.ARGB_8888);
            for(int y=0;y<192;y++)for(int x=0;x<256;x++)image.setPixel(x,y,Color.rgb(20+x/2,20+y/2,40+(x+y)/4));
            try(FileOutputStream out=new FileOutputStream(source)){yes(image.compress(Bitmap.CompressFormat.PNG,100,out),"source encode");}finally{image.recycle();}
            String before=PhotoEditStore.hashFile(source);
            Map<String,Object> request=SharedRuntime.map("path",source.getPath(),"owner","","size","full","recipe",SharedRuntime.map("schema",1));
            Map<String,Object> info=SharedJson.object(media.request("media.info",SharedJson.encode(request),()->false,p->{}));
            yes(((Number)info.get("width")).intValue()==256&&((Number)info.get("height")).intValue()==192,"inspect dimensions");
            Map<String,Object> neutral=SharedJson.object(media.request("media.export",SharedJson.encode(request),()->false,p->{}));
            File output=new File((String)neutral.get("path"));yes(output.isFile()&&!output.equals(source),"private separate export");
            yes(((Number)neutral.get("width")).intValue()==256&&((Number)neutral.get("height")).intValue()==192,"full export dimensions");
            yes(!((String)neutral.get("model")).isEmpty(),"valid render model");
            Bitmap decoded=BitmapFactory.decodeFile(output.getPath());yes(decoded!=null,"JPEG decode");
            yes(Math.abs(Color.red(decoded.getPixel(100,100))-70)<8,"neutral colour");decoded.recycle();
            int[] values=new int[17];values[1]=10;List<Integer> settings=new ArrayList<>();for(int v:values)settings.add(v);
            request.put("recipe",SharedRuntime.map("values",settings,"geometry",SharedRuntime.map("turns",1,"left",0,"top",0,"right",500000,"bottom",1000000)));
            Map<String,Object> changed=SharedJson.object(media.request("media.export",SharedJson.encode(request),()->false,p->{}));
            yes(((Number)changed.get("width")).intValue()==96&&((Number)changed.get("height")).intValue()==256,"rotated half crop");
            Map<String,Object> draft=SharedJson.object(runtime.request("draft.load",SharedJson.encode(SharedRuntime.map("path",source.getPath(),"owner",""))));
            yes(draft.get("recipe") instanceof Map,"original draft readable");
            request.put("recipe",SharedRuntime.map("border",SharedRuntime.map("template",3)));
            Map<String,Object> framed=SharedJson.object(media.request("media.export",SharedJson.encode(request),()->false,p->{}));
            yes(((Number)framed.get("height")).intValue()==192+Math.round(256*.112f),"original border dimensions");
            File orient=new File(workspace,"orientation.jpg");Files.copy(output.toPath(),orient.toPath());ExifInterface exif=new ExifInterface(orient.getPath());exif.setAttribute(ExifInterface.TAG_ORIENTATION,"6");exif.saveAttributes();
            request.put("path",orient.getPath());request.put("recipe",SharedRuntime.map("schema",1));
            Map<String,Object> rotated=SharedJson.object(media.request("media.export",SharedJson.encode(request),()->false,p->{}));
            yes(((Number)rotated.get("width")).intValue()==192&&((Number)rotated.get("height")).intValue()==256,"EXIF orientation applied once");
            int count=new File(workspace,"exports").list().length;
            try{media.request("media.export",SharedJson.encode(request),()->true,p->{});throw new AssertionError("Cancellation ignored");}catch(InterruptedIOException expected){checks++;}
            yes(new File(workspace,"exports").list().length==count,"cancel leaves no partial output");
            yes(before.equals(PhotoEditStore.hashFile(source)),"original bytes unchanged");
            yes(RawDeveloper.available(),"LibRaw loaded for device ABI");yes(RawDeveloper.libraryVersion().contains("0.22.3"),"original LibRaw version");
            result.putString("stream","PASS "+checks+" Android media checks; codecs, original renderer, geometry, EXIF, draft, cancellation, unchanged source, LibRaw ABI\n");
            finish(Activity.RESULT_OK,result);
        }catch(Throwable failure){result.putString("stream","FAIL after "+checks+" checks: "+failure+"\n");finish(Activity.RESULT_CANCELED,result);}
        finally{if(workspace!=null)try{remove(workspace,workspace.getCanonicalFile());}catch(IOException ignored){}}
    }
    private static void remove(File file,File guard)throws IOException{
        if(!file.getCanonicalFile().toPath().startsWith(guard.toPath()))throw new IOException("Test cleanup outside workspace");
        File[] children=file.listFiles();if(children!=null)for(File child:children)remove(child,guard);if(file.exists()&&!file.delete())throw new IOException("Test cleanup failed");
    }
}
