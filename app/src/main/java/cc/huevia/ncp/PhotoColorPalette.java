package cc.huevia.ncp;

import java.io.DataInput;
import java.io.DataOutput;
import java.io.IOException;

/** Independent two-axis colour/tonal look. Coordinates never overwrite manual sliders. */
public final class PhotoColorPalette {
    public static final String MODEL="photo-colour-tone-palette-v1";
    public static final PhotoColorPalette NONE=new PhotoColorPalette(0,0,100);
    public final int color,tone,amount;
    public PhotoColorPalette(int color,int tone,int amount){
        if(color< -100||color>100||tone< -100||tone>100||amount<0||amount>100)throw new IllegalArgumentException("调色盘数值超出范围。");
        this.color=color;this.tone=tone;this.amount=amount;
    }
    public PhotoColorPalette withColor(int value){return new PhotoColorPalette(value,tone,amount);}
    public PhotoColorPalette withTone(int value){return new PhotoColorPalette(color,value,amount);}
    public PhotoColorPalette withAmount(int value){return new PhotoColorPalette(color,tone,value);}
    public boolean isNeutral(){return amount==0||color==0&&tone==0;}
    /** Zero intensity still retains the chosen point for reopening and version identity. */
    public boolean hasStoredState(){return color!=0||tone!=0||amount!=100;}
    public String identity(){return MODEL+":"+color+":"+tone+":"+amount;}
    public int applyArgb(int input){
        if(isNeutral()||(input>>>24)==0)return input;
        double r=((input>>>16)&255)/255.0,g=((input>>>8)&255)/255.0,b=(input&255)/255.0;
        double originalR=r,originalG=g,originalB=b,y=.2126*r+.7152*g+.0722*b;
        if(tone!=0&&y>0&&y<1){
            // Bounded, monotone contrast about mid-gray; black and white remain fixed.
            double k=tone/100.0*.9,next=y+k*(2*y-1)*y*(1-y);
            if(next<y){double scale=next/y;r*=scale;g*=scale;b*=scale;}
            else{double lift=(next-y)/(1-y);r+=(1-r)*lift;g+=(1-g)*lift;b+=(1-b)*lift;}
            y=next;
        }
        if(color!=0){
            double max=Math.max(r,Math.max(g,b)),min=Math.min(r,Math.min(g,b)),chroma=max-min;
            double factor=1+color/100.0;
            if(color>0){
                double saturation=max==0?0:chroma/max,warm=0;
                if(chroma>0){double hue=max==r?(g-b)/chroma:max==g?2+(b-r)/chroma:4+(r-g)/chroma;hue*=60;if(hue<0)hue+=360;
                    double distance=Math.min(Math.abs(hue-30),360-Math.abs(hue-30));warm=1-smooth(15,65,distance);}
                // Prefer muted colours, reduce additional warm-hue saturation, fit into gamut.
                factor=1+color/100.0*.85*Math.pow(1-saturation,1.5)*(1-.55*warm);
                factor=Math.min(factor,Math.min(gamut(y,r-y),Math.min(gamut(y,g-y),gamut(y,b-y))));
            }
            r=y+(r-y)*factor;g=y+(g-y)*factor;b=y+(b-y)*factor;
        }
        double mix=amount/100.0;
        return (input&0xff000000)|(channel(originalR+(r-originalR)*mix)<<16)|(channel(originalG+(g-originalG)*mix)<<8)|channel(originalB+(b-originalB)*mix);
    }
    private static double gamut(double y,double delta){return delta>0?(1-y)/delta:delta<0?-y/delta:Double.POSITIVE_INFINITY;}
    private static double smooth(double a,double b,double value){double x=Math.max(0,Math.min(1,(value-a)/(b-a)));return x*x*(3-2*x);}
    private static int channel(double value){return (int)Math.round(Math.max(0,Math.min(1,value))*255);}
    public void write(DataOutput out)throws IOException{out.writeByte(1);out.writeInt(color);out.writeInt(tone);out.writeInt(amount);}
    public static PhotoColorPalette read(DataInput in)throws IOException{
        if(in.readUnsignedByte()!=1)throw new IOException("调色盘版本不支持。");
        try{return new PhotoColorPalette(in.readInt(),in.readInt(),in.readInt());}catch(IllegalArgumentException invalid){throw new IOException("调色盘数据无效。",invalid);}
    }
    @Override public boolean equals(Object other){return other instanceof PhotoColorPalette&&color==((PhotoColorPalette)other).color&&tone==((PhotoColorPalette)other).tone&&amount==((PhotoColorPalette)other).amount;}
    @Override public int hashCode(){return (color*31+tone)*31+amount;}
}
