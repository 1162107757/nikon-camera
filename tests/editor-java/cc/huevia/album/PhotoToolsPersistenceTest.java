package cc.huevia.album;

import cc.huevia.ncp.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.MessageDigest;
import java.util.Arrays;

/** Real persisted legacy/new bytes and conflicting edits, independent of Android UI. */
public final class PhotoToolsPersistenceTest {
    private static int checks;
    public static void main(String[] args)throws Exception{
        File root=Files.createTempDirectory("photo-tools-persistence-").toFile();
        PhotoEditStore store=new PhotoEditStore(root,"owner");
        PhotoAdjustments old=PhotoAdjustments.NONE.with(PhotoAdjustments.Parameter.EXPOSURE,7);
        for(int version=1;version<=5;version++){
            String sha=Integer.toHexString(version).repeat(64);
            writeLegacy(root,sha,version,old);
            PhotoEditStore.Draft read=store.read(sha);
            check(read.localEdits.isEmpty(),"PED"+version+" adds no local edits");
            check(read.geometry.equals(PhotoGeometry.NONE),"PED"+version+" adds no perspective");
            check(read.adjustments.equals(version==1?PhotoAdjustments.NONE:old),"PED"+version+" retains legacy settings");
            check(read.adjustments.get(PhotoAdjustments.Parameter.GRAIN)==0,"legacy grain is neutral");
        }
        String sha="a".repeat(64);
        PhotoAdjustments manual=old.with(PhotoAdjustments.Parameter.LUMA_DENOISE,31).with(PhotoAdjustments.Parameter.COLOR_DENOISE,44).with(PhotoAdjustments.Parameter.GRAIN,23).with(PhotoAdjustments.Parameter.VIGNETTE,36);
        PhotoGeometry geometry=PhotoGeometry.NONE.crop(.1,.12,.91,.94).straighten(11).perspective(22,-17);
        PhotoLocalEdits local=PhotoLocalEdits.NONE.add(PhotoLocalEdits.Mask.radial(.3,.4).parameters(12,-4,5)).add(PhotoLocalEdits.Mask.linear(.1,.2,.8,.7).parameters(-3,7,-9)).add(PhotoLocalEdits.Mask.brush(new double[]{.1,.2,.3,.4},.05,.7).parameters(5,0,0)).add(new PhotoLocalEdits.Clone(.2,.3,.7,.8,.04,.6,true));
        PhotoEditStore.Draft frozen=new PhotoEditStore.Draft(sha,null,"无滤镜",0,manual,geometry,PhotoBorder.NONE,local,false);
        store.save(frozen);PhotoEditStore.Draft restored=store.read(sha);
        check(restored.identity().equals(frozen.identity()),"PED6 identity roundtrip");
        check(restored.adjustments.equals(manual)&&restored.geometry.equals(geometry)&&restored.localEdits.equals(local),"all tools roundtrip");
        check(restored.profile().modelVersion().equals(frozen.profile().modelVersion()),"complete render identity roundtrip");
        check(new PhotoEditStore(root,"other-owner").read(sha)==null,"new tools remain account scoped");
        PhotoLocalEdits changed=local.withMask(0,local.masks().get(0).parameters(15,-4,5));
        PhotoEditStore.Draft newer=new PhotoEditStore.Draft(sha,null,"无滤镜",0,manual,geometry,PhotoBorder.NONE,changed,false);
        store.save(newer);store.markExported(frozen);
        check(!store.read(sha).exported,"late export cannot mark newer mask exported");
        check(!store.replace(sha,frozen,frozen),"copy undo cannot overwrite newer mask");
        store.markExported(newer);check(store.read(sha).exported&&store.read(sha).localEdits.equals(changed),"matching export preserves all tools");
        PhotoLocalEdits neutralA=PhotoLocalEdits.NONE.add(PhotoLocalEdits.Mask.radial(.2,.2));
        PhotoLocalEdits neutralB=PhotoLocalEdits.NONE.add(PhotoLocalEdits.Mask.radial(.8,.8));
        PhotoEditStore.Draft a=new PhotoEditStore.Draft(sha,null,"无滤镜",0,manual,geometry,PhotoBorder.NONE,neutralA,false);
        PhotoEditStore.Draft b=new PhotoEditStore.Draft(sha,null,"无滤镜",0,manual,geometry,PhotoBorder.NONE,neutralB,false);
        check(a.identity().equals(b.identity()),"zero-effect masks keep effective pixel identity");
        store.save(b);check(!store.replace(sha,a,frozen),"zero-effect mask shape still protects state CAS");
        store.markExported(a);check(!store.read(sha).exported,"late export cannot hide a newer zero-effect region draft");
        PhotoRecipeStore recipes=new PhotoRecipeStore(root,"owner");PhotoRecipeStore.Recipe recipe=recipes.create("工具",frozen);
        PhotoEditStore.Draft applied=recipes.read(recipe.id).apply("b".repeat(64),PhotoGeometry.NONE);
        check(applied.adjustments.equals(manual),"recipe keeps denoise and texture parameters");
        check(applied.localEdits.isEmpty()&&applied.geometry.isNeutral(),"recipe excludes photo-specific regions and perspective");
        File file=draftFile(root,sha);byte[] all=Files.readAllBytes(file.toPath());byte[] body=Arrays.copyOf(all,all.length-32+1);body[body.length-1]=77;writeChecked(file,body);
        try{store.read(sha);throw new AssertionError("trailing data accepted");}catch(IOException expected){checks++;}
        System.out.println("PASS: "+checks+" photo tools persistence/migration/conflict checks");
    }
    private static void writeLegacy(File root,String sha,int version,PhotoAdjustments settings)throws Exception{
        ByteArrayOutputStream bytes=new ByteArrayOutputStream();try(DataOutputStream out=new DataOutputStream(bytes)){
            out.writeInt(0x50454430+version);out.writeUTF(sha);out.writeUTF("无滤镜");out.writeInt(0);out.writeBoolean(false);out.writeInt(0);
            if(version>=2){out.writeUTF(PhotoAdjustments.MODEL);int[] values=Arrays.copyOf(settings.values(),13);out.writeInt(13);for(int value:values)out.writeInt(value);}
            if(version>=5)settings.writeAdvanced(out);
            if(version>=3){out.writeUTF(PhotoGeometry.MODEL);for(int value:new int[]{0,0,0,0,PhotoGeometry.UNIT,PhotoGeometry.UNIT})out.writeInt(value);}
            if(version>=4)PhotoBorder.NONE.write(out);
        }writeChecked(draftFile(root,sha),bytes.toByteArray());
    }
    private static File draftFile(File root,String sha){return new File(root,"photo-edit-drafts/"+PhotoEditStore.hash("owner".getBytes(StandardCharsets.UTF_8))+"/"+sha+".draft");}
    private static void writeChecked(File file,byte[] body)throws Exception{try(FileOutputStream out=new FileOutputStream(file)){out.write(body);out.write(MessageDigest.getInstance("SHA-256").digest(body));}}
    private static void check(boolean value,String message){checks++;if(!value)throw new AssertionError(message);}
}
