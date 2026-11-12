package cc.huevia.sharedapp;

import android.app.PendingIntent;
import android.content.*;
import android.hardware.usb.*;
import android.mtp.*;
import android.os.*;
import cc.huevia.album.PhotoCameraClient;
import cc.huevia.library.SharedJson;
import cc.huevia.ptp.*;
import cc.huevia.shared.*;
import io.flutter.plugin.common.MethodChannel;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.text.SimpleDateFormat;
import java.util.*;
import java.util.function.LongConsumer;

/** Android's OS PTP/MTP stack owns the session; this adapter exposes reads only. */
final class NativeUsbCamera implements SharedCamera.WiredConnections {
    private final Context context;
    private final UsbManager manager;
    private final Handler main=new Handler(Looper.getMainLooper());
    private final String action;
    private MethodChannel.Result pending;
    private String pendingId="";
    private volatile Client active;
    private final BroadcastReceiver receiver=new BroadcastReceiver(){
        @Override public void onReceive(Context ignored,Intent intent){
            UsbDevice device=intent.getParcelableExtra(UsbManager.EXTRA_DEVICE);
            if(device==null)return;
            if(UsbManager.ACTION_USB_DEVICE_DETACHED.equals(intent.getAction())){
                Client current=active;if(current!=null&&current.id.equals(device.getDeviceName()))current.close();
                if(device.getDeviceName().equals(pendingId))finishPermission(false,"相机已拔出，请重新连接。");
            }else if(action.equals(intent.getAction())&&device.getDeviceName().equals(pendingId)){
                finishPermission(manager.hasPermission(device),"未获得 USB 访问权限，请在系统提示中允许访问相机。");
            }
        }
    };
    NativeUsbCamera(Context context){
        this.context=context;manager=(UsbManager)context.getSystemService(Context.USB_SERVICE);action=context.getPackageName()+".WIRED_CAMERA_PERMISSION";
        IntentFilter filter=new IntentFilter(action);filter.addAction(UsbManager.ACTION_USB_DEVICE_DETACHED);
        if(Build.VERSION.SDK_INT>=33)context.registerReceiver(receiver,filter,Context.RECEIVER_NOT_EXPORTED);else context.registerReceiver(receiver,filter);
    }
    private static boolean supported(UsbDevice device){
        if(device.getVendorId()!=0x04b0)return false;
        for(int i=0;i<device.getInterfaceCount();i++)if(device.getInterface(i).getInterfaceClass()==UsbConstants.USB_CLASS_STILL_IMAGE)return true;return false;
    }
    private UsbDevice find(String id)throws IOException{
        if(manager!=null)for(UsbDevice device:manager.getDeviceList().values())if(device.getDeviceName().equals(id)&&supported(device))return device;
        throw new IOException("未找到该 USB 相机，请检查相机开机、数据线及 OTG 连接。");
    }
    @Override public String devices(){
        List<Object> rows=new ArrayList<>();if(manager!=null)for(UsbDevice device:manager.getDeviceList().values())if(supported(device))rows.add(SharedRuntime.map("id",device.getDeviceName(),"name",device.getProductName()==null?"Nikon USB 相机":device.getProductName(),"permission",manager.hasPermission(device)));
        return SharedJson.encode(SharedRuntime.map("items",rows,"transport","usb"));
    }
    void requestPermission(String id,MethodChannel.Result reply){
        if(pending!=null){reply.error("BUSY","请先完成当前 USB 权限选择。",null);return;}
        try{
            UsbDevice device=find(id);if(manager.hasPermission(device)){reply.success(SharedJson.encode(SharedRuntime.map("granted",true)));return;}
            pending=reply;pendingId=id;
            int flags=PendingIntent.FLAG_UPDATE_CURRENT|(Build.VERSION.SDK_INT>=31?PendingIntent.FLAG_MUTABLE:0);
            manager.requestPermission(device,PendingIntent.getBroadcast(context,49320,new Intent(action).setPackage(context.getPackageName()),flags));
            main.postDelayed(()->{if(pending==reply)finishPermission(false,"USB 授权超时，请重试连接。");},45000);
        }catch(Exception failure){if(pending==reply){pending=null;pendingId="";}reply.error("USB_PERMISSION",failure.getMessage(),null);}
    }
    private void finishPermission(boolean granted,String message){MethodChannel.Result reply=pending;pending=null;pendingId="";if(reply!=null){if(granted)reply.success(SharedJson.encode(SharedRuntime.map("granted",true)));else reply.error("USB_PERMISSION",message,null);}}
    @Override public PhotoCameraClient create(String id)throws IOException{UsbDevice device=find(id);if(!manager.hasPermission(device))throw new IOException("请先允许 USB 相机访问权限。");Client next=new Client(device);active=next;return next;}
    void dispose(){finishPermission(false,"USB 权限选择已取消。");Client current=active;if(current!=null)current.close();context.unregisterReceiver(receiver);}

    private final class Client implements PhotoCameraClient {
        final UsbDevice device;final String id;volatile MtpDevice mtp;volatile boolean open;Runnable closed;MtpDeviceInfo info;
        Client(UsbDevice device){this.device=device;id=device.getDeviceName();}
        @Override public byte[] connect(String host,int port,byte[] guid,String name)throws IOException{
            UsbDeviceConnection connection=manager.openDevice(device);if(connection==null)throw new IOException("无法打开 USB 相机，请检查权限及其他相机应用。");
            MtpDevice next=new MtpDevice(device);mtp=next;
            if(!next.open(connection)){connection.close();mtp=null;throw new IOException("USB 相机被占用或未启用 PTP/MTP，请关闭其他相机应用后重连。");}
            open=true;info=next.getDeviceInfo();if(info==null){close();throw new IOException("无法读取 USB 相机身份。");}return deviceInfo();
        }
        private MtpDevice require()throws IOException{MtpDevice current=mtp;if(!open||current==null)throw new IOException("USB 相机已断开，请重新连接。");return current;}
        @Override public boolean isOpen(){return open&&manager.getDeviceList().containsKey(id);}
        @Override public boolean isProtocolUnconfirmed(){return false;}
        @Override public String closeReason(){return open?"":"USB 相机已断开";}
        @Override public String connectedHost(){return "usb:"+id;}
        @Override public int connectedPort(){return 0;}
        @Override public String cameraIdentity(){return info==null?"":info.getSerialNumber();}
        @Override public void setOnClosed(Runnable listener){closed=listener;}
        @Override public void setOnObjectAdded(LongConsumer listener){}
        @Override public byte[] readAlbumDeviceInfo()throws IOException{require();return deviceInfo();}
        private byte[] deviceInfo(){return describeDevice(info.getManufacturer(),info.getModel(),info.getVersion(),info.getSerialNumber(),info.getOperationsSupported(),info.getEventsSupported());}
        @Override public byte[] getData(int operation,int max,long... p)throws IOException{
            MtpDevice current=require();byte[] bytes;
            if(operation==0x1004&&p.length==0){bytes=array(current.getStorageIds());}
            else if(operation==0x1007&&p.length==3){int[] handles=current.getObjectHandles((int)p[0],(int)p[1],(int)p[2]);if(handles==null&&p[1]!=0)handles=current.getObjectHandles((int)p[0],0,(int)p[2]);bytes=array(handles);}
            else if(operation==0x1008&&p.length==1){MtpObjectInfo row=current.getObjectInfo((int)p[0]);if(row==null)throw new IOException("USB 照片信息读取失败，请刷新目录。");bytes=new PtpObjectInfo.Builder().storageId(Integer.toUnsignedLong(row.getStorageId())).objectFormat(row.getFormat()).protectionStatus(row.getProtectionStatus()).compressedSize(row.getCompressedSizeLong()).thumbFormat(row.getThumbFormat()).thumbCompressedSize(row.getThumbCompressedSizeLong()).thumbPixWidth(row.getThumbPixWidth()).thumbPixHeight(row.getThumbPixHeight()).imagePixWidth(row.getImagePixWidth()).imagePixHeight(row.getImagePixHeight()).imageBitDepth(row.getImagePixDepth()).parentObject(Integer.toUnsignedLong(row.getParent())).associationType(row.getAssociationType()).associationDescription(row.getAssociationDesc()).sequenceNumber(row.getSequenceNumber()).filename(row.getName()).captureDate(date(row.getDateCreated())).modificationDate(date(row.getDateModified())).build().toBytes();}
            else if(operation==0x100a&&p.length==1){bytes=current.getThumbnail((int)p[0]);}
            else throw new IOException("USB 照片连接只允许读取目录、信息及缩略图。");
            if(bytes==null||bytes.length>max)throw new IOException("USB 相机未返回有效数据或数据超出范围。");return bytes;
        }
        @Override public byte[] getLargeThumbnail(long handle)throws IOException{throw new PtpResponseException(0x2005,0);}
        @Override public long readTo(int operation,OutputStream destination,long max,long expected,Progress progress,long... p)throws IOException{
            if(operation!=0x1009||p.length!=1||expected<4||expected>max||expected>512L*1024*1024)throw new IOException("USB 原文件请求无效。");
            MtpDevice current=require();int handle=(int)p[0];long received=0;byte[] buffer=new byte[256*1024];
            boolean partial=false;for(int op:info.getOperationsSupported())if(op==0x101b)partial=true;
            if(partial){while(received<expected){require();int count=(int)Math.min(buffer.length,expected-received);long n=current.getPartialObject(handle,received,count,buffer);if(n<1||n>count)throw new IOException("USB 原文件接收中断。");destination.write(buffer,0,(int)n);received+=n;progress.onProgress(received,expected);}return received;}
            // Some cameras offer only GetObject; let Android stream it to a
            // private file rather than allocating the complete RAW in memory.
            File temporary=File.createTempFile("usb-original-",".part",context.getCacheDir());
            try{if(!current.importFile(handle,temporary.getPath())||temporary.length()!=expected)throw new IOException("USB 原文件接收不完整。");
                try(InputStream input=new FileInputStream(temporary)){int n;while((n=input.read(buffer))!=-1){require();if(received+n>expected)throw new IOException("USB 原文件大小发生变化。");destination.write(buffer,0,n);received+=n;progress.onProgress(received,expected);}}return received;
            }finally{Files.deleteIfExists(temporary.toPath());}
        }
        @Override public void abortProtocol(IOException failure){close();}
        @Override public void close(){open=false;MtpDevice current=mtp;mtp=null;if(current!=null)current.close();Runnable listener=closed;closed=null;if(listener!=null)listener.run();}
    }
    static byte[] describeDevice(String maker,String model,String version,String serial,int[] operations,int[] events){
        // MtpDeviceInfo omits the PTP vendor-extension ID. Preserve that as the
        // existing unknown-ID sentinel, never invent a Nikon extension number.
        // create() separately verifies the real USB Nikon VID and PTP interface.
        Writer out=new Writer();out.u16(100).u32(0xffffffffL).u16(100).text("").u16(0);
        out.array16(operations).array16(events).array16(new int[0]).array16(new int[0]).array16(new int[0]);
        out.text(maker).text(model).text(version).text(serial);return out.bytes();
    }
    private static String date(long seconds){if(seconds<=0)return "";SimpleDateFormat format=new SimpleDateFormat("yyyyMMdd'T'HHmmss",Locale.ROOT);format.setTimeZone(TimeZone.getTimeZone("UTC"));return format.format(new Date(seconds));}
    private static byte[] array(int[] values)throws IOException{if(values==null)throw new IOException("USB 相机目录读取失败，请重连。");if(values.length>20000)throw new IOException("USB 相机目录超出本版读取范围。");Writer out=new Writer().u32(values.length);for(int value:values)out.u32(Integer.toUnsignedLong(value));return out.bytes();}
    private static final class Writer {
        final ByteArrayOutputStream out=new ByteArrayOutputStream();
        Writer u16(int n){out.write(n);out.write(n>>>8);return this;}
        Writer u32(long n){for(int i=0;i<4;i++)out.write((int)(n>>>(i*8)));return this;}
        Writer text(String value){String s=value==null?"":value;if(s.length()>254)s=s.substring(0,254);if(s.isEmpty()){out.write(0);return this;}out.write(s.length()+1);byte[] bytes=s.getBytes(StandardCharsets.UTF_16LE);out.write(bytes,0,bytes.length);u16(0);return this;}
        Writer array16(int[] values){if(values==null)values=new int[0];u32(values.length);for(int value:values)u16(value);return this;}
        byte[] bytes(){return out.toByteArray();}
    }
}
