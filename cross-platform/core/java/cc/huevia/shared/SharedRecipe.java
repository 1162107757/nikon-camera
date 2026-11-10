package cc.huevia.shared;

import cc.huevia.ncp.*;
import cc.huevia.library.SharedJson;
import java.io.*;
import java.util.*;

/** Versioned wire recipe. Native hosts use the original immutable models and validators. */
public final class SharedRecipe {
    public final String presetId;
    public final int strength;
    public final PhotoAdjustments adjustments;
    public final PhotoGeometry geometry;
    public final PhotoBorder border;
    public final PhotoLocalEdits local;
    public SharedRecipe(String json)throws IOException {
        Map<String,Object> p=SharedJson.object(json);
        if(n(p,"schema",1)!=1)throw new IOException("编辑数据版本不支持。");
        presetId=SharedRuntime.text(p,"presetId",64);strength=n(p,"strength",100);
        if(strength<0||strength>100)throw new IOException("滤镜强度超出范围。");
        try{
            PhotoCurves curves=PhotoCurves.NONE;
            if(p.get("curves")!=null){List<?> rows=list(p.get("curves"),4);int[][] v=new int[4][];for(int c=0;c<4;c++)v[c]=ints(rows.get(c),-1);curves=new PhotoCurves(v);}
            PhotoHsl hsl=p.get("hsl")==null?PhotoHsl.NONE:new PhotoHsl(ints(p.get("hsl"),24));
            Map<String,Object> palette=obj(p,"palette"),g=obj(p,"geometry"),b=obj(p,"border");
            PhotoCleanup cleanup=PhotoCleanup.NONE;String encoded=SharedRuntime.text(p,"cleanupData",1024);
            if(!encoded.isEmpty()){try(DataInputStream in=stream(encoded,512)){cleanup=PhotoCleanup.read(in);if(in.available()!=0)throw new IOException("去灰数据含多余字节。");}}
            if(p.get("cleanup")!=null){Map<String,Object> settings=obj(p,"cleanup");cleanup=new PhotoCleanup(n(settings,"amount",cleanup.amount),n(settings,"haze",cleanup.haze),n(settings,"noise",cleanup.noise),cleanup.analysis);}
            adjustments=new PhotoAdjustments(p.get("values")==null?new int[PhotoAdjustments.Parameter.values().length]:ints(p.get("values"),PhotoAdjustments.Parameter.values().length),curves,hsl,new PhotoColorPalette(n(palette,"color",0),n(palette,"tone",0),n(palette,"amount",100)),cleanup);
            geometry=new PhotoGeometry(n(g,"turns",0),n(g,"angle",0),n(g,"left",0),n(g,"top",0),n(g,"right",PhotoGeometry.UNIT),n(g,"bottom",PhotoGeometry.UNIT),n(g,"horizontalPerspective",0),n(g,"verticalPerspective",0),Boolean.TRUE.equals(g.get("mirrored")));
            String[] fields=new String[5];for(int i=0;i<5;i++)fields[i]="";
            if(b.get("fields")!=null){List<?> f=list(b.get("fields"),5);for(int i=0;i<5;i++){if(!(f.get(i) instanceof String))throw new IOException("边框文字无效。");fields[i]=(String)f.get(i);}}
            border=new PhotoBorder(n(b,"template",0),!Boolean.FALSE.equals(b.get("automatic")),SharedRuntime.text(b,"brand",96),SharedRuntime.text(b,"model",96),fields,n(b,"visible",63),n(b,"logo",0),n(b,"margin",100),n(b,"corner",100),n(b,"shadow",100),n(b,"blur",100));
            String localData=SharedRuntime.text(p,"localData",2*1024*1024);
            if(localData.isEmpty())local=PhotoLocalEdits.NONE;
            else try(DataInputStream in=stream(localData,1024*1024)){local=PhotoLocalEdits.read(in);if(in.available()!=0)throw new IOException("局部编辑含多余字节。");}
        }catch(IllegalArgumentException invalid){throw new IOException("编辑设置无效。",invalid);}
    }
    public PresetPreviewProfile profile(byte[] preset)throws IOException{
        PresetPreviewProfile base=CoreEngine.colourProfile(preset,strength,adjustments.values(),adjustments.curves,adjustments.hsl,adjustments.palette,adjustments.cleanup,local);
        return BorderPreviewProfile.of(GeometryPreviewProfile.of(base,geometry),border);
    }
    private static int n(Map<String,Object> p,String k,int v)throws IOException{return SharedRuntime.integer(p,k,v);}
    private static Map<String,Object> obj(Map<String,Object> p,String key)throws IOException{return p.get(key)==null?Collections.emptyMap():SharedRuntime.object(p.get(key));}
    private static List<?> list(Object value,int size)throws IOException{if(!(value instanceof List)||size>=0&&((List<?>)value).size()!=size)throw new IOException("编辑数组长度无效。");return (List<?>)value;}
    private static int[] ints(Object value,int size)throws IOException{List<?> rows=list(value,size);if(rows.size()>256)throw new IOException("编辑数组过长。");int[] out=new int[rows.size()];for(int i=0;i<out.length;i++){Object v=rows.get(i);if(!(v instanceof Number)||((Number)v).doubleValue()!=((Number)v).intValue())throw new IOException("编辑参数必须为整数。");out[i]=((Number)v).intValue();}return out;}
    private static DataInputStream stream(String encoded,int max)throws IOException{byte[] bytes;try{bytes=Base64.getDecoder().decode(encoded);}catch(IllegalArgumentException invalid){throw new IOException("编辑数据编码无效。",invalid);}if(bytes.length>max)throw new IOException("编辑数据过大。");return new DataInputStream(new ByteArrayInputStream(bytes));}
}
