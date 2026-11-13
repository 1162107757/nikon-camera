package cc.huevia.shared;

import cc.huevia.account.AccountRepository;
import cc.huevia.album.PhotoEditStore;
import cc.huevia.library.SharedJson;
import cc.huevia.ptp.PtpObjectInfo;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;

/** Native receipt durability and ownership are tested independently of a Flutter completion reply. */
public final class SharedDownloadsBoundaryTest {
    private static int checks;
    private static final String CAMERA="a".repeat(64),OTHER="b".repeat(64),FOLDER="f".repeat(32);
    private interface Action{void run()throws Exception;}
    private static void yes(boolean value){checks++;if(!value)throw new AssertionError("Downloads boundary "+checks);}
    private static void rejects(Action action)throws Exception{checks++;try{action.run();}catch(IOException expected){return;}throw new AssertionError("Invalid queue mutation accepted "+checks);}
    static int run(Path temporary)throws Exception {
        checks=0;Path root=Files.createDirectory(temporary.resolve("shared-downloads"));SharedRuntime runtime=runtime(root);
        byte[] bytes={(byte)255,(byte)216,1,2,3,4,(byte)255,(byte)217};String sha=PhotoEditStore.hash(bytes);Path original=Files.createDirectories(root.resolve("originals")).resolve(sha+".jpg");Files.write(original,bytes);
        PtpObjectInfo object=object("DSC_0001.JPG");Map<String,Object> row=row(object),receipt=SharedRuntime.map("path",original.toString(),"name",object.filename(),"sha256",sha,"bytes",bytes.length,"raw",false);
        Map<String,Object> q=create(runtime,row,SharedRuntime.map("kind","app")),scope=scope(q);String id=(String)q.get("id"),item=(String)scope.get("itemId");
        rejects(()->request(runtime,"downloads.item",SharedRuntime.map("owner","","id",id,"itemId",item,"phase","receiving")));
        rejects(()->SharedDownloads.recordTransfer(root.toFile(),scope,receipt));
        request(runtime,"downloads.resume",SharedRuntime.map("owner","","id",id));request(runtime,"downloads.item",SharedRuntime.map("owner","","id",id,"itemId",item,"phase","receiving"));
        SharedDownloads.validateTransfer(root.toFile(),scope,CAMERA,false,"session-a",object);checks++;
        rejects(()->SharedDownloads.validateTransfer(root.toFile(),scope,OTHER,false,"session-a",object));
        rejects(()->SharedDownloads.validateTransfer(root.toFile(),scope,CAMERA,false,"different-session",object));
        rejects(()->SharedDownloads.validateTransfer(root.toFile(),scope,CAMERA,false,"session-a",object("CHANGED.JPG")));
        Map<String,Object> wrongOwner=new LinkedHashMap<>(scope);wrongOwner.put("owner","11111111-1111-4111-8111-111111111111");rejects(()->SharedDownloads.validateTransfer(root.toFile(),wrongOwner,CAMERA,false,"session-a",object));
        rejects(()->request(runtime,"downloads.get",SharedRuntime.map("owner","11111111-1111-4111-8111-111111111111","id",id)));
        SharedDownloads.recordTransfer(root.toFile(),scope,receipt);q=request(runtime,"downloads.get",SharedRuntime.map("owner","","id",id));yes(first(q).get("phase").equals("received"));yes(map(first(q).get("receipt")).get("sha256").equals(sha));
        SharedRuntime restarted=runtime(root);q=request(restarted,"downloads.get",SharedRuntime.map("owner","","id",id));yes(first(q).get("phase").equals("received"));
        rejects(()->request(restarted,"downloads.item",SharedRuntime.map("owner","","id",id,"itemId",item,"phase","receiving")));
        SharedDownloads.recordTransfer(root.toFile(),scope,receipt);yes(first(request(restarted,"downloads.get",SharedRuntime.map("owner","","id",id))).get("phase").equals("received"));
        request(restarted,"downloads.item",SharedRuntime.map("owner","","id",id,"itemId",item,"phase","completed"));request(restarted,"downloads.finish",SharedRuntime.map("owner","","id",id));
        SharedDownloads.recordTransfer(root.toFile(),scope,receipt);yes(first(request(restarted,"downloads.get",SharedRuntime.map("owner","","id",id))).get("phase").equals("completed"));
        rejects(()->request(restarted,"downloads.item",SharedRuntime.map("owner","","id",id,"itemId",item,"phase","receiving")));
        rejects(()->SharedDownloads.validateTransfer(root.toFile(),scope,CAMERA,false,"session-a",object));
        // Path/SHA/format/size/name errors cannot install a native completed receipt.
        Map<String,Object> folderQueue=create(restarted,row,SharedRuntime.map("kind","folder","id",FOLDER,"name","RAW folder")),folderScope=scope(folderQueue);String folderId=(String)folderQueue.get("id"),folderItem=(String)folderScope.get("itemId");
        request(restarted,"downloads.resume",SharedRuntime.map("owner","","id",folderId));request(restarted,"downloads.item",SharedRuntime.map("owner","","id",folderId,"itemId",folderItem,"phase","receiving"));
        Path outside=temporary.resolve("outside.jpg");Files.write(outside,bytes);
        for(Map<String,Object> bad:List.of(changed(receipt,"path",outside.toString()),changed(receipt,"sha256","0".repeat(64)),changed(receipt,"bytes",7),changed(receipt,"raw",true),changed(receipt,"name","OTHER.JPG")))rejects(()->SharedDownloads.recordTransfer(root.toFile(),folderScope,bad));
        yes(!first(request(restarted,"downloads.get",SharedRuntime.map("owner","","id",folderId))).containsKey("receipt"));yes(Arrays.equals(Files.readAllBytes(outside),bytes));
        SharedDownloads.recordTransfer(root.toFile(),folderScope,receipt);
        Map<String,Object> publication=SharedRuntime.map("owner","","operationId",folderItem,"targetKind","folder","targetId",FOLDER,"published",true,"verified",true,"sha256",sha,"bytes",bytes.length,"uri","content://provider/document/verified-original");
        for(Map<String,Object> bad:List.of(changed(publication,"owner","11111111-1111-4111-8111-111111111111"),changed(publication,"operationId","0".repeat(32)),changed(publication,"sha256","0".repeat(64)),changed(publication,"bytes",7),changed(publication,"targetKind","system"),changed(publication,"targetId","0".repeat(32)),changed(publication,"verified",false),changed(publication,"published",false),changed(publication,"uri","/external/unverified")))rejects(()->request(restarted,"downloads.item",SharedRuntime.map("owner","","id",folderId,"itemId",folderItem,"phase","completed","publication",bad)));
        yes(first(request(restarted,"downloads.get",SharedRuntime.map("owner","","id",folderId))).get("phase").equals("received"));
        byte[] modified=bytes.clone();modified[3]++;Files.write(original,modified);rejects(()->request(restarted,"downloads.item",SharedRuntime.map("owner","","id",folderId,"itemId",folderItem,"phase","completed","publication",publication)));Files.write(original,bytes);
        request(restarted,"downloads.item",SharedRuntime.map("owner","","id",folderId,"itemId",folderItem,"phase","completed","publication",publication));request(restarted,"downloads.finish",SharedRuntime.map("owner","","id",folderId));yes(map(first(request(runtime(root),"downloads.get",SharedRuntime.map("owner","","id",folderId))).get("publication")).get("targetId").equals(FOLDER));
        // Explicitly confirmed camera rebinding changes neither descriptors nor the frozen target.
        Map<String,Object> rebound=create(restarted,row,SharedRuntime.map("kind","system"));String reboundId=(String)rebound.get("id");Map<String,Object> reboundScope=scope(rebound);String reboundItem=(String)reboundScope.get("itemId");
        Map<String,Object> bind=SharedRuntime.map("owner","","id",reboundId,"cameraId",OTHER,"session","session-b","trusted",true,"target",SharedRuntime.map("kind","app"));rejects(()->request(restarted,"downloads.bind",bind));bind.put("confirmed",true);rebound=request(restarted,"downloads.bind",bind);yes(map(rebound.get("target")).get("kind").equals("system"));
        request(restarted,"downloads.resume",SharedRuntime.map("owner","","id",reboundId));request(restarted,"downloads.item",SharedRuntime.map("owner","","id",reboundId,"itemId",reboundItem,"phase","receiving"));
        SharedDownloads.validateTransfer(root.toFile(),reboundScope,OTHER,true,"session-after-reconnect",object);checks++;
        rejects(()->SharedDownloads.validateTransfer(root.toFile(),reboundScope,OTHER,false,"session-after-reconnect",object));
        request(restarted,"downloads.pause",SharedRuntime.map("owner","","id",reboundId));rejects(()->SharedDownloads.validateTransfer(root.toFile(),reboundScope,OTHER,true,"session-b",object));
        rejects(()->create(restarted,row,SharedRuntime.map("kind","folder","id","../outside")));
        Map<String,Object> tooMany=SharedRuntime.map("owner","","cameraId",CAMERA,"trusted",true,"session","s","target",SharedRuntime.map("kind","app"),"items",Collections.nCopies(101,row));rejects(()->request(restarted,"downloads.create",tooMany));
        tooMany.put("items",List.of(row,row));rejects(()->request(restarted,"downloads.create",tooMany));
        // A corrupt record is preserved and does not hide independent valid queues.
        Path queuePath=root.resolve("camera-downloads").resolve(PhotoEditStore.hash(new byte[0])).resolve(reboundId+".json");byte[] valid=Files.readAllBytes(queuePath);Map<String,Object> intact=SharedJson.object(new String(valid,StandardCharsets.UTF_8));
        List<Map<String,Object>> damaged=new ArrayList<>();damaged.add(changed(intact,"phase",null));damaged.add(changed(intact,"trusted","yes"));damaged.add(changed(intact,"items",List.of("invalid")));damaged.add(changed(intact,"target",SharedRuntime.map("kind","folder","id","bad")));damaged.add(changed(intact,"owner","other"));
        for(Map<String,Object> bad:damaged){Files.write(queuePath,SharedJson.encode(bad).getBytes(StandardCharsets.UTF_8));rejects(()->request(restarted,"downloads.get",SharedRuntime.map("owner","","id",reboundId)));}
        Map<String,Object> list=request(restarted,"downloads.list",SharedRuntime.map("owner",""));yes(((List<?>)list.get("items")).size()==2);yes(((List<?>)list.get("issues")).size()==1);yes(Files.exists(queuePath));Files.write(queuePath,valid);
        try(java.util.stream.Stream<Path> files=Files.list(queuePath.getParent())){yes(files.noneMatch(path->path.getFileName().toString().endsWith(".part")));}
        yes(Arrays.equals(Files.readAllBytes(original),bytes));System.out.println("PASS "+checks+" durable download queue checks; owner/camera/session/descriptor guards, native-first receipts, restart, terminal idempotence, frozen target evidence and corrupt-log isolation");return checks;
    }
    private static SharedRuntime runtime(Path root)throws IOException{return new SharedRuntime(root.toString(),new AccountRepository.Store(){public byte[] read(){return null;}public void write(byte[] bytes){}public void clear(){}},(m,p,t,b)->{throw new AssertionError("Queue used network");});}
    private static Map<String,Object> create(SharedRuntime runtime,Map<String,Object> row,Map<String,Object> target)throws IOException{return request(runtime,"downloads.create",SharedRuntime.map("owner","","cameraId",CAMERA,"trusted",false,"session","session-a","target",target,"items",List.of(row)));}
    private static Map<String,Object> row(PtpObjectInfo object){return SharedRuntime.map("descriptor",PhotoEditStore.hash(object.toBytes()),"name",object.filename(),"handle",1,"storage",object.storageId(),"bytes",object.compressedSize(),"raw",false);}
    private static PtpObjectInfo object(String name){return new PtpObjectInfo.Builder().storageId(1).parentObject(10).objectFormat(0x3801).filename(name).compressedSize(8).build();}
    private static Map<String,Object> scope(Map<String,Object> q){return SharedRuntime.map("owner","","queueId",q.get("id"),"itemId",first(q).get("id"));}
    private static Map<String,Object> first(Map<String,Object> q){return map(((List<?>)q.get("items")).get(0));}
    private static Map<String,Object> request(SharedRuntime r,String operation,Map<String,Object> p)throws IOException{return map(SharedDownloads.request(r,operation,p,()->false));}
    private static Map<String,Object> changed(Map<String,Object> original,String key,Object value){Map<String,Object> copy=new LinkedHashMap<>(original);copy.put(key,value);return copy;}
    @SuppressWarnings("unchecked") private static Map<String,Object> map(Object value){return (Map<String,Object>)value;}
    public static void main(String[] args)throws Exception{run(Files.createTempDirectory("shared-downloads-"));}
}
