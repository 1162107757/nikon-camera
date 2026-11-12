package cc.huevia.shared;

import cc.huevia.album.PhotoEditStore;
import cc.huevia.library.SharedJson;
import cc.huevia.ncp.*;
import java.io.*;
import java.util.*;
import java.util.function.BooleanSupplier;

/** Tentative local tools use the original binary model; this adapter never saves a draft. */
public final class SharedLocalEdits {
    private SharedLocalEdits(){}
    public static Map<String,Object> request(String operation,Map<String,Object> p,BooleanSupplier cancel)throws IOException {
        check(cancel);
        if(operation.equals("local.overlay"))return SharedSelectionOverlay.render(p,cancel);
        String original=SharedRuntime.text(p,"localData",1_400_000);
        PhotoLocalEdits start=new SharedRecipe(SharedJson.encode(SharedRuntime.map("localData",original))).local,next=start;
        byte[] before=original.isEmpty()?new byte[0]:Base64.getDecoder().decode(original);
        int selected=-1;String selectedType="";
        AdjustmentRegion seed=null;
        if(operation.equals("local.change")){
            if(!PhotoEditStore.hash(before).equals(SharedRuntime.text(p,"expectedSha",64)))throw new IOException("局部设置已变化，请重新操作。");
            String action=SharedRuntime.text(p,"action",32);Map<String,Object> value=p.containsKey("value")?SharedRuntime.object(p.get("value")):Collections.emptyMap();
            try{
                switch(action){
                    case "addMask":next=start.add(mask(value,null));selected=next.masks().size()-1;selectedType="mask";break;
                    case "setMask":{int index=index(p,start.masks().size());next=start.withMask(index,mask(value,start.masks().get(index)));selected=index;selectedType="mask";break;}
                    case "removeMask":{int index=index(p,start.masks().size());next=start.removeMask(index);selected=Math.min(index,next.masks().size()-1);selectedType="mask";break;}
                    case "addClone":next=start.add(clone(value,null));selected=next.clones().size()-1;selectedType="clone";break;
                    case "setClone":{int index=index(p,start.clones().size());next=start.withClone(index,clone(value,start.clones().get(index)));selected=index;selectedType="clone";break;}
                    case "removeClone":{int index=index(p,start.clones().size());next=start.removeClone(index);selected=Math.min(index,next.clones().size()-1);selectedType="clone";break;}
                    case "addRegion":next=start.addRegion(region(value,null));selected=next.regions().size()-1;selectedType="region";break;
                    case "setRegion":{int index=regionIndex(p,start);next=start.withRegion(index,region(value,start.regions().get(index)));selected=index;selectedType="region";break;}
                    case "removeRegion":{int index=regionIndex(p,start);next=start.removeRegion(index);selected=-1;selectedType="region";break;}
                    case "clearTools":next=new PhotoLocalEdits(Collections.emptyList(),Collections.emptyList(),start.portrait,start.regions(),start.patches());break;
                    case "replaceTools":{
                        List<?> requestedMasks=list(value.get("masks"),PhotoLocalEdits.MAX_MASKS,"蒙版"),requestedClones=list(value.get("clones"),PhotoLocalEdits.MAX_CLONES,"取样修复");
                        List<PhotoLocalEdits.Mask> masks=new ArrayList<>();List<PhotoLocalEdits.Clone> clones=new ArrayList<>();
                        for(Object item:requestedMasks){check(cancel);masks.add(mask(SharedRuntime.object(item),null));}
                        for(Object item:requestedClones){check(cancel);clones.add(clone(SharedRuntime.object(item),null));}
                        next=new PhotoLocalEdits(masks,clones,start.portrait,start.regions(),start.patches());break;
                    }
                    default:throw new IOException("未知的局部编辑操作。");
                }
            }catch(IllegalArgumentException bad){throw new IOException(bad.getMessage()==null?"局部编辑参数无效。":bad.getMessage(),bad);}
        }else if(operation.equals("local.seedRegion")){
            if(start.regions().size()>=PhotoLocalEdits.MAX_REGIONS)throw new IOException("局部调节区域已达上限。");
            String name=SharedRuntime.text(p,"name",40);
            if(name.isEmpty()){Set<String> names=new HashSet<>();for(AdjustmentRegion region:start.regions())names.add(region.name);int n=1;while(names.contains("区域 "+n))n++;name="区域 "+n;}
            try{seed=AdjustmentRegion.create(name);}catch(IllegalArgumentException bad){throw new IOException(bad.getMessage(),bad);}
        }else if(!operation.equals("local.describe"))throw new IOException("未知的局部编辑操作。");
        check(cancel);
        String data=original;
        if(!next.equals(start)){
            ByteArrayOutputStream bytes=new ByteArrayOutputStream();next.write(new DataOutputStream(bytes));
            if(bytes.size()>1_048_576)throw new IOException("局部编辑数据已达容量上限。");
            data=next.isEmpty()?"":Base64.getEncoder().encodeToString(bytes.toByteArray());
        }
        byte[] encoded=data.isEmpty()?new byte[0]:Base64.getDecoder().decode(data);
        List<Object> masks=new ArrayList<>(),clones=new ArrayList<>(),regions=new ArrayList<>();
        for(PhotoLocalEdits.Mask m:next.masks()){
            List<Double> points=new ArrayList<>();for(double point:m.points())points.add(point);
            masks.add(SharedRuntime.map("kind",m.kind.name().toLowerCase(Locale.ROOT),"x0",m.x0,"y0",m.y0,"x1",m.x1,"y1",m.y1,"radius",m.radius,"feather",m.feather,
                "inverted",m.inverted,"enabled",m.enabled,"exposure",m.exposure,"temperature",m.temperature,"saturation",m.saturation,"points",points));
        }
        for(PhotoLocalEdits.Clone c:next.clones())clones.add(SharedRuntime.map("sourceX",c.sourceX,"sourceY",c.sourceY,"targetX",c.targetX,"targetY",c.targetY,"radius",c.radius,"feather",c.feather,"enabled",c.enabled));
        for(AdjustmentRegion region:next.regions())regions.add(regionData(region));
        check(cancel);
        Map<String,Object> result=SharedRuntime.map("localData",data,"sha256",PhotoEditStore.hash(encoded),"masks",masks,"clones",clones,"regions",regions,"selectedType",selectedType,"selectedIndex",selected,
            "regionCount",next.regions().size(),"patchCount",next.patches().size(),"hasPortrait",!next.portrait.isEmpty(),"hasBodyShape",!next.portrait.bodyShape.isNeutral());
        if(seed!=null)result.put("seed",regionData(seed));return result;
    }
    private static int regionIndex(Map<String,Object> p,PhotoLocalEdits edits)throws IOException {
        String id=SharedRuntime.text(p,"regionId",64);for(int i=0;i<edits.regions().size();i++)if(edits.regions().get(i).id.equals(id))return i;throw new IOException("所选局部区域已不存在。");
    }
    private static final String[] ADJUSTMENT_KEYS={"values","curves","hsl","palette","cleanupData","cleanup"};
    private static Map<String,Object> adjustments(PhotoAdjustments value)throws IOException {
        Map<String,Object> all=SharedEdits.recipe(new PhotoEditStore.Draft("0000000000000000000000000000000000000000000000000000000000000000",null,"无滤镜",100,value,PhotoGeometry.NONE,PhotoBorder.NONE,PhotoLocalEdits.NONE,false));
        Map<String,Object> result=new LinkedHashMap<>();for(String key:ADJUSTMENT_KEYS)if(all.containsKey(key))result.put(key,all.get(key));return result;
    }
    private static Map<String,Object> regionData(AdjustmentRegion r)throws IOException {
        List<Object> strokes=new ArrayList<>(),shapes=new ArrayList<>();
        for(PhotoPortrait.Stroke stroke:r.strokes){List<Double> points=new ArrayList<>();for(double point:stroke.points())points.add(point);strokes.add(SharedRuntime.map("points",points,"radius",stroke.radius,"feather",stroke.feather,"erase",stroke.erase));}
        for(SelectionShape shape:r.shapes)shapes.add(SharedRuntime.map("kind",shape.kind.name().toLowerCase(Locale.ROOT),"left",shape.left,"top",shape.top,"right",shape.right,"bottom",shape.bottom,"feather",shape.feather,"subtract",shape.subtract,"strokeIndex",shape.strokeIndex));
        return SharedRuntime.map("id",r.id,"name",r.name,"enabled",r.enabled,"amount",r.amount,"inverted",r.inverted,"strokes",strokes,"shapes",shapes,"adjustments",adjustments(r.adjustments),"hasPortrait",!r.portrait.isEmpty(),"hasSkinMask",r.skinMask!=null);
    }
    private static AdjustmentRegion region(Map<String,Object> p,AdjustmentRegion old)throws IOException {
        String id=p.containsKey("id")?SharedRuntime.text(p,"id",64):old==null?UUID.randomUUID().toString():old.id;
        if(old!=null&&!id.equals(old.id))throw new IOException("局部区域标识不能改变。");
        String name=p.containsKey("name")?SharedRuntime.text(p,"name",40):old==null?"局部调整":old.name;
        List<PhotoPortrait.Stroke> strokes=old==null?Collections.emptyList():old.strokes;
        if(p.containsKey("strokes")){
            List<?> list=list(p.get("strokes"),AdjustmentRegion.MAX_STROKES,"选区画笔");strokes=new ArrayList<>();
            for(Object value:list){Map<String,Object> s=SharedRuntime.object(value);List<?> raw=list(s.get("points"),PhotoLocalEdits.MAX_BRUSH_POINTS*2,"选区轨迹");double[] points=new double[raw.size()];for(int i=0;i<points.length;i++)points[i]=number(raw.get(i),"选区轨迹");
                strokes.add(new PhotoPortrait.Stroke(points,number(s,"radius",.05),number(s,"feather",.3),bool(s,"erase",false)));
            }
        }
        List<SelectionShape> shapes=old==null?Collections.emptyList():old.shapes;
        if(p.containsKey("shapes")){
            List<?> list=list(p.get("shapes"),AdjustmentRegion.MAX_STROKES,"形状选区");shapes=new ArrayList<>();
            for(Object value:list){Map<String,Object> s=SharedRuntime.object(value);String kind=SharedRuntime.text(s,"kind",16).toUpperCase(Locale.ROOT);SelectionShape.Kind type;
                try{type=SelectionShape.Kind.valueOf(kind);}catch(IllegalArgumentException bad){throw new IOException("形状选区类型无效。",bad);}
                shapes.add(new SelectionShape(type,number(s,"left",.25),number(s,"top",.25),number(s,"right",.75),number(s,"bottom",.75),number(s,"feather",.3),bool(s,"subtract",false),integer(s,"strokeIndex",strokes.size())));
            }
        }
        PhotoAdjustments settings=old==null?PhotoAdjustments.NONE:old.adjustments;
        if(p.containsKey("adjustments")){
            Map<String,Object> incoming=SharedRuntime.object(p.get("adjustments")),merged=adjustments(settings);
            Set<String> keys=new HashSet<>(Arrays.asList(ADJUSTMENT_KEYS));
            for(Map.Entry<String,Object> entry:incoming.entrySet()){
                String key=entry.getKey();if(!keys.contains(key))throw new IOException("局部调节字段无效。");Object value=entry.getValue();
                if((key.equals("palette")||key.equals("cleanup"))&&merged.get(key) instanceof Map){Map<String,Object> combined=new LinkedHashMap<>(SharedRuntime.object(merged.get(key)));combined.putAll(SharedRuntime.object(value));value=combined;}
                merged.put(key,value);
            }
            settings=new SharedRecipe(SharedJson.encode(merged)).adjustments;
        }
        return new AdjustmentRegion(id,name,bool(p,"enabled",old==null||old.enabled),number(p,"amount",old==null?1:old.amount),strokes,settings,
            old==null?PhotoPortrait.NONE:old.portrait,old==null?PhotoPortrait.Settings.NONE:old.skinSettings,old==null?null:old.skinMask,shapes,bool(p,"inverted",old!=null&&old.inverted));
    }
    private static List<?> list(Object value,int maximum,String name)throws IOException {if(!(value instanceof List)||((List<?>)value).size()>maximum)throw new IOException(name+"数据无效或超限。");return (List<?>)value;}
    private static int index(Map<String,Object> p,int count)throws IOException {
        int index=integer(p,"index",-1);if(index<0||index>=count)throw new IOException("所选局部调整已不存在。");return index;
    }
    private static PhotoLocalEdits.Mask mask(Map<String,Object> p,PhotoLocalEdits.Mask old)throws IOException {
        PhotoLocalEdits.Kind kind=old==null?PhotoLocalEdits.Kind.BRUSH:old.kind;
        if(p.containsKey("kind")){
            Object raw=p.get("kind");if(!(raw instanceof String))throw new IOException("蒙版类型无效。");
            try{PhotoLocalEdits.Kind requested=PhotoLocalEdits.Kind.valueOf(((String)raw).toUpperCase(Locale.ROOT));if(old!=null&&requested!=old.kind)throw new IOException("请新建另一种蒙版，保留当前轨迹。");kind=requested;}
            catch(IllegalArgumentException bad){throw new IOException("蒙版类型无效。",bad);}
        }
        double[] points=old==null?(kind==PhotoLocalEdits.Kind.BRUSH?new double[]{.5,.5}:new double[0]):old.points();
        if(p.containsKey("points")){
            Object raw=p.get("points");if(!(raw instanceof List))throw new IOException("画笔轨迹无效。");List<?> list=(List<?>)raw;
            if(list.size()>PhotoLocalEdits.MAX_BRUSH_POINTS*2||list.size()%2!=0)throw new IOException("画笔轨迹超限。");
            points=new double[list.size()];for(int i=0;i<points.length;i++)points[i]=number(list.get(i),"画笔轨迹");
        }
        double origin=kind==PhotoLocalEdits.Kind.BRUSH?0:kind==PhotoLocalEdits.Kind.LINEAR?.2:.5;
        return new PhotoLocalEdits.Mask(kind,number(p,"x0",old==null?origin:old.x0),number(p,"y0",old==null?origin:old.y0),
            number(p,"x1",old==null?(kind==PhotoLocalEdits.Kind.RADIAL?.22:kind==PhotoLocalEdits.Kind.LINEAR?.8:0):old.x1),
            number(p,"y1",old==null?(kind==PhotoLocalEdits.Kind.RADIAL?.22:kind==PhotoLocalEdits.Kind.LINEAR?.8:0):old.y1),
            number(p,"radius",old==null?.08:old.radius),number(p,"feather",old==null?(kind==PhotoLocalEdits.Kind.LINEAR?.7:.6):old.feather),bool(p,"inverted",old!=null&&old.inverted),bool(p,"enabled",old==null||old.enabled),
            integer(p,"exposure",old==null?0:old.exposure),integer(p,"temperature",old==null?0:old.temperature),integer(p,"saturation",old==null?0:old.saturation),points);
    }
    private static PhotoLocalEdits.Clone clone(Map<String,Object> p,PhotoLocalEdits.Clone old)throws IOException {
        return new PhotoLocalEdits.Clone(number(p,"sourceX",old==null?.25:old.sourceX),number(p,"sourceY",old==null?.5:old.sourceY),
            number(p,"targetX",old==null?.75:old.targetX),number(p,"targetY",old==null?.5:old.targetY),number(p,"radius",old==null?.08:old.radius),number(p,"feather",old==null?.6:old.feather),bool(p,"enabled",old==null||old.enabled));
    }
    private static double number(Map<String,Object> p,String key,double fallback)throws IOException {return p.containsKey(key)?number(p.get(key),key):fallback;}
    private static double number(Object value,String key)throws IOException {if(!(value instanceof Number)||!Double.isFinite(((Number)value).doubleValue()))throw new IOException(key+"参数无效。");return ((Number)value).doubleValue();}
    private static int integer(Map<String,Object> p,String key,int fallback)throws IOException {
        if(!p.containsKey(key))return fallback;double value=number(p.get(key),key);if(value!=Math.rint(value)||value<Integer.MIN_VALUE||value>Integer.MAX_VALUE)throw new IOException(key+"参数无效。");return (int)value;
    }
    private static boolean bool(Map<String,Object> p,String key,boolean fallback)throws IOException {
        if(!p.containsKey(key))return fallback;if(!(p.get(key) instanceof Boolean))throw new IOException(key+"参数无效。");return (Boolean)p.get(key);
    }
    private static void check(BooleanSupplier cancelled)throws InterruptedIOException {if(cancelled.getAsBoolean())throw new InterruptedIOException("局部编辑已取消。");}
}
