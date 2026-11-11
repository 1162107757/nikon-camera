# JNI resolves these exact names in huevia_raw.cpp. Native method descriptors
# retain the classes, but do not retain Java callbacks looked up by GetMethodID.
-keepclassmembers class cc.huevia.album.RawDeveloper$NativeCallbacks {
    public boolean cancelled();
    public void onProgress(double);
}

# nativeInspect constructs this return value through its exact JNI signature.
-keepclassmembers class cc.huevia.album.RawDeveloper$Info {
    <init>(int, int, int, int, int, int, java.lang.String, java.lang.String, java.lang.String, java.lang.String);
}
