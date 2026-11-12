package cc.huevia.shared;

import cc.huevia.album.PhotoEditStore;
import cc.huevia.library.SharedJson;
import cc.huevia.ncp.*;
import java.io.*;
import java.util.*;
import java.util.concurrent.atomic.AtomicInteger;
import java.nio.file.*;
import cc.huevia.account.AccountRepository;

/** Original-model parity and independent-feature retention for tentative local tools. */
public final class LocalEditsBoundaryTest {
    private static int checks;
    private interface Action {void run()throws Exception;}
    private static void yes(boolean value){checks++;if(!value)throw new AssertionError("Local command boundary "+checks);}
    private static void rejects(Action action)throws Exception {checks++;try{action.run();}catch(IOException expected){return;}throw new AssertionError("Invalid local command was accepted");}
    private static Map<String,Object> describe(String data)throws IOException {return SharedLocalEdits.request("local.describe",SharedRuntime.map("localData",data),()->false);}
    private static Map<String,Object> change(Map<String,Object> state,String action,int index,Map<String,Object> value)throws IOException {
        return SharedLocalEdits.request("local.change",SharedRuntime.map("localData",state.get("localData"),"expectedSha",state.get("sha256"),"action",action,"index",index,"value",value),()->false);
    }
    private static Map<String,Object> regionChange(Map<String,Object> state,String action,String id,Map<String,Object> value)throws IOException {
        return SharedLocalEdits.request("local.change",SharedRuntime.map("localData",state.get("localData"),"expectedSha",state.get("sha256"),"action",action,"regionId",id,"value",value),()->false);
    }
    private static PhotoLocalEdits read(Map<String,Object> result)throws IOException {return new SharedRecipe(SharedJson.encode(SharedRuntime.map("localData",result.get("localData")))).local;}
    private static String encode(PhotoLocalEdits edits)throws IOException {ByteArrayOutputStream b=new ByteArrayOutputStream();edits.write(new DataOutputStream(b));return Base64.getEncoder().encodeToString(b.toByteArray());}
    private static List<Integer> ints(int[] values){List<Integer> result=new ArrayList<>();for(int value:values)result.add(value);return result;}
    public static int run(Path temporary)throws Exception {
        checks=0;Map<String,Object> empty=describe("");
        yes(empty.get("sha256").equals(PhotoEditStore.hash(new byte[0])));yes(((List<?>)empty.get("masks")).isEmpty());
        List<Double> points=Arrays.asList(.1,.2,.3,.4);
        Map<String,Object> brush=change(empty,"addMask",-1,SharedRuntime.map("kind","brush","points",points,"exposure",5));
        PhotoLocalEdits original=PhotoLocalEdits.NONE.add(PhotoLocalEdits.Mask.brush(new double[]{.1,.2,.3,.4},.08,.6).parameters(5,0,0));
        yes(read(brush).equals(original));yes(brush.get("localData").equals(encode(original)));yes(brush.get("selectedIndex").equals(0));
        Map<String,Object> noChange=change(brush,"setMask",0,SharedRuntime.map("exposure",5));yes(noChange.get("localData").equals(brush.get("localData")));yes(noChange.get("sha256").equals(brush.get("sha256")));
        Map<String,Object> adjusted=change(brush,"setMask",0,SharedRuntime.map("temperature",25,"saturation",-30,"inverted",true,"enabled",false));
        PhotoLocalEdits.Mask m=read(adjusted).masks().get(0);yes(Arrays.equals(m.points(),new double[]{.1,.2,.3,.4}));yes(m.exposure==5&&m.temperature==25&&m.saturation==-30&&m.inverted&&!m.enabled);
        Map<String,Object> radial=change(adjusted,"addMask",-1,SharedRuntime.map("kind","radial"));yes(read(radial).masks().get(1).equals(PhotoLocalEdits.Mask.radial(.5,.5)));
        Map<String,Object> linear=change(radial,"addMask",-1,SharedRuntime.map("kind","linear"));yes(read(linear).masks().get(2).equals(PhotoLocalEdits.Mask.linear(.2,.2,.8,.8)));
        Map<String,Object> clone=change(linear,"addClone",-1,Collections.emptyMap());yes(read(clone).clones().get(0).equals(new PhotoLocalEdits.Clone(.25,.5,.75,.5,.08,.6,true)));
        Map<String,Object> moved=change(clone,"setClone",0,SharedRuntime.map("sourceX",.9,"targetY",.8,"radius",.12,"feather",.25));
        PhotoLocalEdits.Clone c=read(moved).clones().get(0);yes(c.sourceX==.9&&c.sourceY==.5&&c.targetX==.75&&c.targetY==.8&&c.radius==.12&&c.feather==.25);
        yes(read(change(moved,"removeMask",1,Collections.emptyMap())).masks().size()==2);yes(read(change(moved,"removeClone",0,Collections.emptyMap())).clones().isEmpty());
        AdjustmentRegion region=AdjustmentRegion.create("保留区域").addStroke(new PhotoPortrait.Stroke(new double[]{.4,.5},.05,.3,false));
        PhotoPatch patch=PhotoPatch.create(region).sample(.1,.2).contextBlend(true);
        PhotoBodyShape body=PhotoBodyShape.NONE.withArea(PhotoBodyShape.BODY,PhotoBodyShape.NONE.body.withAmount(30));
        PhotoPortrait portrait=PhotoPortrait.NONE.withSkinSmoothing(25).withBodyShape(body);
        PhotoLocalEdits complex=new PhotoLocalEdits(read(moved).masks(),read(moved).clones(),portrait,Collections.singletonList(region),Collections.singletonList(patch));
        String complexData=encode(complex);Map<String,Object> described=describe(complexData);yes(described.get("localData").equals(complexData));yes(described.get("regionCount").equals(1)&&described.get("patchCount").equals(1)&&described.get("hasPortrait").equals(true));
        PhotoLocalEdits cleared=read(change(described,"clearTools",-1,Collections.emptyMap()));
        yes(cleared.masks().isEmpty()&&cleared.clones().isEmpty());yes(cleared.portrait.equals(portrait));yes(cleared.regions().equals(Collections.singletonList(region)));yes(cleared.patches().equals(Collections.singletonList(patch)));
        Map<String,Object> raw=SharedRuntime.map("localData",moved.get("localData"),"expectedSha",brush.get("sha256"),"action","removeMask","index",0);
        rejects(()->SharedLocalEdits.request("local.change",raw,()->false));
        rejects(()->change(brush,"setMask",0,SharedRuntime.map("kind","radial")));
        for(Map<String,Object> invalid:Arrays.asList(
                SharedRuntime.map("exposure",31),SharedRuntime.map("temperature",101),SharedRuntime.map("saturation",-101),SharedRuntime.map("radius",0),
                SharedRuntime.map("feather",Double.NaN),SharedRuntime.map("feather",Double.POSITIVE_INFINITY),SharedRuntime.map("enabled","true"),SharedRuntime.map("x0",-1),
                SharedRuntime.map("points",Arrays.asList(.1,.2,.3)),SharedRuntime.map("points",Arrays.asList(.1,"x")),SharedRuntime.map("points",null)))
            rejects(()->change(brush,"setMask",0,invalid));
        rejects(()->change(empty,"addMask",0,SharedRuntime.map("kind","unknown")));
        rejects(()->change(brush,"setMask",0,SharedRuntime.map("points",Collections.nCopies(1026,.5))));
        rejects(()->change(clone,"setClone",0,SharedRuntime.map("radius",.251)));
        rejects(()->change(brush,"removeMask",-1,Collections.emptyMap()));
        rejects(()->change(brush,"removeMask",1,Collections.emptyMap()));
        rejects(()->SharedLocalEdits.request("local.change",SharedRuntime.map("localData",brush.get("localData"),"expectedSha",brush.get("sha256"),"action","removeMask","index",.5),()->false));
        rejects(()->SharedLocalEdits.request("local.change",SharedRuntime.map("localData",brush.get("localData"),"action","removeMask","index",0),()->false));
        rejects(()->change(brush,"unknown",0,Collections.emptyMap()));rejects(()->SharedLocalEdits.request("local.unknown",Collections.emptyMap(),()->false));rejects(()->describe("invalid base64"));
        byte[] trailing=Base64.getDecoder().decode((String)brush.get("localData"));trailing=Arrays.copyOf(trailing,trailing.length+1);final String excess=Base64.getEncoder().encodeToString(trailing);rejects(()->describe(excess));
        Map<String,Object> max=empty;for(int i=0;i<PhotoLocalEdits.MAX_MASKS;i++)max=change(max,"addMask",-1,SharedRuntime.map("kind","radial"));final Map<String,Object> full=max;rejects(()->change(full,"addMask",-1,SharedRuntime.map("kind","radial")));
        max=empty;for(int i=0;i<PhotoLocalEdits.MAX_CLONES;i++)max=change(max,"addClone",-1,Collections.emptyMap());final Map<String,Object> clones=max;rejects(()->change(clones,"addClone",-1,Collections.emptyMap()));
        rejects(()->SharedLocalEdits.request("local.change",SharedRuntime.map("localData",brush.get("localData"),"expectedSha",brush.get("sha256"),"action","setMask","index",0,"value",null),()->false));
        checks++;try{SharedLocalEdits.request("local.describe",Collections.emptyMap(),()->true);throw new AssertionError("Cancelled local command accepted");}catch(InterruptedIOException expected){}
        AtomicInteger count=new AtomicInteger();checks++;try{SharedLocalEdits.request("local.change",SharedRuntime.map("localData",brush.get("localData"),"expectedSha",brush.get("sha256"),"action","removeMask","index",0),()->count.getAndIncrement()>0);throw new AssertionError("Late cancellation accepted");}catch(InterruptedIOException expected){}
        yes(read(brush).equals(original));
        yes(described.get("hasBodyShape").equals(true));
        Path privateRoot=temporary.resolve("local-preview-private"),photo=privateRoot.resolve("originals/own.png");Files.createDirectories(photo.getParent());
        byte[] png=Base64.getDecoder().decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP48OHDfwAJdAPQXHvArAAAAABJRU5ErkJggg==");Files.write(photo,png);
        AccountRepository.Store store=new AccountRepository.Store(){public byte[] read(){return null;}public void write(byte[] value){}public void clear(){}};
        AccountRepository.Transport network=(method,path,token,data)->{throw new AssertionError("Local preview performed network access");};
        SharedRuntime runtime=new SharedRuntime(privateRoot.toString(),store,network);
        Map<String,Object> recipe=SharedRuntime.map("localData",complexData,"geometry",SharedRuntime.map("turns",1,"left",100000,"right",900000),"border",SharedRuntime.map("template",3));
        Map<String,Object> payload=SharedRuntime.map("path",photo.toString(),"owner","","recipe",recipe);
        runtime.request("draft.save",SharedJson.encode(payload));String beforeDraft=runtime.request("draft.load",SharedJson.encode(payload));String beforeVersions=runtime.request("version.list","{\"owner\":\"\"}");
        PhotoEditStore.Draft view=runtime.localView(photo.toString(),"",SharedJson.encode(recipe));
        yes(view.geometry.equals(PhotoGeometry.NONE));yes(view.border.equals(PhotoBorder.NONE));yes(view.localEdits.portrait.bodyShape.equals(PhotoBodyShape.NONE));
        yes(view.localEdits.portrait.skinSmoothing==25);yes(view.localEdits.masks().equals(complex.masks())&&view.localEdits.clones().equals(complex.clones()));
        yes(view.localEdits.regions().equals(complex.regions())&&view.localEdits.patches().equals(complex.patches()));
        yes(runtime.request("draft.load",SharedJson.encode(payload)).equals(beforeDraft));yes(runtime.request("version.list","{\"owner\":\"\"}").equals(beforeVersions));yes(Arrays.equals(Files.readAllBytes(photo),png));
        Map<String,Object> tentativeRecipe=new LinkedHashMap<>(recipe);
        int[] tentativeValues=new int[17];tentativeValues[1]=12;tentativeRecipe.put("values",ints(tentativeValues));
        tentativeRecipe.put("geometry",SharedRuntime.map("turns",3,"left",300000,"right",900000));
        tentativeRecipe.put("border",SharedRuntime.map("template",1,"margin",130));
        PhotoEditStore.Draft tentativeView=runtime.localView(photo.toString(),"",SharedJson.encode(tentativeRecipe));
        yes(tentativeView.adjustments.get(PhotoAdjustments.Parameter.EXPOSURE)==12);
        yes(runtime.request("draft.load",SharedJson.encode(payload)).equals(beforeDraft));
        runtime.cleanupRegion(photo.toString(),"",SharedJson.encode(tentativeRecipe),complex.regions().get(0).id);
        yes(runtime.request("draft.load",SharedJson.encode(payload)).equals(beforeDraft));
        rejects(()->runtime.cleanupRegion(photo.toString(),"",SharedJson.encode(tentativeRecipe),"missing-region"));
        yes(runtime.request("draft.load",SharedJson.encode(payload)).equals(beforeDraft));
        rejects(()->runtime.localView(photo.toString(),"another-account",SharedJson.encode(recipe)));
        yes(runtime.cleanupRegion(photo.toString(),"",SharedJson.encode(recipe),"")==null);
        yes(runtime.cleanupRegion(photo.toString(),"",SharedJson.encode(recipe),complex.regions().get(0).id).equals(complex.regions().get(0)));
        rejects(()->runtime.cleanupRegion(photo.toString(),"",SharedJson.encode(recipe),"missing-region"));
        rejects(()->runtime.cleanupRegion(photo.toString(),"another-account",SharedJson.encode(recipe),complex.regions().get(0).id));
        Map<String,Object> named=SharedLocalEdits.request("local.seedRegion",SharedRuntime.map("localData",""),()->false);
        yes(SharedRuntime.object(named.get("seed")).get("name").equals("区域 1"));
        Map<String,Object> firstNamed=change(empty,"addRegion",-1,SharedRuntime.object(named.get("seed")));
        Map<String,Object> nextNamed=SharedLocalEdits.request("local.seedRegion",SharedRuntime.map("localData",firstNamed.get("localData")),()->false);
        yes(SharedRuntime.object(nextNamed.get("seed")).get("name").equals("区域 2"));
        Map<String,Object> seeded=SharedLocalEdits.request("local.seedRegion",SharedRuntime.map("localData","","name","测试选区"),()->false);
        Map<String,Object> seed=SharedRuntime.object(seeded.get("seed"));String regionId=(String)seed.get("id");
        yes(regionId.matches("[a-f0-9-]{36}"));yes(seeded.get("localData").equals("")&&((List<?>)seeded.get("regions")).isEmpty());
        List<Object> strokes=Arrays.asList(SharedRuntime.map("points",Arrays.asList(.1,.2,.3,.4),"radius",.05,"feather",.3,"erase",false),SharedRuntime.map("points",Arrays.asList(.2,.3),"radius",.03,"feather",.2,"erase",true));
        List<Object> shapes=Collections.singletonList(SharedRuntime.map("kind","ellipse","left",.2,"top",.2,"right",.8,"bottom",.7,"feather",.4,"subtract",false,"strokeIndex",1));
        Map<String,Object> selection=new LinkedHashMap<>(seed);selection.put("strokes",strokes);selection.put("shapes",shapes);
        Map<String,Object> regionState=change(empty,"addRegion",-1,selection);
        AdjustmentRegion expectedRegion=new AdjustmentRegion(regionId,"测试选区",true,1,Arrays.asList(new PhotoPortrait.Stroke(new double[]{.1,.2,.3,.4},.05,.3,false),new PhotoPortrait.Stroke(new double[]{.2,.3},.03,.2,true)),PhotoAdjustments.NONE,PhotoPortrait.NONE,PhotoPortrait.Settings.NONE,null,Collections.singletonList(new SelectionShape(SelectionShape.Kind.ELLIPSE,.2,.2,.8,.7,.4,false,1)),false);
        yes(read(regionState).regions().get(0).equals(expectedRegion));yes(regionState.get("localData").equals(encode(PhotoLocalEdits.NONE.addRegion(expectedRegion))));
        yes(regionState.get("selectedType").equals("region")&&regionState.get("selectedIndex").equals(0));
        Map<String,Object> overlayRegion=new LinkedHashMap<>(seed);
        overlayRegion.put("shapes",Collections.singletonList(SharedRuntime.map("kind","rectangle","left",0,"top",0,"right",.5,"bottom",1,"feather",0,"subtract",false,"strokeIndex",0)));
        Map<String,Object> overlayLocal=change(empty,"addRegion",-1,overlayRegion);
        Map<String,Object> overlayRecipe=SharedRuntime.map("localData",overlayLocal.get("localData"));
        Map<String,Object> overlayRequest=SharedRuntime.map("recipe",overlayRecipe,"regionId",regionId,"sourceWidth",100,"sourceHeight",80,"outputWidth",100,"outputHeight",80);
        Map<String,Object> overlay=SharedLocalEdits.request("local.overlay",overlayRequest,()->false);
        byte[] rgba=Base64.getDecoder().decode((String)overlay.get("rgba"));
        yes(rgba.length==100*80*4);yes((rgba[(40*100+25)*4+3]&255)==38);yes((rgba[(40*100+75)*4+3]&255)==0);
        yes((rgba[(40*100+25)*4]&255)==38&&(rgba[(40*100+25)*4+1]&255)==36&&(rgba[(40*100+25)*4+2]&255)==34);
        overlayRecipe.put("geometry",SharedRuntime.map("turns",1));overlayRequest.put("outputWidth",80);overlayRequest.put("outputHeight",100);
        overlay=SharedLocalEdits.request("local.overlay",overlayRequest,()->false);rgba=Base64.getDecoder().decode((String)overlay.get("rgba"));
        yes((rgba[(25*80+40)*4+3]&255)==38);yes((rgba[(75*80+40)*4+3]&255)==0);
        overlayRecipe.remove("geometry");overlayRecipe.put("border",SharedRuntime.map("template",3));
        int[] overlayCanvas=PhotoBorder.NONE.withTemplate(3).dimensions(100,80);overlayRequest.put("outputWidth",overlayCanvas[0]);overlayRequest.put("outputHeight",overlayCanvas[1]);
        overlay=SharedLocalEdits.request("local.overlay",overlayRequest,()->false);rgba=Base64.getDecoder().decode((String)overlay.get("rgba"));
        yes((rgba[((overlayCanvas[1]-1)*overlayCanvas[0]+25)*4+3]&255)==0);
        overlayRequest.put("outputWidth",4000);overlayRequest.put("outputHeight",3000);
        overlay=SharedLocalEdits.request("local.overlay",overlayRequest,()->false);
        yes(overlay.get("width").equals(320)&&overlay.get("height").equals(240));
        rejects(()->SharedLocalEdits.request("local.overlay",overlayRequest,()->true));
        overlayRequest.put("sourceWidth",0);rejects(()->SharedLocalEdits.request("local.overlay",overlayRequest,()->false));
        int[] hsl=new int[24];hsl[1]=20;
        Map<String,Object> setColor=regionChange(regionState,"setRegion",regionId,SharedRuntime.map("adjustments",SharedRuntime.map("hsl",ints(hsl),"palette",SharedRuntime.map("color",30,"tone",20,"amount",50))));
        int[] exposure=new int[17];exposure[0]=10;
        Map<String,Object> setExposure=regionChange(setColor,"setRegion",regionId,SharedRuntime.map("adjustments",SharedRuntime.map("values",ints(exposure),"palette",SharedRuntime.map("amount",75))));
        AdjustmentRegion colored=read(setExposure).regions().get(0);
        yes(colored.adjustments.values()[0]==10&&colored.adjustments.hsl.equals(new PhotoHsl(hsl)));yes(colored.adjustments.palette.equals(new PhotoColorPalette(30,20,75)));yes(colored.strokes.equals(expectedRegion.strokes)&&colored.shapes.equals(expectedRegion.shapes));
        AdjustmentRegion retained=colored.withPortrait(PhotoPortrait.NONE.withSkinSmoothing(13));
        PhotoLocalEdits retainedEdits=new PhotoLocalEdits(complex.masks(),complex.clones(),complex.portrait,Collections.singletonList(retained),complex.patches());
        Map<String,Object> retainedState=describe(encode(retainedEdits));
        Map<String,Object> inverted=regionChange(retainedState,"setRegion",regionId,SharedRuntime.map("inverted",true,"enabled",false,"amount",.25,"name","重命名选区"));
        AdjustmentRegion revised=read(inverted).regions().get(0);
        yes(revised.portrait.equals(retained.portrait)&&revised.skinSettings.equals(retained.skinSettings));yes(revised.adjustments.equals(retained.adjustments));yes(revised.inverted&&!revised.enabled&&revised.amount==.25&&revised.name.equals("重命名选区"));
        PhotoLocalEdits removed=read(regionChange(inverted,"removeRegion",regionId,Collections.emptyMap()));
        yes(removed.regions().isEmpty()&&removed.masks().equals(complex.masks())&&removed.clones().equals(complex.clones()));yes(removed.portrait.equals(complex.portrait)&&removed.patches().equals(complex.patches()));
        rejects(()->regionChange(regionState,"setRegion","missing",Collections.emptyMap()));rejects(()->regionChange(regionState,"setRegion",regionId,SharedRuntime.map("id","another")));rejects(()->change(regionState,"addRegion",-1,selection));
        for(Map<String,Object> invalid:Arrays.asList(SharedRuntime.map("name",""),SharedRuntime.map("name","bad\nname"),SharedRuntime.map("amount",1.1),SharedRuntime.map("inverted","true"),
                SharedRuntime.map("strokes",Collections.singletonList(SharedRuntime.map("points",Arrays.asList(.1,.2,.3)))),
                SharedRuntime.map("strokes",Collections.singletonList(SharedRuntime.map("points",Arrays.asList(.1,.2),"radius",0))),
                SharedRuntime.map("strokes",Collections.nCopies(65,strokes.get(0))),
                SharedRuntime.map("shapes",Collections.singletonList(SharedRuntime.map("kind","triangle"))),
                SharedRuntime.map("shapes",Collections.singletonList(SharedRuntime.map("kind","rectangle","left",.8,"right",.8))),
                SharedRuntime.map("shapes",Collections.singletonList(SharedRuntime.map("kind","ellipse","strokeIndex",3))),
                SharedRuntime.map("adjustments",SharedRuntime.map("localData",brush.get("localData"))),
                SharedRuntime.map("adjustments",SharedRuntime.map("values",Arrays.asList(1,2)))))
            rejects(()->regionChange(regionState,"setRegion",regionId,invalid));
        Map<String,Object> allRegions=empty;for(int i=0;i<PhotoLocalEdits.MAX_REGIONS;i++)allRegions=change(allRegions,"addRegion",-1,SharedRuntime.map("name","区域 "+i));final Map<String,Object> fullRegions=allRegions;
        rejects(()->change(fullRegions,"addRegion",-1,SharedRuntime.map("name","额外区域")));rejects(()->SharedLocalEdits.request("local.seedRegion",SharedRuntime.map("localData",fullRegions.get("localData")),()->false));
        System.out.println("PASS "+checks+" tentative local-tool command checks; original binary, stale snapshots, strict bounds, cancellation and independent portrait/region/patch retention");
        return checks;
    }
}
