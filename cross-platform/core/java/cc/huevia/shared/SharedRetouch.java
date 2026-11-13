package cc.huevia.shared;

import cc.huevia.album.PhotoEditStore;
import cc.huevia.library.SharedJson;
import cc.huevia.ncp.*;
import java.io.*;
import java.util.*;
import java.util.function.BooleanSupplier;

/** The original immutable portrait/body/patch models, edited in a tentative transaction. */
public final class SharedRetouch {
    private SharedRetouch() {}
    public static PhotoLocalEdits local(Map<String,Object> p)throws IOException {
        return new SharedRecipe(SharedJson.encode(SharedRuntime.map("localData",SharedRuntime.text(p,"localData",1_400_000)))).local;
    }
    private static int regionIndex(PhotoLocalEdits local,String id)throws IOException {
        for(int i=0;i<local.regions().size();i++)if(local.regions().get(i).id.equals(id))return i;
        throw new IOException("所选局部区域已不存在。");
    }
    public static PhotoPortrait portrait(PhotoLocalEdits local,Map<String,Object> p)throws IOException {
        String id=SharedRuntime.text(p,"regionId",64);return id.isEmpty()?local.portrait:local.regions().get(regionIndex(local,id)).portrait;
    }
    public static PhotoLocalEdits withPortrait(PhotoLocalEdits local,Map<String,Object> p,PhotoPortrait value)throws IOException {
        String id=SharedRuntime.text(p,"regionId",64);if(id.isEmpty())return local.withPortrait(value);
        int index=regionIndex(local,id);return local.withRegion(index,local.regions().get(index).withPortrait(value));
    }
    public static String resultFor(PhotoLocalEdits local,Map<String,Object> p,BooleanSupplier cancel)throws IOException {
        return result(local,cancel,scope(p),SharedRuntime.text(p,"regionId",64));
    }
    public static String request(String operation,String json,BooleanSupplier cancel)throws IOException {
        Map<String,Object> p=SharedJson.object(json);check(cancel);PhotoLocalEdits local=local(p);PhotoPortrait portrait=portrait(local,p);
        if(operation.equals("media.retouchChange")) {
            String action=SharedRuntime.text(p,"action",32);Map<String,Object> v=p.get("value")==null?Collections.emptyMap():SharedRuntime.object(p.get("value"));
            // Return only a tentative preview copy in the original photo coordinate space.
            if(action.equals("beforeBody"))return resultFor(local.withPortrait(local.portrait.withBodyShape(PhotoBodyShape.NONE)),p,cancel);
            int index=SharedRuntime.integer(p,"index",0);
            try {
                switch(action) {
                    case "face": {
                        PhotoPortrait.Face f=face(portrait,index);PhotoPortrait.Settings s=f.settings;
                        s=new PhotoPortrait.Settings(n(v,"brightness",s.brightness),n(v,"warmth",s.warmth),n(v,"redness",s.redness),n(v,"smoothing",s.smoothing),n(v,"texture",s.texture),n(v,"light",s.light),n(v,"shadows",s.shadows));
                        PortraitRetouch r=f.retouch;for(PortraitRetouch.Parameter key:PortraitRetouch.Parameter.values())if(v.containsKey(key.name()))r=r.with(key,n(v,key.name(),r.get(key)));
                        f=f.withBounds(d(v,"cx",f.cx),d(v,"cy",f.cy),d(v,"rx",f.rx),d(v,"ry",f.ry),d(v,"roll",f.roll)).withSettings(s).withRetouch(r);
                        if(v.containsKey("enabled"))f=f.withEnabled(flag(v,"enabled",f.enabled));
                        if(v.containsKey("toneBody")&&flag(v,"toneBody",false)&&f.bodySkinMask==null)throw new IOException("请先识别此人物的全身皮肤。");
                        if(hasTone(v))f=f.withTone(tone(v,f.tone));portrait=portrait.withFace(index,f);break;
                    }
                    case "removeFace":face(portrait,index);portrait=portrait.removeFace(index);break;
                    case "faceStroke": {
                        PhotoPortrait.Face f=face(portrait,index);Object raw=v.get("points");
                        if(!(raw instanceof List)||((List<?>)raw).size()<2||((List<?>)raw).size()>1024||(((List<?>)raw).size()&1)!=0)throw new IOException("人像笔触点无效。");
                        double[] points=new double[((List<?>)raw).size()];for(int i=0;i<points.length;i++)points[i]=number(((List<?>)raw).get(i));
                        portrait=portrait.withFace(index,f.addStroke(new PhotoPortrait.Stroke(points,d(v,"radius",.025),.65,flag(v,"erase",false))));break;
                    }
                    case "regionSkin": {
                        String id=SharedRuntime.text(p,"regionId",64);if(id.isEmpty())throw new IOException("请先选择涂抹区域。");
                        int target=regionIndex(local,id);AdjustmentRegion region=local.regions().get(target);PhotoPortrait.Settings s=region.skinSettings;
                        s=new PhotoPortrait.Settings(n(v,"brightness",s.brightness),n(v,"warmth",s.warmth),n(v,"redness",s.redness),n(v,"smoothing",s.smoothing),n(v,"texture",s.texture),n(v,"light",s.light),n(v,"shadows",s.shadows));
                        local=local.withRegion(target,region.withSkinSettings(s));break;
                    }
                    case "manualFace":portrait=portrait.addFace(new PhotoPortrait.Face(d(v,"cx",.5),d(v,"cy",.4),d(v,"rx",.12),d(v,"ry",.18),0,n(v,"skinR",190),n(v,"skinG",145),n(v,"skinB",120),true,PhotoPortrait.Settings.NONE,Collections.emptyList()));break;
                    case "skin": {
                        if(portrait.globalSkinMask==null)throw new IOException("请先分析皮肤范围。");if(skinPixels(portrait.globalSkinMask)<32)throw new IOException("未找到可确认的皮肤范围，请重试或使用局部画笔。");
                        portrait=portrait.withSkinSmoothing(n(v,"smoothing",portrait.skinSmoothing));
                        if(v.containsKey("tone"))portrait=portrait.withGlobalTone(new PhotoPortrait.Tone(1,n(v,"tone",0),d(v,"amount",.25),portrait.globalTone.body));
                        if(hasTone(v))portrait=portrait.withGlobalTone(tone(v,portrait.globalTone));
                        PortraitRetouch r=portrait.retouch;for(PortraitRetouch.Parameter key:PortraitRetouch.Parameter.values())if(v.containsKey(key.name()))r=r.with(key,n(v,key.name(),r.get(key)));
                        portrait=portrait.withRetouch(r);break;
                    }
                    case "body": {
                        PhotoBodyShape b=portrait.bodyShape;int tool=n(v,"tool",0);PhotoBodyShape.Area a=b.area(tool);
                        a=new PhotoBodyShape.Area(d(v,"left",a.left),d(v,"top",a.top),d(v,"right",a.right),d(v,"bottom",a.bottom),n(v,"amount",a.amount));
                        b=b.withArea(tool,a).withSingleLeg(v.containsKey("singleLeg")?Boolean.TRUE.equals(v.get("singleLeg")):b.singleLeg);
                        if(v.containsKey("protection"))b=b.withBackgroundProtection(b.backgroundMask,n(v,"protection",b.backgroundProtection));portrait=portrait.withBodyShape(b);break;
                    }
                    case "removePatch":if(index<0||index>=local.patches().size())throw new IOException("修补已不存在。");local=local.removePatch(index);break;
                    case "removeHeal":if(index<0||index>=portrait.heals().size())throw new IOException("祛痘记录已不存在。");portrait=portrait.removeHeal(index);break;
                    case "addHeals": {
                        Object raw=v.get("heals");if(!(raw instanceof List)||((List<?>)raw).isEmpty()||((List<?>)raw).size()>24)throw new IOException("请选择需要修复的瑕疵。");
                        for(Object item:(List<?>)raw){Map<String,Object> h=SharedRuntime.object(item);portrait=portrait.addHeal(new PhotoPortrait.Heal(d(h,"sx",-1),d(h,"sy",-1),d(h,"tx",-1),d(h,"ty",-1),d(h,"radius",-1),d(h,"feather",.7),flag(h,"enabled",true)));}
                        break;
                    }
                    case "toneScope": {
                        if(!v.containsKey("perFace"))throw new IOException("请选择肤色应用范围。");
                        boolean perFace=flag(v,"perFace",false);PhotoPortrait.Face current=index>=0&&index<portrait.faces().size()?portrait.faces().get(index):null;
                        PhotoPortrait.Tone prior=perFace?portrait.globalTone:current==null?PhotoPortrait.Tone.NONE:current.tone;
                        // Match the original dialog's switchToneEditing transaction. The
                        // editing scope is session state, not a new binary recipe field.
                        if(perFace&&current!=null&&!portrait.globalTone.isNeutral())
                            portrait=portrait.withGlobalTone(PhotoPortrait.Tone.NONE).withFace(index,current.withTone(new PhotoPortrait.Tone(prior.presetId,prior.colorRGB,prior.amount,false)));
                        else if(!perFace&&!prior.isNeutral())
                            portrait=portrait.withGlobalTone(new PhotoPortrait.Tone(prior.presetId,prior.colorRGB,prior.amount,false));
                        p.put("tonePerFace",perFace);break;
                    }
                    case "clearPortrait":portrait=PhotoPortrait.NONE;break;
                    default:throw new IOException("未知的人像操作。");
                }
            }catch(IllegalArgumentException bad){throw new IOException(bad.getMessage(),bad);}
            local=withPortrait(local,p,portrait);
        }else if(!operation.equals("media.retouchDescribe"))throw new IOException("未知的人像操作。");
        check(cancel);return resultFor(local,p,cancel);
    }
    public static String analysis(String json,String facesJson,String skin,String bodyJson,String foreground,BooleanSupplier cancel)throws IOException {
        Map<String,Object> p=SharedJson.object(json);PhotoLocalEdits local=local(p);PhotoPortrait portrait=portrait(local,p);boolean locate=flag(p,"locate",true);check(cancel);
        if(facesJson!=null&&(!"skin".equals(p.get("mode"))||portrait.faces().isEmpty())) {
            List<PhotoPortrait.Face> faces=new ArrayList<>();Object raw=SharedJson.object("{\"faces\":"+facesJson+"}").get("faces");
            if(!(raw instanceof List)||((List<?>)raw).size()>PhotoPortrait.MAX_FACES)throw new IOException("人脸分析结果无效。");
            for(Object value:(List<?>)raw){Map<String,Object> v=SharedRuntime.object(value);PhotoPortrait.Face f=readFace(v);
                for(PhotoPortrait.Face old:portrait.faces())if(Math.hypot(old.cx-f.cx,old.cy-f.cy)<Math.max(old.rx,f.rx)*.7){f=f.withSettings(old.settings).withRetouch(old.retouch).withTone(old.tone).withStrokes(old.strokes).withEnabled(old.enabled).withBodySkinMask(old.bodySkinMask);break;}faces.add(f);}
            portrait=portrait.withFaces(faces);
        }
        if(skin!=null&&!skin.isEmpty())portrait=portrait.withGlobalSkinMask(mask(skin));
        if(locate&&bodyJson!=null&&!bodyJson.isEmpty()) {
            Map<String,Object> v=SharedJson.object(bodyJson);PhotoBodyShape b=portrait.bodyShape;
            double left=d(v,"left",.25),right=d(v,"right",.75),top=d(v,"top",.25),bottom=Math.min(.96,d(v,"bottom",.9));
            if(right-left>=.06&&bottom-top>=.08){b=b.withArea(0,new PhotoBodyShape.Area(left,top,right,bottom,b.body.amount));if(!Boolean.FALSE.equals(v.get("legsVisible"))){double legs=Math.min(bottom-.09,d(v,"legTop",top+(bottom-top)*.58));b=b.withArea(1,new PhotoBodyShape.Area(left,legs,right,bottom,b.legs.amount));b=b.withArea(2,new PhotoBodyShape.Area(left,legs,right,bottom,b.length.amount));}}
            portrait=portrait.withBodyShape(b);
        }
        if(foreground!=null&&!foreground.isEmpty()){int amount=n(p,"protection",70);if(amount<0||amount>100)throw new IOException("背景保护强度无效。");portrait=portrait.withBodyShape(portrait.bodyShape.withBackgroundProtection(mask(foreground),amount));}
        check(cancel);return resultFor(withPortrait(local,p,portrait),p,cancel);
    }
    public static String patch(String json,int[] pixels,int width,int height,BooleanSupplier cancel)throws IOException {
        Map<String,Object> p=SharedJson.object(json);PhotoLocalEdits local=local(p);Object raw=p.get("points");
        if(!(raw instanceof List)||((List<?>)raw).size()<2||((List<?>)raw).size()>1024||(((List<?>)raw).size()&1)!=0)throw new IOException("修补轨迹无效。");
        double[] points=new double[((List<?>)raw).size()];for(int i=0;i<points.length;i++)points[i]=number(((List<?>)raw).get(i));
        try {AdjustmentRegion selection=AdjustmentRegion.create("自动修补").addStroke(PhotoPatchSampler.automaticStroke(points,d(p,"radius",.025)));
            PhotoPatch patch=PhotoPatchSampler.choose(pixels,width,height,selection,cancel).contextBlend(true);check(cancel);return result(local.addPatch(patch),cancel,scope(p));
        }catch(IllegalArgumentException bad){throw new IOException(bad.getMessage(),bad);}
    }
    public static String result(PhotoLocalEdits local,BooleanSupplier cancel)throws IOException {
        return result(local,cancel,null);
    }
    public static String result(PhotoLocalEdits local,BooleanSupplier cancel,Boolean tonePerFace)throws IOException {
        return result(local,cancel,tonePerFace,"");
    }
    private static String result(PhotoLocalEdits local,BooleanSupplier cancel,Boolean tonePerFace,String regionId)throws IOException {
        ByteArrayOutputStream bytes=new ByteArrayOutputStream();local.write(new DataOutputStream(bytes));if(bytes.size()>1_048_576)throw new IOException("编辑数据已达上限。");
        String data=local.isEmpty()?"":Base64.getEncoder().encodeToString(bytes.toByteArray());Map<String,Object> result=SharedLocalEdits.request("local.describe",SharedRuntime.map("localData",data),cancel);
        PhotoPortrait p=regionId.isEmpty()?local.portrait:local.regions().get(regionIndex(local,regionId)).portrait;boolean storedPerFace=false;List<Object> faces=new ArrayList<>();for(PhotoPortrait.Face f:p.faces()){storedPerFace|=f.tone.presetId!=SkinTone.ORIGINAL;Map<String,Object> v=SharedRuntime.map("cx",f.cx,"cy",f.cy,"rx",f.rx,"ry",f.ry,"roll",f.roll,"enabled",f.enabled,"brightness",f.settings.brightness,"warmth",f.settings.warmth,"redness",f.settings.redness,"smoothing",f.settings.smoothing,"texture",f.settings.texture,"light",f.settings.light,"shadows",f.settings.shadows,"hasLandmarks",f.landmarks!=null,"hasBodySkinMask",f.bodySkinMask!=null,"toneBody",f.tone.body,"strokeCount",f.strokes.size(),"toneId",f.tone.presetId,"toneRgb",f.tone.colorRGB,"toneAmount",f.tone.amount);if(f.landmarks!=null){List<Object> points=new ArrayList<>();for(double point:f.landmarks.copyPoints())points.add(point);v.put("landmarks",points);}for(PortraitRetouch.Parameter k:PortraitRetouch.Parameter.values())v.put(k.name(),f.retouch.get(k));faces.add(v);}
        List<Object> body=new ArrayList<>();for(int i=0;i<3;i++){PhotoBodyShape.Area a=p.bodyShape.area(i);body.add(SharedRuntime.map("left",a.left,"top",a.top,"right",a.right,"bottom",a.bottom,"amount",a.amount));}
        Map<String,Object> skin=SharedRuntime.map("smoothing",p.skinSmoothing,"toneId",p.globalTone.presetId,"toneRgb",p.globalTone.colorRGB,"toneAmount",p.globalTone.amount,"toneBody",p.globalTone.body);for(PortraitRetouch.Parameter k:PortraitRetouch.Parameter.values())skin.put(k.name(),p.retouch.get(k));
        List<Object> heals=new ArrayList<>();for(PhotoPortrait.Heal h:p.heals())heals.add(SharedRuntime.map("sx",h.sx,"sy",h.sy,"tx",h.tx,"ty",h.ty,"radius",h.radius,"feather",h.feather,"enabled",h.enabled));
        List<Object> tones=new ArrayList<>();for(SkinTone.Entry tone:SkinTone.presets())tones.add(SharedRuntime.map("id",tone.id,"name",tone.label,"color",tone.colorRGB));result.put("tones",tones);
        result.put("portrait",SharedRuntime.map("faces",faces,"body",body,"skin",skin,"heals",heals,"tonePerFace",tonePerFace==null?storedPerFace:tonePerFace,"hasSkinMask",p.globalSkinMask!=null,"skinPixels",skinPixels(p.globalSkinMask),"hasBodyMask",p.bodyShape.backgroundMask!=null,"protection",p.bodyShape.backgroundProtection,"singleLeg",p.bodyShape.singleLeg));
        if(!regionId.isEmpty()){PhotoPortrait.Settings s=local.regions().get(regionIndex(local,regionId)).skinSettings;SharedRuntime.object(result.get("portrait")).put("regionSkin",SharedRuntime.map("brightness",s.brightness,"warmth",s.warmth,"redness",s.redness,"smoothing",s.smoothing,"texture",s.texture,"light",s.light,"shadows",s.shadows));}
        result.put("regionId",regionId);result.put("sourcePositioning",!local.portrait.bodyShape.isNeutral());check(cancel);return SharedJson.encode(result);
    }
    public static PhotoPortrait.Face readFace(Map<String,Object> v)throws IOException {
        PhotoPortrait.Face f=new PhotoPortrait.Face(d(v,"cx",.5),d(v,"cy",.5),d(v,"rx",.1),d(v,"ry",.15),d(v,"roll",0),n(v,"skinR",180),n(v,"skinG",140),n(v,"skinB",120),true,PhotoPortrait.Settings.NONE,Collections.emptyList());
        if(v.get("landmarks") instanceof List){List<?> raw=(List<?>)v.get("landmarks");double[] points=new double[raw.size()];for(int i=0;i<points.length;i++)points[i]=number(raw.get(i));f=f.withLandmarks(new PhotoPortrait.Landmarks(points));}
        if(v.get("skinMask") instanceof Map){Map<String,Object> m=SharedRuntime.object(v.get("skinMask"));try{f=f.withSkinMask(new PhotoPortrait.SkinMask(d(m,"left",-1),d(m,"top",-1),d(m,"right",1),d(m,"bottom",1),Base64.getDecoder().decode(SharedRuntime.text(m,"data",32768))));}catch(IllegalArgumentException bad){throw new IOException("面部皮肤分析结果无效。",bad);}}
        return f;
    }
    private static PhotoPortrait.Face face(PhotoPortrait p,int i)throws IOException{if(i<0||i>=p.faces().size())throw new IOException("请先选择一张人脸。");return p.faces().get(i);}
    public static Boolean scope(Map<String,Object> p)throws IOException{return p.containsKey("tonePerFace")?flag(p,"tonePerFace",false):null;}
    private static boolean hasTone(Map<String,Object> p){return p.containsKey("toneId")||p.containsKey("toneAmount")||p.containsKey("toneRgb")||p.containsKey("toneBody");}
    private static PhotoPortrait.Tone tone(Map<String,Object> p,PhotoPortrait.Tone prior)throws IOException{
        double amount=d(p,"toneAmount",prior.amount);boolean body=flag(p,"toneBody",prior.body);
        if(p.containsKey("toneRgb"))return SkinTone.custom(n(p,"toneRgb",prior.colorRGB),amount,body);
        int id=n(p,"toneId",prior.presetId);
        if(id==SkinTone.CUSTOM){if(prior.presetId!=SkinTone.CUSTOM)throw new IOException("请先选择自定义肤色。");return SkinTone.custom(prior.colorRGB,amount,body);}
        return SkinTone.preset(id,amount,body);
    }
    private static boolean flag(Map<String,Object> p,String key,boolean fallback)throws IOException{if(!p.containsKey(key))return fallback;Object value=p.get(key);if(!(value instanceof Boolean))throw new IOException("编辑开关无效。");return (Boolean)value;}
    private static int skinPixels(PhotoPortrait.BodySkinMask mask){int count=0;if(mask!=null)for(byte value:mask.copyCoverage())if((value&255)>16)count++;return count;}
    private static PhotoPortrait.BodySkinMask mask(String value)throws IOException{try{return new PhotoPortrait.BodySkinMask(Base64.getDecoder().decode(value));}catch(IllegalArgumentException bad){throw new IOException("分析蒙版无效。",bad);}}
    private static int n(Map<String,Object> p,String key,int fallback)throws IOException{return SharedRuntime.integer(p,key,fallback);}
    private static double d(Map<String,Object> p,String key,double fallback)throws IOException{return p.containsKey(key)?number(p.get(key)):fallback;}
    private static double number(Object value)throws IOException{if(!(value instanceof Number)||!Double.isFinite(((Number)value).doubleValue()))throw new IOException("编辑数值无效。");return ((Number)value).doubleValue();}
    private static void check(BooleanSupplier cancel)throws InterruptedIOException{if(cancel.getAsBoolean()||Thread.currentThread().isInterrupted())throw new InterruptedIOException("编辑计算已停止。");}
}
