package cc.huevia.ncp;

import java.io.*;
import java.lang.management.ManagementFactory;
import java.nio.file.*;
import java.util.*;

/** Synthetic 24 MP source has no backing image: detects accidental full-frame heap allocation. */
public final class RegionBoundedMemoryProbe {
    public static void main(String[] args)throws Exception{
        Path directory=Files.createTempDirectory("region-memory-");
        try{
            AdjustmentRegion region=AdjustmentRegion.create("bounded").withAdjustments(PhotoAdjustments.NONE.with(PhotoAdjustments.Parameter.GRAIN,65)).addStroke(new PhotoPortrait.Stroke(new double[]{.5,.5},.001,0,false));
            com.sun.management.ThreadMXBean bean=(com.sun.management.ThreadMXBean)ManagementFactory.getThreadMXBean();long id=Thread.currentThread().getId(),before=bean.isThreadAllocatedMemorySupported()?bean.getThreadAllocatedBytes(id):-1;
            Source source=new Source(6000,4000,directory);long start=System.nanoTime();LocalEditsPreviewProfile.renderLocal(source,PhotoLocalEdits.NONE.addRegion(region),1,()->false,null);long elapsed=System.nanoTime()-start,allocated=before<0?-1:bean.getThreadAllocatedBytes(id)-before;
            if(source.maxRows!=1||source.changed<=0||source.changed>64||source.peakScratch!=96_000_000L||allocated>8L*1024*1024)throw new AssertionError("Unbounded branch or invalid write scope: "+source.changed+" changed, allocated="+allocated+", peakScratch="+source.peakScratch);
            try(var files=Files.list(directory)){if(files.findAny().isPresent())throw new AssertionError("Scratch survived successful 24 MP render");}
            System.out.println("{\"status\":\"passed\",\"syntheticPixels\":24000000,\"heapLimitMiB\":96,\"threadAllocatedBytes\":"+allocated+",\"maxTransferRows\":"+source.maxRows+",\"scratchBytes\":"+source.peakScratch+",\"changedPixels\":"+source.changed+",\"outsideMaskChangedPixels\":0,\"scratchFilesAfter\":0,\"elapsedMs\":"+String.format(Locale.ROOT,"%.3f",elapsed/1e6)+",\"scope\":\"Desktop JVM synthetic grain layer; not phone timing\"}");
        }finally{try(var files=Files.walk(directory)){for(Path p:files.sorted(Comparator.reverseOrder()).toList())Files.delete(p);}}
    }
    private static final class Source implements SpatialPreviewFilter.Pixels{
        final int width,height;final Path directory;int maxRows,changed;long peakScratch;
        Source(int width,int height,Path directory){this.width=width;this.height=height;this.directory=directory;}
        public int width(){return width;}public int height(){return height;}public File scratchDirectory(){return directory.toFile();}
        private int original(int x,int y){int value=105+((x*3+y*5)%45);return 0xff000000|(value<<16)|(value<<8)|value;}
        public void read(int[] row,int y,int rows){maxRows=Math.max(maxRows,rows);for(int k=0;k<rows;k++)for(int x=0;x<width;x++)row[k*width+x]=original(x,y+k);}
        public void write(int[] row,int y,int rows)throws IOException{
            maxRows=Math.max(maxRows,rows);if(y==0)try(var files=Files.list(directory)){for(Path p:files.toList())peakScratch=Math.max(peakScratch,Files.size(p));}
            for(int k=0;k<rows;k++)for(int x=0;x<width;x++)if(row[k*width+x]!=original(x,y+k)){double dx=x+.5-width*.5,dy=y+k+.5-height*.5;if(Math.hypot(dx,dy)>=.001*Math.min(width,height))throw new AssertionError("Write escaped brush");changed++;}
        }
    }
}
