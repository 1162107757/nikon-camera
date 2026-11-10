package cc.huevia.shared;

import cc.huevia.account.AccountRepository;
import cc.huevia.album.PhotoEditStore;
import cc.huevia.library.*;
import cc.huevia.ncp.NcpCompatibilityFixtures;
import java.io.*;
import java.nio.file.*;
import java.util.*;

/** Exercise original recipe files through the actual native bridge boundary. */
public final class RecipeBoundaryTest {
    private static int checks;
    private interface Action{void run()throws Exception;}
    private static void yes(boolean value){checks++;if(!value)throw new AssertionError("Recipe boundary "+checks);}
    private static void rejects(Action action)throws Exception{checks++;try{action.run();}catch(IOException expected){return;}throw new AssertionError("Invalid recipe request accepted");}
    private static final class EmptyStore implements AccountRepository.Store{
        public byte[] read(){return null;}public void write(byte[] bytes){}public void clear(){}
    }
    private static Map<String,Object> call(SharedRuntime runtime,String operation,Map<String,Object> p)throws IOException{return SharedJson.object(runtime.request(operation,SharedJson.encode(p)));}
    public static int run(Path temporary)throws Exception{
        checks=0;Path root=temporary.resolve("recipe-boundary");
        SharedRuntime runtime=new SharedRuntime(root.toString(),new EmptyStore(),(m,p,t,b)->{throw new AssertionError("Recipe contacted network");});
        Path first=root.resolve("first.jpg"),second=root.resolve("second.jpg");Files.write(first,new byte[]{1,2,3});Files.write(second,new byte[]{4,5,6});
        PresetLibrary library=new PresetLibrary(root.toFile());String preset=library.importFile("original.ncp",NcpCompatibilityFixtures.ncp()).record.id;
        runtime.request("library.list","{}");
        Map<String,Object> settings=SharedRuntime.map("presetId",preset,"strength",65,"values",Arrays.asList(0,10,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0),"geometry",SharedRuntime.map("turns",1),"border",SharedRuntime.map("template",1));
        Map<String,Object> saved=call(runtime,"recipe.create",SharedRuntime.map("owner","","path",first.toString(),"name","秋色","recipe",settings));String id=(String)saved.get("id");
        yes(id.matches("[0-9a-f]{32}"));yes(((List<?>)call(runtime,"recipe.list",SharedRuntime.map("owner","")).get("items")).size()==1);
        library.remove(preset);
        Map<String,Object> target=SharedRuntime.map("geometry",SharedRuntime.map("turns",3,"mirrored",true),"border",SharedRuntime.map("template",3));
        Map<String,Object> applied=call(runtime,"recipe.apply",SharedRuntime.map("owner","","path",second.toString(),"id",id,"recipe",target));
        SharedRecipe checked=new SharedRecipe(SharedJson.encode(applied.get("recipe")));
        yes(checked.strength==65&&checked.presetId.equals(preset));yes(checked.adjustments.values()[1]==10);
        yes(checked.geometry.turns==3&&checked.geometry.mirrored);yes(checked.border.template==3);
        PhotoEditStore.Draft draft=new PhotoEditStore(root.toFile(),"").read(PhotoEditStore.hashFile(second.toFile()));
        yes(Arrays.equals(draft.presetBytes(),NcpCompatibilityFixtures.ncp()));yes(!draft.exported);
        // Removing a filter and undoing must recover its immutable bytes even after library deletion.
        runtime.freezeEdit(second.toString(),"","{}");
        yes(runtime.freezeEdit(second.toString(),"",SharedJson.encode(applied.get("recipe"))).presetSha.equals(preset));
        PhotoEditStore.Draft pending=new PhotoEditStore(root.toFile(),"").read(draft.sourceSha);
        PhotoEditStore.Draft originalView=runtime.originalView(second.toString(),"");
        yes(originalView.presetBytes().length==0&&originalView.adjustments.isNeutral());
        yes(originalView.geometry.isNeutral()&&originalView.border.isNone());
        yes(new PhotoEditStore(root.toFile(),"").read(draft.sourceSha).identity().equals(pending.identity()));
        yes(new PhotoEditStore(root.toFile(),"").read(draft.sourceSha).exported==pending.exported);
        rejects(()->runtime.originalView(second.toString(),"alice"));
        rejects(()->runtime.freezeEdit(first.toString(),"alice",SharedJson.encode(settings)));
        rejects(()->call(runtime,"recipe.list",SharedRuntime.map("owner","alice")));
        rejects(()->call(runtime,"recipe.delete",SharedRuntime.map("owner","alice","id",id)));
        yes(new cc.huevia.album.PhotoRecipeStore(root.toFile(),"alice").list().isEmpty());
        rejects(()->call(runtime,"recipe.create",SharedRuntime.map("owner","","path",second.toString(),"name","秋色","recipe",applied.get("recipe"))));
        yes(call(runtime,"recipe.rename",SharedRuntime.map("owner","","id",id,"name","金秋")).get("name").equals("金秋"));
        rejects(()->call(runtime,"recipe.rename",SharedRuntime.map("owner","","id",id,"name"," ")));
        rejects(()->call(runtime,"recipe.apply",SharedRuntime.map("owner","","path",second.toString(),"id","../bad","recipe",target)));
        call(runtime,"recipe.delete",SharedRuntime.map("owner","","id",id));
        yes(((List<?>)call(runtime,"recipe.list",SharedRuntime.map("owner","")).get("items")).isEmpty());
        yes(Arrays.equals(Files.readAllBytes(first),new byte[]{1,2,3})&&Arrays.equals(Files.readAllBytes(second),new byte[]{4,5,6}));
        rejects(()->call(runtime,"recipe.apply",SharedRuntime.map("owner","","path",second.toString(),"id",id,"recipe",target)));
        return checks;
    }
}
