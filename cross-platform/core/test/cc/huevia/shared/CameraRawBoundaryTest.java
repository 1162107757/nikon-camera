package cc.huevia.shared;

import cc.huevia.album.*;
import cc.huevia.ptp.*;
import java.io.*;
import java.nio.*;
import java.nio.file.*;
import java.util.*;

/** Conservative all-card matching and original NEF bytes, independent of rendered JPEGs. */
public final class CameraRawBoundaryTest {
    private static int checks;
    private interface Action{void run()throws Exception;}
    private static void yes(boolean value){checks++;if(!value)throw new AssertionError("Camera RAW check "+checks);}
    private static void rejects(Action action)throws Exception{checks++;try{action.run();}catch(IOException expected){return;}throw new AssertionError("Unsafe RAW request accepted "+checks);}
    static int run(Path temporary)throws Exception {
        checks=0;PairPeer peer=new PairPeer();SharedCameraRawPairing pairing=new SharedCameraRawPairing(peer,"session",true);
        Map<String,Object> opened=map(pairing.open(1,peer.items.get(1L),()->false));yes(((Number)opened.get("matchedHandle")).longValue()==2);yes(((Number)opened.get("objects")).intValue()==2);yes(peer.downloads==0);
        Map<String,Object> choose=SharedRuntime.map("pairId",opened.get("pairId"),"handle",2,"confirmed",true);
        rejects(()->pairing.select(SharedRuntime.map("pairId","stale","handle",2,"confirmed",true),()->false));
        rejects(()->pairing.select(SharedRuntime.map("pairId",choose.get("pairId"),"handle",2),()->false));
        yes(pairing.select(choose,()->false).filename().equals("DSC_0042.NEF"));
        peer.items.put(2L,photo("DSC_0042.NEF",1,11,42,"20261113T123000"));rejects(()->pairing.select(choose,()->false));
        peer=new PairPeer();peer.items.put(3L,photo("DSC_0042.NEF",2,10,43,"20261112T123000"));
        opened=map(new SharedCameraRawPairing(peer,"session",true).open(1,peer.items.get(1L),()->false));yes(((Number)opened.get("matchedHandle")).longValue()==0);yes(((String)opened.get("reason")).contains("多个同名"));
        peer=new PairPeer();opened=map(new SharedCameraRawPairing(peer,"session",false).open(1,peer.items.get(1L),()->false));yes(((Number)opened.get("matchedHandle")).longValue()==0);yes(((String)opened.get("reason")).contains("设备身份"));
        peer=new PairPeer();peer.missingCard=true;opened=map(new SharedCameraRawPairing(peer,"session",true).open(1,peer.items.get(1L),()->false));yes(((Number)opened.get("matchedHandle")).longValue()==0);yes(((Number)opened.get("unavailable")).intValue()==1);
        PairPeer cancelled=new PairPeer();rejects(()->new SharedCameraRawPairing(cancelled,"session",true).open(1,cancelled.items.get(1L),()->true));yes(cancelled.downloads==0);
        PairPeer changed=new PairPeer();changed.changeJpeg=true;rejects(()->new SharedCameraRawPairing(changed,"session",true).open(1,changed.items.get(1L),()->false));
        File root=Files.createDirectory(temporary.resolve("raw-publication")).toFile(),originals=new File(root,"originals");yes(originals.mkdir());byte[] nef=nef();String sha=PhotoEditStore.hash(nef);File source=new File(originals,sha+".nef");Files.write(source.toPath(),nef);PhotoFormat.validateNef(source,nef.length);
        Map<String,Object> inspected=SharedRuntime.map("format","NEF","sourceSha",sha,"bytes",nef.length,"path",source.getPath());String operation="1".repeat(32);
        Map<String,Object> saved=SharedOriginalPublication.prepare(root,"",inspected,operation,()->false);File snapshot=new File((String)saved.get("path"));yes(snapshot.getName().endsWith(".nef"));yes(saved.get("format").equals("NEF"));yes(Arrays.equals(Files.readAllBytes(snapshot.toPath()),nef));yes(saved.equals(SharedOriginalPublication.prepare(root,"",inspected,operation,()->false)));
        Map<String,Object> wrong=new LinkedHashMap<>(inspected);wrong.put("format","JPEG");rejects(()->SharedOriginalPublication.prepare(root,"",wrong,operation,()->false));
        rejects(()->SharedOriginalPublication.release(root,"",operation,"0".repeat(64),nef.length));yes(snapshot.exists());
        SharedOriginalPublication.release(root,"",operation,sha,nef.length);yes(!snapshot.exists()&&Arrays.equals(Files.readAllBytes(source.toPath()),nef));
        yes(saved.equals(SharedOriginalPublication.prepare(root,"",inspected,operation,()->false)));
        Files.write(snapshot.toPath(),new byte[]{1,2,3,4});rejects(()->SharedOriginalPublication.prepare(root,"",inspected,operation,()->false));rejects(()->SharedOriginalPublication.release(root,"",operation,sha,nef.length));
        System.out.println("PASS "+checks+" RAW pairing/publication checks; complete inventories, ambiguity, identity, explicit selection, unchanged NEF bytes and stable snapshot receipts");return checks;
    }
    private static final class PairPeer implements PhotoCameraClient {
        final Map<Long,PtpObjectInfo> items=new LinkedHashMap<>();boolean missingCard,changeJpeg;int jpegReads,downloads;
        PairPeer(){items.put(1L,photo("DSC_0042.JPG",1,10,42,"20261113T123000"));items.put(2L,photo("DSC_0042.NEF",1,10,42,"20261113T123000"));}
        public byte[] connect(String h,int p,byte[] g,String n){return new byte[0];}public boolean isOpen(){return true;}public boolean isProtocolUnconfirmed(){return false;}public String closeReason(){return "";}public String connectedHost(){return "fixture";}public int connectedPort(){return 0;}public String cameraIdentity(){return "a".repeat(32);}public void setOnClosed(Runnable r){}public void setOnObjectAdded(java.util.function.LongConsumer r){}public byte[] readAlbumDeviceInfo(){return new byte[0];}public void close(){}public void abortProtocol(IOException e){}
        public byte[] getData(int op,int max,long...p)throws IOException {
            if(op==0x1004)return concat(le32(2),le32(1),le32(2));
            if(op==0x1007){if(missingCard&&p[0]==2)throw new PtpResponseException(0x2013,1);List<Long> handles=new ArrayList<>();for(Map.Entry<Long,PtpObjectInfo> item:items.entrySet())if(item.getValue().storageId()==p[0])handles.add(item.getKey());ByteArrayOutputStream out=new ByteArrayOutputStream();out.writeBytes(le32(handles.size()));for(long handle:handles)out.writeBytes(le32((int)handle));return out.toByteArray();}
            if(op==0x1008){if(p[0]==1&&changeJpeg&&++jpegReads>1)return photo("DSC_0042.JPG",1,12,42,"20261113T123000").toBytes();return items.get(p[0]).toBytes();}throw new IOException("Unexpected RAW inventory read");
        }
        public byte[] getLargeThumbnail(long h)throws IOException{throw new IOException("No original read during pairing");}
        public long readTo(int o,OutputStream d,long m,long e,Progress p,long...a){downloads++;throw new AssertionError("Pairing downloaded an original");}
    }
    private static PtpObjectInfo photo(String name,long storage,long parent,long sequence,String date){return new PtpObjectInfo.Builder().storageId(storage).parentObject(parent).sequenceNumber(sequence).captureDate(date).objectFormat(name.endsWith("NEF")?0xb103:0x3801).filename(name).compressedSize(100).imagePixWidth(2).imagePixHeight(2).build();}
    static byte[] nef(){ByteBuffer b=ByteBuffer.allocate(100).order(ByteOrder.LITTLE_ENDIAN);b.put((byte)'I').put((byte)'I').putShort((short)42).putInt(8).putShort((short)6);entry(b,0x010f,2,6,86);entry(b,0x0100,4,1,2);entry(b,0x0101,4,1,2);entry(b,0x0106,3,1,32803);entry(b,0x0111,4,1,92);entry(b,0x0117,4,1,8);b.putInt(0).put(new byte[]{'N','I','K','O','N',0});while(b.hasRemaining())b.put((byte)17);return b.array();}
    private static void entry(ByteBuffer b,int tag,int type,int count,int value){b.putShort((short)tag).putShort((short)type).putInt(count).putInt(value);}
    @SuppressWarnings("unchecked") private static Map<String,Object> map(Object o){return (Map<String,Object>)o;}
    private static byte[] le32(int n){return new byte[]{(byte)n,(byte)(n>>>8),(byte)(n>>>16),(byte)(n>>>24)};}
    private static byte[] concat(byte[]...parts){ByteArrayOutputStream out=new ByteArrayOutputStream();for(byte[] p:parts)out.writeBytes(p);return out.toByteArray();}
    public static void main(String[] args)throws Exception{Path root=Files.createTempDirectory("camera-raw-");run(root);int prior=OriginalPublicationBoundaryTest.run(root);System.out.println("PASS "+prior+" retained original JPEG publication checks");}
}
