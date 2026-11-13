package cc.huevia.shared;

import cc.huevia.account.*;
import cc.huevia.community.*;
import cc.huevia.library.*;
import cc.huevia.album.PhotoEditStore;
import cc.huevia.album.PhotoRecipeStore;
import cc.huevia.album.PhotoStarStore;
import cc.huevia.album.PhotoAdjustmentCopy;
import cc.huevia.ncp.PhotoBorder;
import cc.huevia.ncp.PhotoGeometry;
import cc.huevia.ncp.PhotoBodyShape;
import cc.huevia.ncp.PhotoLocalEdits;
import cc.huevia.ncp.AdjustmentRegion;
import java.io.*;
import java.nio.file.*;
import java.util.*;
import java.util.function.*;
import java.nio.charset.StandardCharsets;

/** Serial worker entry point shared by Android and the translated Apple implementation. */
public final class SharedRuntime {
    private final File root;
    private final PresetLibrary library;
    private final OnlinePresetRepository online;
    private final EditorPresetCatalog editorCatalog;
    private final AccountRepository accounts;
    private final CommunityRepository community;
    private final OnlinePresetSearch search;
    private final String installationId;
    private final SharedEdits edits;
    private SharedPersonal personal;
    private final SharedVersions versions;
    private final SharedCommunityLinks discussionLinks;
    private final SharedSubmissions submissions;
    private final SharedProfile profile;
    private SharedProjects projectRuntime;
    private String storageWarning="";
    private PhotoAdjustmentCopy.Receipt copyReceipt;
    private String copyReceiptId="",copyReceiptOwner="";
    public SharedRuntime(String directory, AccountRepository.Store store, AccountRepository.Transport transport)throws IOException {
        this(directory,store,transport,"");
    }
    public SharedRuntime(String directory, AccountRepository.Store store, AccountRepository.Transport transport,String installation)throws IOException {
        root=new File(directory).getCanonicalFile();
        if(!root.isDirectory()&&!root.mkdirs())throw new IOException("无法打开应用资料目录。");
        library=new PresetLibrary(root);
        edits=new SharedEdits(root,library);
        versions=new SharedVersions(root);
        discussionLinks=new SharedCommunityLinks(root);
        online=new OnlinePresetRepository(root,library);
        online.useManagedEndpoint(OnlinePresetRepository.MANAGED_CATALOG_URL);
        editorCatalog=new EditorPresetCatalog(root,library);
        search=new OnlinePresetSearch(online);
        installationId=installationId(root,installation);
        accounts=new AccountRepository(store,transport);
        community=new CommunityRepository(accounts);
        community.setInstallationId(installationId);
        submissions=new SharedSubmissions(root,SharedSubmissions.network(accounts,community,installationId),this::guardOwner);
        profile=new SharedProfile(root,accounts,installationId);
        try{accounts.restore();}catch(IOException failure){storageWarning=failure.getMessage();}
        personal=new SharedPersonal(root,library,accounts,installationId);
    }
    public File root(){return root;}
    public synchronized void guardProfile(String owner,String updatedAt)throws IOException{profile.guard(owner,updatedAt);}
    public synchronized String prepareAvatar(String owner,String updatedAt,byte[] jpeg)throws IOException{return SharedJson.encode(profile.prepare(owner,updatedAt,jpeg));}
    public byte[] preset(String id)throws IOException{if(id==null||id.isEmpty())return new byte[0];requirePreset(id);return library.readPreset(id);}
    /** Online effects use checked recipe bytes without adding to the personal library. */
    public synchronized byte[] showcasePreset(String id,String descriptor)throws IOException{
        if(descriptor==null||descriptor.isEmpty())return preset(id);
        OnlinePreset selected=OnlinePreset.fromMap(SharedJson.object(descriptor));
        if(!selected.sha256.equals(id))throw new IOException("预设预览身份已变化。");
        return editorCatalog.read(selected);
    }
    public synchronized String request(String operation,String json)throws IOException {
        return request(operation,json,()->false,value->{});
    }
    public synchronized String request(String operation,String json,BooleanSupplier cancel,DoubleConsumer progress)throws IOException {
        Map<String,Object> p=SharedJson.object(json);Object result;
        if(operation.startsWith("downloads."))return SharedJson.encode(SharedDownloads.request(this,operation,p,cancel));
        if(operation.startsWith("album."))return cc.huevia.album.SharedAlbumOperations.request(this,operation,json,cancel);
        if(operation.startsWith("legacy.")){
            Map<String,Object> value=new SharedLegacyMigration(this).request(operation,p,cancel,progress);
            if(operation.equals("legacy.commit")||operation.equals("legacy.rollback")){projectRuntime=null;library.refresh();personal=new SharedPersonal(root,library,accounts,installationId);}
            return SharedJson.encode(value);
        }
        if(operation.startsWith("project.")){
            if(projectRuntime==null)projectRuntime=new SharedProjects(this);
            return SharedJson.encode(projectRuntime.request(operation,p,cancel));
        }
        if(operation.startsWith("personal."))return SharedJson.encode(personal.request(operation,p,cancel,progress));
        if(operation.startsWith("submission."))return SharedJson.encode(submissions.request(operation,p,cancel));
        if(operation.startsWith("recipe."))return SharedJson.encode(recipes(operation,p));
        if(operation.equals("photo.copy")||operation.equals("photo.copyUndo"))return SharedJson.encode(copyAdjustments(operation,p,cancel,progress));
        if(operation.startsWith("version."))return SharedJson.encode(versions(operation,p,cancel));
        if(operation.startsWith("local."))return SharedJson.encode(SharedLocalEdits.request(operation,p,cancel));
        if(operation.startsWith("toneCards.")){
            String owner=text(p,"owner",64);guardOwner(owner);
            return SharedJson.encode(SharedPortraitToneCards.request(root,owner,operation,p,cancel));
        }
        if(operation.equals("export.describe")) {
            if(cancel.getAsBoolean())throw new InterruptedIOException("导出设置已取消。");
            PhotoEditStore.Draft frozen=reviewView(text(p,"path",32768),text(p,"owner",64),SharedJson.encode(object(p.get("recipe"))));
            return SharedJson.encode(SharedExportSpecs.describe(frozen,p,cancel));
        }
        switch(operation){
            case "editor.catalog":{
                OnlinePresetRepository.CatalogResult catalog=editorCatalog.load();
                List<Object> rows=new ArrayList<>();for(OnlinePreset r:catalog.presets)rows.add(onlineMap(r));
                result=map("items",rows,"status",catalog.status,"message",catalog.message);break;
            }
            case "editor.prepare":{
                String owner=text(p,"owner",64);guardOwner(owner);
                File source=privateFile(text(p,"path",4096));
                OnlinePreset selected=OnlinePreset.fromMap(object(p.get("preset")));
                byte[] bytes=editorCatalog.read(selected);
                if(cancel.getAsBoolean())throw new InterruptedIOException("滤镜准备已取消。");
                guardOwner(owner);
                // The existing account/photo-scoped history keeps immutable bytes
                // for undo, reopening and export, including offline use.
                edits.retainPreset(owner,new PhotoEditStore.Draft(edits.sourceIdentity(source,false),bytes,selected.name,100,false));
                result=map("id",selected.sha256,"name",selected.name);break;
            }
            case "source.inspect":result=inspectOriginal(p,cancel);break;
            case "ui.preferences.get":result=new SharedUiState(root).read();break;
            case "ui.preferences.set":result=new SharedUiState(root).update(p);break;
            case "core.schema":return CoreEngine.schema();
            case "photo.stars":result=map("keys",new ArrayList<>(new PhotoStarStore(root).snapshot()));break;
            case "photo.star":{
                File source=privateFile(text(p,"path",4096));
                if(!source.toPath().startsWith(new File(root,"originals").getCanonicalFile().toPath()))throw new IOException("只能标记原图库中的照片。");
                if(!(p.get("starred") instanceof Boolean))throw new IOException("星标状态无效。");
                PhotoStarStore stars=new PhotoStarStore(root);stars.setStarred(PhotoStarStore.localKey(source),(Boolean)p.get("starred"));
                result=map("keys",new ArrayList<>(stars.snapshot()));break;
            }
            case "draft.load":{
                String owner=text(p,"owner",64);guardOwner(owner);File source=privateFile(text(p,"path",4096));
                PhotoEditStore.Draft draft=edits.load(source,owner);
                result=map("sourceSha",edits.sourceIdentity(source,false),"recipe",draft==null?null:SharedEdits.recipe(draft));break;
            }
            case "draft.save":{
                PhotoEditStore.Draft draft=freezeEdit(text(p,"path",4096),text(p,"owner",64),SharedJson.encode(object(p.get("recipe"))));
                result=map("sourceSha",draft.sourceSha,"recipe",SharedEdits.recipe(draft));break;
            }
            case "library.list":{
                library.refresh();personal.restoreMetadata();List<Object> rows=new ArrayList<>();Map<String,String> links=discussionLinks.optionalSnapshot();
                for(PresetRecord r:library.list())if(personal.visible(r.id)){
                    Map<String,Object> value=r.toMap();if(links.containsKey(r.sha256))value.put("discussionId",links.get(r.sha256));rows.add(value);
                }
                List<String> diagnostics=new ArrayList<>(library.diagnostics());
                try{new SharedPresetPins(root).order(SharedPersonal.currentOwner(accounts),rows);}
                catch(IOException unavailable){diagnostics.add("置顶排序暂不可用，已按原顺序显示预设。");}
                result=map("items",rows,"diagnostics",diagnostics);break;
            }
            case "library.import":{
                guardOwner(text(p,"owner",64));
                File file=privateFile(text(p,"path",4096));long length=file.length();
                if(length<1||length>1024*1024)throw new IOException("预设文件大小无效。");
                PresetLibrary.AddResult added=library.importFile(text(p,"name",240),Files.readAllBytes(file.toPath()));
                personal.added(added.record);
                result=map("record",added.record.toMap(),"added",added.added);break;
            }
            case "library.pin":{
                String owner=text(p,"owner",64);guardOwner(owner);String id=text(p,"id",64);requirePreset(id);
                if(!(p.get("pinned") instanceof Boolean))throw new IOException("请选择置顶状态。");
                new SharedPresetPins(root).set(owner,id,Boolean.TRUE.equals(p.get("pinned")));result=map("id",id,"pinned",p.get("pinned"));break;
            }
            case "library.remove":{
                guardOwner(text(p,"owner",64));String id=text(p,"id",64);requirePreset(id);
                PresetLibrary.RemoveResult removed=library.remove(id);personal.deleted(id);List<String> warnings=new ArrayList<>(removed.cleanupWarnings);
                try{new SharedPresetPins(root).set(text(p,"owner",64),id,false);}catch(IOException unavailable){warnings.add("预设已删除，置顶记录暂未清理。");}
                result=map("warnings",warnings);break;
            }
            case "library.category":{
                guardOwner(text(p,"owner",64));String id=text(p,"id",64);requirePreset(id);PresetRecord changed=library.setCategory(id,text(p,"category",100));personal.added(changed);result=changed.toMap();break;
            }
            case "library.export":{
                String id=text(p,"id",64);byte[] bytes=preset(id);PresetRecord record=library.findBySha256(id);
                File dir=new File(root,"shared-exports");if(!dir.isDirectory()&&!dir.mkdirs())throw new IOException("无法创建分享文件。");
                String name=record.originalFileName.replaceAll("[^\\p{L}\\p{N}._-]","_");
                if(name.isEmpty())name=id+"."+record.fileFormat.toLowerCase(Locale.ROOT);
                File output=new File(dir,id+"-"+name);Files.write(output.toPath(),bytes);
                result=map("path",output.getPath(),"name",name);break;
            }
            case "library.inspect":result=SharedJson.object(CoreEngine.inspectPreset(preset(text(p,"id",64))));break;
            case "online.page":{
                OnlinePresetRepository.PageResult page=online.fetchPage(integer(p,"page",1),integer(p,"pageSize",24),text(p,"category",100),text(p,"fileFormat",8));
                List<Object> rows=new ArrayList<>();for(OnlinePreset r:page.presets)rows.add(onlineMap(r));
                result=map("items",rows,"total",page.total,"hasMore",page.hasMore,"page",page.page,"categories",page.categories);break;
            }
            case "online.search":{
                OnlinePresetSearch.Snapshot snapshot=search.load(Boolean.TRUE.equals(p.get("refresh")));
                String category=text(p,"category",100);if(category.isEmpty())category=PresetCategories.ALL;
                else if(PresetCategories.UNCATEGORIZED.equals(category))category="";
                List<Object> rows=new ArrayList<>();for(OnlinePreset r:snapshot.matching(text(p,"query",256),category))rows.add(onlineMap(r));
                result=map("items",rows,"categories",new ArrayList<>(snapshot.categories),"fromCache",snapshot.fromCache,"available",snapshot.available,"message",snapshot.message);break;
            }
            case "online.download":{
                guardOwner(text(p,"owner",64));
                OnlinePreset selected=OnlinePreset.fromMap(object(p.get("preset")));
                PresetLibrary.AddResult added=online.download(selected,null);
                personal.added(added.record);
                Map<String,Object> record=added.record.toMap();String warning="";
                try{CommunityRepository.id(selected.id);record.put("discussionId",selected.id);discussionLinks.remember(added.record.sha256,selected.id);}
                catch(IOException associationFailure){warning="预设已下载，评论关联暂未保存，可在详情中重试。";}
                result=map("record",record,"added",added.added,"discussionWarning",warning);break;
            }
            case "account.current":{
                Object current=session(accounts.cachedSession());Map<String,Object> value=current==null?new LinkedHashMap<>():object(current);
                value.put("storageWarning",storageWarning);value.put("logoutPending",accounts.isLogoutPending());result=value;break;
            }
            case "account.challenge":result=accounts.challenge(installationId);break;
            case "account.login":if(p.containsKey("owner"))guardOwner(text(p,"owner",64));result=authenticated(accounts.login(text(p,"username",32),text(p,"password",256)));break;
            case "account.register":result=authenticated(accounts.register(text(p,"username",32),text(p,"password",256),text(p,"challengeId",128),text(p,"challengeAnswer",128),installationId));break;
            case "account.qq":if(p.containsKey("owner"))guardOwner(text(p,"owner",64));result=authenticated(accounts.loginWithQq(text(p,"accessToken",4096),text(p,"challengeId",128),text(p,"challengeAnswer",128),installationId));break;
            case "account.refresh":if(p.containsKey("owner"))guardOwner(text(p,"owner",64));result=authenticated(accounts.refresh());break;
            case "account.avatarCommit":result=authenticated(profile.commit(text(p,"owner",64),text(p,"receipt",64),text(p,"sha256",64)));break;
            case "account.avatarReset":result=authenticated(profile.reset(text(p,"owner",64),text(p,"updatedAt",64)));break;
            case "account.avatarDiscard":profile.discardForOwner(text(p,"owner",64),text(p,"receipt",64));result=map("discarded",true);break;
            case "account.logout":
                if(p.containsKey("owner")&&!accounts.isLogoutPending())guardOwner(text(p,"owner",64));
                try{accounts.logout();storageWarning="";}catch(IOException failure){storageWarning=failure.getMessage();throw failure;}finally{profile.clear();}
                result=map("loggedOut",true);break;
            case "community.get":
                result=Boolean.TRUE.equals(p.get("login"))
                    ?community.getForOwner(text(p,"path",2048),text(p,"ownerId",64))
                    :community.get(text(p,"path",2048),false);break;
            case "community.write":result=community.writeForOwner(text(p,"method",6),text(p,"path",2048),object(p.get("body")),text(p,"ownerId",64));break;
            case "community.discussion":{
                guardOwner(text(p,"owner",64));String id=text(p,"id",64);requirePreset(id);PresetRecord record=library.findBySha256(id);
                String known=discussionLinks.snapshot().get(record.sha256);
                if(known!=null){result=map("status","linked","id",known);break;}
                if(!"online".equals(record.source)){result=map("status","missing","message","这份预设暂未关联在线讨论。");break;}
                OnlinePresetSearch.Snapshot catalog=search.load(Boolean.TRUE.equals(p.get("refresh")));
                if(!catalog.available)throw new IOException(catalog.message.isEmpty()?"暂时无法加载评论关联，请稍后重试。":catalog.message);
                result=SharedCommunityLinks.match(record.sha256,catalog.presets);
                if("linked".equals(object(result).get("status"))){
                    try{discussionLinks.remember(record.sha256,(String)object(result).get("id"));}
                    catch(IOException saveFailure){object(result).put("message","评论已关联，本机保存暂未完成。");}
                }
                break;
            }
            default:throw new IOException("未知的应用操作："+operation);
        }
        return SharedJson.encode(result);
    }
    private Map<String,Object> recipes(String operation,Map<String,Object> p)throws IOException{
        String owner=text(p,"owner",64);guardOwner(owner);
        PhotoRecipeStore store=new PhotoRecipeStore(root,owner);
        switch(operation){
            case "recipe.list":{
                List<Object> items=new ArrayList<>();for(PhotoRecipeStore.Recipe recipe:store.list())items.add(recipeInfo(recipe));
                return map("items",items);
            }
            case "recipe.create":{
                PhotoEditStore.Draft draft=freezeEdit(text(p,"path",4096),owner,SharedJson.encode(object(p.get("recipe"))));
                return recipeInfo(store.create(text(p,"name",160),draft));
            }
            case "recipe.rename":return recipeInfo(store.rename(text(p,"id",32),text(p,"name",160)));
            case "recipe.delete":store.delete(text(p,"id",32));return map("deleted",true);
            case "recipe.apply":{
                PhotoRecipeStore.Recipe saved=store.read(text(p,"id",32));
                PhotoEditStore.Draft current=freezeEdit(text(p,"path",4096),owner,SharedJson.encode(object(p.get("recipe"))));
                PhotoEditStore.Draft next=new PhotoEditStore.Draft(current.sourceSha,saved.presetBytes(),saved.presetName,saved.strength,saved.adjustments,current.geometry,current.border,current.localEdits,false);
                edits.retainPreset(owner,next);
                if(!new PhotoEditStore(root,owner).replace(current.sourceSha,current,next))throw new IOException("照片设置已变化，请重新应用配方。");
                return map("recipe",SharedEdits.recipe(next),"name",saved.name);
            }
            default:throw new IOException("未知的配方操作。");
        }
    }
    private static Map<String,Object> recipeInfo(PhotoRecipeStore.Recipe recipe){return map("id",recipe.id,"name",recipe.name,"createdAt",recipe.createdAt,"summary",recipe.summary());}
    private Map<String,Object> versions(String operation,Map<String,Object> p,BooleanSupplier cancel)throws IOException{
        String owner=text(p,"owner",64);guardOwner(owner);
        switch(operation){
            case "version.list":{
                String path=text(p,"path",4096),sha=path.isEmpty()?"":sourceIdentity(path,false);
                return map("items",versions.list(owner,sha,cancel));
            }
            case "version.open":return versions.open(owner,text(p,"id",64),cancel);
            case "version.recipe":{
                PhotoEditStore.Draft saved=versions.draft(owner,text(p,"id",64),cancel);
                edits.retainPreset(owner,saved);return map("sourceSha",saved.sourceSha,"recipe",SharedEdits.recipe(saved));
            }
            case "version.delete":versions.delete(owner,text(p,"id",64),cancel);return map("deleted",true);
            default:throw new IOException("未知的成品版本操作。");
        }
    }
    public synchronized String commitVersion(String path,String owner,PhotoEditStore.Draft frozen,String rendered,String details,BooleanSupplier cancel)throws IOException{
        guardOwner(owner);validateSource(path,frozen.sourceSha);
        return SharedJson.encode(versions.commit(privateFile(path),owner,frozen,privateFile(rendered),SharedJson.object(details),cancel));
    }
    private Map<String,Object> copyAdjustments(String operation,Map<String,Object> p,BooleanSupplier cancel,DoubleConsumer progress)throws IOException{
        String owner=text(p,"owner",64);guardOwner(owner);
        BooleanSupplier allowed=()->!cancel.getAsBoolean()&&owner.equals(SharedPersonal.currentOwner(accounts));
        PhotoEditStore store=new PhotoEditStore(root,owner);
        if(operation.equals("photo.copyUndo")){
            if(copyReceipt==null||!owner.equals(copyReceiptOwner)||!copyReceiptId.equals(text(p,"receipt",36)))throw new IOException("此撤销记录已失效，请核对目标照片当前设置。");
            int changed=copyReceipt.changed(),restored=copyReceipt.undo(store,allowed);
            copyReceipt=null;copyReceiptId="";copyReceiptOwner="";
            return map("restored",restored,"changed",changed,"keptNewer",changed-restored);
        }
        if(!(p.get("basic") instanceof Boolean)||!(p.get("curves") instanceof Boolean)||!(p.get("colour") instanceof Boolean))throw new IOException("请选择要复制的调节范围。");
        if(!(p.get("paths") instanceof List)||((List<?>)p.get("paths")).isEmpty()||((List<?>)p.get("paths")).size()>100)throw new IOException("请选择 1–100 张目标照片。");
        boolean basic=(Boolean)p.get("basic"),curves=(Boolean)p.get("curves"),colour=(Boolean)p.get("colour");
        if(!basic&&!curves&&!colour)throw new IOException("请至少选择一类调节。");
        File source=originalPhoto(text(p,"path",4096));
        PhotoEditStore.Draft frozen=freezeEdit(source.getPath(),owner,SharedJson.encode(object(p.get("recipe"))));
        List<PhotoAdjustmentCopy.Target> targets=new ArrayList<>();
        for(Object value:(List<?>)p.get("paths")){
            if(!allowed.getAsBoolean())throw new IOException("账号或任务已变化，复制已取消。");
            if(!(value instanceof String)||((String)value).length()>4096)throw new IOException("目标照片路径无效。");
            File target=originalPhoto((String)value);String sha=edits.sourceIdentity(target,false);
            if(sha.equals(frozen.sourceSha))throw new IOException("源照片与目标包含同一原图，请取消重复选择。");
            PhotoEditStore.Draft expected=store.read(sha);targets.add(new PhotoAdjustmentCopy.Target(sha,expected,expected));
            progress.accept(.2*targets.size()/((List<?>)p.get("paths")).size());
        }
        PhotoAdjustmentCopy.Receipt receipt=PhotoAdjustmentCopy.apply(store,targets,frozen.adjustments,basic,curves,colour,allowed);
        // Only the latest receipt is retained; the original class compares each
        // complete draft before undo, preserving later independent edits.
        copyReceipt=receipt;copyReceiptId=UUID.randomUUID().toString();copyReceiptOwner=owner;progress.accept(1);
        return map("changed",receipt.changed(),"skipped",receipt.skipped,"receipt",copyReceiptId);
    }
    private File originalPhoto(String path)throws IOException{
        File file=privateFile(path);
        if(!file.toPath().startsWith(new File(root,"originals").getCanonicalFile().toPath()))throw new IOException("只能选择应用原图库中的照片。");
        return file;
    }
    private Map<String,Object> inspectOriginal(Map<String,Object> p,BooleanSupplier cancel)throws IOException {
        if(cancel.getAsBoolean())throw new InterruptedIOException("原始文件检查已取消。");
        String owner=text(p,"owner",64);guardOwner(owner);File source=privateFile(text(p,"path",4096));
        File directory=new File(root,"originals").getCanonicalFile();
        if(Files.isSymbolicLink(new File(root,"originals").toPath())||!directory.equals(source.getParentFile())||!source.getName().matches("[0-9a-f]{64}\\.(jpg|jpeg|png|nef|nrw|dng|arw|cr2|cr3|raf|rw2|orf|pef|srw)"))throw new IOException("只能导出原图库中的完整照片。");
        if(source.length()<1||source.length()>512L*1024*1024)throw new IOException("原始文件大小无效。");
        String sha=sourceIdentity(source.getPath(),true),expected=text(p,"expectedSourceSha",64);
        if(!source.getName().startsWith(sha)||(!expected.isEmpty()&&!expected.equals(sha)))throw new IOException("原始文件已变化，未导出。");
        if(cancel.getAsBoolean())throw new InterruptedIOException("原始文件检查已取消。");guardOwner(owner);
        return map("path",source.getPath(),"sourceSha",sha,"bytes",source.length(),"format",source.getName().substring(65).toUpperCase(Locale.ROOT));
    }
    /** Native publication entry points, never a rendered version or editor write. */
    public synchronized String prepareOriginalPublication(String json,BooleanSupplier cancel)throws IOException {
        Map<String,Object> p=SharedJson.object(json);String owner=text(p,"owner",64),expected=text(p,"expectedSourceSha",64);
        if(!expected.matches("[0-9a-f]{64}"))throw new IOException("请重新打开照片后保存原始文件。");
        Map<String,Object> inspected=inspectOriginal(p,cancel);
        Map<String,Object> prepared=SharedOriginalPublication.prepare(root,owner,inspected,text(p,"operationId",32),cancel);
        guardOwner(owner);return SharedJson.encode(prepared);
    }
    public synchronized void releaseOriginalPublication(String json)throws IOException {
        Map<String,Object> p=SharedJson.object(json);String owner=text(p,"owner",64);guardOwner(owner);
        if(!(p.get("bytes") instanceof Number))throw new IOException("原始文件保存大小无效。");
        SharedOriginalPublication.release(root,owner,text(p,"operationId",32),text(p,"sha256",64),((Number)p.get("bytes")).longValue());
    }
    public File privateFile(String path)throws IOException {
        File original=new File(path),file=original.getCanonicalFile();
        Path candidate=original.toPath(),canonical=file.toPath(),base=root.toPath();
        if(candidate==null||canonical==null||base==null)throw new IOException("文件系统路径接口不可用。");
        if(candidate.getFileSystem()==null||candidate.getFileSystem().provider()==null)throw new IOException("文件系统提供器不可用。");
        if(!canonical.startsWith(base)||Files.isSymbolicLink(candidate)||!file.isFile())throw new IOException("文件不在应用资料目录内。");
        return file;
    }
    public synchronized String sourceIdentity(String path,boolean force)throws IOException{return edits.sourceIdentity(privateFile(path),force);}
    public synchronized PhotoEditStore.Draft originalView(String path,String owner)throws IOException{
        guardOwner(owner);return new PhotoEditStore.Draft(sourceIdentity(path,false),null,"无滤镜",0,false);
    }
    public synchronized PhotoEditStore.Draft reviewView(String path,String owner,String json)throws IOException{
        guardOwner(owner);return edits.snapshot(privateFile(path),owner,json,personal::visible);
    }
    public synchronized PhotoEditStore.Draft localView(String path,String owner,String json)throws IOException{
        guardOwner(owner);
        PhotoEditStore.Draft frozen=edits.snapshot(privateFile(path),owner,json,personal::visible);
        PhotoLocalEdits local=frozen.localEdits;
        if(!local.portrait.bodyShape.isNeutral())local=local.withPortrait(local.portrait.withBodyShape(PhotoBodyShape.NONE));
        // Original local tools paint in the EXIF-oriented source before crop,
        // border and global body shaping. The stored recipe is left intact.
        return new PhotoEditStore.Draft(frozen.sourceSha,frozen.presetBytes(),frozen.name,frozen.strength,frozen.adjustments,PhotoGeometry.NONE,PhotoBorder.NONE,local,false);
    }
    public synchronized AdjustmentRegion cleanupRegion(String path,String owner,String json,String regionId)throws IOException{
        guardOwner(owner);
        PhotoEditStore.Draft frozen=edits.snapshot(privateFile(path),owner,json,personal::visible);
        if(regionId==null||regionId.isEmpty())return null;
        for(AdjustmentRegion region:frozen.localEdits.regions())if(region.id.equals(regionId))return region;
        throw new IOException("局部区域已变化，请重新选择。");
    }
    public synchronized PhotoEditStore.Draft freezeEdit(String path,String owner,String json)throws IOException{guardOwner(owner);return edits.freeze(privateFile(path),owner,json,personal::visible);}
    public synchronized void guardOwner(String owner)throws IOException{
        String current=SharedPersonal.currentOwner(accounts);
        if(owner==null||!owner.equals(current))throw new IOException("账号状态已改变，请重新打开照片。");
    }
    private void requirePreset(String id)throws IOException{if(!personal.visible(id)||library.findBySha256(id)==null)throw new IOException("预设已移除或不属于当前账号。");}
    public synchronized void validateSource(String path,String expected)throws IOException{if(!expected.equals(sourceIdentity(path,true)))throw new IOException("照片原文件发生变化，未保存效果图。");}
    public synchronized void markEditExported(String owner,PhotoEditStore.Draft frozen)throws IOException{guardOwner(owner);edits.markExported(owner,frozen);}
    public static String editJson(PhotoEditStore.Draft frozen)throws IOException{return SharedJson.encode(SharedEdits.recipe(frozen));}
    public static Map<String,Object> map(Object... values){Map<String,Object> m=new LinkedHashMap<>();for(int i=0;i<values.length;i+=2)m.put((String)values[i],values[i+1]);return m;}
    @SuppressWarnings("unchecked") public static Map<String,Object> object(Object value)throws IOException{if(!(value instanceof Map))throw new IOException("操作数据格式无效。");return (Map<String,Object>)value;}
    public static String text(Map<String,Object> m,String key,int max)throws IOException{Object v=m.get(key);if(v==null)return "";if(!(v instanceof String)||((String)v).length()>max)throw new IOException("操作文字超出范围："+key);return (String)v;}
    public static int integer(Map<String,Object> m,String key,int fallback)throws IOException{Object v=m.get(key);if(v==null)return fallback;if(!(v instanceof Number)||((Number)v).doubleValue()!=((Number)v).intValue())throw new IOException("操作数字无效："+key);return ((Number)v).intValue();}
    private static Object session(AccountRepository.Session session){
        if(session==null)return null;AccountRepository.User u=session.user;
        return map("user",map("id",u.id,"username",u.username,"nickname",u.nickname,"avatarUrl",u.avatarUrl,"avatarSource",u.avatarSource,"provider",u.provider,"updatedAt",u.updatedAt,"createdAt",u.createdAt,"lastLoginAt",u.lastLoginAt,"loginCount",u.loginCount,"status",u.status),"expiresAt",session.expiresAt,"verified",session.verified);
    }
    private Object authenticated(AccountRepository.Session value){storageWarning="";return session(value);}
    private static Object onlineMap(OnlinePreset r){return map("id",r.id,"name",r.name,"description",r.description,"fileUrl",r.fileUrl,"sha256",r.sha256,"byteLength",r.byteLength,"previewUrl",r.previewUrl,"compatibleModels",r.compatibleModels,"category",r.category,"authorName",r.authorName,"source",r.source,"fileFormat",r.fileFormat);}
    private static String installationId(File root,String preferred)throws IOException{
        if(preferred!=null&&preferred.matches("(?i)[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}"))return preferred;
        File target=new File(root,"account-installation.txt");
        if(target.isFile()&&target.length()<=128){String value=new String(Files.readAllBytes(target.toPath()),StandardCharsets.UTF_8).trim();if(value.matches("(?i)[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}"))return value;}
        String value=UUID.randomUUID().toString();File temporary=File.createTempFile("installation-",".part",root);
        try{Files.write(temporary.toPath(),value.getBytes(StandardCharsets.UTF_8));Files.move(temporary.toPath(),target.toPath(),StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING);}finally{Files.deleteIfExists(temporary.toPath());}
        return value;
    }
}
