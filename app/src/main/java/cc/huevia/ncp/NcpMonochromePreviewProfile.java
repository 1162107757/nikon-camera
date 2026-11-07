package cc.huevia.ncp;

import java.io.IOException;
import java.nio.charset.StandardCharsets;

/**
 * Independent phone approximation for the audited legacy NCP 0100 Monochrome subset.
 * The stored curve follows monochrome conversion; its editor Gamma is not applied twice.
 * The input file, the old colour NCP path and the camera-write converter are never changed.
 * Filter/toning coefficients belong to this app model, not a recovered Nikon pipeline.
 */
public final class NcpMonochromePreviewProfile implements PresetPreviewProfile {
    public static final String MODEL_VERSION="ncp-0100-monochrome-filter-toning-v1";
    // Designed encoded-RGB sensitivities, not measured Nikon filter internals.
    private static final double[][] FILTER_WEIGHTS={
            {.2126,.7152,.0722},{.35,.60,.05},{.55,.42,.03},{.80,.18,.02},{.15,.80,.05}
    };
    // Paired NX MC Off/Sepia4/Yellow4 RGB16 observations fix the colour direction
    // and tone-dependent magnitude. Each row is A+B*v+C*v*v at density four.
    // This compact app response and linear density scaling are not Nikon's pipeline.
    private static final double[][] SEPIA_AT_FOUR={
            {.090915,.060560,-.071558},
            {-.021875,-.016636,.020405},
            {-.119165,-.106714,.122810}
    };
    private static final double[][] YELLOW_AT_FOUR={
            {.030997,.022321,-.027216},
            {.009953,.007150,-.008577},
            {-.126194,-.116398,.132976}
    };
    private final String registrationName;
    private final int sharpening,filterEffect,toning,toningDensity;
    private final int[] samples;

    private NcpMonochromePreviewProfile(byte[] data,String name){
        registrationName=name;sharpening=(data[40]&255)-128;filterEffect=data[45]&255;toning=data[46]&255;toningDensity=data[47]&255;
        samples=new int[257];for(int i=0;i<samples.length;i++)samples[i]=u16(data,120+i*2);
    }
    /** Every accepted active parameter has an explicit path; unknown controls are rejected. */
    public static NcpMonochromePreviewProfile fromNcp(byte[] original)throws IOException{
        require(original!=null&&original.length==638,"仅支持已核验的 638 字节 NCP 0100 单色结构。");
        byte[] data=original.clone();try{NcpFile.validate(data);}catch(IllegalArgumentException invalid){throw unsupported(invalid.getMessage());}
        require(u32(data,4)==1&&u32(data,8)==36&&u32(data,48)==2&&u32(data,52)==578&&u32(data,634)==0,"NCP 单色记录顺序、长度或附加记录不受支持。");
        require(u16(data,36)==0x064d,"仅支持已核验的 Monochrome 单色基底。");
        String name=name(data);require((data[39]&255)==255,"NCP 单色保留参数尚未核验。");
        int sharpening=(data[40]&255)-128;require(sharpening>=0&&sharpening<=9,"NCP 单色锐化须为 0–9，Auto 尚不支持。");
        require(data[41]==1&&data[42]==1,"NCP 单色需要自定义曲线模式的对比度和亮度。");
        require((data[43]&255)==255&&(data[44]&255)==255,"NCP 单色饱和度与色相须为 N/A。");
        int filter=data[45]&255,tone=data[46]&255,density=data[47]&255;
        require(filter>=0x80&&filter<=0x84,"NCP 单色仅支持无、黄、橙、红、绿滤镜效果。");
        require(tone==0x80||tone==0x81||tone==0x84,"此 NCP 单色调色类型尚未核验。");
        require(tone==0x80?density==255:density>=0x81&&density<=0x87,"NCP 单色调色浓度无效或尚未核验。");
        require(data[56]==0x49&&data[57]==0x30,"NCP 单色曲线标识无效。");
        require((data[62]&255)<=20&&(data[63]&255)<=100,"NCP 单色曲线 Gamma 元数据超出已知范围。");
        require((data[64]&255)>=2&&(data[64]&255)<=20,"NCP 单色曲线控制点数量须为 2–20。");
        for(int i=105;i<120;i++)require(data[i]==0,"NCP 单色曲线包含未核验的保留内容。");
        for(int i=120;i<634;i+=2)require(u16(data,i)<=32767,"NCP 单色曲线采样值超出 0–32767。");
        return new NcpMonochromePreviewProfile(data,name);
    }
    private static String name(byte[] data)throws IOException{
        int end=16;while(end<36&&data[end]!=0){int c=data[end]&255;require(c>=32&&c<=126,"NCP 单色名称须为可打印 ASCII。");end++;}
        require(end>16&&end<36,"NCP 单色名称须在 19 字符内以 NUL 终止。");for(int i=end;i<36;i++)require(data[i]==0,"NCP 单色名称终止后包含未知数据。");String name=new String(data,16,end-16,StandardCharsets.US_ASCII);require(!name.trim().isEmpty(),"NCP 单色名称不能为空。");return name;
    }
    public String registrationName(){return registrationName;}
    public String modelVersion(){return MODEL_VERSION;}
    /** Metadata only, matching the existing legacy NCP preview's omission of camera sharpening. */
    public int sharpening(){return sharpening;}
    /** Raw, audited NCP enum byte: 0x80 Off through 0x84 Green. */
    public int filterEffect(){return filterEffect;}
    /** Raw enum byte: 0x80 B&W, 0x81 Sepia or 0x84 Yellow. */
    public int toning(){return toning;}
    public int toningDensity(){return toningDensity;}
    public double mapTone(double normalized){
        if(!Double.isFinite(normalized)||normalized<0||normalized>1)throw new IllegalArgumentException("Tone input must be finite and within 0..1.");
        double position=normalized*256;int lower=(int)position;if(lower==256)return samples[256]/32767.0;return(samples[lower]+(samples[lower+1]-samples[lower])*(position-lower))/32767.0;
    }
    public int applyArgb(int argb){
        double red=((argb>>>16)&255)/255.0,green=((argb>>>8)&255)/255.0,blue=(argb&255)/255.0;
        double[] weights=FILTER_WEIGHTS[filterEffect-0x80];
        double gray=Math.max(0,Math.min(1,weights[0]*red+weights[1]*green+weights[2]*blue)),powered=Math.pow(gray,1.92);
        double value=mapTone(powered/(powered+.48*(1-gray)));
        double rr=value,gg=value,bb=value;
        if(toning!=0x80){
            double amount=(toningDensity-128)/4.0;
            double[][] coefficients=toning==0x81?SEPIA_AT_FOUR:YELLOW_AT_FOUR;
            rr+=amount*offset(value,coefficients[0]);
            gg+=amount*offset(value,coefficients[1]);
            bb+=amount*offset(value,coefficients[2]);
        }
        return(argb&0xff000000)|(channel(rr)<<16)|(channel(gg)<<8)|channel(bb);
    }
    private static double offset(double value,double[] coefficient){return coefficient[0]+value*(coefficient[1]+value*coefficient[2]);}
    private static int channel(double value){return(int)Math.round(Math.max(0,Math.min(1,value))*255);}
    private static int u16(byte[] data,int offset){return((data[offset]&255)<<8)|(data[offset+1]&255);}
    private static long u32(byte[] data,int offset){return((long)(data[offset]&255)<<24)|((long)(data[offset+1]&255)<<16)|((long)(data[offset+2]&255)<<8)|(data[offset+3]&255);}
    private static void require(boolean condition,String reason)throws IOException{if(!condition)throw unsupported(reason);}
    private static IOException unsupported(String reason){return new IOException("此 NCP 单色预设暂不支持手机预览。"+reason);}
}
