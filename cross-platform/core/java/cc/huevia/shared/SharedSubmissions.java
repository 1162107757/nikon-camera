package cc.huevia.shared;

import cc.huevia.account.*;
import cc.huevia.community.*;
import cc.huevia.ncp.NcpFile;
import cc.huevia.album.PhotoEditStore;
import java.io.*;
import java.nio.ByteBuffer;
import java.nio.charset.*;
import java.nio.file.Files;
import java.net.URLEncoder;
import java.util.*;
import java.util.function.BooleanSupplier;
import static cc.huevia.community.CommunityRepository.*;

/** Account-bound, durable submission editing. Uncertain writes retain their exact retry keys. */
public final class SharedSubmissions {
    public interface Api {
        Map<String,Object> get(String owner,String path)throws IOException;
        Map<String,Object> write(String owner,String method,String path,Map<String,Object> body)throws IOException;
        Map<String,Object> upload(String owner,String kind,String name,byte[] bytes,String mime)throws IOException;
    }
    public interface OwnerGuard { void check(String owner)throws IOException; }
    private final File root;
    private final Api api;
    private final OwnerGuard guard;
    public SharedSubmissions(File root,Api api,OwnerGuard guard){this.root=root;this.api=api;this.guard=guard;}
    public static Api network(AccountRepository accounts,CommunityRepository community,String installation){
        return new Api(){
            public Map<String,Object> get(String owner,String path)throws IOException{return community.getForOwner(path,owner);}
            public Map<String,Object> write(String owner,String method,String path,Map<String,Object> body)throws IOException{return community.writeForOwner(method,path,body,owner);}
            public Map<String,Object> upload(String owner,String kind,String name,byte[] bytes,String mime)throws IOException{
                CommunityHttpTransport transport=new CommunityHttpTransport(mime);transport.setInstallationId(installation);
                String path="/community/uploads?kind="+kind+"&filename="+URLEncoder.encode(name,"UTF-8");
                return decode(accounts.requestWithSession(transport,"POST",path,bytes,true,owner));
            }
        };
    }
    public synchronized Map<String,Object> request(String operation,Map<String,Object> p,BooleanSupplier cancel)throws IOException{
        String owner=SharedRuntime.text(p,"owner",64);id(owner);guard.check(owner);
        String slot=SharedRuntime.text(p,"slot",64);if(slot.isEmpty())slot="new";if(!slot.equals("new"))id(slot);
        SubmissionDraftStore store=store(owner,slot);Map<String,Object> draft=store.load(owner);
        if(operation.equals("submission.load")){
            if(slot.equals("new")){
                if(!text(draft,"id").isEmpty()&&!uncertain(draft)&&Arrays.asList("pending","pending_review","approved","published").contains(text(draft,"status"))){
                    Map<String,Object> archived=new LinkedHashMap<>(draft);archived.remove("filePath");archived.remove("previewPath");
                    store(owner,id(text(draft,"id"))).save(owner,archived);draft=SubmissionDraftStore.fresh();
                }
            }else{
                Map<String,Object> recent=store(owner,"new").load(owner);
                if(slot.equals(text(recent,"id"))&&(uncertain(recent)||Boolean.TRUE.equals(recent.get("localDirty")))){
                    slot="new";store=store(owner,slot);draft=recent;
                }else if(!uncertain(draft)&&!Boolean.TRUE.equals(draft.get("localDirty"))){
                    try{Map<String,Object> remote=api.get(owner,"/community/submissions/"+slot);guard.check(owner);
                        Map<String,Object> item=object(remote.get("submission"));mergeServer(draft,item,slot);draft.put("localDirty",false);
                    }catch(IOException failure){if(text(draft,"id").isEmpty())throw failure;return envelope(slot,draft,failure.getMessage());}
                }
            }
            checkpoint(store,owner,draft);return envelope(slot,draft,"");
        }
        if(operation.equals("submission.reload")){
            if(uncertain(draft)||!Boolean.TRUE.equals(p.get("discardLocal")))throw new IOException("请先确认放弃本机修改，未确认的网络操作必须先重试。");
            String serverId=id(text(draft,"id"));Map<String,Object> remote=api.get(owner,"/community/submissions/"+serverId);
            Map<String,Object> fresh=SubmissionDraftStore.fresh();mergeServer(fresh,object(remote.get("submission")),serverId);fresh.put("localDirty",false);
            checkpoint(store,owner,fresh);draft=fresh;
        }else if(operation.equals("submission.persist")){
            if(!uncertain(draft)&&!locked(draft)){edit(draft,SharedRuntime.object(p.get("draft")));checkpoint(store,owner,draft);}
        }else if(operation.equals("submission.attach")){
            requireEditable(draft);String kind=SharedRuntime.text(p,"kind",16);
            if(!kind.equals("ncp")&&!kind.equals("preview"))throw new IOException("投稿文件类型无效。");
            String prefix=kind.equals("ncp")?"file":"preview";
            File staged=null;
            if(Boolean.TRUE.equals(p.get("remove"))){if(!kind.equals("preview"))throw new IOException("请重新选择 NCP 文件。");draft.remove("previewPath");draft.remove("previewName");draft.remove("previewAssetId");draft.remove("preview");}
            else{
                String path=SharedRuntime.text(p,"path",4096),name=SharedRuntime.text(p,"name",1024);
                File incoming=new File(path);File allowed=directory(directory(root,"submission-incoming"),owner);
                if(!incoming.getCanonicalFile().getParentFile().equals(allowed.getCanonicalFile())||Files.isSymbolicLink(incoming.toPath())||Files.isSymbolicLink(allowed.toPath()))throw new IOException("投稿文件不属于当前账号。");
                byte[] bytes=readBounded(incoming,kind.equals("ncp")?1024*1024:4*1024*1024);
                String sha=PhotoEditStore.hashFile(incoming);if(!incoming.getName().startsWith(sha+"."))throw new IOException("所选文件校验失败，请重新选择。");
                if(name.isEmpty()||name.contains("/")||name.contains("\\")||name.codePoints().anyMatch(Character::isISOControl))throw new IOException("文件名称无效。");
                if(kind.equals("ncp")){if(!name.toLowerCase(Locale.ROOT).endsWith(".ncp"))throw new IOException("投稿仅支持 NCP 文件。");NcpFile.validate(bytes);}
                else{mime(bytes);MediaValidation.validate(bytes);}
                guard.check(owner);File owned=store.storeFile(owner,kind,bytes);draft.put(prefix+"Path",owned.getPath());draft.put(prefix+"Name",name);draft.remove(prefix+"AssetId");draft.remove(prefix);
                staged=incoming;
            }
            changed(draft);checkpoint(store,owner,draft);
            if(staged!=null)try{Files.deleteIfExists(staged.toPath());}catch(IOException optionalCleanup){/* The durable draft owns a verified copy. */}
        }else if(operation.equals("submission.save")){
            if(!uncertain(draft)){requireEditable(draft);edit(draft,SharedRuntime.object(p.get("draft")));}
            draft=save(store,owner,draft,Boolean.TRUE.equals(p.get("submit")),cancel);
        }else throw new IOException("未知投稿操作。");
        return envelope(slot,draft,"");
    }
    private Map<String,Object> save(SubmissionDraftStore store,String owner,Map<String,Object> draft,boolean submit,BooleanSupplier cancel)throws IOException{
        if(Boolean.TRUE.equals(draft.get("savePending")))submit=Boolean.TRUE.equals(draft.get("saveIntentSubmit"));
        if(Boolean.TRUE.equals(draft.get("submitPending"))&&!submit)throw new IOException("上次提交结果尚未确认，请重试提交以恢复结果。");
        if(!Boolean.TRUE.equals(draft.get("rightsConfirmed")))throw new IOException("请先确认你拥有预设和效果图的公开分享权利。");
        if(text(draft,"name").trim().isEmpty())throw new IOException("请填写预设名称。");
        if(text(draft,"fileAssetId").isEmpty()&&text(draft,"filePath").isEmpty())throw new IOException("请先选择 NCP 文件。");
        check(cancel);guard.check(owner);
        if(!Boolean.TRUE.equals(draft.get("submitPending"))){
            for(String kind:new String[]{"ncp","preview"}){
                String prefix=kind.equals("ncp")?"file":"preview",path=text(draft,prefix+"Path");
                if(text(draft,prefix+"AssetId").isEmpty()&&!path.isEmpty()){
                    requireOwnedFile(store,owner,path);byte[] bytes=store.readFile(path,kind.equals("ncp")?1024*1024:4*1024*1024);
                    if(kind.equals("ncp"))NcpFile.validate(bytes);else MediaValidation.validate(bytes);
                    check(cancel);Map<String,Object> asset=object(api.upload(owner,kind,text(draft,prefix+"Name"),bytes,kind.equals("ncp")?"application/octet-stream":mime(bytes)).get("asset"));
                    String received=assetId(text(asset,"id"),kind);if(!received.equals(kind+"-"+PhotoEditStore.hash(bytes)))throw new IOException("上传附件校验不一致，请重试。");
                    guard.check(owner);draft.put(prefix+"AssetId",received);draft.put(prefix,asset);checkpoint(store,owner,draft);
                }
            }
            Map<String,Object> body=body("name",text(draft,"name").trim(),"description",text(draft,"description").trim(),"category",text(draft,"category").trim(),
                "compatibleModels",draft.getOrDefault("compatibleModels",new ArrayList<>()),"fileAssetId",assetId(text(draft,"fileAssetId"),"ncp"),
                "previewAssetId",text(draft,"previewAssetId").isEmpty()?null:assetId(text(draft,"previewAssetId"),"preview"),"rightsConfirmed",true);
            String serverId=text(draft,"id");boolean creating=serverId.isEmpty();body.put("idempotencyKey",key(draft,creating?"createKey":"saveKey"));
            if(!creating)body.put("expectedRevision",number(draft,"revision",1));
            // Freeze before the first byte can leave this device. A lost response must not accept edits.
            draft.put("savePending",true);draft.put("saveIntentSubmit",submit);checkpoint(store,owner,draft);check(cancel);
            Map<String,Object> saved=object(write(store,owner,draft,creating?"POST":"PUT","/community/submissions"+(creating?"":"/"+id(serverId)),body).get("submission"));
            mergeServer(draft,saved,serverId);draft.put("savePending",false);draft.put("localDirty",false);draft.put("saveKey",UUID.randomUUID().toString());
            submit=Boolean.TRUE.equals(draft.get("saveIntentSubmit"));draft.put("submitPending",submit);checkpoint(store,owner,draft);
        }
        if(submit){
            check(cancel);Map<String,Object> response=write(store,owner,draft,"POST","/community/submissions/"+id(text(draft,"id"))+"/submit",body("expectedRevision",number(draft,"revision",1),"idempotencyKey",key(draft,"submitKey")));
            mergeServer(draft,object(response.get("submission")),text(draft,"id"));draft.put("submitPending",false);draft.put("submitKey",UUID.randomUUID().toString());checkpoint(store,owner,draft);
        }
        return draft;
    }
    private Map<String,Object> write(SubmissionDraftStore store,String owner,Map<String,Object> draft,String method,String path,Map<String,Object> body)throws IOException{
        try{return api.write(owner,method,path,body);}
        catch(CommunityException rejection){
            // These responses explicitly reject the command before it is applied. Keep editable
            // local changes; a revision conflict can then load the server copy after confirmation.
            if(Arrays.asList(400,401,403,404,409,422).contains(rejection.status)){
                draft.put("savePending",false);draft.put("submitPending",false);draft.put("localDirty",true);checkpoint(store,owner,draft);
            }
            throw rejection;
        }
    }
    private void checkpoint(SubmissionDraftStore store,String owner,Map<String,Object> draft)throws IOException{guard.check(owner);store.save(owner,draft);}
    private SubmissionDraftStore store(String owner,String slot)throws IOException{
        File folder=directory(directory(directory(root,"shared-submissions"),owner),slot);return new SubmissionDraftStore(folder);
    }
    private static File directory(File parent,String name)throws IOException{
        File folder=new File(parent,name);if(Files.isSymbolicLink(folder.toPath())||!folder.getCanonicalFile().getParentFile().equals(parent.getCanonicalFile())||!folder.isDirectory()&&!folder.mkdirs())throw new IOException("无法打开本机投稿草稿。");return folder;
    }
    private static void requireOwnedFile(SubmissionDraftStore store,String owner,String path)throws IOException{
        if(!new File(path).getName().startsWith(owner+"-"))throw new IOException("投稿附件不属于当前账号。");
        // readFile also checks the exact canonical draft directory.
    }
    private static boolean uncertain(Map<String,Object> d){return Boolean.TRUE.equals(d.get("savePending"))||Boolean.TRUE.equals(d.get("submitPending"));}
    private static boolean locked(Map<String,Object> d){return Arrays.asList("pending","pending_review").contains(text(d,"status"));}
    private static void requireEditable(Map<String,Object> d)throws IOException{if(uncertain(d))throw new IOException("上次保存结果尚未确认，请先重试保存或提交。");if(locked(d))throw new IOException("投稿正在审核，暂时不能修改。");}
    private static void changed(Map<String,Object> d){d.put("localDirty",true);d.put("saveKey",UUID.randomUUID().toString());d.put("submitKey",UUID.randomUUID().toString());}
    private static void edit(Map<String,Object> d,Map<String,Object> incoming)throws IOException{
        boolean change=false;for(String field:new String[]{"name","description","category"}){
            String value=SharedRuntime.text(incoming,field,field.equals("name")?160:field.equals("description")?2000:24);if(!value.equals(text(d,field))){d.put(field,value);change=true;}
        }
        Object raw=incoming.getOrDefault("compatibleModels",new ArrayList<>());if(!(raw instanceof List))throw new IOException("相机型号格式无效。");
        List<String> models=new ArrayList<>();int length=0;for(Object model:(List<?>)raw){if(!(model instanceof String))throw new IOException("相机型号格式无效。");String v=((String)model).trim();length+=v.length()+1;if(length>257)throw new IOException("相机型号最多 256 字。");if(!v.isEmpty()&&!models.contains(v))models.add(v);}
        if(!models.equals(d.getOrDefault("compatibleModels",new ArrayList<>()))){d.put("compatibleModels",models);change=true;}
        boolean rights=Boolean.TRUE.equals(incoming.get("rightsConfirmed"));if(rights!=Boolean.TRUE.equals(d.get("rightsConfirmed"))){d.put("rightsConfirmed",rights);change=true;}if(change)changed(d);
    }
    private static void mergeServer(Map<String,Object> draft,Map<String,Object> server,String expected)throws IOException{
        String serverId=id(text(server,"id"));if(!expected.isEmpty()&&!expected.equals(serverId))throw new IOException("服务返回了不同的投稿，草稿已保留。");
        for(String field:new String[]{"file","preview"})if(server.get(field)!=null&&!(server.get(field) instanceof Map))throw new IOException("投稿附件响应不完整。");
        long revision=number(server,"revision",0);if(revision<1||revision>Integer.MAX_VALUE||!Arrays.asList("draft","pending","pending_review","approved","published","rejected","unpublished","withdrawn").contains(text(server,"status")))throw new IOException("投稿状态响应不完整，草稿已保留。");
        for(String field:new String[]{"id","revision","name","description","category","compatibleModels","rightsConfirmed","status","reason","reviewReason","fileAssetId","previewAssetId","file","preview","createdAt","updatedAt"})if(server.containsKey(field))draft.put(field,server.get(field));
    }
    private static Map<String,Object> envelope(String slot,Map<String,Object> draft,String warning){return body("slot",slot,"draft",draft,"warning",warning);}
    private static String key(Map<String,Object> d,String key)throws IOException{String value=text(d,key);if(value.isEmpty()){value=UUID.randomUUID().toString();d.put(key,value);}return id(value);}
    private static String assetId(String value,String kind)throws IOException{if(!value.matches(kind+"-[a-f0-9]{64}"))throw new IOException("投稿附件标识无效，请重新选择文件。");return value;}
    private static byte[] readBounded(File file,int max)throws IOException{
        if(!file.isFile()||file.length()<1||file.length()>max)throw new IOException("所选文件大小超出限制。");
        try(InputStream input=new FileInputStream(file);ByteArrayOutputStream output=new ByteArrayOutputStream()){
            byte[] buffer=new byte[16384];int n;while((n=input.read(buffer))!=-1){if(n>max-output.size())throw new IOException("所选文件过大。");output.write(buffer,0,n);}return output.toByteArray();
        }
    }
    private static String mime(byte[] b)throws IOException{
        if(b.length>=8&&b[0]==(byte)137&&b[1]==80&&b[2]==78&&b[3]==71&&b[4]==13&&b[5]==10&&b[6]==26&&b[7]==10)return "image/png";
        if(b.length>=3&&b[0]==(byte)255&&b[1]==(byte)216&&b[2]==(byte)255)return "image/jpeg";
        if(b.length>=12&&b[0]=='R'&&b[1]=='I'&&b[2]=='F'&&b[3]=='F'&&b[8]=='W'&&b[9]=='E'&&b[10]=='B'&&b[11]=='P')return "image/webp";
        throw new IOException("效果图仅支持 JPEG、PNG 或 WebP 照片。");
    }
    private static void check(BooleanSupplier cancel)throws InterruptedIOException{if(Thread.currentThread().isInterrupted()||cancel!=null&&cancel.getAsBoolean())throw new InterruptedIOException("操作已取消，草稿已保留。");}
    private static Map<String,Object> decode(AccountRepository.Response response)throws IOException{
        Map<String,Object> value;try{if(response.body.length<1||response.body.length>512*1024)throw new IOException();
            value=object(AccountJson.parse(StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(response.body)).toString()));
        }catch(Exception problem){throw new IOException("上传响应不完整，请重试，草稿已保留。");}
        if(response.status>=200&&response.status<300)return value;
        String message=response.status==401?"登录已失效，请重新登录。":response.status==429?"操作较频繁，请稍后再试。":response.status>=500?"服务暂不可用，草稿已保留。":"上传未完成，请重试。";
        throw new IOException(message);
    }
}
