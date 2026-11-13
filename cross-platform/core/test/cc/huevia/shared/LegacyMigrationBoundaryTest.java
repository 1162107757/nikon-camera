package cc.huevia.shared;

import cc.huevia.account.AccountRepository;
import cc.huevia.album.*;
import cc.huevia.library.*;
import cc.huevia.ncp.NcpCompatibilityFixtures;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.function.BooleanSupplier;
import java.util.zip.*;

/** Real ZIP/filesystem/draft/project transactions, including interruption and changed-data rollback. */
public final class LegacyMigrationBoundaryTest {
    private static int checks;
    private interface Action{void run()throws Exception;}
    private static void yes(boolean value){checks++;if(!value)throw new AssertionError("Legacy migration boundary "+checks);}
    private static void rejects(Action action)throws Exception{checks++;try{action.run();}catch(IOException expected){return;}throw new AssertionError("Unsafe migration accepted");}
    private static final class Store implements AccountRepository.Store {
        public byte[] read(){return null;}public void write(byte[] value){}public void clear(){}
    }
    private static SharedRuntime runtime(Path root)throws IOException{return new SharedRuntime(root.toString(),new Store(),(method,path,token,body)->{throw new AssertionError("Migration used network");});}
    private static Map<String,Object> request(SharedLegacyMigration module,String operation,Map<String,Object> data)throws IOException{return module.request(operation,data,()->false,value->{});}
    @SuppressWarnings("unchecked")private static List<Map<String,Object>> rows(Map<String,Object> value,String key){return (List<Map<String,Object>>)(List<?>)value.get(key);}
    private static Map<String,String> snapshot(Path root)throws IOException{Map<String,String> result=new TreeMap<>();if(Files.exists(root))try(java.util.stream.Stream<Path> stream=Files.walk(root)){for(Path file:(Iterable<Path>)stream.filter(Files::isRegularFile)::iterator)result.put(root.relativize(file).toString(),PhotoEditStore.hashFile(file.toFile()));}return result;}
    public static int run(Path temporary)throws Exception{
        checks=0;Path source=temporary.resolve("legacy-source"),photos=source.resolve("pictures/camera-album");Files.createDirectories(photos);
        // Deliberately synthetic JPEG framing tests storage identity; platform tests own decoding.
        byte[] jpeg={(byte)255,(byte)216,10,20,30,40,(byte)255,(byte)217};String sha=PhotoEditStore.hash(jpeg);Path photo=photos.resolve("legacy__DSC_0042.JPG");Files.write(photo,jpeg);
        byte[] preset=NcpCompatibilityFixtures.ncp();PresetLibrary oldLibrary=new PresetLibrary(source.toFile());String presetId=oldLibrary.importFile("旧版色彩.ncp",preset).record.id;
        PhotoEditStore oldEdits=new PhotoEditStore(source.toFile(),"");oldEdits.save(new PhotoEditStore.Draft(sha,preset,"旧版色彩",75,false));
        PhotoLiveProjectStore oldProjects=new PhotoLiveProjectStore(source.resolve("photo-live-projects").toFile(),photos.toFile());PhotoLiveProject oldProject=oldProjects.create("旧版拍摄项目");oldProjects.record(oldProject.id,sha,SharedProjectPhoto.completed(photo.toFile(),"DSC_0042.JPG"));
        new PhotoProjectPresetStore(source.resolve("photo-project-presets").toFile()).setConfig(oldProject.id,presetId,"旧版色彩");
        Map<String,String> before=snapshot(source);Path bundle=temporary.resolve("old-data.zip");
        LegacyArchive.exportAndroid(source.toFile(),photos.toFile(),"",SharedRuntime.map("id","","nickname","游客资料","token","must-never-export"),bundle.toFile(),()->false);
        yes(before.equals(snapshot(source))); // Recovery-capable readers worked on copies.
        Path unpacked=temporary.resolve("unpacked");Map<String,Object> manifest=LegacyArchive.unpack(bundle.toFile(),unpacked.toFile(),()->false);
        yes(!SharedJson.encode(manifest).contains("must-never-export"));yes(rows(manifest,"photos").size()==1);yes(rows(manifest,"presets").size()==1);yes(rows(manifest,"drafts").size()==1);yes(rows(manifest,"projects").size()==1);
        Path target=temporary.resolve("legacy-target");SharedRuntime runtime=runtime(target);SharedLegacyMigration module=new SharedLegacyMigration(runtime);
        Path incoming=target.resolve("legacy-incoming/old.zip");Files.createDirectories(incoming.getParent());Files.copy(bundle,incoming);
        // Pre-existing metadata and draft win over older migration data.
        PresetLibrary existing=new PresetLibrary(target.toFile());existing.importFile("当前保留名称.ncp",preset);
        PhotoEditStore targetEdits=new PhotoEditStore(target.toFile(),"");targetEdits.save(new PhotoEditStore.Draft(sha,preset,"当前草稿",20,false));
        Map<String,Object> preview=request(module,"legacy.inspect",SharedRuntime.map("path",incoming.toString()));String transaction=(String)preview.get("transaction");
        yes(Boolean.TRUE.equals(preview.get("accountMatch")));yes(rows(preview,"photos").size()==1);yes(Files.exists(Paths.get((String)rows(preview,"photos").get(0).get("path"))));
        Map<String,Object> commit=SharedRuntime.map("transaction",transaction,"includeAccountData",true,"photos",List.of(SharedRuntime.map("sha256",sha,"info",SharedRuntime.map("width",1,"height",1,"raw",false))));
        yes(request(module,"legacy.commit",commit).get("status").equals("complete"));
        Path imported=target.resolve("originals/"+sha+".jpg");yes(Arrays.equals(jpeg,Files.readAllBytes(imported)));yes(new PhotoEditStore(target.toFile(),"").read(sha).strength==20);
        yes(new PresetLibrary(target.toFile()).findBySha256(presetId).originalFileName.equals("当前保留名称.ncp"));
        yes(new PhotoLiveProjectStore(target.resolve("photo-live-projects").toFile(),target.resolve("originals").toFile()).list().size()==1);
        rejects(()->request(module,"legacy.inspect",SharedRuntime.map("path",incoming.toString()))); // Stable export receipt prevents duplicate projects.
        yes(request(module,"legacy.rollback",SharedRuntime.map("transaction",transaction)).get("status").equals("rolledBack"));
        yes(!Files.exists(imported));yes(!Files.exists(target.resolve("photos-index.json")));yes(new PhotoEditStore(target.toFile(),"").read(sha).strength==20);
        yes(new PresetLibrary(target.toFile()).findBySha256(presetId)!=null);yes(snapshot(source).equals(before));
        // Interrupt after a real mutation: the journal restores before-images and removes additions.
        Map<String,Object> interrupted=request(module,"legacy.inspect",SharedRuntime.map("path",incoming.toString()));AtomicBoolean stop=new AtomicBoolean();
        Map<String,Object> interruptedCommit=new LinkedHashMap<>(commit);interruptedCommit.put("transaction",interrupted.get("transaction"));
        rejects(()->module.request("legacy.commit",interruptedCommit,stop::get,value->stop.set(true)));
        yes(!Files.exists(imported));yes(!Files.exists(target.resolve("photos-index.json")));yes(new PhotoEditStore(target.toFile(),"").read(sha).strength==20);
        yes(rows(request(module,"legacy.status",SharedRuntime.map()),"items").stream().allMatch(row->"rolledBack".equals(row.get("status"))));
        // A new edit after success blocks rollback before any file is removed.
        Map<String,Object> finalPreview=request(module,"legacy.inspect",SharedRuntime.map("path",incoming.toString()));Map<String,Object> finalCommit=new LinkedHashMap<>(commit);finalCommit.put("transaction",finalPreview.get("transaction"));request(module,"legacy.commit",finalCommit);
        Files.write(target.resolve("photos-index.json")," ".getBytes(StandardCharsets.UTF_8),StandardOpenOption.APPEND);Map<String,String> edited=snapshot(target);
        rejects(()->request(module,"legacy.rollback",SharedRuntime.map("transaction",finalPreview.get("transaction"))));yes(edited.equals(snapshot(target)));yes(Files.exists(imported));
        rejects(()->request(module,"legacy.inspect",SharedRuntime.map("path",bundle.toString())));
        rejects(()->request(module,"legacy.rollback",SharedRuntime.map("transaction",finalPreview.get("transaction"),"owner","other-account")));
        Path bad=temporary.resolve("traversal.zip");try(ZipOutputStream zip=new ZipOutputStream(Files.newOutputStream(bad))){zip.putNextEntry(new ZipEntry("../escape"));zip.write(1);zip.closeEntry();}
        rejects(()->LegacyArchive.unpack(bad.toFile(),temporary.resolve("bad-unpack").toFile(),()->false));yes(!Files.exists(temporary.resolve("escape")));
        Path tampered=temporary.resolve("tampered.zip");try(ZipInputStream input=new ZipInputStream(Files.newInputStream(bundle));ZipOutputStream output=new ZipOutputStream(Files.newOutputStream(tampered))){ZipEntry entry;while((entry=input.getNextEntry())!=null){byte[] bytes=input.readAllBytes();if(entry.getName().endsWith(".ncp"))bytes[bytes.length-1]^=1;output.putNextEntry(new ZipEntry(entry.getName()));output.write(bytes);output.closeEntry();}}
        rejects(()->LegacyArchive.unpack(tampered.toFile(),temporary.resolve("tampered-unpack").toFile(),()->false));
        Path ios=temporary.resolve("ios-presets");Files.createDirectories(ios);Files.write(ios.resolve("apple.ncp"),preset);Path iosZip=temporary.resolve("ios.zip");LegacyArchive.exportIosPresets(ios.toFile(),iosZip.toFile(),()->false);
        Map<String,Object> iosManifest=LegacyArchive.unpack(iosZip.toFile(),temporary.resolve("ios-unpack").toFile(),()->false);yes(iosManifest.get("origin").equals("ios-original"));yes(rows(iosManifest,"presets").size()==1);yes(rows(iosManifest,"photos").isEmpty());
        rejects(()->LegacyArchive.safeName("first\nsecond\n../escape.jpg"));
        Path blockedRoot=temporary.resolve("blocked-target");SharedLegacyMigration blocked=new SharedLegacyMigration(runtime(blockedRoot));Path blockedInput=blockedRoot.resolve("legacy-incoming/old.zip");Files.createDirectories(blockedInput.getParent());Files.copy(bundle,blockedInput);
        Map<String,Object> blockedPreview=request(blocked,"legacy.inspect",SharedRuntime.map("path",blockedInput.toString()));Files.write(blockedRoot.resolve("photo-live-projects"),"preserved obstruction".getBytes(StandardCharsets.UTF_8));
        Map<String,Object> blockedCommit=new LinkedHashMap<>(commit);blockedCommit.put("transaction",blockedPreview.get("transaction"));Map<String,String> blockedBefore=snapshot(blockedRoot);
        rejects(()->request(blocked,"legacy.commit",blockedCommit));Map<String,String> blockedAfter=snapshot(blockedRoot);blockedBefore.keySet().removeIf(key->key.startsWith("legacy-migrations"+File.separator));blockedAfter.keySet().removeIf(key->key.startsWith("legacy-migrations"+File.separator));yes(blockedBefore.equals(blockedAfter));
        return checks;
    }
    public static void main(String[] args)throws Exception{Path temp=Files.createTempDirectory("legacy-migration-boundary-");try{System.out.println("PASS LegacyMigrationBoundaryTest "+run(temp));}finally{try(java.util.stream.Stream<Path> stream=Files.walk(temp)){stream.sorted(Comparator.reverseOrder()).forEach(path->{try{Files.deleteIfExists(path);}catch(IOException ignored){}});}}}
}
