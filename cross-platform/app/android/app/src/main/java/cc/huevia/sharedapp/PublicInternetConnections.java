package cc.huevia.sharedapp;

import android.content.Context;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.net.NetworkRequest;
import cc.huevia.account.AccountException;
import cc.huevia.account.AccountHttpTransport;
import java.io.IOException;
import java.io.InterruptedIOException;
import java.net.URL;
import java.net.URLConnection;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicReference;
import javax.net.ssl.HttpsURLConnection;

/** Public HTTPS gets its own network/lease; camera Wi-Fi and process routing are never changed. */
final class PublicInternetConnections implements AccountHttpTransport.ConnectionOpener {
    private static final int CELLULAR_WAIT_MILLIS = 5000;
    private final ConnectivityManager connectivity;

    PublicInternetConnections(Context context) {
        connectivity = context.getApplicationContext().getSystemService(ConnectivityManager.class);
    }

    @Override public AccountHttpTransport.OpenedConnection open(URL url) throws IOException {
        if (!"https".equalsIgnoreCase(url.getProtocol())) throw new IOException("公共服务地址需要 HTTPS。");
        Selection selected = existing();
        if (selected == null) {
            if (hasVpnRoute()) throw vpnUnavailable();
            selected = requestCellular();
        }
        selected = respectVpn(selected);
        final Selection lease = selected;
        try {
            URLConnection connection = lease.network.openConnection(url);
            if (!(connection instanceof HttpsURLConnection)) throw new IOException("公共服务连接类型无效。");
            return new AccountHttpTransport.OpenedConnection((HttpsURLConnection) connection, lease.release);
        } catch (IOException | RuntimeException failure) {
            lease.release.run();
            throw failure;
        }
    }

    boolean hasValidatedInternet() { return existing() != null; }

    boolean metered() {
        Selection selected = existing();
        if (selected == null) return true; // A manual attempt may need cellular data.
        NetworkCapabilities caps = capabilities(selected.network);
        return caps == null || !caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED);
    }

    private Selection existing() {
        if (connectivity == null) return null;
        try {
            Network active = connectivity.getActiveNetwork();
            NetworkCapabilities activeCaps = capabilities(active);
            if (validated(activeCaps)) return new Selection(active, () -> {});
            boolean vpn = isVpn(activeCaps);
            Network cellular = null, fallback = null;
            for (Network network : connectivity.getAllNetworks()) {
                NetworkCapabilities caps = capabilities(network);
                if (isVpn(caps)) {
                    vpn = true;
                    if (validated(caps)) return new Selection(network, () -> {});
                    continue;
                }
                if (!validated(caps)) continue;
                if (caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)) cellular = network;
                if (fallback == null) fallback = network;
            }
            if (vpn) return null; // Never work around an existing VPN with a physical network.
            if (cellular != null) return new Selection(cellular, () -> {});
            return fallback == null ? null : new Selection(fallback, () -> {});
        } catch (RuntimeException unavailable) { return null; }
    }

    private NetworkCapabilities capabilities(Network network) {
        if (connectivity == null || network == null) return null;
        try { return connectivity.getNetworkCapabilities(network); }
        catch (RuntimeException unavailable) { return null; }
    }

    private static boolean validated(NetworkCapabilities caps) {
        return caps != null && caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                && caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED);
    }

    private static boolean isVpn(NetworkCapabilities caps) {
        return caps != null && caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN);
    }

    private boolean hasVpnRoute() {
        if (connectivity == null) return false;
        try {
            if (isVpn(capabilities(connectivity.getActiveNetwork()))) return true;
            for (Network network : connectivity.getAllNetworks()) if (isVpn(capabilities(network))) return true;
        } catch (RuntimeException unavailable) { /* The normal no-network path remains fail closed. */ }
        return false;
    }

    private Selection respectVpn(Selection selected) throws IOException {
        if (isVpn(capabilities(selected.network)) || !hasVpnRoute()) return selected;
        try {
            Network active = connectivity.getActiveNetwork();
            // A validated per-app default also respects explicit VPN app exclusions.
            if (selected.network.equals(active) && validated(capabilities(active))) return selected;
        } catch (RuntimeException ignored) {}
        Selection routed = existing();
        selected.release.run();
        if (routed != null && isVpn(capabilities(routed.network))) return routed;
        throw vpnUnavailable();
    }

    private AccountException vpnUnavailable() {
        java.util.logging.Logger.getLogger("HueviaPublicNetwork").warning("stage=vpn_unavailable");
        return new AccountException("PUBLIC_VPN_UNAVAILABLE", 0,
                "当前 VPN 无法访问公网。请检查 VPN 或网络设置后重试，无需断开相机连接。");
    }

    private Selection requestCellular() throws IOException {
        if (connectivity == null) throw unavailable();
        CountDownLatch ready = new CountDownLatch(1);
        AtomicReference<Network> available = new AtomicReference<>();
        ConnectivityManager.NetworkCallback callback = new ConnectivityManager.NetworkCallback() {
            private void accept(Network network, NetworkCapabilities caps) {
                if (validated(caps) && caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)) {
                    available.set(network); ready.countDown();
                }
            }
            @Override public void onAvailable(Network network) { accept(network, capabilities(network)); }
            @Override public void onCapabilitiesChanged(Network network, NetworkCapabilities caps) { accept(network, caps); }
            @Override public void onUnavailable() { ready.countDown(); }
        };
        AtomicBoolean released = new AtomicBoolean();
        Runnable release = () -> {
            if (!released.compareAndSet(false, true)) return;
            try { connectivity.unregisterNetworkCallback(callback); }
            catch (RuntimeException alreadyReleased) { /* Only this request's callback is released. */ }
        };
        boolean retained = false;
        try {
            connectivity.requestNetwork(new NetworkRequest.Builder()
                    .addTransportType(NetworkCapabilities.TRANSPORT_CELLULAR)
                    .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET).build(), callback, CELLULAR_WAIT_MILLIS);
            if (!ready.await(CELLULAR_WAIT_MILLIS, TimeUnit.MILLISECONDS)) throw unavailable();
            Network network = available.get();
            if (network == null || !validated(capabilities(network))) throw unavailable();
            retained = true;
            return new Selection(network, release);
        } catch (InterruptedException interrupted) {
            Thread.currentThread().interrupt();
            throw new InterruptedIOException("连接公共服务已取消，请重试。");
        } catch (RuntimeException denied) { throw unavailable(); }
        finally { if (!retained) release.run(); }
    }

    private AccountException unavailable() {
        NetworkCapabilities active = null;
        try { if (connectivity != null) active = capabilities(connectivity.getActiveNetwork()); }
        catch (RuntimeException ignored) {}
        boolean wifi = active != null && active.hasTransport(NetworkCapabilities.TRANSPORT_WIFI);
        java.util.logging.Logger.getLogger("HueviaPublicNetwork").warning("stage=network_unavailable activeWifi=" + wifi);
        return new AccountException("PUBLIC_NETWORK_UNAVAILABLE", 0, wifi
                ? "当前 Wi-Fi 无法上网，且移动数据不可用。请开启移动数据后重试，无需断开相机连接。"
                : "当前没有可上网的网络。请开启移动数据或连接可上网的网络后重试。");
    }

    private static final class Selection {
        final Network network;
        final Runnable release;
        Selection(Network network, Runnable release) { this.network = network; this.release = release; }
    }
}
