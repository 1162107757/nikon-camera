package cc.huevia.ncp;

import java.io.IOException;
import java.io.InterruptedIOException;
import java.util.function.BooleanSupplier;
import java.util.function.DoubleConsumer;

/** Whole exposed-skin retouch. A bounded original-row window never reuses filtered pixels. */
public final class SkinSmoothingFilter {
    private static final long MAX_BYTES=64L*1024*1024;
    private SkinSmoothingFilter() { }
    public static void apply(SpatialPreviewFilter.Pixels pixels,PhotoPortrait.BodySkinMask mask,int strength,
            int exif,BooleanSupplier cancel,DoubleConsumer progress)throws IOException {
        apply(pixels,mask,strength,70,exif,cancel,progress);
    }
    public static void apply(SpatialPreviewFilter.Pixels pixels,PhotoPortrait.BodySkinMask mask,int strength,int texture,
            int exif,BooleanSupplier cancel,DoubleConsumer progress)throws IOException {
        if(texture<0||texture>100)throw new IllegalArgumentException("纹理保留参数无效。");
        if(pixels==null||strength<0||strength>100||exif<1||exif>8)throw new IllegalArgumentException("磨皮参数无效。");
        check(cancel);report(progress,0);
        if(strength==0||mask==null){report(progress,1);return;}
        boolean covered=false;for(byte value:mask.copyCoverage())if((value&255)>0){covered=true;break;}
        if(!covered){report(progress,1);return;}
        int width=pixels.width(),height=pixels.height();
        if(width<1||height<1||width>65535||height>65535)throw new IOException("磨皮照片尺寸无效。");
        int radius=Math.max(1,Math.min(8,(int)Math.round(Math.min(width,height)*.0015)));
        int slots=Math.min(height,2*radius+1);
        if((8L*slots+4)*width>MAX_BYTES)throw new IOException("磨皮行缓存超出内存上限。");
        int[][] rows=new int[slots][width];float[][] coverage=new float[slots][width];int[] out=new int[width];
        int half=Math.max(1,radius/2);int[] offsets=radius==1?new int[]{-1,0,1}:new int[]{-radius,-half,0,half,radius};
        double[][] spatial=new double[offsets.length][offsets.length];
        for(int i=0;i<offsets.length;i++)for(int j=0;j<offsets.length;j++)spatial[i][j]=1/(1+(offsets[i]*offsets[i]+offsets[j]*offsets[j])/(double)(radius*radius+1));
        int loaded=-1;double amount=strength/100.0;
        for(int y=0;y<height;y++) {
            check(cancel);
            while(loaded<Math.min(height-1,y+radius)) {
                check(cancel);int yy=++loaded;int[] row=rows[yy%slots];float[] weights=coverage[yy%slots];pixels.read(row,yy,1);
                for(int x=0;x<width;x++){if((x&255)==0)check(cancel);double nx=LocalEditsPreviewProfile.orientedX((x+.5)/width,(yy+.5)/height,exif),ny=LocalEditsPreviewProfile.orientedY((x+.5)/width,(yy+.5)/height,exif);weights[x]=(float)mask.weight(nx,ny);}
            }
            int[] original=rows[y%slots];System.arraycopy(original,0,out,0,width);
            for(int x=0;x<width;x++) {
                if((x&127)==0)check(cancel);int value=original[x];double cover=coverage[y%slots][x];
                if(cover<=0||(value>>>24)==0)continue;
                double r=(value>>>16)&255,g=(value>>>8)&255,b=value&255,rr=0,gg=0,bb=0,total=0,lum=0,squared=0;
                for(int i=0;i<offsets.length;i++) {
                    int yy=Math.max(0,Math.min(height-1,y+offsets[i]));int[] row=rows[yy%slots];float[] weights=coverage[yy%slots];
                    for(int j=0;j<offsets.length;j++) {
                        int xx=Math.max(0,Math.min(width-1,x+offsets[j]));if(xx==x&&yy==y)continue;
                        int q=row[xx];double alpha=(q>>>24)/255.0;if(alpha==0||weights[xx]<=0)continue;
                        double qr=(q>>>16)&255,qg=(q>>>8)&255,qb=q&255,dr=qr-r,dg=qg-g,db=qb-b;
                        double weight=spatial[i][j]*alpha*weights[xx]/(1+(dr*dr+dg*dg+db*db)/(3*32.0*32));
                        double l=.2126*qr+.7152*qg+.0722*qb;rr+=qr*weight;gg+=qg*weight;bb+=qb*weight;lum+=l*weight;squared+=l*l*weight;total+=weight;
                    }
                }
                if(total<=1e-8)continue;
                double mean=lum/total,variance=Math.max(0,squared/total-mean*mean),residual=Math.abs((.2126*r+.7152*g+.0722*b)-mean);
                // Retain most fine texture. Stronger corrections target small tonal blemishes;
                // high-contrast structures and broad mixed edges stay conservative.
                double detail=.24+.66*smooth(3,16,residual),edge=1/(1+Math.pow(variance/(22.0*22),2));
                double blend=amount*cover*detail*edge*(1-.85*smooth(38,75,residual));
                if(texture!=70)blend=Math.min(.95,blend*(1.7-texture/100.0));
                if(blend<=0)continue;
                out[x]=(value&0xff000000)|(channel(r+(rr/total-r)*blend)<<16)|(channel(g+(gg/total-g)*blend)<<8)|channel(b+(bb/total-b)*blend);
            }
            check(cancel);pixels.write(out,y,1);report(progress,(y+1.0)/height);
        }
    }
    private static double smooth(double low,double high,double value){double x=Math.max(0,Math.min(1,(value-low)/(high-low)));return x*x*(3-2*x);}
    private static int channel(double v){return(int)Math.max(0,Math.min(255,Math.round(v)));}
    private static void report(DoubleConsumer p,double v){if(p!=null)p.accept(v);}
    private static void check(BooleanSupplier cancel)throws InterruptedIOException{if(Thread.currentThread().isInterrupted()||cancel!=null&&cancel.getAsBoolean())throw new InterruptedIOException("磨皮处理已取消。");}
}
