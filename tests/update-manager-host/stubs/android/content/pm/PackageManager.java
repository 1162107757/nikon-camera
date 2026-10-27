package android.content.pm;
public abstract class PackageManager {
    public static final int GET_SIGNING_CERTIFICATES = 0x08000000, GET_SIGNATURES = 64;
    public abstract PackageInfo getPackageInfo(String name, int flags);
    public abstract PackageInfo getPackageArchiveInfo(String path, int flags);
}
