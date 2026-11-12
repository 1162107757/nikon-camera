package cc.huevia.shared;

import cc.huevia.account.AccountRepository;
import cc.huevia.album.PhotoEditStore;
import cc.huevia.library.SharedJson;
import cc.huevia.ncp.NcpCompatibilityFixtures;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.Arrays;
import java.util.Comparator;
import java.util.List;
import java.util.Map;

/** Real catalogs and original binary journals, without a camera or renderer mock success. */
public final class ProjectBoundaryTest {
    private static int checks;
    private static void yes(boolean value){checks++;if(!value)throw new AssertionError("Project boundary "+checks);}
    private interface Action{void run()throws Exception;}
    private static void rejects(Action action)throws Exception{checks++;try{action.run();}catch(IOException expected){return;}throw new AssertionError("Invalid project operation accepted");}
    private static final class Store implements AccountRepository.Store {
        public byte[] read(){return null;}public void write(byte[] value){}public void clear(){}
    }
    private static SharedRuntime runtime(Path root)throws IOException{return new SharedRuntime(root.toString(),new Store(),(method,path,token,data)->{throw new IOException("Offline test");});}
    private static Map<String,Object> call(SharedProjects projects,String operation,Map<String,Object> p)throws IOException{return projects.request(operation,p,()->false);}
    @SuppressWarnings("unchecked") private static List<Map<String,Object>> rows(Map<String,Object> value,String key){return (List<Map<String,Object>>)(List<?>)value.get(key);}
    public static int run(Path temporary)throws Exception {
        checks=0;Path root=temporary.resolve("project-runtime");Files.createDirectories(root);
        SharedRuntime runtime=runtime(root);SharedProjects projects=new SharedProjects(runtime);
        Map<String,Object> project=call(projects,"project.create",SharedRuntime.map("name","拍摄项目 A"));String id=(String)project.get("id");
        rejects(()->call(projects,"project.create",SharedRuntime.map("name","../outside")));
        yes(rows(call(projects,"project.list",SharedRuntime.map()),"items").size()==1);
        Map<String,Object> renamed=call(projects,"project.rename",SharedRuntime.map("projectId",id,"name","拍摄项目 B"));yes(renamed.get("id").equals(id));yes(renamed.get("createdAt").equals(project.get("createdAt")));
        byte[] jpeg={(byte)255,(byte)216,10,20,30,40,(byte)255,(byte)217};String originalSha=PhotoEditStore.hash(jpeg);
        Path source=root.resolve("originals/"+originalSha+".jpg");Files.write(source,jpeg);
        Map<String,Object> add=SharedRuntime.map("projectId",id,"path",source.toString(),"name","DSC_0123.JPG");
        yes(((Number)call(projects,"project.add",add).get("photoCount")).intValue()==1);
        yes(((Number)call(projects,"project.add",add).get("photoCount")).intValue()==1);
        Path bad=root.resolve("originals/bad.jpg");Files.write(bad,new byte[]{1,2,3,4});rejects(()->call(projects,"project.add",SharedRuntime.map("projectId",id,"path",bad.toString(),"name","bad.jpg")));
        Path outside=temporary.resolve("outside.jpg");Files.write(outside,jpeg);rejects(()->call(projects,"project.add",SharedRuntime.map("projectId",id,"path",outside.toString(),"name","outside.jpg")));
        byte[] preset=NcpCompatibilityFixtures.ncp();Path incoming=root.resolve("incoming.ncp");Files.write(incoming,preset);
        Map<String,Object> imported=SharedJson.object(runtime.request("library.import",SharedJson.encode(SharedRuntime.map("path",incoming.toString(),"name","Frozen project.ncp"))));
        String presetId=(String)SharedRuntime.object(imported.get("record")).get("id");
        call(projects,"project.setPreset",SharedRuntime.map("projectId",id,"presetId",presetId));
        runtime.request("library.remove",SharedJson.encode(SharedRuntime.map("id",presetId)));yes(rows(SharedJson.object(runtime.request("library.list","{}")),"items").isEmpty());
        // The default was frozen before library removal; it still queues the exact bytes.
        Map<String,Object> queued=call(projects,"project.enqueue",SharedRuntime.map("projectId",id));yes(rows(queued,"tasks").size()==1);
        yes(rows(call(projects,"project.enqueue",SharedRuntime.map("projectId",id)),"tasks").size()==1);
        String key=(String)rows(queued,"tasks").get(0).get("key");
        Map<String,Object> begin=call(projects,"project.begin",SharedRuntime.map("projectId",id,"key",key));
        yes(originalSha.equals(begin.get("sourceSha")));yes(rows(call(projects,"project.open",SharedRuntime.map("projectId",id)),"tasks").get(0).get("status").equals("processing"));
        rejects(()->call(projects,"project.begin",SharedRuntime.map("projectId",id,"key",key)));
        rejects(()->call(projects,"project.fail",SharedRuntime.map("projectId",id,"key",key,"lease","stale","error","error")));
        call(projects,"project.fail",SharedRuntime.map("projectId",id,"key",key,"lease",begin.get("lease"),"error","Network interrupted"));
        yes(rows(call(projects,"project.open",SharedRuntime.map("projectId",id)),"tasks").get(0).get("status").equals("error"));
        call(projects,"project.retry",SharedRuntime.map("projectId",id));
        Map<String,Object> interrupted=call(projects,"project.begin",SharedRuntime.map("projectId",id,"key",key));
        // Simulate process restart. Original journal recovery returns processing to queued.
        final SharedProjects recovered=new SharedProjects(runtime);
        yes(rows(call(recovered,"project.open",SharedRuntime.map("projectId",id)),"tasks").get(0).get("status").equals("queued"));
        Map<String,Object> active=call(recovered,"project.begin",SharedRuntime.map("projectId",id,"key",key));
        rejects(()->call(recovered,"project.fail",SharedRuntime.map("projectId",id,"key",key,"lease",interrupted.get("lease"),"error","stale")));
        PhotoEditStore.Draft frozen=runtime.reviewView(source.toString(),"",SharedJson.encode(active.get("recipe")));yes(Arrays.equals(preset,frozen.presetBytes()));
        Files.createDirectories(root.resolve("exports"));Path rendered=root.resolve("exports/owned-result.jpg");Files.write(rendered,jpeg);
        Map<String,Object> details=SharedRuntime.map("width",2,"height",2,"model",frozen.profile().modelVersion()+":full-jpeg95-srgb-v1","exportSpec","jpeg-srgb-v1:2x2:q95:capture-no-gps-v1");
        Map<String,Object> version=SharedJson.object(runtime.commitVersion(source.toString(),"",frozen,rendered.toString(),SharedJson.encode(details),()->false));
        Map<String,Object> finish=SharedRuntime.map("projectId",id,"key",key,"lease",active.get("lease"),"versionId",version.get("id"));
        yes(rows(call(recovered,"project.finish",finish),"tasks").get(0).get("status").equals("saved"));
        yes(rows(call(recovered,"project.finish",finish),"tasks").size()==1); // Lost completion reply is idempotent.
        yes(Boolean.TRUE.equals(call(recovered,"project.begin",SharedRuntime.map("projectId",id,"key",key)).get("done")));
        call(recovered,"project.retry",SharedRuntime.map("projectId",id));yes(rows(call(recovered,"project.open",SharedRuntime.map("projectId",id)),"tasks").get(0).get("status").equals("saved"));
        yes(call(recovered,"project.result",SharedRuntime.map("projectId",id,"key",key)).get("id").equals(version.get("id")));
        yes(Arrays.equals(Files.readAllBytes(source),jpeg));yes(new SharedProjects(runtime(root)).request("project.open",SharedRuntime.map("projectId",id),()->false).get("saved").equals(1));
        byte[] second={(byte)255,(byte)216,50,60,70,80,(byte)255,(byte)217};String secondSha=PhotoEditStore.hash(second);Path secondSource=root.resolve("originals/"+secondSha+".jpg");Files.write(secondSource,second);
        call(recovered,"project.add",SharedRuntime.map("projectId",id,"path",secondSource.toString(),"name","DSC_0124.JPG"));
        List<Map<String,Object>> all=rows(call(recovered,"project.enqueue",SharedRuntime.map("projectId",id)),"tasks");yes(all.size()==2);
        String secondKey=(String)all.stream().filter(row->secondSha.equals(row.get("identity"))).findFirst().orElseThrow().get("key");
        Files.write(secondSource,jpeg);
        rejects(()->call(recovered,"project.begin",SharedRuntime.map("projectId",id,"key",secondKey)));
        List<Map<String,Object>> mixed=rows(call(recovered,"project.open",SharedRuntime.map("projectId",id)),"tasks");yes(mixed.stream().filter(row->row.get("status").equals("saved")).count()==1);yes(mixed.stream().filter(row->row.get("status").equals("error")).count()==1);
        rejects(()->call(recovered,"project.enqueue",SharedRuntime.map("projectId",id))); // Frozen project catalog rejects altered source bytes too.
        Files.write(secondSource,second);call(recovered,"project.retry",SharedRuntime.map("projectId",id));
        Map<String,Object> secondBegin=call(recovered,"project.begin",SharedRuntime.map("projectId",id,"key",secondKey));
        rejects(()->call(recovered,"project.finish",SharedRuntime.map("projectId",id,"key",secondKey,"lease",secondBegin.get("lease"),"versionId",version.get("id"))));
        call(recovered,"project.fail",SharedRuntime.map("projectId",id,"key",secondKey,"lease",secondBegin.get("lease"),"error","Stopped"));
        yes(Arrays.equals(Files.readAllBytes(secondSource),second));
        final SharedProjects current=recovered;
        rejects(()->call(current,"project.open",SharedRuntime.map("projectId",id,"owner","another")));
        call(recovered,"project.setPreset",SharedRuntime.map("projectId",id,"presetId",""));yes(call(recovered,"project.open",SharedRuntime.map("projectId",id)).get("presetId").equals(""));
        rejects(()->call(current,"project.enqueue",SharedRuntime.map("projectId",id)));
        System.out.println("PASS "+checks+" project checks; original catalogs, immutable defaults, library removal, source safety, journal recovery, stale leases and saved-version reuse");return checks;
    }
    public static void main(String[] args)throws Exception{
        Path temporary=Files.createTempDirectory("huevia-project-boundary-");
        try{run(temporary);}finally{
            Path system=Paths.get(System.getProperty("java.io.tmpdir")).toRealPath();
            if(!temporary.toRealPath().getParent().equals(system)||!temporary.getFileName().toString().startsWith("huevia-project-boundary-"))throw new IOException("Test cleanup path invalid");
            try(java.util.stream.Stream<Path> paths=Files.walk(temporary)){for(Path path:(Iterable<Path>)paths.sorted(Comparator.reverseOrder())::iterator)Files.delete(path);}
        }
    }
}
