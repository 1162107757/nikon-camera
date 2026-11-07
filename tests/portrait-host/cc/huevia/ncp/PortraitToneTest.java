package cc.huevia.ncp;

import cc.huevia.album.PhotoEditStore;
import java.io.*;
import java.nio.ByteBuffer;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.atomic.AtomicInteger;

/** Synthetic contract and pixel oracles; no user photograph or Android inference. */
public final class PortraitToneTest {
    private static int checks;
    private static final int SKIN=0xffbf987a;
    private static PhotoPortrait maximumPortrait;
    private static long maximumDraftBytes;
    public static void main(String[] args)throws Exception {
        catalogueAndState(); bodySampling(); compatibility(); nestedDraft(); colourInvariants(); rendering();
        System.out.println("PASS PortraitToneTest "+checks+" checks");
        System.out.println("DETAIL maximalPortraitBytes="+bytes(maximumPortrait).length+" maximalDraftBytes="+maximumDraftBytes);
    }
    private static void catalogueAndState()throws Exception {
        List<SkinTone.Entry> entries=SkinTone.presets();
        check(entries.size()==10&&entries.get(0).id==SkinTone.ORIGINAL,"catalogue contains original and nine presets");
        String[] labels={"原肤","自然米色","粉白","冷白","暖白","暖杏","蜜桃","冷米","小麦色","美黑"};
        Set<Integer> colours=new HashSet<>();
        for(int i=0;i<entries.size();i++) {
            SkinTone.Entry e=entries.get(i);check(e==SkinTone.byId(i)&&e.id==i&&e.label.equals(labels[i]),"stable catalogue identifier and label "+i);
            PhotoPortrait.Tone t=SkinTone.preset(i,.6,true);
            check(t.presetId==i&&t.colorRGB==e.colorRGB&&t.amount==.6&&t.body,"preset factory retains exact UI state "+i);
            check(colours.add(e.colorRGB),"preset RGB values are distinct "+i);
        }
        expectUnsupported(()->entries.clear(),"catalogue is immutable");
        expectInvalid(()->SkinTone.byId(-1),"negative preset rejected");expectInvalid(()->SkinTone.byId(10),"custom has no catalogue entry");
        PhotoPortrait.Tone t=SkinTone.custom(0xa1b2c3,.8,true);
        check(t.presetId==SkinTone.CUSTOM&&t.colorRGB==0xa1b2c3,"custom retains arbitrary target RGB");
        check(!SkinTone.custom(0,1,false).isNeutral(),"custom black is distinct from original");
        check(SkinTone.preset(0,1,true).isNeutral()&&SkinTone.custom(0xffffff,0,true).isNeutral(),"original and zero strength are rendering neutral");
        check(t.equals(new PhotoPortrait.Tone(10,0xa1b2c3,.8,true))&&t.hashCode()==new PhotoPortrait.Tone(10,0xa1b2c3,.8,true).hashCode(),"tone is an immutable value");
        check(!t.equals(SkinTone.custom(0xa1b2c4,.8,true))&&!t.equals(SkinTone.custom(0xa1b2c3,.7,true))&&!t.equals(SkinTone.custom(0xa1b2c3,.8,false)),"target strength and scope participate in value identity");
        check(SkinTone.custom(3,-0.0,false).equals(SkinTone.custom(3,0,false))&&SkinTone.custom(3,-0.0,false).hashCode()==SkinTone.custom(3,0,false).hashCode(),"negative zero strength is canonical");
        for(int id:new int[]{-1,11,Integer.MAX_VALUE})expectInvalid(()->new PhotoPortrait.Tone(id,0,.5,false),"invalid preset id rejected");
        for(int rgb:new int[]{-1,0x1000000,Integer.MIN_VALUE})expectInvalid(()->SkinTone.custom(rgb,.5,false),"RGB must contain exactly 24 bits");
        for(double amount:new double[]{-.001,1.001,Double.NaN,Double.POSITIVE_INFINITY,Double.NEGATIVE_INFINITY})expectInvalid(()->SkinTone.custom(0,amount,false),"invalid strength rejected");
        PhotoPortrait.Face old=face(),marked=old.withTone(t).withBodySkinMask(body());
        check(old.tone==PhotoPortrait.Tone.NONE&&old.bodySkinMask==null,"old constructor defaults are neutral");
        PhotoPortrait.Landmarks mesh=PortraitLandmarkMaskTest.mesh(1.4);
        PhotoPortrait.SkinMask skin=skin();
        List<PhotoPortrait.Face> copies=List.of(marked.withSettings(new PhotoPortrait.Settings(2,3,4,5,60,7,8)),marked.withEnabled(false),marked.withSkin(180,130,100),marked.withBounds(.6,.4,.14,.21,32),marked.withStrokes(List.of(stroke(.4,.5,false))),marked.withLandmarks(mesh),marked.withLandmarks(null),marked.withSkinMask(skin),marked.withSkinMask(null),marked.addStroke(stroke(.4,.5,false)),marked.clearStrokes());
        for(PhotoPortrait.Face copy:copies)check(copy.tone==t&&copy.bodySkinMask==marked.bodySkinMask,"all existing face copy methods retain tone and full-image raster");
        check(marked.withTone(PhotoPortrait.Tone.NONE).bodySkinMask==marked.bodySkinMask&&marked.withBodySkinMask(null).tone==t,"independent replacement retains the other field");
        PhotoPortrait.Face moved=marked.withBounds(.6,.4,.14,.21,32);
        near(moved.bodySkinMask.weight(.2,.8),marked.bodySkinMask.weight(.2,.8),0,"body confidence stays in full-image coordinates after face move");
        check(!portrait(marked).isNeutral()&&portrait(marked.withEnabled(false)).isNeutral()&&portrait(marked.withTone(SkinTone.preset(0,1,true))).isNeutral(),"portrait operation scheduling includes active tone and respects original/disabled");
        expectNull(()->marked.withTone(null),"tone cannot be null");
    }
    private static void bodySampling()throws Exception {
        byte[] p=new byte[128*128];for(int y=0;y<128;y++)for(int x=0;x<128;x++)p[y*128+x]=(byte)(x+y);
        PhotoPortrait.BodySkinMask mask=new PhotoPortrait.BodySkinMask(p);p[0]=99;
        near(mask.weight(.5/128,.5/128),0,0,"constructor copies body raster");
        byte[] q=mask.copyCoverage();q[128+1]=99;near(mask.weight(1.5/128,1.5/128),2/255.0,1e-15,"body accessor is a defensive copy");
        near(mask.weight(37.5/128,62.5/128),99/255.0,1e-15,"body pixel-center sampling uses unsigned confidence");
        near(mask.weight(37.75/128,62.125/128),(37.25+61.625)/255,1e-15,"body interpolation reproduces an affine field");
        near(mask.weight(0,0),0,0,"left top samples clamp to edge texel");near(mask.weight(1,1),254/255.0,1e-15,"right bottom samples clamp to edge texel");
        for(double[] xy:new double[][]{{-.001,.5},{1.001,.5},{.5,-.001},{.5,1.001},{Double.NaN,.5},{.5,Double.POSITIVE_INFINITY}})near(mask.weight(xy[0],xy[1]),0,0,"body rejects out-of-frame or nonfinite query");
        byte[] four=new byte[128*128];four[60*128+40]=10;four[60*128+41]=110;four[61*128+40]=(byte)210;four[61*128+41]=(byte)250;
        near(new PhotoPortrait.BodySkinMask(four).weight(40.75/128,61.25/128),173.75/255,1e-15,"explicit four-neighbour bilinear oracle");
        byte[] same=new byte[128*128];for(int y=0;y<128;y++)for(int x=0;x<128;x++)same[y*128+x]=(byte)(x+y);
        check(mask.equals(new PhotoPortrait.BodySkinMask(same))&&mask.hashCode()==new PhotoPortrait.BodySkinMask(same).hashCode(),"body raster value equality and hash");same[100]++;
        check(!mask.equals(new PhotoPortrait.BodySkinMask(same)),"body confidence participates in value state");
        expectInvalid(()->new PhotoPortrait.BodySkinMask(null),"null body raster rejected");expectInvalid(()->new PhotoPortrait.BodySkinMask(new byte[16383]),"short body raster rejected");expectInvalid(()->new PhotoPortrait.BodySkinMask(new byte[16385]),"long body raster rejected");
    }
    private static void compatibility()throws Exception {
        PhotoPortrait.Face base=face().withLandmarks(PortraitLandmarkMaskTest.mesh(1.4)).withSkinMask(skin()).addStroke(stroke(.4,.5,false));
        PhotoPortrait old=new PhotoPortrait(List.of(base),List.of(new PhotoPortrait.Heal(.1,.2,.3,.4,.03,.5,true)));
        for(int version:new int[]{1,2}) {
            PhotoPortrait restored=read(legacy(old,version));PhotoPortrait.Face f=restored.faces().get(0);
            check(f.tone==PhotoPortrait.Tone.NONE&&f.bodySkinMask==null,"version "+version+" migrates to neutral tone without inventing body confidence");
            check(f.cx==base.cx&&f.roll==base.roll&&f.settings.equals(base.settings)&&f.strokes.equals(base.strokes)&&restored.heals().equals(old.heals()),"version "+version+" preserves authored old fields");
            check(version==1?f.landmarks==null&&f.skinMask==null:f.landmarks.equals(base.landmarks)&&f.skinMask.equals(base.skinMask),"version "+version+" preserves its own optional payload layout");
            check(read(bytes(restored)).equals(restored),"version "+version+" migration can be saved in v3");
        }
        PhotoPortrait.Face marked=base.withTone(SkinTone.custom(0x9c6d50,.73,true)).withBodySkinMask(body());
        PhotoPortrait current=new PhotoPortrait(List.of(face(),base,marked.withBodySkinMask(null),marked.withTone(PhotoPortrait.Tone.NONE),marked),old.heals());
        byte[] encoded=bytes(current);PhotoPortrait restored=read(encoded);
        check(ByteBuffer.wrap(encoded).getInt(4)==4&&current.identity().startsWith("portrait-v4:"),"writer and identity are version4");
        check(restored.equals(current)&&restored.hashCode()==current.hashCode()&&Arrays.equals(bytes(restored),encoded),"mixed v4 per-person tone/body payloads roundtrip canonically");
        check(!portrait(marked).identity().equals(portrait(marked.withTone(SkinTone.custom(0x9c6d51,.73,true))).identity()),"tone changes invalidate cached render identity");
        check(!portrait(marked).identity().equals(portrait(marked.withBodySkinMask(null)).identity()),"body confidence changes invalidate cached render identity");
        byte[] one=bytes(portrait(face().withTone(SkinTone.preset(1,.7,true)).withBodySkinMask(body())));
        int tone=99;
        for(int id:new int[]{-1,11}){byte[] bad=one.clone();ByteBuffer.wrap(bad).putInt(tone,id);expectIo(()->read(bad),"invalid stored tone identifier rejected");}
        for(int rgb:new int[]{-1,0x1000000}){byte[] bad=one.clone();ByteBuffer.wrap(bad).putInt(tone+4,rgb);expectIo(()->read(bad),"invalid stored target RGB rejected");}
        for(double amount:new double[]{-.1,1.1,Double.NaN,Double.POSITIVE_INFINITY}){byte[] bad=one.clone();ByteBuffer.wrap(bad).putDouble(tone+8,amount);expectIo(()->read(bad),"invalid stored strength rejected");}
        for(int offset:new int[]{tone+16,tone+17}){byte[] bad=one.clone();bad[offset]=2;expectIo(()->read(bad),"noncanonical v3 boolean rejected");}
        for(int size:new int[]{tone+1,tone+12,tone+17,tone+18,tone+100,one.length-5,one.length-1})expectIo(()->read(Arrays.copyOf(one,size)),"truncated tone/body payload rejected");
        byte[] future=one.clone();ByteBuffer.wrap(future).putInt(4,5);expectIo(()->read(future),"future portrait version rejected");
        ArrayList<PhotoPortrait.Face> maximum=new ArrayList<>();int remaining=PhotoPortrait.MAX_TOTAL_POINTS;
        for(int f=0;f<PhotoPortrait.MAX_FACES;f++) {
            PhotoPortrait.Face value=marked.clearStrokes();while(remaining>0&&value.strokes.size()<(f<4?6:5)){double[] points=new double[128*2];Arrays.fill(points,.5);value=value.addStroke(new PhotoPortrait.Stroke(points,.02,.5,false));remaining-=points.length/2;}maximum.add(value);
        }
        maximumPortrait=new PhotoPortrait(maximum,Collections.nCopies(64,old.heals().get(0)));byte[] max=bytes(maximumPortrait);
        check(remaining==0&&max.length>512*1024&&max.length<1024*1024&&read(max).faces().size()==12,"maximal twelve meshes, two rasters, 64 strokes, 8192 points and 64 heals fit the enlarged bounded draft budget");
    }
    private static void nestedDraft()throws Exception {
        PhotoPortrait.Face face=face().withTone(SkinTone.custom(0x8d6046,.86,true)).withBodySkinMask(body()).withSkinMask(skin());
        PhotoLocalEdits local=new PhotoLocalEdits(List.of(PhotoLocalEdits.Mask.radial(.3,.4).parameters(6,7,-8)),List.of(new PhotoLocalEdits.Clone(.1,.2,.5,.6,.04,.6,true)),portrait(face));
        ByteArrayOutputStream b=new ByteArrayOutputStream();local.write(new DataOutputStream(b));PhotoLocalEdits restored=PhotoLocalEdits.read(new DataInputStream(new ByteArrayInputStream(b.toByteArray())));
        check(local.equals(restored)&&local.identity().equals(restored.identity()),"nested state preserves tone, body confidence, local masks and clones");
        Path temp=Files.createTempDirectory("portrait-tone-model-");
        try {
            String sha="e".repeat(64);PhotoEditStore store=new PhotoEditStore(temp.toFile(),"tone-owner");PhotoEditStore.Draft draft=draft(sha,local);store.save(draft);
            check(store.read(sha).localEdits.equals(local)&&store.read(sha).identity().equals(draft.identity()),"owner draft persists exact tone and full-image confidence");
            check(new PhotoEditStore(temp.toFile(),"other-owner").read(sha)==null,"tone drafts remain owner scoped");
            PhotoLocalEdits next=local.withPortrait(portrait(face.withTone(SkinTone.custom(0x8d6046,.85,true))));PhotoEditStore.Draft newer=draft(sha,next);store.save(newer);store.markExported(draft);
            check(!store.read(sha).exported&&!store.replace(sha,draft,draft),"stale tone snapshot cannot mark or replace a newer edit");
            store.markExported(newer);check(store.read(sha).exported&&store.read(sha).localEdits.equals(next),"matching tone export preserves exact stored state");
            double[] points=new double[1024];Arrays.fill(points,.5);
            PhotoLocalEdits maximum=new PhotoLocalEdits(Collections.nCopies(16,PhotoLocalEdits.Mask.brush(points,.02,.5)),Collections.nCopies(64,new PhotoLocalEdits.Clone(.1,.2,.5,.6,.04,.6,true)),maximumPortrait);
            String maxSha="d".repeat(64);store.save(draft(maxSha,maximum));
            check(store.read(maxSha).localEdits.equals(maximum),"complete worst-case twelve-person draft saves and restores all local and portrait payloads");
            long largest;try(var files=Files.walk(temp)){largest=files.filter(Files::isRegularFile).mapToLong(p->{try{return Files.size(p);}catch(IOException e){throw new UncheckedIOException(e);}}).max().orElseThrow();}
            maximumDraftBytes=largest;
            check(largest>512*1024&&largest+1024*1024<2*1024*1024,"actual maximum edit metadata leaves room for the full recipe limit under the new two-MiB cap");
        } finally {try(var files=Files.walk(temp)){for(Path p:files.sorted(Comparator.reverseOrder()).toList())Files.delete(p);}}
    }
    private static void colourInvariants()throws Exception {
        int[] colours={0,0x00123456,0x80000000,0xffffffff,0xffbf987a,0xff7d593f,0xffd2b398,0x126c452d};
        for(PhotoPortrait.Tone neutral:List.of(PhotoPortrait.Tone.NONE,SkinTone.preset(0,1,true),SkinTone.custom(0xffffff,0,true),SkinTone.custom(0,0,false))) {
            SkinTone.Transform t=new SkinTone.Transform(neutral,191,152,122);boolean unchanged=true;for(int c:colours)unchanged&=c==t.apply(c,1);check(unchanged,"neutral tone is bit-exact for dark light transparent and partial-alpha pixels");
        }
        SkinTone.Transform same=new SkinTone.Transform(SkinTone.custom(SKIN&0xffffff,1,false),191,152,122);
        boolean unchanged=true;for(int c:colours)unchanged&=c==same.apply(c,1);check(unchanged,"a target equal to the sampled skin is an exact identity for every pixel");
        for(SkinTone.Entry e:SkinTone.presets().subList(1,10)) {
            SkinTone.Transform t=new SkinTone.Transform(SkinTone.preset(e.id,1,false),191,152,122);
            double previous=-1,first=0,last=0;boolean increasing=true,alpha=true;
            for(int i=0;i<12;i++){int c=0x80000000|((55+i*15)<<16)|((40+i*14)<<8)|(30+i*13),out=t.apply(c,1);double y=luminance(out);if(i==0)first=y;last=y;increasing&=y>previous+1;previous=y;alpha&=(out>>>24)==128;}
            check(increasing&&last-first>90,"maximum-strength preset retains ordered shadows and highlight contrast "+e.id);
            check(alpha,"tone retains partial alpha "+e.id);
            int grainLow=t.apply(0xffbf987a,1),grainHigh=t.apply(0xffc19a7c,1);check(luminance(grainHigh)>luminance(grainLow)+.5,"fine luminance texture survives maximum strength "+e.id);
            int input=SKIN,half=new SkinTone.Transform(SkinTone.preset(e.id,.5,false),191,152,122).apply(input,1),full=t.apply(input,1);
            check(distance(input,half)<=distance(input,full)+1&&distance(input,full)>0,"strength grows from original toward preset "+e.id);
        }
        for(int target:new int[]{0,0xffffff,0xff0000,0x00ff00,0x0000ff,0xff00ff}) {
            SkinTone.Transform t=new SkinTone.Transform(SkinTone.custom(target,1,false),191,152,122);double previous=-1;boolean monotonic=true;
            for(int i=1;i<15;i++){int v=16*i,c=0xff000000|(v<<16)|(v<<8)|v,out=t.apply(c,1);double y=luminance(out);monotonic&=y>previous;previous=y;}
            check(monotonic,"extreme custom colour keeps lightness order "+target);
            // Gamut compression can approach a gamut edge; it must not flatten a channel there.
            int low=t.apply(0xff555555,1),high=t.apply(0xffaaaaaa,1);check(luminance(high)-luminance(low)>35,"custom target retains broad source contrast "+target);
            check(t.apply(0x00123456,1)==0x00123456,"transparent hidden RGB remains untouched "+target);
            double h1=hue(t.apply(0xff555555,1)),h2=hue(t.apply(0xff888888,1)),h3=hue(t.apply(0xffbbbbbb,1));
            check(hueDistance(h1,h2)<.12&&hueDistance(h2,h3)<.12,"gamut compression retains perceptual hue across different lightnesses "+target);
        }
        check(new SkinTone.Transform(SkinTone.custom(0xedb3aa,1,false),191,152,122).apply(SKIN,1)!=new SkinTone.Transform(SkinTone.custom(0x95704e,1,false),191,152,122).apply(SKIN,1),"custom colours have distinct rendered effects");
    }
    private static void rendering()throws Exception {
        PhotoPortrait.Face f=face().withBounds(.52,.3,.11,.14,17).withLandmarks(PortraitLandmarkMaskTest.mesh(1.4)).withSkinMask(skin()).withBodySkinMask(body());
        Raster source=image(224,160),neutral=source.copy();ArrayList<Double> progress=new ArrayList<>();
        PortraitPreviewFilter.apply(neutral,portrait(f.withTone(SkinTone.preset(0,1,true))),()->false,progress::add);
        exact(source.data,neutral.data,"original tone render is a strict no-op");check(neutral.reads==0&&neutral.writes==0,"neutral tone avoids pixel IO");
        Raster zero=source.copy();PortraitPreviewFilter.apply(zero,portrait(f.withTone(SkinTone.preset(6,0,true))),()->false,null);exact(source.data,zero.data,"zero-strength render is a strict no-op");
        PhotoPortrait.Face faceOnly=f.withTone(SkinTone.preset(2,.8,false)),whole=f.withTone(SkinTone.preset(2,.8,true));
        Raster a=source.copy(),b=source.copy();PortraitPreviewFilter.apply(a,portrait(faceOnly),()->false,null);PortraitPreviewFilter.apply(b,portrait(whole),()->false,null);
        int bodyIndex=(int)(.8*source.h)*source.w+(int)(.2*source.w),background=source.w*source.h-1;
        check(a.data[bodyIndex]==source.data[bodyIndex]&&b.data[bodyIndex]!=source.data[bodyIndex],"full-body tone reaches skin beyond the old face render bounds");
        check(b.data[background]==source.data[background]&&b.data[0]==source.data[0],"zero semantic background stays unchanged");
        PhotoPortrait.Face withSettings=whole.withSettings(new PhotoPortrait.Settings(35,25,30,55,20,60,80));Raster c=source.copy();PortraitPreviewFilter.apply(c,portrait(withSettings),()->false,null);
        check(c.data[bodyIndex]==b.data[bodyIndex],"body skin receives tone only, with no face brightness warmth smoothing or light");
        int changedFace=0,changedBody=0;for(int y=0;y<source.h;y++)for(int x=0;x<source.w;x++){int i=y*source.w+x;if(a.data[i]!=source.data[i])changedFace++;if(b.data[i]!=a.data[i])changedBody++;}check(changedFace>200&&changedBody>200,"both face and body actually render a meaningful area");
        PhotoPortrait.BodySkinMask everywhere=new PhotoPortrait.BodySkinMask(filled());PhotoPortrait.Face protectedFace=whole.withBodySkinMask(everywhere);
        PortraitPreviewFilter.Mask mask=PortraitPreviewFilter.mask(protectedFace,source.w,source.h);
        for(double[] uv:new double[][]{{-.58,-.06},{.60,-.08},{-.55,-.27},{.58,-.30},{0,.78}}){double[] xy=world(protectedFace,uv[0],uv[1],source.w,source.h);near(mask.toneWeight(SKIN,xy[0],xy[1]),0,0,"body confidence cannot reopen protected face features");}
        double[] hole={.2,.8};PhotoPortrait.Face erased=whole.addStroke(stroke(hole[0],hole[1],true));near(PortraitPreviewFilter.mask(erased,224,160).toneWeight(SKIN,hole[0],hole[1]),0,0,"erase stroke removes body tone coverage");
        PhotoPortrait.Face added=erased.addStroke(stroke(hole[0],hole[1],false));near(PortraitPreviewFilter.mask(added,224,160).toneWeight(SKIN,hole[0],hole[1]),1,0,"later add restores body tone coverage");
        Raster erasedPixels=source.copy();PortraitPreviewFilter.apply(erasedPixels,portrait(erased),()->false,null);check(erasedPixels.data[bodyIndex]==source.data[bodyIndex],"body erase reaches rendered pixels");
        PhotoPortrait.Face noBody=whole.withBodySkinMask(null);Raster fallback=source.copy();PortraitPreviewFilter.apply(fallback,portrait(noBody),()->false,null);exact(a.data,fallback.data,"body scope without semantic body data safely retains face-only rendering");
        Raster disabled=source.copy();PortraitPreviewFilter.apply(disabled,portrait(whole.withEnabled(false)),()->false,null);exact(source.data,disabled.data,"disabled person has no tone effect");
        PhotoPortrait.Face other=face().withBounds(.83,.32,.075,.10,-12).withSkinMask(skin());Raster multiple=source.copy();PortraitPreviewFilter.apply(multiple,new PhotoPortrait(List.of(whole,other),List.of()),()->false,null);exact(b.data,multiple.data,"a second neutral person does not alter first-person output");
        PhotoPortrait.Face onlySecond=other.withTone(SkinTone.preset(9,1,false));Raster firstNeutral=source.copy();PortraitPreviewFilter.apply(firstNeutral,new PhotoPortrait(List.of(f,onlySecond),List.of()),()->false,null);check(firstNeutral.data[bodyIndex]==source.data[bodyIndex],"second person's settings do not borrow first person's body mask");
        // Body texture lives in the oriented whole-image frame and must not rotate with face bounds.
        for(int[] size:new int[][]{{224,160},{160,224},{192,192}})for(double roll:new double[]{-42,0,38}) {
            PhotoPortrait.Face candidate=whole.withBounds(.52,.3,.11,.14,roll);PortraitPreviewFilter.Mask m=PortraitPreviewFilter.mask(candidate,size[0],size[1]);
            near(m.toneWeight(SKIN,.2,.8),1,0,"full-image body position independent of face roll and image aspect");near(m.weight(SKIN,.2,.8),0,0,"ordinary face adjustment mask never expands to body");
        }
        Raster canonical=source.copy();PortraitPreviewFilter.apply(canonical,portrait(withSettings),1,()->false,null);
        for(int exif=1;exif<=8;exif++){Raster raw=raw(source,exif);PortraitPreviewFilter.apply(raw,portrait(withSettings),exif,()->false,null);exact(canonical.data,oriented(raw,exif).data,"tone and body are identical under EXIF orientation "+exif);}
        AtomicInteger cancelled=new AtomicInteger();expectIo(()->PortraitPreviewFilter.apply(source.copy(),portrait(whole),()->cancelled.incrementAndGet()>6,null),"tone-only operation remains cancellable");
        progress.clear();PortraitPreviewFilter.apply(source.copy(),portrait(whole),()->false,progress::add);boolean ordered=progress.get(0)==0&&progress.get(progress.size()-1)==1;for(int i=1;i<progress.size();i++)ordered&=progress.get(i)>=progress.get(i-1);check(ordered,"tone-only progress is monotonic and reaches completion");
    }
    private static PhotoPortrait.Face face(){return new PhotoPortrait.Face(.5,.4,.12,.2,0,191,152,122,true,PhotoPortrait.Settings.NONE,List.of());}
    private static PhotoPortrait portrait(PhotoPortrait.Face f){return new PhotoPortrait(List.of(f),List.of());}
    private static PhotoPortrait.SkinMask skin(){return new PhotoPortrait.SkinMask(-1.5,-2,1.5,1.6,filled());}
    private static byte[] filled(){byte[] p=new byte[16384];Arrays.fill(p,(byte)255);return p;}
    private static PhotoPortrait.BodySkinMask body(){byte[] p=new byte[16384];for(int y=88;y<118;y++)for(int x=12;x<44;x++)p[y*128+x]=(byte)255;return new PhotoPortrait.BodySkinMask(p);}
    private static PhotoPortrait.Stroke stroke(double x,double y,boolean erase){return new PhotoPortrait.Stroke(new double[]{x,y},.035,.5,erase);}
    private static PhotoEditStore.Draft draft(String sha,PhotoLocalEdits local)throws IOException{return new PhotoEditStore.Draft(sha,null,"合成肤色测试",0,PhotoAdjustments.NONE,PhotoGeometry.NONE,PhotoBorder.NONE,local,false);}
    private static double[] world(PhotoPortrait.Face f,double u,double v,int w,int h){double a=Math.toRadians(f.roll),x=u*f.rx*w,y=v*f.ry*h;return new double[]{f.cx+(Math.cos(a)*x-Math.sin(a)*y)/w,f.cy+(Math.sin(a)*x+Math.cos(a)*y)/h};}
    private static double luminance(int c){return (((c>>>16)&255)*.2126+((c>>>8)&255)*.7152+(c&255)*.0722);}
    /** Independent sRGB->XYZ->Oklab path, used only to observe hue, not mirror adaptation. */
    private static double hue(int c){
        double r=linear((c>>>16)&255),g=linear((c>>>8)&255),b=linear(c&255);
        double x=.4124564*r+.3575761*g+.1804375*b,y=.2126729*r+.7151522*g+.0721750*b,z=.0193339*r+.1191920*g+.9503041*b;
        double l=Math.cbrt(.8189330101*x+.3618667424*y-.1288597137*z),m=Math.cbrt(.0329845436*x+.9293118715*y+.0361456387*z),s=Math.cbrt(.0482003018*x+.2643662691*y+.6338517070*z);
        return Math.atan2(.0259040371*l+.7827717662*m-.808675766*s,1.9779984951*l-2.428592205*m+.4505937099*s);
    }
    private static double linear(int channel){double x=channel/255.0;return x<=.04045?x/12.92:Math.pow((x+.055)/1.055,2.4);}
    private static double hueDistance(double a,double b){double d=Math.abs(a-b);return Math.min(d,2*Math.PI-d);}
    private static int distance(int a,int b){return Math.abs(((a>>>16)&255)-((b>>>16)&255))+Math.abs(((a>>>8)&255)-((b>>>8)&255))+Math.abs((a&255)-(b&255));}
    private static byte[] bytes(PhotoPortrait value)throws IOException{ByteArrayOutputStream b=new ByteArrayOutputStream();value.write(new DataOutputStream(b));return b.toByteArray();}
    private static PhotoPortrait read(byte[] value)throws IOException{return PhotoPortrait.read(new DataInputStream(new ByteArrayInputStream(value)));}
    /** Frozen published v1/v2/v3 layout, independent of the current v4 writer. */
    static byte[] legacy(PhotoPortrait value,int version)throws IOException {
        ByteArrayOutputStream bytes=new ByteArrayOutputStream();DataOutputStream out=new DataOutputStream(bytes);out.writeInt(0x50525431);out.writeInt(version);out.writeInt(value.faces().size());
        for(PhotoPortrait.Face f:value.faces()) {
            for(double d:new double[]{f.cx,f.cy,f.rx,f.ry,f.roll})out.writeDouble(d);out.writeInt(f.skinR);out.writeInt(f.skinG);out.writeInt(f.skinB);out.writeBoolean(f.enabled);
            PhotoPortrait.Settings s=f.settings;for(int n:new int[]{s.brightness,s.warmth,s.redness,s.smoothing,s.texture,s.light,s.shadows})out.writeInt(n);
            out.writeInt(f.strokes.size());for(PhotoPortrait.Stroke stroke:f.strokes){out.writeDouble(stroke.radius);out.writeDouble(stroke.feather);out.writeBoolean(stroke.erase);double[] points=stroke.points();out.writeInt(points.length);for(double point:points)out.writeDouble(point);}
            if(version>=2){out.writeBoolean(f.landmarks!=null);if(f.landmarks!=null)for(double d:f.landmarks.copyPoints())out.writeDouble(d);out.writeBoolean(f.skinMask!=null);if(f.skinMask!=null){for(double d:new double[]{f.skinMask.left,f.skinMask.top,f.skinMask.right,f.skinMask.bottom})out.writeDouble(d);out.write(f.skinMask.copyCoverage());}}
            if(version>=3){out.writeInt(f.tone.presetId);out.writeInt(f.tone.colorRGB);out.writeDouble(f.tone.amount);out.writeBoolean(f.tone.body);out.writeBoolean(f.bodySkinMask!=null);if(f.bodySkinMask!=null)out.write(f.bodySkinMask.copyCoverage());}
        }
        out.writeInt(value.heals().size());for(PhotoPortrait.Heal h:value.heals()){for(double d:new double[]{h.sx,h.sy,h.tx,h.ty,h.radius,h.feather})out.writeDouble(d);out.writeBoolean(h.enabled);}return bytes.toByteArray();
    }
    private static Raster image(int w,int h){Raster r=new Raster(w,h);for(int y=0;y<h;y++)for(int x=0;x<w;x++){int d=(x+y)%17-8;r.data[y*w+x]=0xff000000|((191+d)<<16)|((152+d)<<8)|(122+d);}r.data[0]=0x00123456;return r;}
    private static Raster raw(Raster canonical,int e){Raster r=new Raster(e>=5?canonical.h:canonical.w,e>=5?canonical.w:canonical.h);for(int y=0;y<r.h;y++)for(int x=0;x<r.w;x++)r.data[y*r.w+x]=canonical.data[oy(x,y,r.w,r.h,e)*canonical.w+ox(x,y,r.w,r.h,e)];return r;}
    private static Raster oriented(Raster raw,int e){Raster r=new Raster(e>=5?raw.h:raw.w,e>=5?raw.w:raw.h);for(int y=0;y<raw.h;y++)for(int x=0;x<raw.w;x++)r.data[oy(x,y,raw.w,raw.h,e)*r.w+ox(x,y,raw.w,raw.h,e)]=raw.data[y*raw.w+x];return r;}
    private static int ox(int x,int y,int w,int h,int e){switch(e){case 2:case 3:return w-1-x;case 5:case 8:return y;case 6:case 7:return h-1-y;default:return x;}}
    private static int oy(int x,int y,int w,int h,int e){switch(e){case 3:case 4:return h-1-y;case 5:case 6:return x;case 7:case 8:return w-1-x;default:return y;}}
    private static final class Raster implements SpatialPreviewFilter.Pixels {
        final int w,h;final int[] data;int reads,writes;Raster(int w,int h){this.w=w;this.h=h;data=new int[w*h];}Raster copy(){Raster r=new Raster(w,h);System.arraycopy(data,0,r.data,0,data.length);return r;}public int width(){return w;}public int height(){return h;}public void read(int[] p,int row,int rows){reads++;System.arraycopy(data,row*w,p,0,rows*w);}public void write(int[] p,int row,int rows){writes++;System.arraycopy(p,0,data,row*w,rows*w);}
    }
    private interface Action{void run()throws Exception;}
    private static void expectInvalid(Action a,String name)throws Exception{try{a.run();throw new AssertionError(name);}catch(IllegalArgumentException expected){checks++;}}
    private static void expectUnsupported(Action a,String name)throws Exception{try{a.run();throw new AssertionError(name);}catch(UnsupportedOperationException expected){checks++;}}
    private static void expectNull(Action a,String name)throws Exception{try{a.run();throw new AssertionError(name);}catch(NullPointerException expected){checks++;}}
    private static void expectIo(Action a,String name)throws Exception{try{a.run();throw new AssertionError(name);}catch(IOException expected){checks++;}}
    private static void exact(int[] a,int[] b,String name){checks++;if(!Arrays.equals(a,b)){int i=0;while(i<a.length&&a[i]==b[i])i++;throw new AssertionError(name+" at "+i+" expected="+Integer.toHexString(a[i])+" actual="+Integer.toHexString(b[i]));}}
    private static void near(double a,double b,double e,String name){checks++;if(!Double.isFinite(a)||Math.abs(a-b)>e)throw new AssertionError(name+" "+a+" != "+b);}
    private static void check(boolean ok,String name){checks++;if(!ok)throw new AssertionError(name);}
}
