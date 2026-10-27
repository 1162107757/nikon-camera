package android.content;
import android.content.pm.PackageManager;
import java.io.File;
public abstract class Context {
    public static final int MODE_PRIVATE = 0;
    public Context getApplicationContext() { return this; }
    public abstract SharedPreferences getSharedPreferences(String name, int mode);
    public abstract <T> T getSystemService(Class<T> type);
    public abstract String getPackageName();
    public abstract PackageManager getPackageManager();
    public abstract File getFilesDir();
    public abstract File getExternalFilesDir(String type);
}
