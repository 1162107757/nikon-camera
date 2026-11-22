package cc.huevia.shared;

import cc.huevia.library.SharedJson;
import cc.huevia.ncp.NcpCompatibilityFixtures;
import java.io.*;
import java.nio.file.*;
import java.util.*;

public final class ImportBoundaryTest {
    private static int checks;
    private static void yes(boolean value){checks++;if(!value)throw new AssertionError("Import boundary "+checks);}
    private interface Action{void run()throws Exception;}
    private static void rejects(Action action)throws Exception{checks++;try{action.run();}catch(IOException expected){return;}throw new AssertionError("Invalid import accepted");}
    private static final class Source extends ByteArrayInputStream{
        boolean closed;int maximumRead;
        Source(byte[] bytes){super(bytes);}
        public int read(byte[] bytes,int offset,int length){maximumRead=Math.max(maximumRead,length);return super.read(bytes,offset,length);}
        public void close(){closed=true;}
        int position(){return pos;}
    }
    public static int run(Path temporary)throws Exception{
        checks=0;Path root=temporary.resolve("native-import");byte[] bytes=NcpCompatibilityFixtures.ncp();Source source=new Source(bytes);
        Map<String,Object> receipt=SharedJson.object(SharedImport.copy(source,"秋色.NCP",true,root.toString(),()->false));Path saved=Paths.get((String)receipt.get("path"));
        yes(source.closed&&source.maximumRead<=65536);yes(receipt.get("name").equals("秋色.NCP"));yes(saved.getFileName().toString().endsWith(".ncp"));yes(Arrays.equals(Files.readAllBytes(saved),bytes));yes(Boolean.TRUE.equals(receipt.get("created")));
        Files.setLastModifiedTime(saved,java.nio.file.attribute.FileTime.fromMillis(1234567890000L));
        Map<String,Object> duplicate=SharedJson.object(SharedImport.copy(new Source(bytes),"别名.ncp",true,root.toString(),()->false));yes(Boolean.FALSE.equals(duplicate.get("created")));yes(Files.getLastModifiedTime(saved).toMillis()==1234567890000L);
        byte[] corrupt=bytes.clone();corrupt[0]^=1;Files.write(saved,corrupt);
        rejects(()->SharedImport.copy(new Source(bytes),"秋色.ncp",true,root.toString(),()->false));yes(Arrays.equals(Files.readAllBytes(saved),corrupt));
        Source invalidName=new Source(bytes);rejects(()->SharedImport.copy(invalidName,"../outside.ncp",true,root.toString(),()->false));yes(invalidName.closed);
        rejects(()->SharedImport.copy(new Source(bytes),"wrong.exe",true,root.toString(),()->false));
        rejects(()->SharedImport.copy(new Source(new byte[1024*1024+1]),"large.ncp",true,root.toString(),()->false));
        rejects(()->SharedImport.copy(new Source(new byte[0]),"empty.ncp",true,root.toString(),()->false));
        Source cancelled=new Source(new byte[128000]);rejects(()->SharedImport.copy(cancelled,"cancelled.nef",false,root.toString(),()->cancelled.position()>0));yes(cancelled.closed);
        try(java.util.stream.Stream<Path> files=Files.walk(root)){yes(files.noneMatch(p->p.getFileName().toString().endsWith(".part")));}
        byte[] photo=new byte[2*1024*1024];Arrays.fill(photo,(byte)7);Source largePhoto=new Source(photo);
        Map<String,Object> photoReceipt=SharedJson.object(SharedImport.copy(largePhoto,"photo.NEF",false,root.toString(),()->false));
        yes(largePhoto.maximumRead==65536&&largePhoto.closed);yes(((Number)photoReceipt.get("bytes")).longValue()==photo.length);yes(((String)photoReceipt.get("path")).contains("originals"));
        byte[] np3=cc.huevia.ncp.CameraPresetProjectionTest.np3(0x20,2,true,true);
        var missingSuffix=SharedJson.object(SharedImport.copy(new Source(np3),"旅行",true,root.toString(),()->false));
        Path stagedNp3=Paths.get((String)missingSuffix.get("path"));
        yes(missingSuffix.get("name").equals("旅行.np3"));yes(stagedNp3.toString().endsWith(".np3"));
        yes(Arrays.equals(np3,Files.readAllBytes(stagedNp3)));
        var missingName=SharedJson.object(SharedImport.copy(new Source(np3),null,true,root.toString(),()->false));
        yes(missingName.get("name").equals("导入预设.np3"));yes(missingName.get("path").equals(stagedNp3.toString()));
        rejects(()->SharedImport.copy(new Source(Arrays.copyOf(np3,np3.length-4)),"损坏预设",true,root.toString(),()->false));
        rejects(()->SharedImport.stageSubmission(new Source(np3),"扩展名缺失","ncp","11111111-1111-4111-8111-111111111111",root.toString(),()->false));
        byte[] np2=cc.huevia.ncp.Np2Fixtures.std();
        Map<String,Object> np2Receipt=SharedJson.object(SharedImport.copy(new Source(np2),"晴空.NP2",true,root.toString(),()->false));
        Path np2Path=Paths.get((String)np2Receipt.get("path"));yes(np2Path.toString().endsWith(".np2"));yes(Arrays.equals(np2,Files.readAllBytes(np2Path)));
        cc.huevia.library.PresetLibrary library=new cc.huevia.library.PresetLibrary(root.toFile());
        var np3Added=library.importFile((String)missingSuffix.get("name"),Files.readAllBytes(stagedNp3));
        yes(np3Added.record.fileFormat.equals("NP3"));yes(Arrays.equals(library.readPreset(np3Added.record.id),np3));
        var added=library.importFile("晴空.NP2",np2);yes(added.record.fileFormat.equals("NP2"));yes(added.record.displayName.equals("HV240_NP2_STD"));
        String id=added.record.sha256;yes(Arrays.equals(np2,library.readPreset(id)));
        yes(!library.importFile("duplicate.np2",np2).added);
        library=new cc.huevia.library.PresetLibrary(root.toFile());yes(library.findBySha256(id).fileFormat.equals("NP2"));yes(Arrays.equals(np2,library.readPreset(id)));
        final cc.huevia.library.PresetLibrary persisted=library;
        rejects(()->persisted.importFile("disguised.np3",np2));rejects(()->persisted.importFile("disguised.np2",bytes));
        // Community submission remains separately limited to NCP; local support does not widen that contract.
        rejects(()->SharedImport.stageSubmission(new Source(np2),"晴空.NP2","ncp","11111111-1111-4111-8111-111111111111",root.toString(),()->false));
        Path legacyFolder=Files.createDirectory(root.resolve("np2-folder"));Files.write(legacyFolder.resolve("晴空.NP2"),np2);
        Path bundle=root.resolve("np2-backup.zip");LegacyArchive.exportIosPresets(legacyFolder.toFile(),bundle.toFile(),()->false);
        Path restored=root.resolve("np2-restored");Map<String,Object> manifest=LegacyArchive.unpack(bundle.toFile(),restored.toFile(),()->false);
        List<?> rows=(List<?>)manifest.get("presets");yes(rows.size()==1);
        Map<?,?> row=(Map<?,?>)rows.get(0);yes(row.get("name").equals("晴空.NP2"));
        yes(row.get("entry").toString().endsWith(".np2"));yes(Arrays.equals(np2,Files.readAllBytes(restored.resolve(row.get("entry").toString()))));
        return checks;
    }
}
