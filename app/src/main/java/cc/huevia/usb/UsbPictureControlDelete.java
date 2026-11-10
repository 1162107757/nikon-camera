package cc.huevia.usb;

import android.hardware.usb.UsbDevice;
import android.hardware.usb.UsbManager;
import java.io.IOException;
import java.util.concurrent.atomic.AtomicBoolean;

/** USB owns and closes one dedicated deletion-only transport; no automatic retry. */
public final class UsbPictureControlDelete implements AutoCloseable {
    private final AtomicBoolean started=new AtomicBoolean();private volatile boolean closed;private volatile PtpUsbTransport active;private volatile int activeDeviceId=-1;
    public void delete(UsbDevice device,UsbManager manager,PictureControlDeleteSession.Confirmation confirmation,PictureControlDeleteSession.Result result)throws IOException{
        if(!started.compareAndSet(false,true)||closed)throw new IOException("删除任务已取消或已执行。");
        activeDeviceId=device==null?-1:device.getDeviceId();
        PictureControlDeleteSession session=null;PtpUsbTransport transport=null;
        try{
            transport=new PtpUsbTransport(device,manager,result.commands,PtpUsbTransport.Mode.DELETE_CONFIRMED_PC);active=transport;
            if(closed)throw new IOException("删除已取消。");session=new PictureControlDeleteSession(transport,confirmation,result);session.run();
        }finally{
            try{if(session!=null&&session.mayCloseSession()&&transport!=null&&!closed&&!transport.isProtocolUnconfirmed())try{session.closeSession();}catch(IOException failure){result.cleanupError=failure.getMessage();}}
            finally{active=null;activeDeviceId=-1;if(transport!=null)transport.close();}
        }
    }
    public boolean isProbingDevice(UsbDevice device){return device!=null&&activeDeviceId==device.getDeviceId();}
    @Override public void close(){closed=true;PtpUsbTransport transport=active;if(transport!=null)transport.close();}
}
