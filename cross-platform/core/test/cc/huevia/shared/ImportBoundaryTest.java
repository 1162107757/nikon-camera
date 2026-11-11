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
        return checks;
    }
}
