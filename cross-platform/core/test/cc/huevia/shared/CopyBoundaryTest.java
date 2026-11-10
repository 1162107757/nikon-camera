package cc.huevia.shared;

import cc.huevia.account.AccountRepository;
import cc.huevia.album.PhotoEditStore;
import cc.huevia.library.SharedJson;
import java.io.*;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.atomic.AtomicInteger;

public final class CopyBoundaryTest {
    private static int checks;
    private interface Action{void run()throws Exception;}
    private static void yes(boolean value){checks++;if(!value)throw new AssertionError("Copy boundary "+checks);}
    private static void rejects(Action action)throws Exception{checks++;try{action.run();}catch(IOException expected){return;}throw new AssertionError("Invalid copy accepted");}
    private static final class Store implements AccountRepository.Store {public byte[] read(){return null;}public void write(byte[] bytes){}public void clear(){}}
    private static Map<String,Object> call(SharedRuntime r,String op,Map<String,Object> p)throws IOException{return SharedJson.object(r.request(op,SharedJson.encode(p)));}
    private static List<Integer> values(int length,int index,int value){List<Integer> row=new ArrayList<>(Collections.nCopies(length,0));row.set(index,value);return row;}
    private static List<Object> curves(int value){return Arrays.asList(Arrays.asList(0,0,128,value,255,255),Arrays.asList(0,0,255,255),Arrays.asList(0,0,255,255),Arrays.asList(0,0,255,255));}
    private static PhotoEditStore.Draft read(SharedRuntime r,Path file)throws IOException{return new PhotoEditStore(r.root(),"").read(PhotoEditStore.hashFile(file.toFile()));}
    public static int run(Path temporary)throws Exception{
        checks=0;Path root=temporary.resolve("copy-boundary");SharedRuntime runtime=new SharedRuntime(root.toString(),new Store(),(m,p,t,b)->{throw new AssertionError("Copy used network");});
        Path dir=Files.createDirectories(root.resolve("originals")),source=dir.resolve("source.jpg"),first=dir.resolve("first.jpg"),second=dir.resolve("second.jpg");
        Files.write(source,new byte[]{1,2,3,4});Files.write(first,new byte[]{5,6,7,8});Files.write(second,new byte[]{9,10,11,12});
        Path presetFile=root.resolve("fixture.ncp");Files.write(presetFile,cc.huevia.ncp.NcpCompatibilityFixtures.ncp());
        Map<String,Object> imported=call(runtime,"library.import",SharedRuntime.map("path",presetFile.toString(),"name","fixture.ncp","owner",""));
        String preset=(String)((Map<?,?>)imported.get("record")).get("id");
        Map<String,Object> sourceRecipe=SharedRuntime.map("values",values(17,1,15),"curves",curves(160),"hsl",values(24,0,20),"palette",SharedRuntime.map("color",25));
        Map<String,Object> targetRecipe=SharedRuntime.map("presetId",preset,"strength",35,"values",values(17,1,-10),"curves",curves(110),"hsl",values(24,0,-20),"palette",SharedRuntime.map("color",-25),"geometry",SharedRuntime.map("turns",1,"mirrored",true),"border",SharedRuntime.map("template",3));
        runtime.freezeEdit(first.toString(),"",SharedJson.encode(targetRecipe));PhotoEditStore.Draft before=read(runtime,first);
        Map<String,Object> request=SharedRuntime.map("path",source.toString(),"recipe",sourceRecipe,"paths",Arrays.asList(first.toString(),second.toString()),"owner","","basic",true,"curves",false,"colour",true);
        Map<String,Object> result=call(runtime,"photo.copy",request);String receipt=(String)result.get("receipt");
        yes(((Number)result.get("changed")).intValue()==2);yes(((Number)result.get("skipped")).intValue()==0);
        PhotoEditStore.Draft copied=read(runtime,first);yes(copied.presetSha.equals(before.presetSha)&&copied.strength==35);yes(copied.geometry.equals(before.geometry)&&copied.border.equals(before.border));
        yes(copied.adjustments.curves.equals(before.adjustments.curves));yes(copied.adjustments.values()[1]==15&&copied.adjustments.hsl.values()[0]==20&&copied.adjustments.palette.color==25);
        PhotoEditStore.Draft later=runtime.freezeEdit(second.toString(),"",SharedJson.encode(SharedRuntime.map("values",values(17,1,25),"geometry",SharedRuntime.map("turns",3))));
        Map<String,Object> undo=call(runtime,"photo.copyUndo",SharedRuntime.map("owner","","receipt",receipt));
        yes(((Number)undo.get("restored")).intValue()==1&&((Number)undo.get("keptNewer")).intValue()==1);yes(read(runtime,first).identity().equals(before.identity()));yes(read(runtime,second).identity().equals(later.identity()));
        rejects(()->call(runtime,"photo.copyUndo",SharedRuntime.map("owner","","receipt",receipt)));
        Map<String,Object> curveOnly=new LinkedHashMap<>(request);curveOnly.put("paths",Collections.singletonList(first.toString()));curveOnly.put("basic",false);curveOnly.put("curves",true);curveOnly.put("colour",false);
        Map<String,Object> curveResult=call(runtime,"photo.copy",curveOnly);PhotoEditStore.Draft curveCopy=read(runtime,first);
        yes(curveCopy.adjustments.values()[1]==before.adjustments.values()[1]&&curveCopy.adjustments.hsl.equals(before.adjustments.hsl)&&curveCopy.adjustments.palette.equals(before.adjustments.palette));yes(!curveCopy.adjustments.curves.equals(before.adjustments.curves));
        rejects(()->call(runtime,"photo.copyUndo",SharedRuntime.map("owner","alice","receipt",curveResult.get("receipt"))));
        Map<String,Object> invalid=new LinkedHashMap<>(request);invalid.put("paths",Arrays.asList(first.toString(),first.toString()));rejects(()->call(runtime,"photo.copy",invalid));yes(read(runtime,first).identity().equals(curveCopy.identity()));
        invalid.put("paths",Collections.singletonList(source.toString()));rejects(()->call(runtime,"photo.copy",invalid));
        invalid.put("paths",Collections.singletonList(presetFile.toString()));rejects(()->call(runtime,"photo.copy",invalid));
        invalid.put("paths",Collections.singletonList(first.toString()));invalid.put("basic",false);invalid.put("colour",false);rejects(()->call(runtime,"photo.copy",invalid));
        // Cancellation after the first replacement must roll it back completely.
        PhotoEditStore.Draft firstAtCancel=read(runtime,first),secondAtCancel=read(runtime,second);AtomicInteger allowedCalls=new AtomicInteger();
        rejects(()->runtime.request("photo.copy",SharedJson.encode(request),()->allowedCalls.incrementAndGet()>=5,p->{}));
        yes(read(runtime,first).identity().equals(firstAtCancel.identity())&&read(runtime,second).identity().equals(secondAtCancel.identity()));
        yes(Arrays.equals(Files.readAllBytes(source),new byte[]{1,2,3,4})&&Arrays.equals(Files.readAllBytes(first),new byte[]{5,6,7,8})&&Arrays.equals(Files.readAllBytes(second),new byte[]{9,10,11,12}));
        return checks;
    }
}
