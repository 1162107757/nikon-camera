package cc.huevia.ncp;

import java.io.*;
import java.util.Objects;

/** Frozen, independent automatic cleanup. No source data is inferred while rendering. */
public final class PhotoCleanup {
    public static final String MODEL="photo-cleanup-veil-noise-v1";
    public static final PhotoCleanup NONE=new PhotoCleanup(0,100,100,null);
    private static final double[] LINEAR=new double[256];
    static{for(int i=0;i<256;i++)LINEAR[i]=linear(i/255.0);}
    public final int amount,haze,noise;
    public final Analysis analysis;
    public PhotoCleanup(int amount,int haze,int noise,Analysis analysis){
        range(amount,100);range(haze,100);range(noise,100);this.amount=amount;this.haze=haze;this.noise=noise;this.analysis=analysis;
    }
    public PhotoCleanup withAmount(int value){return new PhotoCleanup(value,haze,noise,analysis);}
    public PhotoCleanup withHaze(int value){return new PhotoCleanup(amount,value,noise,analysis);}
    public PhotoCleanup withNoise(int value){return new PhotoCleanup(amount,haze,value,analysis);}
    public PhotoCleanup withAnalysis(Analysis value){return new PhotoCleanup(amount,haze,noise,value);}
    public boolean hasStoredState(){return amount!=0||haze!=100||noise!=100||analysis!=null;}
    public boolean hasHazeEffect(){return amount>0&&haze>0&&analysis!=null&&analysis.veil>0&&analysis.hazeConfidence>0;}
    public boolean hasNoiseEffect(){return amount>0&&noise>0&&analysis!=null&&analysis.noiseConfidence>0&&(analysis.lumaNoise>0||analysis.chromaNoise>0);}
    public boolean isNeutral(){return !hasHazeEffect()&&!hasNoiseEffect();}
    public String identity(){return MODEL+":"+amount+":"+haze+":"+noise+(analysis==null?":none":":"+analysis.identity());}
    /** Colour part only; spatial denoising is performed by PhotoCleanupRenderer. */
    public int applyArgb(int input){
        if(!hasHazeEffect()||(input>>>24)==0)return input;
        double er=((input>>>16)&255)/255.0,eg=((input>>>8)&255)/255.0,eb=(input&255)/255.0;
        double y=.2126*er+.7152*eg+.0722*eb;
        double v=.32*analysis.veil/100.0*analysis.hazeConfidence/100.0*amount/100.0*haze/100.0*(1-smooth(.78,.985,y));
        double r=LINEAR[(input>>>16)&255],g=LINEAR[(input>>>8)&255],b=LINEAR[input&255],ar=LINEAR[analysis.airRed],ag=LINEAR[analysis.airGreen],ab=LINEAR[analysis.airBlue];
        // Limit atmospheric subtraction per channel, protecting both ends without clipping.
        v=Math.min(v,Math.min(bound(r,ar),Math.min(bound(g,ag),bound(b,ab))));
        if(v<=1e-8)return input;
        double t=1-v;
        return (input&0xff000000)|(channel(encode((r-ar*v)/t))<<16)|(channel(encode((g-ag*v)/t))<<8)|channel(encode((b-ab*v)/t));
    }
    private static double bound(double value,double air){return Math.min(air>0?value*.82/air:1,air<1?(1-value)*.82/(1-air):1);}
    static double linear(double v){return v<=.04045?v/12.92:Math.pow((v+.055)/1.055,2.4);}
    private static double encode(double v){return v<=.0031308?v*12.92:1.055*Math.pow(v,1/2.4)-.055;}
    static double smooth(double a,double b,double v){double x=Math.max(0,Math.min(1,(v-a)/(b-a)));return x*x*(3-2*x);}
    private static int channel(double v){return (int)Math.round(Math.max(0,Math.min(1,v))*255);}
    private static void range(int value,int max){if(value<0||value>max)throw new IllegalArgumentException("去灰参数超出范围。");}
    public void write(DataOutput out)throws IOException{out.writeByte(1);out.writeByte(amount);out.writeByte(haze);out.writeByte(noise);out.writeBoolean(analysis!=null);if(analysis!=null)analysis.write(out);}
    public static PhotoCleanup read(DataInput in)throws IOException{
        if(in.readUnsignedByte()!=1)throw new IOException("去灰版本不支持。");
        try{int amount=in.readUnsignedByte(),haze=in.readUnsignedByte(),noise=in.readUnsignedByte(),present=in.readUnsignedByte();if(present>1)throw new IOException("去灰分析标记无效。");return new PhotoCleanup(amount,haze,noise,present==1?Analysis.read(in):null);}catch(IllegalArgumentException invalid){throw new IOException("去灰数据无效。",invalid);}
    }
    @Override public boolean equals(Object value){if(!(value instanceof PhotoCleanup))return false;PhotoCleanup p=(PhotoCleanup)value;return amount==p.amount&&haze==p.haze&&noise==p.noise&&Objects.equals(analysis,p.analysis);}
    @Override public int hashCode(){return Objects.hash(amount,haze,noise,analysis);}

    public static final class Analysis {
        public final int sourceWidth,sourceHeight,patchCount,patchPixels,noiseSamples,hazeConfidence,noiseConfidence,veil,airRed,airGreen,airBlue,lumaNoise,chromaNoise;
        public Analysis(int sourceWidth,int sourceHeight,int patchCount,int patchPixels,int noiseSamples,int hazeConfidence,int noiseConfidence,int veil,int airRed,int airGreen,int airBlue,int lumaNoise,int chromaNoise){
            if(sourceWidth<1||sourceWidth>65535||sourceHeight<1||sourceHeight>65535||patchCount<0||patchCount>12||patchPixels<patchCount*9||patchPixels>patchCount*16384||noiseSamples<0||noiseSamples>patchPixels||noiseSamples==0&&(noiseConfidence!=0||lumaNoise!=0||chromaNoise!=0))throw new IllegalArgumentException("去灰分析数据无效。");
            range(hazeConfidence,100);range(noiseConfidence,100);range(veil,100);range(airRed,255);range(airGreen,255);range(airBlue,255);range(lumaNoise,100);range(chromaNoise,100);
            this.sourceWidth=sourceWidth;this.sourceHeight=sourceHeight;this.patchCount=patchCount;this.patchPixels=patchPixels;this.noiseSamples=noiseSamples;this.hazeConfidence=hazeConfidence;this.noiseConfidence=noiseConfidence;this.veil=veil;this.airRed=airRed;this.airGreen=airGreen;this.airBlue=airBlue;this.lumaNoise=lumaNoise;this.chromaNoise=chromaNoise;
        }
        String identity(){return sourceWidth+":"+sourceHeight+":"+patchCount+":"+patchPixels+":"+noiseSamples+":"+hazeConfidence+":"+noiseConfidence+":"+veil+":"+airRed+":"+airGreen+":"+airBlue+":"+lumaNoise+":"+chromaNoise;}
        void write(DataOutput out)throws IOException{out.writeInt(sourceWidth);out.writeInt(sourceHeight);out.writeByte(patchCount);out.writeInt(patchPixels);out.writeInt(noiseSamples);out.writeByte(hazeConfidence);out.writeByte(noiseConfidence);out.writeByte(veil);out.writeByte(airRed);out.writeByte(airGreen);out.writeByte(airBlue);out.writeByte(lumaNoise);out.writeByte(chromaNoise);}
        static Analysis read(DataInput in)throws IOException{return new Analysis(in.readInt(),in.readInt(),in.readUnsignedByte(),in.readInt(),in.readInt(),in.readUnsignedByte(),in.readUnsignedByte(),in.readUnsignedByte(),in.readUnsignedByte(),in.readUnsignedByte(),in.readUnsignedByte(),in.readUnsignedByte(),in.readUnsignedByte());}
        @Override public boolean equals(Object value){return value instanceof Analysis&&identity().equals(((Analysis)value).identity());}
        @Override public int hashCode(){return identity().hashCode();}
    }
}
