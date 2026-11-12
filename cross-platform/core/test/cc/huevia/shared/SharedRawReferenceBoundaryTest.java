package cc.huevia.shared;

import cc.huevia.library.SharedJson;
import java.io.*;
import java.nio.file.*;
import java.util.*;

final class SharedRawReferenceBoundaryTest {
    private static int checks;
    private interface Action{void run()throws Exception;}
    private static void yes(boolean value){checks++;if(!value)throw new AssertionError("RAW reference boundary "+checks);}
    private static void rejects(Action action)throws Exception{checks++;try{action.run();}catch(IOException expected){return;}throw new AssertionError("Invalid RAW reference accepted");}
    static int run(Path temporary)throws Exception{
        checks=0;File root=temporary.resolve("raw-reference").toFile(),originals=new File(root,"originals");yes(originals.mkdirs());
        File raw=new File(originals,"same.NEF"),jpeg=new File(originals,"different-name.JPG"),outside=temporary.resolve("outside-reference.jpg").toFile();
        byte[] rawBytes=new byte[256];for(int i=0;i<rawBytes.length;i++)rawBytes[i]=(byte)i;
        byte[] jpegBytes={(byte)255,(byte)216,1,2,3,4,(byte)255,(byte)217};Files.write(raw.toPath(),rawBytes);Files.write(jpeg.toPath(),jpegBytes);Files.write(outside.toPath(),jpegBytes);
        Map<String,Object> description=SharedRawReference.describe(root,raw,jpeg.getPath(),()->false);
        SharedRawReference.Reference reference=SharedRawReference.resolve(root,SharedJson.encode(description),()->false);
        yes(reference!=null);yes(reference.file.equals(jpeg.getCanonicalFile()));yes(reference.sha256.matches("[0-9a-f]{64}"));
        reference.verifySource((String)description.get("sourceSha"));reference.verify(()->false);yes(true);
        rejects(()->reference.verifySource("0".repeat(64)));
        yes(SharedRawReference.resolve(root,"",()->false)==null);
        rejects(()->SharedRawReference.describe(root,raw,outside.getPath(),()->false));
        rejects(()->SharedRawReference.describe(root,outside,jpeg.getPath(),()->false));
        rejects(()->SharedRawReference.describe(root,raw,raw.getPath(),()->false));
        Map<String,Object> forged=new LinkedHashMap<>(description);forged.put("sha256","0".repeat(64));rejects(()->SharedRawReference.resolve(root,SharedJson.encode(forged),()->false));
        forged.put("sha256",description.get("sha256"));forged.put("sourceSha","invalid");rejects(()->SharedRawReference.resolve(root,SharedJson.encode(forged),()->false));
        rejects(()->SharedRawReference.describe(root,raw,jpeg.getPath(),()->true));
        Files.write(jpeg.toPath(),new byte[]{(byte)255,(byte)216,3,2,1,4,(byte)255,(byte)217});rejects(()->reference.verify(()->false));rejects(()->SharedRawReference.resolve(root,SharedJson.encode(description),()->false));
        Files.write(jpeg.toPath(),new byte[]{(byte)137,80,78,71,13,10});rejects(()->SharedRawReference.describe(root,raw,jpeg.getPath(),()->false));
        Files.write(jpeg.toPath(),new byte[]{(byte)255,(byte)216,1,2});rejects(()->SharedRawReference.describe(root,raw,jpeg.getPath(),()->false));
        try(RandomAccessFile large=new RandomAccessFile(jpeg,"rw")){large.setLength(SharedRawReference.MAX_BYTES+1);}rejects(()->SharedRawReference.describe(root,raw,jpeg.getPath(),()->false));
        Files.write(jpeg.toPath(),jpegBytes);File alias=new File(root,"./originals/different-name.JPG");yes(SharedRawReference.describe(root,raw,alias.getPath(),()->false).get("sha256").equals(description.get("sha256")));
        yes(Arrays.equals(rawBytes,Files.readAllBytes(raw.toPath())));yes(Arrays.equals(jpegBytes,Files.readAllBytes(jpeg.toPath())));
        System.out.println("PASS "+checks+" RAW JPEG reference checks; explicit content/source binding, private paths, cancelled hashing, mutation detection and unchanged originals");return checks;
    }
}
