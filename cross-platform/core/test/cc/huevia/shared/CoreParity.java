package cc.huevia.shared;

import cc.huevia.ncp.*;
import cc.huevia.library.SharedJson;
import java.security.MessageDigest;
import java.util.*;

/** Original Java tests plus deterministic cross-runtime image fingerprints. */
public final class CoreParity {
    private CoreParity() {}
    public static String run()throws Exception{
        NcpPreviewProfileTest.main(new String[0]);
        PhotoLocalEditsTest.main(new String[0]);
        RawJpegColorMatchTest.main(new String[0]);
        RawHighlightColorTest.main(new String[0]);
        Map<String,Object> result=new LinkedHashMap<>();result.put("schema",1);result.put("engine",CoreEngine.VERSION);
        result.put("rawColorModel",RawJpegColorMatch.MODEL);result.put("tests","original-ncp-local-edits-raw-color-highlight");
        Map<String,Object> fingerprints=new LinkedHashMap<>();int width=96,height=64;int[] original=scene(width,height);
        int[] neutral=new int[PhotoAdjustments.Parameter.values().length];
        fingerprints.put("identity",hash(CoreEngine.colourPreview(original,width,height,null,100,neutral)));
        int[] exposure=neutral.clone();exposure[PhotoAdjustments.Parameter.EXPOSURE.ordinal()]=10;
        fingerprints.put("plus-one-ev",hash(CoreEngine.colourPreview(original,width,height,null,100,exposure)));
        int[] mixed=neutral.clone();mixed[PhotoAdjustments.Parameter.TEMPERATURE.ordinal()]=23;mixed[PhotoAdjustments.Parameter.TINT.ordinal()]=-17;mixed[PhotoAdjustments.Parameter.SATURATION.ordinal()]=19;
        fingerprints.put("colour",hash(CoreEngine.colourPreview(original,width,height,null,100,mixed)));
        int[] detail=neutral.clone();detail[PhotoAdjustments.Parameter.CLARITY.ordinal()]=16;detail[PhotoAdjustments.Parameter.SHARPENING.ordinal()]=24;detail[PhotoAdjustments.Parameter.GRAIN.ordinal()]=12;
        fingerprints.put("spatial-detail",hash(CoreEngine.colourPreview(original,width,height,null,100,detail)));
        PhotoCurves curves=PhotoCurves.NONE.withPoints(0,new int[]{0,0,64,52,180,204,255,255});
        PresetPreviewProfile curve=CoreEngine.colourProfile(null,100,neutral,curves,PhotoHsl.NONE,PhotoColorPalette.NONE,PhotoCleanup.NONE,PhotoLocalEdits.NONE);
        fingerprints.put("curves",hash(curve.render(original,width,height)));
        PhotoLocalEdits local=new PhotoLocalEdits(Collections.singletonList(PhotoLocalEdits.Mask.radial(.5,.5).parameters(15,-8,4)),Collections.emptyList());
        PresetPreviewProfile radial=CoreEngine.colourProfile(null,100,neutral,PhotoCurves.NONE,PhotoHsl.NONE,PhotoColorPalette.NONE,PhotoCleanup.NONE,local);
        fingerprints.put("local-radial",hash(radial.render(original,width,height)));
        if(!Arrays.equals(original,scene(width,height)))throw new AssertionError("Shared engine modified source pixels");
        result.put("fingerprints",fingerprints);return SharedJson.encode(result);
    }
    public static void main(String[] args)throws Exception{System.out.println("HUEVIA_CORE_GOLDEN="+run());}
    private static int[] scene(int width,int height){int[] out=new int[width*height];for(int y=0;y<height;y++)for(int x=0;x<width;x++)out[y*width+x]=0xff000000|((x*17+y*5)&255)<<16|((x*7+y*23)&255)<<8|((x*11+y*31)&255);return out;}
    private static String hash(int[] pixels)throws Exception{MessageDigest digest=MessageDigest.getInstance("SHA-256");for(int p:pixels){digest.update((byte)(p>>>24));digest.update((byte)(p>>>16));digest.update((byte)(p>>>8));digest.update((byte)p);}StringBuilder result=new StringBuilder();for(byte value:digest.digest())result.append(Character.forDigit(value>>>4&15,16)).append(Character.forDigit(value&15,16));return result.toString();}
}
