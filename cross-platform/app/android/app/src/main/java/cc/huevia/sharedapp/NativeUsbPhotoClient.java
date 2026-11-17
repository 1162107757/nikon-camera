package cc.huevia.sharedapp;

import android.hardware.usb.*;
import cc.huevia.album.PhotoCameraClient;
import cc.huevia.ptp.*;
import java.io.*;
import java.util.function.LongConsumer;

/** One app-owned raw PTP session, shared by photo reads and explicit slot handoffs. */
final class NativeUsbPhotoClient implements PhotoCameraClient {
    final String id;
    private final UsbDevice device;
    private final UsbManager manager;
    private volatile NativeUsbSlots channel;
    private PtpDeviceInfo info;
    private Runnable closed;
    NativeUsbPhotoClient(UsbDevice device,UsbManager manager){this.device=device;this.manager=manager;id=device.getDeviceName();}
    @Override public byte[] connect(String host,int port,byte[] guid,String name)throws IOException{
        NativeUsbSlots next=new NativeUsbSlots(device,manager);channel=next;
        try{byte[] bytes=next.openPhoto();info=PtpDeviceInfo.parseRedacted(bytes);try{info=PtpDeviceInfo.parse(bytes);}catch(PtpProtocolException optionalSerial){}if(!info.isNikonCamera())throw new IOException("未确认尼康相机身份。");return bytes;}
        catch(IOException|RuntimeException error){next.close();channel=null;if(error instanceof PtpResponseException&&((PtpResponseException)error).responseCode()==0x201e)throw new IOException("相机仍有已打开的 USB 会话。请关闭其他相机应用，拔插数据线后重新连接。",error);throw error;}
    }
    NativeUsbSlots transferSlots()throws IOException{
        NativeUsbSlots current=require();
        current.adoptSlots(next->{NativeUsbPhotoClient photo=new NativeUsbPhotoClient(device,manager);photo.channel=current;photo.info=info;return photo;});
        channel=null;closed=null;return current;
    }
    private NativeUsbSlots require()throws IOException{NativeUsbSlots current=channel;if(current==null||!isOpen())throw new IOException("USB 相机已断开或会话已移交。");return current;}
    @Override public boolean isOpen(){NativeUsbSlots current=channel;return current!=null&&current.isOpen()&&manager.getDeviceList().containsKey(id);}
    @Override public boolean isProtocolUnconfirmed(){return false;}
    @Override public String closeReason(){return isOpen()?"":"USB 相机已断开";}
    @Override public String connectedHost(){return "usb:"+id;}
    @Override public int connectedPort(){return 0;}
    @Override public String cameraIdentity(){return info==null?"":info.serialNumber();}
    @Override public void setOnClosed(Runnable listener){closed=listener;}
    // Full directory scans remain authoritative when a camera omits USB events.
    @Override public void setOnObjectAdded(LongConsumer listener){}
    @Override public byte[] readAlbumDeviceInfo()throws IOException{return getData(0x1001,1024*1024);}
    @Override public byte[] getData(int operation,int max,long...p)throws IOException{return require().photoRead(operation,max,p);}
    @Override public byte[] getLargeThumbnail(long handle)throws IOException{throw new PtpResponseException(0x2005,0);}
    @Override public long readTo(int operation,OutputStream destination,long max,long expected,Progress progress,long...p)throws IOException{
        if(operation!=0x1009||p.length!=1)throw new IOException("USB 原文件读取请求无效。");return require().photoReadTo(destination,max,expected,progress,p[0]);
    }
    @Override public void abortProtocol(IOException error){NativeUsbSlots old=channel;channel=null;if(old!=null)old.abort();notifyClosed();}
    @Override public void close(){NativeUsbSlots old=channel;channel=null;if(old!=null)old.close();notifyClosed();}
    private void notifyClosed(){Runnable listener=closed;closed=null;if(listener!=null)listener.run();}
}
