package cc.huevia.ncp;

import java.io.File;
import java.io.IOException;
import java.io.InterruptedIOException;
import java.io.RandomAccessFile;
import java.util.Arrays;
import java.util.function.BooleanSupplier;
import java.util.function.DoubleConsumer;

/** Smooth inverse warps, composed once and sampled from immutable private scratch storage. */
public final class PhotoBodyWarp {
    private static final long MAX_BYTES=512L*1024*1024, CACHE_BYTES=16L*1024*1024;
    private PhotoBodyWarp(){}

    /** Writes source coordinates into result. Identity outside the compact horizontal support. */
    public static void source(PhotoBodyShape s,double x,double y,double[] result){
        double destinationX=x,destinationY=y;
        if(s==null||result==null||result.length<2||!Double.isFinite(x)||!Double.isFinite(y))throw new IllegalArgumentException("塑形坐标无效。");
        PhotoBodyShape.Area a=s.length;
        if(a.amount>0&&y>a.top&&y<1){
            double u=(x-(a.left+a.right)*.5)/((a.right-a.left)*.5),weight=bell(u);
            // The photographed upper body is fixed. Space below the feet absorbs the extension.
            double distance=Math.min((a.bottom-a.top)*.14,(1-a.bottom)*.35)*a.amount/100.0;
            double v=y<=a.bottom?smooth((y-a.top)/(a.bottom-a.top)):smooth((1-y)/(1-a.bottom));
            y-=distance*weight*v;
        }
        a=s.legs;
        if(a.amount>0){double cy=(a.top+a.bottom)*.5,vy=bell((y-cy)/((a.bottom-a.top)*.5));
            if(vy>0){double width=a.right-a.left,cx=(a.left+a.right)*.5;
                if(s.singleLeg)x=slim(x,cx,width*.5,a.amount/100.0*.34*vy);
                else {double center=x<cx?a.left+width*.25:a.left+width*.75;x=slim(x,center,width*.25,a.amount/100.0*.34*vy);}
            }
        }
        a=s.body;
        if(a.amount>0){double vy=bell((y-(a.top+a.bottom)*.5)/((a.bottom-a.top)*.5));if(vy>0)x=slim(x,(a.left+a.right)*.5,(a.right-a.left)*.5,a.amount/100.0*.28*vy);}
        if(s.backgroundProtection>0&&s.backgroundMask!=null){double keep=s.backgroundMask.weight(destinationX,destinationY)*s.backgroundProtection/100.0;x=destinationX+(x-destinationX)*(1-keep);y=destinationY+(y-destinationY)*(1-keep);}
        result[0]=x;result[1]=y;
    }
    private static double slim(double x,double center,double radius,double amount){return x+amount*(x-center)*bell((x-center)/radius);}
    private static double bell(double x){if(x<=-1||x>=1)return 0;double v=1-x*x;return v*v;}
    private static double smooth(double t){t=Math.max(0,Math.min(1,t));return t*t*(3-2*t);}

    public static void apply(SpatialPreviewFilter.Pixels pixels,PhotoBodyShape shape,int exif,BooleanSupplier cancel,DoubleConsumer progress)throws IOException{
        if(pixels==null||shape==null||exif<1||exif>8)throw new IllegalArgumentException("塑形照片无效。");
        int w=pixels.width(),h=pixels.height();if(w<1||h<1||w>65535||h>65535)throw new IllegalArgumentException("塑形照片尺寸无效。");
        check(cancel);if(shape.isNeutral()){if(progress!=null)progress.accept(1);return;}
        long bytes=4L*w*h;if(bytes>MAX_BYTES)throw new IOException("照片塑形暂存超出容量限制。");
        File dir=pixels.scratchDirectory();if(dir==null){String tmp=System.getProperty("java.io.tmpdir");if(tmp==null||tmp.isEmpty())throw new IOException("塑形暂存目录不可用。");dir=new File(tmp);}
        if(!dir.isDirectory()&&!dir.mkdirs())throw new IOException("无法创建塑形暂存目录。");
        long free=dir.getUsableSpace();if(free>0&&free<bytes+1024*1024)throw new IOException("存储空间不足，无法完成塑形。");
        File file=File.createTempFile("huevia-body-",".argb",dir);
        try(RandomAccessFile storage=new RandomAccessFile(file,"rw")){
            int[] row=new int[w];byte[] buffer=new byte[w*4];storage.setLength(bytes);
            for(int y=0;y<h;y++){check(cancel);pixels.read(row,y,1);for(int x=0;x<w;x++){int p=row[x],i=x*4;buffer[i]=(byte)(p>>>24);buffer[i+1]=(byte)(p>>>16);buffer[i+2]=(byte)(p>>>8);buffer[i+3]=(byte)p;}storage.write(buffer);if(progress!=null)progress.accept(.15*(y+1.0)/h);}
            Rows original=new Rows(storage,w,h,buffer,cancel);double[] p=new double[2];
            for(int y=0;y<h;y++){
                check(cancel);pixels.read(row,y,1);
                for(int x=0;x<w;x++){
                    if((x&255)==0)check(cancel);double nx=(x+.5)/w,ny=(y+.5)/h;
                    double ox=LocalEditsPreviewProfile.orientedX(nx,ny,exif),oy=LocalEditsPreviewProfile.orientedY(nx,ny,exif);
                    source(shape,ox,oy,p);if(p[0]==ox&&p[1]==oy)continue;
                    inverse(p,exif);double sx=Math.max(0,Math.min(w-1,p[0]*w-.5)),sy=Math.max(0,Math.min(h-1,p[1]*h-.5));
                    int x0=(int)sx,y0=(int)sy,x1=Math.min(w-1,x0+1),y1=Math.min(h-1,y0+1);double fx=sx-x0,fy=sy-y0;
                    int[] a=original.get(y0),b=original.get(y1);row[x]=sample(a[x0],a[x1],b[x0],b[x1],fx,fy);
                }
                check(cancel);pixels.write(row,y,1);if(progress!=null)progress.accept(.15+.85*(y+1.0)/h);
            }
        }finally{if(file.exists()&&!file.delete())throw new IOException("未能清理塑形暂存文件。");}
    }
    private static void inverse(double[] p,int exif){double x=p[0],y=p[1];switch(exif){case 2:p[0]=1-x;break;case 3:p[0]=1-x;p[1]=1-y;break;case 4:p[1]=1-y;break;case 5:p[0]=y;p[1]=x;break;case 6:p[0]=y;p[1]=1-x;break;case 7:p[0]=1-y;p[1]=1-x;break;case 8:p[0]=1-y;p[1]=x;break;default:break;}}
    private static int sample(int a,int b,int c,int d,double x,double y){
        double wa=(1-x)*(1-y),wb=x*(1-y),wc=(1-x)*y,wd=x*y;
        double aa=(a>>>24)*wa,ab=(b>>>24)*wb,ac=(c>>>24)*wc,ad=(d>>>24)*wd,alpha=aa+ab+ac+ad;
        if(alpha<.5)return 0;
        int r=channel((((a>>>16)&255)*aa+((b>>>16)&255)*ab+((c>>>16)&255)*ac+((d>>>16)&255)*ad)/alpha);
        int g=channel((((a>>>8)&255)*aa+((b>>>8)&255)*ab+((c>>>8)&255)*ac+((d>>>8)&255)*ad)/alpha);
        int blue=channel(((a&255)*aa+(b&255)*ab+(c&255)*ac+(d&255)*ad)/alpha);
        return(channel(alpha)<<24)|(r<<16)|(g<<8)|blue;
    }
    private static int channel(double x){return(int)Math.max(0,Math.min(255,Math.round(x)));}
    private static void check(BooleanSupplier cancel)throws InterruptedIOException{if(Thread.currentThread().isInterrupted()||cancel!=null&&cancel.getAsBoolean())throw new InterruptedIOException("塑形已取消。");}
    private static final class Rows {
        final RandomAccessFile file;final int width;final byte[] buffer;final int[][] data;final int[] keys;final BooleanSupplier cancel;
        Rows(RandomAccessFile file,int w,int h,byte[] buffer,BooleanSupplier cancel){this.file=file;width=w;this.buffer=buffer;this.cancel=cancel;int slots=Math.max(2,Math.min(h,(int)(CACHE_BYTES/(4L*w))));data=new int[slots][];keys=new int[slots];Arrays.fill(keys,-1);}
        int[] get(int y)throws IOException{int index=y%data.length;if(keys[index]!=y){check(cancel);if(data[index]==null)data[index]=new int[width];file.seek(4L*y*width);file.readFully(buffer);for(int x=0;x<width;x++){int i=x*4;data[index][x]=((buffer[i]&255)<<24)|((buffer[i+1]&255)<<16)|((buffer[i+2]&255)<<8)|(buffer[i+3]&255);}keys[index]=y;}return data[index];}
    }
}
