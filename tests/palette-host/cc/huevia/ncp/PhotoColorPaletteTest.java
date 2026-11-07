package cc.huevia.ncp;

import cc.huevia.album.*;
import java.io.*;
import java.nio.ByteBuffer;
import java.nio.file.*;
import java.security.MessageDigest;
import java.util.*;

/** Actual engine and persisted bytes, synthetic pixels only; no Android or camera dependency. */
public final class PhotoColorPaletteTest {
    private static int checks,outsideChecks;
    private static final String SHA="7".repeat(64);
    public static void main(String[] args)throws Exception{
        limits();pixels();independentSettings();persistence();legacyReaders();regional();
        System.out.println("PhotoColorPaletteTest PASS checks="+checks+" protectedOutsidePixels="+outsideChecks);
    }
    private static void limits()throws Exception{
        for(int[] v:new int[][]{{-101,0,100},{101,0,100},{0,-101,100},{0,101,100},{0,0,-1},{0,0,101}})expectIllegal(()->new PhotoColorPalette(v[0],v[1],v[2]));
        PhotoColorPalette p=new PhotoColorPalette(-100,100,0);check(p.isNeutral()&&p.hasStoredState(),"zero intensity retains position");
        check(!PhotoColorPalette.NONE.hasStoredState()&&PhotoColorPalette.NONE.isNeutral(),"canonical default");
        byte[] good=paletteBytes(p);check(good.length==13&&PhotoColorPalette.read(input(good)).equals(p),"bounded palette roundtrip");
        for(int offset:new int[]{0,1,5,9}){byte[] bad=good.clone();if(offset==0)bad[0]=2;else ByteBuffer.wrap(bad).putInt(offset,Integer.MAX_VALUE);expectIo(()->PhotoColorPalette.read(input(bad)));}
        for(int length=0;length<good.length;length++){byte[] cut=Arrays.copyOf(good,length);expectIo(()->PhotoColorPalette.read(input(cut)));}
    }
    private static void pixels()throws Exception{
        PhotoAdjustments old=PhotoAdjustments.NONE.with(PhotoAdjustments.Parameter.EXPOSURE,7).with(PhotoAdjustments.Parameter.TEMPERATURE,23)
                .withCurves(PhotoCurves.NONE.withPoints(1,new int[]{0,0,128,149,255,255})).withHsl(PhotoHsl.NONE.with(3,1,-19));
        PresetPreviewProfile baseline=AdjustedPreviewProfile.of(null,old);
        for(PhotoColorPalette neutral:new PhotoColorPalette[]{PhotoColorPalette.NONE,new PhotoColorPalette(0,0,0),new PhotoColorPalette(0,0,37),new PhotoColorPalette(100,-100,0),new PhotoColorPalette(-73,29,0)}){
            PresetPreviewProfile current=AdjustedPreviewProfile.of(null,old.withPalette(neutral));
            for(int i=0;i<16384;i++){int value=Integer.rotateLeft(i*0x9e3779b9,7)^0x81732945;check(neutral.applyArgb(value)==value,"neutral direct packed ARGB");check(current.applyArgb(value)==baseline.applyArgb(value),"neutral leaves existing pipeline byte exact");}
        }
        for(int tone=-100;tone<=100;tone+=20){PhotoColorPalette p=new PhotoColorPalette(0,tone,100);int previous=-1;
            for(int v=0;v<256;v++){int out=p.applyArgb(0xff000000|v*0x010101),channel=out&255;check(channel>=previous,"monotonic tone curve");previous=channel;
                check(((out>>>16)&255)==channel&&((out>>>8)&255)==channel,"tone leaves gray neutral");}
            check(p.applyArgb(0xff000000)==0xff000000&&p.applyArgb(0xffffffff)==0xffffffff,"tone fixed endpoints");
        }
        PhotoColorPalette strong=new PhotoColorPalette(88,77,100),half=strong.withAmount(50),gray=new PhotoColorPalette(-100,0,100);
        for(int i=0;i<65536;i++){int value=Integer.rotateLeft(i*0x45d9f3b,9)^0x1a6d3085;int full=strong.applyArgb(value),mid=half.applyArgb(value);
            check((full>>>24)==(value>>>24)&&(mid>>>24)==(value>>>24),"alpha exact");
            if((value>>>24)==0)check(full==value&&mid==value,"transparent hidden RGB exact");
            else{for(int shift=0;shift<=16;shift+=8)check(Math.abs(((mid>>>shift)&255)-(((value>>>shift)&255)+((full>>>shift)&255))/2.0)<=1,"intensity final blend");
                int out=gray.applyArgb(value);check((out&255)==((out>>>8)&255)&&(out&255)==((out>>>16)&255),"negative colour reaches luminance gray");}
        }
        PhotoColorPalette vivid=new PhotoColorPalette(100,0,100);int warm=0xffb08060,cool=0xff6080b0;
        check(chroma(vivid.applyArgb(warm))/chroma(warm)<chroma(vivid.applyArgb(cool))/chroma(cool),"warm hues receive less added saturation");
        check(strong.applyArgb(0xff000000)==0xff000000&&strong.applyArgb(0xffffffff)==0xffffffff,"combined black white fixed");
        check(new PhotoColorPalette(0,100,100).applyArgb(0xff404040)<0xff404040&&new PhotoColorPalette(0,-100,100).applyArgb(0xff404040)>0xff404040,"tone changes contrast rather than whole exposure");
        check(new PhotoColorPalette(0,100,100).applyArgb(0xffc0c0c0)>0xffc0c0c0&&new PhotoColorPalette(0,-100,100).applyArgb(0xffc0c0c0)<0xffc0c0c0,"highlights move opposite shadows");
    }
    private static void independentSettings()throws Exception{
        PhotoAdjustments original=PhotoAdjustments.NONE;for(PhotoAdjustments.Parameter p:PhotoAdjustments.Parameter.values())original=original.with(p,p.max/3);
        PhotoColorPalette point=new PhotoColorPalette(37,-29,61);PhotoAdjustments changed=original.withPalette(point);
        check(Arrays.equals(changed.values(),original.values()),"palette does not overwrite manual sliders");
        for(PhotoAdjustments.Parameter p:PhotoAdjustments.Parameter.values())check(changed.with(p,0).palette.equals(point),"every manual slider retains palette");
        PhotoCurves curve=PhotoCurves.NONE.withPoints(0,new int[]{0,0,128,153,255,255});PhotoHsl hsl=PhotoHsl.NONE.with(0,0,17);
        check(changed.withCurves(curve).palette.equals(point)&&changed.withHsl(hsl).palette.equals(point),"advanced edits retain palette");
        ByteArrayOutputStream advanced=new ByteArrayOutputStream();original.writeAdvanced(new DataOutputStream(advanced));check(changed.readAdvanced(input(advanced.toByteArray())).palette.equals(point),"advanced reconstruction retains palette");
        PhotoAdjustments source=PhotoAdjustments.NONE.withPalette(new PhotoColorPalette(-28,42,80));
        check(changed.copyFrom(source,true,true,false).palette.equals(point),"basic curves copy retains destination colour");
        check(changed.copyFrom(source,false,false,true).palette.equals(source.palette),"colour copy includes palette");
        check(Arrays.equals(changed.copyFrom(source,false,false,true).values(),original.values()),"colour copy does not change basic sliders");
        PhotoAdjustments zero=PhotoAdjustments.NONE.withPalette(point.withAmount(0));check(zero.isNeutral()&&!zero.equals(PhotoAdjustments.NONE)&&!zero.identity().equals(PhotoAdjustments.NONE.identity()),"zero-intensity effect neutral state distinct");
        check(!AdjustedPreviewProfile.of(null,changed).modelVersion().equals(AdjustedPreviewProfile.of(null,original).modelVersion()),"palette invalidates rendered cache key");
    }
    private static void persistence()throws Exception{
        Path dir=Files.createTempDirectory("palette-state-");try{
            PhotoEditStore store=new PhotoEditStore(dir.toFile(),"owner");PhotoRecipeStore recipes=new PhotoRecipeStore(dir.toFile(),"owner");
            PhotoAdjustments manual=PhotoAdjustments.NONE.with(PhotoAdjustments.Parameter.CONTRAST,19).with(PhotoAdjustments.Parameter.TEMPERATURE,-11);
            int n=0;for(PhotoColorPalette palette:new PhotoColorPalette[]{PhotoColorPalette.NONE,new PhotoColorPalette(69,-42,83),new PhotoColorPalette(-71,54,0),new PhotoColorPalette(0,0,37)}){
                PhotoAdjustments settings=manual.withPalette(palette);AdjustmentRegion region=region(settings);PhotoLocalEdits local=local(region);
                byte[] wire=localBytes(local);check(ByteBuffer.wrap(wire).getInt()==(palette.hasStoredState()?4:3),"local version only advances for stored palette");
                check(PhotoLocalEdits.read(input(wire)).equals(local),"regional palette full roundtrip");
                PhotoEditStore.Draft draft=new PhotoEditStore.Draft(SHA,new byte[0],"无滤镜",0,settings,PhotoGeometry.NONE,PhotoBorder.NONE,local,false);store.save(draft);
                PhotoEditStore.Draft read=store.read(SHA);check(read.adjustments.equals(settings)&&read.localEdits.equals(local)&&read.identity().equals(draft.identity()),"draft all settings roundtrip");
                Path file=find(dir,".draft");check(ByteBuffer.wrap(Files.readAllBytes(file)).getInt()==(palette.hasStoredState()?0x50454437:0x50454436),"draft explicit version");
                PhotoRecipeStore.Recipe recipe=recipes.create("配方"+(++n),draft);PhotoRecipeStore.Recipe restored=recipes.read(recipe.id);check(restored.adjustments.equals(settings),"recipe roundtrip retains independent palette");
                check(restored.apply("8".repeat(64),PhotoGeometry.NONE).adjustments.equals(settings),"recipe apply retains palette");
                check(recipes.rename(recipe.id,"改名"+n).adjustments.equals(settings),"recipe rename retains palette");
            }
            PhotoEditStore.Draft before=store.read(SHA);PhotoAdjustments copySource=PhotoAdjustments.NONE.withPalette(new PhotoColorPalette(-32,58,77));
            PhotoAdjustmentCopy.Receipt receipt=PhotoAdjustmentCopy.apply(store,List.of(new PhotoAdjustmentCopy.Target(SHA,before,before)),copySource,false,false,true,()->true);
            check(receipt.changed()==1&&store.read(SHA).adjustments.palette.equals(copySource.palette),"real colour copy persists palette");
            check(Arrays.equals(store.read(SHA).adjustments.values(),before.adjustments.values()),"real colour copy retains manual values");
            check(receipt.undo(store)==1&&store.read(SHA).adjustments.equals(before.adjustments),"real copy undo restores palette state");
            PhotoColorPalette zero=new PhotoColorPalette(74,-39,0);PhotoEditStore.Draft neutral=new PhotoEditStore.Draft(SHA,null,"",0,PhotoAdjustments.NONE,false),positioned=new PhotoEditStore.Draft(SHA,null,"",0,PhotoAdjustments.NONE.withPalette(zero),false);
            check(!neutral.identity().equals(positioned.identity())&&!positioned.hasEffect(),"version identity retains zero strength coordinates");store.save(positioned);check(store.read(SHA).adjustments.palette.equals(zero),"only zero strength point survives reopening");
            PhotoEditStore.Draft regionalOnly=new PhotoEditStore.Draft(SHA,null,"",0,PhotoAdjustments.NONE,PhotoGeometry.NONE,PhotoBorder.NONE,local(region(PhotoAdjustments.NONE.withPalette(zero))),false);store.save(regionalOnly);check(store.read(SHA).localEdits.equals(regionalOnly.localEdits),"PED6 embeds explicit v4 regional data");
            PhotoEditStore.Draft active=new PhotoEditStore.Draft(SHA,null,"",0,PhotoAdjustments.NONE.withPalette(new PhotoColorPalette(75,50,100)),false);store.save(active);byte[] valid=Files.readAllBytes(find(dir,".draft"));
            // Corrupt the authenticated body with a valid digest: the strict field parser must reject it.
            byte[] body=Arrays.copyOf(valid,valid.length-32);int paletteOffset=globalPaletteOffset(body);body[paletteOffset]=2;byte[] invalid=withDigest(body);Files.write(find(dir,".draft"),invalid);expectIo(()->store.read(SHA));
            PhotoColorPalette marker=new PhotoColorPalette(75,50,100);byte[] localWire=localBytes(local(region(PhotoAdjustments.NONE.withPalette(marker))));int markerOffset=indexOf(localWire,paletteBytes(marker));check(markerOffset>=0,"regional stored palette located");ByteBuffer.wrap(localWire).putInt(markerOffset+1,101);expectIo(()->PhotoLocalEdits.read(input(localWire)));
            PhotoRecipeStore.Recipe badRecipe=recipes.create("损坏测试",active);Path recipePath=findRecipe(dir,badRecipe.id);byte[] recipeFile=Files.readAllBytes(recipePath),recipeBody=Arrays.copyOf(recipeFile,recipeFile.length-32);int recipeOffset=indexOf(recipeBody,paletteBytes(marker));check(recipeOffset>=0,"recipe stored palette located");ByteBuffer.wrap(recipeBody).putInt(recipeOffset+9,-1);Files.write(recipePath,withDigest(recipeBody));expectIo(()->recipes.read(badRecipe.id));
        }finally{remove(dir);}
    }
    private static void legacyReaders()throws Exception{
        Path dir=Files.createTempDirectory("palette-old-");try{PhotoEditStore store=new PhotoEditStore(dir.toFile(),"old");
            store.save(new PhotoEditStore.Draft(SHA,null,"",0,PhotoAdjustments.NONE,false));Path target=find(dir,".draft");
            for(int version=1;version<=6;version++){ByteArrayOutputStream bytes=new ByteArrayOutputStream();try(DataOutputStream out=new DataOutputStream(bytes)){
                out.writeInt(0x50454430+version);out.writeUTF(SHA);out.writeUTF("无滤镜");out.writeInt(0);out.writeBoolean(false);out.writeInt(0);
                if(version>=2){out.writeUTF(PhotoAdjustments.MODEL);out.writeInt(version==6?PhotoAdjustments.Parameter.values().length:PhotoAdjustments.LEGACY_PARAMETER_COUNT);for(int i=0;i<(version==6?PhotoAdjustments.Parameter.values().length:PhotoAdjustments.LEGACY_PARAMETER_COUNT);i++)out.writeInt(i==2?17:0);}
                if(version>=5)PhotoAdjustments.NONE.writeAdvanced(out);
                if(version>=3){out.writeUTF(PhotoGeometry.MODEL);for(int v:new int[]{0,0,0,0,10000,10000})out.writeInt(v);if(version==6){out.writeInt(0);out.writeInt(0);}}
                if(version>=4)PhotoBorder.NONE.write(out);if(version==6)PhotoLocalEdits.NONE.write(out);
            }Files.write(target,withDigest(bytes.toByteArray()));PhotoEditStore.Draft old=store.read(SHA);check(old.adjustments.palette.equals(PhotoColorPalette.NONE),"old draft has default palette v"+version);check(old.adjustments.get(PhotoAdjustments.Parameter.CONTRAST)==(version>=2?17:0),"old manual values retained v"+version);}
            PhotoRecipeStore recipes=new PhotoRecipeStore(dir.toFile(),"old");PhotoRecipeStore.Recipe record=recipes.create("迁移",new PhotoEditStore.Draft(SHA,null,"",0,PhotoAdjustments.NONE,false));Path recipePath=findRecipe(dir,record.id);
            for(int version=1;version<=3;version++){ByteArrayOutputStream bytes=new ByteArrayOutputStream();try(DataOutputStream out=new DataOutputStream(bytes)){
                out.writeInt(0x50524330+version);out.writeUTF(record.id);out.writeUTF("旧配方");out.writeLong(123456789L);out.writeUTF("无滤镜");out.writeInt(0);out.writeInt(0);out.writeUTF(PhotoAdjustments.MODEL);
                int count=version==3?PhotoAdjustments.Parameter.values().length:PhotoAdjustments.LEGACY_PARAMETER_COUNT;out.writeInt(count);for(int i=0;i<count;i++)out.writeInt(i==2?19:0);if(version>=2)PhotoAdjustments.NONE.writeAdvanced(out);
            }Files.write(recipePath,withDigest(bytes.toByteArray()));PhotoRecipeStore.Recipe old=recipes.read(record.id);check(old.adjustments.palette.equals(PhotoColorPalette.NONE)&&old.adjustments.get(PhotoAdjustments.Parameter.CONTRAST)==19,"old recipe default palette and slider v"+version);}
        }finally{remove(dir);}
    }
    private static void regional()throws Exception{
        PhotoColorPalette point=new PhotoColorPalette(87,-64,73);PhotoAdjustments settings=PhotoAdjustments.NONE.withPalette(point);AdjustmentRegion region=region(settings);
        Memory small=new Memory(80,54),large=new Memory(240,162);for(int y=0;y<large.h;y++)for(int x=0;x<large.w;x++)large.a[y*large.w+x]=sample(x/3,y/3);for(int y=0;y<small.h;y++)for(int x=0;x<small.w;x++)small.a[y*small.w+x]=sample(x,y);
        int[] original=small.a.clone();PhotoEditStore.Draft draft=new PhotoEditStore.Draft(SHA,null,"",0,PhotoAdjustments.NONE,PhotoGeometry.NONE,PhotoBorder.NONE,local(region),false);
        draft.profile().renderPixels(small,null,null);draft.profile().renderPixels(large,null,null);AdjustmentRegion.Brush brush=region.compileBrush(small.w,small.h);int inside=0;
        for(int y=0;y<small.h;y++)for(int x=0;x<small.w;x++){int index=y*small.w+x;double w=brush.weight((x+.5)/small.w,(y+.5)/small.h)*region.amount;
            if(w==0){outsideChecks++;check(small.a[index]==original[index],"mask outside packed pixel exact");}else if((original[index]>>>24)!=0){inside++;check(small.a[index]==blend(original[index],point.applyArgb(original[index]),w),"one mask blend after independent palette");}
            check(small.a[index]==large.a[(3*y+1)*large.w+3*x+1],"preview full-size normalized coordinates consistent");check((small.a[index]>>>24)==(original[index]>>>24),"regional alpha preserved");
        }check(inside>0&&outsideChecks>0,"regional fixture covers inside outside");
        Memory global=new Memory(80,54);for(int y=0;y<global.h;y++)for(int x=0;x<global.w;x++)global.a[y*global.w+x]=sample(x,y);AdjustedPreviewProfile.of(null,settings).renderPixels(global,null,null);
        for(int i=0;i<global.a.length;i++)check(global.a[i]==((original[i]>>>24)==0?original[i]:point.applyArgb(original[i])),"streaming full-image equals direct palette");
        Memory zero=new Memory(80,54);System.arraycopy(original,0,zero.a,0,original.length);AdjustmentRegionRenderer.apply(zero,List.of(region.withAdjustments(settings.withPalette(point.withAmount(0)))),1,null,null);check(Arrays.equals(zero.a,original),"regional zero intensity exact");
    }
    private static AdjustmentRegion region(PhotoAdjustments settings){return new AdjustmentRegion("palette_region","区域",true,.63,List.of(new PhotoPortrait.Stroke(new double[]{.24,.28,.55,.61},.12,.55,false),new PhotoPortrait.Stroke(new double[]{.4,.43},.035,.35,true)),settings,PhotoPortrait.NONE,PhotoPortrait.Settings.NONE,null);}
    private static PhotoLocalEdits local(AdjustmentRegion region){return new PhotoLocalEdits(List.of(),List.of(),PhotoPortrait.NONE,List.of(region));}
    private static int sample(int x,int y){return ((x+y)%13==0?0:((x*3+y*7)%255+1)<<24)|((x*13+y*3)&255)<<16|((x*7+y*11)&255)<<8|((x*17+y*5)&255);}
    private static int blend(int a,int b,double w){int out=a&0xff000000;for(int s=0;s<=16;s+=8)out|=((int)Math.round(((a>>>s)&255)+(((b>>>s)&255)-((a>>>s)&255))*w))<<s;return out;}
    private static double chroma(int value){return Math.max((value>>>16)&255,Math.max((value>>>8)&255,value&255))-Math.min((value>>>16)&255,Math.min((value>>>8)&255,value&255));}
    private static byte[] paletteBytes(PhotoColorPalette p)throws IOException{ByteArrayOutputStream b=new ByteArrayOutputStream();p.write(new DataOutputStream(b));return b.toByteArray();}
    private static byte[] localBytes(PhotoLocalEdits p)throws IOException{ByteArrayOutputStream b=new ByteArrayOutputStream();p.write(new DataOutputStream(b));return b.toByteArray();}
    private static DataInputStream input(byte[] bytes){return new DataInputStream(new ByteArrayInputStream(bytes));}
    private static int globalPaletteOffset(byte[] body)throws Exception{DataInputStream in=input(body);in.readInt();in.readUTF();in.readUTF();in.readInt();in.readBoolean();int length=in.readInt();in.skipNBytes(length);in.readUTF();int count=in.readInt();for(int i=0;i<count;i++)in.readInt();PhotoAdjustments.NONE.readAdvanced(in);return body.length-in.available();}
    private static byte[] withDigest(byte[] body)throws Exception{ByteArrayOutputStream b=new ByteArrayOutputStream();b.write(body);b.write(MessageDigest.getInstance("SHA-256").digest(body));return b.toByteArray();}
    private static Path find(Path dir,String suffix)throws IOException{try(var stream=Files.walk(dir)){return stream.filter(p->p.toString().endsWith(suffix)).findFirst().orElseThrow();}}
    private static Path findRecipe(Path dir,String id)throws IOException{return find(dir,id+".recipe");}
    private static int indexOf(byte[] source,byte[] value){outer:for(int i=0;i<=source.length-value.length;i++){for(int j=0;j<value.length;j++)if(source[i+j]!=value[j])continue outer;return i;}return -1;}
    private static void remove(Path dir)throws IOException{try(var stream=Files.walk(dir)){for(Path p:stream.sorted(Comparator.reverseOrder()).toArray(Path[]::new))Files.delete(p);}}
    private interface Run {void run()throws Exception;}
    private static void expectIllegal(Run work)throws Exception{try{work.run();throw new AssertionError("accepted invalid value");}catch(IllegalArgumentException expected){checks++;}}
    private static void expectIo(Run work)throws Exception{try{work.run();throw new AssertionError("accepted invalid wire");}catch(IOException expected){checks++;}}
    private static void check(boolean value,String what){if(!value)throw new AssertionError(what);checks++;}
    private static final class Memory implements SpatialPreviewFilter.Pixels {final int w,h;final int[] a;Memory(int w,int h){this.w=w;this.h=h;a=new int[w*h];}public int width(){return w;}public int height(){return h;}public void read(int[] out,int first,int rows){System.arraycopy(a,first*w,out,0,rows*w);}public void write(int[] in,int first,int rows){System.arraycopy(in,0,a,first*w,rows*w);}}
}
