package cc.huevia.library;

import java.io.IOException;
import java.util.Map;

/** Public boundary to the existing strict codec; no second JSON parser. */
public final class SharedJson {
    private SharedJson() {}
    public static Map<String,Object> object(String text)throws IOException {
        if(text==null||text.length()>4*1024*1024)throw new IOException("配置为空或超过限制。");
        return LibraryJson.object(LibraryJson.parse(text));
    }
    public static String encode(Object value){return LibraryJson.stringify(value);}
}
