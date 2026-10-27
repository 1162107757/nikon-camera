package cc.huevia.ncp;

import java.io.IOException;
import java.util.function.BooleanSupplier;
import java.util.function.DoubleConsumer;
import static cc.huevia.ncp.PhotoAdjustments.Parameter.*;

/** Original -> complete preset/strength -> manual colour -> resolution-aware manual detail. */
public final class AdjustedPreviewProfile implements PresetPreviewProfile {
    private static final PresetPreviewProfile ORIGINAL = new PresetPreviewProfile(){
        public String registrationName(){return "无滤镜";} public String modelVersion(){return "original-srgb-v1";}
        public double mapTone(double v){return v;}public int applyArgb(int v){return v;}
    };
    private final PresetPreviewProfile base;
    private final PhotoAdjustments settings;
    private final double[][] channels=new double[3][256];
    private final boolean colourNeutral;
    private final double contrastGain, brightnessGain, highlightsGain, shadowsGain, whitesGain, blacksGain, saturationGain, vibranceGain;
    private final boolean hasCurves, hasHsl;
    private final ThreadLocal<double[]> rgb=ThreadLocal.withInitial(()->new double[3]);
    private AdjustedPreviewProfile(PresetPreviewProfile base,PhotoAdjustments settings){
        this.base=base;this.settings=settings;
        // Settings are immutable; retain the original arithmetic order while computing these once per profile.
        contrastGain=Math.exp(settings.get(CONTRAST)*.009);
        brightnessGain=settings.get(BRIGHTNESS)/100.0*.32;highlightsGain=settings.get(HIGHLIGHTS)/100.0*.38;shadowsGain=settings.get(SHADOWS)/100.0*.38;
        whitesGain=settings.get(WHITES)/100.0*.25;blacksGain=settings.get(BLACKS)/100.0*.25;
        saturationGain=1+settings.get(SATURATION)/100.0;vibranceGain=settings.get(VIBRANCE)/100.0*.8;
        hasCurves=!settings.curves.isNeutral();hasHsl=!settings.hsl.isNeutral();
        boolean neutral=true;for(PhotoAdjustments.Parameter p:PhotoAdjustments.Parameter.values())if(p.ordinal()<PhotoAdjustments.LEGACY_PARAMETER_COUNT&&p!=CLARITY&&p!=SHARPENING&&settings.get(p)!=0)neutral=false;
        colourNeutral=neutral&&settings.curves.isNeutral()&&settings.hsl.isNeutral();
        double exposure=Math.pow(2,settings.get(EXPOSURE)/10.0),t=settings.get(TEMPERATURE)/100.0,tint=settings.get(TINT)/100.0;
        double[] gain={Math.exp(.35*t+.13*tint),Math.exp(-.15*tint),Math.exp(-.35*t+.13*tint)};
        double normalize=.2126*gain[0]+.7152*gain[1]+.0722*gain[2];
        for(int c=0;c<3;c++)for(int v=0;v<256;v++)channels[c][v]=encode(linear(v/255.0)*exposure*gain[c]/normalize);
    }
    public static PresetPreviewProfile of(PresetPreviewProfile base,PhotoAdjustments settings){
        if(settings==null)throw new IllegalArgumentException("settings");
        if(settings.isNeutral())return base==null?ORIGINAL:base;
        return new AdjustedPreviewProfile(base,settings);
    }
    public String registrationName(){return base==null?"基础调节":base.registrationName();}
    public String modelVersion(){
        String value=(base==null?ORIGINAL.modelVersion():base.modelVersion())+":"+settings.identity();
        if(settings.curves.isNeutral()&&settings.hsl.isNeutral())return value;
        try{byte[] digest=java.security.MessageDigest.getInstance("SHA-256").digest(value.getBytes(java.nio.charset.StandardCharsets.UTF_8));StringBuilder key=new StringBuilder("photo-colour-v2:");for(byte b:digest)key.append(Character.forDigit((b>>>4)&15,16)).append(Character.forDigit(b&15,16));return key.toString();}catch(java.security.NoSuchAlgorithmException impossible){throw new AssertionError(impossible);}
    }
    public double mapTone(double value){return value;}
    public int applyArgb(int input){return manual(base==null?input:base.applyArgb(input));}
    private int manual(int input){
        if(colourNeutral)return input;
        double r=channels[0][(input>>>16)&255],g=channels[1][(input>>>8)&255],b=channels[2][input&255];
        double y=.2126*r+.7152*g+.0722*b;
        double next=.5+(y-.5)*contrastGain;
        next+=brightnessGain*4*y*(1-y);
        next+=highlightsGain*smooth(.45,1,y)*4*y*(1-y);
        next+=shadowsGain*(1-smooth(0,.55,y))*4*y*(1-y);
        next+=whitesGain*Math.pow(y,4);
        next+=blacksGain*Math.pow(1-y,4);
        double delta=clamp(next)-y;r+=delta;g+=delta;b+=delta;
        double l=.2126*r+.7152*g+.0722*b,max=Math.max(r,Math.max(g,b)),min=Math.min(r,Math.min(g,b));
        double saturation=max>0?(max-min)/max:0;
        double amount=saturationGain*(1+vibranceGain*Math.pow(1-saturation,2));
        r=l+(r-l)*amount;g=l+(g-l)*amount;b=l+(b-l)*amount;
        if(hasCurves){
            r=settings.curves.map(1,settings.curves.map(0,r));g=settings.curves.map(2,settings.curves.map(0,g));b=settings.curves.map(3,settings.curves.map(0,b));
        }
        if(hasHsl){double[] work=rgb.get();work[0]=r;work[1]=g;work[2]=b;settings.hsl.apply(work);r=work[0];g=work[1];b=work[2];}
        return (input&0xff000000)|(channel(r)<<16)|(channel(g)<<8)|channel(b);
    }
    @Override public void renderPixels(SpatialPreviewFilter.Pixels pixels,BooleanSupplier cancel,DoubleConsumer progress)throws IOException{
        boolean noise=settings.get(LUMA_DENOISE)!=0||settings.get(COLOR_DENOISE)!=0,finish=settings.get(GRAIN)!=0||settings.get(VIGNETTE)!=0;
        if(noise||finish){renderExtended(pixels,cancel,progress,noise,finish);return;}
        if(base!=null)base.renderPixels(pixels,cancel,progress==null?null:v->progress.accept(v*.5));
        SpatialPreviewFilter.Settings detail=new SpatialPreviewFilter.Settings(settings.get(SHARPENING)/100.0,0,settings.get(CLARITY)/100.0);
        SpatialPreviewFilter.applyScaled(pixels,detail,this::manual,cancel,progress==null?null:v->progress.accept((base==null?0:.5)+(base==null?1:.5)*v));
    }
    private void renderExtended(SpatialPreviewFilter.Pixels pixels,BooleanSupplier cancel,DoubleConsumer progress,boolean noise,boolean finish)throws IOException{
        double start=base==null?0:.25;if(base!=null)base.renderPixels(pixels,cancel,segment(progress,0,start));
        SpatialPreviewFilter.Settings detail=new SpatialPreviewFilter.Settings(settings.get(SHARPENING)/100.0,0,settings.get(CLARITY)/100.0);
        double tail=finish?.15:0,space=1-start-tail;
        if(noise){
            SpatialPreviewFilter.applyScaled(pixels,SpatialPreviewFilter.Settings.NONE,this::manual,cancel,segment(progress,start,space*.2));
            PhotoDetailEffects.denoise(pixels,settings.get(LUMA_DENOISE),settings.get(COLOR_DENOISE),cancel,segment(progress,start+space*.2,space*.6));
            SpatialPreviewFilter.applyScaled(pixels,detail,v->v,cancel,segment(progress,start+space*.8,space*.2));
        }else SpatialPreviewFilter.applyScaled(pixels,detail,this::manual,cancel,segment(progress,start,space));
        if(finish)PhotoDetailEffects.finish(pixels,settings.get(GRAIN),settings.get(VIGNETTE),cancel,segment(progress,1-tail,tail));
    }
    private static DoubleConsumer segment(DoubleConsumer progress,double start,double length){return progress==null?null:v->progress.accept(start+length*v);}
    private static double smooth(double a,double b,double v){double x=clamp((v-a)/(b-a));return x*x*(3-2*x);}
    private static double linear(double v){return v<=.04045?v/12.92:Math.pow((v+.055)/1.055,2.4);}
    private static double encode(double v){return v<=.0031308?clamp(v*12.92):clamp(1.055*Math.pow(v,1/2.4)-.055);}
    private static double clamp(double v){return Math.max(0,Math.min(1,v));}
    private static int channel(double v){return (int)Math.round(clamp(v)*255);}
}
