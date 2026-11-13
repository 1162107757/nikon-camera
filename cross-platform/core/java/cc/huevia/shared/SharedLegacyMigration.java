package cc.huevia.shared;

import cc.huevia.album.*;
import cc.huevia.library.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.*;
import java.util.*;
import java.util.function.*;

/** Checkable, additive migration with an on-disk journal and guarded rollback. No session import. */
public final class SharedLegacyMigration {
    private final SharedRuntime runtime;
    private final File root,transactions;
    public SharedLegacyMigration(SharedRuntime runtime)throws IOException{
        this.runtime=runtime;root=runtime.root();transactions=owned(root,"legacy-migrations");mkdir(transactions);
    }
    public Map<String,Object> request(String operation,Map<String,Object> payload,BooleanSupplier cancel,DoubleConsumer progress)throws IOException{
        String owner=SharedRuntime.text(payload,"owner",64);runtime.guardOwner(owner);
        switch(operation){
            case "legacy.status":return status();
            case "legacy.inspect":return inspect(payload,owner,cancel,progress);
            case "legacy.commit":return commit(payload,owner,cancel,progress);
            case "legacy.rollback":return rollback(payload,owner);
            case "legacy.discard":{
                File transaction=transaction(SharedRuntime.text(payload,"transaction",36));
                if(owned(transaction,"journal.json").exists())throw new IOException("已经提交的迁入请使用撤回操作。");
                Map<String,Object> plan=read(owned(transaction,"plan.json"));if(!owner.equals(plan.get("owner")))throw new IOException("账号已改变，请重新打开迁入页面。");
                LegacyArchive.removeTree(transaction);return SharedRuntime.map("discarded",true);
            }
            case "legacy.export":{
                File output=owned(root,"shared-exports/legacy-"+UUID.randomUUID()+".zip");mkdir(output.getParentFile());
                Map<String,Object> session=SharedJson.object(runtime.request("account.current","{}"));Map<String,Object> account=session.get("user") instanceof Map?SharedRuntime.object(session.get("user")):new LinkedHashMap<>();
                LegacyArchive.exportShared(root,owned(root,"originals"),owner,account,output,cancel);
                return SharedRuntime.map("path",output.getPath(),"name",output.getName(),"sha256",hashFile(output),"bytes",output.length());
            }
            default:throw new IOException("未知的旧版资料迁入操作。");
        }
    }
    private Map<String,Object> status()throws IOException{
        List<Object> rows=new ArrayList<>();File[] children=transactions.listFiles();if(children==null)throw new IOException("无法读取迁入记录。");
        for(File child:children)if(child.isDirectory()&&child.getName().matches("[0-9a-f-]{36}")){
            File journal=owned(child,"journal.json");if(journal.isFile()){Map<String,Object> value=read(journal);rows.add(SharedRuntime.map("transaction",child.getName(),"status",value.get("status"),"createdAt",value.get("createdAt"),"account",value.get("account")));}
        }
        return SharedRuntime.map("items",rows,"accountPolicy","不迁入密码、QQ token、旧会话或 Keychain；账号专属草稿需重新登录同一账号后关联。");
    }
    private Map<String,Object> inspect(Map<String,Object> payload,String owner,BooleanSupplier cancel,DoubleConsumer progress)throws IOException{
        LegacyArchive.check(cancel);File selected=new File(SharedRuntime.text(payload,"path",32768)),input;
        if(Boolean.TRUE.equals(payload.get("iosPresets"))){
            File canonical=selected.getCanonicalFile();if(!canonical.toPath().startsWith(root.toPath())||Files.isSymbolicLink(selected.toPath()))throw new IOException("请选择系统导入的旧版预设文件夹。");
            input=owned(root,root.toPath().relativize(canonical.toPath()).toString().replace('\\','/'));
        }else input=runtime.privateFile(selected.getPath());
        File incoming=owned(root,"legacy-incoming");if(!input.toPath().startsWith(incoming.toPath())||input.equals(incoming))throw new IOException("请选择通过系统文件选择器导入的迁移文件。");
        String id=UUID.randomUUID().toString();File transaction=owned(transactions,id);mkdir(transaction);
        File archive=input;
        try{
            if(Boolean.TRUE.equals(payload.get("iosPresets"))){if(!input.isDirectory())throw new IOException("请选择旧版 iOS Presets 文件夹。");archive=owned(transaction,"ios-presets.zip");LegacyArchive.exportIosPresets(input,archive,cancel);}
            Map<String,Object> manifest=LegacyArchive.unpack(archive,owned(transaction,"source"),cancel);
            String exportId=SharedRuntime.text(manifest,"id",36);if(owned(root,"legacy-receipts/"+exportId+".json").exists())throw new IOException("此导出包已经迁入，请先核对现有资料或撤回上次迁入。");
            Map<String,Object> account=SharedRuntime.object(manifest.get("account"));String previousOwner=SharedRuntime.text(account,"id",64);
            Map<String,Object> current=SharedJson.object(runtime.request("account.current","{}"));
            boolean accountMatch=owner.equals(previousOwner)&&(owner.isEmpty()||Boolean.TRUE.equals(current.get("verified")));
            File prepared=owned(transaction,"prepared");mkdir(prepared);
            PresetLibrary library=new PresetLibrary(prepared);Set<String> presetIds=new HashSet<>();
            for(Object value:LegacyArchive.rows(manifest,"presets")){
                LegacyArchive.check(cancel);Map<String,Object> row=SharedRuntime.object(value);File bytes=payloadFile(transaction,row);
                if(bytes.length()>1024*1024)throw new IOException("迁入预设超过大小限制。");
                PresetLibrary.AddResult added=library.importFile(LegacyArchive.safeName(SharedRuntime.text(row,"name",240)),Files.readAllBytes(bytes.toPath()));
                library.updatePersonalMetadata(added.record.id,SharedRuntime.map("displayName",SharedRuntime.text(row,"displayName",240),"originalFileName",added.record.originalFileName,"description",SharedRuntime.text(row,"description",12000),"category",SharedRuntime.text(row,"category",100)));
                presetIds.add(added.record.id);
            }
            List<Object> photos=new ArrayList<>();Map<String,Map<String,Object>> bySha=new LinkedHashMap<>();
            for(Object value:LegacyArchive.rows(manifest,"photos")){
                LegacyArchive.check(cancel);Map<String,Object> row=SharedRuntime.object(value);String sha=SharedRuntime.text(row,"sha256",64),ext=SharedRuntime.text(row,"extension",8);
                if(!LegacyArchive.photoExtension(ext)||bySha.containsKey(sha))throw new IOException("迁入照片类型或身份重复。");
                String relative="originals/"+sha+"."+ext;File target=owned(prepared,relative);mkdir(target.getParentFile());Files.copy(payloadFile(transaction,row).toPath(),target.toPath());
                String name=LegacyArchive.safeName(SharedRuntime.text(row,"name",240));Map<String,Object> photo=SharedRuntime.map("sha256",sha,"path",target.getPath(),"relative",relative,"name",name,"bytes",target.length());photos.add(photo);bySha.put(sha,photo);
            }
            int draftCount=0;
            for(Object value:LegacyArchive.rows(manifest,"drafts")){
                LegacyArchive.check(cancel);Map<String,Object> row=SharedRuntime.object(value);String sha=SharedRuntime.text(row,"sourceSha",64);if(!bySha.containsKey(sha))throw new IOException("旧版草稿缺少对应原片。");
                File sourceRoot=owned(transaction,"draft-source"),encoded=owned(sourceRoot,"photo-edit-drafts/"+hash(previousOwner.getBytes(StandardCharsets.UTF_8))+"/"+sha+".draft");mkdir(encoded.getParentFile());Files.copy(payloadFile(transaction,row).toPath(),encoded.toPath(),StandardCopyOption.REPLACE_EXISTING);
                PhotoEditStore.Draft draft=new PhotoEditStore(sourceRoot,previousOwner).read(sha);if(draft==null)throw new IOException("旧版草稿无法读取。");
                if(accountMatch)new PhotoEditStore(prepared,owner).save(draft);draftCount++;
            }
            File projectFiles=owned(prepared,"photo-live-projects"),originals=owned(prepared,"originals");mkdir(originals);
            PhotoLiveProjectStore projects=new PhotoLiveProjectStore(projectFiles,originals);
            String defaultsRelative="shared-project-presets/"+hash(owner.getBytes(StandardCharsets.UTF_8));
            if(accountMatch)LegacyArchive.copyTree(owned(root,defaultsRelative),owned(prepared,defaultsRelative));
            PhotoProjectPresetStore defaults=accountMatch?new PhotoProjectPresetStore(owned(prepared,defaultsRelative)):null;
            List<Object> projectMap=new ArrayList<>();
            for(Object value:LegacyArchive.rows(manifest,"projects")){
                LegacyArchive.check(cancel);Map<String,Object> row=SharedRuntime.object(value);PhotoLiveProject project=projects.create(SharedRuntime.text(row,"name",240));
                for(Object identity:LegacyArchive.rows(row,"photos")){if(!(identity instanceof String)||!bySha.containsKey(identity))throw new IOException("项目包含未迁入的原图。");Map<String,Object> photo=bySha.get(identity);projects.record(project.id,(String)identity,SharedProjectPhoto.completed(new File((String)photo.get("path")),(String)photo.get("name")));}
                String preset=SharedRuntime.text(row,"presetId",64);if(accountMatch&&!preset.isEmpty()){if(!presetIds.contains(preset))throw new IOException("项目默认预设未包含在迁入包内。");defaults.setConfig(project.id,preset,SharedRuntime.text(row,"presetName",240));}
                projectMap.add(SharedRuntime.map("oldId",SharedRuntime.text(row,"id",36),"id",project.id,"name",project.name));
            }
            Map<String,Object> plan=SharedRuntime.map("transaction",id,"owner",owner,"account",account,"accountMatch",accountMatch,"exportId",exportId,"origin",manifest.get("origin"),"photos",photos,"projects",projectMap,"presets",presetIds.size(),"presetIds",new ArrayList<>(presetIds),"drafts",draftCount,"defaultsRelative",defaultsRelative);
            write(owned(transaction,"plan.json"),plan);progress.accept(1);
            return plan;
        }catch(IOException|RuntimeException failure){LegacyArchive.removeTree(transaction);throw failure;}
    }
    private Map<String,Object> commit(Map<String,Object> payload,String owner,BooleanSupplier cancel,DoubleConsumer progress)throws IOException{
        String id=SharedRuntime.text(payload,"transaction",36);File transaction=transaction(id);Map<String,Object> plan=read(owned(transaction,"plan.json"));
        if(!owner.equals(plan.get("owner")))throw new IOException("账号已改变，请重新预检迁入资料。");
        if(owned(transaction,"journal.json").exists())throw new IOException("此迁入任务已提交，请先核对或撤回。");
        boolean include=Boolean.TRUE.equals(payload.get("includeAccountData"));
        if(include&&!Boolean.TRUE.equals(plan.get("accountMatch")))throw new IOException("请先重新登录导出包中的同一账号，再关联专属草稿。");
        File prepared=owned(transaction,"prepared");
        if(include&&!owner.isEmpty()){
            Map<String,Object> current=SharedJson.object(runtime.request("account.current","{}"));if(!Boolean.TRUE.equals(current.get("verified")))throw new IOException("请重新联网登录同一账号后关联资料。");
            LegacyArchive.copyTree(owned(root,"personal-presets.json"),owned(prepared,"personal-presets.json"));
            PresetLibrary staged=new PresetLibrary(prepared),existing=new PresetLibrary(root);PersonalPresetSync personal=new PersonalPresetSync(prepared,staged);
            for(Object raw:LegacyArchive.rows(plan,"presetIds")){if(!(raw instanceof String))throw new IOException("迁入预设清单无效。");PresetRecord record=existing.findBySha256((String)raw);if(record==null)record=staged.findBySha256((String)raw);if(record==null)throw new IOException("迁入预设已改变，请重新预检。");personal.markAdded(owner,record);}
        }
        if(!include){LegacyArchive.removeTree(owned(prepared,"photo-edit-drafts"));LegacyArchive.removeTree(owned(prepared,"shared-project-presets"));}
        Map<String,Map<String,Object>> supplied=new HashMap<>();for(Object raw:LegacyArchive.rows(payload,"photos")){Map<String,Object> row=SharedRuntime.object(raw);supplied.put(SharedRuntime.text(row,"sha256",64),SharedRuntime.object(row.get("info")));}
        List<Object> index=new ArrayList<>();File currentIndex=owned(root,"photos-index.json");
        if(currentIndex.exists()){if(currentIndex.length()>4*1024*1024)throw new IOException("当前照片索引过大，尚未迁入资料。");Object decoded=SharedJson.object("{\"items\":"+new String(Files.readAllBytes(currentIndex.toPath()),StandardCharsets.UTF_8)+"}").get("items");if(!(decoded instanceof List))throw new IOException("当前照片索引无法读取，尚未迁入资料。");index.addAll((List<?>)decoded);}
        Set<String> indexed=new HashSet<>();for(Object raw:index){Map<String,Object> row=SharedRuntime.object(raw);Object name=row.get("path");if(name instanceof String)indexed.add((String)name);}
        for(Object raw:LegacyArchive.rows(plan,"photos")){
            Map<String,Object> row=SharedRuntime.object(raw);String sha=SharedRuntime.text(row,"sha256",64),relative=SharedRuntime.text(row,"relative",160);Map<String,Object> info=supplied.get(sha);
            if(info==null||!(info.get("width") instanceof Number)||!(info.get("height") instanceof Number)||((Number)info.get("width")).intValue()<1||((Number)info.get("height")).intValue()<1)throw new IOException("请先完成每张迁入照片的原生解码检查。");
            if(!indexed.contains(relative)&&!indexed.contains(owned(root,relative).getPath()))index.add(SharedRuntime.map("path",relative,"relative",true,"name",row.get("name"),"info",info));
        }
        writeValue(owned(prepared,"photos-index.json"),index);
        File receipt=owned(prepared,"legacy-receipts/"+plan.get("exportId")+".json");write(receipt,SharedRuntime.map("transaction",id,"account",plan.get("account"),"origin",plan.get("origin"),"importedAt",System.currentTimeMillis()));
        List<Object> mutations=new ArrayList<>();collect(prepared,prepared,mutations);
        List<Object> changes=new ArrayList<>();int preserved=0;
            for(Object raw:mutations){Map<String,Object> row=SharedRuntime.object(raw);String relative=(String)row.get("relative");File live=owned(root,relative);boolean replace=relative.equals("photos-index.json")||relative.equals("personal-presets.json")||relative.startsWith("shared-project-presets/");
            if(live.exists()&&!replace){preserved++;continue;}
            if(live.exists()&&hashFile(live).equals(row.get("after")))continue;
            row.put("existed",live.exists());if(live.exists()){File backup=owned(transaction,"backup/"+relative);mkdir(backup.getParentFile());Files.copy(live.toPath(),backup.toPath());row.put("before",hashFile(live));}changes.add(row);
        }
        Map<String,Object> journal=SharedRuntime.map("status","applying","createdAt",System.currentTimeMillis(),"owner",owner,"account",plan.get("account"),"changes",changes);File journalFile=owned(transaction,"journal.json");write(journalFile,journal);
        try{
            int done=0;for(Object raw:changes){LegacyArchive.check(cancel);Map<String,Object> row=SharedRuntime.object(raw);String relative=(String)row.get("relative");File live=owned(root,relative),source=owned(prepared,relative);mkdir(live.getParentFile());atomicCopy(source,live);progress.accept(++done/(double)Math.max(1,changes.size()));}
            journal.put("status","complete");journal.put("fingerprint",fingerprint());write(journalFile,journal);
        }catch(IOException|RuntimeException failure){restore(transaction,journal,false);throw failure;}
        return SharedRuntime.map("transaction",id,"status","complete","files",changes.size(),"preserved",preserved,"accountAssociated",include,"projects",plan.get("projects"));
    }
    private Map<String,Object> rollback(Map<String,Object> payload,String owner)throws IOException{
        File transaction=transaction(SharedRuntime.text(payload,"transaction",36));Map<String,Object> journal=read(owned(transaction,"journal.json"));
        if(!owner.equals(journal.get("owner")))throw new IOException("请切回迁入时的账号再撤回资料。");
        if("rolledBack".equals(journal.get("status")))return SharedRuntime.map("status","rolledBack");
        if("complete".equals(journal.get("status"))&&!fingerprint().equals(journal.get("fingerprint")))throw new IOException("迁入后资料已被编辑或新增，为保护这些更改，无法自动撤回；请保留原导出包并逐项核对。");
        restore(transaction,journal,true);return SharedRuntime.map("status","rolledBack");
    }
    private void restore(File transaction,Map<String,Object> journal,boolean guarded)throws IOException{
        List<?> changes=LegacyArchive.rows(journal,"changes");
        for(Object raw:changes){Map<String,Object> row=SharedRuntime.object(raw);String relative=(String)row.get("relative");File file=owned(root,relative);if(file.exists()){String actual=hashFile(file);if(!actual.equals(row.get("after"))&&!actual.equals(row.get("before")))throw new IOException("迁入资料已经改变，已停止自动撤回以保护现有文件。");}if(Boolean.TRUE.equals(row.get("existed"))){File backup=owned(transaction,"backup/"+relative);if(!backup.isFile()||!hashFile(backup).equals(row.get("before")))throw new IOException("迁入回滚副本校验失败，未覆盖当前资料。");}}
        List<?> reverse=new ArrayList<>(changes);Collections.reverse(reverse);
        // Free the additive files first, so low-storage failure can still restore small before-images.
        for(Object raw:reverse){Map<String,Object> row=SharedRuntime.object(raw);if(!Boolean.TRUE.equals(row.get("existed")))Files.deleteIfExists(owned(root,(String)row.get("relative")).toPath());}
        for(Object raw:reverse){Map<String,Object> row=SharedRuntime.object(raw);String relative=(String)row.get("relative");File file=owned(root,relative);if(Boolean.TRUE.equals(row.get("existed"))&&(!file.exists()||!hashFile(file).equals(row.get("before"))))atomicCopy(owned(transaction,"backup/"+relative),file);}
        journal.put("status","rolledBack");write(owned(transaction,"journal.json"),journal);
    }
    private String fingerprint()throws IOException{
        List<Object> rows=new ArrayList<>();for(String part:List.of("preset-library","originals","photo-edit-drafts","photo-live-projects","shared-project-presets","personal-presets.json","photos-index.json","legacy-receipts"))collect(root,owned(root,part),rows);
        rows.sort(Comparator.comparing(value->(String)((Map<?,?>)value).get("relative")));return hash(SharedJson.encode(rows).getBytes(StandardCharsets.UTF_8));
    }
    private static void collect(File base,File file,List<Object> rows)throws IOException{
        if(!file.exists())return;if(Files.isSymbolicLink(file.toPath()))throw new IOException("迁入目标不能包含符号链接。");
        if(file.isDirectory()){File[] children=file.listFiles();if(children==null)throw new IOException("无法核对迁入目录。");for(File child:children)collect(base,child,rows);}
        else{if(rows.size()>=LegacyArchive.MAX_ENTRIES)throw new IOException("当前资料过多，无法完成安全回滚清单。");String relative=base.toPath().relativize(file.toPath()).toString().replace('\\','/');rows.add(SharedRuntime.map("relative",relative,"after",hashFile(file)));}
    }
    private static void atomicCopy(File source,File target)throws IOException{File temporary=File.createTempFile("legacy-",".part",target.getParentFile());try{Files.copy(source.toPath(),temporary.toPath(),StandardCopyOption.REPLACE_EXISTING);try(FileOutputStream sync=new FileOutputStream(temporary,true)){sync.getFD().sync();}Files.move(temporary.toPath(),target.toPath(),StandardCopyOption.REPLACE_EXISTING,StandardCopyOption.ATOMIC_MOVE);}finally{Files.deleteIfExists(temporary.toPath());}}
    private File transaction(String id)throws IOException{if(!id.matches("[0-9a-f-]{36}"))throw new IOException("迁入任务身份无效。");File file=owned(transactions,id);if(!file.isDirectory())throw new IOException("迁入任务已不存在。");return file;}
    private static File payloadFile(File transaction,Map<String,Object> row)throws IOException{return owned(owned(transaction,"source"),SharedRuntime.text(row,"entry",160));}
    private static File owned(File base,String relative)throws IOException{if(relative==null||relative.isEmpty()||relative.startsWith("/")||relative.contains("\\")||relative.contains(":"))throw new IOException("迁入资料路径无效。");File target=new File(base,relative);File canonical=target.getCanonicalFile();if(!canonical.toPath().startsWith(base.getCanonicalFile().toPath())||canonical.equals(base.getCanonicalFile()))throw new IOException("迁入路径越界。");for(File item=target;item!=null&&!item.equals(base);item=item.getParentFile())if(Files.isSymbolicLink(item.toPath()))throw new IOException("迁入路径不能包含符号链接。");return canonical;}
    private static void mkdir(File file)throws IOException{if(!file.isDirectory()&&!file.mkdirs())throw new IOException("无法创建迁入资料目录。");}
    private static Map<String,Object> read(File file)throws IOException{if(!file.isFile()||file.length()>32L*1024*1024)throw new IOException("迁入记录无法读取。");return SharedJson.object(new String(Files.readAllBytes(file.toPath()),StandardCharsets.UTF_8));}
    private static void write(File file,Map<String,Object> value)throws IOException{writeValue(file,value);}
    private static void writeValue(File file,Object value)throws IOException{byte[] encoded=SharedJson.encode(value).getBytes(StandardCharsets.UTF_8);if(encoded.length>4*1024*1024)throw new IOException("资料清单过大，请分批迁入。");if(value instanceof Map&&((Map<?,?>)value).get("changes") instanceof List&&((List<?>)((Map<?,?>)value).get("changes")).size()>20000)throw new IOException("迁入变更多于 20000 项，请分批迁入。");mkdir(file.getParentFile());File temporary=File.createTempFile("legacy-json-",".part",file.getParentFile());try{try(FileOutputStream output=new FileOutputStream(temporary)){output.write(encoded);output.getFD().sync();}Files.move(temporary.toPath(),file.toPath(),StandardCopyOption.REPLACE_EXISTING,StandardCopyOption.ATOMIC_MOVE);}finally{Files.deleteIfExists(temporary.toPath());}}
    private static String hash(byte[] bytes){try{byte[] digest=MessageDigest.getInstance("SHA-256").digest(bytes);StringBuilder result=new StringBuilder();for(byte value:digest)result.append(String.format(Locale.ROOT,"%02x",value&255));return result.toString();}catch(NoSuchAlgorithmException impossible){throw new AssertionError(impossible);}}
    private static String hashFile(File file)throws IOException{return PhotoEditStore.hashFile(file);}
}
