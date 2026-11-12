package cc.huevia.shared;

import cc.huevia.album.*;
import cc.huevia.library.SharedJson;
import cc.huevia.ptp.*;
import java.io.*;
import java.nio.file.*;
import java.util.*;
import java.util.function.LongConsumer;

final class WiredCameraBoundaryTest {
    private static int checks;
    private static void yes(boolean value){checks++;if(!value)throw new AssertionError("Wired camera "+checks);}
    private interface Action{void run()throws Exception;}
    private static void rejects(Action action)throws Exception{checks++;try{action.run();}catch(IOException expected){return;}throw new AssertionError("Invalid wired request accepted");}
    static int run(Path temporary)throws Exception{
        checks=0;File root=Files.createDirectory(temporary.resolve("wired-camera")).toFile();Peer peer=new Peer();
        SharedCamera camera=new SharedCamera(root.getPath(),(host,port,fuji)->{throw new AssertionError("USB opened a Wi-Fi socket");},new SharedCamera.WiredConnections(){
            public String devices(){return SharedJson.encode(SharedRuntime.map("items",List.of(SharedRuntime.map("id","fixture","name","Nikon USB"))));}
            public PhotoCameraClient create(String id)throws IOException{if(!id.equals("fixture"))throw new IOException("Missing device");return peer;}
        });
        yes(((List<?>)call(camera,"camera.usb.devices",Map.of()).get("items")).size()==1);
        Map<String,Object> connect=SharedRuntime.map("transport","usb","deviceId","fixture","protocol","nikon");Map<String,Object> status=call(camera,"camera.connect",connect);String session=(String)status.get("session");
        yes(Boolean.TRUE.equals(status.get("connected")));yes(status.get("transport").equals("usb"));yes(Boolean.FALSE.equals(status.get("supportsLive")));
        Map<String,Object> page=call(camera,"camera.page",SharedRuntime.map("session",session,"limit",24));yes(((List<?>)page.get("items")).size()==1);
        Map<String,Object> request=SharedRuntime.map("session",session,"handle",1);Map<String,Object> saved=call(camera,"camera.download",request);
        yes(Arrays.equals(Files.readAllBytes(Paths.get((String)saved.get("path"))),peer.jpeg));yes(((Number)saved.get("bytes")).longValue()==peer.jpeg.length);
        rejects(()->call(camera,"camera.download",SharedRuntime.map("session","stale","handle",1)));
        rejects(()->call(camera,"camera.connect",SharedRuntime.map("transport","invalid","protocol","nikon")));yes(peer.open);
        rejects(()->call(camera,"camera.live.start",SharedRuntime.map("session",session)));
        camera.disconnect();yes(!peer.open);rejects(()->call(camera,"camera.download",request));
        yes(Files.list(root.toPath().resolve("originals")).noneMatch(path->path.toString().endsWith(".part")));
        System.out.println("PASS "+checks+" wired camera checks; native selection, no Wi-Fi, validated original download, session isolation and disconnect");return checks;
    }
    private static Map<String,Object> call(SharedCamera camera,String op,Map<String,Object> p)throws IOException{return SharedJson.object(camera.request(op,SharedJson.encode(p),"wired-test",()->false,v->{}));}
    private static final class Peer implements PhotoCameraClient{
        boolean open;final byte[] jpeg={(byte)255,(byte)216,1,2,3,4,(byte)255,(byte)217};
        public byte[] connect(String h,int p,byte[] g,String n){open=true;return info();}
        public boolean isOpen(){return open;}public boolean isProtocolUnconfirmed(){return false;}public String closeReason(){return "";}public String connectedHost(){return "usb:fixture";}public int connectedPort(){return 0;}public String cameraIdentity(){return "";}
        public void setOnClosed(Runnable r){}public void setOnObjectAdded(LongConsumer r){}public byte[] readAlbumDeviceInfo(){return info();}
        public byte[] getData(int op,int max,long...p)throws IOException{
            if(op==0x1004||op==0x1007)return concat(le32(1),le32(1));
            if(op==0x1008)return new PtpObjectInfo.Builder().storageId(1).objectFormat(0x3801).compressedSize(jpeg.length).imagePixWidth(4).imagePixHeight(3).filename("USB.JPG").build().toBytes();
            if(op==0x100a)return jpeg;throw new IOException("Unexpected read");
        }
        public byte[] getLargeThumbnail(long h)throws IOException{throw new PtpResponseException(0x2005,0);}
        public long readTo(int op,OutputStream out,long max,long expected,Progress progress,long...p)throws IOException{out.write(jpeg);progress.onProgress(jpeg.length,jpeg.length);return jpeg.length;}
        public void abortProtocol(IOException f){close();}public void close(){open=false;}
    }
    private static byte[] info(){int[] ops={0x1001,0x1002,0x1003,0x1004,0x1007,0x1008,0x1009,0x100a};ByteArrayOutputStream out=new ByteArrayOutputStream();out.writeBytes(le32(ops.length));for(int op:ops)out.writeBytes(le16(op));return concat(le16(100),le32(10),le16(100),text(""),le16(0),out.toByteArray(),le32(0),le32(0),le32(0),le32(0),text("NIKON CORPORATION"),text("USB Fixture"),text("1"),text(""));}
    private static byte[] text(String s){ByteArrayOutputStream o=new ByteArrayOutputStream();if(s.isEmpty()){o.write(0);return o.toByteArray();}o.write(s.length()+1);for(char c:s.toCharArray())o.writeBytes(le16(c));o.writeBytes(le16(0));return o.toByteArray();}
    private static byte[] le16(int n){return new byte[]{(byte)n,(byte)(n>>>8)};}private static byte[] le32(int n){return new byte[]{(byte)n,(byte)(n>>>8),(byte)(n>>>16),(byte)(n>>>24)};}
    private static byte[] concat(byte[]...parts){ByteArrayOutputStream o=new ByteArrayOutputStream();for(byte[] p:parts)o.writeBytes(p);return o.toByteArray();}
    public static void main(String[] args)throws Exception{run(Files.createTempDirectory("wired-camera-test-"));}
}
