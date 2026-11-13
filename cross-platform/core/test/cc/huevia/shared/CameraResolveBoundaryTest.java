package cc.huevia.shared;

import cc.huevia.album.*;
import cc.huevia.library.SharedJson;
import cc.huevia.ptp.*;
import java.io.*;
import java.nio.file.*;
import java.util.*;

/** Stable identity and bounded descriptor recovery do not change visible inventory or download bytes. */
public final class CameraResolveBoundaryTest {
    private static int checks;
    private interface Action{void run()throws Exception;}
    private static void yes(boolean value){checks++;if(!value)throw new AssertionError("Camera resolve "+checks);}
    private static void rejects(Action action)throws Exception{checks++;try{action.run();}catch(IOException expected){return;}throw new AssertionError("Invalid resolve accepted");}
    static int run(Path temporary)throws Exception {
        checks=0;File root=Files.createDirectory(temporary.resolve("camera-resolve")).toFile();Peer peer=new Peer();
        SharedCamera camera=new SharedCamera(root.getPath(),(h,p,f)->{throw new AssertionError("Unexpected Wi-Fi");},new SharedCamera.WiredConnections(){public String devices(){return "{\"items\":[]}";}public PhotoCameraClient create(String id){return peer;}});
        Map<String,Object> connect=SharedRuntime.map("transport","usb","deviceId","fixture","protocol","nikon"),status=call(camera,"camera.connect",connect);String session=(String)status.get("session"),identity=(String)status.get("downloadCameraId");
        yes(Boolean.TRUE.equals(status.get("downloadTrusted")));yes(Boolean.FALSE.equals(status.get("trustedCamera")));yes(identity.matches("[0-9a-f]{64}"));
        Map<String,Object> page=call(camera,"camera.page",SharedRuntime.map("session",session,"limit",1));Map<String,Object> first=map(((List<?>)page.get("items")).get(0));yes(((Number)first.get("storage")).longValue()==1);String descriptor=(String)first.get("descriptor");yes(descriptor.matches("[0-9a-f]{64}"));
        Map<String,Object> request=SharedRuntime.map("session",session,"handle",260,"descriptor",descriptor,"offset",0);
        Map<String,Object> resolved=call(camera,"camera.resolve",request);yes(((Number)map(resolved.get("match")).get("handle")).longValue()==260);yes(peer.downloads==0);
        peer.items.put(500L,peer.items.remove(260L));resolved=call(camera,"camera.resolve",request);yes(resolved.get("match")==null);yes(((Number)resolved.get("nextOffset")).intValue()==128);yes(Boolean.TRUE.equals(resolved.get("hasMore")));
        request.put("offset",128);resolved=call(camera,"camera.resolve",request);yes(resolved.get("match")==null);yes(((Number)resolved.get("nextOffset")).intValue()==256);
        request.put("offset",256);resolved=call(camera,"camera.resolve",request);yes(((Number)map(resolved.get("match")).get("handle")).longValue()==500);yes(peer.downloads==0);
        Map<String,Object> received=call(camera,"camera.download",SharedRuntime.map("session",session,"handle",500));yes(Arrays.equals(Files.readAllBytes(Paths.get((String)received.get("path"))),peer.jpeg));yes(peer.downloads==1);
        rejects(()->call(camera,"camera.resolve",SharedRuntime.map("session",session,"descriptor","bad")));
        camera.disconnect();status=call(camera,"camera.connect",connect);yes(status.get("downloadCameraId").equals(identity));yes(!status.get("session").equals(session));
        peer.serial="000000";camera.disconnect();status=call(camera,"camera.connect",connect);yes(Boolean.FALSE.equals(status.get("downloadTrusted")));String unknown=(String)status.get("downloadCameraId");camera.disconnect();status=call(camera,"camera.connect",connect);yes(!unknown.equals(status.get("downloadCameraId")));camera.disconnect();
        System.out.println("PASS "+checks+" camera descriptor recovery checks; real serial identity, unchanged A1 trust, 128-object paging, relocated handle and exact download authorization");return checks;
    }
    private static final class Peer implements PhotoCameraClient {
        final LinkedHashMap<Long,PtpObjectInfo> items=new LinkedHashMap<>();String serial="REAL-12345";boolean open;int downloads;final byte[] jpeg={(byte)255,(byte)216,1,2,3,4,(byte)255,(byte)217};
        Peer(){for(long h=1;h<=260;h++)items.put(h,new PtpObjectInfo.Builder().storageId(1).parentObject(10).objectFormat(0x3801).filename("DSC_"+h+".JPG").compressedSize(jpeg.length).build());}
        public byte[] connect(String h,int p,byte[] g,String n){open=true;return info(serial);}public boolean isOpen(){return open;}public boolean isProtocolUnconfirmed(){return false;}public String closeReason(){return "";}public String connectedHost(){return "usb:fixture";}public int connectedPort(){return 0;}public String cameraIdentity(){return "";}public void setOnClosed(Runnable r){}public void setOnObjectAdded(java.util.function.LongConsumer l){}public byte[] readAlbumDeviceInfo(){return info(serial);}public void abortProtocol(IOException e){close();}public void close(){open=false;}
        public byte[] getData(int op,int max,long...p)throws IOException {if(op==0x1004)return concat(le32(1),le32(1));if(op==0x1007){ByteArrayOutputStream out=new ByteArrayOutputStream();out.writeBytes(le32(items.size()));for(long h:items.keySet())out.writeBytes(le32((int)h));return out.toByteArray();}if(op==0x1008){PtpObjectInfo info=items.get(p[0]);if(info==null)throw new PtpResponseException(0x2009,1);return info.toBytes();}throw new IOException("Unexpected read");}
        public byte[] getLargeThumbnail(long h){return jpeg;}public long readTo(int op,OutputStream output,long max,long expected,Progress progress,long...p)throws IOException{downloads++;output.write(jpeg);progress.onProgress(jpeg.length,jpeg.length);return jpeg.length;}
    }
    private static byte[] info(String serial){int[] ops={0x1001,0x1002,0x1003,0x1004,0x1007,0x1008,0x1009};ByteArrayOutputStream out=new ByteArrayOutputStream();out.writeBytes(le32(ops.length));for(int op:ops)out.writeBytes(le16(op));return concat(le16(100),le32(10),le16(100),text(""),le16(0),out.toByteArray(),le32(0),le32(0),le32(0),le32(0),text("NIKON CORPORATION"),text("Serial fixture"),text("1"),text(serial));}
    private static byte[] text(String s){ByteArrayOutputStream out=new ByteArrayOutputStream();if(s.isEmpty()){out.write(0);return out.toByteArray();}out.write(s.length()+1);for(char c:s.toCharArray())out.writeBytes(le16(c));out.writeBytes(le16(0));return out.toByteArray();}
    private static byte[] le16(int n){return new byte[]{(byte)n,(byte)(n>>>8)};}private static byte[] le32(int n){return new byte[]{(byte)n,(byte)(n>>>8),(byte)(n>>>16),(byte)(n>>>24)};}
    private static byte[] concat(byte[]...p){ByteArrayOutputStream out=new ByteArrayOutputStream();for(byte[] b:p)out.writeBytes(b);return out.toByteArray();}
    private static Map<String,Object> call(SharedCamera camera,String op,Map<String,Object> p)throws IOException{return SharedJson.object(camera.request(op,SharedJson.encode(p),"resolve-check",()->false,v->{}));}
    @SuppressWarnings("unchecked") private static Map<String,Object> map(Object o){return (Map<String,Object>)o;}
    public static void main(String[] args)throws Exception{run(Files.createTempDirectory("camera-resolve-"));}
}
