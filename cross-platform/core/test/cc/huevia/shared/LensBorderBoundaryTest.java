package cc.huevia.shared;

import cc.huevia.album.PhotoEditStore;
import cc.huevia.library.*;
import cc.huevia.ncp.*;
import java.io.*;
import java.nio.file.*;
import java.util.*;

final class LensBorderBoundaryTest {
    private static int checks;
    private static void yes(boolean value){checks++;if(!value)throw new AssertionError("Lens border check "+checks);}
    private static byte[] bytes(PhotoBorder border)throws IOException{ByteArrayOutputStream out=new ByteArrayOutputStream();border.write(new DataOutputStream(out));return out.toByteArray();}
    static int run(Path temporary)throws Exception {
        checks=0;PhotoBorder legacy=PhotoBorder.NONE.withTemplate(3);
        byte[] old=bytes(legacy);DataInputStream input=new DataInputStream(new ByteArrayInputStream(old));yes(input.readUTF().equals("photo-border-v1"));
        PhotoBorder restored=PhotoBorder.read(new DataInputStream(new ByteArrayInputStream(old)));yes(restored.equals(legacy));yes(!restored.showLens&&restored.lens.isEmpty());yes(Arrays.equals(bytes(restored),old));
        SharedCaptureInfo capture=new SharedCaptureInfo("{\"Make\":\"NIKON\",\"Model\":\"Z6II\",\"LensModel\":\"NIKKOR Z 24-70mm f/4 S\",\"FocalLength\":\"50\"}");
        yes(capture.parameters(legacy).equals("50mm"));
        PhotoBorder automatic=legacy.withLens(true,"");yes(capture.lens(automatic).equals("NIKKOR Z 24-70mm f/4 S"));
        PhotoBorder custom=automatic.withLens(true,"NIKKOR Z 85mm f/1.8 S");yes(!capture.parameters(custom).contains("24-70"));yes(capture.lens(custom).contains("85mm"));
        yes(capture.lens(custom.withLens(false,custom.lens)).isEmpty());
        yes(custom.withAppearance(0,120).showLens);yes(custom.withCamera(false,"NIKON","Z8").lens.equals(custom.lens));
        input=new DataInputStream(new ByteArrayInputStream(bytes(custom)));yes(PhotoBorder.read(input).equals(custom));yes(input.available()==0);
        Path root=Files.createDirectory(temporary.resolve("lens-border")),source=root.resolve("source.jpg");byte[] original={1,2,3,4};Files.write(source,original);
        SharedEdits edits=new SharedEdits(root.toFile(),new PresetLibrary(root.toFile()));
        Map<String,Object> recipe=SharedRuntime.map("border",SharedRuntime.map("template",3,"showLens",true,"lens",custom.lens));
        PhotoEditStore.Draft frozen=edits.freeze(source.toFile(),"",SharedJson.encode(recipe));
        PhotoEditStore.Draft disk=new PhotoEditStore(root.toFile(),"").read(frozen.sourceSha);
        yes(disk.border.equals(custom));SharedRecipe roundtrip=new SharedRecipe(SharedJson.encode(SharedEdits.recipe(disk)));yes(roundtrip.border.equals(custom));
        yes(Arrays.equals(Files.readAllBytes(source),original));
        int w=65,h=65;int[] gray=new int[w*h];Arrays.fill(gray,0xff606060);int[] neutral=new int[PhotoAdjustments.Parameter.values().length];
        for(int exposure:new int[]{15,-15}){
            PhotoLocalEdits local=new PhotoLocalEdits(List.of(new PhotoLocalEdits.Mask(PhotoLocalEdits.Kind.RADIAL,.5,.5,.3,.3,.08,.95,false,true,exposure,0,0,new double[0])),List.of());
            int[] result=CoreEngine.colourProfile(null,100,neutral,PhotoCurves.NONE,PhotoHsl.NONE,PhotoColorPalette.NONE,PhotoCleanup.NONE,local).render(gray,w,h);
            int center=result[32*w+32]&255,corner=result[0]&255;
            yes(exposure>0?center>corner:center<corner);yes(Arrays.stream(gray).allMatch(pixel->pixel==0xff606060));
        }
        System.out.println("PASS "+checks+" lens/frame and light pixel checks; legacy bytes, opt-in EXIF/manual lens, saved draft roundtrip and spatial signed relighting");return checks;
    }
}
