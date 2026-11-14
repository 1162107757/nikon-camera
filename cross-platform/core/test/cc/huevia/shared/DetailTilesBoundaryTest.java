package cc.huevia.shared;

import cc.huevia.album.PhotoEditStore;
import cc.huevia.library.SharedJson;
import java.io.*;
import java.nio.file.*;
import java.util.Comparator;
import java.util.Collections;
import java.util.Map;

/** Real-file capability and upright ROI contracts, independently runnable. */
public final class DetailTilesBoundaryTest {
    private static int checks;
    private interface Action{void run()throws Exception;}
    private static void yes(boolean value){checks++;if(!value)throw new AssertionError("Detail boundary "+checks);}
    private static void rejects(Action action)throws Exception{checks++;try{action.run();}catch(IOException expected){return;}throw new AssertionError("Unsafe detail request accepted: "+checks);}
    public static void main(String[] args)throws Exception{
        Path temporary=Files.createTempDirectory("huevia-detail-tiles-");
        try{
            File root=temporary.resolve("private").toFile(),previews=new File(root,"previews");previews.mkdirs();
            File original=new File(root,"original.jpg"),full=new File(previews,"full.jpg"),other=new File(previews,"other.jpg");
            Files.write(original.toPath(),new byte[]{1,2,3});Files.write(full.toPath(),new byte[]{4,5,6});Files.write(other.toPath(),new byte[]{4,5,6});
            String sha=PhotoEditStore.hashFile(original);SharedDetailTiles tiles=new SharedDetailTiles(root);
            String token=tiles.remember(original.getPath(),"a",sha,full.getPath(),6000,4000,()->false);
            SharedDetailTiles.Entry entry=tiles.checked(token,"a",full.getPath(),sha,()->false);
            yes(entry.width==6000&&entry.height==4000&&entry.sourcePath.equals(original.getCanonicalPath()));
            rejects(()->tiles.checked(token,"b",full.getPath(),sha,()->false));
            rejects(()->tiles.checked(token,"a",other.getPath(),sha,()->false));
            rejects(()->tiles.checked("unknown","a",full.getPath(),sha,()->false));
            rejects(()->tiles.checked(token,"a",full.getPath(),String.join("",Collections.nCopies(64,"0")),()->false));
            rejects(()->tiles.checked(token,"a",full.getPath(),sha,()->true));
            Files.write(original.toPath(),new byte[]{9,2,3});rejects(()->tiles.verify(entry,()->false));Files.write(original.toPath(),new byte[]{1,2,3});
            Files.write(full.toPath(),new byte[]{9,5,6});rejects(()->tiles.verify(entry,()->false));Files.write(full.toPath(),new byte[]{4,5,6});
            rejects(()->tiles.remember(original.getPath(),"a",sha,original.getPath(),2,2,()->false));
            File outside=temporary.resolve("outside.jpg").toFile();Files.write(outside.toPath(),new byte[]{4,5,6});
            rejects(()->tiles.remember(original.getPath(),"a",sha,outside.getPath(),2,2,()->false));
            // A new capability cannot silently rebind a path or resurrect eviction.
            for(int i=0;i<32;i++)tiles.remember(original.getPath(),"a",sha,full.getPath(),6000,4000,()->false);
            rejects(()->tiles.checked(token,"a",full.getPath(),sha,()->false));
            SharedDetailTiles sessions=new SharedDetailTiles(root);
            String active=sessions.remember(original.getPath(),"a",sha,full.getPath(),6000,4000,()->false),deleted="";
            for(int i=0;i<40;i++){
                File child=new File(previews,"tool-"+i+".jpg");Files.write(child.toPath(),new byte[]{7,8,9});
                deleted=sessions.remember(original.getPath(),"a",sha,child.getPath(),6000,4000,()->false);Files.delete(child.toPath());
            }
            yes(sessions.checked(active,"a",full.getPath(),sha,()->false).token.equals(active));
            String deletedToken=deleted;
            rejects(()->sessions.checked(deletedToken,"a",new File(previews,"tool-39.jpg").getPath(),sha,()->false));
            SharedDetailTiles.Plan rotated=new SharedDetailTiles.Plan(4000,3000,6,.1,.2,.4,.6,2048);
            yes(rotated.sourceWidth==3000&&rotated.sourceHeight==4000);
            yes(rotated.rawLeft==800&&rotated.rawTop==1800&&rotated.rawRight==2400&&rotated.rawBottom==2700);
            SharedDetailTiles.Plan pixel=new SharedDetailTiles.Plan(8000,6000,1,.50001,.50001,.50002,.50002,2048);
            yes(pixel.right-pixel.left==1&&pixel.bottom-pixel.top==1&&pixel.width==1&&pixel.height==1);
            for(int orientation=1;orientation<=8;orientation++){
                SharedDetailTiles.Plan plan=new SharedDetailTiles.Plan(8000,6000,orientation,0,0,1,1,2048);
                yes(plan.width<=2048&&plan.height<=2048&&(long)plan.width*plan.height<=4_194_304&&plan.sampleSize==4);
                yes(plan.rawLeft==0&&plan.rawTop==0&&plan.rawRight==8000&&plan.rawBottom==6000);
            }
            rejects(()->new SharedDetailTiles.Plan(8000,6000,1,Double.NaN,0,1,1,2048));
            rejects(()->new SharedDetailTiles.Plan(8000,6000,1,0,0,1.01,1,2048));
            rejects(()->new SharedDetailTiles.Plan(8000,6000,1,.5,0,.5,1,2048));
            rejects(()->new SharedDetailTiles.Plan(8000,6000,1,0,0,1,1,4096));
            Map<String,Object> dto=SharedJson.object("{\"region\":{\"left\":0.25,\"top\":0.25,\"right\":0.5,\"bottom\":0.5},\"maxEdge\":512}");
            Map<String,Object> region=SharedRuntime.object(dto.get("region"));
            SharedDetailTiles.Plan undefinedExif=new SharedDetailTiles.Plan(1600,1200,SharedDetailTiles.normalizedOrientation(0),((Number)region.get("left")).doubleValue(),((Number)region.get("top")).doubleValue(),((Number)region.get("right")).doubleValue(),((Number)region.get("bottom")).doubleValue(),SharedRuntime.integer(dto,"maxEdge",1536));
            yes(undefinedExif.left==400&&undefinedExif.top==300&&undefinedExif.width==400&&undefinedExif.height==300&&undefinedExif.sourceWidth==1600&&undefinedExif.sourceHeight==1200);
            boolean normalized=SharedDetailTiles.normalizedOrientation(0)==1&&SharedDetailTiles.normalizedOrientation(-1)==1&&SharedDetailTiles.normalizedOrientation(9)==1;for(int o=1;o<=8;o++)normalized&=SharedDetailTiles.normalizedOrientation(o)==o;yes(normalized);
            rejects(()->new SharedDetailTiles.Plan(1600,1200,0,.25,.25,.5,.5,512));
            System.out.println("PASS "+checks+" detail tile boundaries; real SHA/owner/path/cancel/eviction and 8 EXIF ROI budgets");
        }finally{try(java.util.stream.Stream<Path> paths=Files.walk(temporary)){for(Path p:(Iterable<Path>)paths.sorted(Comparator.reverseOrder())::iterator)Files.deleteIfExists(p);}}
    }
}
