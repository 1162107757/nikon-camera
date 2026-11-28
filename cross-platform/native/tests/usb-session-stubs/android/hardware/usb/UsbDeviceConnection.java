package android.hardware.usb;
public abstract class UsbDeviceConnection {
 public boolean claimInterface(UsbInterface i,boolean force){if(force)throw new AssertionError("Force claim is forbidden");return true;}
 public boolean releaseInterface(UsbInterface i){return true;}
 public abstract int bulkTransfer(UsbEndpoint endpoint,byte[] buffer,int offset,int length,int timeout);
 public int bulkTransfer(UsbEndpoint endpoint,byte[] buffer,int length,int timeout){return bulkTransfer(endpoint,buffer,0,length,timeout);}
 public int controlTransfer(int requestType,int request,int value,int index,byte[] buffer,int length,int timeout){throw new AssertionError("Unexpected USB control transfer");}
 public abstract void close();
}
