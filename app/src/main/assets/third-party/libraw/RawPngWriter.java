package cc.huevia.album;

import android.graphics.Bitmap;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.function.BooleanSupplier;
import java.util.function.DoubleConsumer;
import java.util.zip.CRC32;
import java.util.zip.Deflater;

/** Bounded, lossless RGB/sRGB PNG for opaque RAW workspaces. Compression effort never changes pixels. */
public final class RawPngWriter {
    private RawPngWriter() { }
    public static void write(Bitmap bitmap,OutputStream output,BooleanSupplier cancel,DoubleConsumer progress)throws IOException{
        if(bitmap==null||bitmap.isRecycled()||bitmap.getWidth()<1||bitmap.getHeight()<1)throw new IOException("显影图像不可用。");
        check(cancel);int width=bitmap.getWidth(),height=bitmap.getHeight();
        if((long)width*height>60_000_000)throw new IOException("显影图像尺寸超出限制。");
        DataOutputStream out=new DataOutputStream(output);out.writeLong(0x89504e470d0a1a0aL);
        ByteArrayOutputStream header=new ByteArrayOutputStream(13);DataOutputStream fields=new DataOutputStream(header);
        fields.writeInt(width);fields.writeInt(height);fields.writeByte(8);fields.writeByte(2);fields.writeByte(0);fields.writeByte(0);fields.writeByte(0);
        chunk(out,"IHDR",header.toByteArray(),13);chunk(out,"sRGB",new byte[]{0},1);
        int rowsPerBlock=32,stride=width*3+1;
        int[] pixels=new int[width*rowsPerBlock];byte[] filtered=new byte[stride*rowsPerBlock],compressed=new byte[64*1024];
        Deflater encoder=new Deflater(Deflater.BEST_SPEED);
        try{
            for(int y=0;y<height;y+=rowsPerBlock){
                check(cancel);int rows=Math.min(rowsPerBlock,height-y);bitmap.getPixels(pixels,0,width,0,y,width,rows);
                int offset=0;
                for(int row=0;row<rows;row++){
                    filtered[offset++]=1;int previousR=0,previousG=0,previousB=0;
                    for(int x=0;x<width;x++){
                        int pixel=pixels[row*width+x];if((pixel>>>24)!=255)throw new IOException("显影图像透明度异常，未保存。");
                        int r=(pixel>>>16)&255,g=(pixel>>>8)&255,b=pixel&255;
                        filtered[offset++]=(byte)(r-previousR);filtered[offset++]=(byte)(g-previousG);filtered[offset++]=(byte)(b-previousB);
                        previousR=r;previousG=g;previousB=b;
                    }
                }
                encoder.setInput(filtered,0,offset);
                while(!encoder.needsInput()){check(cancel);int n=encoder.deflate(compressed);if(n>0)chunk(out,"IDAT",compressed,n);}
                if(progress!=null)progress.accept(.98*(y+rows)/(double)height);
            }
            encoder.finish();while(!encoder.finished()){check(cancel);int n=encoder.deflate(compressed);if(n==0)throw new IOException("显影 PNG 编码未完成。");chunk(out,"IDAT",compressed,n);}
            check(cancel);chunk(out,"IEND",new byte[0],0);out.flush();if(progress!=null)progress.accept(1);
        }finally{encoder.end();}
    }
    private static void chunk(DataOutputStream out,String name,byte[] data,int length)throws IOException{
        byte[] type=name.getBytes(StandardCharsets.US_ASCII);CRC32 crc=new CRC32();crc.update(type);crc.update(data,0,length);
        out.writeInt(length);out.write(type);out.write(data,0,length);out.writeInt((int)crc.getValue());
    }
    private static void check(BooleanSupplier cancel)throws IOException{if(Thread.currentThread().isInterrupted()||cancel!=null&&cancel.getAsBoolean())throw new InterruptedIOException("RAW 保存已取消。");}
}
