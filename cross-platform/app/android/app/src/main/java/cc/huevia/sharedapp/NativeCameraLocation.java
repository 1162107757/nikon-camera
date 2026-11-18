package cc.huevia.sharedapp;

import android.Manifest;
import android.annotation.SuppressLint;
import android.app.Activity;
import android.bluetooth.*;
import android.bluetooth.le.*;
import android.content.*;
import android.content.pm.PackageManager;
import android.location.Location;
import android.location.LocationListener;
import android.location.LocationManager;
import android.os.*;

import java.util.*;
import javax.crypto.Cipher;
import javax.crypto.spec.SecretKeySpec;

import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/** One explicitly selected camera, with a single serialized native operation at a time. */
@SuppressLint("MissingPermission")
final class NativeCameraLocation implements MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    static final int PERMISSION_REQUEST = 49331;
    private static final String CHANNEL = "cc.huevia/camera-location";
    private static final UUID SERVICE = nikon("0000de00"), PAIR = nikon("00002000"),
        NAME = nikon("00002002"), LOCATION = nikon("00002007"), READY = nikon("00002008");
    private static final UUID CCC = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb");
    private static final byte[] NIKON_KEY = {(byte)255, (byte)255, (byte)170, 85, 17, 34, 51, 0};

    private final Activity activity;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final MethodChannel methods;
    private final EventChannel stream;
    private final BluetoothManager bluetooth;
    private final LocationManager locationManager;
    private final Map<String, BluetoothDevice> discovered = new LinkedHashMap<>();
    private final Map<String, String> names = new LinkedHashMap<>();
    private EventChannel.EventSink events;
    private MethodChannel.Result pending;
    private String operation;
    private Runnable timeout;
    private Runnable permissionAction;
    private int permissionGeneration, generation;
    private boolean requesting, disposed, gattReady, discoveryStarted;
    private int mtu = 23;
    private BluetoothLeScanner scanner;
    private ScanCallback scan;
    private BluetoothGatt gatt;
    private UUID subscription, writing;
    private BroadcastReceiver receiver;
    private BluetoothDevice classicTarget;
    private LocationListener locator;

    NativeCameraLocation(Activity activity, BinaryMessenger messenger) {
        this.activity = activity;
        bluetooth = activity.getSystemService(BluetoothManager.class);
        locationManager = activity.getSystemService(LocationManager.class);
        methods = new MethodChannel(messenger, CHANNEL);
        stream = new EventChannel(messenger, CHANNEL + "/events");
        methods.setMethodCallHandler(this);
        stream.setStreamHandler(this);
    }

    private static UUID nikon(String prefix) {
        return UUID.fromString(prefix + "-3dd4-4255-8d62-6dc7b9bd5561");
    }

    @Override public void onListen(Object arguments, EventChannel.EventSink sink) { events = sink; }
    @Override public void onCancel(Object arguments) { events = null; stop(); }

    @Override public void onMethodCall(MethodCall call, MethodChannel.Result reply) {
        if ("stop".equals(call.method)) { stop(); reply.success(null); return; }
        if ("encrypt".equals(call.method)) {
            encrypt(call.argument("bytes"), reply);
            return;
        }
        if (disposed || pending != null || requesting) {
            reply.error("BUSY", "请等待当前蓝牙或权限操作完成。", null);
            return;
        }
        switch (call.method) {
            case "scan":
                withPermissions(reply, "scan", scanPermissions(), this::startScan);
                break;
            case "connect":
                withPermissions(reply, "connect", scanPermissions(), () -> connect(call.argument("id")));
                break;
            case "pairClassic":
                withPermissions(reply, "pairClassic", scanPermissions(), () -> pairClassic(call.argument("name")));
                break;
            case "locate":
                withPermissions(reply, "locate", new String[]{Manifest.permission.ACCESS_COARSE_LOCATION,
                    Manifest.permission.ACCESS_FINE_LOCATION}, this::locate);
                break;
            case "write":
                begin(reply, "write");
                safely(() -> write(call.argument("type"), call.argument("bytes")));
                break;
            default:
                reply.notImplemented();
        }
    }

    private void encrypt(byte[] block, MethodChannel.Result reply) {
        if (block == null || block.length != 8) {
            reply.error("PAIRING", "相机配对数据无效。", null);
            return;
        }
        try {
            Cipher cipher = Cipher.getInstance("Blowfish/ECB/NoPadding");
            cipher.init(Cipher.ENCRYPT_MODE, new SecretKeySpec(NIKON_KEY, "Blowfish"));
            reply.success(cipher.doFinal(block));
        } catch (java.security.GeneralSecurityException error) {
            reply.error("PAIRING", "此手机暂无法校验相机配对。", null);
        }
    }

    private String[] scanPermissions() {
        return Build.VERSION.SDK_INT >= 31
            ? new String[]{Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT}
            : new String[]{Manifest.permission.ACCESS_FINE_LOCATION};
    }

    private boolean granted(String permission) {
        return activity.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED;
    }

    private void begin(MethodChannel.Result reply, String name) {
        pending = reply;
        operation = name;
        generation++;
    }

    private void withPermissions(MethodChannel.Result reply, String name, String[] permissions,
                                 Runnable action) {
        begin(reply, name);
        if (Arrays.stream(permissions).allMatch(this::granted)) {
            safely(action);
            return;
        }
        requesting = true;
        permissionGeneration = generation;
        permissionAction = () -> {
            if (Arrays.stream(permissions).allMatch(this::granted)) safely(action);
            else fail("PERMISSION", "请在系统设置中允许附近设备或精确位置权限后重试。");
        };
        safely(() -> activity.requestPermissions(permissions, PERMISSION_REQUEST));
    }

    void permissionResult() {
        if (!requesting) return;
        requesting = false;
        Runnable action = permissionAction;
        permissionAction = null;
        if (!disposed && pending != null && permissionGeneration == generation && action != null) action.run();
    }

    private void safely(Runnable action) {
        try { action.run(); }
        catch (SecurityException error) { fail("PERMISSION", "蓝牙或定位权限已关闭，请在系统设置中允许。"); }
        catch (RuntimeException error) { fail("UNAVAILABLE", "蓝牙定位暂不可用，请检查系统设置后重试。"); }
    }

    private void later(int seconds, Runnable action) {
        if (timeout != null) main.removeCallbacks(timeout);
        final int requested = generation;
        timeout = () -> { if (requested == generation && pending != null) safely(action); };
        main.postDelayed(timeout, seconds * 1000L);
    }

    private MethodChannel.Result takeResult() {
        if (timeout != null) main.removeCallbacks(timeout);
        timeout = null;
        MethodChannel.Result result = pending;
        pending = null;
        operation = null;
        return result;
    }

    private void success(Object value) {
        MethodChannel.Result result = takeResult();
        if (result != null) result.success(value);
    }

    private void fail(String code, String message) {
        MethodChannel.Result result = takeResult();
        finishScan();
        finishClassic();
        finishPosition();
        if (!"LOCATION_UNAVAILABLE".equals(code)) closeGatt();
        if (result != null) result.error(code, message, null);
    }

    private BluetoothAdapter adapter() {
        BluetoothAdapter adapter = bluetooth == null ? null : bluetooth.getAdapter();
        if (adapter == null || !adapter.isEnabled()) {
            fail("BLUETOOTH_OFF", "请打开手机蓝牙后重试。");
            return null;
        }
        return adapter;
    }

    private void startScan() {
        BluetoothAdapter adapter = adapter();
        if (adapter == null) return;
        scanner = adapter.getBluetoothLeScanner();
        if (scanner == null) { fail("SCAN_FAILED", "手机暂时无法扫描蓝牙相机。"); return; }
        discovered.clear();
        names.clear();
        scan = new ScanCallback() {
            @Override public void onScanResult(int callbackType, ScanResult result) {
                main.post(() -> {
                    if (scan != this) return;
                    safely(() -> recordDevice(result));
                });
            }
            @Override public void onScanFailed(int error) {
                main.post(() -> {
                    if (scan == this) fail("SCAN_FAILED", "蓝牙搜索未完成，请稍后再试。");
                });
            }
        };
        scanner.startScan(Collections.emptyList(), new ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build(), scan);
        later(8, () -> {
            finishScan();
            List<Map<String, String>> found = new ArrayList<>();
            names.forEach((id, name) -> {
                Map<String, String> item = new HashMap<>();
                item.put("id", id);
                item.put("name", name);
                found.add(item);
            });
            success(found);
        });
    }

    private void recordDevice(ScanResult result) {
        ScanRecord record = result.getScanRecord();
        if (record == null) return;
        List<ParcelUuid> services = record.getServiceUuids();
        if (record.getManufacturerSpecificData(0x0399) == null &&
            (services == null || !services.contains(new ParcelUuid(SERVICE)))) return;
        BluetoothDevice device = result.getDevice();
        String name = record.getDeviceName();
        if (name == null || name.trim().isEmpty()) name = device.getName();
        if (name == null || name.trim().isEmpty()) return;
        String id = device.getAddress();
        discovered.put(id, device);
        names.put(id, name.trim());
    }

    private void finishScan() {
        if (scan != null && scanner != null) {
            try { scanner.stopScan(scan); } catch (RuntimeException ignored) {}
        }
        scan = null;
        scanner = null;
    }

    private void connect(String id) {
        BluetoothDevice device = discovered.get(id);
        if (device == null) { fail("SELECT_CAMERA", "请重新搜索并选择相机。"); return; }
        closeGatt();
        gatt = device.connectGatt(activity, false, callback, BluetoothDevice.TRANSPORT_LE);
        if (gatt == null) { fail("CONNECT_FAILED", "连接相机失败，请重试。"); return; }
        later(22, () -> fail("CONNECT_TIMEOUT", "相机连接超时，请检查蓝牙配对菜单。"));
    }

    private final BluetoothGattCallback callback = new BluetoothGattCallback() {
        @Override public void onConnectionStateChange(BluetoothGatt source, int status, int state) {
            fromGatt(source, () -> {
                if (status != BluetoothGatt.GATT_SUCCESS || state == BluetoothProfile.STATE_DISCONNECTED) {
                    boolean connected = gattReady;
                    fail("DISCONNECTED", "相机蓝牙已断开，请重新连接。");
                    if (connected) sendEvent("disconnected", null);
                } else if (state == BluetoothProfile.STATE_CONNECTED && "connect".equals(operation)) {
                    if (source.requestMtu(64)) {
                        main.postDelayed(() -> {
                            if (gatt == source && "connect".equals(operation) && !discoveryStarted) {
                                safely(() -> discoverServices(source));
                            }
                        }, 3000);
                    } else {
                        discoverServices(source);
                    }
                }
            });
        }

        @Override public void onMtuChanged(BluetoothGatt source, int size, int status) {
            fromGatt(source, () -> {
                if (status == BluetoothGatt.GATT_SUCCESS) mtu = size;
                if ("connect".equals(operation)) discoverServices(source);
            });
        }

        @Override public void onServicesDiscovered(BluetoothGatt source, int status) {
            fromGatt(source, () -> {
                if (!"connect".equals(operation)) return;
                if (status != BluetoothGatt.GATT_SUCCESS || characteristic(PAIR) == null ||
                    characteristic(NAME) == null || characteristic(LOCATION) == null ||
                    characteristic(READY) == null) {
                    fail("UNSUPPORTED_CAMERA", "这台相机未提供蓝牙定位服务。");
                    return;
                }
                subscribe(PAIR, BluetoothGattDescriptor.ENABLE_INDICATION_VALUE);
            });
        }

        @Override public void onDescriptorWrite(BluetoothGatt source, BluetoothGattDescriptor descriptor, int status) {
            fromGatt(source, () -> {
                UUID type = descriptor.getCharacteristic().getUuid();
                if (!"connect".equals(operation) || !type.equals(subscription)) return;
                if (status != BluetoothGatt.GATT_SUCCESS) {
                    fail("CONNECT_FAILED", "相机未允许配对通知。");
                } else if (type.equals(PAIR)) {
                    int properties = characteristic(READY).getProperties();
                    subscribe(READY, (properties & BluetoothGattCharacteristic.PROPERTY_NOTIFY) != 0
                        ? BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                        : BluetoothGattDescriptor.ENABLE_INDICATION_VALUE);
                } else {
                    subscription = null;
                    gattReady = true;
                    success(null);
                }
            });
        }

        @Override public void onCharacteristicChanged(BluetoothGatt source, BluetoothGattCharacteristic value) {
            if (Build.VERSION.SDK_INT < 33) notification(source, value.getUuid(), value.getValue());
        }

        @Override public void onCharacteristicChanged(BluetoothGatt source, BluetoothGattCharacteristic value, byte[] bytes) {
            notification(source, value.getUuid(), bytes);
        }

        @Override public void onCharacteristicWrite(BluetoothGatt source, BluetoothGattCharacteristic value, int status) {
            fromGatt(source, () -> {
                if (!"write".equals(operation) || !value.getUuid().equals(writing)) return;
                boolean isLocation = LOCATION.equals(writing);
                writing = null;
                if (status == BluetoothGatt.GATT_SUCCESS) success(null);
                else fail("WRITE_FAILED", isLocation ? "相机未接受定位，请检查相机配对状态。" : "相机未接受配对数据。");
            });
        }
    };

    private void fromGatt(BluetoothGatt source, Runnable action) {
        main.post(() -> { if (gatt == source && !disposed) safely(action); });
    }

    private void discoverServices(BluetoothGatt source) {
        if (discoveryStarted) return;
        discoveryStarted = true;
        if (!source.discoverServices()) fail("CONNECT_FAILED", "无法读取相机蓝牙服务。");
    }

    private BluetoothGattCharacteristic characteristic(UUID type) {
        BluetoothGattService service = gatt == null ? null : gatt.getService(SERVICE);
        return service == null ? null : service.getCharacteristic(type);
    }

    @SuppressWarnings("deprecation")
    private void subscribe(UUID type, byte[] value) {
        BluetoothGattCharacteristic characteristic = characteristic(type);
        BluetoothGattDescriptor descriptor = characteristic.getDescriptor(CCC);
        subscription = type;
        if (descriptor == null || !gatt.setCharacteristicNotification(characteristic, true)) {
            fail("CONNECT_FAILED", "无法接收相机蓝牙通知。");
            return;
        }
        boolean started;
        if (Build.VERSION.SDK_INT >= 33) started = gatt.writeDescriptor(descriptor, value) == BluetoothStatusCodes.SUCCESS;
        else {
            descriptor.setValue(value);
            started = gatt.writeDescriptor(descriptor);
        }
        if (!started) fail("CONNECT_FAILED", "无法接收相机蓝牙通知。");
    }

    private void notification(BluetoothGatt source, UUID type, byte[] value) {
        if (value == null || value.length > 64) return;
        byte[] bytes = value.clone();
        fromGatt(source, () -> {
            if (PAIR.equals(type)) sendEvent("pair", bytes);
            else if (READY.equals(type)) sendEvent("ready", bytes);
        });
    }

    private void sendEvent(String type, byte[] bytes) {
        if (events == null) return;
        Map<String, Object> event = new HashMap<>();
        event.put("type", type);
        if (bytes != null) event.put("bytes", bytes);
        events.success(event);
    }

    @SuppressWarnings("deprecation")
    private void write(String type, byte[] bytes) {
        if (!gattReady || type == null) { fail("DISCONNECTED", "请先连接相机蓝牙。"); return; }
        UUID id;
        int length;
        switch (type) {
            case "pair": id = PAIR; length = 17; break;
            case "name": id = NAME; length = 32; break;
            case "location": id = LOCATION; length = 41; break;
            default: fail("WRITE_FAILED", "相机蓝牙数据类型无效。"); return;
        }
        BluetoothGattCharacteristic value = characteristic(id);
        if (bytes == null || bytes.length != length || value == null) {
            fail("WRITE_FAILED", "相机蓝牙数据无效。");
            return;
        }
        if (length > mtu - 3) {
            fail("WRITE_FAILED", "相机蓝牙连接未能协商足够的数据长度，请重新连接。");
            return;
        }
        writing = id;
        boolean started;
        if (Build.VERSION.SDK_INT >= 33) {
            started = gatt.writeCharacteristic(value, bytes, BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT)
                == BluetoothStatusCodes.SUCCESS;
        } else {
            value.setWriteType(BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT);
            value.setValue(bytes);
            started = gatt.writeCharacteristic(value);
        }
        if (started) later(10, () -> fail("WRITE_TIMEOUT", "相机未回复蓝牙数据，请重新连接。"));
        else fail("WRITE_FAILED", "相机暂时无法接收蓝牙数据。");
    }

    private void closeGatt() {
        BluetoothGatt previous = gatt;
        gatt = null;
        gattReady = false;
        discoveryStarted = false;
        mtu = 23;
        writing = null;
        subscription = null;
        if (previous != null) {
            try { previous.disconnect(); } catch (RuntimeException ignored) {}
            try { previous.close(); } catch (RuntimeException ignored) {}
        }
    }

    @SuppressWarnings("deprecation")
    private void pairClassic(String name) {
        if (!gattReady || name == null || !names.containsValue(name)) {
            fail("PAIRING", "请先选择并连接相机。"); return;
        }
        closeGatt();
        BluetoothAdapter adapter = adapter();
        if (adapter == null) return;
        Map<String, BluetoothDevice> nearby = new LinkedHashMap<>();
        receiver = new BroadcastReceiver() {
            @Override public void onReceive(Context context, Intent intent) {
                safely(() -> {
                    if (receiver != this || !"pairClassic".equals(operation)) return;
                    BluetoothDevice device = intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE);
                    String action = intent.getAction();
                    if (BluetoothDevice.ACTION_FOUND.equals(action) && device != null && classicTarget == null) {
                        if (matchesName(name, device.getName())) nearby.put(device.getAddress(), device);
                    } else if (BluetoothAdapter.ACTION_DISCOVERY_FINISHED.equals(action) && classicTarget == null) {
                        startBond(name, nearby.values());
                    } else if (BluetoothDevice.ACTION_BOND_STATE_CHANGED.equals(action) &&
                        device != null && device.equals(classicTarget)) {
                        int state = classicTarget.getBondState();
                        if (state == BluetoothDevice.BOND_BONDED) completeBond();
                        else if (state == BluetoothDevice.BOND_NONE &&
                            intent.getIntExtra(BluetoothDevice.EXTRA_PREVIOUS_BOND_STATE, -1) == BluetoothDevice.BOND_BONDING) {
                            fail("PAIRING", "配对已取消，请在相机与手机上确认相同的配对码。");
                        }
                    }
                });
            }
        };
        IntentFilter filter = new IntentFilter(BluetoothDevice.ACTION_FOUND);
        filter.addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED);
        filter.addAction(BluetoothDevice.ACTION_BOND_STATE_CHANGED);
        if (Build.VERSION.SDK_INT >= 33) activity.registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED);
        else activity.registerReceiver(receiver, filter);
        for (BluetoothDevice device : adapter.getBondedDevices()) {
            if (matchesName(name, device.getName()) && device.getType() != BluetoothDevice.DEVICE_TYPE_LE) {
                nearby.put(device.getAddress(), device);
            }
        }
        if (!adapter.startDiscovery()) {
            fail("PAIRING", "无法开始相机配对，请检查相机的配对界面。");
            return;
        }
        later(22, () -> startBond(name, nearby.values()));
    }

    private static boolean matchesName(String selected, String candidate) {
        if (candidate == null) return false;
        String a = selected.trim().toLowerCase(Locale.ROOT);
        String b = candidate.trim().toLowerCase(Locale.ROOT);
        return a.equals(b) || (Math.min(a.length(), b.length()) >= 4 &&
            (a.startsWith(b) || b.startsWith(a)));
    }

    private void startBond(String name, Collection<BluetoothDevice> candidates) {
        if (classicTarget != null) return;
        List<BluetoothDevice> exact = new ArrayList<>();
        for (BluetoothDevice candidate : candidates) {
            if (name.equalsIgnoreCase(candidate.getName())) exact.add(candidate);
        }
        Collection<BluetoothDevice> matches = exact.isEmpty() ? candidates : exact;
        if (matches.size() != 1) {
            fail("PAIRING", matches.isEmpty() ? "未找到可配对的相机，请在机身重新开始配对。"
                : "发现多台同名相机，请只保留目标相机处于配对状态。");
            return;
        }
        classicTarget = matches.iterator().next();
        BluetoothAdapter adapter = bluetooth.getAdapter();
        if (adapter != null) adapter.cancelDiscovery();
        if (classicTarget.getBondState() == BluetoothDevice.BOND_BONDED) completeBond();
        else if (classicTarget.createBond()) later(55, () -> fail("PAIRING", "相机配对确认超时。"));
        else fail("PAIRING", "相机没有进入系统配对，请在机身重新开始配对。");
    }

    private void completeBond() {
        finishClassic();
        success(null);
    }

    private void finishClassic() {
        if (receiver == null) return;
        try { activity.unregisterReceiver(receiver); } catch (RuntimeException ignored) {}
        receiver = null;
        classicTarget = null;
        try {
            BluetoothAdapter adapter = bluetooth == null ? null : bluetooth.getAdapter();
            if (adapter != null) adapter.cancelDiscovery();
        } catch (RuntimeException ignored) {}
    }

    private void locate() {
        if (!gattReady) { fail("DISCONNECTED", "请先连接相机蓝牙。"); return; }
        if (locationManager == null) { fail("LOCATION_UNAVAILABLE", "此手机未提供定位服务。"); return; }
        List<String> providers = new ArrayList<>();
        for (String provider : new String[]{LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER}) {
            if (locationManager.isProviderEnabled(provider)) providers.add(provider);
        }
        if (providers.isEmpty()) { fail("LOCATION_UNAVAILABLE", "请打开手机定位服务。"); return; }
        Location best = null;
        for (String provider : providers) {
            Location cached = locationManager.getLastKnownLocation(provider);
            if (validFix(cached) && (best == null || cached.getAccuracy() < best.getAccuracy())) best = cached;
        }
        if (best != null) { reportPosition(best); return; }
        locator = new LocationListener() {
            @Override public void onLocationChanged(Location fix) {
                if (locator == this && validFix(fix)) reportPosition(fix);
            }
            @Override public void onProviderEnabled(String provider) {}
            @Override public void onProviderDisabled(String provider) {}
            @Override public void onStatusChanged(String provider, int status, Bundle extras) {}
        };
        for (String provider : providers) {
            locationManager.requestLocationUpdates(provider, 0, 0, locator, Looper.getMainLooper());
        }
        later(15, () -> fail("LOCATION_UNAVAILABLE", "暂未获取到精确定位，正在等待手机定位。"));
    }

    private static boolean validFix(Location fix) {
        if (fix == null || !fix.hasAccuracy() || !Float.isFinite(fix.getAccuracy()) ||
            fix.getAccuracy() < 0 || fix.getAccuracy() > 100) return false;
        long age = SystemClock.elapsedRealtimeNanos() - fix.getElapsedRealtimeNanos();
        return age >= 0 && age <= 30_000_000_000L;
    }

    private void reportPosition(Location fix) {
        finishPosition();
        Map<String, Object> result = new HashMap<>();
        result.put("latitude", fix.getLatitude());
        result.put("longitude", fix.getLongitude());
        result.put("altitude", fix.hasAltitude() ? fix.getAltitude() : null);
        result.put("accuracy", (double)fix.getAccuracy());
        result.put("time", fix.getTime());
        success(result);
    }

    private void finishPosition() {
        if (locator == null) return;
        try { locationManager.removeUpdates(locator); } catch (RuntimeException ignored) {}
        locator = null;
    }

    private void stop() {
        generation++;
        permissionAction = null;
        fail("CANCELLED", "已结束蓝牙定位操作。");
        discovered.clear();
        names.clear();
    }

    void dispose() {
        disposed = true;
        stop();
        events = null;
        methods.setMethodCallHandler(null);
        stream.setStreamHandler(null);
    }
}
