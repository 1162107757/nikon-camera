package cc.huevia.shared;

import cc.huevia.library.SharedJson;
import cc.huevia.ncp.RawDevelopmentSettings;
import java.io.IOException;
import java.util.Map;

/** The exact original RAW controls, validated before either native LibRaw adapter. */
public final class SharedRawSettings {
    private SharedRawSettings(){}
    public static RawDevelopmentSettings parse(String json)throws IOException{
        Map<String,Object> p=SharedJson.object(json);
        try{
            String white=SharedRuntime.text(p,"whiteBalance",16),color=SharedRuntime.text(p,"colorMode",16);
            return new RawDevelopmentSettings(
                white.isEmpty()?RawDevelopmentSettings.WhiteBalance.CAMERA:RawDevelopmentSettings.WhiteBalance.valueOf(white),
                SharedRuntime.integer(p,"temperature",5500),SharedRuntime.integer(p,"tint",0),SharedRuntime.integer(p,"exposure",0),
                SharedRuntime.integer(p,"highlights",2),SharedRuntime.integer(p,"quality",3),
                color.isEmpty()?RawDevelopmentSettings.ColorMode.CAMERA_JPEG:RawDevelopmentSettings.ColorMode.valueOf(color));
        }catch(IllegalArgumentException invalid){throw new IOException("RAW 显影设置无效。",invalid);}
    }
    public static String json(RawDevelopmentSettings s){return SharedJson.encode(SharedRuntime.map("whiteBalance",s.whiteBalance.name(),"colorMode",s.colorMode.name(),"temperature",s.temperatureKelvin,"tint",s.tint,"exposure",s.exposureTenths,"highlights",s.highlightMode,"quality",s.demosaicQuality));}
    public static String identity(String json)throws IOException{return parse(json).identity();}
}
