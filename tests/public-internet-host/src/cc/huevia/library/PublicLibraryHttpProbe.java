package cc.huevia.library;
public final class PublicLibraryHttpProbe {
    public static byte[] read(String address)throws Exception { return new SecureHttpClient().get(address,1024,-1,"application/json",null); }
}
