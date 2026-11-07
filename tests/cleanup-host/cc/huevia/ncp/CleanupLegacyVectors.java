package cc.huevia.ncp;
import cc.huevia.album.PhotoEditStore;
import java.io.*;
import java.nio.file.*;
import java.security.MessageDigest;
import java.util.*;
/** Synthetic pre-cleanup baseline, including active and zero-intensity palette state. */
public final class CleanupLegacyVectors {
    public static void main(String[] args)throws Exception{
        MessageDigest digest=MessageDigest.getInstance("SHA-256");int count=0;
        PhotoAdjustments mixed=PhotoAdjustments.NONE.with(PhotoAdjustments.Parameter.CONTRAST,21).with(PhotoAdjustments.Parameter.TEMPERATURE,-18).withHsl(PhotoHsl.NONE.with(2,1,25)).withCurves(PhotoCurves.NONE.withPoints(0,new int[]{0,0,128,141,255,255}));
        Path dir=Files.createTempDirectory("cleanup-legacy-");try{PhotoEditStore store=new PhotoEditStore(dir.toFile(),"old");int index=0;
            for(PhotoAdjustments settings:new PhotoAdjustments[]{PhotoAdjustments.NONE,mixed,mixed.withPalette(new PhotoColorPalette(71,-38,69)),PhotoAdjustments.NONE.withPalette(new PhotoColorPalette(-57,32,0))}){
                PresetPreviewProfile profile=AdjustedPreviewProfile.of(null,settings);for(int i=0;i<16384;i++){int v=profile.applyArgb(Integer.rotateLeft(i*0x9e3779b9,13)^0x215894ab);for(int shift=24;shift>=0;shift-=8)digest.update((byte)(v>>>shift));count++;}
                AdjustmentRegion region=new AdjustmentRegion("legacy","区域",true,.6,List.of(new PhotoPortrait.Stroke(new double[]{.2,.3,.5,.6},.1,.5,false)),settings,PhotoPortrait.NONE,PhotoPortrait.Settings.NONE,null);
                PhotoLocalEdits local=new PhotoLocalEdits(List.of(),List.of(),PhotoPortrait.NONE,List.of(region));ByteArrayOutputStream bytes=new ByteArrayOutputStream();local.write(new DataOutputStream(bytes));System.out.println("local"+index+"="+hash(bytes.toByteArray()));
                String sha=Integer.toString(index+1).repeat(64);PhotoEditStore.Draft draft=new PhotoEditStore.Draft(sha,null,"",0,settings,PhotoGeometry.NONE,PhotoBorder.NONE,local,false);store.save(draft);try(var paths=Files.walk(dir)){Path file=paths.filter(p->p.getFileName().toString().equals(sha+".draft")).findFirst().orElseThrow();System.out.println("draft"+index+"="+hash(Files.readAllBytes(file)));}System.out.println("identity"+index+"="+hash(draft.identity().getBytes(java.nio.charset.StandardCharsets.UTF_8)));index++;
            }System.out.println("pixels="+HexFormat.of().formatHex(digest.digest())+" count="+count);
        }finally{try(var paths=Files.walk(dir)){for(Path p:paths.sorted(Comparator.reverseOrder()).toArray(Path[]::new))Files.delete(p);}}
    }
    private static String hash(byte[] bytes)throws Exception{return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes));}
}
