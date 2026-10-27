package cc.huevia.ncp;

import java.io.IOException;
import java.io.InterruptedIOException;
import java.util.function.BooleanSupplier;
import java.util.function.DoubleConsumer;

/** Shared encoded-sRGB detail effects. Row rings are bounded independently of photo height. */
public final class PhotoDetailEffects {
    private static final long MAX_WORKING_BYTES=64L*1024*1024;
    private PhotoDetailEffects(){}

    /** Bilateral luminance/chroma filtering with the original pixels as the edge guide.
     * The guide is never fed back from a filtered row. Alpha weights neighbours and is preserved.
     * Five sampled positions per axis keep work per pixel bounded at full camera resolution.
     * Integer weighted sums are independent of traversal direction, including EXIF reflections. */
    public static void denoise(SpatialPreviewFilter.Pixels pixels,int luminance,int chroma,
            BooleanSupplier cancel,DoubleConsumer progress)throws IOException{
        amount(luminance);amount(chroma);check(cancel);
        int width=pixels.width(),height=pixels.height();dimensions(width,height);
        if(luminance==0&&chroma==0){if(progress!=null)progress.accept(1);return;}
        int radius=Math.max(1,Math.min(12,(int)Math.round(2*Math.max(width,height)/1600.0)));
        int slots=Math.min(height,2*radius+1);
        if((4L*slots+4)*width+32768>MAX_WORKING_BYTES)throw new IOException("照片降噪行缓冲超出内存限制。");
        new Denoise(pixels,luminance,chroma,cancel,progress,width,height,radius,slots).run();
    }

    /** Grain is a deterministic field in the EXIF-oriented source, before crop/border/export resize. */
    public static void finish(SpatialPreviewFilter.Pixels pixels,int grain,int vignette,
            BooleanSupplier cancel,DoubleConsumer progress)throws IOException{
        amount(grain);amount(vignette);check(cancel);int width=pixels.width(),height=pixels.height();dimensions(width,height);
        if(grain==0&&vignette==0){if(progress!=null)progress.accept(1);return;}
        int exif=pixels.exifOrientation();if(exif<1||exif>8)throw new IOException("照片方向无效。");
        int ow=exif>=5?height:width,oh=exif>=5?width:height;
        double gridX=1600.0*ow/Math.max(ow,oh),gridY=1600.0*oh/Math.max(ow,oh);
        double[] shade=new double[2049];for(int i=0;i<shade.length;i++){double t=Math.max(0,Math.min(1,(i/2048.0-.12)/.88));shade[i]=Math.pow(2,-1.6*vignette/100.0*t*t*(3-2*t));}
        int[] row=new int[width];
        for(int y=0;y<height;y++){
            check(cancel);pixels.read(row,y,1);
            for(int x=0;x<width;x++){
                if((x&255)==0)check(cancel);int input=row[x];if((input>>>24)==0)continue;
                int ox=x,oy=y;
                switch(exif){case 2:ox=width-1-x;break;case 3:ox=width-1-x;oy=height-1-y;break;case 4:oy=height-1-y;break;case 5:ox=y;oy=x;break;case 6:ox=height-1-y;oy=x;break;case 7:ox=height-1-y;oy=width-1-x;break;case 8:ox=y;oy=width-1-x;break;}
                double ou=(ox+.5)/ow,ov=(oy+.5)/oh;
                double dx=2*ou-1,dy=2*ov-1,gain=shade[Math.min(2048,(int)Math.round((dx*dx+dy*dy)*1024))];
                double r=((input>>>16)&255)*gain,g=((input>>>8)&255)*gain,b=(input&255)*gain;
                if(grain!=0){double l=(.2126*r+.7152*g+.0722*b)/255,mid=4*l*(1-l);double n=noise(ou*gridX,ov*gridY)*grain/100.0*26*(.35+.65*mid);r+=n;g+=n;b+=n;}
                row[x]=(input&0xff000000)|(channel(r)<<16)|(channel(g)<<8)|channel(b);
            }
            check(cancel);pixels.write(row,y,1);if(progress!=null)progress.accept((y+1.0)/height);
        }
    }

    private static double noise(double x,double y){int ix=(int)Math.floor(x),iy=(int)Math.floor(y);double fx=x-ix,fy=y-iy;fx=fx*fx*(3-2*fx);fy=fy*fy*(3-2*fy);double a=hash(ix,iy),b=hash(ix+1,iy),c=hash(ix,iy+1),d=hash(ix+1,iy+1);return (a+(b-a)*fx)*(1-fy)+(c+(d-c)*fx)*fy;}
    private static double hash(int x,int y){int v=x*0x1f123bb5^y*0x5f356495^0x6d2b79f5;v^=v>>>16;v*=0x7feb352d;v^=v>>>15;v*=0x846ca68b;v^=v>>>16;return (v&0xffff)/32767.5-1;}
    private static void dimensions(int width,int height){if(width<1||height<1||width>65535||height>65535)throw new IllegalArgumentException("照片尺寸无效。");}
    private static void amount(int value){if(value<0||value>100)throw new IllegalArgumentException("细节参数超出范围。");}
    private static void check(BooleanSupplier cancel)throws InterruptedIOException{if(Thread.currentThread().isInterrupted()||cancel!=null&&cancel.getAsBoolean())throw new InterruptedIOException("图片细节处理已取消。");}
    private static int channel(double value){return (int)Math.max(0,Math.min(255,Math.round(value)));}
    private static int y(int p){return 54*((p>>>16)&255)+183*((p>>>8)&255)+19*(p&255);}
    private static int cr(int p,int y){return (((p>>>16)&255)<<8)-y;}
    private static int cb(int p,int y){return ((p&255)<<8)-y;}
    private static int range(int[] table,int difference){return table[Math.min(table.length-1,(Math.abs(difference)+128)>>8)];}
    private static int[] table(double sigma,int length){int[] out=new int[length];for(int i=0;i<length;i++)out[i]=(int)Math.round(4096*Math.exp(-.5*i*i/(sigma*sigma)));return out;}

    private static final class Denoise {
        final SpatialPreviewFilter.Pixels pixels;final int width,height,radius,slots;final BooleanSupplier cancel;final DoubleConsumer progress;
        final double lumaAmount,chromaAmount;final int[] offsets,lumaRange,chromaRange,chromaGuide,lumaGuide;final int[][] spatial;
        final int[][] original;final int[] output;
        int loaded=-1;
        Denoise(SpatialPreviewFilter.Pixels pixels,int luminance,int chroma,BooleanSupplier cancel,DoubleConsumer progress,int width,int height,int radius,int slots){
            this.pixels=pixels;this.width=width;this.height=height;this.radius=radius;this.slots=slots;this.cancel=cancel;this.progress=progress;
            lumaAmount=luminance/100.0*.92;chromaAmount=chroma/100.0;
            offsets=radius==1?new int[]{-1,0,1}:new int[]{-radius,-Math.max(1,(int)Math.round(radius/2.0)),0,Math.max(1,(int)Math.round(radius/2.0)),radius};
            spatial=new int[offsets.length][offsets.length];for(int i=0;i<offsets.length;i++)for(int j=0;j<offsets.length;j++)spatial[i][j]=(int)Math.round(4096*Math.exp(-1.25*(offsets[i]*offsets[i]+offsets[j]*offsets[j])/(double)(radius*radius)));
            lumaRange=table(3+luminance*.22,256);chromaRange=table(8+chroma*.45,512);chromaGuide=table(45,512);lumaGuide=table(18+chroma*.15,256);
            original=new int[slots][width];output=new int[width];
        }
        void run()throws IOException{
            if(progress!=null)progress.accept(0);
            for(int row=0;row<height;row++){
                loadThrough(Math.min(height-1,row+radius));check(cancel);int[] centre=original[row%slots];
                for(int x=0;x<width;x++){
                    if((x&127)==0)check(cancel);int p=centre[x];if((p>>>24)==0){output[x]=p;continue;}
                    int py=y(p),pcb=cb(p,py),pcr=cr(p,py);long sumY=0,sumCb=0,sumCr=0,wy=0,wc=0;
                    for(int i=0;i<offsets.length;i++){
                        int[] neighbours=original[clamp(row+offsets[i],height)%slots];
                        for(int j=0;j<offsets.length;j++){
                            int q=neighbours[clamp(x+offsets[j],width)],alpha=q>>>24;if(alpha==0)continue;
                            int qy=y(q),qcb=cb(q,qy),qcr=cr(q,qy),cd=Math.max(Math.abs(qcb-pcb),Math.abs(qcr-pcr)),s=spatial[i][j];
                            if(lumaAmount!=0){long w=weight(s,range(lumaRange,qy-py),range(chromaGuide,cd))*alpha;sumY+=w*qy;wy+=w;}
                            if(chromaAmount!=0){long w=weight(s,range(lumaGuide,qy-py),range(chromaRange,cd))*alpha;sumCb+=w*qcb;sumCr+=w*qcr;wc+=w;}
                        }
                    }
                    double nextY=(wy==0?py:py+lumaAmount*(sumY/(double)wy-py))/256,nextCb=(wc==0?pcb:pcb+chromaAmount*(sumCb/(double)wc-pcb))/256,nextCr=(wc==0?pcr:pcr+chromaAmount*(sumCr/(double)wc-pcr))/256;
                    output[x]=(p&0xff000000)|(channel(nextY+nextCr)<<16)|(channel(nextY-(54*nextCr+19*nextCb)/183)<<8)|channel(nextY+nextCb);
                }
                check(cancel);pixels.write(output,row,1);if(progress!=null)progress.accept((row+1.0)/height);
            }
        }
        void loadThrough(int target)throws IOException{
            while(loaded<target){check(cancel);int row=++loaded;pixels.read(original[row%slots],row,1);}
        }
        static int weight(int spatial,int luma,int colour){return (((spatial*luma+2048)>>12)*colour+2048)>>12;}
        static int clamp(int v,int size){return Math.max(0,Math.min(size-1,v));}
    }
}
