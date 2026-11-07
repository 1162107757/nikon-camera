package cc.huevia.ncp;
import java.io.*;
import java.util.Arrays;

/** Independent colour/texture controls; contains no photo or person coordinates. */
public final class PortraitRetouch {
    public enum Parameter {
        TEXTURE("纹理保留",0,100,70), EVENNESS("匀肤",0,100,0), SHINE("去油光",0,100,0),
        EYE_DETAIL("眼神清晰",0,100,0), EYE_WHITE("眼白净化",0,100,0), TEETH("牙齿去黄",0,100,0),
        UNDER_EYE("眼下修复",0,100,0), FILL("柔光补光",0,100,0),
        LIGHT_X("光源左右",-100,100,0), LIGHT_Y("光源上下",-100,100,0), NATURAL("自然精修",0,100,0);
        public final String label;public final int min,max,initial;
        Parameter(String label,int min,int max,int initial){this.label=label;this.min=min;this.max=max;this.initial=initial;}
    }
    public static final PortraitRetouch NONE=new PortraitRetouch(defaults());
    private final int[] values;
    public PortraitRetouch(int[] values){if(values==null||values.length!=Parameter.values().length)throw new IllegalArgumentException("人像精修参数数量无效。");this.values=values.clone();for(Parameter p:Parameter.values())if(get(p)<p.min||get(p)>p.max)throw new IllegalArgumentException(p.label+"超出范围。");}
    private static int[] defaults(){int[] v=new int[Parameter.values().length];for(Parameter p:Parameter.values())v[p.ordinal()]=p.initial;return v;}
    public int get(Parameter p){return values[p.ordinal()];}
    public PortraitRetouch with(Parameter p,int value){int[] v=values.clone();v[p.ordinal()]=value;return new PortraitRetouch(v);}
    public boolean hasStoredState(){return !equals(NONE);}
    public boolean hasSkinEffect(){return get(Parameter.EVENNESS)>0||get(Parameter.SHINE)>0||get(Parameter.NATURAL)>0;}
    public boolean hasFaceEffect(){return get(Parameter.EYE_DETAIL)>0||get(Parameter.EYE_WHITE)>0||get(Parameter.TEETH)>0||get(Parameter.UNDER_EYE)>0||get(Parameter.FILL)>0||get(Parameter.NATURAL)>0;}
    public int effective(Parameter p){int direct=get(p),n=get(Parameter.NATURAL);switch(p){case EVENNESS:return Math.max(direct,n*30/100);case SHINE:return Math.max(direct,n*40/100);case FILL:return Math.max(direct,n*25/100);case UNDER_EYE:return Math.max(direct,n*25/100);default:return direct;}}
    public void write(DataOutput out)throws IOException{out.writeInt(values.length);for(int v:values)out.writeInt(v);}
    public static PortraitRetouch read(DataInput in)throws IOException{if(in.readInt()!=Parameter.values().length)throw new IOException("人像精修参数版本无效。");int[] v=new int[Parameter.values().length];for(int i=0;i<v.length;i++)v[i]=in.readInt();try{return new PortraitRetouch(v);}catch(IllegalArgumentException e){throw new IOException("人像精修参数损坏。",e);}}
    @Override public boolean equals(Object o){return o instanceof PortraitRetouch&&Arrays.equals(values,((PortraitRetouch)o).values);}
    @Override public int hashCode(){return Arrays.hashCode(values);}
}
