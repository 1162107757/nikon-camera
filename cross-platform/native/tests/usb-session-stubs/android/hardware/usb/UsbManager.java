package android.hardware.usb;
import java.util.*;
public final class UsbManager {
 private final UsbDeviceConnection connection;public final Map<String,UsbDevice> devices=new HashMap<>();
 public UsbManager(UsbDeviceConnection connection){this.connection=connection;devices.put("fixture",new UsbDevice());}
 public boolean hasPermission(UsbDevice device){return true;} public UsbDeviceConnection openDevice(UsbDevice device){return connection;}
 public Map<String,UsbDevice> getDeviceList(){return devices;}
}
