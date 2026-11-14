package android.content;
import android.net.ConnectivityManager;
public final class Context {
    private final ConnectivityManager connectivity;
    public Context(ConnectivityManager connectivity) { this.connectivity = connectivity; }
    public Context getApplicationContext() { return this; }
    public <T> T getSystemService(Class<T> type) { return type.cast(connectivity); }
}
