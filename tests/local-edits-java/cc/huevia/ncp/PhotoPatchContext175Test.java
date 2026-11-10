package cc.huevia.ncp;

import java.io.*;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.atomic.AtomicInteger;

/** Known clean-background oracle, separate legacy-wire and new-context contracts. */
public final class PhotoPatchContext175Test {
    private static int checks;
    public static void main(String[] args)throws Exception{
        File temp=Files.createTempDirectory("huevia-context175-").toFile();
        try{persistence();contextQuality(temp,args.length>0?new File(args[0]):null);bilinear(temp);transparentDonor(temp);softEdge(temp);cancel(temp);large(temp);check(temp.list().length==0,"scratch cleaned");
            System.out.println("PASS "+checks+" context-blend checks; v1/v7/v8 persistence, known blemish core/clean rim, EXIF1-8, alpha/exterior, bilinear sample and softer edge.");
        }finally{for(File f:Objects.requireNonNull(temp.listFiles()))Files.deleteIfExists(f.toPath());Files.delete(temp.toPath());}
    }
    private static AdjustmentRegion circle(double radius,double feather){return AdjustmentRegion.create("known blemish").addStroke(new PhotoPortrait.Stroke(new double[]{.25,.5},radius,feather,false));}
    private static void persistence()throws Exception{
        PhotoPatch legacy=PhotoPatch.create(circle(.16,.2)).sample(.5,0),enhanced=legacy.contextBlend(true).feather(.55);
        byte[] old=bytes(PhotoLocalEdits.NONE.addPatch(legacy));check(version(old)==7,"old patches keep v7");
        PhotoLocalEdits oldRead=read(old);check(!oldRead.patches().get(0).contextBlend,"v7 defaults legacy algorithm");check(Arrays.equals(old,bytes(oldRead)),"v7 wire unchanged on reload");
        PhotoLocalEdits mixed=PhotoLocalEdits.NONE.addPatch(legacy).addPatch(enhanced);byte[] wire=bytes(mixed);check(version(wire)==8,"new context patch opts into v8");
        PhotoLocalEdits reread=read(wire);check(mixed.equals(reread)&&mixed.identity().equals(reread.identity()),"mixed recipe roundtrip and cache identity");
        check(!reread.patches().get(0).contextBlend&&reread.patches().get(1).contextBlend,"per-patch legacy flag retained");
        check(!legacy.equals(enhanced)&&!PhotoLocalEdits.NONE.addPatch(legacy).identity().equals(PhotoLocalEdits.NONE.addPatch(enhanced).identity()),"new renderer never reuses old recipe identity");
        check(enhanced.sample(.2,.1).blend(.5).enabled(false).feather(.7).contextBlend,"all immutable operators retain blend mode");
        check(version(bytes(mixed.removePatch(1)))==7,"removing last new patch restores legacy format");check(version(bytes(PhotoLocalEdits.NONE))==1,"neutral stays v1");
        byte[] invalid=wire.clone();invalid[invalid.length-1]=2;try{read(invalid);throw new AssertionError("invalid flag accepted");}catch(IOException expected){checks++;}
    }
    private static void contextQuality(File temp,File out)throws Exception{
        int w=192,h=128;int[] clean=new int[w*h],damaged;
        for(int y=0;y<h;y++)for(int x=0;x<w;x++){
            double u=x<96?x:x-96,texture=((int)u+y)%6<3?2:-2;
            double r=142+u*.06+y*.025+texture,g=150+u*.04+y*.04+texture,b=155+u*.035-y*.015+texture;
            if(x>=96){r+=30+(u-48)*.25+(y-64)*.08;g+=-18+(u-48)*.12-(y-64)*.1;b+=23-(u-48)*.18+(y-64)*.06;}
            clean[y*w+x]=rgb(r,g,b);
        }
        damaged=clean.clone();for(int y=0;y<h;y++)for(int x=0;x<w;x++)if(Math.hypot(x+.5-48,y+.5-64)<11.5)damaged[y*w+x]=0xff30202a;
        PhotoPatch patch=PhotoPatch.create(circle(.1,.2)).sample(.5,0);
        PhotoPatch healing=PhotoPatch.create(AdjustmentRegion.create("soft exterior").addStroke(PhotoPatchSampler.automaticStroke(new double[]{.25,.5},.1))).sample(.5,0).contextBlend(true);
        Pixels old=new Pixels(damaged,w,h,1,temp),next=new Pixels(damaged,w,h,1,temp);
        PhotoPatchRenderer.apply(old,List.of(patch),1,null,null);PhotoPatchRenderer.apply(next,List.of(healing),1,null,null);
        double oldCore=error(old.canonical(),clean,w,h,0,7),newCore=error(next.canonical(),clean,w,h,0,7);
        double oldRim=error(old.canonical(),clean,w,h,11.5,12.8),newRim=error(next.canonical(),clean,w,h,11.5,12.8);
        System.out.println("Known core MAE legacy="+oldCore+" context="+newCore+"; clean rim MAE legacy="+oldRim+" context="+newRim);
        check(newCore<2&&newCore*3<oldCore,"clean exterior prevents blemish-colour feedback");check(newRim<1.5&&newRim<oldRim,"local gradient/context keeps clean feather rim");
        check(error(next.canonical(),clean,w,h,0,11.5)<2,"opaque painted core removes full blemish without a dark feather halo");
        check(error(next.canonical(),clean,w,h,13,20)<1.5,"soft exterior stays close to clean background");
        int[] reference=next.canonical();AdjustmentRegion.Brush mask=healing.selection.compileBrush(w,h);
        for(int e=1;e<=8;e++){
            Pixels p=new Pixels(damaged,w,h,e,temp);PhotoPatchRenderer.apply(p,List.of(healing),e,null,null);int[] actual=p.canonical();
            for(int y=0;y<h;y++)for(int x=0;x<w;x++){int i=y*w+x;check((actual[i]>>>24)==(damaged[i]>>>24),"alpha preserved");if(mask.weight((x+.5)/w,(y+.5)/h)==0)check(actual[i]==damaged[i],"mask exterior exact");for(int shift:new int[]{16,8,0})check(Math.abs(((actual[i]>>>shift)&255)-((reference[i]>>>shift)&255))<=1,"EXIF invariant context fit");}
        }
        if(out!=null){out.mkdirs();ppm(new File(out,"01-damaged.ppm"),damaged,w,h);ppm(new File(out,"02-legacy.ppm"),old.canonical(),w,h);ppm(new File(out,"03-context.ppm"),reference,w,h);ppm(new File(out,"04-known-clean.ppm"),clean,w,h);}
    }
    private static void bilinear(File temp)throws Exception{
        int w=80,h=60;int[] a=new int[w*h];for(int y=0;y<h;y++)for(int x=0;x<w;x++)a[y*w+x]=rgb(40+x*2,60+x,100+x);
        AdjustmentRegion r=AdjustmentRegion.create("fractional").addShape(new SelectionShape(SelectionShape.Kind.RECTANGLE,.1,.1,.4,.8,0,false,0));
        PhotoPatch p=PhotoPatch.create(r).sample(.5/w,0).blend(0).contextBlend(true);Pixels pixels=new Pixels(a,w,h,1,temp);PhotoPatchRenderer.apply(pixels,List.of(p),1,null,null);
        int x=20,y=30;for(int shift:new int[]{16,8,0}){double first=linear((a[y*w+x]>>>shift)&255),second=linear((a[y*w+x+1]>>>shift)&255);int expected=encode((first+second)*.5);check(((pixels.data[y*w+x]>>>shift)&255)==expected,"fractional source uses linear-light interpolation");}
    }

    private static void transparentDonor(File temp)throws Exception{
        int w=80,h=60;int[] a=new int[w*h];Arrays.fill(a,0x80646464);
        for(int y=0;y<h;y++){a[y*w+60]=0x800000c8;a[y*w+61]=0x0000ff00;}
        a[30*w+20]=0x00646464;
        AdjustmentRegion r=AdjustmentRegion.create("premultiplied donor").addShape(new SelectionShape(SelectionShape.Kind.RECTANGLE,.1,.1,.4,.8,0,false,0));
        PhotoPatch p=PhotoPatch.create(r).sample(40.5/w,0).blend(0).contextBlend(true);
        for(int e=1;e<=8;e++){Pixels pixels=new Pixels(a,w,h,e,temp);PhotoPatchRenderer.apply(pixels,List.of(p),e,null,null);int[] actual=pixels.canonical();
            check(actual[30*w+20]==a[30*w+20],"transparent target packed bytes unchanged");
            int value=actual[31*w+20];check((value>>>24)==128,"target partial alpha preserved");
            for(int shift:new int[]{16,8,0}){int donor=shift==0?200:0;int expected=encode(linear(100)+(linear(donor)-linear(100))*(64/255.0));check(((value>>>shift)&255)==expected,"transparent donor RGB ignored; alpha-weighted linear interpolation");}
        }
        Arrays.fill(a,0x80646464);for(int y=0;y<h;y++){a[y*w+60]=0x00ff0000;a[y*w+61]=0x0000ff00;}
        Pixels pixels=new Pixels(a,w,h,1,temp);PhotoPatchRenderer.apply(pixels,List.of(p),1,null,null);check(pixels.canonical()[31*w+20]==a[31*w+20],"fully transparent donor leaves target exact");
    }

    private static void softEdge(File temp)throws Exception{
        int w=160,h=100;int[] a=new int[w*h];for(int y=0;y<h;y++)for(int x=0;x<w;x++)a[y*w+x]=rgb(x<80?80:180,x<80?80:180,x<80?80:180);
        PhotoPatch p=PhotoPatch.create(circle(.2,.2)).sample(.5,0).blend(0).contextBlend(true);
        Pixels hard=new Pixels(a,w,h,1,temp),soft=new Pixels(a,w,h,1,temp);PhotoPatchRenderer.apply(hard,List.of(p),1,null,null);PhotoPatchRenderer.apply(soft,List.of(p.feather(.55)),1,null,null);
        int maxHard=0,maxSoft=0;for(int x=40;x<65;x++){maxHard=Math.max(maxHard,Math.abs((hard.data[50*w+x]&255)-(hard.data[50*w+x-1]&255)));maxSoft=Math.max(maxSoft,Math.abs((soft.data[50*w+x]&255)-(soft.data[50*w+x-1]&255)));}
        check(maxSoft<maxHard*.65,"wider feather reduces maximum seam step");
    }
    private static void cancel(File temp)throws Exception{
        int[] a=new int[192*128];Arrays.fill(a,0xff998877);Pixels p=new Pixels(a,192,128,1,temp);AtomicInteger checks=new AtomicInteger();
        try{PhotoPatchRenderer.apply(p,List.of(PhotoPatch.create(circle(.16,.55)).sample(.5,0).contextBlend(true)),1,()->checks.incrementAndGet()>40,null);throw new AssertionError("cancellation ignored");}catch(InterruptedIOException expected){PhotoPatchContext175Test.check(temp.list().length==0,"context cancel cleans scratch");}
    }
    private static void large(File temp)throws Exception{
        SpatialPreviewFilter.Pixels stream=new SpatialPreviewFilter.Pixels(){public int width(){return 6000;}public int height(){return 4000;}public File scratchDirectory(){return temp;}public void read(int[] row,int first,int count){for(int y=0;y<count;y++)for(int x=0;x<6000;x++)row[y*6000+x]=0xff887766;}public void write(int[] row,int first,int count){check(row.length<=6000&&count==1,"24MP context renderer writes bounded rows");}};
        AdjustmentRegion r=AdjustmentRegion.create("small context patch").addShape(new SelectionShape(SelectionShape.Kind.RECTANGLE,.1,.1,.12,.12,.35,false,0));
        LocalEditsPreviewProfile.renderLocal(stream,PhotoLocalEdits.NONE.addPatch(PhotoPatch.create(r).sample(.123456,.1).contextBlend(true)),1,null,null);
        check(temp.list().length==0,"24MP context scratch cleaned");
    }
    private static double error(int[] a,int[] expected,int w,int h,double min,double max){double sum=0,n=0;for(int y=0;y<h;y++)for(int x=0;x<w;x++){double d=Math.hypot(x+.5-48,y+.5-64);if(d<min||d>=max)continue;for(int shift:new int[]{16,8,0}){sum+=Math.abs(((a[y*w+x]>>>shift)&255)-((expected[y*w+x]>>>shift)&255));n++;}}return sum/n;}
    private static int rgb(double r,double g,double b){return 0xff000000|clamp(r)<<16|clamp(g)<<8|clamp(b);}private static int clamp(double v){return Math.max(0,Math.min(255,(int)Math.round(v)));}
    private static double linear(int v){double x=v/255.0;return x<=.04045?x/12.92:Math.pow((x+.055)/1.055,2.4);}private static int encode(double v){return clamp(255*(v<=.0031308?12.92*v:1.055*Math.pow(v,1/2.4)-.055));}
    private static byte[] bytes(PhotoLocalEdits e)throws Exception{ByteArrayOutputStream b=new ByteArrayOutputStream();e.write(new DataOutputStream(b));return b.toByteArray();}private static int version(byte[] b)throws Exception{return new DataInputStream(new ByteArrayInputStream(b)).readInt();}private static PhotoLocalEdits read(byte[] b)throws Exception{return PhotoLocalEdits.read(new DataInputStream(new ByteArrayInputStream(b)));}
    private static void ppm(File file,int[] a,int w,int h)throws Exception{try(OutputStream o=new FileOutputStream(file)){o.write(("P6\n"+w+" "+h+"\n255\n").getBytes("US-ASCII"));for(int p:a){o.write(p>>>16&255);o.write(p>>>8&255);o.write(p&255);}}}
    private static final class Pixels implements SpatialPreviewFilter.Pixels{
        final int w,h,ow,oh,e;final int[] data;final File temp;Pixels(int[] a,int ow,int oh,int e,File t){this.ow=ow;this.oh=oh;this.e=e;temp=t;w=e>=5?oh:ow;h=e>=5?ow:oh;data=new int[w*h];for(int y=0;y<oh;y++)for(int x=0;x<ow;x++)data[index(x,y)]=a[y*ow+x];}
        int index(int x,int y){switch(e){case 2:return y*w+w-1-x;case 3:return (h-1-y)*w+w-1-x;case 4:return (h-1-y)*w+x;case 5:return x*w+y;case 6:return (h-1-x)*w+y;case 7:return (h-1-x)*w+w-1-y;case 8:return x*w+w-1-y;default:return y*w+x;}}
        int[] canonical(){int[] r=new int[ow*oh];for(int y=0;y<oh;y++)for(int x=0;x<ow;x++)r[y*ow+x]=data[index(x,y)];return r;}
        public int width(){return w;}public int height(){return h;}public File scratchDirectory(){return temp;}public void read(int[] r,int y,int n){System.arraycopy(data,y*w,r,0,n*w);}public void write(int[] r,int y,int n){System.arraycopy(r,0,data,y*w,n*w);}
    }
    private static void check(boolean ok,String label){checks++;if(!ok)throw new AssertionError(label);}
}
