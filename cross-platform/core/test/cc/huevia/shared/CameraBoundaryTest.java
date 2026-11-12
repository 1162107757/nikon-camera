package cc.huevia.shared;

import cc.huevia.album.*;
import cc.huevia.library.SharedJson;
import cc.huevia.ptp.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.function.*;

/** Nikon-shaped fixtures: RAW-only browsing, actual preview bytes and no GetObject. */
final class CameraBoundaryTest {
    private static int checks;
    private static void yes(boolean value){checks++;if(!value)throw new AssertionError("Camera boundary "+checks);}
    private interface Action {void run()throws Exception;}
    private static void rejects(Action action)throws Exception{checks++;try{action.run();}catch(IOException expected){return;}throw new AssertionError("Camera request accepted invalid identity/data");}
    static int run(Path temporary)throws Exception{
        checks=0;File root=temporary.resolve("camera").toFile();yes(root.mkdirs());
        FakeClient peer=new FakeClient();SharedCamera camera=new SharedCamera(root.getPath(),(host,port,fuji)->null,(connector,fuji)->peer);
        Map<String,Object> connected=call(camera,"camera.connect",SharedRuntime.map("host","192.168.1.1","port",15740,"protocol","nikon"));String session=(String)connected.get("session");yes(Boolean.TRUE.equals(connected.get("connected")));
        Map<String,Object> request=SharedRuntime.map("session",session,"raw",false,"offset",0,"limit",24);
        yes(((List<?>)call(camera,"camera.page",request).get("items")).isEmpty());
        request.put("raw",true);yes(((List<?>)call(camera,"camera.page",request).get("items")).size()==1);
        Map<String,Object> thumb=SharedRuntime.map("session",session,"handle",1);
        Map<String,Object> preview=call(camera,"camera.thumbnail",thumb);File file=new File((String)preview.get("path"));
        yes(file.getParentFile().getName().equals("camera-previews"));yes(Arrays.equals(Files.readAllBytes(file.toPath()),peer.jpeg));yes(peer.large==1&&peer.small==0&&peer.originals==0);
        call(camera,"camera.thumbnail",thumb);yes(peer.large==1);yes(session.equals(preview.get("session"))&&((Number)preview.get("handle")).longValue()==1);
        rejects(()->call(camera,"camera.thumbnail",SharedRuntime.map("session","stale","handle",1)));
        rejects(()->call(camera,"camera.thumbnail",SharedRuntime.map("session",session,"handle",2)));
        rejects(()->call(camera,"camera.thumbnail",SharedRuntime.map("session",session,"handle",0)));
        thumb.put("refresh",true);peer.unsupported=true;call(camera,"camera.thumbnail",thumb);yes(peer.large==2&&peer.small==1);
        call(camera,"camera.thumbnail",thumb);yes(peer.large==2&&peer.small==2);
        peer.invalid=true;rejects(()->call(camera,"camera.thumbnail",thumb));yes(Arrays.equals(Files.readAllBytes(file.toPath()),peer.jpeg));peer.invalid=false;
        peer.changed=true;int small=peer.small;rejects(()->call(camera,"camera.thumbnail",thumb));yes(peer.small==small);peer.changed=false;
        rejects(()->camera.request("camera.thumbnail",SharedJson.encode(thumb),"cancel",()->true,v->{}));yes(peer.open);
        peer.count=2;request.put("refresh",true);yes(((List<?>)call(camera,"camera.page",request).get("items")).size()==2);
        request.put("offset",1);rejects(()->call(camera,"camera.page",request));
        SharedCameraPreviews cache=new SharedCameraPreviews(root);rejects(()->cache.cached("../../source"));
        rejects(()->cache.store(cache.key(session,7,new byte[]{7}),new byte[SharedCameraPreviews.MAX_BYTES+1],()->false));
        for(int i=0;i<70;i++)cache.store(cache.key(session,100+i,new byte[]{1}),peer.jpeg,()->false);
        yes(Objects.requireNonNull(new File(root,"camera-previews").listFiles()).length<=SharedCameraPreviews.MAX_FILES);
        byte[] large=new byte[SharedCameraPreviews.MAX_BYTES];large[0]=(byte)255;large[1]=(byte)216;large[large.length-2]=(byte)255;large[large.length-1]=(byte)217;
        for(int i=0;i<5;i++)cache.store(cache.key(session,1000+i,new byte[]{2}),large,()->false);
        long cachedBytes=0;for(File cached:Objects.requireNonNull(new File(root,"camera-previews").listFiles()))cachedBytes+=cached.length();yes(cachedBytes<=SharedCameraPreviews.CACHE_BYTES);
        yes(!new File(root,"originals").exists()&&!new File(root,"versions").exists());yes(peer.originals==0);
        camera.disconnect();rejects(()->call(camera,"camera.thumbnail",thumb));
        System.out.println("PASS "+checks+" shared camera checks; RAW-only browse, JPEG previews, fallback, refresh, session isolation and bounded cache");return checks;
    }
    private static Map<String,Object> call(SharedCamera camera,String operation,Map<String,Object> p)throws IOException{return SharedJson.object(camera.request(operation,SharedJson.encode(p),"test",()->false,v->{}));}
    private static final class FakeClient implements PhotoCameraClient {
        boolean open,unsupported,invalid,changed;int large,small,originals,count=1;
        final byte[] jpeg={(byte)255,(byte)216,(byte)255,(byte)224,1,2,(byte)255,(byte)217};
        public byte[] connect(String host,int port,byte[] guid,String name){open=true;return info();}
        public boolean isOpen(){return open;}public boolean isProtocolUnconfirmed(){return false;}public String closeReason(){return "";}public String connectedHost(){return "192.168.1.1";}public int connectedPort(){return 15740;}public String cameraIdentity(){return "fixture";}
        public void setOnClosed(Runnable listener){}public void setOnObjectAdded(LongConsumer listener){}public byte[] readAlbumDeviceInfo(){return info();}
        public byte[] getData(int op,int max,long... p)throws IOException{
            if(op==0x1004)return concat(le32(1),le32(1));
            if(op==0x1007)return count==1?concat(le32(1),le32(1)):concat(le32(2),le32(1),le32(2));
            if(op==0x1008)return new PtpObjectInfo.Builder().storageId(1).objectFormat(0xb103).filename(changed?"changed.NEF":"DSC_6522.NEF").compressedSize(27000000).imagePixWidth(6048).imagePixHeight(4024).build().toBytes();
            if(op==0x100a){small++;return invalid?new byte[]{1,2,3}:jpeg;}
            if(op==0x1009)originals++;
            throw new IOException("Unexpected fixture operation "+op);
        }
        public byte[] getLargeThumbnail(long handle)throws IOException{large++;if(unsupported)throw new PtpResponseException(0x2005,1);return jpeg;}
        public long readTo(int op,OutputStream out,long max,long expected,Progress progress,long...p)throws IOException{originals++;throw new IOException("A thumbnail must not download a source");}
        public void abortProtocol(IOException error){open=false;}public void close(){open=false;}
    }
    private static byte[] info(){int[] operations={0x1001,0x1002,0x1003,0x1004,0x1007,0x1008,0x1009,0x100a,0x90c4};ByteArrayOutputStream ops=new ByteArrayOutputStream();ops.writeBytes(le32(operations.length));for(int op:operations)ops.writeBytes(le16(op));return concat(le16(100),le32(10),le16(100),string("Fixture"),le16(0),ops.toByteArray(),le32(0),le32(0),le32(0),le32(0),string("NIKON CORPORATION"),string("Z 6_2"),string("1"),string(""));}
    private static byte[] string(String text){return text.isEmpty()?new byte[]{0}:concat(new byte[]{(byte)(text.length()+1)},(text+'\0').getBytes(StandardCharsets.UTF_16LE));}
    private static byte[] le16(long n){return new byte[]{(byte)n,(byte)(n>>>8)};}
    private static byte[] le32(long n){return new byte[]{(byte)n,(byte)(n>>>8),(byte)(n>>>16),(byte)(n>>>24)};}
    private static byte[] concat(byte[]... parts){ByteArrayOutputStream out=new ByteArrayOutputStream();for(byte[] part:parts)out.writeBytes(part);return out.toByteArray();}
}
