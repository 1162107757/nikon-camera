package cc.huevia.shared;

import cc.huevia.ncp.*;
import cc.huevia.library.*;
import java.io.IOException;
import java.util.*;
import java.util.function.*;

/** Platform-neutral entry points. Original Android algorithms remain the source of truth. */
public final class CoreEngine {
    public static final String VERSION="huevia-shared-core-v1";
    private CoreEngine() {}
    public static String schema(){
        Map<String,Object> value=new LinkedHashMap<>();value.put("version",VERSION);
        value.put("presetModel",PresetPreviewProfiles.MODEL_VERSION);value.put("rawColorModel",RawJpegColorMatch.MODEL);
        List<Object> parameters=new ArrayList<>();
        for(PhotoAdjustments.Parameter p:PhotoAdjustments.Parameter.values()){
            Map<String,Object> row=new LinkedHashMap<>();row.put("name",p.name());row.put("index",p.ordinal());row.put("label",p.label);row.put("min",p.min);row.put("max",p.max);row.put("help",p.help());parameters.add(row);
        }
        value.put("parameters",parameters);return SharedJson.encode(value);
    }
    public static String inspectPreset(byte[] bytes)throws IOException{
        PresetFile file=PresetFile.validate(bytes);Map<String,Object> result=new LinkedHashMap<>();
        result.put("format",file.fileFormat);result.put("version",file.version);result.put("registrationName",file.registrationName);
        try{PresetPreviewProfile profile=PresetPreviewProfiles.fromPreset(bytes);result.put("previewSupported",true);result.put("registrationName",profile.registrationName());result.put("model",profile.modelVersion());}
        catch(IOException unsupported){result.put("previewSupported",false);result.put("reason",unsupported.getMessage());}
        return SharedJson.encode(result);
    }
    public static PresetPreviewProfile colourProfile(byte[] preset,int strength,int[] values,
            PhotoCurves curves,PhotoHsl hsl,PhotoColorPalette palette,PhotoCleanup cleanup,PhotoLocalEdits local)throws IOException{
        if(strength<0||strength>100)throw new IllegalArgumentException("滤镜强度超出范围。");
        PresetPreviewProfile base=preset==null||preset.length==0?null:PresetPreviewProfiles.fromPreset(preset);
        if(base!=null)base=StrengthPreviewProfile.of(base,strength);
        PhotoAdjustments settings=new PhotoAdjustments(values,curves,hsl,palette,cleanup);
        return LocalEditsPreviewProfile.of(AdjustedPreviewProfile.of(base,settings),local);
    }
    /** Colour only. Oriented geometry/border compositing is a separate native raster stage. */
    public static int[] colourPreview(int[] pixels,int width,int height,byte[] preset,int strength,int[] values)throws IOException{
        return colourProfile(preset,strength,values,PhotoCurves.NONE,PhotoHsl.NONE,PhotoColorPalette.NONE,PhotoCleanup.NONE,PhotoLocalEdits.NONE).render(pixels,width,height);
    }
    /** Native row-backed surfaces keep full-size image buffers outside the UI runtime. */
    public static void fullColour(SpatialPreviewFilter.Pixels pixels,byte[] preset,int strength,int[] values,
            PhotoCurves curves,PhotoHsl hsl,PhotoColorPalette palette,PhotoCleanup cleanup,PhotoLocalEdits local,
            BooleanSupplier cancelled,DoubleConsumer progress)throws IOException{
        colourProfile(preset,strength,values,curves,hsl,palette,cleanup,local).renderPixels(pixels,cancelled,progress);
    }
}
