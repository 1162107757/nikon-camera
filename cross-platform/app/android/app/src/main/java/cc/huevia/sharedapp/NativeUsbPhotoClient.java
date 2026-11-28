package cc.huevia.sharedapp;

import android.hardware.usb.*;
import cc.huevia.album.PhotoCameraClient;
import cc.huevia.ptp.*;
import cc.huevia.shared.SharedWiredRemote;
import java.io.*;
import java.util.function.LongConsumer;

/** One app-owned raw PTP session, shared by photo reads and explicit slot handoffs. */
final class NativeUsbPhotoClient implements PhotoCameraClient, SharedWiredRemote.Wire {
    final String id;
    private final UsbDevice device;
    private final UsbManager manager;
    private final boolean recoverSession;
    private volatile NativeUsbSlots channel;
    private volatile boolean retired;
    private PtpDeviceInfo info;
    private Runnable closed;
    NativeUsbPhotoClient(UsbDevice device,UsbManager manager){this(device,manager,false);}
    NativeUsbPhotoClient(UsbDevice device,UsbManager manager,boolean recoverSession){this.device=device;this.manager=manager;this.recoverSession=recoverSession;id=device.getDeviceName();}
    @Override public byte[] connect(String host,int port,byte[] guid,String name)throws IOException{
        if(retired)throw new IOException("USB 相机连接已取消。");
        NativeUsbSlots next=new NativeUsbSlots(device,manager);
        synchronized(this){if(!retired&&channel==null)channel=next;}
        if(retired||channel!=next){
            next.abort();
            removeChannel(next);
            throw new IOException("USB 相机连接已取消。");
        }
        try{byte[] bytes=next.openPhoto(recoverSession);info=PtpDeviceInfo.parseRedacted(bytes);try{info=PtpDeviceInfo.parse(bytes);}catch(PtpProtocolException optionalSerial){}if(!info.isNikonCamera())throw new IOException("未确认尼康相机身份。");return bytes;}
        catch(IOException|RuntimeException error){next.close();removeChannel(next);throw error;}
    }
    synchronized NativeUsbSlots transferSlots()throws IOException{
        NativeUsbSlots current=require();
        current.adoptSlots(next->{NativeUsbPhotoClient photo=new NativeUsbPhotoClient(device,manager);photo.channel=current;photo.info=info;return photo;});
        retired=true;channel=null;closed=null;return current;
    }
    private NativeUsbSlots require()throws IOException{NativeUsbSlots current=channel;if(current==null||!isOpen())throw new IOException("USB 相机已断开或会话已移交。");return current;}
    @Override public boolean isOpen(){NativeUsbSlots current=channel;return !retired&&current!=null&&current.isOpen()&&manager.getDeviceList().containsKey(id);}
    @Override public boolean isProtocolUnconfirmed(){return false;}
    @Override public String closeReason(){return isOpen()?"":"USB 相机已断开";}
    @Override public String connectedHost(){return "usb:"+id;}
    @Override public int connectedPort(){return 0;}
    @Override public String cameraIdentity(){return info==null?"":info.serialNumber();}
    @Override public synchronized void setOnClosed(Runnable listener){closed=listener;}
    // Full directory scans remain authoritative when a camera omits USB events.
    @Override public void setOnObjectAdded(LongConsumer listener){}
    @Override public byte[] readAlbumDeviceInfo()throws IOException{return getData(0x1001,1024*1024);}
    @Override public byte[] getData(int operation,int max,long...p)throws IOException{return require().photoRead(operation,max,p);}
    @Override public byte[] exchange(int operation,int maximum,byte[] outgoing,long... parameters)throws IOException{
        return require().remoteExchange(operation,maximum,outgoing,parameters);
    }
    @Override public byte[] getLargeThumbnail(long handle)throws IOException{throw new PtpResponseException(0x2005,0);}
    @Override public long readTo(int operation,OutputStream destination,long max,long expected,Progress progress,long...p)throws IOException{
        if(operation!=0x1009||p.length!=1)throw new IOException("USB 原文件读取请求无效。");return require().photoReadTo(destination,max,expected,progress,p[0]);
    }
    @Override public void abortProtocol(IOException error){
        NativeUsbSlots old;
        synchronized(this){retired=true;old=channel;}
        if(old!=null){
            try{old.abort();}finally{if(old.isReleased())removeChannel(old);}
        }
        notifyClosed();
    }
    @Override public void close(){close(false);}
    void closePhotoGracefully(){close(true);}
    private void close(boolean drain){
        NativeUsbSlots old;
        synchronized(this){retired=true;old=channel;}
        if(old!=null){
            // Keep the exact transport reachable until a concurrent detach can abort it.
            try{if(drain)old.closePhotoGracefully();else old.close();}
            finally{if(old.isReleased())removeChannel(old);}
        }
        notifyClosed();
    }
    private synchronized void removeChannel(NativeUsbSlots old){if(channel==old)channel=null;}
    private void notifyClosed(){
        Runnable listener;
        synchronized(this){listener=closed;closed=null;}
        if(listener!=null)listener.run();
    }
}
