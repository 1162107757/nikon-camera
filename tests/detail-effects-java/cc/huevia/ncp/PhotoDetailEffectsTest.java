package cc.huevia.ncp;

import java.io.*;
import java.util.*;
import java.util.concurrent.atomic.AtomicBoolean;

/** Behavioural image properties, orientation equivalence, projective geometry and streaming limits. */
public final class PhotoDetailEffectsTest {
    static int checks;
    public static void main(String[] args)throws Exception{
        legacy();denoise();finish();orientation();geometry();cancellation();streaming();
        System.out.println("PASS photo detail effects: "+checks+" checks");
    }
    static void check(boolean value,String message){checks++;if(!value)throw new AssertionError(message);}
    static void legacy(){
        PhotoAdjustments old=new PhotoAdjustments(new int[13]);check(old.equals(PhotoAdjustments.NONE),"old parameter vector expands with zero defaults");
        check(old.identity().equals(PhotoAdjustments.MODEL+":0".repeat(13)),"old neutral identity retained");
        int[] v=new int[13];v[1]=13;PhotoAdjustments exposure=new PhotoAdjustments(v);check(exposure.identity().equals(PhotoAdjustments.MODEL+":0:13"+":0".repeat(11)),"old effect identity retained");
        check(!old.with(PhotoAdjustments.Parameter.GRAIN,1).identity().equals(old.identity()),"grain participates in identity");
        check(!old.with(PhotoAdjustments.Parameter.LUMA_DENOISE,1).isNeutral(),"noise participates in state");
        expectInvalid(()->new PhotoAdjustments(new int[14]));expectInvalid(()->new PhotoGeometry(0,0,0,0,1000000,1000000,101,0));
    }
    static void denoise()throws Exception{
        int w=192,h=128;Pixels p=new Pixels(w,h);Random random=new Random(48291);
        for(int i=0;i<p.data.length;i++){int n=random.nextInt(31)-15;p.data[i]=argb(255,128+n,128+n,128+n);}
        double before=variance(p.data,0,w,h,128);double meanBefore=mean(p.data);PhotoDetailEffects.denoise(p,100,0,null,null);
        double after=variance(p.data,0,w,h,128);check(after<before*.55,"flat luminance noise decreases: "+before+" -> "+after);check(Math.abs(mean(p.data)-meanBefore)<.35,"denoise luminance has no material bias");
        Pixels colour=new Pixels(w,h);random=new Random(9184);for(int i=0;i<colour.data.length;i++){int r=random.nextInt(31)-15,b=random.nextInt(31)-15;int g=(int)Math.round(-(54*r+19*b)/183.0);colour.data[i]=argb(255,128+r,128+g,128+b);}
        int[] original=colour.data.clone();double cb=chromaEnergy(colour.data);PhotoDetailEffects.denoise(colour,0,100,null,null);check(chromaEnergy(colour.data)<cb*.55,"colour speckles decrease");double lumaError=0;for(int i=0;i<original.length;i++)lumaError+=Math.abs(luma(original[i])-luma(colour.data[i]));check(lumaError/original.length<.55,"colour-only preserves luminance texture");
        Pixels edge=new Pixels(w,h);random=new Random(91231);for(int y=0;y<h;y++)for(int x=0;x<w;x++){int n=random.nextInt(25)-12,b=x<w/2?48:208;edge.data[y*w+x]=argb(255,b+n,b+n,b+n);}
        PhotoDetailEffects.denoise(edge,100,100,null,null);double left=0,right=0;for(int y=5;y<h-5;y++){left+=luma(edge.data[y*w+w/2-1]);right+=luma(edge.data[y*w+w/2]);}left/=h-10;right/=h-10;check(left<52&&right>204,"high contrast edge remains local: "+left+","+right);check(right-left>150,"edge contrast retained");
        Pixels alpha=new Pixels(7,5);Arrays.fill(alpha.data,0xff404040);alpha.data[17]=0x00ffffff;alpha.data[16]=0x71404040;PhotoDetailEffects.denoise(alpha,100,100,null,null);check(alpha.data[17]==0x00ffffff,"transparent RGB untouched");check(alpha.data[16]==0x71404040,"neighbour alpha excluded and original alpha retained");
        for(int[] size:new int[][]{{1,1},{1,7},{9,1}}){Pixels tiny=new Pixels(size[0],size[1]);Arrays.fill(tiny.data,0x87643219);PhotoDetailEffects.denoise(tiny,100,100,null,null);for(int v:tiny.data)check(v==0x87643219,"tiny uniform image invariant");}
    }
    static void finish()throws Exception{
        Pixels a=new Pixels(160,120);Arrays.fill(a.data,0x7f808080);Pixels b=a.copy();PhotoDetailEffects.finish(a,65,0,null,null);PhotoDetailEffects.finish(b,65,0,null,null);check(Arrays.equals(a.data,b.data),"grain deterministic");check(!Arrays.equals(a.data,new Pixels(160,120).data),"grain material effect");int changes=0;double sum=0;for(int p:a.data){check((p>>>24)==127,"finish preserves alpha");if((p&255)!=128)changes++;sum+=(p&255)-128;}check(changes>a.data.length*.75,"grain reaches image");check(Math.abs(sum/a.data.length)<.8,"grain mean remains neutral");
        Pixels v=new Pixels(101,101);Arrays.fill(v.data,0xff808080);PhotoDetailEffects.finish(v,0,100,null,null);check(v.data[50*101+50]==0xff808080,"vignette leaves centre");check((v.data[0]&255)<60,"vignette darkens corner");check(v.data[0]==v.data[100]&&v.data[0]==v.data[100*101]&&v.data[0]==v.data[v.data.length-1],"vignette symmetric");
        Pixels none=b.copy();int[] data=none.data.clone();PhotoDetailEffects.denoise(none,0,0,null,null);PhotoDetailEffects.finish(none,0,0,null,null);check(Arrays.equals(data,none.data)&&none.reads==0&&none.writes==0,"zero effects avoid pixel IO");
    }
    static void orientation()throws Exception{
        Pixels raw=new Pixels(41,29);Random rnd=new Random(7213);for(int i=0;i<raw.data.length;i++)raw.data[i]=0xff000000|rnd.nextInt(0x1000000);
        for(int exif=1;exif<=8;exif++){
            Pixels source=raw.copy();source.exif=exif;Pixels oriented=orient(raw,exif);PhotoDetailEffects.finish(source,70,60,null,null);PhotoDetailEffects.finish(oriented,70,60,null,null);check(Arrays.equals(orient(source,exif).data,oriented.data),"finish EXIF "+exif+" exact source-coordinate identity");
            source=raw.copy();source.exif=exif;oriented=orient(raw,exif);PhotoDetailEffects.denoise(source,75,80,null,null);PhotoDetailEffects.denoise(oriented,75,80,null,null);check(Arrays.equals(orient(source,exif).data,oriented.data),"denoise EXIF "+exif+" traversal independent");
        }
    }
    static Pixels orient(Pixels input,int exif){int w=input.width,h=input.height;Pixels out=new Pixels(exif>=5?h:w,exif>=5?w:h);for(int y=0;y<h;y++)for(int x=0;x<w;x++){int ox=x,oy=y;switch(exif){case 2:ox=w-1-x;break;case 3:ox=w-1-x;oy=h-1-y;break;case 4:oy=h-1-y;break;case 5:ox=y;oy=x;break;case 6:ox=h-1-y;oy=x;break;case 7:ox=h-1-y;oy=w-1-x;break;case 8:ox=y;oy=w-1-x;break;}out.data[oy*out.width+ox]=input.data[y*w+x];}return out;}
    static void geometry(){
        PhotoGeometry none=PhotoGeometry.NONE;check(none.identity().equals(PhotoGeometry.MODEL+":0:0:0:0:1000000:1000000"),"old geometry identity");
        PhotoGeometry perspective=new PhotoGeometry(0,0,0,0,1000000,1000000,80,-65);PhotoGeometry.Plan p=perspective.plan(401,303,1);check(p.g!=0&&p.h!=0,"perspective has non-affine denominator");
        double[] t0=p.map(0,0),t1=p.map(401,0),b0=p.map(0,303),b1=p.map(401,303);check(Math.abs((t1[0]-t0[0])-(b1[0]-b0[0]))>10,"perspective changes convergence");
        for(int exif=1;exif<=8;exif++)for(int turns=0;turns<4;turns++)for(int hp:new int[]{-100,0,100})for(int vp:new int[]{-100,0,100}){
            PhotoGeometry g=new PhotoGeometry(turns,137,80000,110000,910000,940000,hp,vp);PhotoGeometry.Plan plan=g.plan(401,303,exif);
            for(int iy=0;iy<=4;iy++)for(int ix=0;ix<=4;ix++){double x=ix*401/4.0,y=iy*303/4.0;double[] mapped=plan.map(x,y),back=plan.inverse(mapped[0],mapped[1]);check(Math.abs(x-back[0])<1e-8&&Math.abs(y-back[1])<1e-8,"homography inverse under EXIF/turn/crop");}
            PhotoGeometry.Plan full=g.fullFrame().plan(401,303,exif);for(double[] corner:new double[][]{{0,0},{full.width,0},{0,full.height},{full.width,full.height}}){double[] back=full.inverse(corner[0],corner[1]);check(back[0]>=-1e-8&&back[0]<=401+1e-8&&back[1]>=-1e-8&&back[1]<=303+1e-8,"projective fill has no empty corners");}
            check(g.straighten(0).horizontalPerspective==hp&&g.rotate().verticalPerspective==vp,"composition changes retain perspective");
        }
    }
    static void cancellation()throws Exception{
        Pixels p=new Pixels(96,80);Arrays.fill(p.data,0xff777777);AtomicBoolean cancelled=new AtomicBoolean();boolean stopped=false;try{PhotoDetailEffects.denoise(p,80,80,cancelled::get,v->{if(v>.25)cancelled.set(true);});}catch(InterruptedIOException expected){stopped=true;}check(stopped&&p.writes>0&&p.writes<p.height,"mid-frame cancellation stops writes");
        p=new Pixels(20,20);stopped=false;try{PhotoDetailEffects.finish(p,30,30,()->true,null);}catch(InterruptedIOException expected){stopped=true;}check(stopped&&p.reads==0,"pre-cancel avoids IO");
        Thread.currentThread().interrupt();stopped=false;try{PhotoDetailEffects.denoise(p,10,10,null,null);}catch(InterruptedIOException expected){stopped=true;}check(stopped&&Thread.currentThread().isInterrupted(),"interruption preserved");Thread.interrupted();
    }
    static void streaming()throws Exception{
        final int w=6000,h=4000;final int[] count={0,0};final double[] previous={-1};long start=System.nanoTime();
        SpatialPreviewFilter.Pixels stream=new SpatialPreviewFilter.Pixels(){public int width(){return w;}public int height(){return h;}public void read(int[] row,int first,int rows){check(rows==1&&first==count[0]++,"one increasing read per input row");for(int x=0;x<w;x++){int n=(x*23+first*71)%17-8;row[x]=argb(255,120+n,124-n/2,128+n/3);}}public void write(int[] row,int first,int rows){check(rows==1&&first==count[1]++,"one increasing write per output row");}};
        PhotoDetailEffects.denoise(stream,65,70,null,v->{check(v>=previous[0]&&v>=0&&v<=1,"monotone progress");previous[0]=v;});check(count[0]==h&&count[1]==h&&previous[0]==1,"24MP streaming completes in 64MiB heap");System.out.printf(Locale.ROOT,"24MP denoise streaming %.1f ms%n",(System.nanoTime()-start)/1e6);
    }
    static void expectInvalid(Runnable r){try{r.run();throw new AssertionError("expected invalid input");}catch(IllegalArgumentException good){checks++;}}
    static int argb(int a,int r,int g,int b){return a<<24|r<<16|g<<8|b;}
    static double luma(int p){return (54*((p>>>16)&255)+183*((p>>>8)&255)+19*(p&255))/256.0;}
    static double mean(int[] values){double sum=0;for(int p:values)sum+=luma(p);return sum/values.length;}
    static double variance(int[] values,int left,int w,int h,double expected){double sum=0;for(int p:values){double d=luma(p)-expected;sum+=d*d;}return sum/values.length;}
    static double chromaEnergy(int[] values){double sum=0;for(int p:values){double y=luma(p),r=((p>>>16)&255)-y,b=(p&255)-y;sum+=r*r+b*b;}return sum/values.length;}
    static final class Pixels implements SpatialPreviewFilter.Pixels {
        final int width,height;int exif=1,reads,writes;final int[] data;
        Pixels(int w,int h){width=w;height=h;data=new int[w*h];}
        public int width(){return width;}public int height(){return height;}public int exifOrientation(){return exif;}
        public void read(int[] dest,int first,int rows){reads++;System.arraycopy(data,first*width,dest,0,width*rows);}public void write(int[] source,int first,int rows){writes++;System.arraycopy(source,0,data,first*width,width*rows);}
        Pixels copy(){Pixels p=new Pixels(width,height);p.exif=exif;System.arraycopy(data,0,p.data,0,data.length);return p;}
    }
}
