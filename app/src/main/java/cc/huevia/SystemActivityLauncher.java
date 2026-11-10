package cc.huevia;

import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.Intent;
import java.util.function.Consumer;

/** Vendor document/settings apps can be absent or blocked. A failed handoff stays in Huevia. */
public final class SystemActivityLauncher {
    private SystemActivityLauncher() {}
    public static boolean document(Activity activity, Intent intent, int requestCode, Consumer<String> failed) {
        try { activity.startActivityForResult(intent, requestCode); return true; }
        catch (ActivityNotFoundException missing) {
            if (Intent.ACTION_OPEN_DOCUMENT.equals(intent.getAction())) {
                Intent fallback = new Intent(intent).setAction(Intent.ACTION_GET_CONTENT);
                fallback.removeFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION);
                try { activity.startActivityForResult(fallback, requestCode); return true; }
                catch (ActivityNotFoundException | SecurityException unavailable) { }
            }
            failed.accept("系统未提供可用的文件选择器，请启用系统文件应用后重试。"); return false;
        } catch (SecurityException denied) {
            failed.accept("系统拒绝打开文件选择器，请检查系统文件应用及访问权限后重试。"); return false;
        }
    }
    public static boolean settings(Activity activity, Intent preferred, Intent fallback, Consumer<String> failed) {
        try { activity.startActivity(preferred); return true; }
        catch (ActivityNotFoundException | SecurityException unavailable) {
            try { activity.startActivity(fallback); return true; }
            catch (ActivityNotFoundException | SecurityException missing) {
                failed.accept("无法打开系统设置，请在手机设置中手动找到 Huevia 后调整权限。"); return false;
            }
        }
    }
}
