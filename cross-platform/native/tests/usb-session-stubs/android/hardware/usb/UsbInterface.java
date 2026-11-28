package android.hardware.usb;
public final class UsbInterface { public int getId(){return 0;} public int getInterfaceClass(){return 6;} public int getInterfaceSubclass(){return 1;} public int getInterfaceProtocol(){return 1;} public int getEndpointCount(){return 2;} public UsbEndpoint getEndpoint(int i){return new UsbEndpoint(i==0?128:0);} }
