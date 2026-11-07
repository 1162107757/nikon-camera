package cc.huevia.ncp;

import java.io.*;
import java.util.*;
import java.util.concurrent.atomic.AtomicInteger;
import cc.huevia.album.PhotoEditStore;

public final class SkinSmoothingTest {
    private static int checks;
    public static void main(String[] args)throws Exception {
        model();pixels();orientations();cancellation();large();
        System.out.println("PASS SkinSmoothingTest "+checks+" checks");
    }
    private static void check(boolean b,String label){checks++;if(!b)throw new AssertionError(label);}
    private static PhotoPortrait.BodySkinMask mask(boolean half){int n=PhotoPortrait.BodySkinMask.SIZE;byte[] b=new byte[n*n];for(int y=0;y<n;y++)for(int x=0;x<n;x++)if(!half||x<n/2)b[y*n+x]=(byte)255;return new PhotoPortrait.BodySkinMask(b);}
    private static byte[] wire(PhotoPortrait p)throws Exception{ByteArrayOutputStream b=new ByteArrayOutputStream();p.write(new DataOutputStream(b));return b.toByteArray();}
    private static PhotoPortrait read(byte[] b)throws Exception{return PhotoPortrait.read(new DataInputStream(new ByteArrayInputStream(b)));}
    private static void model()throws Exception {
        PhotoPortrait old=PhotoPortrait.NONE.withGlobalSkinMask(mask(false)),p=old.withSkinSmoothing(68);
        check(p.skinSmoothing==68&&!p.isNeutral()&&!p.isEmpty(),"global smoothing active without faces");
        check(p.identity().startsWith("portrait-v6:"),"new effect identity");check(read(wire(p)).equals(p),"portrait v6 roundtrip");
        check(Arrays.equals(wire(old),wire(p.withSkinSmoothing(0))),"zero restores old wire exactly");check(old.identity().equals(p.withSkinSmoothing(0).identity()),"zero restores old identity");
        check(p.withFaces(Collections.emptyList()).skinSmoothing==68&&p.withGlobalTone(PhotoPortrait.Tone.NONE).skinSmoothing==68&&p.withGlobalSkinMask(null).skinSmoothing==68&&p.withBodyShape(PhotoBodyShape.NONE).skinSmoothing==68,"mutations preserve independent smoothing");
        PhotoPortrait q=p.withBodyShape(new PhotoBodyShape(new PhotoBodyShape.Area(.2,.2,.8,.8,35),PhotoBodyShape.NONE.legs,PhotoBodyShape.NONE.length,false));check(read(wire(q)).equals(q),"body and smoothing coexist");
        byte[] broken=wire(p);Arrays.fill(broken,broken.length-4,broken.length,(byte)0xff);try{read(broken);throw new AssertionError("invalid strength accepted");}catch(IOException expected){checks++;}
        try{read(Arrays.copyOf(wire(p),wire(p).length-1));throw new AssertionError("truncated accepted");}catch(IOException expected){checks++;}
        PhotoLocalEdits edits=PhotoLocalEdits.NONE.withPortrait(p.withGlobalSkinMask(null));check(edits.hasStoredSkinSmoothingState(),"unprepared state retained");
        String sha="1234567890abcdef".repeat(4);PhotoEditStore.Draft d=new PhotoEditStore.Draft(sha,new byte[0],"test",0,PhotoAdjustments.NONE,PhotoGeometry.NONE,PhotoBorder.NONE,edits,false);check(d.identity().contains(edits.identity()),"draft identity retains unprepared state");
    }
    private static void pixels()throws Exception {
        int w=128,h=96;int[] base=new int[w*h];Arrays.fill(base,0xffb69a86);int middle=48*w+32;base[middle]=0xff987c68;
        int[] out=render(base,w,h,1,mask(true),100);check(luma(out[middle])>luma(base[middle])+17,"small dark blemish softened");
        for(int y=0;y<h;y++)for(int x=75;x<w;x++)check(out[y*w+x]==base[y*w+x],"outside skin exact");
        check(Arrays.equals(base,render(base,w,h,1,mask(true),0)),"zero exact");check(Arrays.equals(base,render(base,w,h,1,new PhotoPortrait.BodySkinMask(new byte[PhotoPortrait.BodySkinMask.SIZE*PhotoPortrait.BodySkinMask.SIZE]),100)),"empty mask exact");
        int[] grain=new int[w*h];for(int y=0;y<h;y++)for(int x=0;x<w;x++){int c=150+(((x+y)&1)==0?2:-2);grain[y*w+x]=0xff000000|(c<<16)|(c<<8)|c;}
        int[] smooth=render(grain,w,h,1,mask(false),100);check(Math.abs(luma(smooth[20*w+20])-luma(smooth[20*w+21]))>=2,"fine texture retained");
        int[] edge=new int[w*h];for(int y=0;y<h;y++)for(int x=0;x<w;x++)edge[y*w+x]=x<w/2?0xff252525:0xffd8d8d8;
        int[] protectedEdge=render(edge,w,h,1,mask(false),100);check(luma(protectedEdge[48*w+64])-luma(protectedEdge[48*w+63])>=170,"strong edge retained");
        base[middle]=0x80302010;base[middle+1]=0x00112233;out=render(base,w,h,1,mask(false),100);for(int i=0;i<base.length;i++)check((out[i]>>>24)==(base[i]>>>24),"alpha exact");check(out[middle+1]==base[middle+1],"transparent packed pixel exact");
    }
    private static int[] render(int[] source,int w,int h,int exif,PhotoPortrait.BodySkinMask mask,int amount)throws Exception{int[] p=source.clone();SkinSmoothingFilter.apply(new SpatialPreviewFilter.Pixels(){public int width(){return w;}public int height(){return h;}public void read(int[] b,int y,int n){System.arraycopy(p,y*w,b,0,n*w);}public void write(int[] b,int y,int n){System.arraycopy(b,0,p,y*w,n*w);}},mask,amount,exif,()->false,null);return p;}
    private static void orientations()throws Exception {
        int w=80,h=60;int[] base=new int[w*h];for(int y=0;y<h;y++)for(int x=0;x<w;x++){int c=130+((x*13+y*7)%7);if(x%17==0&&y%11==0)c-=24;base[y*w+x]=0xff000000|(c<<16)|(c<<8)|c;}
        int[] reference=render(base,w,h,1,mask(true),80);
        for(int exif=1;exif<=8;exif++){int rw=exif>=5?h:w,rh=exif>=5?w:h;int[] raw=new int[rw*rh];for(int y=0;y<rh;y++)for(int x=0;x<rw;x++){int ox=(int)(LocalEditsPreviewProfile.orientedX((x+.5)/rw,(y+.5)/rh,exif)*w),oy=(int)(LocalEditsPreviewProfile.orientedY((x+.5)/rw,(y+.5)/rh,exif)*h);raw[y*rw+x]=base[oy*w+ox];}int[] out=render(raw,rw,rh,exif,mask(true),80);for(int y=0;y<rh;y++)for(int x=0;x<rw;x++){int ox=(int)(LocalEditsPreviewProfile.orientedX((x+.5)/rw,(y+.5)/rh,exif)*w),oy=(int)(LocalEditsPreviewProfile.orientedY((x+.5)/rw,(y+.5)/rh,exif)*h);check(Math.abs((out[y*rw+x]&255)-(reference[oy*w+ox]&255))<=1,"EXIF "+exif);}}
    }
    private static void cancellation()throws Exception{AtomicInteger count=new AtomicInteger();try{SkinSmoothingFilter.apply(new SpatialPreviewFilter.Pixels(){public int width(){return 1200;}public int height(){return 800;}public void read(int[] p,int y,int n){Arrays.fill(p,0xffaa9988);}public void write(int[] p,int y,int n){}},mask(false),70,1,()->count.incrementAndGet()>30,null);throw new AssertionError("cancel ignored");}catch(InterruptedIOException expected){checks++;}}
    private static void large()throws Exception{int w=6000,h=4000;AtomicInteger rows=new AtomicInteger();long start=System.nanoTime();SkinSmoothingFilter.apply(new SpatialPreviewFilter.Pixels(){public int width(){return w;}public int height(){return h;}public void read(int[] p,int y,int n){Arrays.fill(p,0xffb69a86);}public void write(int[] p,int y,int n){check(p[100]==0xffb69a86,"flat colour unchanged");rows.addAndGet(n);}},mask(true),75,1,()->false,null);check(rows.get()==h,"all full 24MP rows processed under 96MiB heap");System.out.println("24MP virtual-source elapsedMs="+(System.nanoTime()-start)/1_000_000);}
    private static int luma(int v){return(((v>>>16)&255)+((v>>>8)&255)+(v&255))/3;}
}
