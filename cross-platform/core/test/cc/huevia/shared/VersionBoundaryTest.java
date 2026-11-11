package cc.huevia.shared;

import cc.huevia.account.AccountRepository;
import cc.huevia.album.*;
import cc.huevia.library.SharedJson;
import java.io.*;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.atomic.AtomicInteger;

/** Storage/recipe transactions; real JPEG pixels are checked separately on device. */
public final class VersionBoundaryTest {
    private static int checks;
    private interface Action{void run()throws Exception;}
    private static void yes(boolean value){checks++;if(!value)throw new AssertionError("Version boundary "+checks);}
    private static void rejects(Action action)throws Exception{checks++;try{action.run();}catch(IOException expected){return;}throw new AssertionError("Invalid version accepted");}
    private static final class Store implements AccountRepository.Store{public byte[] read(){return null;}public void write(byte[] data){}public void clear(){}}
    private static SharedRuntime runtime(Path root)throws IOException{return new SharedRuntime(root.toString(),new Store(),(m,p,t,b)->{throw new AssertionError("Version operation used network");});}
    private static Map<String,Object> call(SharedRuntime r,String op,Object... values)throws IOException{return SharedJson.object(r.request(op,SharedJson.encode(SharedRuntime.map(values))));}
    private static File output(Path root,String name)throws IOException{Path file=Files.createDirectories(root.resolve("exports")).resolve(name+".jpg");Files.write(file,new byte[]{(byte)255,(byte)216,1,2,3,4,(byte)255,(byte)217});return file.toFile();}
    private static Map<String,Object> detail(PhotoEditStore.Draft frozen,PhotoExportSpec spec)throws IOException{PhotoExportSpec.Resolved resolved=spec.resolve(1200,800);return SharedRuntime.map("width",resolved.width,"height",resolved.height,"model",SharedExportModel.of(frozen.profile(),resolved),"exportSpec",resolved.identity());}
    public static int run(Path temporary)throws Exception{
        checks=0;Path root=temporary.resolve("version-boundary");SharedRuntime r=runtime(root);
        Path source=Files.createDirectories(root.resolve("originals")).resolve("source.jpg");byte[] original={10,20,30,40};Files.write(source,original);
        Path preset=root.resolve("fixture.ncp");Files.write(preset,cc.huevia.ncp.NcpCompatibilityFixtures.ncp());
        Map<String,Object> added=call(r,"library.import","owner","","name","fixture.ncp","path",preset.toString());
        String presetId=(String)((Map<?,?>)added.get("record")).get("id");
        PhotoEditStore.Draft frozen=r.freezeEdit(source.toString(),"",SharedJson.encode(SharedRuntime.map("presetId",presetId,"strength",70,"geometry",SharedRuntime.map("turns",1))));
        Map<String,Object> full=detail(frozen,PhotoExportSpec.full());File first=output(root,"first");
        Map<String,Object> saved=SharedJson.object(r.commitVersion(source.toString(),"",frozen,first.getPath(),SharedJson.encode(full),()->false));
        String id=(String)saved.get("id");File image=new File((String)saved.get("path"));
        yes(image.isFile()&&!first.exists()&&Boolean.FALSE.equals(saved.get("reused")));
        yes(image.getName().equals("effect-"+SharedVersions.key(frozen,(String)full.get("model"))+"__Effect.JPG"));
        yes(((List<?>)call(r,"version.list","owner","","path",source.toString()).get("items")).size()==1);
        yes(call(r,"version.open","owner","","id",id).get("sha256").equals(saved.get("sha256")));
        File duplicate=output(root,"duplicate");Map<String,Object> reused=SharedJson.object(r.commitVersion(source.toString(),"",frozen,duplicate.getPath(),SharedJson.encode(full),()->false));
        yes(reused.get("path").equals(image.getPath())&&Boolean.TRUE.equals(reused.get("reused"))&&!duplicate.exists());
        File share=output(root,"share");Map<String,Object> second=SharedJson.object(r.commitVersion(source.toString(),"",frozen,share.getPath(),SharedJson.encode(detail(frozen,PhotoExportSpec.share())),()->false));
        yes(!second.get("id").equals(id)&&new File((String)second.get("path")).isFile());
        call(r,"library.remove","owner","","id",presetId);
        PhotoEditStore.Draft current=r.freezeEdit(source.toString(),"","{}");
        Map<String,Object> recovered=call(r,"version.recipe","owner","","id",id);
        yes(((Map<?,?>)recovered.get("recipe")).get("presetId").equals(presetId));
        yes(new PhotoEditStore(root.toFile(),"").read(frozen.sourceSha).identity().equals(current.identity()));
        yes(r.freezeEdit(source.toString(),"",SharedJson.encode(recovered.get("recipe"))).identity().equals(frozen.identity()));
        rejects(()->call(r,"version.list","owner","alice"));rejects(()->call(r,"version.delete","owner","alice","id",id));
        rejects(()->call(r,"version.open","owner","","id","../originals"));
        File invalid=output(root,"invalid");Map<String,Object> wrong=new LinkedHashMap<>(full);wrong.put("model","wrong-model");
        rejects(()->r.commitVersion(source.toString(),"",frozen,invalid.getPath(),SharedJson.encode(wrong),()->false));yes(invalid.isFile());
        wrong.clear();wrong.putAll(full);wrong.put("width",1);
        rejects(()->r.commitVersion(source.toString(),"",frozen,invalid.getPath(),SharedJson.encode(wrong),()->false));
        Path outsider=root.resolve("other.jpg");Files.copy(invalid.toPath(),outsider);
        rejects(()->r.commitVersion(source.toString(),"",frozen,outsider.toString(),SharedJson.encode(full),()->false));
        File cancelled=output(root,"cancelled");Map<String,Object> custom=detail(frozen,PhotoExportSpec.custom(640,80));AtomicInteger steps=new AtomicInteger();
        rejects(()->r.commitVersion(source.toString(),"",frozen,cancelled.getPath(),SharedJson.encode(custom),()->steps.incrementAndGet()>=5));
        yes(((List<?>)call(r,"version.list","owner","").get("items")).size()==2);
        File ownerDir=image.getParentFile().getParentFile();yes(Arrays.stream(Objects.requireNonNull(ownerDir.list())).noneMatch(name->name.startsWith(".pending-")));
        Files.delete(source);yes(Boolean.FALSE.equals(call(r,"version.open","owner","","id",id).get("sourceAvailable")));
        rejects(()->call(r,"version.recipe","owner","","id",id));Files.write(source,new byte[]{11,20,30,40});
        rejects(()->call(r,"version.recipe","owner","","id",id));
        rejects(()->r.commitVersion(source.toString(),"",frozen,invalid.getPath(),SharedJson.encode(full),()->false));Files.write(source,original);
        byte[] encoded=Files.readAllBytes(image.toPath());encoded[2]^=1;Files.write(image.toPath(),encoded);
        rejects(()->call(r,"version.open","owner","","id",id));
        File attempt=output(root,"attempt");rejects(()->r.commitVersion(source.toString(),"",frozen,attempt.getPath(),SharedJson.encode(full),()->false));
        yes(Files.readAllBytes(image.toPath())[2]==encoded[2]);
        call(r,"version.delete","owner","","id",id);yes(!image.exists()&&Arrays.equals(Files.readAllBytes(source),original));
        yes(((List<?>)call(r,"version.list","owner","").get("items")).size()==1);
        // Paths in saved records survive an application-container relocation.
        Path relocated=temporary.resolve("relocated-versions");Files.move(root,relocated);SharedRuntime restored=runtime(relocated);
        Map<String,Object> moved=call(restored,"version.open","owner","","id",second.get("id"));
        // macOS temp roots can be aliases (/var -> /private/var). Runtime paths
        // deliberately use the canonical container, on both JVM and Apple.
        Path canonicalRelocated=relocated.toFile().getCanonicalFile().toPath();
        yes(new File((String)moved.get("path")).toPath().startsWith(canonicalRelocated)&&new File((String)moved.get("sourcePath")).toPath().startsWith(canonicalRelocated));
        Path record=new File((String)moved.get("path")).getParentFile().toPath().resolve("manifest.json");Files.writeString(record,"{}");
        List<?> damaged=(List<?>)call(restored,"version.list","owner","").get("items");yes(damaged.size()==1&&((Map<?,?>)damaged.get(0)).containsKey("error"));
        call(restored,"version.delete","owner","","id",second.get("id"));yes(((List<?>)call(restored,"version.list","owner","").get("items")).isEmpty());
        Path snapshotRoot=temporary.resolve("version-inactive-state");SharedRuntime snapshots=runtime(snapshotRoot);
        Path snapshotSource=Files.createDirectories(snapshotRoot.resolve("originals")).resolve("source.jpg");Files.write(snapshotSource,original);
        PhotoEditStore.Draft neutral=snapshots.freezeEdit(snapshotSource.toString(),"","{}"),inactive=snapshots.freezeEdit(snapshotSource.toString(),"",SharedJson.encode(SharedRuntime.map("palette",SharedRuntime.map("color",25,"amount",0))));
        yes(neutral.profile().modelVersion().equals(inactive.profile().modelVersion())&&!neutral.identity().equals(inactive.identity()));
        Map<String,Object> neutralSaved=SharedJson.object(snapshots.commitVersion(snapshotSource.toString(),"",neutral,output(snapshotRoot,"neutral").getPath(),SharedJson.encode(detail(neutral,PhotoExportSpec.full())),()->false));
        Map<String,Object> inactiveSaved=SharedJson.object(snapshots.commitVersion(snapshotSource.toString(),"",inactive,output(snapshotRoot,"inactive").getPath(),SharedJson.encode(detail(inactive,PhotoExportSpec.full())),()->false));
        yes(neutralSaved.get("effectKey").equals(inactiveSaved.get("effectKey"))&&!neutralSaved.get("id").equals(inactiveSaved.get("id")));
        Map<?,?> inactiveRecipe=(Map<?,?>)call(snapshots,"version.recipe","owner","","id",inactiveSaved.get("id")).get("recipe");
        yes(((Number)((Map<?,?>)inactiveRecipe.get("palette")).get("color")).intValue()==25&&((Number)((Map<?,?>)inactiveRecipe.get("palette")).get("amount")).intValue()==0);
        yes(((List<?>)call(snapshots,"version.list","owner","").get("items")).size()==2);
        return checks;
    }
}
