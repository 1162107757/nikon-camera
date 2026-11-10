package cc.huevia.shared;

import cc.huevia.album.PhotoEditStore;
import cc.huevia.library.*;
import cc.huevia.ncp.*;
import java.io.*;
import java.util.*;
import java.util.function.Predicate;

/** Reuses the original account-scoped, checksummed, immutable-preset draft format. */
public final class SharedEdits {
    private final File root;
    private final PresetLibrary library;
    private final LinkedHashMap<String,Identity> identities=new LinkedHashMap<>(64,.75f,true);
    private static final class Identity {
        final long length,modified;final String sha;
        Identity(File file,String sha){length=file.length();modified=file.lastModified();this.sha=sha;}
        boolean matches(File file){return file.isFile()&&file.length()==length&&file.lastModified()==modified;}
    }
    public SharedEdits(File root,PresetLibrary library){this.root=root;this.library=library;}
    public synchronized String sourceIdentity(File file,boolean force)throws IOException{
        if(!file.isFile()||file.length()<1||file.length()>1024L*1024*1024)throw new IOException("照片原文件大小无效。");
        String path=file.getCanonicalPath();Identity cached=identities.get(path);
        if(!force&&cached!=null&&cached.matches(file))return cached.sha;
        long length=file.length(),modified=file.lastModified();String sha=PhotoEditStore.hashFile(file);
        if(file.length()!=length||file.lastModified()!=modified)throw new IOException("读取期间原文件发生变化。");
        identities.put(path,new Identity(file,sha));while(identities.size()>64)identities.remove(identities.keySet().iterator().next());return sha;
    }
    public PhotoEditStore.Draft load(File source,String owner)throws IOException{return new PhotoEditStore(root,owner).read(sourceIdentity(source,false));}
    public PhotoEditStore.Draft freeze(File source,String owner,String json)throws IOException{
        return freeze(source,owner,json,id->true);
    }
    public PhotoEditStore.Draft freeze(File source,String owner,String json,Predicate<String> visible)throws IOException{
        String sha=sourceIdentity(source,false);SharedRecipe recipe=new SharedRecipe(json);PhotoEditStore store=new PhotoEditStore(root,owner);
        PhotoEditStore.Draft previous=store.read(sha);byte[] bytes;String name;
        if(recipe.presetId.isEmpty()){bytes=new byte[0];name="无滤镜";}
        else if(previous!=null&&recipe.presetId.equals(previous.presetSha)){bytes=previous.presetBytes();name=previous.name;}
        else{
            if(!visible.test(recipe.presetId))throw new IOException("此预设不属于当前账号。");
            bytes=library.readPreset(recipe.presetId);PresetRecord record=library.findBySha256(recipe.presetId);
            if(record==null)throw new IOException("预设已移除，请重新选择滤镜。");name=record.displayName;
        }
        PhotoEditStore.Draft next=new PhotoEditStore.Draft(sha,bytes,name,recipe.strength,recipe.adjustments,recipe.geometry,recipe.border,recipe.local,false);
        if(previous!=null&&previous.exported&&previous.identity().equals(next.identity()))next=new PhotoEditStore.Draft(sha,bytes,name,recipe.strength,recipe.adjustments,recipe.geometry,recipe.border,recipe.local,true);
        store.save(next);return next;
    }
    public void markExported(String owner,PhotoEditStore.Draft frozen)throws IOException{new PhotoEditStore(root,owner).markExported(frozen);}
    public static Map<String,Object> recipe(PhotoEditStore.Draft d)throws IOException{
        Map<String,Object> value=SharedRuntime.map("schema",1,"presetId",d.presetSha,"presetName",d.name,"strength",d.strength,"values",ints(d.adjustments.values()),"hsl",ints(d.adjustments.hsl.values()));
        List<Object> curves=new ArrayList<>();for(int channel=0;channel<4;channel++)curves.add(ints(d.adjustments.curves.points(channel)));value.put("curves",curves);
        PhotoColorPalette palette=d.adjustments.palette;value.put("palette",SharedRuntime.map("color",palette.color,"tone",palette.tone,"amount",palette.amount));
        PhotoGeometry g=d.geometry;value.put("geometry",SharedRuntime.map("turns",g.turns,"angle",g.angle,"left",g.left,"top",g.top,"right",g.right,"bottom",g.bottom,"horizontalPerspective",g.horizontalPerspective,"verticalPerspective",g.verticalPerspective,"mirrored",g.mirrored));
        PhotoBorder b=d.border;List<String> fields=new ArrayList<>();for(int i=0;i<5;i++)fields.add(b.field(i));
        value.put("border",SharedRuntime.map("template",b.template,"automatic",b.automatic,"brand",b.brand,"model",b.model,"fields",fields,"visible",b.visible,"logo",b.logo,"margin",b.margin,"corner",b.corner,"shadow",b.shadow,"blur",b.blur));
        if(d.adjustments.cleanup.hasStoredState()){
            ByteArrayOutputStream bytes=new ByteArrayOutputStream();d.adjustments.cleanup.write(new DataOutputStream(bytes));value.put("cleanupData",Base64.getEncoder().encodeToString(bytes.toByteArray()));
        }
        if(!d.localEdits.isEmpty()){
            ByteArrayOutputStream bytes=new ByteArrayOutputStream();d.localEdits.write(new DataOutputStream(bytes));value.put("localData",Base64.getEncoder().encodeToString(bytes.toByteArray()));
        }
        return value;
    }
    private static List<Integer> ints(int[] values){List<Integer> out=new ArrayList<>(values.length);for(int value:values)out.add(value);return out;}
}
