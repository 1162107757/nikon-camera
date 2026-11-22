package cc.huevia.shared;

import cc.huevia.album.PhotoEditStore;
import cc.huevia.library.PresetLibrary;
import cc.huevia.library.SharedJson;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.Collections;

/** Existing drafts, identity resets, owner boundaries and unchanged original bytes. */
public final class AlbumEditStatusBoundaryTest {
    private static int checks;
    private static void yes(boolean value){checks++;if(!value)throw new AssertionError("Album edit status "+checks);}
    private interface Action {void run()throws Exception;}
    private static void rejects(Action action)throws Exception{checks++;try{action.run();}catch(IOException expected){return;}throw new AssertionError("Invalid album status accepted");}
    public static int run(Path temporary)throws Exception{
        checks=0;Path root=Files.createDirectory(temporary.resolve("album-edited"));
        byte[] bytes={1,2,3,4,5};String sha=PhotoEditStore.hash(bytes);
        Path source=root.resolve(sha+".jpg");Files.write(source,bytes);
        SharedEdits edits=new SharedEdits(root.toFile(),new PresetLibrary(root.toFile()));
        yes(Boolean.FALSE.equals(edits.albumStatus(source.toFile(),"alice").get("edited")));
        edits.freeze(source.toFile(),"alice","{}");
        yes(Boolean.FALSE.equals(edits.albumStatus(source.toFile(),"alice").get("edited")));
        int[] values=new int[17];values[0]=10;
        edits.freeze(source.toFile(),"alice",SharedJson.encode(SharedRuntime.map("values",Arrays.stream(values).boxed().collect(java.util.stream.Collectors.toList()))));
        yes(Boolean.TRUE.equals(edits.albumStatus(source.toFile(),"alice").get("edited")));
        yes(Boolean.FALSE.equals(edits.albumStatus(source.toFile(),"bob").get("edited")));
        yes(Boolean.FALSE.equals(edits.albumStatus(source.toFile(),"").get("edited")));
        yes(edits.albumStatus(source.toFile(),"alice").get("sourceSha").equals(sha));
        edits.freeze(source.toFile(),"alice","{}");
        yes(Boolean.FALSE.equals(edits.albumStatus(source.toFile(),"alice").get("edited")));
        edits.freeze(source.toFile(),"alice","{\"geometry\":{\"turns\":1}}");
        yes(Boolean.TRUE.equals(edits.albumStatus(source.toFile(),"alice").get("edited")));
        yes(Arrays.equals(bytes,Files.readAllBytes(source)));
        Files.write(source,new byte[]{5,4,3,2,1});
        Files.setLastModifiedTime(source,java.nio.file.attribute.FileTime.fromMillis(source.toFile().lastModified()+1000));
        yes(Boolean.FALSE.equals(edits.albumStatus(source.toFile(),"alice").get("edited")));
        SharedRuntime runtime=new SharedRuntime(root.toString(),new cc.huevia.account.AccountRepository.Store(){
            public byte[] read(){return null;}public void write(byte[] b){}public void clear(){}
        },(method,path,token,body)->{throw new AssertionError("Status used network");});
        String request=SharedJson.encode(SharedRuntime.map("owner","","paths",Collections.singletonList(source.toString())));
        yes(SharedJson.object(runtime.request("draft.statuses",request)).containsKey("items"));
        String mixed=SharedJson.encode(SharedRuntime.map("owner","","paths",Arrays.asList(source.toString(),root.resolve("missing.jpg").toString())));
        java.util.List<?> mixedRows=(java.util.List<?>)SharedJson.object(runtime.request("draft.statuses",mixed)).get("items");
        yes(mixedRows.size()==2);yes(Boolean.TRUE.equals(SharedRuntime.object(mixedRows.get(1)).get("unavailable")));
        rejects(()->runtime.request("draft.statuses",SharedJson.encode(SharedRuntime.map("owner","alice","paths",Collections.singletonList(source.toString())))));
        rejects(()->runtime.request("draft.statuses",SharedJson.encode(SharedRuntime.map("owner","","paths",Collections.nCopies(101,source.toString())))));
        rejects(()->runtime.request("draft.statuses",SharedJson.encode(SharedRuntime.map("owner","","paths",Collections.singletonList(temporary.resolve("outside.jpg").toString())))));
        System.out.println("PASS "+checks+" album edited-state checks; owner scope, reset, geometry, original identity and bounded private paths");
        return checks;
    }
}
