package cc.huevia.sharedapp;

import android.content.Context;
import cc.huevia.AppCrashDiagnostics;
import org.json.JSONObject;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;

/** Reuses the original Application-level Java/OS exit collector. */
final class NativeStability {
    private static final int LIMIT=32768;
    private final Context context;
    NativeStability(Context context){this.context=context.getApplicationContext();}
    private File record()throws IOException{
        File folder=new File(context.getFilesDir(),"app-stability");
        if(Files.isSymbolicLink(folder.toPath())||(!folder.isDirectory()&&!folder.mkdirs()))throw new IOException("stability directory");
        File file=new File(folder,"last-flutter-error.json");
        if(Files.isSymbolicLink(file.toPath()))throw new IOException("stability record");
        return file;
    }
    synchronized void recordFlutter(Object value)throws Exception{
        if(!(value instanceof java.util.Map))throw new IOException("stability data");
        byte[] bytes=new JSONObject((java.util.Map<?,?>)value).toString().getBytes(StandardCharsets.UTF_8);
        if(bytes.length>LIMIT)throw new IOException("stability bounds");
        File target=record(),temporary=new File(target.getParentFile(),"last-flutter-error.tmp");
        if(Files.isSymbolicLink(temporary.toPath()))throw new IOException("stability temporary");
        try{
            try(FileOutputStream out=new FileOutputStream(temporary)){out.write(bytes);out.getFD().sync();}
            try{Files.move(temporary.toPath(),target.toPath(),StandardCopyOption.REPLACE_EXISTING,StandardCopyOption.ATOMIC_MOVE);}
            catch(AtomicMoveNotSupportedException unsupported){Files.move(temporary.toPath(),target.toPath(),StandardCopyOption.REPLACE_EXISTING);}
        }finally{Files.deleteIfExists(temporary.toPath());}
    }
    synchronized String snapshot(){
        JSONObject result=AppCrashDiagnostics.snapshot(context);
        try{
            result.put("platform","android");File file=record();
            if(file.isFile()&&file.length()<=LIMIT)result.put("lastFlutterError",new JSONObject(new String(Files.readAllBytes(file.toPath()),StandardCharsets.UTF_8)));
        }catch(Exception|LinkageError|OutOfMemoryError unavailable){/* Original native evidence remains available. */}
        return result.toString();
    }
}
