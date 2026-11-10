package cc.huevia.ncp;

import java.util.Arrays;

/** Regression for a confident midtone fit that used to recolor known white highlights. */
public final class RawHighlightColorTest {
    private static int checks;
    public static void main(String[] args)throws Exception{
        int w=192,h=128;int[] source=RawJpegColorMatchTest.scene(w,h),reference=source.clone();
        for(int y=0;y<h;y++)for(int x=0;x<w;x++){
            int i=y*w+x,p=source[i],r=p>>>16&255,g=p>>>8&255,b=p&255;
            reference[i]=0xff000000|channel(.1+1.15*r/255.0)<<16|channel(.1+.74*g/255.0)<<8|channel(.1+1.15*b/255.0);
            if(x>140&&y<30){int n=220+(x-141)*35/50;source[i]=0xff000000|n<<16|n<<8|n;reference[i]=0xffffffff;}
        }
        int[] before=source.clone(),referenceBefore=reference.clone();
        RawJpegColorMatch.Fit fit=RawJpegColorMatch.fit(source,w,h,reference,w,h,null);
        check(fit.correlation>.95,"same-frame alignment remains reliable");
        for(int n=220;n<=255;n++){
            int p=0x65000000|n<<16|n<<8|n,out=fit.applyArgb(p);
            int r=out>>>16&255,g=out>>>8&255,b=out&255;
            check(Math.min(r,b)-g<=3,"known white highlight cannot become magenta "+n);
            check(out>>>24==0x65,"highlight alpha preserved "+n);
            if(!fit.accepted)check(out==p,"rejected fit preserves the developed original "+n);
        }
        if(!fit.accepted)check("UNSAFE_HIGHLIGHTS".equals(fit.reason),"unsafe color model has an explicit rejection reason");
        int magenta=fit.applyArgb(0xffff00ff);
        check((magenta>>>16&255)>200&&(magenta&255)>200&&(magenta>>>8&255)<80,"real saturated magenta remains colored");
        check(Arrays.equals(source,before)&&Arrays.equals(reference,referenceBefore),"analysis never mutates RAW/reference pixels");

        int[] good=RawJpegColorMatchTest.scene(w,h),target=new int[good.length];
        for(int i=0;i<good.length;i++){int p=good[i];target[i]=0xff000000|tone(p>>>16&255)<<16|tone(p>>>8&255)<<8|tone(p&255);}
        RawJpegColorMatch.Fit safe=RawJpegColorMatch.fit(good,w,h,target,w,h,null);
        check(safe.accepted,"ordinary camera tone approximation still accepted");
        check(safe.applyArgb(0x73ffffff)==0x73ffffff,"accepted LUT fixes display white exactly");
        double highest=0;
        for(int n=128;n<=255;n++){
            int p=safe.applyArgb(0xff000000|n<<16|n<<8|n);
            double light=.2126*(p>>>16&255)+.7152*(p>>>8&255)+.0722*(p&255);
            check(light+3>=highest,"neutral highlights do not fold darker "+n);highest=Math.max(highest,light);
        }
        check("same-raw-jpeg-crop-ridge-cubic-lut17-white-v2".equals(RawJpegColorMatch.MODEL),"cache model identity advances for changed pixels");
        System.out.println("PASS RAW highlight color "+checks+" checks; unsafe-midtones-only fit "+fit.reason);
    }
    private static int tone(int n){return channel(1-Math.pow(1-n/255.0,1.15));}
    private static int channel(double v){return Math.max(0,Math.min(255,(int)Math.round(v*255)));}
    private static void check(boolean value,String message){checks++;if(!value)throw new AssertionError(message);}
}
