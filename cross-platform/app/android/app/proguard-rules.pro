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

-keep class cc.huevia.sharedapp.NativeRawThumbnail { *; }
-keep class cc.huevia.sharedapp.NativeRawThumbnail$Callbacks { *; }

# The original project stages classes.jar from the pinned LiteRT 1.4.1 AARs.
# Preserve the AAR's consumer rules too: plain JARs do not carry proguard.txt.
-keep class org.tensorflow.lite.annotations.UsedByReflection
-keep @org.tensorflow.lite.annotations.UsedByReflection class *
-keepclassmembers class * {
    @org.tensorflow.lite.annotations.UsedByReflection *;
}
