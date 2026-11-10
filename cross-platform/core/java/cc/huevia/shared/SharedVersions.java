package cc.huevia.shared;

import cc.huevia.album.PhotoEditStore;
import cc.huevia.library.SharedJson;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.function.BooleanSupplier;

/** Immutable private JPEG versions. Recipes use the original checksummed draft format. */
final class SharedVersions {
    private final File root;
    SharedVersions(File root){this.root=root;}
    private static void check(BooleanSupplier cancel)throws IOException{
        if(Thread.currentThread().isInterrupted()||cancel.getAsBoolean())throw new InterruptedIOException("成品操作已取消。");
    }
    private File checked(File file)throws IOException{
        File value=file.getCanonicalFile();
        if(!value.equals(file)||!value.toPath().startsWith(root.toPath()))throw new IOException("成品资料路径无效。");
        for(File part=file;part!=null&&!part.equals(root);part=part.getParentFile())if(Files.isSymbolicLink(part.toPath()))throw new IOException("成品资料路径无效。");
        return value;
    }
    private File directory(String owner)throws IOException{
        File value=checked(new File(root,"photo-versions/"+PhotoEditStore.hash(owner.getBytes(StandardCharsets.UTF_8))));
        if(!value.isDirectory()&&!value.mkdirs())throw new IOException("无法创建成品资料目录。");return value;
    }
    private File version(String owner,String id)throws IOException{
        if(id==null||!id.matches("[0-9a-f]{64}"))throw new IOException("成品版本身份无效。");
        return checked(new File(directory(owner),id));
    }
    private File jpeg(File dir,String id)throws IOException{return checked(new File(dir,"effect-"+id+"__Effect.JPG"));}
    private Map<String,Object> read(String owner,String id)throws IOException{
        File dir=version(owner,id),record=checked(new File(dir,"manifest.json"));
        if(!record.isFile()||record.length()<2||record.length()>32768)throw new IOException("成品记录不存在或已损坏。");
        byte[] manifest=Files.readAllBytes(record.toPath());File checksum=checked(new File(dir,"manifest.sha256"));
        if(!checksum.isFile()||checksum.length()!=64||!PhotoEditStore.hash(manifest).equals(new String(Files.readAllBytes(checksum.toPath()),StandardCharsets.US_ASCII)))throw new IOException("成品记录校验失败。");
        Map<String,Object> row=SharedJson.object(new String(manifest,StandardCharsets.UTF_8));
        if(SharedRuntime.integer(row,"schema",0)!=1||!id.equals(SharedRuntime.text(row,"id",64)))throw new IOException("成品记录身份不符。");
        String sha=SharedRuntime.text(row,"sourceSha",64),model=SharedRuntime.text(row,"model",256),imageSha=SharedRuntime.text(row,"sha256",64);
        PhotoEditStore.Draft draft=new PhotoEditStore(dir,owner).read(sha);
        if(draft==null||!imageSha.matches("[0-9a-f]{64}")||!id.equals(versionKey(draft,model,SharedRuntime.text(row,"exportSpec",128)))||!key(draft,model).equals(SharedRuntime.text(row,"effectKey",64))||!draft.identity().equals(SharedRuntime.text(row,"draftIdentity",16384)))throw new IOException("成品配方与记录不符。");
        // A historical JPEG remains usable after a later renderer-model update.
        // Its frozen recipe, stored model key, record checksum and pixel digest
        // establish identity; only a new commit must match today's renderer.
        validateSpec(row);
        Object created=row.get("createdAt");if(!(created instanceof Number)||((Number)created).longValue()<0||((Number)created).doubleValue()!=((Number)created).longValue())throw new IOException("成品时间记录无效。");
        String relative=SharedRuntime.text(row,"source",4096);
        File source=checked(new File(root,relative));
        if(new File(relative).isAbsolute()||relative.isEmpty())throw new IOException("成品原图路径无效。");
        File image=jpeg(dir,key(draft,model));Object size=row.get("bytes");
        if(!(size instanceof Number)||((Number)size).longValue()<4||!image.isFile()||image.length()!=((Number)size).longValue())throw new IOException("成品文件缺失或大小已变化。");
        row.put("path",image.getPath());row.put("sourcePath",source.getPath());row.put("sourceAvailable",source.isFile());
        return row;
    }
    static String key(PhotoEditStore.Draft draft,String model)throws IOException{
        if(model==null||model.isEmpty()||model.length()>256||model.matches(".*[\\p{Cntrl}].*"))throw new IOException("成品效果模型无效。");
        // Exact source/preset/model identity used by original PhotoPresetBatch.key.
        return PhotoEditStore.hash((draft.sourceSha+"\n"+draft.effectPresetSha()+"\n"+model).getBytes(StandardCharsets.UTF_8));
    }
    private static String versionKey(PhotoEditStore.Draft draft,String model,String spec)throws IOException{
        // Inactive cleanup/palette state can produce identical pixels while
        // remaining meaningful when the user resumes editing the saved recipe.
        return PhotoEditStore.hash(("huevia-saved-version-v1\n"+key(draft,model)+"\n"+draft.identity()+"\n"+spec).getBytes(StandardCharsets.UTF_8));
    }
    private static void validate(PhotoEditStore.Draft draft,Map<String,Object> details)throws IOException{
        validateSpec(details);
        String model=SharedRuntime.text(details,"model",256),spec=SharedRuntime.text(details,"exportSpec",128);
        String full=draft.profile().modelVersion()+":full-jpeg95-srgb-v1",custom="export-jpeg-v1:"+PhotoEditStore.hash((full+"\n"+spec).getBytes(StandardCharsets.UTF_8));
        if(!(model.equals(full)&&spec.contains(":q95:")||model.equals(custom)))throw new IOException("成品效果模型与配方或编码规格不符。");
    }
    private static void validateSpec(Map<String,Object> details)throws IOException{
        String spec=SharedRuntime.text(details,"exportSpec",128);
        int width=SharedRuntime.integer(details,"width",0),height=SharedRuntime.integer(details,"height",0);
        if(width<1||height<1||width>65535||height>65535||(long)width*height>100_000_000||!spec.matches("jpeg-srgb-v1:"+width+"x"+height+":q(7[0-9]|8[0-9]|9[0-9]|100):capture-no-gps-v1"))throw new IOException("成品编码规格无效。");
    }
    Map<String,Object> commit(File source,String owner,PhotoEditStore.Draft frozen,File rendered,Map<String,Object> details,BooleanSupplier cancel)throws IOException{
        check(cancel);checked(source);checked(rendered);
        if(!rendered.toPath().startsWith(new File(root,"exports").toPath())||!rendered.isFile()||rendered.length()<4||rendered.length()>512L*1024*1024)throw new IOException("成品输出文件无效。");
        String model=SharedRuntime.text(details,"model",256),spec=SharedRuntime.text(details,"exportSpec",128),effectKey=key(frozen,model),id=versionKey(frozen,model,spec);
        validate(frozen,details);int width=SharedRuntime.integer(details,"width",0),height=SharedRuntime.integer(details,"height",0);
        if(!frozen.sourceSha.equals(hash(source,cancel)))throw new IOException("原文件已变化，未保存成品版本。");
        File target=version(owner,id);
        if(target.exists()){
            Map<String,Object> previous=open(owner,id,cancel);
            if(!spec.equals(previous.get("exportSpec"))||!frozen.identity().equals(previous.get("draftIdentity")))throw new IOException("已有成品与当前配方或规格不符，未覆盖。");
            Files.delete(rendered.toPath());previous.put("reused",true);return previous;
        }
        File staging=checked(new File(directory(owner),".pending-"+UUID.randomUUID()));
        if(!staging.mkdir())throw new IOException("无法暂存成品版本。");
        try{
            String imageSha=hash(rendered,cancel);
            Map<String,Object> row=SharedRuntime.map("schema",1,"id",id,"effectKey",effectKey,"sourceSha",frozen.sourceSha,"source",root.toPath().relativize(source.toPath()).toString().replace('\\','/'),"name",frozen.label(),"createdAt",System.currentTimeMillis(),"draftIdentity",frozen.identity(),"model",model,"exportSpec",spec,"width",width,"height",height,"bytes",rendered.length(),"sha256",imageSha,"preview",false,"rawColorStatus",details.getOrDefault("rawColorStatus",""));
            new PhotoEditStore(staging,owner).save(frozen);
            byte[] manifest=SharedJson.encode(row).getBytes(StandardCharsets.UTF_8);
            write(checked(new File(staging,"manifest.json")),manifest);
            write(checked(new File(staging,"manifest.sha256")),PhotoEditStore.hash(manifest).getBytes(StandardCharsets.US_ASCII));
            check(cancel);Files.move(rendered.toPath(),jpeg(staging,effectKey).toPath());check(cancel);
            try{Files.move(staging.toPath(),target.toPath(),StandardCopyOption.ATOMIC_MOVE);}
            catch(AtomicMoveNotSupportedException unsupported){Files.move(staging.toPath(),target.toPath());}
            row.put("path",jpeg(target,effectKey).getPath());row.put("sourcePath",source.getPath());row.put("sourceAvailable",true);row.put("reused",false);return row;
        }finally{if(staging.exists())remove(staging);}
    }
    List<Object> list(String owner,String sourceSha,BooleanSupplier cancel)throws IOException{
        File[] files=directory(owner).listFiles();if(files==null)throw new IOException("无法读取成品目录。");
        List<Map<String,Object>> rows=new ArrayList<>();
        for(File file:files){check(cancel);if(!file.getName().matches("[0-9a-f]{64}"))continue;
            try{Map<String,Object> row=read(owner,file.getName());if(sourceSha.isEmpty()||sourceSha.equals(row.get("sourceSha")))rows.add(row);}
            catch(IOException invalid){rows.add(SharedRuntime.map("id",file.getName(),"name","无法读取的成品记录","error",invalid.getMessage(),"createdAt",0));}
        }
        rows.sort((a,b)->Long.compare(((Number)b.get("createdAt")).longValue(),((Number)a.get("createdAt")).longValue()));
        return new ArrayList<Object>(rows);
    }
    Map<String,Object> open(String owner,String id,BooleanSupplier cancel)throws IOException{
        check(cancel);Map<String,Object> row=read(owner,id);
        if(!row.get("sha256").equals(hash(new File((String)row.get("path")),cancel)))throw new IOException("成品内容已变化，未分享或覆盖。");
        return row;
    }
    PhotoEditStore.Draft draft(String owner,String id,BooleanSupplier cancel)throws IOException{
        Map<String,Object> row=open(owner,id,cancel);File source=new File((String)row.get("sourcePath"));
        if(!source.isFile()||!row.get("sourceSha").equals(hash(source,cancel)))throw new IOException("原文件不可用，仍可查看和分享已保存的成品。");
        return new PhotoEditStore(version(owner,id),owner).read((String)row.get("sourceSha"));
    }
    void delete(String owner,String id,BooleanSupplier cancel)throws IOException{
        File dir=version(owner,id);if(!dir.exists())return;
        checked(dir);check(cancel);File retired=checked(new File(directory(owner),".deleted-"+UUID.randomUUID()));
        Files.move(dir.toPath(),retired.toPath());remove(retired);
    }
    private static String hash(File file,BooleanSupplier cancel)throws IOException{
        java.security.MessageDigest digest;try{digest=java.security.MessageDigest.getInstance("SHA-256");}catch(Exception impossible){throw new AssertionError(impossible);}
        byte[] buffer=new byte[65536];try(InputStream input=Files.newInputStream(file.toPath())){int count;while((count=input.read(buffer))!=-1){check(cancel);digest.update(buffer,0,count);}}
        StringBuilder value=new StringBuilder();for(byte b:digest.digest())value.append(String.format(Locale.ROOT,"%02x",b&255));return value.toString();
    }
    private static void write(File file,byte[] bytes)throws IOException{try(FileOutputStream output=new FileOutputStream(file)){output.write(bytes);output.getFD().sync();}}
    private void remove(File file)throws IOException{
        checked(file);if(file.isDirectory()){File[] children=file.listFiles();if(children==null)throw new IOException("无法清理成品暂存资料。");for(File child:children)remove(child);}Files.deleteIfExists(file.toPath());
    }
}
