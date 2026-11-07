package cc.huevia.ncp;

import cc.huevia.album.*;
import java.io.*;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.atomic.AtomicInteger;

/** Numerical geometry, EXIF equivalence, unchanged legacy state and real draft persistence. */
public final class PhotoBodyShapeTest {
    private static long checks;
    private static File scratch;
    public static void main(String[] args)throws Exception{
        scratch=Files.createTempDirectory("huevia-body-test-").toFile();
        try{state();geometry();pixels();failure();large();System.out.println("PhotoBodyShapeTest PASS checks="+checks);}finally{check(scratch.list().length==0,"all scratch files removed");Files.delete(scratch.toPath());}
    }
    private static PhotoBodyShape active(){return PhotoBodyShape.NONE.withArea(0,PhotoBodyShape.NONE.body.withAmount(70)).withArea(1,PhotoBodyShape.NONE.legs.withAmount(80)).withArea(2,PhotoBodyShape.NONE.length.withAmount(90));}
    private static byte[] bytes(PhotoPortrait p)throws Exception{ByteArrayOutputStream b=new ByteArrayOutputStream();p.write(new DataOutputStream(b));return b.toByteArray();}
    private static PhotoPortrait decode(byte[] b)throws Exception{return PhotoPortrait.read(new DataInputStream(new ByteArrayInputStream(b)));}
    private static void state()throws Exception{
        check(new PhotoBodyShape.Area(-0.0,-0.0,1,1,0).hashCode()==new PhotoBodyShape.Area(0,0,1,1,0).hashCode(),"signed zero canonical hash");
        PhotoBodyShape s=active();PhotoPortrait p=PhotoPortrait.NONE.withBodyShape(s);check(!p.isNeutral()&&!p.isEmpty(),"shape-only portrait active");check(decode(bytes(p)).equals(p),"v5 round trip");check(new DataInputStream(new ByteArrayInputStream(bytes(p))).readInt()==0x50525431,"portrait magic");check(bytes(p)[7]==5&&bytes(PhotoPortrait.NONE)[7]==4,"v5 only with stored shape");
        PhotoBodyShape zero=s.withArea(0,s.body.withAmount(0)).withArea(1,s.legs.withAmount(0)).withArea(2,s.length.withAmount(0));check(zero.isNeutral(),"zero amount neutral");
        PhotoBodyShape positioned=zero.withArea(0,new PhotoBodyShape.Area(.1,.2,.8,.9,0));PhotoPortrait emptyPosition=PhotoPortrait.NONE.withBodyShape(positioned);check(emptyPosition.isNeutral()&&!emptyPosition.isEmpty(),"positioned zero retains state");check(decode(bytes(emptyPosition)).equals(emptyPosition),"zero shape round trip");
        check(p.withFaces(List.of()).bodyShape.equals(s)&&p.withGlobalTone(PhotoPortrait.Tone.NONE).bodyShape.equals(s)&&p.withGlobalSkinMask(null).bodyShape.equals(s),"colour mutations retain shape");
        PhotoPortrait.Heal h=new PhotoPortrait.Heal(.2,.2,.5,.5,.01,.4,true);check(p.addHeal(h).removeHeal(0).equals(p),"heal mutations retain shape");
        byte[] encoded=bytes(p);for(int i=0;i<encoded.length;i++){byte[] cut=Arrays.copyOf(encoded,i);expectIo(()->decode(cut));}byte[] bad=encoded.clone();bad[bad.length-1]=2;expectIo(()->decode(bad));
        expectIllegal(()->new PhotoBodyShape.Area(Double.NaN,0,.9,.9,20));expectIllegal(()->new PhotoBodyShape.Area(0,0,1,1,101));expectIllegal(()->new PhotoBodyShape.Area(.8,0,.7,1,0));expectIllegal(()->PhotoBodyShape.NONE.withArea(3,PhotoBodyShape.NONE.body));
        File files=new File(scratch,"drafts");files.mkdir();String sha="a".repeat(64);PhotoEditStore store=new PhotoEditStore(files,"body128");
        PhotoEditStore.Draft draft=new PhotoEditStore.Draft(sha,null,"",0,PhotoAdjustments.NONE,PhotoGeometry.NONE,PhotoBorder.NONE,PhotoLocalEdits.NONE.withPortrait(p),false);
        store.save(draft);PhotoEditStore.Draft read=store.read(sha);check(read.localEdits.portrait.equals(p)&&read.identity().equals(draft.identity()),"actual draft restores shape");
        PhotoEditStore.Draft neutral=new PhotoEditStore.Draft(sha,null,"",0,false),z=new PhotoEditStore.Draft(sha,null,"",0,PhotoAdjustments.NONE,PhotoGeometry.NONE,PhotoBorder.NONE,PhotoLocalEdits.NONE.withPortrait(emptyPosition),false);check(!z.identity().equals(neutral.identity()),"zero shape position distinct draft identity");store.save(z);check(store.read(sha).localEdits.portrait.equals(emptyPosition),"actual zero-position draft restored");
        // Delete only the owned tree, deepest first; no user files are present.
        try(java.util.stream.Stream<Path> paths=Files.walk(files.toPath())){for(Path f:(Iterable<Path>)paths.sorted(Comparator.reverseOrder())::iterator)Files.delete(f);}
    }
    private static void geometry(){
        double[] q=new double[2];PhotoBodyShape s=active();
        for(int tool=0;tool<3;tool++)for(int amount:new int[]{0,25,100}){
            PhotoBodyShape only=PhotoBodyShape.NONE.withArea(tool,PhotoBodyShape.NONE.area(tool).withAmount(amount));
            for(int y=0;y<=200;y++)for(int x=0;x<=200;x++){double nx=x/200.0,ny=y/200.0;PhotoBodyWarp.source(only,nx,ny,q);check(Double.isFinite(q[0])&&Double.isFinite(q[1])&&q[0]>=0&&q[0]<=1&&q[1]>=0&&q[1]<=1,"source within image");if(x==0||x==200||y==0||y==200||amount==0)check(q[0]==nx&&q[1]==ny,"fixed edges and zero exact");}
        }
        for(double x:new double[]{.02,.25,.375,.5,.625,.75,.98}){double previous=-1;for(int y=0;y<=2000;y++){PhotoBodyWarp.source(s,x,y/2000.0,q);check(q[1]>previous,"vertical mapping no fold");previous=q[1];}}
        for(double y:new double[]{.1,.3,.5,.7,.9}){double previous=-1;for(int x=0;x<=2000;x++){PhotoBodyWarp.source(s,x/2000.0,y,q);check(q[0]>previous,"horizontal mapping no fold");previous=q[0];}}
        PhotoBodyWarp.source(PhotoBodyShape.NONE.withArea(0,PhotoBodyShape.NONE.body.withAmount(100)),.6,.575,q);check(q[0]>.6&&q[1]==.575,"body inverse pulls sides inward");
        PhotoBodyShape legs=PhotoBodyShape.NONE.withArea(1,PhotoBodyShape.NONE.legs.withAmount(100));PhotoBodyWarp.source(legs,.37,.72,q);check(q[0]<.37,"left leg outer edge contracts");PhotoBodyWarp.source(legs,.63,.72,q);check(q[0]>.63,"right leg outer edge contracts");PhotoBodyWarp.source(legs,.5,.72,q);check(q[0]==.5,"double-leg gap is fixed");
        PhotoBodyShape length=PhotoBodyShape.NONE.withArea(2,PhotoBodyShape.NONE.length.withAmount(100));PhotoBodyWarp.source(length,.5,.3,q);check(q[1]==.3,"upper body fixed in lengthening");PhotoBodyWarp.source(length,.5,.90,q);check(q[1]<.90,"lower leg pulled downward");
    }
    private static void pixels()throws Exception{
        int w=96,h=128;Memory raw=new Memory(w,h);for(int y=0;y<h;y++)for(int x=0;x<w;x++)raw.a[y*w+x]=((x+y)%7==0?0:255)<<24|(x*2)<<16|(y*2)<<8|(x+y);int[] input=raw.a.clone();
        PhotoBodyWarp.apply(raw,PhotoBodyShape.NONE,1,null,null);check(Arrays.equals(input,raw.a),"neutral image exact");
        PhotoBodyShape s=active();PhotoBodyWarp.apply(raw,s,1,null,null);int changed=0,outside=0;double[] q=new double[2];for(int y=0;y<h;y++)for(int x=0;x<w;x++){int i=y*w+x;PhotoBodyWarp.source(s,(x+.5)/w,(y+.5)/h,q);if(q[0]==(x+.5)/w&&q[1]==(y+.5)/h){check(raw.a[i]==input[i],"outside support packed ARGB exact");outside++;}if(raw.a[i]!=input[i])changed++;}check(changed>100&&outside>100,"real deformation and outside support");
        for(int exif=2;exif<=8;exif++){int rw=exif>=5?h:w,rh=exif>=5?w:h;Memory orientedRaw=new Memory(rw,rh);for(int y=0;y<rh;y++)for(int x=0;x<rw;x++){int ox=(int)(LocalEditsPreviewProfile.orientedX((x+.5)/rw,(y+.5)/rh,exif)*w),oy=(int)(LocalEditsPreviewProfile.orientedY((x+.5)/rw,(y+.5)/rh,exif)*h);orientedRaw.a[y*rw+x]=input[oy*w+ox];}PhotoBodyWarp.apply(orientedRaw,s,exif,null,null);int max=0;for(int y=0;y<rh;y++)for(int x=0;x<rw;x++){int ox=(int)(LocalEditsPreviewProfile.orientedX((x+.5)/rw,(y+.5)/rh,exif)*w),oy=(int)(LocalEditsPreviewProfile.orientedY((x+.5)/rw,(y+.5)/rh,exif)*h);int a=orientedRaw.a[y*rw+x],b=raw.a[oy*w+ox];for(int shift:new int[]{0,8,16,24})max=Math.max(max,Math.abs(((a>>>shift)&255)-((b>>>shift)&255)));}check(max<=1,"EXIF"+exif+" equivalence max="+max);}
        PhotoPortrait shape=PhotoPortrait.NONE.withBodyShape(s);Memory through=new Memory(w,h);through.a=input.clone();LocalEditsPreviewProfile.renderLocal(through,PhotoLocalEdits.NONE.withPortrait(shape),1,null,null);check(Arrays.equals(through.a,raw.a),"main preview/export local pipeline applies shape");
        Memory expected=new Memory(w,h),combined=new Memory(w,h);expected.a=input.clone();combined.a=input.clone();PhotoLocalEdits.Mask mask=PhotoLocalEdits.Mask.radial(.5,.6).parameters(10,4,0);PhotoLocalEdits local=PhotoLocalEdits.NONE.add(mask);LocalEditsPreviewProfile.renderLocal(expected,local,1,null,null);PhotoBodyWarp.apply(expected,s,1,null,null);LocalEditsPreviewProfile.renderLocal(combined,local.withPortrait(shape),1,null,null);check(Arrays.equals(expected.a,combined.a),"source masks run before body deformation");
        System.out.println("Body pixels changed="+changed+" outsideExact="+outside+" EXIF=1..8");
    }
    private static void failure()throws Exception{
        for(int limit:new int[]{0,40,130}){AtomicInteger ticks=new AtomicInteger();Memory m=new Memory(96,128);expectIo(()->PhotoBodyWarp.apply(m,active(),1,()->ticks.incrementAndGet()>limit,null));check(scratch.list().length==0,"cancel cleans scratch");}
        Memory failed=new Memory(96,128){@Override public void write(int[] a,int y,int n)throws IOException{throw new IOException("injected write");}};expectIo(()->PhotoBodyWarp.apply(failed,active(),1,null,null));check(scratch.list().length==0,"write failure cleans scratch");
    }
    private static void large()throws Exception{
        AtomicInteger writes=new AtomicInteger();long started=System.nanoTime();SpatialPreviewFilter.Pixels virtual=new SpatialPreviewFilter.Pixels(){public int width(){return 6000;}public int height(){return 4000;}public File scratchDirectory(){return scratch;}public void read(int[] a,int y,int rows){for(int x=0;x<6000;x++)a[x]=0xff000000|((x*193/6000)<<16)|((y*211/4000)<<8)|((x+y)%256);}public void write(int[] a,int y,int rows){writes.addAndGet(rows);}};
        PhotoBodyWarp.apply(virtual,active(),1,null,null);check(writes.get()==4000,"24MP complete output rows");check(scratch.list().length==0,"24MP scratch removed");System.out.println("24MP full render rows="+writes+" elapsedMs="+(System.nanoTime()-started)/1000000+" maxHeap="+Runtime.getRuntime().maxMemory());
    }
    private static class Memory implements SpatialPreviewFilter.Pixels {final int w,h;int[] a;Memory(int w,int h){this.w=w;this.h=h;a=new int[w*h];}public int width(){return w;}public int height(){return h;}public File scratchDirectory(){return scratch;}public void read(int[] out,int row,int rows){System.arraycopy(a,row*w,out,0,rows*w);}public void write(int[] in,int row,int rows)throws IOException{System.arraycopy(in,0,a,row*w,rows*w);}}
    private interface Work{void run()throws Exception;}
    private static void expectIo(Work w)throws Exception{try{w.run();throw new AssertionError("missing IO rejection");}catch(IOException expected){checks++;}}
    private static void expectIllegal(Work w)throws Exception{try{w.run();throw new AssertionError("missing invalid-input rejection");}catch(IllegalArgumentException expected){checks++;}}
    private static void check(boolean ok,String label){checks++;if(!ok)throw new AssertionError(label);}
}
