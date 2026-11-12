package cc.huevia.shared;

import cc.huevia.account.AccountRepository;
import cc.huevia.album.PhotoEditStore;
import cc.huevia.library.SharedJson;
import java.io.IOException;
import java.nio.file.*;
import java.util.*;

public final class OriginalPublicationBoundaryTest {
    private static int checks;
    private static void yes(boolean value){checks++;if(!value)throw new AssertionError("Original publication boundary "+checks);}
    private static void rejected(SharedRuntime runtime,Map<String,Object> input)throws Exception {
        try{runtime.prepareOriginalPublication(SharedJson.encode(input),()->false);throw new AssertionError("Invalid original publication accepted");}catch(IOException expected){checks++;}
    }
    public static int run(Path temporary)throws Exception {
        checks=0;Path root=Files.createDirectories(temporary.resolve("original-publication")),originals=Files.createDirectories(root.resolve("originals"));
        byte[] bytes={(byte)255,(byte)216,(byte)255,(byte)225,1,2,3,4,(byte)255,(byte)217};String sha=PhotoEditStore.hash(bytes);
        Path source=originals.resolve(sha+".jpg");Files.write(source,bytes);
        AccountRepository.Store store=new AccountRepository.Store(){public byte[] read(){return null;}public void write(byte[] value){}public void clear(){}};
        SharedRuntime runtime=new SharedRuntime(root.toString(),store,(method,path,token,body)->{throw new AssertionError("Original save contacted network");});
        Map<String,Object> input=SharedRuntime.map("owner","","path",source.toString(),"expectedSourceSha",sha,"operationId","a".repeat(32));
        String versions=runtime.request("version.list","{\"owner\":\"\"}"),draft=runtime.request("draft.load",SharedJson.encode(input));
        Map<String,Object> prepared=SharedJson.object(runtime.prepareOriginalPublication(SharedJson.encode(input),()->false));
        Path snapshot=Path.of((String)prepared.get("path"));
        yes(!snapshot.equals(source)&&Arrays.equals(Files.readAllBytes(snapshot),bytes));
        yes(sha.equals(prepared.get("sourceSha"))&&sha.equals(prepared.get("sha256")));
        yes(prepared.equals(SharedJson.object(runtime.prepareOriginalPublication(SharedJson.encode(input),()->false))));
        yes(runtime.request("version.list","{\"owner\":\"\"}").equals(versions));
        yes(runtime.request("draft.load",SharedJson.encode(input)).equals(draft));
        Map<String,Object> release=SharedRuntime.map("owner","","operationId",input.get("operationId"),"sha256",sha,"bytes",bytes.length);
        release.put("sha256","0".repeat(64));
        try{runtime.releaseOriginalPublication(SharedJson.encode(release));throw new AssertionError("Mismatched cleanup accepted");}catch(IOException expected){checks++;}
        yes(Files.exists(snapshot));release.put("sha256",sha);
        runtime.releaseOriginalPublication(SharedJson.encode(release));yes(!Files.exists(snapshot)&&Arrays.equals(Files.readAllBytes(source),bytes));
        // Lost acknowledgement: the same task re-prepares the exact bytes and identity.
        yes(prepared.equals(SharedJson.object(runtime.prepareOriginalPublication(SharedJson.encode(input),()->false))));
        input.put("owner","another");rejected(runtime,input);input.put("owner","");
        input.put("expectedSourceSha","");rejected(runtime,input);input.put("expectedSourceSha","0".repeat(64));rejected(runtime,input);input.put("expectedSourceSha",sha);
        input.put("operationId","../outside");rejected(runtime,input);input.put("operationId","a".repeat(32));
        try{runtime.prepareOriginalPublication(SharedJson.encode(input),()->true);throw new AssertionError("Cancelled snapshot accepted");}catch(IOException expected){checks++;}
        Path png=originals.resolve(sha+".png");Files.write(png,bytes);input.put("path",png.toString());rejected(runtime,input);
        input.put("path",source.toString());Files.write(snapshot,new byte[]{1,2,3});rejected(runtime,input);
        try{runtime.releaseOriginalPublication(SharedJson.encode(release));throw new AssertionError("Changed snapshot cleanup accepted");}catch(IOException expected){checks++;}
        yes(Arrays.equals(Files.readAllBytes(snapshot),new byte[]{1,2,3}));Files.write(snapshot,bytes);
        byte[] changed=bytes.clone();changed[5]=33;String otherSha=PhotoEditStore.hash(changed);Path other=originals.resolve(otherSha+".jpg");Files.write(other,changed);
        input.put("path",other.toString());input.put("expectedSourceSha",otherSha);rejected(runtime,input);
        input.put("operationId","b".repeat(32));
        Map<String,Object> second=SharedJson.object(runtime.prepareOriginalPublication(SharedJson.encode(input),()->false));yes(!second.get("id").equals(prepared.get("id")));
        // Snapshot lifetime is independent of the source's later removal.
        Files.delete(other);yes(Arrays.equals(Files.readAllBytes(Path.of((String)second.get("path"))),changed));
        rejected(runtime,input);
        byte[] invalid={1,2,3,4};String invalidSha=PhotoEditStore.hash(invalid);Path invalidJpeg=originals.resolve(invalidSha+".jpg");Files.write(invalidJpeg,invalid);
        input.put("path",invalidJpeg.toString());input.put("expectedSourceSha",invalidSha);input.put("operationId","c".repeat(32));rejected(runtime,input);
        input.put("path",source.toString());input.put("expectedSourceSha",sha);input.put("operationId","d".repeat(32));
        final int[] polls={0};
        try{runtime.prepareOriginalPublication(SharedJson.encode(input),()->++polls[0]>=4);throw new AssertionError("Mid-copy cancellation accepted");}catch(IOException expected){checks++;}
        Path directory=snapshot.getParent();
        yes(!Files.exists(directory.resolve("d".repeat(32)+".jpg")));
        try(java.util.stream.Stream<Path> files=Files.list(directory)){yes(files.noneMatch(file->file.getFileName().toString().endsWith(".part")));}
        for(int i=0;i<6;i++)Files.write(directory.resolve("quota-own-"+i+".part"),new byte[]{1});
        input.put("operationId","e".repeat(32));rejected(runtime,input);
        for(int i=0;i<6;i++)Files.delete(directory.resolve("quota-own-"+i+".part"));
        yes(Arrays.equals(Files.readAllBytes(source),bytes));
        return checks;
    }
}
