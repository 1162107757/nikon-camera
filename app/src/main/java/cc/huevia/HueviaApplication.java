package cc.huevia;

/** Installs local crash evidence for activities, background workers and services. */
public final class HueviaApplication extends android.app.Application {
    @Override public void onCreate() {
        super.onCreate();
        AppCrashDiagnostics.install(this);
    }
}
