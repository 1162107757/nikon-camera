package android.net;
import java.io.IOException;
import java.net.URL;
import java.net.URLConnection;
import javax.net.SocketFactory;
public final class Network {
    public interface Connections { URLConnection open(URL url) throws IOException; }
    public final String name;
    public NetworkCapabilities capabilities;
    public Connections connections;
    public int httpOpens, socketFactories;
    public Network(String name, NetworkCapabilities caps) { this.name=name; capabilities=caps; }
    public URLConnection openConnection(URL url) throws IOException { httpOpens++; return connections.open(url); }
    public SocketFactory getSocketFactory() { socketFactories++; return SocketFactory.getDefault(); }
}
