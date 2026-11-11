package cc.huevia.shared;

import cc.huevia.account.*;
import cc.huevia.library.SharedJson;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;

/** Native codecs have device tests; these tests exercise receipts, revisions and real account persistence. */
final class ProfileBoundaryTest {
    private static final String OWNER="11111111-1111-4111-8111-111111111111",OTHER="22222222-2222-4222-8222-222222222222",INSTALL="33333333-3333-4333-8333-333333333333";
    private static final String FIRST="2026-01-01T00:00:00.000Z",SECOND="2026-01-02T00:00:00.000Z";
    private static final byte[] JPEG={(byte)255,(byte)216,(byte)255,1,2,3,(byte)255,(byte)217};
    private static int checks;
    private interface Action{void run()throws Exception;}
    private static void yes(boolean value){checks++;if(!value)throw new AssertionError("Profile boundary "+checks);}
    private static void rejects(Action action)throws Exception{checks++;try{action.run();}catch(IOException expected){return;}throw new AssertionError("Invalid profile action accepted");}
    private static final class Store implements AccountRepository.Store {
        byte[] bytes;
        public byte[] read(){return bytes==null?null:bytes.clone();}
        public void write(byte[] value){bytes=value.clone();}
        public void clear(){bytes=null;}
    }
    private static final class Server implements AccountRepository.Transport {
        String owner=OWNER,updated=FIRST;int mutations,requests;boolean failNext,switchAccount;AccountRepository accounts;
        Map<String,Object> user(String id,String stamp){return SharedRuntime.map("id",id,"username",id.equals(OWNER)?"alice":"bob","nickname","测试资料","provider","password","avatarUrl","","avatarSource","default","status","active","createdAt",FIRST,"lastLoginAt",FIRST,"updatedAt",stamp,"loginCount",1);}
        AccountRepository.Response response(int status,Map<String,Object> value){return new AccountRepository.Response(status,AccountJson.stringify(value).getBytes(StandardCharsets.UTF_8));}
        public AccountRepository.Response request(String method,String path,String token,byte[] body)throws IOException{
            requests++;
            if(path.equals("/auth/login")){
                Map<String,Object> value=AccountJson.object(AccountJson.parse(new String(body,StandardCharsets.UTF_8)));
                owner="bob".equals(value.get("username"))?OTHER:OWNER;
                return response(200,SharedRuntime.map("tokenType","Bearer","accessToken","aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","expiresAt","2099-01-01T00:00:00.000Z","user",user(owner,updated)));
            }
            return response(200,SharedRuntime.map("ok",true));
        }
        public AccountRepository.Response profileRequest(String method,String path,String token,byte[] body,String installation,String expected)throws IOException{
            mutations++;yes(INSTALL.equals(installation));
            if(!expected.equals(updated))return response(409,SharedRuntime.map("error",SharedRuntime.map("code","USER_CONFLICT","message","changed")));
            if(method.equals("PUT"))yes(Arrays.equals(body,JPEG));
            updated=SECOND;Map<String,Object> receipt=user(owner,updated);
            if(switchAccount)accounts.login("bob","password1");
            if(failNext){failNext=false;throw new IOException("response lost after remote write");}
            return response(200,SharedRuntime.map("user",receipt));
        }
    }
    static int run(Path parent)throws Exception{
        checks=0;Path root=Files.createDirectory(parent.resolve("profile-boundaries"));Store store=new Store();Server server=new Server();
        AccountRepository accounts=new AccountRepository(store,server);server.accounts=accounts;accounts.login("alice","password1");
        // Real decoding is deliberately provided by Android/ImageIO, not simulated by this transport test.
        MediaValidation.install(bytes->{if(bytes.length<4)throw new IOException("invalid image");});
        SharedProfile profile=new SharedProfile(root.toFile(),accounts,INSTALL);
        rejects(()->profile.prepare(OTHER,FIRST,JPEG));
        rejects(()->profile.prepare(OWNER,SECOND,JPEG));
        rejects(()->profile.prepare(OWNER,FIRST,new byte[]{1,2,3,4}));
        yes(!Files.exists(root.resolve("profile-pending")));
        Map<String,Object> draft=profile.prepare(OWNER,FIRST,JPEG);String id=(String)draft.get("receipt"),sha=(String)draft.get("sha256");Path file=Paths.get((String)draft.get("path"));
        yes(Files.isRegularFile(file)&&((String)draft.get("owner")).equals(OWNER));
        yes(!SharedJson.encode(draft).contains("accessToken"));
        rejects(()->profile.commit(OTHER,id,sha));rejects(()->profile.discardForOwner(OTHER,id));
        yes(server.mutations==0);
        Files.write(file,new byte[]{(byte)255,(byte)216,(byte)255,9,9,(byte)255,(byte)217});
        rejects(()->profile.commit(OWNER,id,sha));yes(server.mutations==0);
        profile.discardForOwner(OWNER,id);yes(!Files.exists(file));
        draft=profile.prepare(OWNER,FIRST,JPEG);String savedId=(String)draft.get("receipt"),savedSha=(String)draft.get("sha256");Path saved=Paths.get((String)draft.get("path"));
        profile.commit(OWNER,savedId,savedSha);yes(accounts.cachedSession().user.updatedAt.equals(SECOND)&&server.mutations==1&&!Files.exists(saved));
        rejects(()->profile.commit(OWNER,savedId,savedSha));
        profile.reset(OWNER,SECOND);yes(server.mutations==2);
        rejects(()->profile.reset(OTHER,SECOND));yes(server.mutations==2);
        // A lost response retains reviewed bytes. A retry cannot overwrite a newer server revision.
        server.updated=FIRST;accounts.login("alice","password1");draft=profile.prepare(OWNER,FIRST,JPEG);String lostId=(String)draft.get("receipt"),lostSha=(String)draft.get("sha256");Path lost=Paths.get((String)draft.get("path"));server.failNext=true;
        rejects(()->profile.commit(OWNER,lostId,lostSha));yes(Files.exists(lost)&&accounts.cachedSession().user.updatedAt.equals(FIRST));
        rejects(()->profile.commit(OWNER,lostId,lostSha));accounts.login("alice","password1");int before=server.mutations;
        rejects(()->profile.commit(OWNER,lostId,lostSha));yes(server.mutations==before);profile.clear();yes(!Files.exists(lost));
        // The original repository's generation check prevents an old response replacing a new author.
        server.updated=FIRST;accounts.login("alice","password1");draft=profile.prepare(OWNER,FIRST,JPEG);String switchingId=(String)draft.get("receipt"),switchingSha=(String)draft.get("sha256");server.switchAccount=true;
        rejects(()->profile.commit(OWNER,switchingId,switchingSha));yes(accounts.cachedSession().user.id.equals(OTHER));server.switchAccount=false;profile.clear();
        server.updated=FIRST;accounts.login("alice","password1");
        Map<String,Object> oldest=profile.prepare(OWNER,FIRST,JPEG);Path oldestFile=Paths.get((String)oldest.get("path"));
        for(int i=0;i<8;i++)profile.prepare(OWNER,FIRST,JPEG);yes(!Files.exists(oldestFile));
        Path notes=oldestFile.getParent().resolve("user-notes.txt");Files.write(notes,new byte[]{1,2,3});
        new SharedProfile(root.toFile(),accounts,INSTALL);yes(Files.isRegularFile(notes));
        try(java.util.stream.Stream<Path> files=Files.list(notes.getParent())){yes(files.noneMatch(p->p.toString().endsWith(".jpg")));}
        byte[] raw=new byte[64];Map<String,Object> staged=SharedJson.object(SharedImport.stageAvatar(new ByteArrayInputStream(raw),"image",OWNER,root.toString(),()->false));Path stagedFile=Paths.get((String)staged.get("path"));
        yes(Files.isRegularFile(stagedFile)&&stagedFile.toString().contains("avatar-incoming"));
        new SharedProfile(root.toFile(),accounts,INSTALL);yes(!Files.exists(stagedFile));
        rejects(()->SharedImport.stageAvatar(new ByteArrayInputStream(raw),"image.png",OWNER,root.toString(),()->true));
        SharedRuntime runtime=new SharedRuntime(root.resolve("runtime").toString(),store,server,INSTALL);int requests=server.requests;
        rejects(()->runtime.request("account.login",SharedJson.encode(SharedRuntime.map("owner",OTHER,"username","bob","password","password1"))));
        rejects(()->runtime.request("account.refresh",SharedJson.encode(SharedRuntime.map("owner",OTHER))));
        rejects(()->runtime.request("account.logout",SharedJson.encode(SharedRuntime.map("owner",OTHER))));
        yes(requests==server.requests);
        System.out.println("PASS "+checks+" profile checks; reviewed bytes, account revisions, response loss, generation and bounded cleanup");return checks;
    }
}
