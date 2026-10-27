package cc.huevia.ncp;

import java.io.*;
import java.util.Arrays;

/** Eight overlapping hue bands, in encoded sRGB. Neutral settings leave pixels unchanged. */
public final class PhotoHsl {
    public static final String MODEL="photo-hsl-eight-bands-v1";
    public static final String[] NAMES={"红","橙","黄","绿","青","蓝","紫","洋红"};
    public static final double[] CENTERS={0,30,60,120,180,240,270,300};
    public static final int[] COLORS={0xffee635b,0xffeaa05b,0xffdfc967,0xff76b880,0xff68bfc1,0xff739de1,0xffa38bd7,0xffd383b5};
    public static final PhotoHsl NONE=new PhotoHsl(new int[24]);
    private final int[] values;
    private final int changed;
    public PhotoHsl(int[] values){if(values==null||values.length!=24)throw new IllegalArgumentException("HSL 数据不完整。");this.values=values.clone();for(int v:values)if(v< -100||v>100)throw new IllegalArgumentException("HSL 范围为 −100 至 100。");int n=0;for(int b=0;b<8;b++)if(get(b,0)!=0||get(b,1)!=0||get(b,2)!=0)n++;changed=n;}
    public int get(int band,int axis){check(band,axis);return values[band*3+axis];}
    public int[] values(){return values.clone();}
    public PhotoHsl with(int band,int axis,int value){check(band,axis);int[] copy=values();copy[band*3+axis]=value;return new PhotoHsl(copy);}
    public PhotoHsl reset(int band){int[] copy=values();for(int a=0;a<3;a++){check(band,a);copy[band*3+a]=0;}return new PhotoHsl(copy);}
    public int count(){return changed;}
    public boolean isNeutral(){return count()==0;}
    public String identity(){StringBuilder s=new StringBuilder(MODEL);for(int v:values)s.append(':').append(v);return s.toString();}
    /** Mutates one reusable RGB work vector; no per-pixel allocation. */
    public void apply(double[] rgb){
        if(isNeutral())return;
        double r=clamp(rgb[0]),g=clamp(rgb[1]),b=clamp(rgb[2]),max=Math.max(r,Math.max(g,b)),min=Math.min(r,Math.min(g,b)),delta=max-min;
        if(delta<1e-9)return;
        double light=(max+min)/2,sat=delta/(1-Math.abs(2*light-1));
        double hue=(max==r?(g-b)/delta+(g<b?6:0):max==g?(b-r)/delta+2:(r-g)/delta+4)*60;
        int left=7,right=0;double a=CENTERS[7],z=360;
        for(int i=0;i<7;i++)if(hue>=CENTERS[i]&&hue<CENTERS[i+1]){left=i;right=i+1;a=CENTERS[i];z=CENTERS[i+1];break;}
        double t=(hue-a)/(z-a);t=t*t*(3-2*t);
        double dh=(get(left,0)*(1-t)+get(right,0)*t)*.3;
        double ds=(get(left,1)*(1-t)+get(right,1)*t)/100;
        double dl=(get(left,2)*(1-t)+get(right,2)*t)/100;
        hue=(hue+dh+360)%360;sat=clamp(sat*(1+ds));
        // Reduce near-neutral spill and taper at the lightness endpoints.
        light=clamp(light+dl*.35*Math.min(1,delta*5)*4*light*(1-light));
        double chroma=(1-Math.abs(2*light-1))*sat,x=chroma*(1-Math.abs((hue/60)%2-1)),m=light-chroma/2;
        if(hue<60){r=chroma;g=x;b=0;}else if(hue<120){r=x;g=chroma;b=0;}else if(hue<180){r=0;g=chroma;b=x;}else if(hue<240){r=0;g=x;b=chroma;}else if(hue<300){r=x;g=0;b=chroma;}else{r=chroma;g=0;b=x;}
        rgb[0]=r+m;rgb[1]=g+m;rgb[2]=b+m;
    }
    public void write(DataOutput out)throws IOException{out.writeUTF(MODEL);for(int v:values)out.writeInt(v);}
    public static PhotoHsl read(DataInput in)throws IOException{if(!MODEL.equals(in.readUTF()))throw new IOException("HSL 版本不支持。");int[] v=new int[24];for(int i=0;i<24;i++)v[i]=in.readInt();try{return new PhotoHsl(v);}catch(IllegalArgumentException e){throw new IOException("HSL 数据损坏。",e);}}
    private static double clamp(double v){return Math.max(0,Math.min(1,v));}
    private static void check(int b,int a){if(b<0||b>=8||a<0||a>=3)throw new IllegalArgumentException("HSL 通道无效。");}
    @Override public boolean equals(Object value){return value instanceof PhotoHsl&&Arrays.equals(values,((PhotoHsl)value).values);}
    @Override public int hashCode(){return Arrays.hashCode(values);}
}
