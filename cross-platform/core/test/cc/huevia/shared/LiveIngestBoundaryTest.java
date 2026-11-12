package cc.huevia.shared;

import cc.huevia.account.AccountRepository;
import cc.huevia.album.PhotoEditStore;
import cc.huevia.library.SharedJson;
import cc.huevia.ncp.NcpCompatibilityFixtures;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.Arrays;
import java.util.Comparator;
import java.util.List;
import java.util.Map;

/** Durable receive/queue boundaries, exercised against the original project and preset journals. */
public final class LiveIngestBoundaryTest {
    private static int checks;
    private static void yes(boolean value){checks++;if(!value)throw new AssertionError("Live ingest boundary "+checks);}
    private interface Action{void run()throws Exception;}
    private static void rejects(Action action)throws Exception{checks++;try{action.run();}catch(IOException expected){return;}throw new AssertionError("Invalid live receive accepted");}
    private static final class Store implements AccountRepository.Store {public byte[] read(){return null;}public void write(byte[] value){}public void clear(){}}
    private static SharedRuntime runtime(Path root)throws IOException{return new SharedRuntime(root.toString(),new Store(),(method,path,token,data)->{throw new IOException("Offline test");});}
    private static Map<String,Object> call(SharedProjects projects,String operation,Map<String,Object> p)throws IOException{return projects.request(operation,p,()->false);}
    @SuppressWarnings("unchecked") private static List<Map<String,Object>> rows(Map<String,Object> value,String key){return (List<Map<String,Object>>)(List<?>)value.get(key);}
    private static Map<String,Object> with(Map<String,Object> base,Object... values){Map<String,Object> result=new java.util.LinkedHashMap<>(base);result.putAll(SharedRuntime.map(values));return result;}
    private static String hash(String value){return PhotoEditStore.hash(value.getBytes(StandardCharsets.UTF_8));}
    private static Map<String,Object> cursor(){return SharedRuntime.map("baseline",Arrays.asList(SharedRuntime.map("storage",1,"handle",100)),"initializedStorages",Arrays.asList(1));}
    private static Map<String,Object> candidate(String key,int handle,long bytes){return SharedRuntime.map("objectKey",key,"storage",1,"handle",handle,"name","DSC_"+handle+".JPG","bytes",bytes,"width",4,"height",2,"capturedAt","20261112T120000","raw",false);}

    public static int run(Path temporary)throws Exception{
        checks=0;Path root=temporary.resolve("live-ingest-runtime");Files.createDirectories(root);SharedRuntime runtime=runtime(root);SharedProjects projects=new SharedProjects(runtime);
        String id=(String)call(projects,"project.create",SharedRuntime.map("name","自动拍摄项目")).get("id"),camera=hash("owned-camera-guid");
        Map<String,Object> identity=SharedRuntime.map("projectId",id,"cameraId",camera),start=with(identity,"session","session1","watchId","watch1","mode","fresh","trustedCamera",true,"cursor",cursor());
        yes(Boolean.FALSE.equals(call(projects,"project.live.state",identity).get("exists")));
        final SharedProjects first=projects;Map<String,Object> noDefault=call(first,"project.live.start",start);yes(Boolean.TRUE.equals(noDefault.get("active")));
        call(first,"project.live.stop",with(start,"token",noDefault.get("token")));
        Path incoming=root.resolve("incoming.ncp");Files.write(incoming,NcpCompatibilityFixtures.ncp());
        Map<String,Object> imported=SharedJson.object(runtime.request("library.import",SharedJson.encode(SharedRuntime.map("path",incoming.toString(),"name","现场预设.ncp"))));String preset=(String)SharedRuntime.object(imported.get("record")).get("id");
        call(projects,"project.setPreset",SharedRuntime.map("projectId",id,"presetId",preset));
        Map<String,Object> active=call(projects,"project.live.start",start);yes(Boolean.TRUE.equals(active.get("active")));yes(rows(SharedRuntime.object(active.get("cursor")),"baseline").size()==1);
        Map<String,Object> lease=with(identity,"session","session1","watchId","watch1","token",active.get("token"));
        byte[] jpeg={(byte)255,(byte)216,1,2,3,4,(byte)255,(byte)217};String sha=PhotoEditStore.hash(jpeg);Path source=root.resolve("originals/"+sha+".jpg");Files.write(source,jpeg);
        String key=hash("capture-101");Map<String,Object> item=candidate(key,101,jpeg.length);
        Map<String,Object> observed=call(projects,"project.live.observe",with(lease,"items",Arrays.asList(item),"baselineUpdates",Arrays.asList(SharedRuntime.map("storage",1,"handle",100,"objectKey",hash("baseline100"))),"initializedStorages",Arrays.asList(1)));
        yes(rows(observed,"pending").size()==1);yes(rows(observed,"pending").get(0).get("presetId").equals(preset));yes(rows(SharedRuntime.object(observed.get("cursor")),"pending").size()==1);
        yes(rows(call(projects,"project.live.observe",with(lease,"items",Arrays.asList(item,item))),"pending").size()==1);
        Map<String,Object> receipt=with(lease,"objectKey",key,"storage",1,"handle",101,"name",item.get("name"),"path",source.toString(),"sha256",sha,"bytes",jpeg.length,"raw",false);
        rejects(()->call(first,"project.live.commit",with(receipt,"session","stale")));rejects(()->call(first,"project.live.commit",with(receipt,"watchId","stale")));rejects(()->call(first,"project.live.commit",with(receipt,"handle",102)));
        rejects(()->call(first,"project.live.commit",with(receipt,"sha256",hash("wrong"))));rejects(()->call(first,"project.live.commit",with(receipt,"bytes",jpeg.length+1)));rejects(()->call(first,"project.live.commit",with(receipt,"raw",true)));
        rejects(()->call(first,"project.live.commit",with(receipt,"owner","someone-else")));
        Path outside=temporary.resolve("outside.jpg");Files.write(outside,jpeg);rejects(()->call(first,"project.live.commit",with(receipt,"path",outside.toString())));
        // Removing the library item and changing current defaults cannot change an observed capture.
        runtime.request("library.remove",SharedJson.encode(SharedRuntime.map("id",preset)));call(projects,"project.setPreset",SharedRuntime.map("projectId",id,"presetId",""));
        Map<String,Object> committed=call(projects,"project.live.commit",receipt);yes(((Number)committed.get("completedCount")).intValue()==1);yes(rows(committed,"pending").isEmpty());yes(((Number)committed.get("queuedCount")).intValue()==1);
        Map<String,Object> opened=call(projects,"project.open",SharedRuntime.map("projectId",id));yes(((Number)opened.get("photoCount")).intValue()==1);yes(rows(opened,"tasks").size()==1);yes(rows(opened,"tasks").get(0).get("presetId").equals(preset));
        yes(((Number)call(projects,"project.live.commit",receipt).get("completedCount")).intValue()==1);yes(rows(call(projects,"project.open",SharedRuntime.map("projectId",id)),"tasks").size()==1);
        yes(((List<?>)call(projects,"project.live.observe",with(lease,"items",Arrays.asList(item))).get("acknowledged")).equals(Arrays.asList(key)));
        yes(Arrays.equals(jpeg,Files.readAllBytes(source)));
        // A different object with exactly the same JPEG must not add a second task or original.
        runtime.request("library.import",SharedJson.encode(SharedRuntime.map("path",incoming.toString(),"name","现场预设.ncp")));
        call(projects,"project.setPreset",SharedRuntime.map("projectId",id,"presetId",preset));String duplicateKey=hash("capture-102");Map<String,Object> duplicate=candidate(duplicateKey,102,jpeg.length);
        call(projects,"project.live.observe",with(lease,"items",Arrays.asList(duplicate)));call(projects,"project.live.commit",with(receipt,"objectKey",duplicateKey,"handle",102,"name",duplicate.get("name")));
        yes(((Number)call(projects,"project.open",SharedRuntime.map("projectId",id)).get("photoCount")).intValue()==1);yes(rows(call(projects,"project.open",SharedRuntime.map("projectId",id)),"tasks").size()==1);
        // Unknown objects and changed data under an existing object key never enter a project.
        rejects(()->call(first,"project.live.commit",with(receipt,"objectKey",hash("never-observed"))));rejects(()->call(first,"project.live.observe",with(lease,"items",Arrays.asList(with(item,"name","different.JPG")))));
        Map<String,Object> next=candidate(hash("capture-103"),103,jpeg.length);call(projects,"project.live.observe",with(lease,"items",Arrays.asList(next)));
        call(projects,"project.live.failed",with(lease,"objectKey",next.get("objectKey"),"error","网络连接中断"));yes(((Number)call(projects,"project.live.state",identity).get("failedCount")).intValue()==1);
        SharedProjects recovered=new SharedProjects(runtime(root));Map<String,Object> recoveredState=call(recovered,"project.live.state",identity);yes(Boolean.TRUE.equals(recoveredState.get("active")));yes(recoveredState.get("token").equals(""));yes(rows(recoveredState,"pending").size()==1);
        final SharedProjects reopened=recovered;rejects(()->call(reopened,"project.live.commit",receipt));
        Map<String,Object> normalizedCursor=with(SharedRuntime.object(recoveredState.get("cursor")),"baseline",Arrays.asList(rows(SharedRuntime.object(recoveredState.get("cursor")),"baseline").get(0),SharedRuntime.map("storage",2,"handle",200,"objectKey",hash("new-readable-card"))),"initializedStorages",Arrays.asList(1,2));
        Map<String,Object> resumed=call(recovered,"project.live.start",with(start,"mode","resume","session","session2","watchId","watch2","cursor",normalizedCursor));yes(!resumed.get("token").equals(active.get("token")));yes(((Number)resumed.get("completedCount")).intValue()==2);yes(rows(SharedRuntime.object(resumed.get("cursor")),"baseline").get(0).containsKey("objectKey"));
        Map<String,Object> persistedAgain=call(new SharedProjects(runtime(root)),"project.live.state",identity);yes(rows(SharedRuntime.object(persistedAgain.get("cursor")),"baseline").size()==2);yes(((List<?>)SharedRuntime.object(persistedAgain.get("cursor")).get("initializedStorages")).size()==2);
        Map<String,Object> secondResume=call(recovered,"project.live.start",with(start,"mode","resume","session","session2b","watchId","watch2b","cursor",persistedAgain.get("cursor")));yes(rows(SharedRuntime.object(secondResume.get("cursor")),"baseline").get(1).get("objectKey").equals(hash("new-readable-card")));
        rejects(()->call(reopened,"project.live.commit",receipt));Map<String,Object> newLease=with(identity,"session","session2b","watchId","watch2b","token",secondResume.get("token"));
        call(recovered,"project.live.observe",with(newLease,"items",Arrays.asList(),"unavailable",Arrays.asList(SharedRuntime.map("objectKey",next.get("objectKey"),"reason","changed"))));yes(((Number)call(recovered,"project.live.state",identity).get("failedCount")).intValue()==1);
        Map<String,Object> authorizedAgain=call(recovered,"project.live.observe",with(newLease,"items",Arrays.asList(next)));yes(((Number)authorizedAgain.get("failedCount")).intValue()==0);yes(rows(authorizedAgain,"pending").get(0).get("status").equals("waiting"));
        call(recovered,"project.live.stop",newLease);yes(Boolean.FALSE.equals(call(recovered,"project.live.state",identity).get("active")));rejects(()->call(reopened,"project.live.start",with(start,"mode","resume","session","session3","watchId","watch3")));rejects(()->call(reopened,"project.live.observe",with(newLease,"items",Arrays.asList(item))));
        rejects(()->reopened.request("project.live.start",start,()->true));
        // Cursor storage removal is committed with the same durable observation boundary.
        Map<String,Object> fresh=call(recovered,"project.live.start",with(start,"session","session4","watchId","watch4"));Map<String,Object> freshLease=with(identity,"session","session4","watchId","watch4","token",fresh.get("token"));
        Map<String,Object> removed=call(recovered,"project.live.observe",with(freshLease,"items",Arrays.asList(),"baselineRemoved",Arrays.asList(SharedRuntime.map("storage",1,"handle",100)),"initializedStorages",Arrays.asList(1,2)));yes(rows(SharedRuntime.object(removed.get("cursor")),"baseline").isEmpty());
        Map<String,Object> untrustedStart=with(start,"cameraId",hash("session-only-camera"),"trustedCamera",false);Map<String,Object> untrusted=call(recovered,"project.live.start",untrustedStart);yes(Boolean.TRUE.equals(untrusted.get("active")));rejects(()->call(reopened,"project.live.start",with(untrustedStart,"mode","resume")));
        // The standalone intent journal proves recovery across a failure after a durable intent.
        intentRecovery(temporary);
        largeCursor(temporary);
        noDefaultOriginals(temporary);
        System.out.println("PASS "+checks+" live ingest checks; durable cursors, explicit resume/stop, source receipts, frozen defaults, duplicate-source suppression and intent recovery");return checks;
    }
    private static void intentRecovery(Path temporary)throws Exception{
        Path root=temporary.resolve("intent-runtime");Files.createDirectories(root);SharedLiveIngest journal=new SharedLiveIngest(root.toFile());String project="12345678-1234-1234-1234-123456789012",camera=hash("intent-camera");
        Map<String,Object> start=SharedRuntime.map("cameraId",camera,"session","one","watchId","one","mode","fresh","trustedCamera",true,"cursor",cursor());
        final int[] applied={0};final boolean[] fail={true};
        SharedLiveIngest.Project sink=new SharedLiveIngest.Project(){public Map<String,Object> preset(){return SharedRuntime.map("presetId",hash("preset"),"presetName","Frozen");}public void validate(Map<String,Object> item,Map<String,Object> receipt){}public String apply(Map<String,Object> item,Map<String,Object> receipt)throws IOException{applied[0]++;if(fail[0])throw new IOException("Simulated crash after durable receive intent");return "task";}};
        Map<String,Object> active=journal.request("project.live.start","",project,start,()->false,sink),lease=with(start,"token",active.get("token"));String key=hash("intent-object");Map<String,Object> item=candidate(key,101,8);journal.request("project.live.observe","",project,with(lease,"items",Arrays.asList(item)),()->false,sink);
        rejects(()->journal.request("project.live.commit","",project,with(lease,"objectKey",key,"storage",1,"handle",101,"name",item.get("name"),"bytes",8,"sha256",hash("jpeg"),"path","ignored.jpg"),()->false,sink));yes(applied[0]==1);
        fail[0]=false;Map<String,Object> changed=journal.request("project.live.observe","",project,with(lease,"items",Arrays.asList(candidate(hash("intent-handle-reused"),101,9))),()->false,sink);yes(applied[0]==2);yes(((Number)changed.get("completedCount")).intValue()==1);yes(rows(SharedRuntime.object(changed.get("cursor")),"pending").size()==1);
        SharedLiveIngest recovered=new SharedLiveIngest(root.toFile());Map<String,Object> result=recovered.request("project.live.start","",project,with(start,"mode","resume","session","two","watchId","two","cursor",changed.get("cursor")),()->false,sink);yes(applied[0]==2);yes(((Number)result.get("completedCount")).intValue()==1);
        Map<String,Object> state=recovered.request("project.live.state","",project,SharedRuntime.map("cameraId",camera),()->false,sink);yes(((Number)state.get("completedCount")).intValue()==1);
        Path journalFile=root.resolve("shared-live-ingest/"+hash("")+"/"+project+"/"+camera+".json");byte[] bytes=Files.readAllBytes(journalFile);bytes[bytes.length/2]^=1;Files.write(journalFile,bytes);rejects(()->recovered.request("project.live.state","",project,SharedRuntime.map("cameraId",camera),()->false,sink));
    }
    private static void noDefaultOriginals(Path temporary)throws Exception{
        Path root=temporary.resolve("no-default-runtime");Files.createDirectories(root);SharedRuntime runtime=runtime(root);SharedProjects projects=new SharedProjects(runtime);
        String id=(String)call(projects,"project.create",SharedRuntime.map("name","仅接收原图")).get("id"),camera=hash("originals-first-camera");
        Map<String,Object> identity=SharedRuntime.map("projectId",id,"cameraId",camera),start=with(identity,"session","originals1","watchId","originals1","mode","fresh","trustedCamera",true,"cursor",cursor());
        Map<String,Object> active=call(projects,"project.live.start",start),lease=with(identity,"session","originals1","watchId","originals1","token",active.get("token"));yes(Boolean.TRUE.equals(active.get("active")));
        byte[][] bytes={{(byte)255,(byte)216,1,2,3,4,(byte)255,(byte)217},{(byte)255,(byte)216,5,6,7,8,(byte)255,(byte)217},{(byte)255,(byte)216,9,10,11,12,(byte)255,(byte)217}};
        String[] keys={hash("no-default-A"),hash("with-default-B"),hash("no-default-C")},shas=new String[3];Path[] sources=new Path[3];
        for(int i=0;i<3;i++){shas[i]=PhotoEditStore.hash(bytes[i]);sources[i]=root.resolve("originals/"+shas[i]+".jpg");Files.write(sources[i],bytes[i]);}
        Map<String,Object> a=candidate(keys[0],101,8),b=candidate(keys[1],102,8),c=candidate(keys[2],103,8);
        Map<String,Object> observed=call(projects,"project.live.observe",with(lease,"items",Arrays.asList(a)));yes(rows(observed,"pending").get(0).get("presetId").equals(""));yes(rows(observed,"pending").get(0).get("presetName").equals(""));
        Path incoming=root.resolve("incoming.ncp");Files.write(incoming,NcpCompatibilityFixtures.ncp());Map<String,Object> imported=SharedJson.object(runtime.request("library.import",SharedJson.encode(SharedRuntime.map("path",incoming.toString(),"name","之后拍摄才套用.ncp"))));String preset=(String)SharedRuntime.object(imported.get("record")).get("id");call(projects,"project.setPreset",SharedRuntime.map("projectId",id,"presetId",preset));
        Map<String,Object> both=call(projects,"project.live.observe",with(lease,"items",Arrays.asList(b)));yes(rows(both,"pending").get(0).get("presetId").equals(""));yes(rows(both,"pending").get(1).get("presetId").equals(preset));
        Map<String,Object> receiptA=with(lease,"objectKey",keys[0],"storage",1,"handle",101,"name",a.get("name"),"path",sources[0].toString(),"sha256",shas[0],"bytes",8,"raw",false);
        Map<String,Object> completedA=call(projects,"project.live.commit",receiptA);yes(((Number)completedA.get("completedCount")).intValue()==1);yes(((Number)completedA.get("queuedCount")).intValue()==0);Map<String,Object> projectA=call(projects,"project.open",SharedRuntime.map("projectId",id));yes(((Number)projectA.get("photoCount")).intValue()==1);yes(rows(projectA,"tasks").isEmpty());
        call(projects,"project.live.commit",receiptA);yes(rows(call(projects,"project.open",SharedRuntime.map("projectId",id)),"tasks").isEmpty());
        call(projects,"project.live.commit",with(receiptA,"objectKey",keys[1],"handle",102,"name",b.get("name"),"path",sources[1].toString(),"sha256",shas[1]));Map<String,Object> afterB=call(projects,"project.open",SharedRuntime.map("projectId",id));yes(((Number)afterB.get("photoCount")).intValue()==2);yes(rows(afterB,"tasks").size()==1);yes(rows(afterB,"tasks").get(0).get("identity").equals(shas[1]));
        call(projects,"project.setPreset",SharedRuntime.map("projectId",id,"presetId",""));Map<String,Object> pendingC=call(projects,"project.live.observe",with(lease,"items",Arrays.asList(c)));yes(rows(pendingC,"pending").get(0).get("presetId").equals(""));
        SharedProjects recovered=new SharedProjects(runtime(root));Map<String,Object> state=call(recovered,"project.live.state",identity);yes(rows(state,"pending").get(0).get("presetId").equals(""));Map<String,Object> resumed=call(recovered,"project.live.start",with(start,"mode","resume","session","originals2","watchId","originals2","cursor",state.get("cursor")));Map<String,Object> newLease=with(identity,"session","originals2","watchId","originals2","token",resumed.get("token"));
        Map<String,Object> done=call(recovered,"project.live.commit",with(receiptA,"session","originals2","watchId","originals2","token",resumed.get("token"),"objectKey",keys[2],"handle",103,"name",c.get("name"),"path",sources[2].toString(),"sha256",shas[2]));yes(((Number)done.get("completedCount")).intValue()==3);yes(rows(done,"pending").isEmpty());Map<String,Object> all=call(recovered,"project.open",SharedRuntime.map("projectId",id));yes(((Number)all.get("photoCount")).intValue()==3);yes(rows(all,"tasks").size()==1);yes(all.get("presetId").equals(""));
        yes(((List<?>)call(recovered,"project.live.observe",with(newLease,"items",Arrays.asList(a,b,c))).get("acknowledged")).size()==3);yes(rows(call(new SharedProjects(runtime(root)),"project.open",SharedRuntime.map("projectId",id)),"tasks").size()==1);
        for(int i=0;i<3;i++)yes(Arrays.equals(bytes[i],Files.readAllBytes(sources[i])));
        call(recovered,"project.live.stop",newLease);Map<String,Object> fresh=call(recovered,"project.live.start",with(start,"session","originals3","watchId","originals3"));yes(Boolean.TRUE.equals(fresh.get("active")));yes(((Number)fresh.get("completedCount")).intValue()==3);
    }
    @SuppressWarnings("unchecked") private static void largeCursor(Path temporary)throws Exception{
        Path root=temporary.resolve("large-cursor");Files.createDirectories(root);SharedLiveIngest journal=new SharedLiveIngest(root.toFile());String project="12345678-1234-1234-1234-123456789012",camera=hash("large-camera");
        SharedLiveIngest.Project sink=new SharedLiveIngest.Project(){public Map<String,Object> preset(){return SharedRuntime.map("presetId",hash("preset"),"presetName","Frozen");}public void validate(Map<String,Object> item,Map<String,Object> receipt){}public String apply(Map<String,Object> item,Map<String,Object> receipt){return "task";}};
        List<Object> first=new java.util.ArrayList<>(),pages=new java.util.ArrayList<>(),page=first;
        for(int i=1;i<=20000;i++){if(i>1&&(i-1)%1000==0){page=new java.util.ArrayList<>();pages.add(page);}page.add(SharedRuntime.map("storage",1,"handle",i));}
        Map<String,Object> start=SharedRuntime.map("cameraId",camera,"session","one","watchId","one","mode","fresh","trustedCamera",true,"cursor",SharedRuntime.map("baseline",first,"baselinePages",pages,"initializedStorages",Arrays.asList(1)));
        Map<String,Object> active=journal.request("project.live.start","",project,start,()->false,sink);Map<String,Object> savedCursor=SharedRuntime.object(active.get("cursor"));yes(((Number)savedCursor.get("baselineCount")).intValue()==20000);yes(((List<?>)savedCursor.get("baseline")).size()==1000);yes(((List<?>)savedCursor.get("baselinePages")).size()==19);
        // The preserved strict JSON codec caps each array/object at4096. Paginated
        // 20k inventory must survive both bridge serialization and disk recovery.
        SharedJson.object(SharedJson.encode(active));SharedLiveIngest recovered=new SharedLiveIngest(root.toFile());Map<String,Object> state=recovered.request("project.live.state","",project,SharedRuntime.map("cameraId",camera),()->false,sink);yes(((Number)SharedRuntime.object(state.get("cursor")).get("baselineCount")).intValue()==20000);
        Map<String,Object> lease=with(start,"token",active.get("token")),full=SharedRuntime.map("baseline",Arrays.asList(SharedRuntime.map("storage",2,"handle",999)),"initializedStorages",Arrays.asList(1,2));
        Map<String,Object> updated=journal.request("project.live.observe","",project,with(lease,"cursor",full,"items",Arrays.asList()),()->false,sink);yes(((Number)SharedRuntime.object(updated.get("cursor")).get("baselineCount")).intValue()==1);
        // A journal containing more than4096 completion receipts is encoded in
        // bounded object pages as well, never as one unparseable JSON object.
        String sourceSha=hash("same-owned-jpeg");Map<String,Object> data=SharedRuntime.map("schema",1,"projectId",project,"cameraId",camera,"trustedCamera",true,"active",true,"session","one","watchId","one","cursor",cursor(),"entries",new java.util.LinkedHashMap<String,Object>(),"entryPages",new java.util.ArrayList<>());
        Map<String,Object> entries=SharedRuntime.object(data.get("entries")),entryPage=entries;List<Object> entryPages=(List<Object>)data.get("entryPages");
        for(int i=0;i<4200;i++){if(i>0&&i%1000==0){entryPage=new java.util.LinkedHashMap<>();entryPages.add(entryPage);}String key=hash("completed-"+i);entryPage.put(key,with(candidate(key,i+1,8),"presetId",hash("preset"),"presetName","Frozen","status","done","error","","taskKey","task","sha256",sourceSha,"sourceFileName",sourceSha+".jpg"));}
        String payload=SharedJson.encode(data);Path journalFile=root.resolve("shared-live-ingest/"+hash("")+"/"+project+"/"+camera+".json");Files.write(journalFile,SharedJson.encode(SharedRuntime.map("payload",payload,"sha256",hash(payload))).getBytes(StandardCharsets.UTF_8));
        Map<String,Object> many=recovered.request("project.live.state","",project,SharedRuntime.map("cameraId",camera),()->false,sink);yes(((Number)many.get("completedCount")).intValue()==4200);
        Map<String,Object> resumed=recovered.request("project.live.start","",project,with(start,"mode","resume","session","two","watchId","two","cursor",many.get("cursor")),()->false,sink);yes(((Number)new SharedLiveIngest(root.toFile()).request("project.live.state","",project,SharedRuntime.map("cameraId",camera),()->false,sink).get("completedCount")).intValue()==4200);
        Map<String,Object> liveLease=with(start,"session","two","watchId","two","token",resumed.get("token"));
        for(int offset=0;offset<128;offset+=60){List<Object> items=new java.util.ArrayList<>();for(int i=offset;i<Math.min(offset+60,128);i++)items.add(candidate(hash("pending-"+i),5000+i,8));recovered.request("project.live.observe","",project,with(liveLease,"items",items),()->false,sink);}
        Map<String,Object> fullQueue=recovered.request("project.live.state","",project,SharedRuntime.map("cameraId",camera),()->false,sink);yes(rows(fullQueue,"pending").size()==128);yes(rows(SharedRuntime.object(fullQueue.get("cursor")),"pending").size()==128);
        rejects(()->recovered.request("project.live.observe","",project,with(liveLease,"items",Arrays.asList(candidate(hash("pending-overflow"),6000,8))),()->false,sink));yes(rows(recovered.request("project.live.state","",project,SharedRuntime.map("cameraId",camera),()->false,sink),"pending").size()==128);
        List<Object> unavailable=new java.util.ArrayList<>();for(int i=0;i<128;i++)unavailable.add(SharedRuntime.map("objectKey",hash("pending-"+i),"reason","missing"));
        Map<String,Object> missing=recovered.request("project.live.observe","",project,with(liveLease,"items",Arrays.asList(),"unavailable",unavailable),()->false,sink);yes(((Number)missing.get("failedCount")).intValue()==128);yes(rows(SharedRuntime.object(missing.get("cursor")),"pending").isEmpty());
        Map<String,Object> restarted=recovered.request("project.live.start","",project,with(start,"session","three","watchId","three","cursor",cursor()),()->false,sink);Map<String,Object> newLease=with(start,"session","three","watchId","three","token",restarted.get("token"));
        String oldKey=hash("old-pending-handle"),newKey=hash("new-pending-handle");Map<String,Object> oldItem=candidate(oldKey,101,8),newItem=candidate(newKey,101,9);
        recovered.request("project.live.observe","",project,with(newLease,"items",Arrays.asList(oldItem)),()->false,sink);Map<String,Object> reused=recovered.request("project.live.observe","",project,with(newLease,"items",Arrays.asList(newItem)),()->false,sink);
        yes(rows(reused,"pending").size()==2);yes(((Number)reused.get("failedCount")).intValue()==1);List<Map<String,Object>> hints=rows(SharedRuntime.object(reused.get("cursor")),"pending");yes(hints.size()==1&&hints.get(0).get("objectKey").equals(newKey));
        Map<String,Object> afterReconnect=new SharedLiveIngest(root.toFile()).request("project.live.start","",project,with(start,"mode","resume","session","four","watchId","four","cursor",reused.get("cursor")),()->false,sink);yes(rows(SharedRuntime.object(afterReconnect.get("cursor")),"pending").size()==1);yes(rows(SharedRuntime.object(afterReconnect.get("cursor")),"pending").get(0).get("objectKey").equals(newKey));
        rejects(()->recovered.request("project.live.observe","",project,with(newLease,"items",Arrays.asList(newItem)),()->false,sink));
        Map<String,Object> invalidCursor=SharedRuntime.map("baseline",Arrays.asList(SharedRuntime.map("storage",1,"handle",1),SharedRuntime.map("storage",1,"handle",1)),"initializedStorages",Arrays.asList(1));
        rejects(()->recovered.request("project.live.start","",project,with(start,"cursor",invalidCursor),()->false,sink));
    }
    public static void main(String[] args)throws Exception{
        Path temporary=Files.createTempDirectory("huevia-live-ingest-boundary-");
        try{run(temporary);}finally{Path system=Paths.get(System.getProperty("java.io.tmpdir")).toRealPath();if(!temporary.toRealPath().getParent().equals(system)||!temporary.getFileName().toString().startsWith("huevia-live-ingest-boundary-"))throw new IOException("Test cleanup path invalid");try(java.util.stream.Stream<Path> paths=Files.walk(temporary)){for(Path path:(Iterable<Path>)paths.sorted(Comparator.reverseOrder())::iterator)Files.delete(path);}}
    }
}
