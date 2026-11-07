package cc.huevia.ncp;

import cc.huevia.album.PhotoEditStore;
import java.io.*;
import java.nio.ByteBuffer;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.atomic.AtomicInteger;

/** Whole-image skin-tone tests start with no detected or selected faces. */
public final class PortraitGlobalToneTest {
    private static int checks;
    private static final int SKIN=0xffbf987a;
    private static int maximumPortraitBytes;
    private static long maximumDraftBytes;
    public static void main(String[] args)throws Exception {
        state(); wire(); draft(); noFacePixels(); protectedFeatures(); orientations(); lifetime();
        System.out.println("PASS PortraitGlobalToneTest "+checks+" checks");
        System.out.println("DETAIL globalMaximumPortraitBytes="+maximumPortraitBytes+" globalMaximumDraftBytes="+maximumDraftBytes);
    }
    private static void state()throws Exception {
        PhotoPortrait.Tone tone=SkinTone.preset(6,.8,false);PhotoPortrait.BodySkinMask mask=skin();
        check(PhotoPortrait.NONE.globalTone==PhotoPortrait.Tone.NONE&&PhotoPortrait.NONE.globalSkinMask==null,"legacy constructor defaults remain global-neutral");
        PhotoPortrait waiting=PhotoPortrait.NONE.withGlobalTone(tone),global=waiting.withGlobalSkinMask(mask);
        check(waiting.faces().isEmpty()&&!waiting.isEmpty()&&waiting.isNeutral(),"empty-face pending tone persists without rendering before mask exists");
        check(global.faces().isEmpty()&&global.heals().isEmpty()&&!global.isEmpty()&&!global.isNeutral(),"global tone becomes active without any face");
        check(global.globalTone==tone&&global.globalSkinMask==mask,"global state retains immutable tone and confidence objects");
        check(!PhotoPortrait.NONE.withGlobalSkinMask(mask).isEmpty()&&PhotoPortrait.NONE.withGlobalSkinMask(mask).isNeutral(),"analysis mask alone is preservable neutral state");
        check(global.withGlobalTone(PhotoPortrait.Tone.NONE).isNeutral()&&global.withGlobalSkinMask(null).isNeutral(),"original and pending-mask global state are neutral");
        check(global.equals(PhotoPortrait.NONE.withGlobalSkinMask(mask).withGlobalTone(tone))&&global.hashCode()==PhotoPortrait.NONE.withGlobalSkinMask(mask).withGlobalTone(tone).hashCode(),"global values participate in portrait equality and hash");
        check(!global.equals(global.withGlobalTone(SkinTone.preset(6,.7,false))),"global colour participates in value state");
        check(!global.identity().equals(global.withGlobalTone(SkinTone.preset(6,.7,false)).identity()),"global strength changes render identity");
        check(!global.identity().equals(global.withGlobalSkinMask(new PhotoPortrait.BodySkinMask(filled())).identity()),"global confidence changes render identity");
        PhotoPortrait.Face neutral=face(),other=neutral.withBounds(.8,.4,.09,.1,-13);
        PhotoPortrait withFace=global.addFace(neutral);PhotoPortrait.Heal heal=new PhotoPortrait.Heal(.1,.2,.6,.7,.03,.6,true);
        for(PhotoPortrait copy:List.of(withFace.withFace(0,neutral.withSettings(new PhotoPortrait.Settings(12,0,0,0,70,0,0))),withFace.withFaces(List.of(other)),withFace.addFace(other),withFace.removeFace(0),withFace.addHeal(heal),withFace.addHeal(heal).removeHeal(0)))
            check(copy.globalTone==tone&&copy.globalSkinMask==mask,"face and heal copy operations preserve independent global state");
        PhotoPortrait.Face person=neutral.withTone(SkinTone.preset(9,.6,true)).withBodySkinMask(mask).addStroke(new PhotoPortrait.Stroke(new double[]{.2,.3},.03,.5,false));
        PhotoPortrait old=new PhotoPortrait(List.of(person,person.withTone(SkinTone.preset(2,0,false))),List.of(heal));
        for(PhotoPortrait.Tone selected:List.of(tone,PhotoPortrait.Tone.NONE,SkinTone.preset(0,1,true),SkinTone.preset(2,0,false))) {
            PhotoPortrait chosen=old.withGlobalTone(selected);
            check(chosen.faces().stream().allMatch(f->f.tone==PhotoPortrait.Tone.NONE),"choosing global original/zero/active clears every per-person tone");
            check(chosen.faces().get(0).bodySkinMask==person.bodySkinMask&&chosen.faces().get(0).strokes.equals(person.strokes)&&chosen.heals().equals(old.heals()),"global mode changes only prior target colours");
        }
        check(old.faces().get(0).tone==person.tone,"switching mode does not mutate the undo snapshot");
        for(PhotoPortrait personal:List.of(withFace.withFace(0,person),global.withFaces(List.of(person)),global.addFace(person)))
            check(personal.globalTone==PhotoPortrait.Tone.NONE&&personal.globalSkinMask==mask&&!personal.faces().get(0).tone.isNeutral(),"explicit personal colour disables global colour while retaining mask cache");
        expectNull(()->global.withGlobalTone(null),"global tone cannot be null");expectNull(()->global.withFaces(null),"replacement faces cannot be null");
        expectInvalid(()->global.withFaces(Collections.nCopies(13,neutral)),"replacement faces remain bounded");
    }
    private static void wire()throws Exception {
        PhotoPortrait.Face full=face().withSettings(new PhotoPortrait.Settings(13,4,-3,18,68,8,7)).withLandmarks(PortraitLandmarkMaskTest.mesh(1.4)).withSkinMask(new PhotoPortrait.SkinMask(-1.5,-2,1.5,1.6,filled())).withBodySkinMask(skin()).withTone(SkinTone.custom(0x98684c,.6,true)).addStroke(new PhotoPortrait.Stroke(new double[]{.3,.4,.32,.43},.02,.7,true));
        PhotoPortrait old=new PhotoPortrait(List.of(full),List.of(new PhotoPortrait.Heal(.1,.2,.6,.7,.03,.5,true)));
        for(int version:new int[]{1,2,3}) {
            PhotoPortrait restored=read(PortraitToneTest.legacy(old,version));PhotoPortrait.Face f=restored.faces().get(0);
            check(restored.globalTone==PhotoPortrait.Tone.NONE&&restored.globalSkinMask==null,"published v"+version+" migrates without invented global state");
            check(restored.heals().equals(old.heals())&&f.settings.equals(full.settings)&&f.strokes.equals(full.strokes)&&f.cx==full.cx&&f.roll==full.roll,"published v"+version+" retains old authored state");
            check(version<2?f.landmarks==null&&f.skinMask==null:f.landmarks.equals(full.landmarks)&&f.skinMask.equals(full.skinMask),"published v"+version+" retains its mesh and face-mask layout");
            check(version<3?f.tone==PhotoPortrait.Tone.NONE&&f.bodySkinMask==null:f.tone.equals(full.tone)&&f.bodySkinMask.equals(full.bodySkinMask),"published v"+version+" retains individual tone and body layout");
            check(read(bytes(restored)).equals(restored),"published v"+version+" can be resaved as v4 without state loss");
        }
        PhotoPortrait global=PhotoPortrait.NONE.withGlobalTone(SkinTone.custom(0xcda089,.67,false)).withGlobalSkinMask(skin());
        byte[] encoded=bytes(global);PhotoPortrait restored=read(encoded);
        check(ByteBuffer.wrap(encoded).getInt(4)==4&&global.identity().startsWith("portrait-v4:"),"global writer and identity use version4");
        check(restored.equals(global)&&restored.faces().isEmpty()&&Arrays.equals(encoded,bytes(restored))&&restored.identity().equals(global.identity()),"empty-face v4 global bytes roundtrip canonically");
        for(PhotoPortrait variant:List.of(global,global.withGlobalSkinMask(null),global.withGlobalTone(PhotoPortrait.Tone.NONE),global.addFace(full.withTone(PhotoPortrait.Tone.NONE))))check(read(bytes(variant)).equals(variant),"optional v4 global values roundtrip independently");
        for(int offset:new int[]{32,33}){byte[] bad=encoded.clone();bad[offset]=2;expectIo(()->read(bad),"strict global booleans rejected");}
        for(int rgb:new int[]{-1,0x1000000}){byte[] bad=encoded.clone();ByteBuffer.wrap(bad).putInt(20,rgb);expectIo(()->read(bad),"invalid global target RGB rejected");}
        for(double amount:new double[]{-.1,1.1,Double.NaN,Double.POSITIVE_INFINITY}){byte[] bad=encoded.clone();ByteBuffer.wrap(bad).putDouble(24,amount);expectIo(()->read(bad),"invalid global strength rejected");}
        for(int size:new int[]{0,4,8,12,16,17,24,32,33,34,100,encoded.length-1})expectIo(()->read(Arrays.copyOf(encoded,size)),"truncated global state rejected");
        byte[] future=encoded.clone();ByteBuffer.wrap(future).putInt(4,5);expectIo(()->read(future),"future portrait version rejected");
        byte[] layered=bytes(old);int globalOffset=PortraitToneTest.legacy(old,3).length;ByteBuffer.wrap(layered).putInt(globalOffset,1).putInt(globalOffset+4,0xe1bfa5).putDouble(globalOffset+8,.8);expectIo(()->read(layered),"invalid stored simultaneous global and individual colours rejected");
        PhotoLocalEdits local=new PhotoLocalEdits(List.of(),List.of(),global);ByteArrayOutputStream out=new ByteArrayOutputStream();local.write(new DataOutputStream(out));
        check(ByteBuffer.wrap(out.toByteArray()).getInt()==2&&PhotoLocalEdits.read(new DataInputStream(new ByteArrayInputStream(out.toByteArray()))).equals(local),"empty face list still selects nested portrait serialization");
    }
    private static void draft()throws Exception {
        PhotoPortrait global=global();PhotoLocalEdits local=new PhotoLocalEdits(List.of(),List.of(),global);Path temp=Files.createTempDirectory("portrait-global-tone-");
        try {
            PhotoEditStore store=new PhotoEditStore(temp.toFile(),"global-owner");String sha="c".repeat(64);PhotoEditStore.Draft snapshot=draft(sha,local);store.save(snapshot);
            check(store.read(sha).localEdits.equals(local)&&store.read(sha).localEdits.portrait.faces().isEmpty(),"zero-face global tone and confidence persist in actual draft");
            check(new PhotoEditStore(temp.toFile(),"different-owner").read(sha)==null,"whole-image skin edits remain owner scoped");
            PhotoLocalEdits next=local.withPortrait(global.withGlobalTone(SkinTone.preset(9,.4,true)));PhotoEditStore.Draft newer=draft(sha,next);store.save(newer);store.markExported(snapshot);
            check(!store.read(sha).exported&&!store.replace(sha,snapshot,snapshot),"stale global colour snapshot cannot mark export or replace a newer edit");
            store.markExported(newer);check(store.read(sha).exported&&store.read(sha).localEdits.equals(next),"matching global export preserves exact state");
            byte[] changed=global.globalSkinMask.copyCoverage();changed[90*128+20]=0;PhotoLocalEdits changedMask=next.withPortrait(next.portrait.withGlobalSkinMask(new PhotoPortrait.BodySkinMask(changed)));PhotoEditStore.Draft maskDraft=draft(sha,changedMask);store.save(maskDraft);store.markExported(newer);
            check(!store.read(sha).exported&&!store.replace(sha,newer,newer),"semantic-global-mask changes retain stale-export protection");
            Raster source=image(192,140,false),a=source.copy(),b=source.copy();PortraitPreviewFilter.apply(a,global,()->false,null);PortraitPreviewFilter.apply(b,read(bytes(global)),()->false,null);exact(a.data,b.data,"restored global draft renders exact pixels");
            Raster full=source.copy();snapshot.profile().renderPixels(full,()->false,null);exact(a.data,full.data,"actual persisted draft profile exports global skin colour with an empty face list");
            Raster localPixels=source.copy();LocalEditsPreviewProfile.renderLocal(localPixels,local,1,()->false,null);exact(a.data,localPixels.data,"local-edit wrapper invokes the identical empty-face global renderer");
            check(snapshot.hasEffect()&&!local.isNeutral()&&!snapshot.identity().equals(draft(sha,PhotoLocalEdits.NONE).identity()),"empty-face global tone changes edited-detail and export cache identity");
            // Cache coexistence and all existing maxima remain within the bounded edit budget.
            PhotoPortrait maximum=maximum();maximumPortraitBytes=bytes(maximum).length;double[] points=new double[1024];Arrays.fill(points,.5);PhotoLocalEdits maxLocal=new PhotoLocalEdits(Collections.nCopies(16,PhotoLocalEdits.Mask.brush(points,.02,.5)),Collections.nCopies(64,new PhotoLocalEdits.Clone(.1,.2,.5,.6,.04,.6,true)),maximum);
            String maxSha="b".repeat(64);store.save(draft(maxSha,maxLocal));check(store.read(maxSha).localEdits.equals(maxLocal),"maximum v4 portrait/global cache and local edits save and restore");
            long largest;try(var files=Files.walk(temp)){largest=files.filter(Files::isRegularFile).mapToLong(p->{try{return Files.size(p);}catch(IOException e){throw new UncheckedIOException(e);}}).max().orElseThrow();}
            maximumDraftBytes=largest;check(largest+1024*1024<2*1024*1024,"maximum v4 metadata plus maximum recipe remains under two-MiB draft cap");
        }finally{try(var files=Files.walk(temp)){for(Path p:files.sorted(Comparator.reverseOrder()).toList())Files.delete(p);}}
    }
    private static void noFacePixels()throws Exception {
        PhotoPortrait global=global();Raster source=image(240,180,false),actual=source.copy();PortraitPreviewFilter.apply(actual,global,()->false,null);
        check(global.faces().isEmpty(),"rendering global skin never invents selected faces");
        for(double[] point:new double[][]{{.2,.75},{.75,.8},{.5,.37},{.5,.15}}){int i=index(source,point[0],point[1]);check(actual.data[i]!=source.data[i],"disconnected exposed face, neck, arm or leg is tinted without a face seed");}
        boolean background=true,alpha=true;int changed=0;for(int y=0;y<source.h;y++)for(int x=0;x<source.w;x++){int i=y*source.w+x;double w=global.globalSkinMask.weight((x+.5)/source.w,(y+.5)/source.h);if(w==0)background&=actual.data[i]==source.data[i];if(actual.data[i]!=source.data[i])changed++;alpha&=(actual.data[i]>>>24)==(source.data[i]>>>24);}
        check(background&&changed>1500,"full-frame global renderer changes skin islands and leaves every zero-mask background pixel exact");check(alpha,"whole-image tone preserves all alpha values");
        Raster differentBackground=image(240,180,true),different=differentBackground.copy();PortraitPreviewFilter.apply(different,global,()->false,null);boolean referenceIndependent=true;
        for(int y=0;y<source.h;y++)for(int x=0;x<source.w;x++)if(global.globalSkinMask.weight((x+.5)/source.w,(y+.5)/source.h)>0)referenceIndependent&=actual.data[y*source.w+x]==different.data[y*source.w+x];
        check(referenceIndependent,"weighted source reference ignores unrelated background colours");
        Raster uniform=new Raster(192,144);Arrays.fill(uniform.data,SKIN);Raster same=uniform.copy();PortraitPreviewFilter.apply(same,PhotoPortrait.NONE.withGlobalSkinMask(skin()).withGlobalTone(SkinTone.custom(SKIN&0xffffff,1,true)),()->false,null);exact(uniform.data,same.data,"mask-weighted source matching custom target is exact identity without a face sample");
        for(PhotoPortrait.Tone tone:List.of(PhotoPortrait.Tone.NONE,SkinTone.preset(0,1,true),SkinTone.preset(6,0,false),SkinTone.custom(0,0,true))) {
            Raster neutral=source.copy();PortraitPreviewFilter.apply(neutral,global.withGlobalTone(tone),()->false,null);exact(source.data,neutral.data,"global original and zero strength are bit-exact");check(neutral.reads==0&&neutral.writes==0,"neutral global colour performs no pixel IO");
        }
        Raster pending=source.copy();PortraitPreviewFilter.apply(pending,global.withGlobalSkinMask(null),()->false,null);exact(source.data,pending.data,"pending global mask performs no colour change");check(pending.reads==0&&pending.writes==0,"pending mask avoids pixel IO");
        Raster empty=source.copy();PortraitPreviewFilter.apply(empty,global.withGlobalSkinMask(new PhotoPortrait.BodySkinMask(new byte[16384])),()->false,null);exact(source.data,empty.data,"empty semantic confidence leaves the whole image unchanged");check(empty.writes==0,"no reference skin avoids a full-frame write pass");
        Raster transparent=source.copy();for(int i=0;i<transparent.data.length;i++)transparent.data[i]&=0xffffff;int[] hidden=transparent.data.clone();PortraitPreviewFilter.apply(transparent,global,()->false,null);exact(hidden,transparent.data,"transparent hidden RGB never becomes a skin reference or gets tinted");check(transparent.writes==0,"transparent-only skin needs no write pass");
        Raster faceFlag=source.copy(),bodyFlag=source.copy();PortraitPreviewFilter.apply(faceFlag,global.withGlobalTone(SkinTone.preset(6,.8,false)),()->false,null);PortraitPreviewFilter.apply(bodyFlag,global.withGlobalTone(SkinTone.preset(6,.8,true)),()->false,null);exact(faceFlag.data,bodyFlag.data,"legacy per-person scope flag cannot restrict global exposed-skin coverage");
        PhotoPortrait.Face old=face().withBounds(.2,.75,.1,.14,0).withTone(SkinTone.preset(9,1,false));PhotoPortrait selected=new PhotoPortrait(List.of(old),List.of()).withGlobalSkinMask(skin()).withGlobalTone(SkinTone.preset(6,.8,false));
        Raster selectedPixels=source.copy();PortraitPreviewFilter.apply(selectedPixels,selected,()->false,null);exact(actual.data,selectedPixels.data,"global selection clears old personal colour instead of layering it");
        PhotoPortrait personal=selected.withFace(0,old);Raster switched=source.copy(),legacy=source.copy();PortraitPreviewFilter.apply(switched,personal,()->false,null);PortraitPreviewFilter.apply(legacy,new PhotoPortrait(List.of(old),List.of()),()->false,null);exact(switched.data,legacy.data,"switching back to personal tone produces exactly the legacy branch");
    }
    private static void protectedFeatures()throws Exception {
        int w=256,h=192;PhotoPortrait.Face f=face().withBounds(.5,.5,.12,.14,23).withLandmarks(PortraitLandmarkMaskTest.mesh(1.4)).withEnabled(false).withSkinMask(new PhotoPortrait.SkinMask(-1,-1,1,1,new byte[16384]));
        Raster source=image(w,h,false);PhotoPortrait all=PhotoPortrait.NONE.withGlobalSkinMask(new PhotoPortrait.BodySkinMask(filled())).withGlobalTone(SkinTone.preset(2,1,false)).withFaces(List.of(f));Raster actual=source.copy();PortraitPreviewFilter.apply(actual,all,()->false,null);
        for(double[] uv:new double[][]{{-.58,-.06},{.60,-.08},{-.55,-.27},{.58,-.30},{0,.78},{-.12,.4}}){double[] xy=world(f,uv[0],uv[1],w,h);near(PortraitPreviewFilter.featureProtection(f,xy[0],xy[1],w,h),0,0,"known geometric features are protected even when face edit is disabled");int i=index(source,xy[0],xy[1]);check(source.data[i]==actual.data[i],"global pixels preserve known eyes brows lips and nostrils");}
        for(double[] uv:new double[][]{{0,-1.9},{1.4,-.1},{-2,1.2}}){double[] xy=world(f,uv[0],uv[1],w,h);near(PortraitPreviewFilter.featureProtection(f,xy[0],xy[1],w,h),1,0,"feature API never clips exposed forehead or body by face envelope");int i=index(source,xy[0],xy[1]);check(source.data[i]!=actual.data[i],"global tone reaches skin outside old ellipse and mesh boundaries");}
        near(PortraitPreviewFilter.featureProtection(null,.2,.8,w,h),1,0,"missing face does not gate exposed skin");near(PortraitPreviewFilter.featureProtection(f,.02,.98,w,h),1,0,"far body has no face protection envelope");
        expectInvalid(()->PortraitPreviewFilter.featureProtection(f,.5,.5,0,h),"feature API rejects zero image width");expectInvalid(()->PortraitPreviewFilter.featureProtection(f,.5,.5,w,65536),"feature API rejects oversized image height");
        PhotoPortrait.Face noMesh=f.withLandmarks(null);double[] legacyEye=world(noMesh,-.526,-.407,w,h);near(PortraitPreviewFilter.featureProtection(noMesh,legacyEye[0],legacyEye[1],w,h),0,0,"known face without mesh retains legacy feature protection only");near(PortraitPreviewFilter.featureProtection(noMesh,.02,.98,w,h),1,0,"legacy feature protection stays local to face");
        Raster differentFaceSample=source.copy();PortraitPreviewFilter.apply(differentFaceSample,all.withFace(0,f.withSkin(20,240,245)),()->false,null);exact(actual.data,differentFaceSample.data,"global source reference never depends on Face.skinR/G/B");
        PhotoPortrait withSettings=all.withFace(0,f.withEnabled(true).withSettings(new PhotoPortrait.Settings(35,22,0,25,70,40,20)));Raster adjusted=source.copy();PortraitPreviewFilter.apply(adjusted,withSettings,()->false,null);int arm=index(source,.08,.85);check(adjusted.data[arm]==actual.data[arm],"global reference freezes original skin before local face adjustments can bias it");
    }
    private static void orientations()throws Exception {
        for(int[] size:new int[][]{{367,219},{219,367},{257,257}}) {
            Raster source=image(size[0],size[1],false),expected=source.copy();PhotoPortrait global=global();PortraitPreviewFilter.apply(expected,global,1,()->false,null);
            for(int e=1;e<=8;e++){Raster raw=raw(source,e);PortraitPreviewFilter.apply(raw,global,e,()->false,null);exact(expected.data,oriented(raw,e).data,"canonical weighted reference and render agree at EXIF "+e+" / "+size[0]+"x"+size[1]);int maxReads=Math.min(256,raw.h)+raw.h;check(raw.reads<=maxReads,"EXIF sampling reads only bounded source rows, not one row per sample");}
        }
        PhotoPortrait.Face f=face().withLandmarks(PortraitLandmarkMaskTest.mesh(1.4)).withBounds(.5,.32,.1,.14,-27);Raster source=image(221,167,false),expected=source.copy();PhotoPortrait global=global().withFaces(List.of(f));PortraitPreviewFilter.apply(expected,global,1,()->false,null);for(int e=1;e<=8;e++){Raster raw=raw(source,e);PortraitPreviewFilter.apply(raw,global,e,()->false,null);exact(expected.data,oriented(raw,e).data,"optional rolled feature protection follows EXIF "+e);}
        Raster noFace=image(197,149,false),exportExpected=noFace.copy();PortraitPreviewFilter.apply(exportExpected,global(),1,()->false,null);PhotoEditStore.Draft draft=draft("9".repeat(64),PhotoLocalEdits.NONE.withPortrait(global()));
        for(int e=1;e<=8;e++){Raster raw=raw(noFace,e);draft.profile().renderPixels(raw,()->false,null);exact(exportExpected.data,oriented(raw,e).data,"empty-face global draft/export profile follows source EXIF "+e);}
    }
    private static void lifetime()throws Exception {
        PhotoPortrait global=global();Raster source=image(193,141,false);AtomicInteger checksCancel=new AtomicInteger();expectIo(()->PortraitPreviewFilter.apply(source.copy(),global,()->checksCancel.incrementAndGet()>5,null),"global reference sampling honours cancellation");
        Raster stopped=source.copy();expectIo(()->PortraitPreviewFilter.apply(stopped,global,()->stopped.writes>=3,null),"global whole-image render honours cancellation after sampling");check(stopped.writes==3,"render cancellation prevents later rows from writing");
        Raster failure=source.copy();failure.failReadAt=3;expectIo(()->PortraitPreviewFilter.apply(failure,global,()->false,null),"source IO failure during weighted sampling propagates");check(failure.writes==0,"sampling failure writes no partially tinted image");
        ArrayList<Double> progress=new ArrayList<>();PortraitPreviewFilter.apply(source.copy(),global,()->false,progress::add);boolean ordered=progress.get(0)==0&&progress.get(progress.size()-1)==1;for(int i=1;i<progress.size();i++)ordered&=progress.get(i)>=progress.get(i-1);check(ordered,"global-only progress starts at zero and finishes monotonically");
    }
    private static PhotoPortrait global(){return PhotoPortrait.NONE.withGlobalSkinMask(skin()).withGlobalTone(SkinTone.preset(6,.8,false));}
    private static PhotoPortrait.BodySkinMask skin(){byte[] p=new byte[16384];rect(p,13,76,39,116);rect(p,83,70,108,122);rect(p,55,8,73,64);return new PhotoPortrait.BodySkinMask(p);}
    private static void rect(byte[] p,int l,int t,int r,int b){for(int y=t;y<b;y++)for(int x=l;x<r;x++)p[y*128+x]=(byte)255;}
    private static byte[] filled(){byte[] p=new byte[16384];Arrays.fill(p,(byte)255);return p;}
    private static PhotoPortrait.Face face(){return new PhotoPortrait.Face(.5,.4,.12,.2,0,191,152,122,true,PhotoPortrait.Settings.NONE,List.of());}
    private static PhotoPortrait maximum(){
        PhotoPortrait.Face seed=face().withLandmarks(PortraitLandmarkMaskTest.mesh(1.4)).withSkinMask(new PhotoPortrait.SkinMask(-1.5,-2,1.5,1.6,filled())).withBodySkinMask(skin());ArrayList<PhotoPortrait.Face> faces=new ArrayList<>();
        for(int f=0;f<12;f++){PhotoPortrait.Face value=seed;for(int s=0;s<(f<4?6:5);s++){double[] p=new double[256];Arrays.fill(p,.5);value=value.addStroke(new PhotoPortrait.Stroke(p,.02,.5,false));}faces.add(value);}
        return new PhotoPortrait(faces,Collections.nCopies(64,new PhotoPortrait.Heal(.1,.2,.6,.7,.03,.5,true))).withGlobalSkinMask(skin()).withGlobalTone(SkinTone.preset(6,.8,false));
    }
    private static PhotoEditStore.Draft draft(String sha,PhotoLocalEdits local)throws IOException{return new PhotoEditStore.Draft(sha,null,"全图露肤合成测试",0,PhotoAdjustments.NONE,PhotoGeometry.NONE,PhotoBorder.NONE,local,false);}
    private static byte[] bytes(PhotoPortrait p)throws IOException{ByteArrayOutputStream b=new ByteArrayOutputStream();p.write(new DataOutputStream(b));return b.toByteArray();}
    private static PhotoPortrait read(byte[] p)throws IOException{return PhotoPortrait.read(new DataInputStream(new ByteArrayInputStream(p)));}
    private static double[] world(PhotoPortrait.Face f,double u,double v,int w,int h){double a=Math.toRadians(f.roll),x=u*f.rx*w,y=v*f.ry*h;return new double[]{f.cx+(Math.cos(a)*x-Math.sin(a)*y)/w,f.cy+(Math.sin(a)*x+Math.cos(a)*y)/h};}
    private static int index(Raster r,double x,double y){return Math.max(0,Math.min(r.h-1,(int)(y*r.h)))*r.w+Math.max(0,Math.min(r.w-1,(int)(x*r.w)));}
    private static Raster image(int w,int h,boolean blueBackground){Raster r=new Raster(w,h);PhotoPortrait.BodySkinMask mask=skin();for(int y=0;y<h;y++)for(int x=0;x<w;x++){int d=(x+y*3)%19-9;boolean skin=mask.weight((x+.5)/w,(y+.5)/h)>0;r.data[y*w+x]=skin?(0xff000000|((191+d)<<16)|((152+d)<<8)|(122+d)):(blueBackground?0xff1144dd:0xffb59a89);if(skin&&(x+y*3)%11==0)r.data[y*w+x]=(r.data[y*w+x]&0xffffff)|0x80000000;}r.data[0]=0x00123456;return r;}
    private static Raster raw(Raster canonical,int e){Raster r=new Raster(e>=5?canonical.h:canonical.w,e>=5?canonical.w:canonical.h);r.exif=e;for(int y=0;y<r.h;y++)for(int x=0;x<r.w;x++)r.data[y*r.w+x]=canonical.data[oy(x,y,r.w,r.h,e)*canonical.w+ox(x,y,r.w,r.h,e)];return r;}
    private static Raster oriented(Raster raw,int e){Raster r=new Raster(e>=5?raw.h:raw.w,e>=5?raw.w:raw.h);for(int y=0;y<raw.h;y++)for(int x=0;x<raw.w;x++)r.data[oy(x,y,raw.w,raw.h,e)*r.w+ox(x,y,raw.w,raw.h,e)]=raw.data[y*raw.w+x];return r;}
    private static int ox(int x,int y,int w,int h,int e){switch(e){case 2:case 3:return w-1-x;case 5:case 8:return y;case 6:case 7:return h-1-y;default:return x;}}
    private static int oy(int x,int y,int w,int h,int e){switch(e){case 3:case 4:return h-1-y;case 5:case 6:return x;case 7:case 8:return w-1-x;default:return y;}}
    private static final class Raster implements SpatialPreviewFilter.Pixels{final int w,h;final int[] data;int exif=1,reads,writes,failReadAt=-1;Raster(int w,int h){this.w=w;this.h=h;data=new int[w*h];}Raster copy(){Raster r=new Raster(w,h);r.exif=exif;System.arraycopy(data,0,r.data,0,data.length);return r;}public int width(){return w;}public int height(){return h;}public int exifOrientation(){return exif;}public void read(int[] p,int row,int rows)throws IOException{if(++reads==failReadAt)throw new IOException("Synthetic global sampling read failure");System.arraycopy(data,row*w,p,0,rows*w);}public void write(int[] p,int row,int rows){writes++;System.arraycopy(p,0,data,row*w,rows*w);}}
    private interface Action{void run()throws Exception;}
    private static void expectInvalid(Action a,String n)throws Exception{try{a.run();throw new AssertionError(n);}catch(IllegalArgumentException expected){checks++;}}
    private static void expectNull(Action a,String n)throws Exception{try{a.run();throw new AssertionError(n);}catch(NullPointerException expected){checks++;}}
    private static void expectIo(Action a,String n)throws Exception{try{a.run();throw new AssertionError(n);}catch(IOException expected){checks++;}}
    private static void exact(int[] a,int[] b,String n){checks++;if(!Arrays.equals(a,b)){int i=0;while(i<a.length&&a[i]==b[i])i++;throw new AssertionError(n+" at "+i+" expected="+Integer.toHexString(a[i])+" actual="+Integer.toHexString(b[i]));}}
    private static void near(double a,double b,double e,String n){checks++;if(!Double.isFinite(a)||Math.abs(a-b)>e)throw new AssertionError(n+" "+a+" != "+b);}
    private static void check(boolean a,String n){checks++;if(!a)throw new AssertionError(n);}
}
