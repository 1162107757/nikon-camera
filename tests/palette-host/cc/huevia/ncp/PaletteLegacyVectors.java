package cc.huevia.ncp;

import cc.huevia.album.PhotoEditStore;
import java.io.*;
import java.nio.file.*;
import java.security.MessageDigest;
import java.util.*;

/** Deterministic pre-palette compatibility vector; contains synthetic pixels only. */
public final class PaletteLegacyVectors {
    public static void main(String[] args)throws Exception{
        MessageDigest pixels=MessageDigest.getInstance("SHA-256");
        ArrayList<PhotoAdjustments> cases=new ArrayList<>();cases.add(PhotoAdjustments.NONE);
        for(PhotoAdjustments.Parameter p:PhotoAdjustments.Parameter.values())for(int v:new int[]{p.min,p.max})cases.add(PhotoAdjustments.NONE.with(p,v));
        PhotoAdjustments mixed=PhotoAdjustments.NONE.with(PhotoAdjustments.Parameter.TEMPERATURE,27).with(PhotoAdjustments.Parameter.SATURATION,-18)
                .withCurves(PhotoCurves.NONE.withPoints(0,new int[]{0,0,64,77,128,151,255,255})).withHsl(PhotoHsl.NONE.with(1,1,31));
        cases.add(mixed);int count=0;
        for(PhotoAdjustments settings:cases){PresetPreviewProfile profile=AdjustedPreviewProfile.of(null,settings);
            for(int i=0;i<8192;i++){int input=Integer.rotateLeft(i*0x9e3779b9,11)^0x53271389;int output=profile.applyArgb(input);for(int shift=24;shift>=0;shift-=8)pixels.update((byte)(output>>>shift));count++;}}
        System.out.println("pixels="+hex(pixels.digest())+" count="+count);
        ByteArrayOutputStream bytes=new ByteArrayOutputStream();mixed.writeAdvanced(new DataOutputStream(bytes));System.out.println("advanced="+hash(bytes.toByteArray()));
        AdjustmentRegion region=new AdjustmentRegion("legacy_region","局部",true,.65,List.of(new PhotoPortrait.Stroke(new double[]{.22,.35,.41,.56},.09,.6,false)),mixed,PhotoPortrait.NONE,PhotoPortrait.Settings.NONE,null);
        PhotoLocalEdits local=new PhotoLocalEdits(List.of(),List.of(),PhotoPortrait.NONE,List.of(region));bytes.reset();local.write(new DataOutputStream(bytes));System.out.println("local="+hash(bytes.toByteArray()));
        Path dir=Files.createTempDirectory("palette-legacy-");try{PhotoEditStore store=new PhotoEditStore(dir.toFile(),"legacy");PhotoEditStore.Draft draft=new PhotoEditStore.Draft("1".repeat(64),new byte[0],"无滤镜",0,mixed,PhotoGeometry.NONE,PhotoBorder.NONE,local,false);store.save(draft);try(var stream=Files.walk(dir)){Path file=stream.filter(Files::isRegularFile).findFirst().orElseThrow();System.out.println("draft="+hash(Files.readAllBytes(file)));}System.out.println("identity="+draft.identity());}finally{try(var stream=Files.walk(dir)){for(Path p:stream.sorted(Comparator.reverseOrder()).toArray(Path[]::new))Files.delete(p);}}
    }
    private static String hash(byte[] bytes)throws Exception{return hex(MessageDigest.getInstance("SHA-256").digest(bytes));}
    private static String hex(byte[] bytes){return HexFormat.of().formatHex(bytes);}
}
