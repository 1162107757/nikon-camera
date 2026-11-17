package cc.huevia.sharedapp;

import android.hardware.usb.*;
import cc.huevia.album.PhotoCameraClient;
import cc.huevia.ptp.*;
import cc.huevia.shared.*;
import cc.huevia.library.SharedJson;
import java.io.*;
import java.nio.file.*;
import java.util.*;

/** Executes the production raw USB adapter against fragmented wire replies, never a camera mock UI. */
public final class NativeUsbSessionBoundaryTest {
 private static int checks;
 private static void yes(boolean value){checks++;if(!value)throw new AssertionError("USB session check "+checks);}
 interface Action {void run()throws Exception;}
 private static void rejects(Action action)throws Exception{checks++;try{action.run();}catch(IOException expected){return;}throw new AssertionError("Invalid USB transaction accepted");}
 private static int u16(byte[] b,int i){return (b[i]&255)|((b[i+1]&255)<<8);}
 private static long u32(byte[] b,int i){return (u16(b,i)&65535L)|((long)u16(b,i+2)<<16);}
 private static byte[] info(){Writer out=new Writer();out.u16(100).u32(10).u16(100).text("").u16(0);out.u32(11);for(int op:new int[]{0x1001,0x1002,0x1003,0x1004,0x1007,0x1008,0x1009,0x100a,0x90cc,0x90cd,0x90cf})out.u16(op);for(int i=0;i<4;i++)out.u32(0);return out.text("NIKON CORPORATION").text("USB fixture").text("1").text("serial-123").bytes();}
 private static final class Writer {
  final ByteArrayOutputStream out=new ByteArrayOutputStream();Writer u16(int n){out.write(n);out.write(n>>>8);return this;}Writer u32(long n){for(int i=0;i<4;i++)out.write((int)(n>>>(8*i)));return this;}
  Writer text(String value){if(value.isEmpty()){out.write(0);return this;}out.write(value.length()+1);for(char c:value.toCharArray())u16(c);u16(0);return this;}byte[] bytes(){return out.toByteArray();}
 }
 private static final class Wire extends UsbDeviceConnection {
  final List<String> commands=new ArrayList<>();final ArrayDeque<Byte> inbound=new ArrayDeque<>();
  byte[] original=new byte[1024*1024+31];boolean alreadyOpen,lostAck,wrongSize,closed;int closes,fragment=73;
  Wire(){for(int i=0;i<original.length;i++)original[i]=(byte)(i*31);}
  void queue(byte[] bytes){for(byte b:bytes)inbound.add(b);}
  public int bulkTransfer(UsbEndpoint endpoint,byte[] bytes,int at,int count,int timeout){
   if(closed)return -1;
   if(endpoint.getDirection()==128){if(inbound.isEmpty())return -1;int n=Math.min(count,Math.min(fragment,inbound.size()));for(int i=0;i<n;i++)bytes[at+i]=inbound.remove();return n;}
   if(count==0)return 0;
   int op=u16(bytes,at+6);long tx=u32(bytes,at+8);commands.add(Integer.toHexString(op)+":"+tx);
   if(op==0x1002&&alreadyOpen){queue(PtpContainer.response(0x201e,tx).toBytes());return count;}
   if(op==0x1001||op==0x1004||op==0x90cf||op==0x90cc){byte[] payload=op==0x1001?info():op==0x90cf?new byte[28]:op==0x90cc?new byte[36]:new byte[]{1,0,0,0,1,0,0,0};if(op==0x90cc){payload[0]=1;payload[2]='P';}queue(PtpContainer.data(op,tx,payload).toBytes());queue(PtpContainer.response(0x2001,tx).toBytes());}
   else if(op==0x1009){byte[] payload=wrongSize?new byte[5]:original;queue(PtpContainer.data(op,tx,payload).toBytes());if(!lostAck)queue(PtpContainer.response(0x2001,tx).toBytes());}
   else queue(PtpContainer.response(0x2001,tx).toBytes());return count;
  }
  public void close(){closed=true;closes++;}
 }
 private static NativeUsbPhotoClient photo(Wire wire)throws IOException{NativeUsbPhotoClient client=new NativeUsbPhotoClient(new UsbDevice(),new UsbManager(wire));client.connect("usb",0,new byte[16],"test");return client;}
 public static void main(String[] args)throws Exception{
  Wire wire=new Wire();NativeUsbPhotoClient photo=photo(wire);yes(photo.isOpen());photo.getData(0x1004,100);
  NativeUsbSlots slots=photo.transferSlots();yes(!photo.isOpen());yes(slots.inheritedTransaction()==2);
  photo.close();yes(slots.isOpen());yes(wire.closes==0);
  rejects(()->slots.command(0x1002,0,1));yes(Collections.frequency(wire.commands,"1002:0")==1);
  slots.read(0x1001,2);PhotoCameraClient restored=slots.releaseAlbum(3);yes(restored!=null&&restored.isOpen());restored.getData(0x1004,100);
  yes(wire.commands.contains("1004:3"));yes(wire.commands.stream().noneMatch(s->s.startsWith("1003:")));
  NativeUsbSlots again=((NativeUsbPhotoClient)restored).transferSlots();yes(again.inheritedTransaction()==4);again.read(0x1001,4);
  PhotoCameraClient second=again.releaseAlbum(5);second.close();second.close();yes(wire.closes==1);yes(Collections.frequency(wire.commands,"1003:5")==1);
  Wire stream=new Wire();NativeUsbPhotoClient streaming=photo(stream);ByteArrayOutputStream result=new ByteArrayOutputStream();long[] received={0};
  long total=streaming.readTo(0x1009,result,2*1024*1024,stream.original.length,(n,max)->{yes(n>received[0]&&n<=max);received[0]=n;},7);
  yes(total==stream.original.length);yes(Arrays.equals(result.toByteArray(),stream.original));streaming.getData(0x1004,100);yes(stream.commands.contains("1004:2"));streaming.close();
  for(boolean mismatch:new boolean[]{false,true}){
   Wire failed=new Wire();failed.lostAck=!mismatch;failed.wrongSize=mismatch;NativeUsbPhotoClient client=photo(failed);
   rejects(()->client.readTo(0x1009,new ByteArrayOutputStream(),2*1024*1024,failed.original.length,(n,max)->{},9));yes(!client.isOpen());yes(Collections.frequency(failed.commands,"1009:1")==1);yes(failed.commands.stream().noneMatch(s->s.startsWith("1003:")));
  }
  Wire occupied=new Wire();occupied.alreadyOpen=true;rejects(()->photo(occupied));yes(occupied.commands.equals(Arrays.asList("1001:0","1002:0")));yes(occupied.closes==1);
  // Exercise the real SharedCamera -> SharedSlots -> native USB adapter path as well.
  Wire owned=new Wire();UsbManager manager=new UsbManager(owned);Path root=Files.createTempDirectory("huevia-usb-adoption-");
  SharedCamera camera=new SharedCamera(root.toString(),(h,p,f)->{throw new AssertionError("USB opened Wi-Fi");},new SharedCamera.WiredConnections(){
   public String devices(){return "{\"items\":[]}";}
   public PhotoCameraClient create(String id){return new NativeUsbPhotoClient(new UsbDevice(),manager);}
   public SharedSlots.Transport adoptSlots(String id,PhotoCameraClient original)throws IOException{return ((NativeUsbPhotoClient)original).transferSlots();}
   public SharedSlots.Transport openSlots(String id){throw new AssertionError("USB reopened a live session");}
  });
  Map<String,Object> connected=call(camera,"camera.connect",SharedRuntime.map("transport","usb","protocol","nikon","deviceId","fixture"));String session=(String)connected.get("session");yes(Boolean.TRUE.equals(connected.get("supportsLive")));
  Map<String,Object> opened=call(camera,"camera.slots.open",SharedRuntime.map("session",session));String slotSession=(String)opened.get("session");yes(((List<?>)opened.get("items")).size()==9);
  yes(owned.commands.stream().filter(s->s.startsWith("1002:")).count()==1);yes(owned.commands.stream().noneMatch(s->s.startsWith("1003:")));
  call(camera,"camera.slots.close",SharedRuntime.map("session",slotSession));Map<String,Object> status=call(camera,"camera.status",Map.of());yes(Boolean.TRUE.equals(status.get("photoConnected")));yes(status.get("session").equals(session));yes(owned.closes==0);
  call(camera,"camera.disconnect",SharedRuntime.map("session",session));yes(owned.commands.stream().filter(s->s.startsWith("1003:")).count()==1);yes(owned.closes==1);
  if(!root.toRealPath().startsWith(Paths.get(System.getProperty("java.io.tmpdir")).toRealPath())||!root.getFileName().toString().startsWith("huevia-usb-adoption-"))throw new IOException("Unsafe USB fixture cleanup");
  try(java.util.stream.Stream<Path> paths=Files.walk(root)){for(Path path:(Iterable<Path>)paths.sorted(Comparator.reverseOrder())::iterator)Files.delete(path);}
  System.out.println("PASS "+checks+" production USB session checks; one OpenSession, photo-slot-photo handoff, monotonic transactions, fragmented original streaming, no replay after lost ACK and no takeover of external sessions");
 }
 private static Map<String,Object> call(SharedCamera camera,String operation,Map<String,Object> payload)throws IOException{return SharedJson.object(camera.request(operation,SharedJson.encode(payload),"usb-e2e",()->false,value->{}));}
}
