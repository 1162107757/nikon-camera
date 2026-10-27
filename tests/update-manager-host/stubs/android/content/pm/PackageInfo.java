package android.content.pm;
public final class PackageInfo {
    public String packageName;
    public String versionName;
    public int versionCode;
    public ApplicationInfo applicationInfo;
    public SigningInfo signingInfo;
    public Signature[] signatures;
    public long getLongVersionCode() { return versionCode; }
}
