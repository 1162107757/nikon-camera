package cc.huevia.ncp;

import java.io.InterruptedIOException;
import java.util.Arrays;
import java.util.Random;
import java.util.concurrent.atomic.AtomicInteger;

/** Independent full-raster checks in addition to the fitter's spatial holdout. */
public final class RawJpegColorMatchTest {
    private static int checks;
    public static void main(String[] args) throws Exception {
        int w=192,h=128;int[] source=scene(w,h),original=source.clone(),target=graded(source,false);
        RawJpegColorMatch.Fit fit=RawJpegColorMatch.fit(source,w,h,target,w,h,()->false);
        check(fit.accepted&&"MATCHED".equals(fit.reason),"known smooth camera grade accepted");
        check(fit.orientation==0&&fit.correlation>.96,"same-frame alignment recognized");
        double before=error(source,target,null),after=error(source,target,fit);
        check(after<before*.35&&after<.015,"independent full-raster RGB error reduced");
        check(fit.afterError<fit.beforeError*.35,"heldout error reduced");
        check(Arrays.equals(source,original),"RAW analysis pixels unchanged");
        check(Arrays.equals(target,graded(source,false)),"reference pixels unchanged");
        float[] table=fit.table();check(table.length==17*17*17*3,"bounded 17 cubed LUT");
        for(float value:table)check(Float.isFinite(value)&&value>=0&&value<=1,"finite RGB table");
        int pixel=0x73126bca,first=fit.applyArgb(pixel);Arrays.fill(table,Float.NaN);
        check(fit.applyArgb(pixel)==first&&(first>>>24)==0x73,"LUT defensive copy and alpha retained");
        for(int transform=0;transform<8;transform++) {
            int rw=transform%2==0?w:h,rh=transform%2==0?h:w;
            int[] turned=transform(target,w,h,transform);
            RawJpegColorMatch.Fit rotated=RawJpegColorMatch.fit(source,w,h,turned,rw,rh,()->false);
            check(rotated.accepted&&rotated.orientation==transform,"orientation and mirror "+transform);
            check(error(source,target,rotated)<before*.35,"orientation full-raster recovery "+transform);
        }
        for(double zoom:new double[]{1.05,1.10,1.15}) {
            int[] crop=crop(target,w,h,zoom);RawJpegColorMatch.Fit registered=RawJpegColorMatch.fit(source,w,h,crop,w,h,null);
            check(registered.accepted&&Math.abs(registered.referenceScale-zoom)<=.011,"camera JPEG crop registration "+zoom);
            check(error(source,target,registered)<.012,"cropped reference changes color without cropping RAW "+zoom);
        }
        RawJpegColorMatch.Fit identity=RawJpegColorMatch.fit(source,w,h,source,w,h,null);
        check(identity.accepted&&"ALREADY_CLOSE".equals(identity.reason)&&identity.table().length==0,"identity has no transform");
        for(int i=0;i<source.length;i+=31)check(identity.applyArgb(source[i])==source[i],"identity byte exact");
        int[] mono=graded(source,true);RawJpegColorMatch.Fit monochrome=RawJpegColorMatch.fit(source,w,h,mono,w,h,null);
        check(monochrome.accepted&&error(source,mono,monochrome)<.015,"monochrome JPEG tone can be approximated");
        int[] unrelated=new int[source.length];Random random=new Random(1729);
        for(int i=0;i<unrelated.length;i++)unrelated[i]=0xff000000|random.nextInt(0x1000000);
        RawJpegColorMatch.Fit wrong=RawJpegColorMatch.fit(source,w,h,unrelated,w,h,null);
        check(!wrong.accepted&&"UNRELIABLE_ALIGNMENT".equals(wrong.reason)&&wrong.applyArgb(pixel)==pixel,"unrelated reference rejected without pixel change");
        int[] flat=new int[source.length];Arrays.fill(flat,0xff808080);
        check(!RawJpegColorMatch.fit(flat,w,h,flat,w,h,null).accepted,"flat ambiguous scene rejected");
        check(!RawJpegColorMatch.fit(source,w,h,new int[96*96],96,96,null).accepted,"incompatible aspect rejected");
        check("REFERENCE_TOO_SMALL".equals(RawJpegColorMatch.fit(new int[32*32],32,32,new int[32*32],32,32,null).reason),"tiny reference rejected");
        check(!RawJpegColorMatch.unavailable("NO_REFERENCE").accepted,"missing reference no correction");
        invalid(()->RawJpegColorMatch.fit(null,w,h,target,w,h,null));
        invalid(()->RawJpegColorMatch.fit(source,w+1,h,target,w,h,null));
        invalid(()->RawJpegColorMatch.fit(new int[1],Integer.MAX_VALUE,Integer.MAX_VALUE,target,w,h,null));
        interrupted(()->RawJpegColorMatch.fit(source,w,h,target,w,h,()->true));
        AtomicInteger calls=new AtomicInteger();interrupted(()->RawJpegColorMatch.fit(source,w,h,target,w,h,()->calls.incrementAndGet()>12));
        check(calls.get()>12,"cancellation during fit observed");
        System.out.printf(java.util.Locale.ROOT,"PASS JPEG color matching %d checks; full-raster RGB RMSE %.6f -> %.6f; heldout %.6f -> %.6f%n",checks,before,after,fit.beforeError,fit.afterError);
    }
    public static int[] scene(int w,int h) {
        int[] pixels=new int[w*h];
        for(int y=0;y<h;y++)for(int x=0;x<w;x++) {
            double u=x/(double)(w-1),v=y/(double)(h-1);
            double r=.42+.21*Math.sin(u*8.3+v*2.6)+.11*Math.cos(v*13.1-u*3.7);
            double g=.46+.19*Math.cos(u*5.2-v*7.3)+.12*Math.sin(v*11.4+u*2.3);
            double b=.43+.22*Math.sin(u*11.3-v*4.1)+.12*Math.cos(v*8.8+u*1.9);
            pixels[y*w+x]=0xff000000|channel(r)<<16|channel(g)<<8|channel(b);
        }return pixels;
    }
    private static int[] graded(int[] source,boolean mono) {
        int[] result=new int[source.length];
        for(int i=0;i<source.length;i++) {
            int p=source[i];double r=((p>>>16)&255)/255.0,g=((p>>>8)&255)/255.0,b=(p&255)/255.0;
            double rr=.025+.97*r+.035*g+.08*r*(1-r)-.015*b;
            double gg=.018+.96*g+.025*r+.035*g*(1-g);
            double bb=.012+.94*b+.025*g-.015*r+.06*b*b;
            if(mono)rr=gg=bb=.05+.85*(.2126*r+.7152*g+.0722*b);
            result[i]=0xff000000|channel(rr)<<16|channel(gg)<<8|channel(bb);
        }return result;
    }
    private static int[] transform(int[] image,int w,int h,int transform) {
        int rw=transform%2==0?w:h,rh=transform%2==0?h:w;int[] out=new int[rw*rh];
        for(int y=0;y<h;y++)for(int x=0;x<w;x++) {
            int u=transform>=4?w-1-x:x,rx=u,ry=y;
            switch(transform%4){case 1:rx=y;ry=w-1-u;break;case 2:rx=w-1-u;ry=h-1-y;break;case 3:rx=h-1-y;ry=u;break;}
            out[ry*rw+rx]=image[y*w+x];
        }return out;
    }
    private static int[] crop(int[] image,int w,int h,double scale) {
        int[] result=new int[image.length];for(int y=0;y<h;y++)for(int x=0;x<w;x++) {
            int xx=Math.max(0,Math.min(w-1,(int)Math.round((w-1)*.5+(x-(w-1)*.5)/scale)));
            int yy=Math.max(0,Math.min(h-1,(int)Math.round((h-1)*.5+(y-(h-1)*.5)/scale)));
            result[y*w+x]=image[yy*w+xx];
        }return result;
    }
    private static double error(int[] source,int[] target,RawJpegColorMatch.Fit fit) {
        double sum=0;for(int i=0;i<source.length;i++){int p=fit==null?source[i]:fit.applyArgb(source[i]);for(int shift:new int[]{16,8,0}){double delta=(((p>>>shift)&255)-((target[i]>>>shift)&255))/255.0;sum+=delta*delta;}}
        return Math.sqrt(sum/(source.length*3.0));
    }
    private static int channel(double value){return (int)Math.round(Math.max(0,Math.min(1,value))*255);}
    private interface Task{void run()throws Exception;}
    private static void invalid(Task task)throws Exception{boolean rejected=false;try{task.run();}catch(IllegalArgumentException expected){rejected=true;}check(rejected,"invalid analysis rejected");}
    private static void interrupted(Task task)throws Exception{boolean cancelled=false;try{task.run();}catch(InterruptedIOException expected){cancelled=true;}check(cancelled,"fit cancellation");}
    private static void check(boolean condition,String message){checks++;if(!condition)throw new AssertionError(message);}
}
