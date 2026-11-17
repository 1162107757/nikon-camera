package android.hardware.usb;
public final class UsbDevice { public int getVendorId(){return 0x04b0;} public int getInterfaceCount(){return 1;} public UsbInterface getInterface(int i){return new UsbInterface();} public String getDeviceName(){return "fixture";} }
