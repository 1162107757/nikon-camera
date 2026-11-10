package cc.huevia.ncp;

import java.io.*;
import java.util.*;
import java.util.concurrent.atomic.AtomicInteger;

public final class PhotoPatchSamplerTest {
    private static int checks;
    public static void main(String[] args)throws Exception{
        for(int mode=0;mode<3;mode++)fixture(mode);
        edgeAndTransparency();failures();persistenceAndLargerGuide();
        System.out.println("PASS "+checks+" automatic donor/real-pixel/atomic-input checks");
    }
    private static void fixture(int mode)throws Exception{
        int w=128,h=96;int[] clean=new int[w*h];
        for(int y=0;y<h;y++)for(int x=0;x<w;x++){
            int v=mode==0?150:mode==1?90+x/4:100+(x%8<4?25:0);
            clean[y*w+x]=0xff000000|(v<<16)|((v+5)<<8)|(v+10);
        }
        int[] damaged=clean.clone();for(int y=44;y<=48;y++)for(int x=61;x<=65;x++)damaged[y*w+x]=0xff131020;
        AdjustmentRegion region=AdjustmentRegion.create("dot").addStroke(new PhotoPortrait.Stroke(new double[]{63.5/w,46.5/h},.075,.2,false));
        int[] unchanged=damaged.clone();PhotoPatch patch=PhotoPatchSampler.choose(damaged,w,h,region,null);
        check(Arrays.equals(damaged,unchanged),"search mutates no photo pixels");
        check(patch.equals(PhotoPatchSampler.choose(damaged,w,h,region,null)),"deterministic frozen donor");
        validDonor(damaged,w,h,patch);
        Memory out=new Memory(w,h,damaged.clone());PhotoPatchRenderer.apply(out,Collections.singletonList(patch),1,null,null);
        double error=0;int count=0;
        for(int y=44;y<=48;y++)for(int x=61;x<=65;x++)for(int c=0;c<3;c++){int shift=c*8;error+=Math.abs(((out.data[y*w+x]>>>shift)&255)-((clean[y*w+x]>>>shift)&255));count++;}
        check(error/count<3,"known small blemish restored with surrounding tone/texture: "+mode+" error="+error/count);
        AdjustmentRegion.Brush mask=region.compileBrush(w,h);
        for(int y=0;y<h;y++)for(int x=0;x<w;x++)if(mask.weight((x+.5)/w,(y+.5)/h)==0)check(out.data[y*w+x]==damaged[y*w+x],"exact exterior");
        check(patch.hasEffect(),"nonzero donor translation");
    }
    private static void edgeAndTransparency()throws Exception{
        int w=120,h=100;int[] p=new int[w*h];Arrays.fill(p,0xffa0a0a0);
        AdjustmentRegion r=AdjustmentRegion.create("edge").addStroke(new PhotoPortrait.Stroke(new double[]{.012,.3,.04,.4,.05,.6},.03,.25,false));
        PhotoPatch repair=PhotoPatchSampler.choose(p,w,h,r,null);validDonor(p,w,h,repair);check(repair.hasEffect(),"edge stroke gets safe donor");
        for(int y=0;y<h;y++)for(int x=0;x<w;x++)if(x>80)p[y*w+x]=0;
        repair=PhotoPatchSampler.choose(p,w,h,r,null);validDonor(p,w,h,repair);
    }
    private static void validDonor(int[] p,int w,int h,PhotoPatch patch){
        AdjustmentRegion.Brush b=patch.selection.compileBrush(w,h);int dx=(int)Math.round(patch.dx*w),dy=(int)Math.round(patch.dy*h);
        for(int y=0;y<h;y++)for(int x=0;x<w;x++)if(b.weight((x+.5)/w,(y+.5)/h)>.001){int xx=x+dx,yy=y+dy;check(xx>=0&&xx<w&&yy>=0&&yy<h,"donor in image");check(b.weight((xx+.5)/w,(yy+.5)/h)<=.001,"no donor from marked region");check((p[yy*w+xx]>>>24)>=(p[y*w+x]>>>24),"no transparent replacement");}
    }
    private static void failures()throws Exception{
        int[] p=new int[128*128];Arrays.fill(p,0xff888888);int[] original=p.clone();
        AdjustmentRegion r=AdjustmentRegion.create("stroke").addStroke(new PhotoPortrait.Stroke(new double[]{.4,.4,.6,.6},.03,.2,false));
        AtomicInteger calls=new AtomicInteger();try{PhotoPatchSampler.choose(p,128,128,r,()->calls.incrementAndGet()>5);throw new AssertionError("missing cancellation");}catch(InterruptedIOException expected){check(Arrays.equals(p,original),"cancel leaves input unchanged");}
        AdjustmentRegion whole=AdjustmentRegion.create("whole").addShape(new SelectionShape(SelectionShape.Kind.RECTANGLE,0,0,1,1,0,false,0));
        try{PhotoPatchSampler.choose(p,128,128,whole,null);throw new AssertionError("missing size failure");}catch(IOException expected){check(Arrays.equals(p,original),"failed selection leaves input unchanged");}
        Arrays.fill(p,0);try{PhotoPatchSampler.choose(p,128,128,r,null);throw new AssertionError("missing opacity failure");}catch(IOException expected){check(true,"transparent surroundings fail safely");}
    }
    private static void persistenceAndLargerGuide()throws Exception{
        int w=384,h=256;int[] pixels=new int[w*h];Arrays.fill(pixels,0xff908070);
        AdjustmentRegion r=AdjustmentRegion.create("long stroke").addStroke(new PhotoPortrait.Stroke(new double[]{.25,.35,.4,.4,.6,.55,.72,.56},.025,.2,false));
        long start=System.nanoTime();PhotoPatch patch=PhotoPatchSampler.choose(pixels,w,h,r,null);validDonor(pixels,w,h,patch);
        PhotoLocalEdits edits=PhotoLocalEdits.NONE.addPatch(patch);ByteArrayOutputStream bytes=new ByteArrayOutputStream();edits.write(new DataOutputStream(bytes));
        check(new DataInputStream(new ByteArrayInputStream(bytes.toByteArray())).readInt()==7,"existing v7 recipe, no schema fork");
        PhotoLocalEdits reopened=PhotoLocalEdits.read(new DataInputStream(new ByteArrayInputStream(bytes.toByteArray())));
        check(edits.equals(reopened)&&edits.identity().equals(reopened.identity()),"automatic source frozen across persistence");
        Memory before=new Memory(w,h,pixels.clone()),after=new Memory(w,h,pixels.clone());PhotoPatchRenderer.apply(before,edits.patches(),1,null,null);PhotoPatchRenderer.apply(after,reopened.patches(),1,null,null);
        check(Arrays.equals(before.data,after.data),"reopened donor renders byte-identically");
        System.out.println("384px guide search + existing renderer roundtrip ms="+(System.nanoTime()-start)/1_000_000);
    }
    private static void check(boolean pass,String message){checks++;if(!pass)throw new AssertionError(message);}
    private static final class Memory implements SpatialPreviewFilter.Pixels{
        final int w,h;final int[] data;Memory(int w,int h,int[] data){this.w=w;this.h=h;this.data=data;}
        public int width(){return w;}public int height(){return h;}
        public void read(int[] row,int y,int count){System.arraycopy(data,y*w,row,0,count*w);}
        public void write(int[] row,int y,int count){System.arraycopy(row,0,data,y*w,count*w);}
    }
}
