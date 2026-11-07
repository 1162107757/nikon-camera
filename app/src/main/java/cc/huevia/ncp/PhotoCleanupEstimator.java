package cc.huevia.ncp;

import java.io.*;
import java.util.*;
import java.util.function.BooleanSupplier;

/** Bounded statistics from an oriented small sample and independently decoded 100% patches. */
public final class PhotoCleanupEstimator {
    private PhotoCleanupEstimator(){}
    public static final class Patch {
        final int[] pixels;final byte[] coverage;final int width,height;
        public Patch(int[] pixels,int width,int height,byte[] coverage){if(width<3||height<3||width>128||height>128||pixels==null||pixels.length!=width*height||coverage!=null&&coverage.length!=pixels.length)throw new IllegalArgumentException("原图噪点样本无效。");this.pixels=pixels.clone();this.width=width;this.height=height;this.coverage=coverage==null?null:coverage.clone();}
    }
    public static PhotoCleanup.Analysis analyze(int[] sample,int width,int height,int sourceWidth,int sourceHeight,List<Patch> patches,byte[] coverage,BooleanSupplier cancel)throws IOException{
        if(width<1||height<1||width>512||height>512||sample==null||sample.length!=width*height||coverage!=null&&coverage.length!=sample.length||patches==null||patches.size()>12)throw new IllegalArgumentException("去灰分析样本无效。");
        int[] luma=new int[256],dark=new int[256];int count=0,gradients=0;double edge=0;
        for(int y=0;y<height;y++){check(cancel);for(int x=0;x<width;x++){int i=y*width+x,p=sample[i];if(!included(p,coverage,i))continue;int value=luma(p);luma[value]++;dark[Math.min((p>>>16)&255,Math.min((p>>>8)&255,p&255))]++;count++;
            if(x>0&&included(sample[i-1],coverage,i-1)){edge+=Math.abs(value-luma(sample[i-1]));gradients++;}if(y>0&&included(sample[i-width],coverage,i-width)){edge+=Math.abs(value-luma(sample[i-width]));gradients++;}}}
        int low=quantile(luma,count,.05),high=quantile(luma,count,.95),black=quantile(dark,count,.05),bright=quantile(luma,count,.85);long ar=0,ag=0,ab=0;int airCount=0;
        for(int i=0;i<sample.length;i++){if((i&4095)==0)check(cancel);int p=sample[i];if(!included(p,coverage,i))continue;int r=(p>>>16)&255,g=(p>>>8)&255,b=p&255,max=Math.max(r,Math.max(g,b)),min=Math.min(r,Math.min(g,b));if(luma(p)>=bright&&max<254&&max-min<110){ar+=r;ag+=g;ab+=b;airCount++;}}
        int airR=air(airCount==0?230:ar/(double)airCount),airG=air(airCount==0?230:ag/(double)airCount),airB=air(airCount==0?230:ab/(double)airCount);
        double contrast=(high-low)/255.0,meanEdge=gradients==0?0:edge/gradients/255;
        double confidence=PhotoCleanup.smooth(.015,.12,black/255.0)*PhotoCleanup.smooth(.08,.32,contrast)*PhotoCleanup.smooth(.002,.018,meanEdge)*(1-PhotoCleanup.smooth(.48,.78,low/255.0))*(1-.8*PhotoCleanup.smooth(.91,.995,high/255.0));
        if(count<64)confidence=0;
        double airL=.2126*PhotoCleanup.linear(airR/255.0)+.7152*PhotoCleanup.linear(airG/255.0)+.0722*PhotoCleanup.linear(airB/255.0);
        int veil=(int)Math.round(Math.min(.32,PhotoCleanup.linear(black/255.0)/Math.max(.2,airL)*.82)/.32*100);
        int[] ly=new int[2049],cb=new int[2049],cr=new int[2049];int noiseCount=0,patchPixels=0;
        for(Patch patch:patches){Objects.requireNonNull(patch,"patch");patchPixels+=patch.pixels.length;int w=patch.width,h=patch.height;
            for(int y=1;y<h-1;y++){check(cancel);for(int x=1;x<w-1;x++){int i=y*w+x;if(!flat(patch,i,w))continue;int centre=patch.pixels[i],up=patch.pixels[i-w],down=patch.pixels[i+w],left=patch.pixels[i-1],right=patch.pixels[i+1];
                histogram(ly,4*luma(centre)-luma(up)-luma(down)-luma(left)-luma(right));histogram(cb,4*chroma(centre,false)-chroma(up,false)-chroma(down,false)-chroma(left,false)-chroma(right,false));histogram(cr,4*chroma(centre,true)-chroma(up,true)-chroma(down,true)-chroma(left,true)-chroma(right,true));noiseCount++;}}
        }
        // Five-point Laplacian has variance 20*sigma^2; median absolute residual -> robust sigma.
        double sigmaY=quantile(ly,noiseCount,.5)/(.67448975*Math.sqrt(20)),sigmaC=Math.max(quantile(cb,noiseCount,.5),quantile(cr,noiseCount,.5))/(.67448975*Math.sqrt(20));
        int noiseConfidence=noiseCount<64?0:(int)Math.round(Math.min(1,noiseCount/768.0)*100);
        int lumaNoise=noiseConfidence==0?0:(int)Math.round(Math.min(100,Math.max(0,sigmaY-.45)*5)),chromaNoise=noiseConfidence==0?0:(int)Math.round(Math.min(100,Math.max(0,sigmaC-.6)*4));
        return new PhotoCleanup.Analysis(sourceWidth,sourceHeight,patches.size(),patchPixels,noiseCount,(int)Math.round(confidence*85),noiseConfidence,veil,airR,airG,airB,lumaNoise,chromaNoise);
    }
    private static boolean flat(Patch p,int i,int w){int min=255,max=0;for(int dy=-1;dy<=1;dy++)for(int dx=-1;dx<=1;dx++){int at=i+dy*w+dx,value=p.pixels[at];if(!included(value,p.coverage,at))return false;int y=luma(value);if(y<8||y>247)return false;min=Math.min(min,y);max=Math.max(max,y);}if(max-min>65)return false;int a=luma(p.pixels[i-w-1])+luma(p.pixels[i-w+1]),b=luma(p.pixels[i+w-1])+luma(p.pixels[i+w+1]),c=luma(p.pixels[i-w-1])+luma(p.pixels[i+w-1]),d=luma(p.pixels[i-w+1])+luma(p.pixels[i+w+1]);return Math.abs(a-b)<35&&Math.abs(c-d)<35;}
    private static boolean included(int p,byte[] coverage,int i){return (p>>>24)>=192&&(coverage==null||(coverage[i]&255)>=192);}
    private static int air(double value){return (int)Math.round(Math.min(255,Math.max(180,value*.9+25.5)));}
    private static int luma(int p){return (int)Math.round(.2126*((p>>>16)&255)+.7152*((p>>>8)&255)+.0722*(p&255));}
    private static int chroma(int p,boolean red){return (red?(p>>>16)&255:p&255)-luma(p);}
    private static void histogram(int[] histogram,int value){histogram[Math.min(histogram.length-1,Math.abs(value))]++;}
    private static int quantile(int[] histogram,int count,double q){if(count==0)return 0;int target=Math.max(1,(int)Math.ceil(count*q)),sum=0;for(int i=0;i<histogram.length;i++){sum+=histogram[i];if(sum>=target)return i;}return histogram.length-1;}
    static void check(BooleanSupplier cancel)throws InterruptedIOException{if(Thread.currentThread().isInterrupted()||cancel!=null&&cancel.getAsBoolean())throw new InterruptedIOException("去灰处理已取消。");}
}
