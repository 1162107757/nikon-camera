package cc.huevia.sharedapp;

import android.content.Context;
import android.graphics.*;
import android.media.ExifInterface;
import cc.huevia.album.*;
import cc.huevia.library.SharedJson;
import cc.huevia.ncp.*;
import cc.huevia.shared.*;
import java.io.*;
import java.nio.file.*;
import java.util.*;
import java.util.function.*;

/** Private files and frozen recipes cross the bridge; full-size pixels stay native. */
final class NativeMedia {
    private final Context context;
    private final SharedRuntime runtime;
    NativeMedia(Context context,SharedRuntime runtime){this.context=context.getApplicationContext();this.runtime=runtime;}
    String request(String operation,String json,BooleanSupplier cancel,DoubleConsumer progress)throws IOException{
        Map<String,Object> p=SharedJson.object(json);File source=runtime.privateFile(SharedRuntime.text(p,"path",4096));
        if(operation.equals("media.info")){
            if(raw(source)){RawDeveloper.Info info=RawDeveloper.inspect(source);return SharedJson.encode(SharedRuntime.map("width",info.width,"height",info.height,"raw",true,"make",info.make,"model",info.model));}
            BitmapFactory.Options bounds=bounds(source);return SharedJson.encode(SharedRuntime.map("width",bounds.outWidth,"height",bounds.outHeight,"raw",false,"orientation",new ExifInterface(source.getPath()).getAttributeInt(ExifInterface.TAG_ORIENTATION,1)));
        }
        if(operation.equals("media.rawPreview")||operation.equals("media.rawDevelop"))return rawDevelop(operation,p,source,cancel,progress);
        if(!operation.equals("media.preview")&&!operation.equals("media.export"))throw new IOException("未知的照片操作。");
        boolean preview=operation.equals("media.preview");
        String owner=SharedRuntime.text(p,"owner",64),original=source.getPath();
        PhotoEditStore.Draft frozen=runtime.freezeEdit(original,owner,SharedJson.encode(SharedRuntime.object(p.get("recipe"))));
        if(!preview)runtime.validateSource(original,frozen.sourceSha);
        if(raw(source))source=RawDeveloper.develop(context,source,owner,RawDevelopmentSettings.DEFAULT,cancel,value->progress.accept(value*.3)).workingFile;
        File directory=new File(runtime.root(),preview?"previews":"exports");if(!directory.isDirectory()&&!directory.mkdirs())throw new IOException("无法创建照片输出目录。");
        File temporary=File.createTempFile("render-",".part",directory),target=new File(directory,UUID.randomUUID()+".jpg");File reduced=null;
        try{
            PhotoExportSpec spec=preview?PhotoExportSpec.share():spec(p);
            PresetPreviewProfile profile=frozen.profile();
            if(preview||!"image/jpeg".equals(bounds(source).outMimeType))NativeRaster.render(context,source,temporary,profile,spec,preview,cancel,progress);
            else PhotoPresetRenderer.forContext(context).render(source,temporary,profile,spec,cancel,progress::accept);
            if(cancel.getAsBoolean())throw new InterruptedIOException("照片处理已取消。");
            runtime.guardOwner(owner);
            if(!preview)runtime.validateSource(original,frozen.sourceSha);
            Files.move(temporary.toPath(),target.toPath(),StandardCopyOption.ATOMIC_MOVE);
            if(!preview)runtime.markEditExported(owner,frozen);
            BitmapFactory.Options info=bounds(target);
            int orientation=new ExifInterface(target.getPath()).getAttributeInt(ExifInterface.TAG_ORIENTATION,1);
            return SharedJson.encode(SharedRuntime.map("path",target.getPath(),"width",orientation>=5?info.outHeight:info.outWidth,"height",orientation>=5?info.outWidth:info.outHeight,"bytes",target.length(),"preview",preview,"model",profile.modelVersion()));
        }catch(PhotoPresetRenderer.Cancelled stopped){throw new InterruptedIOException("照片处理已取消。");}
        finally{Files.deleteIfExists(temporary.toPath());if(reduced!=null)Files.deleteIfExists(reduced.toPath());}
    }
    private String rawDevelop(String operation,Map<String,Object> p,File source,BooleanSupplier cancel,DoubleConsumer progress)throws IOException{
        if(!raw(source))throw new IOException("请选择 RAW 原文件。");
        String owner=SharedRuntime.text(p,"owner",64);runtime.guardOwner(owner);
        RawDevelopmentSettings settings=SharedRawSettings.parse(SharedJson.encode(SharedRuntime.object(p.get("settings"))));
        RawDeveloper.Result result=RawDeveloper.develop(context,source,owner,settings,cancel,progress);
        boolean preview=operation.equals("media.rawPreview");File dir=new File(runtime.root(),preview?"previews":"raw-editor");
        if(!dir.isDirectory()&&!dir.mkdirs())throw new IOException("无法创建 RAW 编辑目录。");
        File temporary=File.createTempFile("raw-edit-",".part",dir),target=new File(dir,UUID.randomUUID()+".jpg");Bitmap bitmap=null;
        try{
            if(preview){File reduced=small(result.workingFile,dir,cancel);try{Files.move(reduced.toPath(),temporary.toPath(),StandardCopyOption.REPLACE_EXISTING);}finally{Files.deleteIfExists(reduced.toPath());}}
            else{
                BitmapFactory.Options options=new BitmapFactory.Options();options.inPreferredConfig=Bitmap.Config.ARGB_8888;options.inPreferredColorSpace=ColorSpace.get(ColorSpace.Named.SRGB);options.inSampleSize=1;options.inScaled=false;
                bitmap=BitmapFactory.decodeFile(result.workingFile.getPath(),options);
                if(bitmap==null||bitmap.getWidth()!=result.info.width||bitmap.getHeight()!=result.info.height)throw new IOException("无法读取完整显影像素，未缩小原图。");
                try(FileOutputStream out=new FileOutputStream(temporary)){if(!bitmap.compress(Bitmap.CompressFormat.JPEG,100,out))throw new IOException("无法生成 RAW 编辑副本。");out.flush();out.getFD().sync();}
                bitmap.recycle();bitmap=null;RawEditorSource.writeMetadata(source,temporary,result.info);
            }
            if(cancel.getAsBoolean())throw new InterruptedIOException("RAW 显影已取消。");runtime.guardOwner(owner);runtime.validateSource(source.getPath(),result.sourceSha);
            Files.move(temporary.toPath(),target.toPath(),StandardCopyOption.ATOMIC_MOVE);
            BitmapFactory.Options info=bounds(target);
            return SharedJson.encode(SharedRuntime.map("path",target.getPath(),"width",info.outWidth,"height",info.outHeight,"sourceSha",result.sourceSha,"rawColorStatus",result.colorStatus,"settings",SharedJson.object(SharedRawSettings.json(settings))));
        }finally{if(bitmap!=null)bitmap.recycle();Files.deleteIfExists(temporary.toPath());}
    }
    private static PhotoExportSpec spec(Map<String,Object> p)throws IOException{String size=SharedRuntime.text(p,"size",16);if(size.equals("share"))return PhotoExportSpec.share();if(size.equals("custom"))return PhotoExportSpec.custom(SharedRuntime.integer(p,"longEdge",2048),SharedRuntime.integer(p,"quality",95));return PhotoExportSpec.full();}
    private static boolean raw(File source){String name=source.getName().toLowerCase(Locale.ROOT);return name.matches(".*\\.(nef|nrw|arw|cr2|cr3|dng|raf|rw2|orf|pef|srw)$");}
    private static BitmapFactory.Options bounds(File source)throws IOException{BitmapFactory.Options options=new BitmapFactory.Options();options.inJustDecodeBounds=true;BitmapFactory.decodeFile(source.getPath(),options);if(options.outWidth<1||options.outHeight<1||(long)options.outWidth*options.outHeight>60_000_000)throw new IOException("照片尺寸无效或超过 6000 万像素。");return options;}
    private static File small(File source,File directory,BooleanSupplier cancel)throws IOException{
        BitmapFactory.Options info=bounds(source),options=new BitmapFactory.Options();options.inSampleSize=1;while(Math.max(info.outWidth,info.outHeight)/options.inSampleSize>1280)options.inSampleSize*=2;
        options.inPreferredConfig=Bitmap.Config.ARGB_8888;options.inPreferredColorSpace=ColorSpace.get(ColorSpace.Named.SRGB);
        Bitmap bitmap=BitmapFactory.decodeFile(source.getPath(),options);if(bitmap==null)throw new IOException("无法读取照片预览。");
        File file=File.createTempFile("preview-source-",".jpg",directory);boolean complete=false;
        try{
            if(cancel.getAsBoolean())throw new InterruptedIOException("预览已取消。");
            try(FileOutputStream output=new FileOutputStream(file)){if(!bitmap.compress(Bitmap.CompressFormat.JPEG,98,output))throw new IOException("无法生成照片预览。");}
            ExifInterface exif=new ExifInterface(file.getPath());exif.setAttribute(ExifInterface.TAG_ORIENTATION,Integer.toString(new ExifInterface(source.getPath()).getAttributeInt(ExifInterface.TAG_ORIENTATION,1)));exif.saveAttributes();complete=true;return file;
        }finally{bitmap.recycle();if(!complete)Files.deleteIfExists(file.toPath());}
    }
}
