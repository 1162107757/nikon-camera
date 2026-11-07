package cc.huevia.ncp;

import cc.huevia.album.PhotoEditStore;
import java.io.*;
import java.nio.ByteBuffer;
import java.nio.file.*;
import java.util.*;

/** Synthetic semantic-mask storage and sampling contracts; no inference or user photographs. */
public final class PortraitSkinMaskTest {
    private static int checks;
    public static void main(String[] args)throws Exception{
        sampling();
        byte[] data=gradient();PhotoPortrait.SkinMask mask=new PhotoPortrait.SkinMask(-1.25,-1.75,1.75,1.25,data);
        byte first=data[0];data[0]=99;check(mask.copyCoverage()[0]==first,"constructor copies mask bytes");
        byte[] returned=mask.copyCoverage();returned[40]=99;check(mask.copyCoverage()[40]!=99,"coverage accessor returns defensive bytes");
        PhotoPortrait.SkinMask equal=new PhotoPortrait.SkinMask(-1.25,-1.75,1.75,1.25,gradient());
        check(mask.equals(equal)&&equal.equals(mask)&&mask.hashCode()==equal.hashCode(),"semantic value equality and hash");
        byte[] changed=gradient();changed[100]++;
        check(!mask.equals(new PhotoPortrait.SkinMask(-1.25,-1.75,1.75,1.25,changed)),"coverage participates in value state");
        check(!mask.equals(new PhotoPortrait.SkinMask(-1.24,-1.75,1.75,1.25,gradient()))&&!mask.equals(null),"bounds participate in value state");
        PhotoPortrait.SkinMask plusZero=new PhotoPortrait.SkinMask(0,0,1,1,gradient()),minusZero=new PhotoPortrait.SkinMask(-0.0,-0.0,1,1,gradient());
        check(plusZero.equals(minusZero)&&plusZero.hashCode()==minusZero.hashCode(),"signed zero bounds are canonical");
        for(double[] bad:new double[][]{{-8.01,0,1,1},{0,-8.01,1,1},{0,0,8.01,1},{0,0,1,8.01},{Double.NaN,0,1,1},{0,Double.NEGATIVE_INFINITY,1,1},{0,0,Double.POSITIVE_INFINITY,1},{0,0,1,Double.NaN},{1,0,1,1},{2,0,1,1},{0,1,1,1},{0,2,1,1}})
            expectInvalid(()->new PhotoPortrait.SkinMask(bad[0],bad[1],bad[2],bad[3],gradient()),"invalid semantic bounds rejected");
        expectInvalid(()->new PhotoPortrait.SkinMask(0,0,1,1,null),"null coverage rejected");
        expectInvalid(()->new PhotoPortrait.SkinMask(0,0,1,1,new byte[16383]),"short coverage rejected");
        expectInvalid(()->new PhotoPortrait.SkinMask(0,0,1,1,new byte[16385]),"long coverage rejected");
        check(new PhotoPortrait.SkinMask(-8,-8,8,8,gradient()).left==-8,"inclusive coordinate bounds accepted");

        PhotoPortrait.Face old=face(),marked=old.withLandmarks(mesh()).withSkinMask(mask);
        check(old.skinMask==null&&new PhotoPortrait.Face(old.cx,old.cy,old.rx,old.ry,old.roll,old.skinR,old.skinG,old.skinB,old.enabled,old.settings,old.strokes,mesh()).skinMask==null,"old eleven/twelve parameter constructors leave mask absent");
        check(marked.equals(new PhotoPortrait.Face(old.cx,old.cy,old.rx,old.ry,old.roll,old.skinR,old.skinG,old.skinB,old.enabled,old.settings,old.strokes,mesh(),equal)),"thirteen parameter constructor preserves both optional values");
        check(marked.withSettings(PhotoPortrait.Settings.NONE).skinMask==mask,"settings retain semantic mask");
        check(marked.withEnabled(false).skinMask==mask,"enabled change retains semantic mask");
        check(marked.withSkin(160,110,80).skinMask==mask,"skin sample change retains semantic mask");
        check(marked.withBounds(.6,.4,.12,.2,27).skinMask==mask,"bounds change retains local semantic mask");
        PhotoPortrait.Stroke stroke=new PhotoPortrait.Stroke(new double[]{.2,.3,.3,.4},.03,.6,false);
        check(marked.withStrokes(List.of(stroke)).skinMask==mask&&marked.addStroke(stroke).skinMask==mask&&marked.clearStrokes().skinMask==mask,"all stroke copies retain semantic mask");
        check(marked.withLandmarks(null).landmarks==null&&marked.withLandmarks(null).skinMask==mask,"mesh removal retains independent semantic mask");
        check(marked.withSkinMask(null).skinMask==null&&marked.withSkinMask(null).landmarks==marked.landmarks,"semantic mask removal retains mesh");
        check(!marked.equals(marked.withSkinMask(null)),"semantic mask participates in face state");

        PhotoPortrait.Heal heal=new PhotoPortrait.Heal(.1,.2,.6,.7,.025,.4,true);
        PhotoPortrait mixed=new PhotoPortrait(List.of(old,old.withLandmarks(mesh()),old.withSkinMask(mask),marked),List.of(heal));
        byte[] encoded=bytes(mixed);PhotoPortrait restored=read(encoded);
        check(ByteBuffer.wrap(encoded).getInt(4)==4,"current writer emits version4 with backward-compatible mesh/semantic state");
        check(restored.equals(mixed)&&restored.hashCode()==mixed.hashCode()&&Arrays.equals(encoded,bytes(restored)),"all four mesh/skin presence combinations roundtrip canonically");
        check(restored.faces().get(0).landmarks==null&&restored.faces().get(0).skinMask==null,"both absent remains absent");
        check(restored.faces().get(1).landmarks!=null&&restored.faces().get(1).skinMask==null,"mesh-only face remains independent");
        check(restored.faces().get(2).landmarks==null&&restored.faces().get(2).skinMask.equals(mask),"skin-only face remains independent");
        check(restored.faces().get(3).landmarks.equals(marked.landmarks)&&restored.faces().get(3).skinMask.equals(mask),"both present restore fully");
        check(restored.identity().equals(mixed.identity())&&!mixed.identity().equals(mixed.withFace(3,marked.withSkinMask(new PhotoPortrait.SkinMask(-1.25,-1.75,1.75,1.25,changed))).identity()),"semantic raster participates in canonical portrait identity");
        PhotoPortrait legacy=read(legacyBytes(old));
        check(legacy.faces().get(0).equals(old)&&legacy.faces().get(0).landmarks==null&&legacy.faces().get(0).skinMask==null,"version1 layout is untouched and gains no invented segmentation");
        check(read(bytes(legacy)).equals(legacy),"version1 can be saved as complete version4 without changing old face state");
        byte[] maximum=bytes(new PhotoPortrait(Collections.nCopies(PhotoPortrait.MAX_FACES,marked),List.of()));
        check(maximum.length<512*1024&&read(maximum).faces().size()==PhotoPortrait.MAX_FACES,"maximum semantic/mesh count stays bounded and readable");
        malformed(old,mask);
        nestedAndDraft(mixed,marked);
        System.out.println("PASS PortraitSkinMaskTest "+checks+" checks");
    }
    private static void sampling(){
        int size=PhotoPortrait.SkinMask.SIZE;check(size==128,"raster size contract");
        PhotoPortrait.SkinMask plane=new PhotoPortrait.SkinMask(-1.25,-1.75,1.75,1.25,gradient());
        near(plane.weight(u(0),v(0)),0,1e-14,"first pixel centre is not offset by half a sample");
        near(plane.weight(u(127),v(127)),254/255.0,1e-14,"last pixel centre uses unsigned value");
        near(plane.weight(u(20.25),v(47.75)),68/255.0,1e-14,"bilinear interpolation exactly preserves an affine ramp");
        near(plane.weight(-1.25,-1.75),0,1e-14,"left/top border clamps neighbouring sample indices");
        near(plane.weight(1.75,1.25),254/255.0,1e-14,"right/bottom border clamps neighbouring sample indices");
        byte[] four=new byte[size*size];four[40*size+30]=10;four[40*size+31]=110;four[41*size+30]=(byte)210;four[41*size+31]=(byte)250;
        PhotoPortrait.SkinMask cells=new PhotoPortrait.SkinMask(-1.25,-1.75,1.75,1.25,four);
        near(cells.weight(u(30.25),v(40.75)),173.75/255,1e-14,"four known neighbours have analytic bilinear weight");
        near(cells.weight(u(30),v(41)),210/255.0,1e-14,"negative signed byte decodes as unsigned confidence");
        byte[] opaque=new byte[size*size];Arrays.fill(opaque,(byte)255);
        PhotoPortrait.SkinMask full=new PhotoPortrait.SkinMask(-1.25,-1.75,1.75,1.25,opaque);
        for(double[] p:new double[][]{{-1.25,-1.75},{1.75,1.25},{0,0},{-1.2,1.2}})near(full.weight(p[0],p[1]),1,1e-14,"constant opaque mask remains one including clamped borders");
        for(double[] p:new double[][]{{Math.nextDown(-1.25),0},{Math.nextUp(1.75),0},{0,Math.nextDown(-1.75)},{0,Math.nextUp(1.25)},{Double.NaN,0},{0,Double.POSITIVE_INFINITY},{Double.NEGATIVE_INFINITY,0}})
            check(full.weight(p[0],p[1])==0,"outside or nonfinite query is zero");
        check(new PhotoPortrait.SkinMask(0,0,1,1,new byte[size*size]).weight(.5,.5)==0,"empty confidence stays zero");
        check(new PhotoPortrait.SkinMask(0,0,Double.MIN_VALUE,Double.MIN_VALUE,opaque).weight(Double.MIN_VALUE,Double.MIN_VALUE)==1,"finite tiny local bounds stay numerically safe");
    }
    private static void malformed(PhotoPortrait.Face old,PhotoPortrait.SkinMask mask)throws Exception{
        byte[] encoded=bytes(new PhotoPortrait(List.of(old.withSkinMask(mask)),List.of()));
        int skinFlag=legacyBytes(old).length-4+1;
        byte[] badFlag=encoded.clone();badFlag[skinFlag]=2;expectIo(()->read(badFlag),"noncanonical skin presence byte rejected");
        for(double[] values:new double[][]{{Double.NaN,-1.75,1.75,1.25},{-1.25,-1.75,Double.POSITIVE_INFINITY,1.25},{2,-1.75,1.75,1.25},{-1.25,1.25,1.75,1.25},{-8.01,-1.75,1.75,1.25}}){
            byte[] invalid=encoded.clone();for(int i=0;i<4;i++)ByteBuffer.wrap(invalid).putDouble(skinFlag+1+i*8,values[i]);expectIo(()->read(invalid),"invalid wire bounds rejected");
        }
        for(int length:new int[]{skinFlag,skinFlag+1,skinFlag+32,skinFlag+1+32+8192,skinFlag+1+32+16384-1,encoded.length-1}){
            byte[] cut=Arrays.copyOf(encoded,length);expectIo(()->read(cut),"truncated skin bounds/bytes/continuation rejected");
        }
    }
    private static void nestedAndDraft(PhotoPortrait portrait,PhotoPortrait.Face face)throws Exception{
        PhotoLocalEdits local=new PhotoLocalEdits(List.of(PhotoLocalEdits.Mask.radial(.3,.4).parameters(6,7,-8)),List.of(new PhotoLocalEdits.Clone(.1,.2,.5,.6,.04,.6,true)),portrait);
        ByteArrayOutputStream b=new ByteArrayOutputStream();local.write(new DataOutputStream(b));PhotoLocalEdits restored=PhotoLocalEdits.read(new DataInputStream(new ByteArrayInputStream(b.toByteArray())));
        check(restored.equals(local)&&restored.identity().equals(local.identity()),"nested local state preserves segmentation, mesh, manual masks and clones");
        ByteArrayOutputStream v1=new ByteArrayOutputStream();DataOutputStream old=new DataOutputStream(v1);old.writeInt(2);old.writeInt(0);old.writeInt(0);old.write(legacyBytes(face()));
        check(PhotoLocalEdits.read(new DataInputStream(new ByteArrayInputStream(v1.toByteArray()))).portrait.faces().get(0).skinMask==null,"nested version1 portrait still reads without semantic data");
        Path temp=Files.createTempDirectory("portrait-semantic-model-");
        try{
            String sha="f".repeat(64);PhotoEditStore store=new PhotoEditStore(temp.toFile(),"semantic-owner");PhotoEditStore.Draft draft=draft(sha,local);
            store.save(draft);PhotoEditStore.Draft read=store.read(sha);
            check(read.localEdits.equals(local)&&read.identity().equals(draft.identity()),"persistent draft restores exact segmentation and complete nested state");
            check(Arrays.equals(read.localEdits.portrait.faces().get(3).skinMask.copyCoverage(),face.skinMask.copyCoverage()),"persistent unsigned confidence bytes restore exactly");
            check(new PhotoEditStore(temp.toFile(),"other-owner").read(sha)==null,"semantic draft remains owner scoped");
            byte[] changed=face.skinMask.copyCoverage();changed[7]++;
            PhotoPortrait.Face nextFace=face.withSkinMask(new PhotoPortrait.SkinMask(face.skinMask.left,face.skinMask.top,face.skinMask.right,face.skinMask.bottom,changed));
            PhotoLocalEdits nextLocal=local.withPortrait(portrait.withFace(3,nextFace));PhotoEditStore.Draft next=draft(sha,nextLocal);store.save(next);store.markExported(draft);
            check(!store.read(sha).exported&&!store.replace(sha,draft,draft),"semantic changes prevent stale export and stale draft replacement");
            store.markExported(next);check(store.read(sha).exported&&store.read(sha).localEdits.equals(nextLocal),"matching semantic export preserves exact new state");
        }finally{try(var files=Files.walk(temp)){for(Path file:files.sorted(Comparator.reverseOrder()).toList())Files.delete(file);}}
    }
    private static PhotoEditStore.Draft draft(String sha,PhotoLocalEdits local)throws IOException{return new PhotoEditStore.Draft(sha,null,"合成语义蒙版",0,PhotoAdjustments.NONE,PhotoGeometry.NONE,PhotoBorder.NONE,local,false);}
    private static double u(double x){return -1.25+(x+.5)/128*3;}
    private static double v(double y){return -1.75+(y+.5)/128*3;}
    private static byte[] gradient(){byte[] p=new byte[128*128];for(int y=0;y<128;y++)for(int x=0;x<128;x++)p[y*128+x]=(byte)(x+y);return p;}
    private static PhotoPortrait.Landmarks mesh(){double[] p=new double[936];for(int i=0;i<468;i++){p[2*i]=(i%26-12)/10.0;p[2*i+1]=(i/26-9)/10.0;}return new PhotoPortrait.Landmarks(p);}
    private static PhotoPortrait.Face face(){return new PhotoPortrait.Face(.4,.55,.17,.26,-8,190,135,100,true,new PhotoPortrait.Settings(12,3,-2,16,68,4,7),List.of());}
    private static byte[] bytes(PhotoPortrait p)throws IOException{ByteArrayOutputStream b=new ByteArrayOutputStream();p.write(new DataOutputStream(b));return b.toByteArray();}
    private static PhotoPortrait read(byte[] b)throws IOException{return PhotoPortrait.read(new DataInputStream(new ByteArrayInputStream(b)));}
    /** Independent original version1 face layout, with no optional data at all. */
    private static byte[] legacyBytes(PhotoPortrait.Face f)throws IOException{
        ByteArrayOutputStream b=new ByteArrayOutputStream();DataOutputStream out=new DataOutputStream(b);out.writeInt(0x50525431);out.writeInt(1);out.writeInt(1);
        for(double x:new double[]{f.cx,f.cy,f.rx,f.ry,f.roll})out.writeDouble(x);out.writeInt(f.skinR);out.writeInt(f.skinG);out.writeInt(f.skinB);out.writeBoolean(f.enabled);
        PhotoPortrait.Settings s=f.settings;for(int x:new int[]{s.brightness,s.warmth,s.redness,s.smoothing,s.texture,s.light,s.shadows})out.writeInt(x);out.writeInt(0);out.writeInt(0);return b.toByteArray();
    }
    private interface Action{void run()throws Exception;}
    private static void expectInvalid(Action action,String name)throws Exception{try{action.run();throw new AssertionError(name);}catch(IllegalArgumentException expected){checks++;}}
    private static void expectIo(Action action,String name)throws Exception{try{action.run();throw new AssertionError(name);}catch(IOException expected){checks++;}}
    private static void near(double actual,double expected,double tolerance,String name){checks++;if(!Double.isFinite(actual)||Math.abs(actual-expected)>tolerance)throw new AssertionError(name+" "+actual+" != "+expected);}
    private static void check(boolean value,String name){checks++;if(!value)throw new AssertionError(name);}
}
