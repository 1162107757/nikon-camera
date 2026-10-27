package android.net;
public final class ConnectivityManager {
    public boolean online = true;
    public Object getActiveNetwork() { return online ? this : null; }
    public NetworkCapabilities getNetworkCapabilities(Object active) { return active == null ? null : new NetworkCapabilities(); }
    public boolean isActiveNetworkMetered() { return false; }
}
