package cc.huevia.shared;

import cc.huevia.account.AccountRepository;
import cc.huevia.album.PhotoEditStore;
import cc.huevia.album.SharedAlbumOperations;
import cc.huevia.album.PhotoExportSpec;
import cc.huevia.library.SharedJson;
import cc.huevia.ncp.*;
import java.io.*;
import java.nio.file.*;
import java.util.*;

/** Real original-model round trips and filesystem deletion failure boundaries. */
public final class RetouchBoundaryTest {
    private static int checks;
    private interface Action{void run()throws Exception;}
    private static void yes(boolean value){checks++;if(!value)throw new AssertionError("Retouch boundary "+checks);}
    private static void rejects(Action action)throws Exception{checks++;try{action.run();}catch(IOException expected){return;}throw new AssertionError("Unsafe retouch/deletion request accepted");}
    private static Map<String,Object> change(Map<String,Object> old,String action,Map<String,Object> value)throws Exception{return SharedJson.object(SharedRetouch.request("media.retouchChange",SharedJson.encode(SharedRuntime.map("localData",old.get("localData"),"action",action,"index",0,"value",value)),()->false));}
    private static PhotoLocalEdits local(Map<String,Object> value)throws Exception{return new SharedRecipe(SharedJson.encode(value)).local;}
    public static int run(Path temporary)throws Exception {
        checks=0;Map<String,Object> empty=SharedJson.object(SharedRetouch.request("media.retouchDescribe","{}",()->false));yes(local(empty).isEmpty());
        Map<String,Object> manual=change(empty,"manualFace",SharedRuntime.map("cx",.4,"cy",.4,"rx",.12,"ry",.18));yes(local(manual).portrait.faces().size()==1);
        Map<String,Object> adjusted=change(manual,"face",SharedRuntime.map("brightness",20,"smoothing",45,"NATURAL",30));PhotoPortrait.Face f=local(adjusted).portrait.faces().get(0);yes(f.settings.brightness==20&&f.settings.smoothing==45&&f.retouch.get(PortraitRetouch.Parameter.NATURAL)==30);
        yes(local(manual).portrait.faces().get(0).settings.brightness==0); // The tentative before-state is immutable.
        rejects(()->change(adjusted,"skin",SharedRuntime.map("smoothing",50)));
        rejects(()->change(adjusted,"face",SharedRuntime.map("smoothing",101)));
        rejects(()->SharedRetouch.request("media.retouchChange",SharedJson.encode(SharedRuntime.map("localData",adjusted.get("localData"),"action","clearPortrait")),()->true));yes(local(adjusted).portrait.faces().size()==1);
        byte[] coverage=new byte[128*128];Arrays.fill(coverage,(byte)255);String mask=Base64.getEncoder().encodeToString(coverage);
        Map<String,Object> analyzed=SharedJson.object(SharedRetouch.analysis(SharedJson.encode(adjusted),null,mask,"{\"left\":0.2,\"top\":0.3,\"right\":0.8,\"bottom\":0.9}",mask,()->false));
        yes(local(analyzed).portrait.globalSkinMask!=null&&local(analyzed).portrait.bodyShape.backgroundMask!=null);yes(local(analyzed).portrait.faces().get(0).settings.brightness==20);
        Map<String,Object> skin=change(analyzed,"skin",SharedRuntime.map("smoothing",35,"EVENNESS",40));yes(local(skin).portrait.skinSmoothing==35&&local(skin).portrait.retouch.get(PortraitRetouch.Parameter.EVENNESS)==40);
        Map<String,Object> body=change(skin,"body",SharedRuntime.map("tool",1,"amount",18));yes(local(body).portrait.bodyShape.legs.amount==18&&local(body).portrait.skinSmoothing==35);
        int w=128,h=96;int[] pixels=new int[w*h];for(int y=0;y<h;y++)for(int x=0;x<w;x++){int v=70+(x%13)*5+(y%11)*3;pixels[y*w+x]=0xff000000|v<<16|v<<8|v;}
        Map<String,Object> request=SharedRuntime.map("localData",body.get("localData"),"points",Arrays.asList(.5,.5,.51,.5),"radius",.02);
        String one=SharedRetouch.patch(SharedJson.encode(request),pixels,w,h,()->false),two=SharedRetouch.patch(SharedJson.encode(request),pixels,w,h,()->false);PhotoLocalEdits a=local(SharedJson.object(one)),b=local(SharedJson.object(two));
        yes(a.patches().size()==1&&a.patches().get(0).contextBlend);yes(a.patches().get(0).dx==b.patches().get(0).dx&&a.patches().get(0).dy==b.patches().get(0).dy);yes(a.portrait.equals(local(body).portrait));yes(local(body).patches().isEmpty());
        Map<String,Object> healed=SharedJson.object(SharedPortraitInference.heal(SharedJson.encode(SharedRuntime.map("localData",body.get("localData"),"x",.5,"y",.5,"radius",.01)),pixels,w,h,()->false));yes(local(healed).portrait.heals().size()==1);yes(local(body).portrait.heals().isEmpty());
        Map<String,Object> tinted=change(skin,"skin",SharedRuntime.map("toneId",2,"toneAmount",.5));yes(local(tinted).portrait.globalTone.presetId==2);Map<String,Object> faceTone=change(tinted,"face",SharedRuntime.map("toneId",8,"toneAmount",.4));yes(local(faceTone).portrait.globalTone.isNeutral()&&local(faceTone).portrait.faces().get(0).tone.presetId==8);
        rejects(()->SharedRetouch.patch(SharedJson.encode(request),pixels,w,h,()->true));request.put("points",Arrays.asList(.5));rejects(()->SharedRetouch.patch(SharedJson.encode(request),pixels,w,h,()->false));
        float[] input=SharedPortraitInference.input(pixels,w,h,"",true,()->false);yes(input.length==256*256*3);yes(input[0]==-1); // Letterbox padding remains normalized black.
        float[] logits=new float[256*256*6];for(int i=0;i<256*256;i++)logits[i*6+2]=8;
        Map<String,Object> segmented=SharedJson.object(SharedPortraitInference.person(pixels,w,h,logits,"[]",()->false));yes(Base64.getDecoder().decode((String)segmented.get("skin")).length==128*128);yes(segmented.get("body") instanceof Map);logits[3]=Float.NaN;rejects(()->SharedPortraitInference.person(pixels,w,h,logits,"[]",()->false));
        Map<String,Object> face=SharedRuntime.map("cx",.5,"cy",.5,"rx",.15,"ry",.2);float[] points=new float[468*3];for(int i=0;i<468;i++){points[i*3]=90+i%20*3;points[i*3+1]=90+i/20*3;}Map<String,Object> mesh=SharedJson.object(SharedPortraitInference.face(SharedJson.encode(face),w,h,points,2,null,()->false));yes(((List<?>)mesh.get("landmarks")).size()==936);yes(SharedPortraitInference.face(SharedJson.encode(face),w,h,points,-2,null,()->false).isEmpty());
        Path root=Files.createDirectories(temporary.resolve("album-operations")),originals=Files.createDirectories(root.resolve("originals"));byte[] bytes={1,2,3,4,5};String sha=PhotoEditStore.hash(bytes);Path source=originals.resolve(sha+".jpg"),other=originals.resolve("keep.jpg");Files.write(source,bytes);Files.write(other,new byte[]{8,9});
        AccountRepository.Store store=new AccountRepository.Store(){public byte[] read(){return null;}public void write(byte[] value){}public void clear(){}};SharedRuntime runtime=new SharedRuntime(root.toString(),store,(method,path,token,data)->{throw new AssertionError("Offline deletion contacted network");});
        PhotoEditStore.Draft frozen=runtime.freezeEdit(source.toString(),"","{}");List<Map<String,Object>> saved=new ArrayList<>();for(PhotoExportSpec spec:new PhotoExportSpec[]{PhotoExportSpec.full(),PhotoExportSpec.share()}){PhotoExportSpec.Resolved resolved=spec.resolve(1200,800);Map<String,Object> details=SharedRuntime.map("width",resolved.width,"height",resolved.height,"model",SharedExportModel.of(frozen.profile(),resolved),"exportSpec",resolved.identity());Path output=Files.createDirectories(root.resolve("exports")).resolve("test.jpg");Files.write(output,new byte[]{(byte)255,(byte)216,1,2,3,4,(byte)255,(byte)217});saved.add(SharedJson.object(runtime.commitVersion(source.toString(),"",frozen,output.toString(),SharedJson.encode(details),()->false)));}
        Map<String,Object> versionDelete=SharedRuntime.map("owner","","path",originals.resolve(".").resolve(sha+".jpg").toString(),"expectedSourceSha",sha,"operationId","c".repeat(32),"versionIds",Arrays.asList(saved.get(0).get("id")));
        SharedAlbumOperations.request(runtime,"album.deleteVersions",SharedJson.encode(versionDelete),()->false);yes(!new File((String)saved.get(0).get("path")).exists());yes(new File((String)saved.get(1).get("path")).isFile()&&Files.exists(source));SharedAlbumOperations.request(runtime,"album.deleteVersions",SharedJson.encode(versionDelete),()->false);yes(new File((String)saved.get(1).get("path")).isFile());
        Map<String,Object> deletion=SharedRuntime.map("owner","","path",source.toString(),"expectedSourceSha",sha,"operationId","a".repeat(32));
        rejects(()->SharedAlbumOperations.request(runtime,"album.deleteOriginal",SharedJson.encode(deletion),()->true));yes(Files.exists(source));
        Map<String,Object> done=SharedJson.object(SharedAlbumOperations.request(runtime,"album.deleteOriginal",SharedJson.encode(deletion),()->false));yes(Boolean.TRUE.equals(done.get("deleted"))&&!Files.exists(source));yes(Arrays.equals(Files.readAllBytes(other),new byte[]{8,9}));
        yes(SharedJson.object(SharedAlbumOperations.request(runtime,"album.deleteOriginal",SharedJson.encode(deletion),()->false)).get("deleted").equals(true));deletion.put("path",other.toString());rejects(()->SharedAlbumOperations.request(runtime,"album.deleteOriginal",SharedJson.encode(deletion),()->false));
        deletion.put("operationId","b".repeat(32));deletion.put("expectedSourceSha",sha);rejects(()->SharedAlbumOperations.request(runtime,"album.deleteOriginal",SharedJson.encode(deletion),()->false));yes(Files.exists(other));
        return checks;
    }
    public static void main(String[] args)throws Exception{Path root=Files.createTempDirectory("retouch-boundaries-");System.out.println("Retouch checks: "+run(root));}
}
