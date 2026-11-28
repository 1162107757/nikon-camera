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
            public SharedWiredRemote.Wire remoteWire(PhotoCameraClient photo){return peer;}
        });
        yes(((List<?>)call(camera,"camera.usb.devices",Map.of()).get("items")).size()==1);
        Map<String,Object> connect=SharedRuntime.map("transport","usb","deviceId","fixture","protocol","nikon");Map<String,Object> status=call(camera,"camera.connect",connect);String session=(String)status.get("session");
        yes(Boolean.TRUE.equals(status.get("connected")));yes(status.get("transport").equals("usb"));yes(Boolean.TRUE.equals(status.get("supportsLive")));
        Map<String,Object> page=call(camera,"camera.page",SharedRuntime.map("session",session,"limit",24));yes(((List<?>)page.get("items")).size()==1);
        Map<String,Object> request=SharedRuntime.map("session",session,"handle",1);Map<String,Object> saved=call(camera,"camera.download",request);
        yes(Arrays.equals(Files.readAllBytes(Paths.get((String)saved.get("path"))),peer.jpeg));yes(((Number)saved.get("bytes")).longValue()==peer.jpeg.length);
        rejects(()->call(camera,"camera.download",SharedRuntime.map("session","stale","handle",1)));
        rejects(()->call(camera,"camera.connect",SharedRuntime.map("transport","invalid","protocol","nikon")));yes(peer.open);
        Map<String,Object> started=call(camera,"camera.live.start",SharedRuntime.map("session",session));
        rejects(()->call(camera,"camera.remote.open",Map.of("session",session)));
        call(camera,"camera.live.stop",SharedRuntime.map("session",session,"watchId",started.get("watchId")));yes(peer.open);
        Map<String,Object> remote=call(camera,"camera.remote.open",Map.of("session",session));
        yes(Boolean.TRUE.equals(remote.get("liveView"))&&Boolean.TRUE.equals(remote.get("capture"))
                &&Boolean.TRUE.equals(remote.get("autoFocus"))&&Boolean.TRUE.equals(remote.get("exposureControls")));
        Map<String,Object> scope=SharedRuntime.map("session",session,"remoteId",remote.get("remoteId"));
        rejects(()->call(camera,"camera.page",Map.of("session",session)));
        rejects(()->call(camera,"camera.live.start",Map.of("session",session)));
        rejects(()->call(camera,"camera.slots.open",Map.of("session",session)));
        Map<String,Object> view=new LinkedHashMap<>(scope);view.put("enabled",true);
        call(camera,"camera.remote.view",view);
        yes(Boolean.TRUE.equals(call(camera,"camera.remote.frame",scope).get("ready")));
        call(camera,"camera.remote.focus",scope);yes(peer.commands.contains(0x90c1));
        Map<String,Object> change=new LinkedHashMap<>(scope);change.put("code",0x5007);change.put("value",400);
        peer.descriptorBusy = 1;
        List<?> choices = (List<?>)call(camera,"camera.remote.exposure.options",change).get("choices");
        yes(choices.size()==2 && ((Number)choices.get(0)).intValue()==280
                && ((Number)choices.get(1)).intValue()==400);
        peer.writeBusy = 1;
        Map<String,Object> setting = call(camera,"camera.remote.exposure.set",change);
        yes(!setting.containsKey("notice") && peer.aperture==400 && peer.writes==2);
        peer.readyBusy = 2;
        Map<String,Object> blocked = call(camera,"camera.remote.capture",scope);
        yes(blocked.get("notice").toString().contains("未发送快门") && peer.releaseRequests==0);
        peer.readyBusy = 1;
        peer.releaseBusy = true;
        Map<String,Object> rejected = call(camera,"camera.remote.capture",scope);
        yes(rejected.get("notice").toString().contains("机身未接受快门"));
        yes(rejected.get("action") instanceof Map &&
                Boolean.FALSE.equals(((Map<?,?>)rejected.get("action")).get("pending")));
        yes(peer.releaseRequests==1 && peer.exposures==0);
        peer.releaseBusy = false;
        Map<String,Object> captured = call(camera,"camera.remote.capture",scope);
        yes(!captured.containsKey("notice") && peer.releaseRequests==2 && peer.exposures==1);
        call(camera,"camera.remote.check",scope);
        call(camera,"camera.remote.close",scope);
        yes(peer.commands.get(peer.commands.size()-1)==0x9202&&peer.open);
        rejects(()->call(camera,"camera.remote.focus",scope));
        yes(session.equals(call(camera,"camera.status",Map.of()).get("session")));
        yes(!((List<?>)call(camera,"camera.page",Map.of("session",session)).get("items")).isEmpty());
        camera.disconnect();yes(!peer.open);rejects(()->call(camera,"camera.download",request));
        yes(Files.list(root.toPath().resolve("originals")).noneMatch(path->path.toString().endsWith(".part")));
        System.out.println("PASS "+checks+" wired camera checks; native selection, no Wi-Fi, validated original download, session isolation and disconnect");return checks+WiredLiveBoundaryTest.run(temporary);
    }
    private static Map<String,Object> call(SharedCamera camera,String op,Map<String,Object> p)throws IOException{return SharedJson.object(camera.request(op,SharedJson.encode(p),"wired-test",()->false,v->{}));}
    private static final class Peer implements PhotoCameraClient,SharedWiredRemote.Wire{
        boolean open, releaseBusy;
        int aperture=280, descriptorBusy, readyBusy, writes, writeBusy, releaseRequests, exposures;
        final List<Integer> commands=new ArrayList<>();
        final byte[] jpeg={(byte)255,(byte)216,1,2,3,4,(byte)255,(byte)217};
        public byte[] connect(String h,int p,byte[] g,String n){open=true;return info();}
        public boolean isOpen(){return open;}public boolean isProtocolUnconfirmed(){return false;}public String closeReason(){return "";}public String connectedHost(){return "usb:fixture";}public int connectedPort(){return 0;}public String cameraIdentity(){return "";}
        public void setOnClosed(Runnable r){}public void setOnObjectAdded(LongConsumer r){}public byte[] readAlbumDeviceInfo(){return info();}
        public byte[] getData(int op,int max,long...p)throws IOException{
            if(op==0x1004||op==0x1007)return concat(le32(1),le32(1));
            if(op==0x1008)return new PtpObjectInfo.Builder().storageId(1).objectFormat(0x3801).compressedSize(jpeg.length).imagePixWidth(4).imagePixHeight(3).filename("USB.JPG").build().toBytes();
            if(op==0x100a)return jpeg;throw new IOException("Unexpected read");
        }
        public byte[] getLargeThumbnail(long h)throws IOException{throw new PtpResponseException(0x2005,0);}
        public byte[] exchange(int op,int max,byte[] outgoing,long...p)throws IOException{
            if(op==0x9203)return new byte[]{-1,-40,-1,-64,0,8,8,0,3,0,4,1,-1,-39,0,0};
            if(op==0x1014||op==0x1015){
                int code=(int)p[0];
                if (op==0x1014 && descriptorBusy>0) {
                    descriptorBusy--;
                    throw new PtpResponseException(0x2019, 0);
                }
                byte[] value=code==0x500d?le32(100):le16(code==0x5013?1:aperture);
                if(op==0x1015)return value;
                byte[] choices=code==0x5007?concat(new byte[]{2},le16(2),le16(280),le16(400)):new byte[]{0};
                return concat(le16(code),le16(code==0x500d?6:4),new byte[]{1},value,value,choices);
            }
            if(op==0x1016){
                yes(p.length==1&&p[0]==0x5007&&Arrays.equals(outgoing,le16(400)));
                writes++;
                if (writeBusy>0) { writeBusy--; throw new PtpResponseException(0x2019, 0); }
                aperture=400;return new byte[0];
            }
            if (op==0x90c8 && readyBusy>0) { readyBusy--; throw new PtpResponseException(0x2019, 0); }
            if (op==0x9207) {
                releaseRequests++;
                if (releaseBusy) throw new PtpResponseException(0x2019, 0);
                exposures++;
            }
            if(max==0){commands.add(op);return new byte[0];}
            if(op==0x1007&&exposures>0)return concat(le32(2),le32(1),le32(2));
            return getData(op,max,p);
        }
        public long readTo(int op,OutputStream out,long max,long expected,Progress progress,long...p)throws IOException{out.write(jpeg);progress.onProgress(jpeg.length,jpeg.length);return jpeg.length;}
        public void abortProtocol(IOException f){close();}public void close(){open=false;}
    }
    private static byte[] text(String s){ByteArrayOutputStream o=new ByteArrayOutputStream();if(s.isEmpty()){o.write(0);return o.toByteArray();}o.write(s.length()+1);for(char c:s.toCharArray())o.writeBytes(le16(c));o.writeBytes(le16(0));return o.toByteArray();}
    private static byte[] info() {
        int[] ops = {0x1001, 0x1002, 0x1003, 0x1004, 0x1007, 0x1008, 0x1009, 0x100a,
                0x1014, 0x1015, 0x1016, 0x9201, 0x9202, 0x9203, 0x9207, 0x90c1, 0x90c8};
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        out.writeBytes(le32(ops.length));
        for (int op : ops) out.writeBytes(le16(op));
        return concat(le16(100), le32(10), le16(100), text(""), le16(0), out.toByteArray(),
                le32(0), le32(3), le16(0x5007), le16(0x500d), le16(0x5013), le32(0), le32(0),
                text("NIKON CORPORATION"), text("USB Fixture"), text("1"), text(""));
    }
    private static byte[] le16(int n){return new byte[]{(byte)n,(byte)(n>>>8)};}private static byte[] le32(int n){return new byte[]{(byte)n,(byte)(n>>>8),(byte)(n>>>16),(byte)(n>>>24)};}
    private static byte[] concat(byte[]...parts){ByteArrayOutputStream o=new ByteArrayOutputStream();for(byte[] p:parts)o.writeBytes(p);return o.toByteArray();}
    public static void main(String[] args)throws Exception{run(Files.createTempDirectory("wired-camera-test-"));}
}
