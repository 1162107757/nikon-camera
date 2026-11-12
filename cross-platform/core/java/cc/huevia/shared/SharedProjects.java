package cc.huevia.shared;

import cc.huevia.album.DownloadedPhoto;
import cc.huevia.album.PhotoEditStore;
import cc.huevia.album.PhotoLiveProject;
import cc.huevia.album.PhotoLiveProjectStore;
import cc.huevia.album.PhotoProjectPresetStore;
import cc.huevia.album.PhotoSaveTarget;
import cc.huevia.album.SharedProjectPhoto;
import cc.huevia.library.PresetLibrary;
import cc.huevia.library.SharedJson;
import java.io.File;
import java.io.IOException;
import java.io.InterruptedIOException;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.StandardCopyOption;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.function.BooleanSupplier;

/** Original project catalogs/journals; platform renderers produce immutable saved versions. */
public final class SharedProjects {
    private final SharedRuntime runtime;
    private final File root;
    private final PhotoLiveProjectStore projects;
    private final SharedEdits edits;
    private final SharedLiveIngest live;
    private final Map<String,PhotoProjectPresetStore> stores=new LinkedHashMap<>();
    private final Map<String,Lease> leases=new LinkedHashMap<>();
    private static final class Lease {
        final String owner,token;
        final PhotoEditStore.Draft draft;
        Lease(String owner,PhotoEditStore.Draft draft){this.owner=owner;this.draft=draft;token=UUID.randomUUID().toString();}
    }
    public SharedProjects(SharedRuntime runtime)throws IOException {
        this.runtime=runtime;root=runtime.root();
        projects=new PhotoLiveProjectStore(directory("photo-live-projects"),directory("originals"));
        edits=new SharedEdits(root,new PresetLibrary(root));
        live=new SharedLiveIngest(root);
    }
    private File directory(String relative)throws IOException{
        File file=new File(root,relative),canonical=file.getCanonicalFile();
        if(!file.equals(canonical)||!canonical.toPath().startsWith(root.toPath()))throw new IOException("项目资料目录无效。");
        for(File part=file;part!=null&&!part.equals(root);part=part.getParentFile())if(Files.isSymbolicLink(part.toPath()))throw new IOException("项目资料目录无效。");
        if(!file.isDirectory()&&!file.mkdirs())throw new IOException("无法创建项目资料目录。");
        return file;
    }
    private PhotoProjectPresetStore store(String owner)throws IOException{
        PhotoProjectPresetStore found=stores.get(owner);
        if(found==null){found=new PhotoProjectPresetStore(directory("shared-project-presets/"+PhotoEditStore.hash(owner.getBytes(StandardCharsets.UTF_8))));stores.put(owner,found);}
        return found;
    }
    public synchronized Map<String,Object> request(String operation,Map<String,Object> payload,BooleanSupplier cancel)throws IOException{
        String owner=SharedRuntime.text(payload,"owner",64);runtime.guardOwner(owner);check(cancel);
        PhotoProjectPresetStore store=store(owner);
        if(operation.equals("project.list")){
            List<Object> rows=new ArrayList<>();for(PhotoLiveProject project:projects.list())rows.add(summary(project,store));
            return SharedRuntime.map("items",rows);
        }
        if(operation.equals("project.create"))return summary(projects.create(SharedRuntime.text(payload,"name",240)),store);
        String id=SharedRuntime.text(payload,"projectId",36);PhotoLiveProject project=projects.get(id);
        if(operation.startsWith("project.live."))return live(owner,id,operation,payload,cancel);
        if(operation.equals("project.rename"))return summary(projects.rename(id,SharedRuntime.text(payload,"name",240)),store);
        if(operation.equals("project.open"))return open(project,store);
        if(operation.equals("project.setPreset")){
            String preset=SharedRuntime.text(payload,"presetId",64),name="";
            if(!preset.isEmpty()){
                byte[] bytes=runtime.preset(preset);new PhotoEditStore.Draft("0".repeat(64),bytes,"项目预设",100,false).profile();
                Map<String,Object> listed=SharedJson.object(runtime.request("library.list","{}"));
                for(Object row:(List<?>)listed.get("items")){Map<String,Object> record=SharedRuntime.object(row);if(preset.equals(record.get("id"))){name=(String)record.get("displayName");break;}}
                if(name.isEmpty())throw new IOException("请选择当前账号可用的本机预设。");
                retainDefault(owner,preset,bytes);
            }
            store.setConfig(id,preset,name);return open(project,store);
        }
        if(operation.equals("project.add")){
            File source=source(SharedRuntime.text(payload,"path",4096));
            projects.record(id,runtime.sourceIdentity(source.getPath(),true),SharedProjectPhoto.completed(source,SharedRuntime.text(payload,"name",240)));
            return open(projects.get(id),store);
        }
        if(operation.equals("project.enqueue")){
            PhotoProjectPresetStore.Config config=store.config(id);
            if(config.presetId.isEmpty())throw new IOException("请先选择项目默认预设。");
            byte[] bytes=defaultBytes(owner,config.presetId);int queued=0;
            for(DownloadedPhoto photo:project.photos){
                check(cancel);File source=source(photo.file().getPath());String identity=runtime.sourceIdentity(source.getPath(),true);
                projects.record(id,identity,photo); // Revalidate the original catalog's frozen file identity.
                edits.retainPreset(owner,new PhotoEditStore.Draft(identity,bytes,config.presetName,100,false));
                PhotoProjectPresetStore.Task task=new PhotoProjectPresetStore.Task(id,identity,config.presetId,config.presetName,source.getName(),photo.filename(),source.length(),"queued","","",System.currentTimeMillis(),PhotoSaveTarget.APP_ONLY);
                store.queue(task);queued++;
            }
            Map<String,Object> result=open(project,store);result.put("considered",queued);return result;
        }
        if(operation.equals("project.retry")){
            // The bridge serializes this after a preceding renderer returns.
            // Explicit retry can retire an interrupted page's in-memory lease.
            leases.entrySet().removeIf(active->active.getKey().startsWith(id+":")&&active.getValue().owner.equals(owner));
            for(PhotoProjectPresetStore.Task task:store.tasks(id))if(task.status.equals("error")||task.status.equals("processing"))store.update(task.withStatus("queued","",""));
            return open(project,store);
        }
        String key=SharedRuntime.text(payload,"key",180);PhotoProjectPresetStore.Task task=find(store,id,key);
        if(operation.equals("project.result")){
            if(!task.status.equals("saved"))throw new IOException("这张照片的项目效果尚未保存。");
            return version(owner,versionId(task),cancel);
        }
        if(operation.equals("project.begin")){
            if(task.status.equals("saved"))return SharedRuntime.map("done",true,"task",task(task));
            if(!task.status.equals("queued"))throw new IOException("请重试未完成照片后再继续处理。");
            try{
            File source=source(new File(root,"originals/"+task.sourceFileName).getPath());
            if(source.length()!=task.sourceBytes||!runtime.sourceIdentity(source.getPath(),true).equals(task.identity))throw new IOException("项目原图已变化，未套用预设。");
            boolean present=false;for(DownloadedPhoto photo:project.photos)if(photo.file().equals(source))present=true;
            if(!present)throw new IOException("照片已不在当前项目中。");
            Map<String,Object> recipe=SharedRuntime.map("schema",1,"presetId",task.presetId,"strength",100);
            PhotoEditStore.Draft frozen=edits.snapshot(source,owner,SharedJson.encode(recipe),value->false);
            Lease lease=new Lease(owner,frozen);store.update(task.withStatus("processing","",""));leases.put(key,lease);
            return SharedRuntime.map("lease",lease.token,"path",source.getPath(),"sourceSha",frozen.sourceSha,"recipe",SharedEdits.recipe(frozen));
            }catch(IOException failure){store.update(task.withStatus("error","",failure.getMessage()==null?"项目照片未能准备。":failure.getMessage()));throw failure;}
        }
        if(operation.equals("project.finish")){
            String version=SharedRuntime.text(payload,"versionId",64);
            if(task.status.equals("saved")){
                if(!versionId(task).equals(version))throw new IOException("已保存的项目成品不能被替换。");
                version(owner,version,cancel);return open(project,store);
            }
            Lease lease=lease(owner,key,payload);
            Map<String,Object> saved=version(owner,version,cancel);
            if(!lease.draft.sourceSha.equals(saved.get("sourceSha"))||!lease.draft.identity().equals(saved.get("draftIdentity")))throw new IOException("成品与项目的原图或预设快照不符。");
            // This journal is separate from the legacy batch renderer's directory:
            // its filename token points to the shared immutable-version catalog.
            store.update(task.withStatus("saved",version+".version",""));leases.remove(key);return open(project,store);
        }
        if(operation.equals("project.fail")){
            if(task.status.equals("saved"))return open(project,store);
            lease(owner,key,payload);String error=SharedRuntime.text(payload,"error",2048);
            store.update(task.withStatus("error","",error.isEmpty()?"处理已停止，原图仍保留。":error));leases.remove(key);return open(project,store);
        }
        throw new IOException("未知的拍摄项目操作。");
    }
    private File source(String path)throws IOException{
        File source=runtime.privateFile(path);
        if(!source.getParentFile().equals(new File(root,"originals").getCanonicalFile()))throw new IOException("请选择应用相册中已保存的 JPEG 原图。");
        return source;
    }
    private Map<String,Object> live(String owner,String id,String operation,Map<String,Object> payload,BooleanSupplier cancel)throws IOException{
        Map<String,Object> result=live.request(operation,owner,id,payload,cancel,new SharedLiveIngest.Project(){
            public Map<String,Object> preset()throws IOException{
                PhotoProjectPresetStore.Config config=store(owner).config(id);
                if(!config.presetId.isEmpty())defaultBytes(owner,config.presetId);
                return SharedRuntime.map("presetId",config.presetId,"presetName",config.presetName);
            }
            public void validate(Map<String,Object> item,Map<String,Object> receipt)throws IOException{liveSource(item,receipt);}
            public String apply(Map<String,Object> item,Map<String,Object> receipt)throws IOException{
                File source=liveSource(item,receipt);String identity=runtime.sourceIdentity(source.getPath(),true);
                DownloadedPhoto association=null;
                for(DownloadedPhoto existing:projects.get(id).photos)if(existing.file().equals(source)){association=existing;break;}
                projects.record(id,identity,association==null?SharedProjectPhoto.completed(source,(String)item.get("name")):association);
                String preset=(String)item.get("presetId"),name=(String)item.get("presetName");
                if(preset.isEmpty())return ""; // Original-first receive never requires an effect task.
                // A second camera object with identical immutable source bytes is
                // the same project original. Keep its first queued/saved snapshot.
                for(PhotoProjectPresetStore.Task existing:store(owner).tasks(id))if(existing.identity.equals(identity))return existing.key();
                byte[] bytes=defaultBytes(owner,preset);
                edits.retainPreset(owner,new PhotoEditStore.Draft(identity,bytes,name,100,false));
                PhotoProjectPresetStore.Task task=new PhotoProjectPresetStore.Task(id,identity,preset,name,source.getName(),(String)item.get("name"),source.length(),"queued","","",System.currentTimeMillis(),PhotoSaveTarget.APP_ONLY);
                return store(owner).queue(task).key();
            }
        });
        int queued=0;for(PhotoProjectPresetStore.Task task:store(owner).tasks(id))if(task.status.equals("queued")||task.status.equals("processing"))queued++;
        result.put("queuedCount",queued);return result;
    }
    private File liveSource(Map<String,Object> item,Map<String,Object> receipt)throws IOException{
        String sha=SharedRuntime.text(receipt,"sha256",64);if(!sha.matches("[0-9a-f]{64}"))throw new IOException("相机原文件校验无效。");
        String path=SharedRuntime.text(receipt,"path",4096);
        if(path.isEmpty()){
            if(!(sha+".jpg").equals(SharedRuntime.text(receipt,"sourceFileName",80)))throw new IOException("自动收片原文件记录无效。");
            path=new File(root,"originals/"+sha+".jpg").getPath();
        }
        File source=source(path);
        if(!source.getName().equals(sha+".jpg")||!(item.get("bytes") instanceof Number)||source.length()!=((Number)item.get("bytes")).longValue()||!runtime.sourceIdentity(source.getPath(),true).equals(sha))throw new IOException("自动收片原文件已变化，未加入项目。");
        SharedProjectPhoto.completed(source,(String)item.get("name"));return source;
    }
    private File defaultFile(String owner,String id)throws IOException{
        if(!id.matches("[0-9a-f]{64}"))throw new IOException("项目预设快照身份无效。");
        File directory=directory("shared-project-presets/"+PhotoEditStore.hash(owner.getBytes(StandardCharsets.UTF_8))+"/presets");
        File file=new File(directory,id+".bin");
        if(Files.isSymbolicLink(file.toPath())||!file.equals(file.getCanonicalFile()))throw new IOException("项目预设快照路径无效。");
        return file;
    }
    private void retainDefault(String owner,String id,byte[] bytes)throws IOException{
        File target=defaultFile(owner,id);
        if(target.isFile()){defaultBytes(owner,id);return;}
        File temporary=File.createTempFile("preset-",".part",target.getParentFile());
        try{
            try(FileOutputStream output=new FileOutputStream(temporary)){output.write(bytes);output.getFD().sync();}
            Files.move(temporary.toPath(),target.toPath(),StandardCopyOption.ATOMIC_MOVE);
        }finally{Files.deleteIfExists(temporary.toPath());}
    }
    private byte[] defaultBytes(String owner,String id)throws IOException{
        File file=defaultFile(owner,id);
        if(!file.isFile()||file.length()<8||file.length()>1024*1024)throw new IOException("项目预设快照缺失，请重新选择默认预设。");
        byte[] bytes=Files.readAllBytes(file.toPath());
        if(!PhotoEditStore.hash(bytes).equals(id))throw new IOException("项目预设快照校验失败，未套用照片。");
        new PhotoEditStore.Draft("0".repeat(64),bytes,"项目预设",100,false).profile();return bytes;
    }
    private Lease lease(String owner,String key,Map<String,Object> payload)throws IOException{
        Lease lease=leases.get(key);
        if(lease==null||!lease.owner.equals(owner)||!lease.token.equals(SharedRuntime.text(payload,"lease",36)))throw new IOException("项目任务已变化，请刷新处理记录。");
        return lease;
    }
    private static PhotoProjectPresetStore.Task find(PhotoProjectPresetStore store,String projectId,String key)throws IOException{
        for(PhotoProjectPresetStore.Task task:store.tasks(projectId))if(task.key().equals(key))return task;
        throw new IOException("项目处理记录不存在。");
    }
    private Map<String,Object> version(String owner,String id,BooleanSupplier cancel)throws IOException{return SharedJson.object(runtime.request("version.open",SharedJson.encode(SharedRuntime.map("owner",owner,"id",id)),cancel,value->{}));}
    private static String versionId(PhotoProjectPresetStore.Task task)throws IOException{
        if(!task.resultFileName.matches("[0-9a-f]{64}\\.version"))throw new IOException("项目成品记录无效。");
        return task.resultFileName.substring(0,64);
    }
    private static void check(BooleanSupplier cancel)throws IOException{if(cancel.getAsBoolean())throw new InterruptedIOException("项目操作已停止。");}
    private static Map<String,Object> task(PhotoProjectPresetStore.Task task){return SharedRuntime.map("key",task.key(),"identity",task.identity,"presetId",task.presetId,"presetName",task.presetName,"name",task.sourceDisplayName,"status",task.status,"error",task.error,"updatedAt",task.updatedAt);}
    private static Map<String,Object> summary(PhotoLiveProject project,PhotoProjectPresetStore store){
        PhotoProjectPresetStore.Config config=store.config(project.id);int queued=0,failed=0,saved=0;
        for(PhotoProjectPresetStore.Task task:store.tasks(project.id)){if(task.status.equals("saved"))saved++;else if(task.status.equals("error"))failed++;else queued++;}
        return SharedRuntime.map("id",project.id,"name",project.name,"createdAt",project.createdAt,"photoCount",project.photoCount,"totalBytes",project.totalBytes,"presetId",config.presetId,"presetName",config.presetName,"queued",queued,"failed",failed,"saved",saved);
    }
    private static Map<String,Object> open(PhotoLiveProject project,PhotoProjectPresetStore store){
        Map<String,Object> result=summary(project,store);List<Object> photos=new ArrayList<>(),tasks=new ArrayList<>();
        for(DownloadedPhoto photo:project.photos)photos.add(SharedRuntime.map("path",photo.file().getPath(),"name",photo.filename(),"bytes",photo.byteSize()));
        for(PhotoProjectPresetStore.Task task:store.tasks(project.id))tasks.add(task(task));
        result.put("photos",photos);result.put("tasks",tasks);return result;
    }
}
