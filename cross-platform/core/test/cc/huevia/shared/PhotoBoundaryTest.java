package cc.huevia.shared;

import cc.huevia.account.AccountRepository;
import cc.huevia.album.PhotoStarStore;
import cc.huevia.library.SharedJson;
import java.io.*;
import java.nio.file.*;
import java.util.*;

public final class PhotoBoundaryTest {
    private static int checks;
    private static void yes(boolean value){checks++;if(!value)throw new AssertionError("Photo boundary "+checks);}
    private static final class Store implements AccountRepository.Store {
        public byte[] read(){return null;}public void write(byte[] bytes){}public void clear(){}
    }
    private static SharedRuntime open(Path root)throws IOException{return new SharedRuntime(root.toString(),new Store(),(m,p,t,b)->{throw new AssertionError("Stars contacted network");});}
    private static Map<String,Object> call(SharedRuntime r,String op,Map<String,Object> body)throws IOException{return SharedJson.object(r.request(op,SharedJson.encode(body)));}
    public static int run(Path temporary)throws Exception{
        checks=0;Path root=temporary.resolve("photo-boundary");SharedRuntime runtime=open(root);Path originals=Files.createDirectories(root.resolve("originals")),photo=originals.resolve("stable.jpg");Files.write(photo,new byte[]{1,2,3,4});
        yes(((List<?>)call(runtime,"photo.stars",Collections.emptyMap()).get("keys")).isEmpty());
        String key=PhotoStarStore.localKey(photo.toFile());
        Map<String,Object> starred=call(runtime,"photo.star",SharedRuntime.map("path",photo.toString(),"starred",true));
        yes(((List<?>)starred.get("keys")).contains(key));yes(((List<?>)call(open(root),"photo.stars",Collections.emptyMap()).get("keys")).contains(key));
        call(runtime,"photo.star",SharedRuntime.map("path",photo.toString(),"starred",true));yes(((List<?>)call(runtime,"photo.stars",Collections.emptyMap()).get("keys")).size()==1);
        Path moved=Files.createDirectories(root.resolve("new-container")).resolve("stable.jpg");Files.write(moved,new byte[]{1,2,3,4});yes(PhotoStarStore.localKey(moved.toFile()).equals(key));
        boolean invalid=false;try{call(runtime,"photo.star",SharedRuntime.map("path",moved.toString(),"starred",true));}catch(IOException expected){invalid=true;}yes(invalid);
        invalid=false;try{call(runtime,"photo.star",SharedRuntime.map("path",photo.toString(),"starred","true"));}catch(IOException expected){invalid=true;}yes(invalid);
        call(runtime,"photo.star",SharedRuntime.map("path",photo.toString(),"starred",false));yes(((List<?>)call(open(root),"photo.stars",Collections.emptyMap()).get("keys")).isEmpty());
        yes(Arrays.equals(Files.readAllBytes(photo),new byte[]{1,2,3,4}));return checks;
    }
}
