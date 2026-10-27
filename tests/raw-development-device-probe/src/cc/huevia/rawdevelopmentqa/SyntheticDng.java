package cc.huevia.rawdevelopmentqa;

import java.io.*;
import java.nio.*;
import java.nio.file.Files;
import java.util.*;

/** Original generated Bayer fixture, CC0. A real uncompressed DNG with no preview/JPEG IFD. */
public final class SyntheticDng {
    private SyntheticDng(){}
    public static void write(File target,int width,int height,int orientation)throws IOException{
        if(width<24||height<24||width>2048||height>2048||orientation<1||orientation>8)throw new IllegalArgumentException("fixture dimensions");
        List<Tag> tags=new ArrayList<>();
        tags.add(longTag(254,0));tags.add(longTag(256,width));tags.add(longTag(257,height));tags.add(shortTag(258,16));tags.add(shortTag(259,1));tags.add(shortTag(262,32803));
        tags.add(ascii(271,"Huevia QA"));tags.add(ascii(272,"Uncompressed Bayer DNG"));Tag strip=longTag(273,0);tags.add(strip);tags.add(shortTag(274,orientation));tags.add(shortTag(277,1));tags.add(longTag(278,height));tags.add(longTag(279,width*height*2));tags.add(shortTag(284,1));
        tags.add(shortTag(33421,2,2));tags.add(bytes(33422,0,1,1,2));tags.add(bytes(50706,1,4,0,0));tags.add(bytes(50707,1,1,0,0));tags.add(ascii(50708,"Huevia QA Test Bayer"));tags.add(bytes(50710,0,1,2));tags.add(shortTag(50711,1));tags.add(shortTag(50713,1,1));tags.add(rational(50714,false,512,1));tags.add(longTag(50717,4095));
        tags.add(rational(50718,false,1,1,1,1));tags.add(longTag(50719,0,0));tags.add(longTag(50720,width,height));tags.add(rational(50721,true,1,1,0,1,0,1,0,1,1,1,0,1,0,1,0,1,1,1));tags.add(rational(50728,false,1,2,1,1,2,3));tags.add(shortTag(50778,21));tags.add(longTag(50829,0,0,height,width));
        tags.sort(Comparator.comparingInt(t->t.id));int extra=8+2+12*tags.size()+4;for(Tag tag:tags)if(tag.data.length>4){tag.offset=extra;extra=(extra+tag.data.length+3)&~3;}int pixels=extra;strip.data=longTag(273,pixels).data;
        ByteBuffer buffer=ByteBuffer.allocate(pixels+width*height*2).order(ByteOrder.LITTLE_ENDIAN);buffer.put((byte)'I').put((byte)'I').putShort((short)42).putInt(8);buffer.putShort((short)tags.size());
        for(Tag tag:tags){buffer.putShort((short)tag.id).putShort((short)tag.type).putInt(tag.count);if(tag.data.length>4)buffer.putInt(tag.offset);else{buffer.put(tag.data);for(int i=tag.data.length;i<4;i++)buffer.put((byte)0);}}buffer.putInt(0);
        for(Tag tag:tags)if(tag.data.length>4){buffer.position(tag.offset);buffer.put(tag.data);}buffer.position(pixels);
        for(int y=0;y<height;y++)for(int x=0;x<width;x++){
            double checker=((x/7+y/5)&1)==0?1:.52,r=.10+.28*x/(width-1.0),g=.12+.27*y/(height-1.0),b=.11+.29*(1-x/(width-1.0));
            double value=(y&1)==0?((x&1)==0?r:g):((x&1)==0?g:b);if(x>width*3/4&&y>height*3/4)value*=3.2;
            buffer.putShort((short)Math.min(4095,Math.round(512+3583*value*checker)));
        }
        Files.write(target.toPath(),buffer.array());
    }
    private static Tag bytes(int id,int...values){byte[] data=new byte[values.length];for(int i=0;i<values.length;i++)data[i]=(byte)values[i];return new Tag(id,1,values.length,data);}
    private static Tag ascii(int id,String value){byte[] data=(value+'\0').getBytes(java.nio.charset.StandardCharsets.US_ASCII);return new Tag(id,2,data.length,data);}
    private static Tag shortTag(int id,int...values){ByteBuffer data=ByteBuffer.allocate(values.length*2).order(ByteOrder.LITTLE_ENDIAN);for(int value:values)data.putShort((short)value);return new Tag(id,3,values.length,data.array());}
    private static Tag longTag(int id,int...values){ByteBuffer data=ByteBuffer.allocate(values.length*4).order(ByteOrder.LITTLE_ENDIAN);for(int value:values)data.putInt(value);return new Tag(id,4,values.length,data.array());}
    private static Tag rational(int id,boolean signed,int...values){ByteBuffer data=ByteBuffer.allocate(values.length*4).order(ByteOrder.LITTLE_ENDIAN);for(int value:values)data.putInt(value);return new Tag(id,signed?10:5,values.length/2,data.array());}
    private static final class Tag{final int id,type,count;byte[] data;int offset;Tag(int id,int type,int count,byte[] data){this.id=id;this.type=type;this.count=count;this.data=data;}}
}
