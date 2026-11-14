package android.net;
import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;
public final class ConnectivityManager {
    public static class NetworkCallback {
        public void onAvailable(Network network) {}
        public void onCapabilitiesChanged(Network network, NetworkCapabilities caps) {}
        public void onUnavailable() {}
    }
    public Network active, requested;
    public Network[] networks=new Network[0];
    public final NetworkCallback cameraLease=new NetworkCallback();
    public final List<NetworkCallback> callbacks=new CopyOnWriteArrayList<>();
    public int requests, unregisters, processChanges;
    public long delayMillis;
    public ConnectivityManager() { callbacks.add(cameraLease); }
    public Network getActiveNetwork() { return active; }
    public Network[] getAllNetworks() { return networks; }
    public NetworkCapabilities getNetworkCapabilities(Network network) { return network==null?null:network.capabilities; }
    public void requestNetwork(NetworkRequest request, NetworkCallback callback, int timeout) {
        if(request.transport!=NetworkCapabilities.TRANSPORT_CELLULAR || request.capability!=NetworkCapabilities.NET_CAPABILITY_INTERNET
                ||timeout<1||timeout>5000) throw new AssertionError("Only a bounded cellular request is allowed");
        requests++; callbacks.add(callback);
        Thread reply=new Thread(()->{
            try { Thread.sleep(delayMillis); } catch(InterruptedException ignored) { Thread.currentThread().interrupt(); }
            if(requested==null) callback.onUnavailable();
            else { callback.onAvailable(requested); callback.onCapabilitiesChanged(requested,requested.capabilities); }
        },"fake-cellular-callback");
        reply.setDaemon(true); reply.start();
    }
    public void unregisterNetworkCallback(NetworkCallback callback) {
        if(callback==cameraLease) throw new AssertionError("Camera lease must never be released by public HTTP");
        if(!callbacks.remove(callback)) throw new IllegalArgumentException("Callback already released");
        unregisters++;
    }
    public boolean bindProcessToNetwork(Network network) { processChanges++; throw new AssertionError("Process routing must not change"); }
}
