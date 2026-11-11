package cc.huevia.wifialbumqa;

import android.app.*;
import android.content.*;
import android.graphics.Bitmap;
import android.os.*;
import android.view.*;
import android.widget.TextView;
import java.io.*;
import java.lang.reflect.*;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.atomic.AtomicReference;
import org.json.*;

/** Runs the installed native shell/runtime/controller against two synthetic PTP/IP sockets.
 * Production classes are loaded from the target APK, never bundled into this probe. */
public final class WifiAlbumProbe extends Instrumentation {
    private Bundle args;
    private Activity activity;
    private Object client, lease, controller;
    private final JSONArray checks = new JSONArray();
    private final Peer peer = new Peer();
    @Override public void onCreate(Bundle args) { super.onCreate(args); this.args = args; start(); }
    @Override public void onStart() {
        Bundle result = new Bundle(); JSONObject report = new JSONObject(); boolean passed = false;
        try {
            check(Build.HARDWARE.equals("ranchu") || Build.HARDWARE.equals("goldfish"), "owned-emulator-only");
            check(sha(new File(getTargetContext().getApplicationInfo().sourceDir)).equals(args.getString("apkSha256")), "installed-candidate-hash");
            activity = startActivitySync(new Intent().setClassName("cc.huevia", "cc.huevia.MainActivity").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            long until = System.nanoTime() + 30_000_000_000L;
            while (!onMain(() -> (Boolean) get(activity, "ready")) && System.nanoTime() < until) Thread.sleep(50);
            check(onMain(() -> (Boolean) get(activity, "ready")), "production-shell-ready");
            Class<?> connector = type("cc.huevia.album.PtpIpClient$SocketConnector");
            Object sockets = Proxy.newProxyInstance(connector.getClassLoader(), new Class<?>[] {connector}, (p, m, a) -> {
                if (m.getName().equals("connect")) return peer.open();
                if (m.getName().equals("toString")) return "Owned synthetic sockets";
                throw new UnsupportedOperationException(m.getName());
            });
            client = type("cc.huevia.album.PtpIpClient").getConstructor(connector).newInstance(sockets);
            call(client, "connect", new Class<?>[] {String.class, int.class, byte[].class, String.class},
                    "camera.test", 15740, new byte[16], "Regression QA");
            check(peer.count(0x1002) == 1 && peer.channels == 2, "single-initial-session-two-channels");
            onMain(() -> {
                Object runtime = get(activity, "connections");
                controller = get(runtime, "album");
                check(!(Boolean) call(controller, "hasLiveSession"), "no-existing-camera-session");
                lease = call(runtime, "beginOperation");
                set(controller, "active", client);
                Constructor<?> info = type("cc.huevia.album.ConnectionInfo").getDeclaredConstructor(String.class, String.class, int.class, int.class);
                info.setAccessible(true);
                set(controller, "sessionConnectionInfo", info.newInstance("Z 30", "camera.test", 15740, 0));
                set(activity, "albumTab", true); set(activity, "settingsTab", false); set(activity, "localAlbumTab", false);
                Object panel = get(activity, "album");
                call(panel, "followSharedConnection");
                call(activity, "syncConnectionState");
                check((Boolean) call(controller, "hasLiveSession") && !(Boolean) call(controller, "isConnected"), "connected-with-inventory-deferred-by-lease");
                check(text(activity.getWindow().getDecorView()).contains("读取照片列表后即可浏览"), "matches-reported-default-unavailable-message");
                check(peer.count(0x1004) == 0, "no-inventory-transaction-during-connect-lease");
                return null;
            });
            onMain(() -> { call(lease, "close"); lease = null; return null; });
            boolean baseline = args.getString("expectBlocked", "false").equals("true");
            until = System.nanoTime() + (baseline ? 2_000_000_000L : 10_000_000_000L);
            while (!(Boolean) call(controller, "isConnected") && System.nanoTime() < until) Thread.sleep(30);
            boolean connected = (Boolean) call(controller, "isConnected");
            check(baseline ? !connected && peer.count(0x1004) == 0 : connected && peer.count(0x1004) == 1 && peer.count(0x1007) == 1,
                    baseline ? "baseline-reproduces-missing-inventory-after-lease-release" : "lease-release-automatically-reads-storage-and-photo-handles");
            check(peer.channels == 2 && peer.count(0x1002) == 1, "no-reconnect-or-repeated-open-session");
            check(peer.onlyReads(), "no-camera-content-or-setting-writes");
            if (!baseline) {
                Object info = call(controller, "connectionInfo");
                check((Integer) call(info, "totalHandles") == 1, "one-camera-photo-in-production-inventory");
                check(onMain(() -> !text(activity.getWindow().getDecorView()).contains("照片暂不可用")), "unavailable-state-clears-without-tapping-retry");
            }
            report.put("operations", peer.operations.toString()).put("channels", peer.channels);
            passed = true;
        } catch (Throwable failure) {
            try { StringWriter stack = new StringWriter(); failure.printStackTrace(new PrintWriter(stack)); report.put("error", stack.toString()); } catch (Exception ignored) { }
        } finally {
            try {
                if (lease != null) onMain(() -> { call(lease, "close"); return null; });
                if (client != null) call(client, "close");
                if (activity != null) onMain(() -> { activity.finish(); return null; });
                report.put("status", passed ? "PASS" : "FAIL").put("assertions", checks).put("apkSha256", args.getString("apkSha256"))
                        .put("scope", "Installed native MainActivity/runtime/controller with synthetic PTP/IP peer; no physical camera or Wi-Fi radio validation");
                result.putString("report", report.toString());
            } catch (Throwable cleanup) { passed = false; result.putString("cleanupError", cleanup.toString()); }
            finish(passed ? Activity.RESULT_OK : Activity.RESULT_CANCELED, result);
        }
    }
    private Class<?> type(String name) throws Exception { return getTargetContext().getClassLoader().loadClass(name); }
    private static Object get(Object target, String name) throws Exception { Field f = target.getClass().getDeclaredField(name); f.setAccessible(true); return f.get(target); }
    private static void set(Object target, String name, Object value) throws Exception { Field f = target.getClass().getDeclaredField(name); f.setAccessible(true); f.set(target, value); }
    private static Object call(Object target, String name, Class<?>[] types, Object... args) throws Exception {
        Method m = target.getClass().getDeclaredMethod(name, types); m.setAccessible(true); return m.invoke(target, args);
    }
    private static Object call(Object target, String name) throws Exception { return call(target, name, new Class<?>[0]); }
    private static String text(View root) {
        StringBuilder out = new StringBuilder(); if (root instanceof TextView) out.append(((TextView) root).getText()).append('\n');
        if (root instanceof ViewGroup) { ViewGroup group = (ViewGroup) root; for (int i = 0; i < group.getChildCount(); i++) out.append(text(group.getChildAt(i))); }
        return out.toString();
    }
    private void check(boolean ok, String name) { if (!ok) throw new AssertionError(name); checks.put(name); }
    private interface Work<T> { T get() throws Exception; }
    private <T> T onMain(Work<T> work) throws Exception {
        AtomicReference<T> value = new AtomicReference<>(); AtomicReference<Throwable> error = new AtomicReference<>();
        runOnMainSync(() -> { try { value.set(work.get()); } catch (Throwable e) { error.set(e); } });
        if (error.get() != null) throw new Exception(error.get()); return value.get();
    }
    private static String sha(File file) throws Exception {
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        try (InputStream in = new FileInputStream(file)) { byte[] b = new byte[65536]; int n; while ((n = in.read(b)) >= 0) digest.update(b, 0, n); }
        StringBuilder out = new StringBuilder(); for (byte b : digest.digest()) out.append(String.format("%02x", b & 255)); return out.toString();
    }
    private final class Peer {
        int channels;
        final List<Integer> operations = Collections.synchronizedList(new ArrayList<>());
        synchronized Socket open() throws IOException { if (channels >= 2) throw new IOException("Unexpected reconnect"); return new FakeSocket(channels++ != 0); }
        int count(int op) { synchronized (operations) { return Collections.frequency(operations, op); } }
        boolean onlyReads() { synchronized (operations) { for (int op : operations) if (!Arrays.asList(0x1001,0x1002,0x1004,0x1007,0x1008,0x100a).contains(op)) return false; return true; } }
        byte[] info() { return concat(le(100,2), le(10,4), le(100,2), str(""), le(0,2), le(6,4), le(0x1001,2),le(0x1002,2),le(0x1004,2),le(0x1007,2),le(0x1008,2),le(0x1009,2),le(0,4),le(0,4),le(0,4),le(0,4),str("NIKON CORPORATION"),str("Z 30"),str("test"),str("synthetic")); }
        void receive(FakeSocket socket, byte[] packet) throws IOException {
            int type = (int) u32(packet,4);
            if (type == 1) { socket.input.add(frame(2, concat(le(7,4),new byte[16],"Z 30\0".getBytes(StandardCharsets.UTF_16LE),le(0x10000,4)))); return; }
            if (type == 3) { socket.input.add(frame(4,new byte[0])); return; }
            if (type != 6 || socket.event) throw new IOException("Unexpected packet type " + type);
            int op = (packet[12]&255)|((packet[13]&255)<<8); long tx=u32(packet,14); operations.add(op);
            if (op == 0x1002) { socket.input.add(frame(7,concat(le(0x2001,2),le(tx,4)))); return; }
            byte[] data;
            if (op==0x1001) data=info();
            else if (op==0x1004 || op==0x1007) data=concat(le(1,4),le(1,4));
            else if(op==0x1008) data=concat(le(1,4),le(0x3801,2),le(0,2),le(1024,4),le(0,2),new byte[12],le(600,4),le(400,4),new byte[18],str("QA_PHOTO.JPG"),str("20261111T120000"),str(""),str(""));
            else if(op==0x100a) { Bitmap b=Bitmap.createBitmap(20,20,Bitmap.Config.ARGB_8888); b.eraseColor(0xff9ba79b); ByteArrayOutputStream bytes=new ByteArrayOutputStream(); b.compress(Bitmap.CompressFormat.JPEG,80,bytes); b.recycle(); data=bytes.toByteArray(); }
            else throw new IOException("Unexpected operation " + op);
            socket.input.add(concat(frame(9,concat(le(tx,4),le(data.length,8))),frame(12,concat(le(tx,4),data)),frame(7,concat(le(0x2001,2),le(tx,4)))));
        }
        final class FakeSocket extends Socket {
            final boolean event; final QueuedInput input=new QueuedInput(); final ByteArrayOutputStream pending=new ByteArrayOutputStream();
            FakeSocket(boolean event) { this.event=event; }
            @Override public InputStream getInputStream() { return input; }
            @Override public OutputStream getOutputStream() { return new OutputStream() {
                @Override public void write(int v)throws IOException { write(new byte[]{(byte)v}); }
                @Override public void write(byte[] b,int o,int n)throws IOException {
                    pending.write(b,o,n); while(pending.size()>=8) { byte[] bytes=pending.toByteArray(); int size=(int)u32(bytes,0); if(size<8||size>65536)throw new IOException("Invalid request"); if(bytes.length<size)return; pending.reset();pending.write(bytes,size,bytes.length-size);receive(FakeSocket.this,Arrays.copyOf(bytes,size)); }
                }
            }; }
            @Override public void setSoTimeout(int timeout) { }
            @Override public void setTcpNoDelay(boolean enabled) { }
            @Override public boolean isConnected() { return true; }
            @Override public void close() { input.close(); }
        }
    }
    private static final class QueuedInput extends InputStream {
        private final ArrayDeque<Byte> bytes=new ArrayDeque<>(); private boolean closed;
        synchronized void add(byte[] b) { for(byte v:b)bytes.add(v); notifyAll(); }
        @Override public synchronized int read() throws IOException { while(bytes.isEmpty()&&!closed)try{wait();}catch(InterruptedException e){Thread.currentThread().interrupt();throw new IOException(e);} return bytes.isEmpty()?-1:bytes.remove()&255; }
        @Override public synchronized int read(byte[] b,int o,int n)throws IOException { int first=read();if(first<0)return -1;b[o]=(byte)first;int count=1;while(count<n&&!bytes.isEmpty())b[o+count++]=bytes.remove();return count; }
        @Override public synchronized void close() { closed=true;notifyAll(); }
    }
    private static byte[] le(long value,int n) { byte[] b=new byte[n];for(int i=0;i<n;i++)b[i]=(byte)(value>>>(i*8));return b; }
    private static long u32(byte[] b,int o) { long v=0;for(int i=0;i<4;i++)v|=(b[o+i]&255L)<<(i*8);return v; }
    private static byte[] concat(byte[]...parts) { ByteArrayOutputStream out=new ByteArrayOutputStream();for(byte[] b:parts)out.write(b,0,b.length);return out.toByteArray(); }
    private static byte[] frame(int type,byte[] b) { return concat(le(b.length+8,4),le(type,4),b); }
    private static byte[] str(String s) { return concat(new byte[]{(byte)(s.length()+1)},(s+'\0').getBytes(StandardCharsets.UTF_16LE)); }
}
