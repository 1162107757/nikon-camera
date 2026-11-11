package cc.huevia.shared;

import cc.huevia.library.*;
import cc.huevia.ncp.NcpCompatibilityFixtures;
import java.io.*;
import java.nio.file.*;
import java.util.*;

/** Exercises the original sync transaction and conflict decisions against a revisioned fake server. */
public final class PersonalSyncBoundaryTest {
    private static int checks;
    private static void yes(boolean value){checks++;if(!value)throw new AssertionError("Personal sync check "+checks);}
    public static int run(Path parent)throws Exception {
        checks=0;File root=Files.createDirectory(parent.resolve("sync-boundaries")).toFile();
        String alice="aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",bob="bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb";
        PresetLibrary library=new PresetLibrary(root);byte[] bytes=NcpCompatibilityFixtures.ncp();
        PresetRecord preset=library.importFile("sync-fixture.ncp",bytes).record;String hash=preset.id;
        PersonalPresetSync sync=new PersonalPresetSync(root,library);
        yes(sync.visible("",hash));yes(sync.consentNeeded(alice));
        sync.consent(alice,false);yes(!sync.consentNeeded(alice));yes(sync.visible("",hash));
        sync.markAdded(alice,preset);yes(!sync.visible("",hash));yes(sync.visible(alice,hash));yes(!sync.visible(bob,hash));
        Map<String,Object> server=new LinkedHashMap<>();int[] puts={0},deletes={0};
        PersonalPresetSync.Backend backend=new PersonalPresetSync.Backend(){
            private void owner(String id)throws IOException{if(!alice.equals(id))throw new IOException("Wrong account at backend boundary");}
            public List<Map<String,Object>> list(String id,String after)throws IOException{owner(id);return server.isEmpty()||!after.isEmpty()?Collections.emptyList():Collections.singletonList(new LinkedHashMap<>(server));}
            public byte[] download(String id,String sha)throws IOException{owner(id);yes(sha.equals(hash));return bytes.clone();}
            public long put(String id,String sha,Map<String,Object> metadata,byte[] value,long revision)throws IOException{
                owner(id);yes(sha.equals(hash));yes(Arrays.equals(bytes,value));long current=server.isEmpty()?0:((Number)server.get("revision")).longValue();
                if(current!=revision)throw new IOException("Revision conflict");server.clear();server.putAll(metadata);server.put("sha256",sha);server.put("revision",current+1);server.put("deleted",false);puts[0]++;return current+1;
            }
            public void delete(String id,String sha,long revision)throws IOException{owner(id);yes(sha.equals(hash));if(((Number)server.get("revision")).longValue()!=revision)throw new IOException("Revision conflict");server.put("deleted",true);server.put("revision",revision+1);deletes[0]++;}
        };
        sync.sync(alice,backend,(done,total)->{});yes(puts[0]==1);yes(((Number)server.get("revision")).longValue()==1);
        PresetRecord edited=library.setCategory(hash,"本机分类");sync.markAdded(alice,edited);
        server.put("displayName","云端名称");server.put("revision",2L);sync.sync(alice,backend,(done,total)->{});
        yes(sync.conflicts(alice)==1);yes(puts[0]==1);yes(library.findBySha256(hash).category.equals("本机分类"));
        sync.resolveConflicts(alice,false);sync.sync(alice,backend,(done,total)->{});
        yes(sync.conflicts(alice)==0);yes(library.findBySha256(hash).displayName.equals("云端名称"));yes(!library.findBySha256(hash).category.equals("本机分类"));
        edited=library.setCategory(hash,"保留本机");sync.markAdded(alice,edited);server.put("displayName","再次修改");server.put("revision",3L);
        sync.sync(alice,backend,(done,total)->{});yes(sync.conflicts(alice)==1);sync.resolveConflicts(alice,true);sync.sync(alice,backend,(done,total)->{});
        yes(sync.conflicts(alice)==0);yes(puts[0]==2);yes(server.get("category").equals("保留本机"));yes(((Number)server.get("revision")).longValue()==4);
        sync.markDeleted(alice,hash);sync.sync(alice,backend,(done,total)->{});
        yes(deletes[0]==1);yes(Boolean.TRUE.equals(server.get("deleted")));yes(!sync.visible(alice,hash));
        PersonalPresetSync reopened=new PersonalPresetSync(root,library);yes(!reopened.visible("",hash));yes(!reopened.visible(alice,hash));yes(!reopened.visible(bob,hash));
        System.out.println("PASS "+checks+" personal sync checks; consent, owner visibility, revisions, both conflict choices and deletion persistence");return checks;
    }
}
