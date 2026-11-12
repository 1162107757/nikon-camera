package cc.huevia.shared;

import cc.huevia.album.*;
import cc.huevia.library.SharedJson;
import cc.huevia.ptp.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.function.*;

final class CameraTransferBoundaryTest {
    private static int checks;
    private static void yes(boolean value){checks++;if(!value)throw new AssertionError("Camera transfer boundary "+checks);}
    private interface Action{void run()throws Exception;}
    private static void rejects(Action action)throws Exception{checks++;try{action.run();}catch(IOException expected){return;}throw new AssertionError("Invalid camera transfer accepted");}
    static int run(Path temporary)throws Exception{
        checks=0;
        for(int strategy=0;strategy<3;strategy++){
            File root=temporary.resolve("transfer-"+strategy).toFile();yes(root.mkdirs());Peer peer=new Peer();peer.strategy=strategy;
            SharedCamera camera=new SharedCamera(root.getPath(),(host,port,fuji)->null,(connector,fuji)->peer);
            String session=(String)call(camera,"camera.connect",SharedRuntime.map("host","192.168.1.1","port",15740,"protocol","nikon")).get("session");
            Map<String,Object> page=SharedRuntime.map("session",session,"raw",false,"offset",0,"limit",24);
            Map<String,Object> listing=call(camera,"camera.page",page);List<?> jpeg=(List<?>)listing.get("items");
            yes(jpeg.size()==2);yes(((Number)listing.get("unavailableStorages")).intValue()==1);yes(peer.formats.get(0)==0x3801);
            for(Object row:jpeg){Map<?,?> item=(Map<?,?>)row;yes(!Boolean.TRUE.equals(item.get("raw")));yes(((String)item.get("name")).toLowerCase(Locale.ROOT).endsWith(".jpg"));}
            page.put("raw",true);List<?> raw=(List<?>)call(camera,"camera.page",page).get("items");yes(raw.size()==1);yes(((Map<?,?>)raw.get(0)).get("name").equals("RAW.NEF"));
            page.put("offset",1);page.put("raw",false);rejects(()->call(camera,"camera.page",page));page.put("offset",0);
            yes(((List<?>)call(camera,"camera.page",page).get("items")).size()==2);
            List<Double> progress=new ArrayList<>();Map<String,Object> download=SharedRuntime.map("session",session,"handle",1,"raw",false);
            Map<String,Object> receipt=SharedJson.object(camera.request("camera.download",SharedJson.encode(download),"transfer",()->false,progress::add));
            File received=new File((String)receipt.get("path"));yes(Arrays.equals(Files.readAllBytes(received.toPath()),peer.jpeg));yes(progress.equals(Arrays.asList(0.0,.5,1.0)));yes(Boolean.FALSE.equals(receipt.get("raw")));
            // A bad data-start count cannot produce a fabricated 100% or publish a file.
            peer.badSize=true;progress.clear();rejects(()->camera.request("camera.download",SharedJson.encode(download),"bad",()->false,progress::add));yes(progress.isEmpty());
            yes(Arrays.stream(Objects.requireNonNull(received.getParentFile().listFiles())).noneMatch(f->f.getName().endsWith(".part")));
            yes(Arrays.equals(Files.readAllBytes(received.toPath()),peer.jpeg));camera.disconnect();
        }
        File root=temporary.resolve("transfer-cancel").toFile();yes(root.mkdirs());Peer peer=new Peer();SharedCamera camera=new SharedCamera(root.getPath(),(h,p,f)->null,(c,f)->peer);
        String session=(String)call(camera,"camera.connect",SharedRuntime.map("host","192.168.1.1","protocol","nikon")).get("session");
        call(camera,"camera.page",SharedRuntime.map("session",session,"raw",false));AtomicBoolean cancel=new AtomicBoolean();
        rejects(()->camera.request("camera.download",SharedJson.encode(SharedRuntime.map("session",session,"handle",1)),"cancel",cancel::get,v->{if(v>=.5)cancel.set(true);}));
        yes(Objects.requireNonNull(new File(root,"originals").list()).length==0);camera.disconnect();
        System.out.println("PASS "+checks+" camera transfer checks; separate JPEG indexes, generic JPEG metadata, fallback, unavailable cards, exact bytes, real progress and cancelled partial cleanup");return checks;
    }
    private static Map<String,Object> call(SharedCamera camera,String op,Map<String,Object> p)throws IOException{return SharedJson.object(camera.request(op,SharedJson.encode(p),"test",()->false,v->{}));}
    private static final class Peer implements PhotoCameraClient {
        boolean open,badSize;int strategy;List<Integer> formats=new ArrayList<>();
        final byte[] jpeg={(byte)255,(byte)216,1,2,3,4,(byte)255,(byte)217};
        public byte[] connect(String h,int p,byte[] g,String n){open=true;return info();}
        public boolean isOpen(){return open;}public boolean isProtocolUnconfirmed(){return false;}public String closeReason(){return "";}public String connectedHost(){return "192.168.1.1";}public int connectedPort(){return 15740;}public String cameraIdentity(){return "transfer";}
        public void setOnClosed(Runnable r){}public void setOnObjectAdded(LongConsumer r){}public byte[] readAlbumDeviceInfo(){return info();}
        public byte[] getData(int op,int max,long...p)throws IOException{
            if(op==0x1004)return concat(le32(2),le32(1),le32(2));
            if(op==0x1007){if(p[0]==2)throw new PtpResponseException(0x2013,1);int format=(int)p[1];formats.add(format);if(format==0x3801){if(strategy==1)throw new PtpResponseException(0x2014,1);if(strategy==2)return le32(0);return concat(le32(2),le32(1),le32(3));}return strategy==0?concat(le32(1),le32(2)):concat(le32(4),le32(1),le32(2),le32(3),le32(4));}
            if(op==0x1008){long h=p[0];return new PtpObjectInfo.Builder().storageId(1).objectFormat(h==2?0xb103:h==3?0x3000:h==4?0x3001:0x3801).filename(h==2?"RAW.NEF":h==4?"folder.jpg":"JPEG"+h+".JpG").compressedSize(h==2?27000000:jpeg.length).imagePixWidth(6048).imagePixHeight(4024).build().toBytes();}
            throw new IOException("Unexpected operation "+op);
        }
        public byte[] getLargeThumbnail(long h){return jpeg;}
        public long readTo(int op,OutputStream out,long max,long expected,Progress progress,long...p)throws IOException{
            long total=jpeg.length+(badSize?1:0);progress.onProgress(0,total);out.write(jpeg,0,4);progress.onProgress(4,total);if(!open)throw new IOException("Closed");out.write(jpeg,4,4);progress.onProgress(8,total);return jpeg.length;
        }
        public void abortProtocol(IOException e){open=false;}public void close(){open=false;}
    }
    private static byte[] info(){int[] operations={0x1001,0x1002,0x1003,0x1004,0x1007,0x1008,0x1009,0x100a,0x90c4};ByteArrayOutputStream ops=new ByteArrayOutputStream();ops.writeBytes(le32(operations.length));for(int op:operations)ops.writeBytes(le16(op));return concat(le16(100),le32(10),le16(100),string("Fixture"),le16(0),ops.toByteArray(),le32(0),le32(0),le32(0),le32(0),string("NIKON CORPORATION"),string("Z 6_2"),string("1"),string(""));}
    private static byte[] string(String text){return text.isEmpty()?new byte[]{0}:concat(new byte[]{(byte)(text.length()+1)},(text+'\0').getBytes(StandardCharsets.UTF_16LE));}
    private static byte[] le16(long n){return new byte[]{(byte)n,(byte)(n>>>8)};}
    private static byte[] le32(long n){return new byte[]{(byte)n,(byte)(n>>>8),(byte)(n>>>16),(byte)(n>>>24)};}
    private static byte[] concat(byte[]...parts){ByteArrayOutputStream out=new ByteArrayOutputStream();for(byte[]part:parts)out.writeBytes(part);return out.toByteArray();}
}
