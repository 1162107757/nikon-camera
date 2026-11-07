package cc.huevia.ncp;

import cc.huevia.album.PhotoAdjustmentCopy;
import cc.huevia.album.PhotoEditStore;
import cc.huevia.album.PhotoRecipeStore;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.BooleanSupplier;

/** Independent synthetic pixel oracles plus real persisted draft/copy/recipe integration. */
public final class PortraitPipelineTest {
    private static int checks;
    private static final PhotoPortrait.Settings BRIGHT = new PhotoPortrait.Settings(45,0,0,0,70,0,0);
    public static void main(String[] args)throws Exception {
        neutralAndIsolation();maskCorrections();textureAndHealing();orientationAndProfile();cancelAndFailure();persistence();
        System.out.println("PASS PortraitPipelineTest "+checks+" checks");
    }
    private static void neutralAndIsolation()throws Exception {
        Raster source=twoFaces(256,160),empty=source.copy();
        PortraitPreviewFilter.apply(empty,PhotoPortrait.NONE,()->false,null);
        exact(source.data,empty.data,"no portrait preserves every ARGB pixel");
        PhotoPortrait.Face left=face(.28,.5,.2,.37,203,151,116,PhotoPortrait.Settings.NONE);
        PhotoPortrait.Face right=face(.73,.5,.2,.37,103,66,46,PhotoPortrait.Settings.NONE);
        Raster zero=source.copy();PortraitPreviewFilter.apply(zero,new PhotoPortrait(List.of(left,right),List.of()),()->false,null);
        exact(source.data,zero.data,"all effect controls zero preserve every ARGB pixel");
        check(zero.reads==0&&zero.writes==0,"neutral face selections perform no pixel IO");
        PhotoPortrait selected=new PhotoPortrait(List.of(left.withSettings(BRIGHT),right),List.of());
        Raster edited=source.copy();PortraitPreviewFilter.apply(edited,selected,()->false,null);
        int changedLeft=0,changedRight=0,outside=0;
        for(int y=0;y<source.h;y++)for(int x=0;x<source.w;x++)if(source.at(x,y)!=edited.at(x,y)){
            if(x<source.w/2)changedLeft++;else changedRight++;
            if(Math.hypot((x/(double)source.w-left.cx)/left.rx,(y/(double)source.h-left.cy)/left.ry)>1.1)outside++;
        }
        check(changedLeft>300,"selected light-skinned face receives visible effect");
        check(changedRight==0,"second face with zero settings remains exactly unchanged");
        check(outside==0,"automatic face mask does not touch background");
        Raster darker=source.copy();PortraitPreviewFilter.apply(darker,new PhotoPortrait(List.of(left,right.withSettings(BRIGHT)),List.of()),()->false,null);
        int changedDark=0,changedLight=0;
        for(int y=0;y<source.h;y++)for(int x=0;x<source.w;x++)if(source.at(x,y)!=darker.at(x,y)){if(x<source.w/2)changedLight++;else changedDark++;}
        check(changedDark>300&&changedLight==0,"sampled darker skin is adjusted independently without touching light face");
        Raster disabled=source.copy();PortraitPreviewFilter.apply(disabled,new PhotoPortrait(List.of(left.withSettings(BRIGHT).withEnabled(false)),List.of()),()->false,null);
        exact(source.data,disabled.data,"disabled face never changes pixels");
        int alphaErrors=0;for(int i=0;i<edited.data.length;i++)if((source.data[i]>>>24)!=(edited.data[i]>>>24))alphaErrors++;
        check(alphaErrors==0,"face effects preserve source alpha across every pixel");
    }
    private static void maskCorrections()throws Exception {
        int w=240,h=160,skin=0xffcb9774;Raster source=new Raster(w,h);Arrays.fill(source.data,skin);
        PhotoPortrait.Face base=face(.28,.5,.14,.34,203,151,116,BRIGHT);
        PhotoPortrait.Face added=base.addStroke(new PhotoPortrait.Stroke(new double[]{.52,.55,.57,.55},.06,.3,false));
        Raster normal=source.copy(),painted=source.copy();PortraitPreviewFilter.apply(normal,portrait(base),()->false,null);PortraitPreviewFilter.apply(painted,portrait(added),()->false,null);
        check(normal.at(130,88)==skin&&painted.at(130,88)!=skin,"add brush extends automatic mask into an explicitly painted skin region");
        PhotoPortrait.Face erased=base.addStroke(new PhotoPortrait.Stroke(new double[]{.22,.54,.25,.54},.06,.2,true));
        Raster removed=source.copy();PortraitPreviewFilter.apply(removed,portrait(erased),()->false,null);
        check(normal.at(55,86)!=skin&&removed.at(55,86)==skin,"erase brush removes effect at its opaque core");
        PhotoPortrait.Face repainted=erased.addStroke(new PhotoPortrait.Stroke(new double[]{.22,.54,.25,.54},.06,.2,false));
        Raster replaced=source.copy();PortraitPreviewFilter.apply(replaced,portrait(repainted),()->false,null);
        check(replaced.at(55,86)!=skin,"later add stroke restores an erased region");
    }
    private static void textureAndHealing()throws Exception {
        Raster noise=twoFaces(256,160);PhotoPortrait.Face face=face(.28,.5,.2,.37,203,151,116,new PhotoPortrait.Settings(0,0,0,90,0,0,0));
        Raster soft=noise.copy(),textured=noise.copy();PortraitPreviewFilter.apply(soft,portrait(face),()->false,null);
        PortraitPreviewFilter.apply(textured,portrait(face.withSettings(new PhotoPortrait.Settings(0,0,0,90,100,0,0))),()->false,null);
        long originalEnergy=energy(noise,45,77,72,97),softEnergy=energy(soft,45,77,72,97),textureEnergy=energy(textured,45,77,72,97);
        check(softEnergy<originalEnergy,"smoothing reduces synthetic fine cheek noise");
        check(textureEnergy>=softEnergy,"texture protection retains at least as much fine cheek variation");
        check(soft.at(55,58)==noise.at(55,58),"dark eye detail outside sampled skin remains exact");
        check(soft.at(3,3)==noise.at(3,3),"background texture remains exact");
        Raster healing=new Raster(200,160);int target=0xffa36c4b,donor=0xffd6ad89;
        for(int y=0;y<healing.h;y++)for(int x=0;x<healing.w;x++)healing.data[y*healing.w+x]=x<100?donor:target;
        int tx=140,ty=80;for(int y=ty-2;y<=ty+2;y++)for(int x=tx-2;x<=tx+2;x++)healing.data[y*healing.w+x]=0xffc9322d;
        int defect=healing.at(tx,ty);PhotoPortrait.Heal heal=new PhotoPortrait.Heal(.3,.5,.7,.5,.055,.55,true);
        PortraitPreviewFilter.apply(healing,new PhotoPortrait(List.of(),List.of(heal)),()->false,null);
        int fixed=healing.at(tx,ty);
        check(distance(fixed,target)<distance(defect,target),"healing reduces target blemish colour error");
        check(distance(fixed,target)<distance(fixed,donor),"healing matches target colour instead of copying donor brightness");
        check(healing.at(140,40)==target&&healing.at(60,80)==donor,"healing preserves pixels outside target and its source patch");
    }
    private static void orientationAndProfile()throws Exception {
        Raster canonical=twoFaces(80,64);
        PhotoPortrait.Face first=face(.28,.5,.2,.37,203,151,116,new PhotoPortrait.Settings(30,15,-10,0,70,12,10));
        PhotoPortrait.Face second=face(.73,.5,.2,.37,103,66,46,new PhotoPortrait.Settings(-10,-15,10,0,70,-10,15));
        PhotoPortrait settings=new PhotoPortrait(List.of(first,second),List.of());
        Raster expected=canonical.copy();PortraitPreviewFilter.apply(expected,settings,1,()->false,null);
        for(int exif=1;exif<=8;exif++){
            Raster raw=rawFromOriented(canonical,exif);raw.exif=exif;PortraitPreviewFilter.apply(raw,settings,()->false,null);
            exact(expected.data,oriented(raw,exif).data,"EXIF "+exif+" portrait mask follows the oriented photo");
        }
        PhotoPortrait detailed=new PhotoPortrait(List.of(first.withSettings(new PhotoPortrait.Settings(30,15,-10,65,70,12,10)),second),List.of(new PhotoPortrait.Heal(.2,.53,.31,.56,.045,.6,true)));
        Raster detailExpected=canonical.copy();PortraitPreviewFilter.apply(detailExpected,detailed,1,()->false,null);
        for(int exif=1;exif<=8;exif++){
            Raster raw=rawFromOriented(canonical,exif);raw.exif=exif;PortraitPreviewFilter.apply(raw,detailed,()->false,null);
            exact(detailExpected.data,oriented(raw,exif).data,"EXIF "+exif+" smoothing, light and healing match canonical oriented pixels");
        }
        PhotoLocalEdits edits=PhotoLocalEdits.NONE.withPortrait(settings);
        Raster local=canonical.copy();LocalEditsPreviewProfile.renderLocal(local,edits,1,()->false,null);
        exact(expected.data,local.data,"local pipeline invokes identical portrait kernel");
        PhotoEditStore.Draft draft=draft("a".repeat(64),edits,PhotoAdjustments.NONE);
        Raster full=canonical.copy();draft.profile().renderPixels(full,()->false,null);
        exact(expected.data,full.data,"persisted draft profile includes portrait effect for full render/export");
        check(!draft.identity().equals(draft("a".repeat(64),PhotoLocalEdits.NONE,PhotoAdjustments.NONE).identity()),"portrait pixels change draft/export cache identity");
        check(draft.hasEffect()&&!edits.isNeutral(),"portrait-only draft is classified as edited detail content");
    }
    private static void cancelAndFailure()throws Exception {
        PhotoPortrait settings=portrait(face(.28,.5,.2,.37,203,151,116,BRIGHT));Raster source=twoFaces(128,96),cancelled=source.copy();
        expectIo(()->PortraitPreviewFilter.apply(cancelled,settings,()->true,null),"pre-cancelled render fails explicitly");
        check(cancelled.writes==0,"pre-cancelled render publishes no rows");exact(source.data,cancelled.data,"pre-cancellation leaves source pixel storage intact");
        AtomicInteger polls=new AtomicInteger();Raster partial=source.copy();expectIo(()->PortraitPreviewFilter.apply(partial,settings,()->polls.incrementAndGet()>20,null),"mid-render cancellation propagates as IO failure");
        check(polls.get()<100,"cancellation is observed within a bounded number of checks");
        Raster failing=source.copy();failing.failReadAt=3;expectIo(()->PortraitPreviewFilter.apply(failing,settings,()->false,null),"pixel read failure propagates without successful output");
        Thread.currentThread().interrupt();try{expectIo(()->PortraitPreviewFilter.apply(source.copy(),settings,()->false,null),"thread interruption cancels render");}finally{Thread.interrupted();}
    }
    private static void persistence()throws Exception {
        PhotoLocalEdits.Mask mask=PhotoLocalEdits.Mask.radial(.3,.4).parameters(7,-4,8);
        PhotoLocalEdits.Clone clone=new PhotoLocalEdits.Clone(.2,.3,.6,.7,.04,.5,true);
        PhotoLocalEdits old=new PhotoLocalEdits(List.of(mask),List.of(clone));byte[] v1=oldLocalBytes(old),written=localBytes(old);
        exact(v1,written,"portrait-empty local edits preserve exact v1 wire bytes");
        check(old.identity().equals("photo-local-linear-v1:"+hex(MessageDigest.getInstance("SHA-256").digest(v1))),"portrait-empty existing local identity remains byte compatible");
        PhotoLocalEdits migrated=PhotoLocalEdits.read(new DataInputStream(new ByteArrayInputStream(v1)));
        check(migrated.equals(old)&&migrated.portrait.isEmpty(),"local v1 migrates to absent portrait without losing masks or clones");
        PhotoPortrait p=portrait(face(.28,.5,.2,.37,203,151,116,BRIGHT));PhotoLocalEdits local=old.withPortrait(p);
        check(local.add(PhotoLocalEdits.Mask.linear(.1,.2,.8,.9)).portrait.equals(p),"add mask preserves portrait");
        check(local.withMask(0,mask.parameters(8,0,0)).portrait.equals(p)&&local.removeMask(0).portrait.equals(p),"mask replace/delete preserves portrait");
        check(local.add(clone).portrait.equals(p)&&local.withClone(0,clone.enabled(false)).portrait.equals(p)&&local.removeClone(0).portrait.equals(p),"clone mutations preserve portrait");
        byte[] encoded=localBytes(local);check(new DataInputStream(new ByteArrayInputStream(encoded)).readInt()==2,"portrait state uses local v2 envelope");
        check(PhotoLocalEdits.read(new DataInputStream(new ByteArrayInputStream(encoded))).equals(local),"portrait and existing local edits roundtrip together");
        Path temp=Files.createTempDirectory("portrait-host-");
        try{
            PhotoEditStore store=new PhotoEditStore(temp.toFile(),"owner");String sha="b".repeat(64);PhotoEditStore.Draft frozen=draft(sha,local,PhotoAdjustments.NONE);
            store.save(frozen);PhotoEditStore.Draft read=store.read(sha);
            check(read.localEdits.equals(local)&&read.identity().equals(frozen.identity()),"persisted portrait draft restores complete state and identity");
            check(read.profile().modelVersion().equals(frozen.profile().modelVersion()),"restored portrait keeps frozen full-render profile identity");
            check(new PhotoEditStore(temp.toFile(),"other-owner").read(sha)==null,"portrait draft remains account scoped");
            PhotoEditStore.Draft newer=draft(sha,local.withPortrait(p.withFace(0,p.faces().get(0).withSettings(new PhotoPortrait.Settings(50,0,0,0,70,0,0)))),PhotoAdjustments.NONE);
            store.save(newer);store.markExported(frozen);check(!store.read(sha).exported,"late export cannot mark a newer portrait exported");
            check(!store.replace(sha,frozen,frozen),"late batch undo cannot overwrite newer portrait");
            store.markExported(newer);check(store.read(sha).exported&&store.read(sha).localEdits.equals(newer.localEdits),"matching export preserves complete portrait state");
            PhotoPortrait n1=portrait(face(.25,.5,.2,.3,190,130,95,PhotoPortrait.Settings.NONE)),n2=portrait(face(.75,.5,.2,.3,190,130,95,PhotoPortrait.Settings.NONE));
            PhotoEditStore.Draft a=draft(sha,PhotoLocalEdits.NONE.withPortrait(n1),PhotoAdjustments.NONE),b=draft(sha,PhotoLocalEdits.NONE.withPortrait(n2),PhotoAdjustments.NONE);
            check(a.identity().equals(b.identity())&&!a.localEdits.equals(b.localEdits),"zero-effect face selections retain effective pixel identity but distinct draft state");
            store.save(b);store.markExported(a);check(!store.read(sha).exported&&!store.replace(sha,a,frozen),"neutral portrait selection still protects export and copy CAS");
            store.save(frozen);PhotoAdjustmentCopy.Receipt receipt=PhotoAdjustmentCopy.apply(store,List.of(new PhotoAdjustmentCopy.Target(sha,frozen,frozen)),PhotoAdjustments.NONE.with(PhotoAdjustments.Parameter.EXPOSURE,5),true,false,false,()->true);
            check(receipt.changed()==1&&store.read(sha).localEdits.equals(local),"copying global adjustments retains target portrait");
            check(receipt.undo(store)==1&&store.read(sha).localEdits.equals(local),"copy undo restores complete portrait draft");
            PhotoRecipeStore recipes=new PhotoRecipeStore(temp.toFile(),"owner");PhotoRecipeStore.Recipe recipe=recipes.create("Portrait colour",frozen);
            check(recipe.apply("c".repeat(64),PhotoGeometry.NONE).localEdits.isEmpty(),"reusable colour recipe excludes photo-bound portrait coordinates");
            String legacySha="d".repeat(64);writeLegacyDraft(temp.toFile(),legacySha,old);PhotoEditStore.Draft legacy=store.read(legacySha);
            check(legacy.localEdits.equals(old)&&legacy.localEdits.portrait.isEmpty(),"existing PED6/local-v1 draft restores without invented portrait");
            check(legacy.localEdits.identity().equals(old.identity()),"existing persisted local identity remains unchanged");
        }finally{
            Path parent=temp.toAbsolutePath().normalize().getParent();if(!parent.equals(Path.of(System.getProperty("java.io.tmpdir")).toAbsolutePath().normalize())||!temp.getFileName().toString().startsWith("portrait-host-"))throw new IOException("Unexpected fixture cleanup path");
            try(var paths=Files.walk(temp)){for(Path file:paths.sorted(Comparator.reverseOrder()).toList())Files.delete(file);}
        }
    }
    private static void writeLegacyDraft(File root,String sha,PhotoLocalEdits local)throws Exception {
        ByteArrayOutputStream bytes=new ByteArrayOutputStream();try(DataOutputStream out=new DataOutputStream(bytes)){
            out.writeInt(0x50454436);out.writeUTF(sha);out.writeUTF("无滤镜");out.writeInt(0);out.writeBoolean(false);out.writeInt(0);
            out.writeUTF(PhotoAdjustments.MODEL);int[] values=PhotoAdjustments.NONE.values();out.writeInt(values.length);for(int value:values)out.writeInt(value);PhotoAdjustments.NONE.writeAdvanced(out);
            out.writeUTF(PhotoGeometry.MODEL);for(int value:new int[]{0,0,0,0,PhotoGeometry.UNIT,PhotoGeometry.UNIT,0,0})out.writeInt(value);PhotoBorder.NONE.write(out);out.write(oldLocalBytes(local));
        }File file=new File(root,"photo-edit-drafts/"+PhotoEditStore.hash("owner".getBytes(StandardCharsets.UTF_8))+"/"+sha+".draft");
        try(FileOutputStream out=new FileOutputStream(file)){out.write(bytes.toByteArray());out.write(MessageDigest.getInstance("SHA-256").digest(bytes.toByteArray()));}
    }
    private static byte[] oldLocalBytes(PhotoLocalEdits edits)throws IOException {
        ByteArrayOutputStream bytes=new ByteArrayOutputStream();DataOutputStream out=new DataOutputStream(bytes);out.writeInt(1);out.writeInt(edits.masks().size());
        for(PhotoLocalEdits.Mask m:edits.masks()){
            out.writeByte(m.kind.ordinal());for(double v:new double[]{m.x0,m.y0,m.x1,m.y1,m.radius,m.feather})out.writeDouble(v);out.writeBoolean(m.inverted);out.writeBoolean(m.enabled);out.writeInt(m.exposure);out.writeInt(m.temperature);out.writeInt(m.saturation);double[] p=m.points();out.writeInt(p.length);for(double value:p)out.writeDouble(value);
        }out.writeInt(edits.clones().size());for(PhotoLocalEdits.Clone c:edits.clones()){for(double v:new double[]{c.sourceX,c.sourceY,c.targetX,c.targetY,c.radius,c.feather})out.writeDouble(v);out.writeBoolean(c.enabled);}return bytes.toByteArray();
    }
    private static byte[] localBytes(PhotoLocalEdits edits)throws IOException{ByteArrayOutputStream b=new ByteArrayOutputStream();edits.write(new DataOutputStream(b));return b.toByteArray();}
    private static PhotoEditStore.Draft draft(String sha,PhotoLocalEdits local,PhotoAdjustments manual)throws IOException{return new PhotoEditStore.Draft(sha,null,"无滤镜",0,manual,PhotoGeometry.NONE,PhotoBorder.NONE,local,false);}
    private static PhotoPortrait.Face face(double x,double y,double rx,double ry,int r,int g,int b,PhotoPortrait.Settings settings){return new PhotoPortrait.Face(x,y,rx,ry,0,r,g,b,true,settings,List.of());}
    private static PhotoPortrait portrait(PhotoPortrait.Face face){return new PhotoPortrait(List.of(face),List.of());}
    private static Raster twoFaces(int w,int h){
        Raster image=new Raster(w,h);for(int y=0;y<h;y++)for(int x=0;x<w;x++){
            double nx=(x+.5)/w,ny=(y+.5)/h;boolean left=Math.hypot((nx-.28)/.2,(ny-.5)/.37)<1,right=Math.hypot((nx-.73)/.2,(ny-.5)/.37)<1;int noise=((x*37+y*53+x*y*3)&15)-7;
            int c=left?rgb(203+noise,151+noise,116+noise):right?rgb(103+noise,66+noise,46+noise):0xff286b81;
            if(left&&((Math.abs(nx-.215)<.035||Math.abs(nx-.345)<.035)&&Math.abs(ny-.36)<.025))c=0xff181719;
            image.data[y*w+x]=c;
        }return image;
    }
    private static long energy(Raster image,int left,int top,int right,int bottom){long sum=0;for(int y=top;y<bottom;y++)for(int x=left;x<right-1;x++)sum+=Math.abs((image.at(x,y)&255)-(image.at(x+1,y)&255));return sum;}
    private static int distance(int a,int b){int sum=0;for(int shift:new int[]{0,8,16})sum+=Math.abs(((a>>>shift)&255)-((b>>>shift)&255));return sum;}
    private static int rgb(int r,int g,int b){return 0xff000000|(Math.max(0,Math.min(255,r))<<16)|(Math.max(0,Math.min(255,g))<<8)|Math.max(0,Math.min(255,b));}
    private static Raster rawFromOriented(Raster canonical,int exif){Raster raw=new Raster(exif>=5?canonical.h:canonical.w,exif>=5?canonical.w:canonical.h);for(int y=0;y<raw.h;y++)for(int x=0;x<raw.w;x++)raw.data[y*raw.w+x]=canonical.data[oy(x,y,raw.w,raw.h,exif)*canonical.w+ox(x,y,raw.w,raw.h,exif)];return raw;}
    private static Raster oriented(Raster raw,int exif){Raster image=new Raster(exif>=5?raw.h:raw.w,exif>=5?raw.w:raw.h);for(int y=0;y<raw.h;y++)for(int x=0;x<raw.w;x++)image.data[oy(x,y,raw.w,raw.h,exif)*image.w+ox(x,y,raw.w,raw.h,exif)]=raw.data[y*raw.w+x];return image;}
    private static int ox(int x,int y,int w,int h,int e){switch(e){case 2:case 3:return w-1-x;case 5:case 8:return y;case 6:case 7:return h-1-y;default:return x;}}
    private static int oy(int x,int y,int w,int h,int e){switch(e){case 3:case 4:return h-1-y;case 5:case 6:return x;case 7:case 8:return w-1-x;default:return y;}}
    private static final class Raster implements SpatialPreviewFilter.Pixels {
        final int w,h;final int[] data;int exif=1,reads,writes,failReadAt=-1;
        Raster(int w,int h){this.w=w;this.h=h;this.data=new int[w*h];}
        Raster copy(){Raster r=new Raster(w,h);System.arraycopy(data,0,r.data,0,data.length);r.exif=exif;return r;}
        int at(int x,int y){return data[y*w+x];}public int width(){return w;}public int height(){return h;}public int exifOrientation(){return exif;}
        public void read(int[] pixels,int row,int rows)throws IOException{if(++reads==failReadAt)throw new IOException("Owned injected read failure");System.arraycopy(data,row*w,pixels,0,rows*w);}
        public void write(int[] pixels,int row,int rows){writes++;System.arraycopy(pixels,0,data,row*w,rows*w);}
    }
    private interface Action {void run()throws Exception;}
    private static void expectIo(Action action,String message)throws Exception{try{action.run();throw new AssertionError(message);}catch(IOException expected){checks++;}}
    private static void exact(int[] expected,int[] actual,String message){checks++;if(!Arrays.equals(expected,actual)){int n=0;while(n<expected.length&&expected[n]==actual[n])n++;throw new AssertionError(message+" first difference "+n+" expected="+Integer.toHexString(expected[n])+" actual="+Integer.toHexString(actual[n]));}}
    private static void exact(byte[] expected,byte[] actual,String message){checks++;if(!Arrays.equals(expected,actual))throw new AssertionError(message);}
    private static String hex(byte[] bytes){StringBuilder s=new StringBuilder();for(byte b:bytes)s.append(Character.forDigit((b>>>4)&15,16)).append(Character.forDigit(b&15,16));return s.toString();}
    private static void check(boolean value,String message){checks++;if(!value)throw new AssertionError(message);}
}
