package cc.huevia.shared;

import java.io.IOException;

/** A real platform decoder validates samples before the existing cache commits them. */
public final class MediaValidation {
    public interface Decoder { void validate(byte[] bytes) throws IOException; }
    private static volatile Decoder decoder;
    private MediaValidation() {}
    public static void install(Decoder value) { if(value==null)throw new IllegalArgumentException("Missing image decoder");decoder=value; }
    public static void validate(byte[] bytes)throws IOException {
        if(bytes==null||bytes.length<4||bytes.length>8*1024*1024)throw new IOException("样片文件大小无效。");
        Decoder current=decoder;
        if(current==null)throw new IOException("样片解码器尚未准备好。");
        current.validate(bytes);
    }
}
