package cc.huevia.shared;

import cc.huevia.library.SharedJson;
import cc.huevia.ncp.*;
import java.io.IOException;
import java.util.*;

/** Original Android portrait-menu transactions through the opaque recipe boundary. */
public final class RetouchMenuBoundaryTest {
    private static int checks;
    private interface Action { void run() throws Exception; }
    private static void yes(boolean value) { checks++; if(!value)throw new AssertionError("Portrait menu boundary " + checks); }
    private static void rejects(Action action)throws Exception { checks++;try{action.run();}catch(IOException expected){return;}throw new AssertionError("Invalid portrait menu mutation accepted"); }
    private static Map<String,Object> dto(PhotoLocalEdits value)throws Exception { return SharedJson.object(SharedRetouch.result(value,()->false)); }
    private static PhotoLocalEdits local(Map<String,Object> value)throws Exception { return new SharedRecipe(SharedJson.encode(value)).local; }
    private static Map<String,Object> portrait(Map<String,Object> value)throws Exception { return SharedRuntime.object(value.get("portrait")); }
    private static Map<String,Object> change(Map<String,Object> before,String action,int index,Map<String,Object> value,boolean scope)throws Exception {
        return SharedJson.object(SharedRetouch.request("media.retouchChange",SharedJson.encode(SharedRuntime.map("localData",before.get("localData"),"tonePerFace",scope,"action",action,"index",index,"value",value)),()->false));
    }
    private static Map<String,Object> faceDto(Map<String,Object> value,int index)throws Exception { return SharedRuntime.object(((List<?>)portrait(value).get("faces")).get(index)); }
    public static int run()throws Exception {
        checks=0;
        PhotoPortrait.Face first=new PhotoPortrait.Face(.3,.4,.12,.18,0,190,145,120,true,PhotoPortrait.Settings.NONE,Collections.emptyList());
        PhotoPortrait.Face second=new PhotoPortrait.Face(.7,.4,.12,.18,0,180,135,110,true,PhotoPortrait.Settings.NONE,Collections.emptyList());
        PhotoPortrait original=PhotoPortrait.NONE.addFace(first).addFace(second);
        Map<String,Object> before=dto(PhotoLocalEdits.NONE.withPortrait(original));
        Map<String,Object> disabled=change(before,"face",0,SharedRuntime.map("enabled",false),true);
        yes(!local(disabled).portrait.faces().get(0).enabled);
        yes(Boolean.FALSE.equals(faceDto(disabled,0).get("enabled")));
        yes(local(before).portrait.faces().get(0).enabled);
        yes(local(change(disabled,"face",0,SharedRuntime.map("enabled",true),true)).portrait.equals(original));
        rejects(()->change(before,"face",0,SharedRuntime.map("enabled",1),true));
        Map<String,Object> brushed=change(before,"faceStroke",0,SharedRuntime.map("points",Arrays.asList(.2,.3,.25,.35),"radius",.02,"erase",false),true);
        PhotoPortrait.Stroke stroke=local(brushed).portrait.faces().get(0).strokes.get(0);
        yes(Arrays.equals(stroke.points(),new double[]{.2,.3,.25,.35})&&stroke.radius==.02&&stroke.feather==.65&&!stroke.erase);
        yes(((Number)faceDto(brushed,0).get("strokeCount")).intValue()==1&&local(before).portrait.faces().get(0).strokes.isEmpty());
        Map<String,Object> erased=change(brushed,"faceStroke",0,SharedRuntime.map("points",Arrays.asList(.2,.3),"radius",.01,"erase",true),true);
        yes(local(erased).portrait.faces().get(0).strokes.get(1).erase&&local(erased).portrait.faces().get(1).strokes.isEmpty());
        rejects(()->change(before,"faceStroke",0,SharedRuntime.map("points",Arrays.asList(.2),"radius",.02),true));
        rejects(()->change(before,"faceStroke",0,SharedRuntime.map("points",Arrays.asList(-.2,.3),"radius",.02),true));
        rejects(()->change(before,"faceStroke",0,SharedRuntime.map("points",Arrays.asList(.2,.3),"erase",1),true));

        int rgb=0xc6a58b;
        Map<String,Object> custom=change(disabled,"face",0,SharedRuntime.map("toneRgb",rgb,"toneAmount",.43),true);
        yes(local(custom).portrait.faces().get(0).tone.presetId==SkinTone.CUSTOM);
        yes(local(custom).portrait.faces().get(0).tone.colorRGB==rgb);
        yes(((Number)faceDto(custom,0).get("toneRgb")).intValue()==rgb);
        Map<String,Object> strength=change(custom,"face",0,SharedRuntime.map("toneAmount",.7),true);
        PhotoPortrait.Face stored=local(strength).portrait.faces().get(0);
        yes(stored.tone.presetId==SkinTone.CUSTOM&&stored.tone.colorRGB==rgb&&stored.tone.amount==.7&&!stored.enabled);
        Map<String,Object> preset=change(strength,"face",0,SharedRuntime.map("toneId",3),true);
        yes(local(preset).portrait.faces().get(0).tone.colorRGB==SkinTone.byId(3).colorRGB);
        rejects(()->change(custom,"face",0,SharedRuntime.map("toneRgb",-1),true));
        rejects(()->change(custom,"face",0,SharedRuntime.map("toneRgb",0x1000000),true));
        rejects(()->change(before,"face",0,SharedRuntime.map("toneId",SkinTone.CUSTOM),true));
        rejects(()->change(custom,"face",0,SharedRuntime.map("toneAmount",1.01),true));

        PhotoPortrait.Tone wholeTone=SkinTone.custom(0xb6957f,.61,true);
        Map<String,Object> whole=dto(PhotoLocalEdits.NONE.withPortrait(original.withGlobalTone(wholeTone)));
        Map<String,Object> per=change(whole,"toneScope",1,SharedRuntime.map("perFace",true),false);
        PhotoPortrait scoped=local(per).portrait;
        yes(scoped.globalTone.equals(PhotoPortrait.Tone.NONE));
        yes(scoped.faces().get(0).tone.equals(PhotoPortrait.Tone.NONE));
        yes(scoped.faces().get(1).tone.presetId==SkinTone.CUSTOM&&scoped.faces().get(1).tone.colorRGB==wholeTone.colorRGB&&scoped.faces().get(1).tone.amount==wholeTone.amount&&!scoped.faces().get(1).tone.body);
        yes(Boolean.TRUE.equals(portrait(per).get("tonePerFace")));
        yes(local(whole).portrait.globalTone.equals(wholeTone));
        Map<String,Object> back=change(per,"toneScope",1,SharedRuntime.map("perFace",false),true);
        PhotoPortrait returned=local(back).portrait;
        yes(returned.globalTone.presetId==SkinTone.CUSTOM&&returned.globalTone.colorRGB==wholeTone.colorRGB&&returned.globalTone.amount==wholeTone.amount&&!returned.globalTone.body);
        yes(returned.faces().get(0).tone.equals(PhotoPortrait.Tone.NONE)&&returned.faces().get(1).tone.equals(PhotoPortrait.Tone.NONE));
        yes(Boolean.FALSE.equals(portrait(back).get("tonePerFace")));
        rejects(()->change(back,"toneScope",0,SharedRuntime.map("perFace","true"),false));

        Map<String,Object> zero=dto(PhotoLocalEdits.NONE.withPortrait(original.withGlobalTone(SkinTone.custom(rgb,0,false))));
        Map<String,Object> zeroScope=change(zero,"toneScope",0,SharedRuntime.map("perFace",true),false);
        yes(local(zeroScope).portrait.equals(local(zero).portrait)); // Original neutral-strength scope switch is a UI-only change.
        yes(Boolean.TRUE.equals(portrait(zeroScope).get("tonePerFace")));
        Map<String,Object> empty=dto(PhotoLocalEdits.NONE);
        Map<String,Object> noFace=change(empty,"toneScope",-1,SharedRuntime.map("perFace",true),false);
        yes(local(noFace).isEmpty()&&Boolean.TRUE.equals(portrait(noFace).get("tonePerFace")));

        // Each body-skin matte belongs to its face; disconnected, unseeded people stay untouched.
        float[] semantic=new float[256*256*6];
        for(int y=0;y<256;y++)for(int x=0;x<256;x++)semantic[(y*256+x)*6+((y>=40&&y<240&&((x>=32&&x<112)||(x>=144&&x<224)))?2:0)]=8;
        Map<String,Object> bodyRequest=SharedRuntime.map("localData",custom.get("localData"),"tonePerFace",true);
        Map<String,Object> bodySkins=SharedJson.object(SharedPortraitInference.bodySkin(SharedJson.encode(bodyRequest),256,256,semantic,()->false));
        PhotoPortrait bodyPortrait=local(bodySkins).portrait;
        yes(bodyPortrait.faces().get(0).bodySkinMask.weight(.3,.7)>.9);
        yes(bodyPortrait.faces().get(0).bodySkinMask.weight(.7,.7)==0);
        yes(bodyPortrait.faces().get(1).bodySkinMask.weight(.7,.7)>.9);
        yes(bodyPortrait.faces().get(1).bodySkinMask.weight(.3,.7)==0);
        yes(bodyPortrait.faces().get(0).tone.equals(local(custom).portrait.faces().get(0).tone)&&!bodyPortrait.faces().get(0).enabled);
        yes(Boolean.TRUE.equals(faceDto(bodySkins,0).get("hasBodySkinMask"))&&Boolean.TRUE.equals(portrait(bodySkins).get("tonePerFace")));
        yes(local(custom).portrait.faces().get(0).bodySkinMask==null);
        rejects(()->change(custom,"face",0,SharedRuntime.map("toneBody",true),true));
        rejects(()->change(bodySkins,"face",0,SharedRuntime.map("toneBody",1),true));
        Map<String,Object> allSkin=change(bodySkins,"face",0,SharedRuntime.map("toneBody",true),true);
        PhotoPortrait.Tone bodyTone=local(allSkin).portrait.faces().get(0).tone;
        yes(bodyTone.body&&bodyTone.colorRGB==rgb&&bodyTone.amount==.43);
        yes(Boolean.TRUE.equals(faceDto(allSkin,0).get("toneBody")));
        yes(local(change(allSkin,"face",0,SharedRuntime.map("toneAmount",.8),true)).portrait.faces().get(0).tone.body);
        PhotoPortrait.Tone faceOnly=local(change(allSkin,"face",0,SharedRuntime.map("toneBody",false),true)).portrait.faces().get(0).tone;
        yes(!faceOnly.body&&faceOnly.colorRGB==rgb&&faceOnly.amount==.43);
        rejects(()->SharedPortraitInference.bodySkin(SharedJson.encode(empty),256,256,semantic,()->false));
        rejects(()->SharedPortraitInference.bodySkin(SharedJson.encode(bodyRequest),256,256,semantic,()->true));
        byte[] fullSkin=new byte[128*128];Arrays.fill(fullSkin,(byte)255);
        Map<String,Object> global=dto(PhotoLocalEdits.NONE.withPortrait(original.withGlobalSkinMask(new PhotoPortrait.BodySkinMask(fullSkin)).withGlobalTone(SkinTone.custom(rgb,.4,false))));
        yes(!local(change(global,"skin",0,SharedRuntime.map("toneAmount",.8),false)).portrait.globalTone.body);
        yes(Boolean.FALSE.equals(SharedRuntime.object(portrait(global).get("skin")).get("toneBody")));

        AdjustmentRegion region=AdjustmentRegion.create("局部人像").addStroke(new PhotoPortrait.Stroke(new double[]{.3,.4},.1,.65,false)).withPortrait(PhotoPortrait.NONE.addFace(first));
        AdjustmentRegion otherRegion=AdjustmentRegion.create("保留区域").withPortrait(PhotoPortrait.NONE.addFace(second));
        PhotoLocalEdits parent=PhotoLocalEdits.NONE.withPortrait(original).addRegion(region).addRegion(otherRegion);
        Map<String,Object> regionRequest=SharedRuntime.map("localData",dto(parent).get("localData"),"regionId",region.id,"tonePerFace",true);
        Map<String,Object> regionDto=SharedJson.object(SharedRetouch.request("media.retouchDescribe",SharedJson.encode(regionRequest),()->false));
        yes(((List<?>)portrait(regionDto).get("faces")).size()==1&&region.id.equals(regionDto.get("regionId")));
        regionRequest.put("action","face");regionRequest.put("index",0);regionRequest.put("value",SharedRuntime.map("brightness",34));
        Map<String,Object> regionChanged=SharedJson.object(SharedRetouch.request("media.retouchChange",SharedJson.encode(regionRequest),()->false));
        PhotoLocalEdits regionLocal=local(regionChanged);
        yes(regionLocal.portrait.equals(parent.portrait)&&regionLocal.regions().get(1).equals(otherRegion));
        yes(regionLocal.regions().get(0).portrait.faces().get(0).settings.brightness==34&&((Number)faceDto(regionChanged,0).get("brightness")).intValue()==34);
        yes(regionLocal.regions().get(0).strokes.equals(region.strokes)&&parent.regions().get(0).portrait.faces().get(0).settings.brightness==0);
        Map<String,Object> regionAnalyzed=SharedJson.object(SharedRetouch.analysis(SharedJson.encode(regionRequest),null,Base64.getEncoder().encodeToString(fullSkin),null,null,()->false));
        yes(local(regionAnalyzed).regions().get(0).portrait.globalSkinMask!=null&&local(regionAnalyzed).portrait.globalSkinMask==null);
        Map<String,Object> regionBodies=SharedJson.object(SharedPortraitInference.bodySkin(SharedJson.encode(regionRequest),256,256,semantic,()->false));
        yes(local(regionBodies).regions().get(0).portrait.faces().get(0).bodySkinMask!=null&&local(regionBodies).portrait.faces().get(0).bodySkinMask==null);
        Map<String,Object> regionHealRequest=new LinkedHashMap<>(regionRequest);regionHealRequest.put("x",.5);regionHealRequest.put("y",.5);regionHealRequest.put("radius",.01);
        int[] healPixels=new int[64*64];Arrays.fill(healPixels,0xffaa9988);
        Map<String,Object> regionHealed=SharedJson.object(SharedPortraitInference.heal(SharedJson.encode(regionHealRequest),healPixels,64,64,()->false));
        yes(local(regionHealed).regions().get(0).portrait.heals().size()==1&&local(regionHealed).portrait.heals().isEmpty());
        regionRequest.put("action","clearPortrait");
        Map<String,Object> regionReset=SharedJson.object(SharedRetouch.request("media.retouchChange",SharedJson.encode(regionRequest),()->false));
        yes(local(regionReset).regions().get(0).portrait.isEmpty()&&local(regionReset).portrait.equals(parent.portrait));
        yes(local(regionReset).regions().get(0).strokes.equals(region.strokes)&&local(regionReset).regions().get(1).equals(otherRegion));
        rejects(()->SharedRetouch.request("media.retouchChange",SharedJson.encode(regionRequest),()->true));
        regionRequest.put("regionId","missing-region");
        rejects(()->SharedRetouch.request("media.retouchDescribe",SharedJson.encode(regionRequest),()->false));
        PhotoBodyShape shape=PhotoBodyShape.NONE.withArea(0,new PhotoBodyShape.Area(.2,.3,.8,.9,18));
        PhotoLocalEdits shaped=parent.withPortrait(parent.portrait.withBodyShape(shape));
        Map<String,Object> beforeBody=change(dto(shaped),"beforeBody",0,Collections.emptyMap(),true);
        yes(local(beforeBody).portrait.bodyShape.equals(PhotoBodyShape.NONE)&&local(beforeBody).portrait.faces().equals(parent.portrait.faces()));
        yes(local(beforeBody).regions().equals(parent.regions())&&shaped.portrait.bodyShape.equals(shape));
        yes(Boolean.TRUE.equals(dto(shaped).get("sourcePositioning"))&&Boolean.FALSE.equals(beforeBody.get("sourcePositioning")));
        Map<String,Object> protectionRequest=SharedRuntime.map("localData",dto(shaped).get("localData"),"locate",false,"protection",100);
        Map<String,Object> protectedOnly=SharedJson.object(SharedRetouch.analysis(SharedJson.encode(protectionRequest),null,null,"{\"left\":0.1,\"top\":0.1,\"right\":0.9,\"bottom\":0.95}",Base64.getEncoder().encodeToString(fullSkin),()->false));
        yes(local(protectedOnly).portrait.bodyShape.body.equals(shape.body)&&local(protectedOnly).portrait.bodyShape.legs.equals(shape.legs)&&local(protectedOnly).portrait.bodyShape.length.equals(shape.length));
        yes(local(protectedOnly).portrait.bodyShape.backgroundMask!=null&&local(protectedOnly).portrait.bodyShape.backgroundProtection==100&&shaped.portrait.bodyShape.backgroundMask==null);
        protectionRequest.put("locate","false");rejects(()->SharedRetouch.analysis(SharedJson.encode(protectionRequest),null,null,null,null,()->false));
        protectionRequest.put("locate",false);protectionRequest.put("protection",101);rejects(()->SharedRetouch.analysis(SharedJson.encode(protectionRequest),null,null,null,Base64.getEncoder().encodeToString(fullSkin),()->false));
        double[] meshPoints=new double[936];for(int i=0;i<meshPoints.length;i++)meshPoints[i]=(i%13-6)*.1;
        Map<String,Object> meshDto=dto(PhotoLocalEdits.NONE.withPortrait(PhotoPortrait.NONE.addFace(first.withLandmarks(new PhotoPortrait.Landmarks(meshPoints)))));
        List<?> reported=(List<?>)faceDto(meshDto,0).get("landmarks");
        yes(reported.size()==936&&((Number)reported.get(317)).doubleValue()==meshPoints[317]);
        int[] overlayPixels=new int[64*64];Arrays.fill(overlayPixels,0xffbe9178);
        Map<String,Object> overlayRequest=SharedRuntime.map("localData",global.get("localData"),"global",true);
        Map<String,Object> overlay=SharedJson.object(SharedPortraitOverlay.render(SharedJson.encode(overlayRequest),overlayPixels,64,64,()->false));
        Map<String,Object> raster=SharedRuntime.object(overlay.get("selectionOverlay"));byte[] rgba=Base64.getDecoder().decode((String)raster.get("rgba"));
        yes(((Number)raster.get("width")).intValue()==128&&((Number)raster.get("height")).intValue()==128&&rgba.length==128*128*4);
        yes((rgba[0]&255)==38&&(rgba[1]&255)==36&&(rgba[2]&255)==34&&(rgba[3]&255)==38&&Boolean.TRUE.equals(raster.get("premultiplied")));
        yes(overlay.get("localData").equals(global.get("localData")));
        AdjustmentRegion paintedRegion=region.withPortrait(original.withGlobalSkinMask(new PhotoPortrait.BodySkinMask(fullSkin)));
        Map<String,Object> clippedRequest=SharedRuntime.map("localData",dto(parent.withRegion(0,paintedRegion)).get("localData"),"regionId",region.id,"global",true);
        Map<String,Object> clipped=SharedJson.object(SharedPortraitOverlay.render(SharedJson.encode(clippedRequest),overlayPixels,64,64,()->false));
        byte[] clippedRgba=Base64.getDecoder().decode((String)SharedRuntime.object(clipped.get("selectionOverlay")).get("rgba"));
        yes((clippedRgba[3]&255)==0&&(clippedRgba[(51*128+38)*4+3]&255)>0);
        yes(clipped.get("localData").equals(clippedRequest.get("localData"))&&region.id.equals(clipped.get("regionId")));
        Map<String,Object> faceOverlay=SharedJson.object(SharedPortraitOverlay.render(SharedJson.encode(SharedRuntime.map("localData",before.get("localData"),"index",0)),overlayPixels,64,64,()->false));
        byte[] faceRgba=Base64.getDecoder().decode((String)SharedRuntime.object(faceOverlay.get("selectionOverlay")).get("rgba"));
        int px=72,py=96;double nx=(px+.5)/240,ny=(py+.5)/240;int expectedAlpha=(int)Math.round(PortraitPreviewFilter.mask(first,64,64).weight(overlayPixels[0],nx,ny)*38);
        yes(expectedAlpha>0&&(faceRgba[(py*240+px)*4+3]&255)==expectedAlpha);
        Map<String,Object> noOverlay=SharedJson.object(SharedPortraitOverlay.render("{\"index\":-1}",overlayPixels,64,64,()->false));
        yes(noOverlay.get("selectionOverlay")==null&&local(noOverlay).isEmpty());
        rejects(()->SharedPortraitOverlay.render(SharedJson.encode(overlayRequest),overlayPixels,64,64,()->true));
        rejects(()->SharedPortraitOverlay.render("{\"global\":1}",overlayPixels,64,64,()->false));
        Map<String,Object> hitRequest=SharedRuntime.map("localData",before.get("localData"),"mode","hitFace","x",.3,"y",.4);
        Map<String,Object> hit=SharedJson.object(SharedPortraitOverlay.render(SharedJson.encode(hitRequest),overlayPixels,64,64,()->false));
        yes(((Number)hit.get("hitFace")).intValue()==0&&hit.get("localData").equals(before.get("localData")));
        hitRequest.put("x",.02);hitRequest.put("y",.02);
        yes(((Number)SharedJson.object(SharedPortraitOverlay.render(SharedJson.encode(hitRequest),overlayPixels,64,64,()->false)).get("hitFace")).intValue()==-1);
        hitRequest.put("x",-.1);rejects(()->SharedPortraitOverlay.render(SharedJson.encode(hitRequest),overlayPixels,64,64,()->false));

        PhotoPortrait.Heal h1=new PhotoPortrait.Heal(.22,.25,.3,.3,.02,.7,true),h2=new PhotoPortrait.Heal(.65,.65,.7,.7,.03,.6,false);
        PhotoPortrait withHeals=original.addHeal(h1).addHeal(h2);
        Map<String,Object> candidate=SharedRuntime.map("sx",h1.sx,"sy",h1.sy,"tx",h1.tx,"ty",h1.ty,"radius",h1.radius,"feather",h1.feather,"enabled",h1.enabled);
        Map<String,Object> automatic=change(before,"addHeals",0,SharedRuntime.map("heals",Arrays.asList(candidate,candidate)),true);
        yes(local(automatic).portrait.heals().equals(Arrays.asList(h1,h1))&&local(before).portrait.heals().isEmpty());
        rejects(()->change(before,"addHeals",0,SharedRuntime.map("heals",Collections.emptyList()),true));
        rejects(()->change(before,"addHeals",0,SharedRuntime.map("heals",Arrays.asList(candidate,SharedRuntime.map("sx",-1))),true));
        yes(local(before).portrait.heals().isEmpty());
        int width=128,height=96;int[] pixels=new int[width*height];
        for(int y=0;y<height;y++)for(int x=0;x<width;x++){int v=70+(x%13)*5+(y%11)*3;pixels[y*width+x]=0xff000000|v<<16|v<<8|v;}
        Map<String,Object> patched=SharedJson.object(SharedRetouch.patch(SharedJson.encode(SharedRuntime.map("localData",dto(PhotoLocalEdits.NONE.withPortrait(withHeals)).get("localData"),"points",Arrays.asList(.5,.5,.51,.5),"radius",.02,"tonePerFace",true)),pixels,width,height,()->false));
        List<?> heals=(List<?>)portrait(patched).get("heals");
        yes(heals.size()==2&&((Number)SharedRuntime.object(heals.get(1)).get("tx")).doubleValue()==h2.tx);
        yes(Boolean.FALSE.equals(SharedRuntime.object(heals.get(1)).get("enabled")));
        Map<String,Object> one=change(patched,"removeHeal",0,Collections.emptyMap(),true);
        yes(local(one).portrait.heals().equals(Collections.singletonList(h2)));
        yes(local(patched).portrait.heals().size()==2);
        yes(local(one).patches().size()==1&&local(one).patches().get(0).contextBlend);
        rejects(()->change(one,"removeHeal",1,Collections.emptyMap(),true));
        Map<String,Object> reset=change(one,"clearPortrait",0,Collections.emptyMap(),true);
        yes(local(reset).portrait.equals(PhotoPortrait.NONE)&&local(reset).patches().size()==1);
        String plain=SharedRetouch.request("media.retouchDescribe",SharedJson.encode(SharedRuntime.map("localData",one.get("localData"),"tonePerFace",true)),()->false);
        yes(Boolean.TRUE.equals(portrait(SharedJson.object(plain)).get("tonePerFace")));
        rejects(()->SharedRetouch.request("media.retouchChange",SharedJson.encode(SharedRuntime.map("localData",one.get("localData"),"action","clearPortrait")),()->true));
        yes(local(one).portrait.heals().size()==1);
        return checks;
    }
    public static void main(String[] args)throws Exception { System.out.println("Portrait menu checks: "+run()); }
}
