package cc.huevia.connection;

import android.content.Context;
import cc.huevia.album.CameraWifiNetwork;
import cc.huevia.album.ConnectionTrace;
import cc.huevia.shared.SharedCamera;
import java.io.IOException;
import java.io.InterruptedIOException;
import java.net.ConnectException;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;
import java.util.function.BooleanSupplier;

/** Reuses the legacy app's explicit, system-authorized camera network. */
public final class SharedFujifilmWifi implements SharedCamera.FujifilmWifiJoin {
    private final Context app;
    private final CameraWifiNetwork wifi;

    public SharedFujifilmWifi(Context context, CameraWifiNetwork wifi) {
        app = context.getApplicationContext();
        this.wifi = wifi;
    }

    @Override public SharedCamera.WifiEndpoint select(String ssid, String password, int port,
                                                     BooleanSupplier cancel) throws IOException {
        CameraWifiSession lease = new CameraWifiSession(app, null);
        CountDownLatch ready = new CountDownLatch(1);
        AtomicReference<String> failure = new AtomicReference<>();
        boolean accepted = false;
        try {
            lease.connect(ssid, password, new CameraWifiSession.Listener() {
                @Override public void onConnected() { ready.countDown(); }
                @Override public void onFailure(String message) { failure.set(message); ready.countDown(); }
            });
            long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(35);
            while (!ready.await(100, TimeUnit.MILLISECONDS)) {
                check(cancel);
                if (System.nanoTime() >= deadline) {
                    throw new IOException("连接相机 Wi-Fi 超时。请保持 X-T20 的「无线通信」开启，并确认系统连接提示。");
                }
            }
            check(cancel);
            if (failure.get() != null) throw new IOException(failure.get());

            // Android can report onAvailable before publishing DHCP routes.
            deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(4);
            while (wifi.selectedCameraGateway().isEmpty() && System.nanoTime() < deadline) {
                check(cancel);
                Thread.sleep(100);
            }
            check(cancel);
            CameraWifiNetwork.FujifilmEndpoint endpoint = wifi.automaticFujifilmEndpoint(port);
            // The only retry is the first TCP connect. A failed handshake or an
            // auxiliary channel must stay with the existing protocol recovery.
            SharedCamera.WifiEndpoint result = new SharedCamera.WifiEndpoint(endpoint.host,
                    (host, requestedPort, timeout) -> {
                        if (requestedPort != port) return endpoint.connector.connect(host, requestedPort, timeout);
                        long retryUntil = System.nanoTime() + TimeUnit.SECONDS.toNanos(3);
                        for (;;) {
                            check(cancel);
                            try { return endpoint.connector.connect(host, requestedPort, timeout); }
                            catch (ConnectException refused) {
                                if (System.nanoTime() >= retryUntil) throw refused;
                                try { Thread.sleep(250); }
                                catch (InterruptedException stopped) {
                                    Thread.currentThread().interrupt();
                                    throw new InterruptedIOException("等待相机传图端口已取消。");
                                }
                                ConnectionTrace.mark("FUJI_COMMAND_RETRY");
                            }
                        }
                    }, lease::disconnect);
            accepted = true;
            return result;
        } catch (InterruptedException stopped) {
            Thread.currentThread().interrupt();
            throw new InterruptedIOException("连接相机 Wi-Fi 已取消。");
        } catch (IllegalArgumentException invalid) {
            throw new IOException(invalid.getMessage(), invalid);
        } finally {
            if (!accepted) lease.disconnect();
        }
    }

    private static void check(BooleanSupplier cancel) throws InterruptedIOException {
        if (cancel.getAsBoolean()) throw new InterruptedIOException("连接相机 Wi-Fi 已取消。");
    }
}
