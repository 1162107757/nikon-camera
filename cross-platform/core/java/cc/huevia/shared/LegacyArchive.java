package cc.huevia.shared;

import cc.huevia.album.*;
import cc.huevia.library.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.function.BooleanSupplier;
import java.util.zip.*;

/** Versioned user-controlled transfer; exported account data never contains credentials. */
public final class LegacyArchive {
    public static final long MAX_BYTES=16L*1024*1024*1024,MAX_FILE=1024L*1024*1024;
    public static final int MAX_ENTRIES=60000;
    private final ZipOutputStream zip;
    private final Set<String> written=new HashSet<>();
    private final BooleanSupplier cancel;
    private long totalPayloadBytes;
    private LegacyArchive(ZipOutputStream zip,BooleanSupplier cancel){this.zip=zip;this.cancel=cancel;}
    public static void exportAndroid(File files,File photos,String owner,Map<String,Object> account,File output,BooleanSupplier cancel)throws IOException{
        try(ZipOutputStream zip=new ZipOutputStream(new BufferedOutputStream(new FileOutputStream(output)))){
            LegacyArchive exporter=new LegacyArchive(zip,cancel);
            exporter.export(files,photos,owner,account,"android-original");
        }
    }
    public static void exportShared(File files,File photos,String owner,Map<String,Object> account,File output,BooleanSupplier cancel)throws IOException{
        try(ZipOutputStream zip=new ZipOutputStream(new BufferedOutputStream(new FileOutputStream(output)))){
            new LegacyArchive(zip,cancel).export(files,photos,owner,account,"shared");
        }
    }
    public static void exportIosPresets(File directory,File output,BooleanSupplier cancel)throws IOException{
        try(ZipOutputStream zip=new ZipOutputStream(new BufferedOutputStream(new FileOutputStream(output)))){
            LegacyArchive exporter=new LegacyArchive(zip,cancel);List<Object> presets=new ArrayList<>();
            File[] files=directory.listFiles();if(files==null||files.length>20000)throw new IOException("旧版预设目录无法读取或文件过多。");
            for(File file:files){check(cancel);String ext=extension(file.getName());if(!ext.equals("ncp")&&!ext.equals("np3"))continue;
                owned(directory,file);if(file.length()<1||file.length()>1024*1024)throw new IOException("旧版预设文件大小无效。");byte[] bytes=Files.readAllBytes(file.toPath());PresetFile.validate(bytes);
                Map<String,Object> row=exporter.payload(file,ext);row.put("name",file.getName());row.put("displayName",file.getName());row.put("category","");row.put("description","");presets.add(row);}
            if(presets.isEmpty())throw new IOException("所选文件夹中没有 NCP 或 NP3 预设。");
            exporter.manifest("ios-original",new LinkedHashMap<>(),presets,List.of(),List.of(),List.of());
        }
    }
    private void export(File files,File photos,String owner,Map<String,Object> account,String origin)throws IOException{
        List<Object> presetRows=new ArrayList<>(),photoRows=new ArrayList<>(),draftRows=new ArrayList<>(),projectRows=new ArrayList<>();
        File outgoing=new File(outputWorkspace(files),UUID.randomUUID().toString());if(!outgoing.mkdirs())throw new IOException("无法准备迁出资料。");
        try{
            // Original readers can perform recovery. Give them private copies, never the old files.
            for(String part:List.of("preset-library","selected.ncp","preset.json","photo-live-projects","personal-presets.json"))copyTree(new File(files,part),new File(outgoing,part));
            String ownerHash=PhotoEditStore.hash(owner.getBytes(StandardCharsets.UTF_8));
            copyTree(new File(files,origin.equals("shared")?"shared-project-presets/"+ownerHash:"photo-project-presets"),new File(outgoing,"photo-project-presets"));
            copyTree(new File(files,"photo-edit-drafts/"+ownerHash),new File(outgoing,"photo-edit-drafts/"+ownerHash));
            PresetLibrary library=new PresetLibrary(outgoing);
            PersonalPresetSync visibility=new PersonalPresetSync(outgoing,library);
            for(PresetRecord preset:library.list()){
                if(!visibility.visible(owner,preset.id))continue;
                check(cancel);File bytes=new File(outgoing,preset.id+"."+preset.fileFormat.toLowerCase(Locale.ROOT));Files.write(bytes.toPath(),library.readPreset(preset.id));
                Map<String,Object> row=payload(bytes,preset.fileFormat.toLowerCase(Locale.ROOT));row.put("name",preset.originalFileName);row.put("displayName",preset.displayName);row.put("category",preset.category);row.put("description",preset.description);presetRows.add(row);
            }
            Map<String,Map<String,Object>> byFilename=new LinkedHashMap<>();Set<String> identities=new HashSet<>();
            List<File> sources=new ArrayList<>();Set<String> sourcePaths=new HashSet<>();
            List<File> sourceDirectories=new ArrayList<>(List.of(photos));
            if(origin.equals("android-original")){
                sourceDirectories.add(new File(files,"pictures/camera-album"));sourceDirectories.add(new File(files,"raw-editor-sources"));
                sourceDirectories.add(new File(files,"camera-raw"));sourceDirectories.add(new File(photos.getParentFile(),"camera-raw"));
            }
            for(File directory:sourceDirectories){if(!directory.isDirectory())continue;File[] items=directory.listFiles();if(items==null)throw new IOException("旧版照片目录无法读取。");for(File item:items)if(sourcePaths.add(item.getCanonicalPath()))sources.add(item);}
            if(sources.size()>60000)throw new IOException("旧版照片过多，请分批导出。");
            PhotoEditStore edits=new PhotoEditStore(outgoing,owner);
            for(File source:sources){
                check(cancel);String ext=extension(source.getName());if(!photoExtension(ext)||!source.isFile())continue;owned(source.getParentFile(),source);
                Map<String,Object> row=payload(source,ext);String sha=(String)row.get("sha256");
                String name=source.getName();int marker=name.indexOf("__");if(marker>=0)name=name.substring(marker+2);row.put("name",safeName(name));
                if(source.getParentFile().getCanonicalFile().equals(photos.getCanonicalFile()))byFilename.put(source.getName(),row);else byFilename.putIfAbsent(source.getName(),row);
                if(identities.add(sha))photoRows.add(row);
                PhotoEditStore.Draft draft=edits.read(sha);
                if(draft!=null){
                    File encoded=new File(outgoing,"photo-edit-drafts/"+ownerHash+"/"+sha+".draft");
                    Map<String,Object> item=payload(encoded,"draft");item.put("sourceSha",sha);draftRows.add(item);
                }
            }
            File projectDirectory=new File(outgoing,"photo-live-projects");
            if(projectDirectory.isDirectory()){
                PhotoLiveProjectStore projects=new PhotoLiveProjectStore(projectDirectory,photos);
                PhotoProjectPresetStore defaults=new PhotoProjectPresetStore(new File(outgoing,"photo-project-presets"));
                for(PhotoLiveProject project:projects.list()){
                    List<Object> members=new ArrayList<>();for(DownloadedPhoto photo:project.photos){Map<String,Object> source=byFilename.get(photo.file().getName());if(source==null)throw new IOException("项目存在未导出的原图，请先核对旧版资料。");members.add(source.get("sha256"));}
                    PhotoProjectPresetStore.Config config=defaults.config(project.id);
                    projectRows.add(SharedRuntime.map("id",project.id,"name",project.name,"photos",members,"presetId",config.presetId,"presetName",config.presetName));
                }
            }
            manifest(origin,account,presetRows,photoRows,draftRows,projectRows);
        }finally{removeTree(outgoing);}
    }
    private static File outputWorkspace(File files)throws IOException{File directory=new File(files,"legacy-export-work");if(!directory.isDirectory()&&!directory.mkdirs())throw new IOException("无法准备迁出资料。");return directory;}
    private void manifest(String origin,Map<String,Object> account,List<Object> presets,List<Object> photos,List<Object> drafts,List<Object> projects)throws IOException{
        Map<String,Object> safeAccount=new LinkedHashMap<>();
        for(String key:List.of("id","provider","username","nickname")){Object value=account.get(key);if(value instanceof String&&((String)value).length()<=240)safeAccount.put(key,value);}
        byte[] manifest=SharedJson.encode(SharedRuntime.map("format","huevia-migration","schema",1,"id",UUID.randomUUID().toString(),"origin",origin,"exportedAt",System.currentTimeMillis(),"account",safeAccount,"presets",presets,"photos",photos,"drafts",drafts,"projects",projects)).getBytes(StandardCharsets.UTF_8);
        if(manifest.length>4*1024*1024)throw new IOException("资料清单过大，请分批导出。");
        zip.putNextEntry(new ZipEntry("huevia-migration.json"));zip.write(manifest);zip.closeEntry();
    }
    private Map<String,Object> payload(File source,String ext)throws IOException{
        check(cancel);if(!source.isFile()||source.length()<1||source.length()>MAX_FILE)throw new IOException("迁出文件大小无效。");
        String sha=PhotoEditStore.hashFile(source),entry="payload/"+sha+"."+ext;long length=source.length();
        if(written.add(entry)){
            totalPayloadBytes+=length;if(totalPayloadBytes>MAX_BYTES||written.size()>MAX_ENTRIES)throw new IOException("迁出资料超过本次转移上限，请先分批整理。");
            zip.putNextEntry(new ZipEntry(entry));try(InputStream input=new FileInputStream(source)){byte[] block=new byte[65536];int count;long done=0;while((count=input.read(block))!=-1){check(cancel);done+=count;if(done>length)throw new IOException("迁出期间文件发生变化。");zip.write(block,0,count);}if(done!=length)throw new IOException("迁出期间文件发生变化。");}zip.closeEntry();
            if(!PhotoEditStore.hashFile(source).equals(sha))throw new IOException("迁出期间文件发生变化。");
        }
        return SharedRuntime.map("entry",entry,"sha256",sha,"bytes",length,"extension",ext);
    }
    public static Map<String,Object> unpack(File archive,File directory,BooleanSupplier cancel)throws IOException{
        if(!archive.isFile()||archive.length()<1||archive.length()>MAX_BYTES)throw new IOException("迁入文件大小无效。");
        if(!directory.mkdirs())throw new IOException("无法创建迁入暂存目录。");long total=0;int entries=0;Set<String> seen=new HashSet<>();
        try(ZipInputStream input=new ZipInputStream(new BufferedInputStream(new FileInputStream(archive)))){
            ZipEntry entry;byte[] block=new byte[65536];
            while((entry=input.getNextEntry())!=null){
                check(cancel);String name=entry.getName();
                if(++entries>MAX_ENTRIES||entry.isDirectory()||!seen.add(name)||!(name.equals("huevia-migration.json")||name.matches("payload/[0-9a-f]{64}\\.(ncp|np3|draft|jpg|jpeg|png|nef|nrw|dng|arw|cr2|cr3|raf|rw2|orf|pef|srw)")))throw new IOException("迁入包包含未知或重复路径。");
                File target=new File(directory,name);if(!target.getCanonicalFile().toPath().startsWith(directory.getCanonicalFile().toPath()))throw new IOException("迁入路径越界。");
                File parent=target.getParentFile();if(!parent.isDirectory()&&!parent.mkdirs())throw new IOException("无法准备迁入文件。");long bytes=0,limit=name.equals("huevia-migration.json")?16L*1024*1024:MAX_FILE;
                try(FileOutputStream output=new FileOutputStream(target)){int count;while((count=input.read(block))!=-1){check(cancel);bytes+=count;total+=count;if(bytes>limit||total>MAX_BYTES)throw new IOException("迁入包展开后超过限制。");output.write(block,0,count);}output.getFD().sync();}input.closeEntry();
            }
        }
        File manifest=new File(directory,"huevia-migration.json");if(!manifest.isFile())throw new IOException("请选择 Huevia 旧版资料导出包。");
        Map<String,Object> value=SharedJson.object(new String(Files.readAllBytes(manifest.toPath()),StandardCharsets.UTF_8));
        if(!"huevia-migration".equals(value.get("format"))||!(value.get("schema") instanceof Number)||((Number)value.get("schema")).intValue()!=1||!SharedRuntime.text(value,"id",36).matches("[0-9a-f-]{36}"))throw new IOException("迁入包版本或身份无效。");
        for(String kind:List.of("presets","photos","drafts"))for(Object raw:rows(value,kind)){
            Map<String,Object> row=SharedRuntime.object(raw);String name=SharedRuntime.text(row,"entry",160),sha=SharedRuntime.text(row,"sha256",64),ext=SharedRuntime.text(row,"extension",8);File source=new File(directory,name);
            if(!name.equals("payload/"+sha+"."+ext)||!sha.matches("[0-9a-f]{64}")||!source.isFile()||!(row.get("bytes") instanceof Number)||source.length()!=((Number)row.get("bytes")).longValue()||!PhotoEditStore.hashFile(source).equals(sha))throw new IOException("迁入资料的字节数或 SHA-256 校验失败。");
        }
        rows(value,"projects");SharedRuntime.object(value.get("account"));return value;
    }
    public static List<?> rows(Map<String,Object> value,String key)throws IOException{Object rows=value.get(key);if(!(rows instanceof List)||((List<?>)rows).size()>20000)throw new IOException("迁入资料清单无效。");return (List<?>)rows;}
    public static String extension(String name){int dot=name.lastIndexOf('.');return dot<0?"":name.substring(dot+1).toLowerCase(Locale.ROOT);}
    public static boolean photoExtension(String ext){return List.of("jpg","jpeg","png","nef","nrw","dng","arw","cr2","cr3","raf","rw2","orf","pef","srw").contains(ext);}
    public static String safeName(String name)throws IOException{if(name==null||name.isBlank()||name.length()>240||name.matches(".*[\\x00-\\x1f/\\\\].*"))throw new IOException("资料文件名称无效。");return name;}
    static void owned(File parent,File source)throws IOException{if(Files.isSymbolicLink(source.toPath())||!source.getCanonicalFile().getParentFile().equals(parent.getCanonicalFile()))throw new IOException("旧资料路径无效。");}
    static void copyTree(File source,File target)throws IOException{if(!source.exists())return;if(Files.isSymbolicLink(source.toPath()))throw new IOException("旧资料不能包含符号链接。");if(source.isDirectory()){if(!target.isDirectory()&&!target.mkdirs())throw new IOException("无法准备旧资料副本。");File[] children=source.listFiles();if(children==null||children.length>MAX_ENTRIES)throw new IOException("旧资料目录无法读取。");for(File child:children)copyTree(child,new File(target,child.getName()));}else{if(source.length()>MAX_FILE)throw new IOException("旧资料文件过大。");File parent=target.getParentFile();if(!parent.isDirectory()&&!parent.mkdirs())throw new IOException("无法准备旧资料副本。");Files.copy(source.toPath(),target.toPath(),StandardCopyOption.REPLACE_EXISTING);}}
    static void check(BooleanSupplier cancel)throws IOException{if(cancel.getAsBoolean())throw new InterruptedIOException("资料迁移已取消。");}
    static void removeTree(File directory)throws IOException{if(Files.isSymbolicLink(directory.toPath()))throw new IOException("资料清理路径无效。");File[] files=directory.listFiles();if(files!=null)for(File file:files){if(file.isDirectory())removeTree(file);else Files.deleteIfExists(file.toPath());}Files.deleteIfExists(directory.toPath());}
}
