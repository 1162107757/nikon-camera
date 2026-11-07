package cc.huevia.ncp;

import java.io.*;
import java.util.*;

/** Model and untrusted-wire checks; does not rely on Android or the image kernel. */
public final class PortraitModelTest {
    private static int checks;
    public static void main(String[] args) throws Exception {
        check(PhotoPortrait.NONE.isEmpty() && PhotoPortrait.NONE.isNeutral(), "empty portrait is neutral");
        PhotoPortrait.Face face = face(PhotoPortrait.Settings.NONE);
        PhotoPortrait neutral = new PhotoPortrait(List.of(face), List.of());
        check(!neutral.isEmpty() && neutral.isNeutral(), "selected face without effects retains state but no pixel effect");
        check(face.withSettings(new PhotoPortrait.Settings(0,0,0,0,0,0,0)).settings.isNeutral(), "texture alone cannot change pixels");
        check(!face.withSettings(new PhotoPortrait.Settings(1,0,0,0,70,0,0)).settings.isNeutral(), "brightness activates face effect");
        PhotoPortrait disabled = new PhotoPortrait(List.of(face.withSettings(new PhotoPortrait.Settings(30,0,0,0,70,0,0)).withEnabled(false)),List.of());
        check(disabled.isNeutral(), "disabled face is neutral");
        PhotoPortrait.Heal heal = new PhotoPortrait.Heal(.2,.3,.6,.7,.04,.6,true);
        check(!PhotoPortrait.NONE.addHeal(heal).isNeutral(), "enabled distinct healing patch is active");
        check(PhotoPortrait.NONE.addHeal(new PhotoPortrait.Heal(.2,.3,.2,.3,.04,.6,true)).isNeutral(), "same-source healing is neutral");
        check(PhotoPortrait.NONE.addHeal(new PhotoPortrait.Heal(.2,.3,.6,.7,.04,.6,false)).isNeutral(), "disabled healing is neutral");

        double[] points={.2,.3,.4,.5};
        PhotoPortrait.Stroke stroke=new PhotoPortrait.Stroke(points,.03,.4,false);points[0]=.9;
        check(stroke.points()[0]==.2, "stroke copies input points");
        double[] returned=stroke.points();returned[1]=.9;
        check(stroke.points()[1]==.3, "stroke returns defensive points");
        ArrayList<PhotoPortrait.Stroke> strokes=new ArrayList<>();strokes.add(stroke);
        PhotoPortrait.Face painted=face.withStrokes(strokes);strokes.clear();
        check(painted.strokes.size()==1, "face copies stroke list");
        expectUnsupported(()->painted.strokes.clear(), "face stroke list is immutable");
        ArrayList<PhotoPortrait.Face> faces=new ArrayList<>();faces.add(painted);
        PhotoPortrait portrait=new PhotoPortrait(faces,List.of(heal));faces.clear();
        check(portrait.faces().size()==1 && portrait.heals().size()==1, "portrait copies lists");
        expectUnsupported(()->portrait.faces().clear(), "face list is immutable");
        expectUnsupported(()->portrait.heals().clear(), "healing list is immutable");
        check(portrait.withFace(0,face).heals().equals(portrait.heals()), "face mutation retains healing");
        check(portrait.removeFace(0).heals().equals(portrait.heals()), "face deletion retains independent healing");
        check(portrait.removeHeal(0).faces().equals(portrait.faces()), "healing deletion retains face masks");
        check(painted.clearStrokes().settings.equals(painted.settings), "clear mask strokes retains effects");

        byte[] encoded=bytes(portrait);
        PhotoPortrait restored=read(encoded);
        check(restored.equals(portrait) && restored.hashCode()==portrait.hashCode(), "full portrait roundtrip");
        check(restored.identity().equals(portrait.identity()), "full portrait identity roundtrip");
        check(Arrays.equals(encoded,bytes(restored)), "canonical portrait wire bytes");
        check(portrait.identity().equals(portrait.identity()), "cached immutable identity is stable");
        check(!neutral.identity().equals(neutral.withFace(0,face.withSkin(100,70,50)).identity()), "skin sample participates in state identity");
        check(!neutral.identity().equals(neutral.withFace(0,face.withBounds(.35,.5,.2,.3,12)).identity()), "face bounds participate in state identity");
        check(!neutral.identity().equals(neutral.withFace(0,face.addStroke(stroke)).identity()), "mask correction participates in state identity");
        check(!neutral.identity().equals(neutral.withFace(0,face.withSettings(new PhotoPortrait.Settings(0,0,0,0,0,0,0))).identity()), "neutral texture choice still participates in state identity");
        PhotoPortrait.Face zeroA=new PhotoPortrait.Face(-0.0,.5,.2,.3,-0.0,190,130,95,true,PhotoPortrait.Settings.NONE,List.of());
        PhotoPortrait.Face zeroB=new PhotoPortrait.Face(0.0,.5,.2,.3,0.0,190,130,95,true,PhotoPortrait.Settings.NONE,List.of());
        check(new PhotoPortrait(List.of(zeroA),List.of()).identity().equals(new PhotoPortrait(List.of(zeroB),List.of()).identity()), "signed zero is canonical");

        expectInvalid(()->new PhotoPortrait.Settings(101,0,0,0,70,0,0), "settings upper bound");
        expectInvalid(()->new PhotoPortrait.Settings(0,0,0,-1,70,0,0), "smoothing cannot be negative");
        expectInvalid(()->new PhotoPortrait.Face(Double.NaN,.5,.2,.3,0,190,130,95,true,PhotoPortrait.Settings.NONE,List.of()), "nonfinite coordinates rejected");
        expectInvalid(()->new PhotoPortrait.Face(.3,.5,0,.3,0,190,130,95,true,PhotoPortrait.Settings.NONE,List.of()), "zero face radius rejected");
        expectInvalid(()->face.withSkin(256,0,0), "skin channel bound");
        expectInvalid(()->new PhotoPortrait.Stroke(new double[]{.2},.03,.4,false), "odd stroke coordinates rejected");
        expectInvalid(()->new PhotoPortrait.Stroke(new double[]{.2,.3},.03,Double.NaN,false), "nonfinite feather rejected");
        expectInvalid(()->new PhotoPortrait.Heal(.2,.3,.6,.7,0,.5,true), "zero healing radius rejected");
        expectInvalid(()->new PhotoPortrait(Collections.nCopies(PhotoPortrait.MAX_FACES+1,face),List.of()), "face count is bounded");
        expectInvalid(()->new PhotoPortrait(List.of(),Collections.nCopies(PhotoPortrait.MAX_HEALS+1,heal)), "healing count is bounded");
        expectInvalid(()->face.withStrokes(Collections.nCopies(PhotoPortrait.MAX_STROKES+1,stroke)), "per-face stroke count is bounded");
        expectInvalid(()->new PhotoPortrait(Collections.nCopies(3,face.withStrokes(Collections.nCopies(32,stroke))),List.of()), "global stroke count is bounded");
        double[] maximumPoints=new double[PhotoPortrait.MAX_STROKE_POINTS*2];Arrays.fill(maximumPoints,.4);
        PhotoPortrait.Stroke longStroke=new PhotoPortrait.Stroke(maximumPoints,.03,.4,false);
        expectInvalid(()->new PhotoPortrait(List.of(face.withStrokes(Collections.nCopies(16,longStroke)),face.withStrokes(List.of(longStroke))),List.of()), "global point count is bounded");
        byte[] invalid=encoded.clone();invalid[0]^=1;expectIo(()->read(invalid), "bad portrait magic rejected");
        byte[] version=encoded.clone();version[7]=99;expectIo(()->read(version), "unknown portrait version rejected");
        byte[] bool=encoded.clone();bool[64]=2;expectIo(()->read(bool), "noncanonical boolean rejected");
        for(int length=0;length<encoded.length;length++){
            byte[] truncated=Arrays.copyOf(encoded,length);expectIo(()->read(truncated), "truncated portrait at byte "+length);
        }
        check(encoded.length<64*1024, "representative state remains small");
        System.out.println("PASS PortraitModelTest "+checks+" checks");
    }
    private static PhotoPortrait.Face face(PhotoPortrait.Settings settings){return new PhotoPortrait.Face(.3,.5,.2,.3,0,190,130,95,true,settings,List.of());}
    private static byte[] bytes(PhotoPortrait value)throws IOException{ByteArrayOutputStream b=new ByteArrayOutputStream();value.write(new DataOutputStream(b));return b.toByteArray();}
    private static PhotoPortrait read(byte[] bytes)throws IOException{return PhotoPortrait.read(new DataInputStream(new ByteArrayInputStream(bytes)));}
    private interface Action {void run()throws Exception;}
    private static void expectIo(Action action,String message)throws Exception{try{action.run();throw new AssertionError(message);}catch(IOException expected){checks++;}}
    private static void expectInvalid(Action action,String message)throws Exception{try{action.run();throw new AssertionError(message);}catch(IllegalArgumentException|NullPointerException expected){checks++;}}
    private static void expectUnsupported(Action action,String message)throws Exception{try{action.run();throw new AssertionError(message);}catch(UnsupportedOperationException expected){checks++;}}
    private static void check(boolean value,String message){checks++;if(!value)throw new AssertionError(message);}
}
