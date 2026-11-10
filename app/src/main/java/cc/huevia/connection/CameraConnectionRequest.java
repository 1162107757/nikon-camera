package cc.huevia.connection;

import android.app.Activity;
import android.content.Intent;
import cc.huevia.MainActivity;

/** Opens a connection workspace above the caller, so Back and success return to its existing UI. */
public final class CameraConnectionRequest {
    public static final int REQUEST = 7320;
    public static final String OPERATION = "cc.huevia.connection.operation";
    public static final String TRANSPORT = "cc.huevia.connection.transport";
    public static final String USB_ID = "cc.huevia.connection.usbId";
    public static final String USB_MODEL = "cc.huevia.connection.usbModel";
    public static final String USB_MANUFACTURER = "cc.huevia.connection.usbManufacturer";
    public static final String WIFI = "wifi", USB = "usb", ANY = "any";
    private CameraConnectionRequest() {}

    public static void open(Activity caller, String operation, String transport) {
        caller.startActivityForResult(new Intent(caller, MainActivity.class)
                .putExtra(OPERATION, operation).putExtra(TRANSPORT, transport), REQUEST);
    }
}
