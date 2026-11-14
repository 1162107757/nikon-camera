package android.net;
import java.util.HashSet;
import java.util.Set;
public final class NetworkCapabilities {
    public static final int NET_CAPABILITY_INTERNET=12, NET_CAPABILITY_VALIDATED=16, NET_CAPABILITY_NOT_METERED=11;
    public static final int TRANSPORT_CELLULAR=0, TRANSPORT_WIFI=1, TRANSPORT_VPN=4;
    private final Set<Integer> capabilities=new HashSet<>(), transports=new HashSet<>();
    public NetworkCapabilities capability(int value) { capabilities.add(value); return this; }
    public NetworkCapabilities transport(int value) { transports.add(value); return this; }
    public boolean hasCapability(int value) { return capabilities.contains(value); }
    public boolean hasTransport(int value) { return transports.contains(value); }
}
