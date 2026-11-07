package cc.huevia.ncp;
import java.io.*;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.atomic.AtomicInteger;

/** 24 MP processing with virtual source rows, never a 24 MP Java array. Run with -Xmx96m. */
public final class PhotoCleanupBoundedTest {
    public static void main(String[] args)throws Exception{
        PhotoCleanup.Analysis analysis=new PhotoCleanup.Analysis(6000,4000,1,4096,2048,75,100,30,230,237,245,40,45);
        Virtual haze=new Virtual(null);long start=System.nanoTime();PhotoCleanupRenderer.apply(haze,new PhotoCleanup(100,100,0,analysis),null,null);haze.finished();
        Virtual noise=new Virtual(null);PhotoCleanupRenderer.apply(noise,new PhotoCleanup(100,0,100,analysis),null,null);noise.finished();
        Path dir=Files.createTempDirectory("cleanup-24mp-");try{Virtual branch=new Virtual(dir.toFile());PhotoCleanup combined=new PhotoCleanup(100,100,100,analysis);AdjustmentRegion region=new AdjustmentRegion("large","区域",true,1,List.of(new PhotoPortrait.Stroke(new double[]{.5,.5},.8,.4,false)),PhotoAdjustments.NONE.withCleanup(combined),PhotoPortrait.NONE,PhotoPortrait.Settings.NONE,null);AtomicInteger checks=new AtomicInteger();try{AdjustmentRegionRenderer.apply(branch,List.of(region),1,()->checks.incrementAndGet()>35,null);throw new AssertionError("not cancelled");}catch(InterruptedIOException expected){}try(var files=Files.list(dir)){if(files.findAny().isPresent())throw new AssertionError("scratch leaked");}}finally{try(var files=Files.walk(dir)){for(Path p:files.sorted(Comparator.reverseOrder()).toArray(Path[]::new))Files.delete(p);}}
        System.out.println("PhotoCleanupBoundedTest PASS hazePixels="+haze.written+" noisePixels="+noise.written+" changedHaze="+haze.changed+" changedNoise="+noise.changed+" heapLimitBytes="+Runtime.getRuntime().maxMemory()+" maxObservedHeapBytes="+Math.max(haze.heap,noise.heap)+" cancelledScratchClean=true elapsedMs="+(System.nanoTime()-start)/1000000);
    }
    private static final class Virtual implements SpatialPreviewFilter.Pixels {
        final File scratch;int last=-1;long written,changed,heap;Virtual(File scratch){this.scratch=scratch;}public int width(){return 6000;}public int height(){return 4000;}public File scratchDirectory(){return scratch;}
        public void read(int[] out,int row,int rows){if(row<=last)throw new AssertionError("reread already overwritten original");for(int y=0;y<rows;y++)for(int x=0;x<6000;x++)out[y*6000+x]=pixel(x,row+y);}
        public void write(int[] in,int row,int rows){if(row!=last+1)throw new AssertionError("nonsequential output");for(int y=0;y<rows;y++)for(int x=0;x<6000;x++){int original=pixel(x,row+y),changedPixel=in[y*6000+x];if((original>>>24)!=(changedPixel>>>24)||original>>>24==0&&original!=changedPixel)throw new AssertionError("alpha/hidden RGB changed");if(original!=changedPixel)changed++;}last=row+rows-1;written+=(long)rows*6000;if((row&127)==0)heap=Math.max(heap,Runtime.getRuntime().totalMemory()-Runtime.getRuntime().freeMemory());}
        void finished(){if(written!=24000000||changed==0)throw new AssertionError("incomplete/no effect");}
        private static int pixel(int x,int y){int hash=(x*73856093)^(y*19349663),v=100+((hash>>>8)&31);return (hash%31==0?0:0xff000000)|(v+8)<<16|v<<8|(v+3);}
    }
}
