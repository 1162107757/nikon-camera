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
    private final NativeExportPreview exportPreview;
    private final SharedDetailTiles detailTiles;
    NativeMedia(Context context,SharedRuntime runtime){this.context=context.getApplicationContext();this.runtime=runtime;this.exportPreview=new NativeExportPreview(this.context,runtime);this.detailTiles=new SharedDetailTiles(runtime.root());MediaValidation.install(NativeMedia::validateSample);}
    private static void validateSample(byte[] bytes)throws IOException{
        BitmapFactory.Options options=new BitmapFactory.Options();options.inJustDecodeBounds=true;
        BitmapFactory.decodeByteArray(bytes,0,bytes.length,options);
        if(options.outWidth<1||options.outHeight<1||options.outWidth>16384||options.outHeight>16384||(long)options.outWidth*options.outHeight>64000000)throw new IOException("请选择有效的 PNG、JPEG 或 WebP 图片。");
        options.inSampleSize=1;while(Math.max(options.outWidth,options.outHeight)/options.inSampleSize>256)options.inSampleSize*=2;
        options.inJustDecodeBounds=false;Bitmap probe=BitmapFactory.decodeByteArray(bytes,0,bytes.length,options);
        if(probe==null)throw new IOException("效果图无法解码，请重新选择。");probe.recycle();
    }
    String request(String operation,String json,BooleanSupplier cancel,DoubleConsumer progress)throws IOException{
        Map<String,Object> p=SharedJson.object(json);
        if(operation.equals("media.detailTile"))return detailTile(p,cancel,progress);
        if(operation.startsWith("media.exportPreview"))return exportPreview.request(operation,p,cancel,progress);
        if(operation.startsWith("media.template")){
            cc.huevia.ui.PresetPreviewRenderer templates=new cc.huevia.ui.PresetPreviewRenderer(context);
            if(operation.equals("media.templateSet")){
                File source=runtime.privateFile(SharedRuntime.text(p,"path",4096));
                if(source.length()<4||source.length()>20L*1024*1024||raw(source))throw new IOException("请选择 20MB 以内的普通照片作为模板。");
                if(cancel.getAsBoolean())throw new InterruptedIOException("模板更新已取消。");
                templates.setTemplate(android.net.Uri.fromFile(source));
            }else if(operation.equals("media.templateReset")){
                templates.resetTemplate();
            }else if(operation.equals("media.templateSource")){
                cc.huevia.ui.PresetShowcaseRenderer renderer=new cc.huevia.ui.PresetShowcaseRenderer(context,templates);
                cc.huevia.ui.PresetShowcaseRenderer.Source[] scenes=renderer.sources();
                int index=SharedRuntime.integer(p,"index",0);if(index<0||index>=scenes.length)throw new IOException("模板样片索引无效。");
                File directory=new File(runtime.root(),"preset-previews");if(!directory.isDirectory()&&!directory.mkdirs())throw new IOException("无法创建模板预览目录。");
                File target=new File(directory,PhotoEditStore.hash(("template:"+scenes[index].cacheKey).getBytes(java.nio.charset.StandardCharsets.UTF_8))+".jpg");
                if(Files.isSymbolicLink(directory.toPath())||Files.isSymbolicLink(target.toPath()))throw new IOException("模板预览路径无效。");
                if(!target.isFile()){
                    Bitmap bitmap=renderer.original(scenes[index],960);File temporary=File.createTempFile("template-",".part",directory);
                    try{try(FileOutputStream out=new FileOutputStream(temporary)){if(!bitmap.compress(Bitmap.CompressFormat.JPEG,95,out))throw new IOException("模板预览编码失败。");out.getFD().sync();}
                        if(cancel.getAsBoolean())throw new InterruptedIOException("模板预览已取消。");Files.move(temporary.toPath(),target.toPath(),StandardCopyOption.REPLACE_EXISTING);
                    }finally{bitmap.recycle();Files.deleteIfExists(temporary.toPath());}
                }
                return SharedJson.encode(SharedRuntime.map("path",target.getPath(),"label",scenes[index].label,"credit",scenes[index].credit));
            }else if(!operation.equals("media.templateInfo"))throw new IOException("未知的模板操作。");
            return SharedJson.encode(SharedRuntime.map("custom",templates.hasCustomTemplate(),"count",templates.hasCustomTemplate()?1:10,"version",templates.versionKey()));
        }
        if(operation.equals("media.showcase")){
            runtime.guardOwner(SharedRuntime.text(p,"owner",64));
            String id=SharedRuntime.text(p,"id",64),category=SharedRuntime.text(p,"category",64);
            byte[] bytes=runtime.showcasePreset(id,p.containsKey("preset")?SharedJson.encode(p.get("preset")):"");if(bytes.length==0)throw new IOException("请选择预设。");
            cc.huevia.ui.PresetShowcaseRenderer renderer=new cc.huevia.ui.PresetShowcaseRenderer(context,new cc.huevia.ui.PresetPreviewRenderer(context));
            cc.huevia.ui.PresetShowcaseRenderer.Source scene=renderer.source(id,category);
            File directory=new File(runtime.root(),"preset-previews");if(!directory.isDirectory()&&!directory.mkdirs())throw new IOException("无法创建预设预览目录。");
            boolean original=Boolean.TRUE.equals(p.get("original"));
            int edge=SharedRuntime.integer(p,"edge",480);if(edge!=480&&edge!=960)throw new IOException("预览尺寸无效。");
            File target=new File(directory,PhotoEditStore.hash((id+":"+scene.cacheKey+":"+PresetPreviewProfiles.MODEL_VERSION+":"+original+":"+edge).getBytes(java.nio.charset.StandardCharsets.UTF_8))+".jpg");
            if(Files.isSymbolicLink(target.toPath()))throw new IOException("预设预览路径无效。");
            if(!target.isFile()){
                if(cancel.getAsBoolean())throw new InterruptedIOException("预览已取消。");
                Bitmap bitmap=original?renderer.original(scene,edge):renderer.render(bytes,scene,edge);File temporary=File.createTempFile("showcase-",".part",directory);
                try{try(FileOutputStream out=new FileOutputStream(temporary)){if(!bitmap.compress(Bitmap.CompressFormat.JPEG,90,out))throw new IOException("预设预览编码失败。");out.getFD().sync();}
                    if(cancel.getAsBoolean())throw new InterruptedIOException("预览已取消。");Files.move(temporary.toPath(),target.toPath(),StandardCopyOption.REPLACE_EXISTING);
                }finally{bitmap.recycle();Files.deleteIfExists(temporary.toPath());}
            }
            return SharedJson.encode(SharedRuntime.map("path",target.getPath(),"credit",scene.credit,"scene",scene.id));
        }
        File source=runtime.privateFile(SharedRuntime.text(p,"path",4096));
        if(operation.equals("media.atmosphere")){
            runtime.guardOwner(SharedRuntime.text(p,"owner",64));
            if(!source.toPath().startsWith(new File(runtime.root(),"previews").getCanonicalFile().toPath()))throw new IOException("编辑背景只能读取有界预览。");
            BitmapFactory.Options dimensions=bounds(source);if(Math.max(dimensions.outWidth,dimensions.outHeight)>1280)throw new IOException("编辑背景预览超过尺寸限制。");
            Bitmap bitmap=BitmapFactory.decodeFile(source.getPath()),small=null,blurred=null;
            if(bitmap==null)throw new IOException("无法读取编辑背景预览。");
            File target=new File(source.getParentFile(),"atmosphere-"+UUID.randomUUID()+".png");boolean complete=false;
            try{
                float ratio=Math.min(1f,64f/Math.max(bitmap.getWidth(),bitmap.getHeight()));int width=Math.max(1,Math.round(bitmap.getWidth()*ratio)),height=Math.max(1,Math.round(bitmap.getHeight()*ratio));
                small=Bitmap.createScaledBitmap(bitmap,width,height,true);int[] pixels=new int[width*height];small.getPixels(pixels,0,width,0,0,width,height);
                blurred=Bitmap.createBitmap(SharedAtmosphere.blur(pixels,width,height),width,height,Bitmap.Config.ARGB_8888);
                if(cancel.getAsBoolean())throw new InterruptedIOException("编辑背景生成已取消。");
                try(FileOutputStream output=new FileOutputStream(target)){if(!blurred.compress(Bitmap.CompressFormat.PNG,100,output))throw new IOException("无法保存编辑背景。");output.getFD().sync();}
                complete=true;return SharedJson.encode(SharedRuntime.map("path",target.getPath()));
            }finally{if(blurred!=null)blurred.recycle();if(small!=null&&small!=bitmap)small.recycle();bitmap.recycle();if(!complete)Files.deleteIfExists(target.toPath());}
        }
        if(operation.equals("media.info")){
            if(raw(source)){RawDeveloper.Info info=RawDeveloper.inspect(source);return SharedJson.encode(SharedRuntime.map("width",info.width,"height",info.height,"raw",true,"make",info.make,"model",info.model));}
            BitmapFactory.Options bounds=bounds(source);int orientation=new ExifInterface(source.getPath()).getAttributeInt(ExifInterface.TAG_ORIENTATION,1);if(orientation<1||orientation>8)orientation=1;
            return SharedJson.encode(SharedRuntime.map("width",bounds.outWidth,"height",bounds.outHeight,"raw",false,"orientation",orientation));
        }
        if(operation.equals("media.borderInfo")){
            String owner=SharedRuntime.text(p,"owner",64);runtime.guardOwner(owner);
            PhotoCaptureInfo capture=PhotoCaptureInfo.read(source);List<String> fields=new ArrayList<>();
            for(int i=0;i<5;i++)fields.add(capture.field(PhotoBorder.NONE,i));
            runtime.guardOwner(owner);
            return SharedJson.encode(SharedRuntime.map("brand",capture.brand,"model",capture.model,"fields",fields));
        }
        if(operation.equals("media.rawReferenceInfo")){
            if(!raw(source))throw new IOException("请选择 RAW 原文件。");runtime.guardOwner(SharedRuntime.text(p,"owner",64));
            Map<String,Object> reference=SharedRawReference.describe(runtime.root(),source,SharedRuntime.text(p,"referencePath",32768),cancel);
            NativeRawReference.validate(new File((String)reference.get("path")));return SharedJson.encode(reference);
        }
        if(operation.equals("media.rawThumbnail")){if(!raw(source))throw new IOException("请选择 RAW 原文件。");return SharedJson.encode(NativeRawThumbnail.request(runtime,source,cancel));}
        if(operation.equals("media.rawPreview")||operation.equals("media.rawDevelop")||operation.equals("media.rawDetail"))return rawDevelop(operation,p,source,cancel,progress);
        if(operation.startsWith("media.retouch"))return NativeRetouch.request(context,runtime,operation,p,source,cancel,progress);
        if(operation.equals("media.cleanupAnalyze")){
            String owner=SharedRuntime.text(p,"owner",64);runtime.guardOwner(owner);
            String sha=runtime.sourceIdentity(source.getPath(),true);File pixels=source;
            String regionId=SharedRuntime.text(p,"regionId",64);
            cc.huevia.ncp.AdjustmentRegion region=regionId.isEmpty()?null:runtime.cleanupRegion(source.getPath(),owner,SharedJson.encode(SharedRuntime.object(p.get("recipe"))),regionId);
            if(raw(source))pixels=RawDeveloper.develop(context,source,owner,RawDevelopmentSettings.DEFAULT,cancel,progress).workingFile;
            String pixelSha=PhotoEditStore.hashFile(pixels);
            PhotoCleanup.Analysis analysis=PhotoCleanupAnalyzer.analyze(pixels,pixelSha,region,cancel);
            runtime.guardOwner(owner);runtime.validateSource(source.getPath(),sha);
            return SharedCleanup.result(analysis);
        }
        boolean originalView=operation.equals("media.originalPreview"),localView=operation.equals("media.localPreview"),reviewView=operation.equals("media.reviewPreview"),detail=operation.equals("media.detailRender");
        if(!originalView&&!localView&&!reviewView&&!detail&&!operation.equals("media.preview")&&!operation.equals("media.export"))throw new IOException("未知的照片操作。");
        boolean preview=originalView||localView||reviewView||operation.equals("media.preview");
        int previewEdge=SharedRuntime.integer(p,"maxEdge",1280);
        if(preview&&(previewEdge<128||previewEdge>1280))throw new IOException("预览边长必须在 128 到 1280 之间。");
        String owner=SharedRuntime.text(p,"owner",64),original=source.getPath();
        String detailMode=detail?SharedRuntime.text(p,"viewMode",16):"";
        if(detail&&(p.containsKey("viewMode")&&!(p.get("viewMode") instanceof String)||!detailMode.isEmpty()&&!detailMode.equals("local")))throw new IOException("未知的细节构图模式。");
        boolean detailLocal=detail&&detailMode.equals("local");
        if(detail){
            runtime.guardOwner(owner);if(cancel.getAsBoolean())throw new InterruptedIOException("细节查看已取消。");
            String expected=SharedRuntime.text(p,"expectedSourceSha",64);if(!expected.matches("[a-f0-9]{64}"))throw new IOException("细节查看需要已校验的原图身份。");
            runtime.validateSource(original,expected);
            if(raw(source))throw new IOException("请先显影 RAW，再查看完整尺寸效果。");
        }
        if(p.containsKey("snapshot")&&!(p.get("snapshot") instanceof Boolean))throw new IOException("导出快照标识无效。");
        boolean snapshot=Boolean.TRUE.equals(p.get("snapshot"));
        PhotoEditStore.Draft frozen=originalView?runtime.originalView(original,owner):localView||detailLocal?runtime.localView(original,owner,SharedJson.encode(SharedRuntime.object(p.get("recipe")))):reviewView||snapshot||detail?runtime.reviewView(original,owner,SharedJson.encode(SharedRuntime.object(p.get("recipe")))):runtime.freezeEdit(original,owner,SharedJson.encode(SharedRuntime.object(p.get("recipe"))));
        if((snapshot||detail)&&!frozen.sourceSha.equals(SharedRuntime.text(p,"expectedSourceSha",64)))throw new IOException("原图与打开导出设置时不同，请重新打开照片。");
        if(!preview)runtime.validateSource(original,frozen.sourceSha);
        if(raw(source))source=RawDeveloper.develop(context,source,owner,RawDevelopmentSettings.DEFAULT,cancel,value->progress.accept(value*.3)).workingFile;
        File directory=new File(runtime.root(),preview||detail?"previews":"exports");if(!directory.isDirectory()&&!directory.mkdirs())throw new IOException("无法创建照片输出目录。");
        File temporary=File.createTempFile("render-",".part",directory),target=new File(directory,UUID.randomUUID()+".jpg");File reduced=null;boolean detailComplete=false,detailMoved=false;
        try{
            PhotoExportSpec spec=detail?PhotoExportSpec.full():preview?PhotoExportSpec.share():spec(p);
            PresetPreviewProfile profile=frozen.profile();
            BitmapFactory.Options sourceBounds=bounds(source);
            int sourceOrientation=new ExifInterface(source.getPath()).getAttributeInt(ExifInterface.TAG_ORIENTATION,1);if(sourceOrientation<1||sourceOrientation>8)sourceOrientation=1;
            PhotoGeometry.Plan plan=GeometryPreviewProfile.geometry(profile).plan(sourceBounds.outWidth,sourceBounds.outHeight,sourceOrientation);
            PhotoGeometry.Plan uncomposed=PhotoGeometry.NONE.plan(sourceBounds.outWidth,sourceBounds.outHeight,sourceOrientation);
            int[] canvas=BorderPreviewProfile.border(profile).dimensions(plan.width,plan.height);
            PhotoExportSpec.Resolved resolved=spec.resolve(canvas[0],canvas[1]);
            if(preview||!"image/jpeg".equals(bounds(source).outMimeType))NativeRaster.render(context,source,temporary,null,profile,spec,preview,previewEdge,cancel,progress);
            else PhotoPresetRenderer.forContext(context).render(source,temporary,profile,spec,cancel,progress::accept);
            if(cancel.getAsBoolean())throw new InterruptedIOException("照片处理已取消。");
            BitmapFactory.Options info=bounds(temporary,100_000_000);
            int orientation=new ExifInterface(temporary.getPath()).getAttributeInt(ExifInterface.TAG_ORIENTATION,1);
            int width=orientation>=5?info.outHeight:info.outWidth,height=orientation>=5?info.outWidth:info.outHeight;
            if(!preview&&(width!=resolved.width||height!=resolved.height))throw new IOException("成品尺寸与导出规格不符，未保存结果。");
            runtime.guardOwner(owner);
            if(!preview)runtime.validateSource(original,frozen.sourceSha);
            Files.move(temporary.toPath(),target.toPath(),StandardCopyOption.ATOMIC_MOVE);
            detailMoved=true;
            Map<String,Object> result=SharedRuntime.map("path",target.getPath(),"width",width,"height",height,"geometryWidth",plan.width,"geometryHeight",plan.height,"bytes",target.length(),"preview",preview,"model",preview?profile.modelVersion():SharedExportModel.of(profile,resolved),"exportSpec",preview?"":resolved.identity());
            if(detail){
                // The same full-size renderer, without the export transaction
                // or persistent draft mutation below.
                progress.accept(1);runtime.guardOwner(owner);runtime.validateSource(original,frozen.sourceSha);
                if(cancel.getAsBoolean())throw new InterruptedIOException("细节查看已取消。");
                result.put("sourceSha",frozen.sourceSha);result.put("temporary",true);result.put("fullResolution",true);
                result.put("detailToken",detailTiles.remember(original,owner,frozen.sourceSha,target.getPath(),width,height,cancel));
                runtime.guardOwner(owner);SharedDetailTiles.check(cancel);
                String encoded=SharedJson.encode(result);detailComplete=true;return encoded;
            }
            if(preview){result.put("sourceWidth",uncomposed.width);result.put("sourceHeight",uncomposed.height);}
            if(!preview){
                try{
                    String saved=runtime.commitVersion(original,owner,frozen,target.getPath(),SharedJson.encode(result),cancel);
                    if(!snapshot)runtime.markEditExported(owner,frozen);return saved;
                }finally{Files.deleteIfExists(target.toPath());}
            }
            return SharedJson.encode(result);
        }catch(PhotoPresetRenderer.Cancelled stopped){throw new InterruptedIOException("照片处理已取消。");}
        finally{Files.deleteIfExists(temporary.toPath());if(detail&&detailMoved&&!detailComplete)Files.deleteIfExists(target.toPath());if(reduced!=null)Files.deleteIfExists(reduced.toPath());}
    }
    private String rawDevelop(String operation,Map<String,Object> p,File source,BooleanSupplier cancel,DoubleConsumer progress)throws IOException{
        if(!raw(source))throw new IOException("请选择 RAW 原文件。");
        String owner=SharedRuntime.text(p,"owner",64);runtime.guardOwner(owner);
        boolean detail=operation.equals("media.rawDetail");String expected=detail?SharedRuntime.text(p,"expectedSourceSha",64):"";
        if(detail){if(!expected.matches("[0-9a-f]{64}"))throw new IOException("RAW 原图身份无效。");runtime.validateSource(source.getPath(),expected);}
        PhotoEditStore.Draft rawRecipe=null;
        if(detail){
            String mode=SharedRuntime.text(p,"viewMode",16);
            if(p.containsKey("viewMode")&&!(p.get("viewMode") instanceof String)||!mode.isEmpty()&&!mode.equals("review")&&!mode.equals("local"))throw new IOException("未知的 RAW 细节构图模式。");
            if(p.containsKey("recipe")){
                if(!(p.get("recipe") instanceof Map))throw new IOException("RAW 编辑设置无效。");
                String recipe=SharedJson.encode(SharedRuntime.object(p.get("recipe")));
                rawRecipe=mode.equals("local")?runtime.localView(source.getPath(),owner,recipe):runtime.reviewView(source.getPath(),owner,recipe);
                if(!rawRecipe.sourceSha.equals(expected))throw new IOException("RAW 原图已变化。");
            }
        }
        RawDevelopmentSettings settings=SharedRawSettings.parse(SharedJson.encode(SharedRuntime.object(p.get("settings"))));
        SharedRawReference.Reference reference=settings.colorMode==RawDevelopmentSettings.ColorMode.CAMERA_JPEG&&p.get("reference")!=null?SharedRawReference.resolve(runtime.root(),SharedJson.encode(p.get("reference")),cancel):null;
        RawDeveloper.Result result=RawDeveloper.develop(context,source,owner,reference==null?settings:settings.withColorMode(RawDevelopmentSettings.ColorMode.NEUTRAL),cancel,reference==null?progress:value->progress.accept(value*.65));
        RawJpegColorMatch.Fit fit=reference==null?null:NativeRawReference.fit(context,source,owner,result.sourceSha,reference,cancel);
        boolean preview=operation.equals("media.rawPreview");File dir=new File(runtime.root(),preview||detail?"previews":"raw-editor");
        if(!dir.isDirectory()&&!dir.mkdirs())throw new IOException("无法创建 RAW 编辑目录。");
        File temporary=File.createTempFile("raw-edit-",".part",dir),target=new File(dir,UUID.randomUUID()+".jpg");Bitmap bitmap=null;boolean complete=false;
        try{
            if(detail&&fit==null){Files.copy(result.workingFile.toPath(),temporary.toPath(),StandardCopyOption.REPLACE_EXISTING);RawEditorSource.writeMetadata(source,temporary,result.info);}
            else if(preview&&fit==null){File reduced=small(result.workingFile,dir,cancel);try{Files.move(reduced.toPath(),temporary.toPath(),StandardCopyOption.REPLACE_EXISTING);}finally{Files.deleteIfExists(reduced.toPath());}}
            else{
                BitmapFactory.Options options=new BitmapFactory.Options();options.inPreferredConfig=Bitmap.Config.ARGB_8888;options.inPreferredColorSpace=ColorSpace.get(ColorSpace.Named.SRGB);options.inSampleSize=1;options.inScaled=false;options.inMutable=fit!=null;
                if(preview)while(Math.max(result.info.width,result.info.height)/options.inSampleSize>1280)options.inSampleSize*=2;
                bitmap=BitmapFactory.decodeFile(result.workingFile.getPath(),options);
                if(bitmap==null||!preview&&(bitmap.getWidth()!=result.info.width||bitmap.getHeight()!=result.info.height))throw new IOException("无法读取完整显影像素，未缩小原图。");
                if(fit!=null){NativeRawReference.apply(bitmap,fit,cancel);progress.accept(.9);}
                try(FileOutputStream out=new FileOutputStream(temporary)){if(!bitmap.compress(Bitmap.CompressFormat.JPEG,preview?98:100,out))throw new IOException("无法生成 RAW 编辑副本。");out.flush();out.getFD().sync();}
                bitmap.recycle();bitmap=null;if(!preview)RawEditorSource.writeMetadata(source,temporary,result.info);
            }
            if(rawRecipe!=null){
                File composed=File.createTempFile("raw-detail-",".part",dir);
                try{renderRawRecipe(temporary,composed,rawRecipe,cancel,value->progress.accept(.55+.45*value));Files.move(composed.toPath(),temporary.toPath(),StandardCopyOption.REPLACE_EXISTING);}
                finally{Files.deleteIfExists(composed.toPath());}
            }
            if(cancel.getAsBoolean())throw new InterruptedIOException("RAW 显影已取消。");runtime.guardOwner(owner);runtime.validateSource(source.getPath(),result.sourceSha);
            if(reference!=null)reference.verify(cancel);
            Files.move(temporary.toPath(),target.toPath(),StandardCopyOption.ATOMIC_MOVE);
            BitmapFactory.Options info=detail?bounds(target,100_000_000):bounds(target);
            int orientation=new ExifInterface(target.getPath()).getAttributeInt(ExifInterface.TAG_ORIENTATION,1),width=orientation>=5?info.outHeight:info.outWidth,height=orientation>=5?info.outWidth:info.outHeight;
            Map<String,Object> value=SharedRuntime.map("path",target.getPath(),"width",detail?width:info.outWidth,"height",detail?height:info.outHeight,"sourceSha",result.sourceSha,"rawColorStatus",fit==null?result.colorStatus:NativeRawReference.status(fit),"settings",SharedJson.object(SharedRawSettings.json(settings)));
            if(detail){if(!expected.equals(result.sourceSha))throw new IOException("RAW 原图已变化。");value.put("detailToken",detailTiles.remember(source.getPath(),owner,result.sourceSha,target.getPath(),width,height,cancel));value.put("temporary",true);value.put("fullResolution",true);}
            progress.accept(1);runtime.guardOwner(owner);SharedDetailTiles.check(cancel);String encoded=SharedJson.encode(value);complete=true;return encoded;
        }finally{if(bitmap!=null)bitmap.recycle();Files.deleteIfExists(temporary.toPath());if(detail&&!complete)Files.deleteIfExists(target.toPath());}
    }
    private void renderRawRecipe(File working,File output,PhotoEditStore.Draft frozen,BooleanSupplier cancel,DoubleConsumer progress)throws IOException{
        PresetPreviewProfile profile=frozen.profile();PhotoExportSpec spec=PhotoExportSpec.full();BitmapFactory.Options source=bounds(working);
        int orientation=new ExifInterface(working.getPath()).getAttributeInt(ExifInterface.TAG_ORIENTATION,1);if(orientation<1||orientation>8)orientation=1;
        PhotoGeometry.Plan geometry=GeometryPreviewProfile.geometry(profile).plan(source.outWidth,source.outHeight,orientation);int[] canvas=BorderPreviewProfile.border(profile).dimensions(geometry.width,geometry.height);PhotoExportSpec.Resolved expected=spec.resolve(canvas[0],canvas[1]);
        try{
            if("image/jpeg".equals(source.outMimeType))PhotoPresetRenderer.forContext(context).render(working,output,profile,spec,cancel,progress::accept);
            else NativeRaster.render(context,working,output,null,profile,spec,false,1280,cancel,progress);
        }catch(PhotoPresetRenderer.Cancelled stopped){throw new InterruptedIOException("RAW 细节处理已取消。");}
        SharedDetailTiles.check(cancel);BitmapFactory.Options actual=bounds(output,100_000_000);int exif=new ExifInterface(output.getPath()).getAttributeInt(ExifInterface.TAG_ORIENTATION,1);
        int width=exif>=5?actual.outHeight:actual.outWidth,height=exif>=5?actual.outWidth:actual.outHeight;if(width!=expected.width||height!=expected.height)throw new IOException("RAW 完整效果图尺寸校验失败。");
    }
    private String detailTile(Map<String,Object> p,BooleanSupplier cancel,DoubleConsumer progress)throws IOException{
        String owner=SharedRuntime.text(p,"owner",64);runtime.guardOwner(owner);
        SharedDetailTiles.Entry entry=detailTiles.checked(SharedRuntime.text(p,"detailToken",64),owner,SharedRuntime.text(p,"path",4096),SharedRuntime.text(p,"expectedSourceSha",64),cancel);
        File source=runtime.privateFile(entry.path);Map<String,Object> region=SharedRuntime.object(p.get("region"));
        BitmapFactory.Options info=bounds(source,100_000_000);int orientation=SharedDetailTiles.normalizedOrientation(new ExifInterface(source.getPath()).getAttributeInt(ExifInterface.TAG_ORIENTATION,1));
        SharedDetailTiles.Plan plan=new SharedDetailTiles.Plan(info.outWidth,info.outHeight,orientation,coordinate(region,"left"),coordinate(region,"top"),coordinate(region,"right"),coordinate(region,"bottom"),SharedRuntime.integer(p,"maxEdge",1536));
        if(plan.sourceWidth!=entry.width||plan.sourceHeight!=entry.height)throw new IOException("完整细节图尺寸已变化。");
        File directory=new File(runtime.root(),"previews"),temporary=File.createTempFile("detail-tile-",".part",directory),target=new File(directory,UUID.randomUUID()+".jpg");
        BitmapRegionDecoder decoder=null;Bitmap decoded=null,tile=null;boolean complete=false;
        try{
            SharedDetailTiles.check(cancel);decoder=BitmapRegionDecoder.newInstance(source.getPath(),false);
            BitmapFactory.Options options=new BitmapFactory.Options();options.inSampleSize=plan.sampleSize;options.inPreferredConfig=Bitmap.Config.ARGB_8888;options.inPreferredColorSpace=ColorSpace.get(ColorSpace.Named.SRGB);
            decoded=decoder.decodeRegion(new Rect(plan.rawLeft,plan.rawTop,plan.rawRight,plan.rawBottom),options);if(decoded==null)throw new IOException("无法读取照片可见细节。");
            SharedDetailTiles.check(cancel);tile=Bitmap.createBitmap(plan.width,plan.height,Bitmap.Config.ARGB_8888);
            float[] from=new float[6],to={0,0,plan.width,0,0,plan.height};double[] xs={plan.left,plan.right,plan.left},ys={plan.top,plan.top,plan.bottom};
            for(int i=0;i<3;i++){from[i*2]=(float)((plan.sourceX(xs[i],ys[i])-plan.rawLeft)*decoded.getWidth()/(plan.rawRight-plan.rawLeft));from[i*2+1]=(float)((plan.sourceY(xs[i],ys[i])-plan.rawTop)*decoded.getHeight()/(plan.rawBottom-plan.rawTop));}
            Matrix transform=new Matrix();if(!transform.setPolyToPoly(from,0,to,0,3))throw new IOException("细节图方向无效。");new Canvas(tile).drawBitmap(decoded,transform,new Paint(Paint.FILTER_BITMAP_FLAG));
            try(FileOutputStream output=new FileOutputStream(temporary)){if(!tile.compress(Bitmap.CompressFormat.JPEG,98,output))throw new IOException("无法保存可见细节。");output.flush();output.getFD().sync();}
            detailTiles.verify(entry,cancel);runtime.guardOwner(owner);SharedDetailTiles.check(cancel);Files.move(temporary.toPath(),target.toPath(),StandardCopyOption.ATOMIC_MOVE);
            progress.accept(1);runtime.guardOwner(owner);SharedDetailTiles.check(cancel);
            String value=SharedJson.encode(SharedRuntime.map("path",target.getPath(),"width",plan.width,"height",plan.height,"sourceWidth",plan.sourceWidth,"sourceHeight",plan.sourceHeight,"region",SharedJson.object(plan.regionJson()),"sourceSha",entry.sourceSha,"detailToken",entry.token,"temporary",true,"decodedWidth",decoded.getWidth(),"decodedHeight",decoded.getHeight(),"decodedBytes",decoded.getAllocationByteCount()));complete=true;return value;
        }finally{if(decoder!=null)decoder.recycle();if(decoded!=null)decoded.recycle();if(tile!=null)tile.recycle();Files.deleteIfExists(temporary.toPath());if(!complete)Files.deleteIfExists(target.toPath());}
    }
    private static double coordinate(Map<String,Object> region,String key)throws IOException{Object value=region.get(key);if(!(value instanceof Number))throw new IOException("细节可见区域无效。");return ((Number)value).doubleValue();}
    private static PhotoExportSpec spec(Map<String,Object> p)throws IOException{String size=SharedRuntime.text(p,"size",16);if(size.equals("share"))return PhotoExportSpec.share();if(size.equals("custom"))return PhotoExportSpec.custom(SharedRuntime.integer(p,"longEdge",2048),SharedRuntime.integer(p,"quality",95));return PhotoExportSpec.full();}
    private static boolean raw(File source){String name=source.getName().toLowerCase(Locale.ROOT);return name.matches(".*\\.(nef|nrw|arw|cr2|cr3|dng|raf|rw2|orf|pef|srw)$");}
    private static BitmapFactory.Options bounds(File source)throws IOException{return bounds(source,60_000_000);}
    private static BitmapFactory.Options bounds(File source,long maxPixels)throws IOException{BitmapFactory.Options options=new BitmapFactory.Options();options.inJustDecodeBounds=true;BitmapFactory.decodeFile(source.getPath(),options);if(options.outWidth<1||options.outHeight<1||(long)options.outWidth*options.outHeight>maxPixels)throw new IOException("照片尺寸无效或超过处理上限。");return options;}
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
