package cc.huevia.sharedapp;

import android.app.PendingIntent;
import android.content.*;
import android.hardware.usb.*;
import android.mtp.*;
import android.os.*;
import cc.huevia.album.PhotoCameraClient;
import cc.huevia.album.ConnectionTrace;
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

/** USB discovery and permission; the application owns one raw PTP session. */
final class NativeUsbCamera implements SharedCamera.WiredConnections {
    private final Context context;
    private final UsbManager manager;
    private final Handler main=new Handler(Looper.getMainLooper());
    private final String action;
    private MethodChannel.Result pending;
    private String pendingId="";
    private volatile NativeUsbPhotoClient active;
    private volatile NativeUsbSlots activeSlots;
    private volatile String activeSlotsId="";
    private final BroadcastReceiver receiver=new BroadcastReceiver(){
        @Override public void onReceive(Context ignored,Intent intent){
            UsbDevice device=intent.getParcelableExtra(UsbManager.EXTRA_DEVICE);
            if(device==null)return;
            if(UsbManager.ACTION_USB_DEVICE_DETACHED.equals(intent.getAction())){
                NativeUsbPhotoClient current=active;if(current!=null&&current.id.equals(device.getDeviceName()))current.abortProtocol(new IOException("USB 相机已拔出。"));
                NativeUsbSlots slots=activeSlots;if(slots!=null&&activeSlotsId.equals(device.getDeviceName()))slots.abort();
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
    @Override public PhotoCameraClient create(String id)throws IOException{UsbDevice device=find(id);if(!manager.hasPermission(device))throw new IOException("请先允许 USB 相机访问权限。");NativeUsbSlots slots=activeSlots;if(slots!=null)slots.close();if(active!=null)active.close();NativeUsbPhotoClient next=new NativeUsbPhotoClient(device,manager);active=next;return next;}
    @Override public SharedSlots.Transport openSlots(String id)throws IOException{UsbDevice device=find(id);if(!manager.hasPermission(device))throw new IOException("请先允许 USB 相机访问权限。");NativeUsbPhotoClient current=active;if(current!=null)current.close();NativeUsbSlots previous=activeSlots;if(previous!=null)previous.close();NativeUsbSlots next=new NativeUsbSlots(device,manager);activeSlotsId=id;activeSlots=next;return next;}
    @Override public SharedSlots.Transport adoptSlots(String id,PhotoCameraClient photo)throws IOException{
        if(!(photo instanceof NativeUsbPhotoClient)||!((NativeUsbPhotoClient)photo).id.equals(id))return null;
        find(id);NativeUsbSlots next=((NativeUsbPhotoClient)photo).transferSlots();active=null;activeSlots=next;activeSlotsId=id;return next;
    }
    void dispose(){finishPermission(false,"USB 权限选择已取消。");NativeUsbPhotoClient current=active;if(current!=null)current.close();NativeUsbSlots slots=activeSlots;if(slots!=null)slots.close();context.unregisterReceiver(receiver);}

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
