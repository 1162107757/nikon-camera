package cc.huevia.ncp;

import java.io.DataInput;
import java.io.DataOutput;
import java.io.IOException;
import java.util.Locale;
import java.util.Objects;

/** Immutable RAW development controls, before the existing 8-bit sRGB photo editing chain. */
public final class RawDevelopmentSettings {
    public static final String MODEL="libraw-0.22.3-full-srgb8-v1";
    private static final int MAGIC=0x52445331;
    public enum WhiteBalance { CAMERA, AUTO, CUSTOM }
    public static final RawDevelopmentSettings DEFAULT=new RawDevelopmentSettings(WhiteBalance.CAMERA,5500,0,0,2,3);
    public final WhiteBalance whiteBalance;
    public final int temperatureKelvin,tint,exposureTenths,highlightMode,demosaicQuality;
    public RawDevelopmentSettings(WhiteBalance whiteBalance,int temperatureKelvin,int tint,int exposureTenths,int highlightMode,int demosaicQuality){
        if(whiteBalance==null||temperatureKelvin<2000||temperatureKelvin>12000||tint< -100||tint>100||exposureTenths< -50||exposureTenths>50||highlightMode<0||highlightMode>9||(demosaicQuality!=0&&demosaicQuality!=3))throw new IllegalArgumentException("RAW 显影参数无效。");
        this.whiteBalance=whiteBalance;this.temperatureKelvin=temperatureKelvin;this.tint=tint;this.exposureTenths=exposureTenths;this.highlightMode=highlightMode;this.demosaicQuality=demosaicQuality;
    }
    public RawDevelopmentSettings withWhiteBalance(WhiteBalance value){return new RawDevelopmentSettings(value,temperatureKelvin,tint,exposureTenths,highlightMode,demosaicQuality);}
    public RawDevelopmentSettings withTemperature(int value){return new RawDevelopmentSettings(WhiteBalance.CUSTOM,value,tint,exposureTenths,highlightMode,demosaicQuality);}
    public RawDevelopmentSettings withTint(int value){return new RawDevelopmentSettings(WhiteBalance.CUSTOM,temperatureKelvin,value,exposureTenths,highlightMode,demosaicQuality);}
    public RawDevelopmentSettings withExposure(int value){return new RawDevelopmentSettings(whiteBalance,temperatureKelvin,tint,value,highlightMode,demosaicQuality);}
    public RawDevelopmentSettings withHighlights(int value){return new RawDevelopmentSettings(whiteBalance,temperatureKelvin,tint,exposureTenths,value,demosaicQuality);}
    public RawDevelopmentSettings withDemosaicQuality(int value){return new RawDevelopmentSettings(whiteBalance,temperatureKelvin,tint,exposureTenths,highlightMode,value);}
    public String identity(){return MODEL+":"+whiteBalance.name()+":"+temperatureKelvin+":"+tint+":"+exposureTenths+":"+highlightMode+":"+demosaicQuality;}
    public String summary(){return (whiteBalance==WhiteBalance.CAMERA?"相机白平衡":whiteBalance==WhiteBalance.AUTO?"自动白平衡":temperatureKelvin+"K")+" · "+String.format(Locale.ROOT,"%+.1f EV",exposureTenths/10.0);}
    public void write(DataOutput output)throws IOException{output.writeInt(MAGIC);output.writeInt(whiteBalance.ordinal());output.writeInt(temperatureKelvin);output.writeInt(tint);output.writeInt(exposureTenths);output.writeInt(highlightMode);output.writeInt(demosaicQuality);}
    public static RawDevelopmentSettings read(DataInput input)throws IOException{if(input.readInt()!=MAGIC)throw new IOException("RAW 显影设置版本不支持。");int wb=input.readInt(),temperature=input.readInt(),tint=input.readInt(),exposure=input.readInt(),highlight=input.readInt(),quality=input.readInt();if(wb<0||wb>=WhiteBalance.values().length)throw new IOException("RAW 白平衡设置损坏。");try{return new RawDevelopmentSettings(WhiteBalance.values()[wb],temperature,tint,exposure,highlight,quality);}catch(IllegalArgumentException invalid){throw new IOException("RAW 显影设置损坏。",invalid);}}
    @Override public boolean equals(Object value){if(!(value instanceof RawDevelopmentSettings))return false;RawDevelopmentSettings s=(RawDevelopmentSettings)value;return whiteBalance==s.whiteBalance&&temperatureKelvin==s.temperatureKelvin&&tint==s.tint&&exposureTenths==s.exposureTenths&&highlightMode==s.highlightMode&&demosaicQuality==s.demosaicQuality;}
    @Override public int hashCode(){return Objects.hash(whiteBalance,temperatureKelvin,tint,exposureTenths,highlightMode,demosaicQuality);}
}
