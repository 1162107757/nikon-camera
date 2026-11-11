package cc.huevia.shared;

import cc.huevia.account.AccountRepository;
import cc.huevia.album.PhotoEditStore;
import cc.huevia.community.CommunityRepository;
import java.io.*;
import java.nio.file.Files;
import java.util.*;

/** Reviewed avatar bytes stay native and are bound to the exact account profile revision. */
public final class SharedProfile {
    private static final int MAX_DRAFTS=8;
    private final File root;
    private final AccountRepository accounts;
    private final String installation;
    private final LinkedHashMap<String,Draft> drafts=new LinkedHashMap<>();
    private static final class Draft {
        final String owner,updatedAt,sha;final File file;
        Draft(String owner,String updatedAt,String sha,File file){this.owner=owner;this.updatedAt=updatedAt;this.sha=sha;this.file=file;}
    }
    public SharedProfile(File root,AccountRepository accounts,String installation){
        this.root=root;this.accounts=accounts;this.installation=installation;
        cleanAbandoned("profile-pending",true);cleanAbandoned("avatar-incoming",false);
    }
    private void cleanAbandoned(String name,boolean prepared){
        try{
            File base=new File(root,name);
            if(!base.isDirectory()||Files.isSymbolicLink(base.toPath())||!base.getCanonicalFile().getParentFile().equals(root.getCanonicalFile()))return;
            File[] owners=base.listFiles();if(owners==null)return;
            for(File owner:owners){
                if(!owner.isDirectory()||Files.isSymbolicLink(owner.toPath())||!owner.getName().matches("(?i)[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}")||!owner.getCanonicalFile().getParentFile().equals(base.getCanonicalFile()))continue;
                File[] files=owner.listFiles();if(files==null)continue;
                for(File file:files){
                    String leaf=file.getName();boolean owned=prepared?leaf.matches("(?i)[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}\\.jpg"):
                        leaf.matches("[a-f0-9]{64}\\..+")||leaf.matches("import-[a-zA-Z0-9_-]+\\.part");
                    if(owned&&file.isFile()&&!Files.isSymbolicLink(file.toPath())&&file.getCanonicalFile().getParentFile().equals(owner.getCanonicalFile()))try{Files.deleteIfExists(file.toPath());}catch(IOException ignored){}
                }
            }
        }catch(IOException ignored){/* An unavailable optional preview cache must not prevent startup. */}
    }
    public synchronized void guard(String owner,String updatedAt)throws IOException{snapshot(owner,updatedAt);}
    private AccountRepository.Session snapshot(String owner,String updatedAt)throws IOException{
        CommunityRepository.id(owner);AccountRepository.Session session=accounts.cachedSession();
        if(session==null||accounts.isLogoutPending()||!owner.equals(session.user.id)||!session.user.updatedAt.equals(updatedAt))throw new IOException("账号资料已改变，请刷新后重新选择头像。");
        return session;
    }
    public synchronized Map<String,Object> prepare(String owner,String updatedAt,byte[] jpeg)throws IOException{
        snapshot(owner,updatedAt);
        if(jpeg==null||jpeg.length<4||jpeg.length>AccountRepository.MAX_AVATAR_BYTES||jpeg[0]!=(byte)255||jpeg[1]!=(byte)216||jpeg[jpeg.length-2]!=(byte)255||jpeg[jpeg.length-1]!=(byte)217)throw new IOException("头像图片无效或超过 1 MB。");
        MediaValidation.validate(jpeg);
        File folder=directory(directory(root,"profile-pending"),owner);
        String id=UUID.randomUUID().toString(),sha=PhotoEditStore.hash(jpeg);File file=new File(folder,id+".jpg");
        try(FileOutputStream output=new FileOutputStream(file)){output.write(jpeg);output.getFD().sync();}
        catch(IOException failure){Files.deleteIfExists(file.toPath());throw failure;}
        try{snapshot(owner,updatedAt);}catch(IOException stale){Files.deleteIfExists(file.toPath());throw stale;}
        drafts.put(id,new Draft(owner,updatedAt,sha,file));
        while(drafts.size()>MAX_DRAFTS){String oldest=drafts.keySet().iterator().next();try{discard(oldest);}catch(IOException optionalCleanup){drafts.remove(oldest);}}
        return SharedRuntime.map("receipt",id,"path",file.getPath(),"sha256",sha,"bytes",jpeg.length,"owner",owner,"updatedAt",updatedAt);
    }
    public synchronized AccountRepository.Session commit(String owner,String receipt,String sha)throws IOException{
        CommunityRepository.id(receipt);Draft draft=drafts.get(receipt);
        if(draft==null||!draft.owner.equals(owner)||!draft.sha.equals(sha))throw new IOException("头像预览已失效，请重新选择。");
        AccountRepository.Session session=snapshot(owner,draft.updatedAt);
        requireOwned(draft);
        if(!draft.file.isFile()||draft.file.length()<4||draft.file.length()>AccountRepository.MAX_AVATAR_BYTES||!PhotoEditStore.hashFile(draft.file).equals(draft.sha))throw new IOException("头像预览文件已改变，请重新选择。");
        byte[] bytes=bounded(draft.file);
        try{
            if(!PhotoEditStore.hash(bytes).equals(draft.sha))throw new IOException("头像预览文件已改变，请重新选择。");
            AccountRepository.Session fresh=accounts.updateAvatar(session,bytes,installation);
            try{discard(receipt);}catch(IOException optionalCleanup){drafts.remove(receipt);}return fresh;
        }finally{Arrays.fill(bytes,(byte)0);}
    }
    public synchronized AccountRepository.Session reset(String owner,String updatedAt)throws IOException{
        AccountRepository.Session session=snapshot(owner,updatedAt);
        AccountRepository.Session fresh=accounts.restoreDefaultAvatar(session,installation);clear();return fresh;
    }
    public synchronized void discardForOwner(String owner,String receipt)throws IOException{
        CommunityRepository.id(receipt);Draft draft=drafts.get(receipt);
        if(draft!=null){if(!draft.owner.equals(owner))throw new IOException("头像预览不属于当前账号。");discard(receipt);}
    }
    public synchronized void clear(){for(String id:new ArrayList<>(drafts.keySet()))try{discard(id);}catch(IOException ignored){drafts.remove(id);}}
    private void discard(String id)throws IOException{
        Draft draft=drafts.get(id);if(draft==null)return;requireOwned(draft);Files.deleteIfExists(draft.file.toPath());drafts.remove(id);
    }
    private void requireOwned(Draft draft)throws IOException{
        File parent=new File(new File(root,"profile-pending"),draft.owner);
        File pending=new File(root,"profile-pending");
        if(Files.isSymbolicLink(pending.toPath())||!pending.getCanonicalFile().getParentFile().equals(root.getCanonicalFile())||Files.isSymbolicLink(draft.file.toPath())||Files.isSymbolicLink(parent.toPath())||!draft.file.getCanonicalFile().getParentFile().equals(parent.getCanonicalFile())||!parent.getCanonicalFile().getParentFile().equals(pending.getCanonicalFile()))throw new IOException("头像预览路径无效。");
    }
    private static File directory(File parent,String name)throws IOException{
        File folder=new File(parent,name);if(Files.isSymbolicLink(folder.toPath())||!folder.getCanonicalFile().getParentFile().equals(parent.getCanonicalFile())||!folder.isDirectory()&&!folder.mkdirs())throw new IOException("无法准备头像预览目录。");return folder;
    }
    private static byte[] bounded(File file)throws IOException{
        try(InputStream input=new FileInputStream(file);ByteArrayOutputStream output=new ByteArrayOutputStream()){
            byte[] buffer=new byte[8192];int n;while((n=input.read(buffer))!=-1){if(n>AccountRepository.MAX_AVATAR_BYTES-output.size())throw new IOException("头像图片过大。");output.write(buffer,0,n);}return output.toByteArray();
        }
    }
}
