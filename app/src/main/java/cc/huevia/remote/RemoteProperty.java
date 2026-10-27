package cc.huevia.remote;

import java.io.IOException;
import java.util.Locale;

/** Scalar PTP property descriptors, with signedness and wire sizes preserved. */
public final class RemoteProperty {
    public final int code, type;
    public final long value;
    private RemoteProperty(int code, int type, long value) { this.code=code; this.type=type; this.value=value; }
    public static RemoteProperty descriptor(int expected, byte[] bytes) throws IOException {
        if(bytes==null || bytes.length<8 || u16(bytes,0)!=expected)throw new IOException("机身参数描述不完整。");
        int type=u16(bytes,2), size=size(type), current=5+size;
        if(bytes.length<current+size+1)throw new IOException("机身参数描述被截断。");
        long value=scalar(bytes,current,type);
        int form=bytes[current+size]&255, tail=current+size+1;
        if(form==0){if(bytes.length!=tail)throw new IOException("机身参数描述长度不符。");}
        else if(form==1){if(bytes.length!=tail+size*3)throw new IOException("机身参数范围不完整。");}
        else if(form==2){if(bytes.length<tail+2 || bytes.length!=tail+2+u16(bytes,tail)*size)throw new IOException("机身参数选项不完整。");}
        else throw new IOException("机身参数格式暂不支持。");
        return new RemoteProperty(expected,type,value);
    }
    public RemoteProperty update(byte[] bytes) throws IOException {
        if(bytes==null||bytes.length!=size(type))throw new IOException("机身参数值长度不符。");
        return new RemoteProperty(code,type,scalar(bytes,0,type));
    }
    private static int size(int type) throws IOException {
        if(type<1||type>8)throw new IOException("该机身参数不是受支持的标量。");
        return 1<<((type-1)/2);
    }
    private static long scalar(byte[] bytes,int offset,int type) throws IOException {
        int size=size(type); long value=0;
        for(int i=0;i<size;i++)value|=(bytes[offset+i]&255L)<<(8*i);
        if((type&1)==1&&size<8){int shift=64-size*8;value=value<<shift>>shift;}
        if(type==8&&value<0)throw new IOException("机身参数超出显示范围。");
        return value;
    }
    public static int u16(byte[] bytes,int at){return(bytes[at]&255)|((bytes[at+1]&255)<<8);}
    public static String shutter(long value){
        if(value==0xffffffffL)return "Bulb";
        if(value==0xfffffffeL)return "Time";
        if(value<=0)return "—";
        if(value<10000)return "1/"+Math.round(10000.0/value);
        return trim(value/10000.0)+"s";
    }
    public static String aperture(long value){return value<=0||value>=65535?"—":"F"+trim(value/100.0);}
    public static String compensation(long value){return String.format(Locale.ROOT,"%.1f",value/1000.0);}
    private static String trim(double value){return value==Math.rint(value)?Long.toString(Math.round(value)):String.format(Locale.ROOT,"%.1f",value);}
}
