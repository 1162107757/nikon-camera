package cc.huevia.ncp;

import java.io.File;
import java.io.IOException;
import java.io.InterruptedIOException;
import java.io.RandomAccessFile;
import java.util.List;
import java.util.function.BooleanSupplier;
import java.util.function.DoubleConsumer;

/** Complete one adjustment branch, then blend it once through its independent brush.
 * The caller owns the destination and must discard incomplete output after cancellation or IO failure.
 * Only a private, disposable file holds the full-resolution candidate; extra heap storage is row bounded.
 */
public final class AdjustmentRegionRenderer {
    public static final long MAX_SCRATCH_BYTES=512L*1024*1024;
    private AdjustmentRegionRenderer(){}

    public static void apply(SpatialPreviewFilter.Pixels pixels,List<AdjustmentRegion> regions,int exif,
            BooleanSupplier cancel,DoubleConsumer progress)throws IOException{
        if(pixels==null||regions==null||exif<1||exif>8)throw new IllegalArgumentException("局部调节照片无效。");
        int width=pixels.width(),height=pixels.height();if(width<1||height<1||width>65535||height>65535)throw new IllegalArgumentException("局部调节照片尺寸无效。");
        int total=0;for(AdjustmentRegion r:regions)if(r.hasEffect())total++;int done=0;
        for(AdjustmentRegion region:regions){check(cancel);if(!region.hasEffect())continue;final int step=done++;final int count=total;render(pixels,region,exif,cancel,progress==null?null:v->progress.accept((step+v)/count));}
        check(cancel);if(progress!=null)progress.accept(1);
    }
    private static void render(SpatialPreviewFilter.Pixels pixels,AdjustmentRegion region,int exif,
            BooleanSupplier cancel,DoubleConsumer progress)throws IOException{
        int width=pixels.width(),height=pixels.height(),ow=exif>=5?height:width,oh=exif>=5?width:height;
        AdjustmentRegion.Brush brush=region.compileBrush(ow,oh);
        PresetPreviewProfile effect=AdjustedPreviewProfile.of(null,region.adjustments);
        boolean skin=!region.skinSettings.isNeutral()&&region.effectiveSkinMask()!=null;
        boolean spatial=needsSpatial(region.adjustments)||region.adjustments.cleanup.hasNoiseEffect()||!region.portrait.isNeutral()||skin;
        if(!spatial){
            int[] row=new int[width];
            for(int y=0;y<height;y++){check(cancel);pixels.read(row,y,1);for(int x=0;x<width;x++){if((x&255)==0)check(cancel);int original=row[x];if((original>>>24)==0)continue;double w=weight(brush,x,y,width,height,exif)*region.amount;if(w>0)row[x]=blend(original,effect.applyArgb(original),w);}pixels.write(row,y,1);if(progress!=null)progress.accept((y+1.0)/height);}return;
        }
        // An erased/empty selection must not allocate a full-resolution temporary branch.
        boolean covered=false;
        for(int y=0;y<height&&!covered;y++){check(cancel);for(int x=0;x<width;x++){if((x&255)==0)check(cancel);if(weight(brush,x,y,width,height,exif)>0){covered=true;break;}}}
        if(!covered){if(progress!=null)progress.accept(1);return;}
        try(Scratch branch=Scratch.copyOf(pixels,exif,cancel,progress==null?null:v->progress.accept(v*.12))){
            effect.renderPixels(branch,cancel,progress==null?null:v->progress.accept(.12+.38*v));
            if(skin)skin(branch,region.skinSettings,region.effectiveSkinMask(),exif,cancel);
            if(!region.portrait.isNeutral())PortraitPreviewFilter.apply(branch,region.portrait,exif,cancel,progress==null?null:v->progress.accept(.5+.3*v));
            int[] original=new int[width],candidate=new int[width];
            for(int y=0;y<height;y++){check(cancel);pixels.read(original,y,1);branch.read(candidate,y,1);for(int x=0;x<width;x++){if((x&255)==0)check(cancel);if((original[x]>>>24)==0)continue;double w=weight(brush,x,y,width,height,exif)*region.amount;if(w>0)original[x]=blend(original[x],candidate[x],w);}pixels.write(original,y,1);if(progress!=null)progress.accept(.8+.2*(y+1.0)/height);}
        }
    }
    private static boolean needsSpatial(PhotoAdjustments s){for(PhotoAdjustments.Parameter p:new PhotoAdjustments.Parameter[]{PhotoAdjustments.Parameter.CLARITY,PhotoAdjustments.Parameter.SHARPENING,PhotoAdjustments.Parameter.LUMA_DENOISE,PhotoAdjustments.Parameter.COLOR_DENOISE,PhotoAdjustments.Parameter.GRAIN,PhotoAdjustments.Parameter.VIGNETTE})if(s.get(p)!=0)return true;return false;}
    private static double weight(AdjustmentRegion.Brush brush,int x,int y,int width,int height,int exif){double nx=(x+.5)/width,ny=(y+.5)/height;return brush.weight(LocalEditsPreviewProfile.orientedX(nx,ny,exif),LocalEditsPreviewProfile.orientedY(nx,ny,exif));}
    private static int blend(int original,int changed,double w){if(w<=0||original==changed)return original;if(w>=1)return(original&0xff000000)|(changed&0x00ffffff);return(original&0xff000000)|(channel(((original>>>16)&255)+(((changed>>>16)&255)-((original>>>16)&255))*w)<<16)|(channel(((original>>>8)&255)+(((changed>>>8)&255)-((original>>>8)&255))*w)<<8)|channel((original&255)+((changed&255)-(original&255))*w);}
    private static int channel(double value){return(int)Math.max(0,Math.min(255,Math.round(value)));}
    private static void check(BooleanSupplier cancel)throws InterruptedIOException{if(Thread.currentThread().isInterrupted()||cancel!=null&&cancel.getAsBoolean())throw new InterruptedIOException("局部调节处理已取消。");}

    /** Whole exposed-skin texture, independent of face detection and of ordinary adjustment scope. */
    private static void skin(SpatialPreviewFilter.Pixels pixels,PhotoPortrait.Settings settings,
            PhotoPortrait.BodySkinMask mask,int exif,BooleanSupplier cancel)throws IOException{
        int width=pixels.width(),height=pixels.height(),radius=settings.smoothing==0?0:Math.max(1,Math.min(10,(int)Math.round(Math.min(width,height)*.003)));
        int slots=Math.min(height,2*radius+1);int[][] ring=new int[slots][width];int[] output=new int[width];int loaded=-1;
        int[] offsets=radius==0?new int[]{0}:radius==1?new int[]{-1,0,1}:new int[]{-radius,-Math.max(1,radius/2),0,Math.max(1,radius/2),radius};
        double smoothing=settings.smoothing/100.0*.85*(1-.80*settings.texture/100.0),lift=settings.brightness/100.0*.22,sigma=18+settings.smoothing*.20,denominator=3*sigma*sigma;
        for(int y=0;y<height;y++){
            check(cancel);while(loaded<Math.min(height-1,y+radius)){loaded++;pixels.read(ring[loaded%slots],loaded,1);}int[] row=ring[y%slots];System.arraycopy(row,0,output,0,width);
            for(int x=0;x<width;x++){
                if((x&255)==0)check(cancel);int original=row[x];if((original>>>24)==0)continue;double nx=LocalEditsPreviewProfile.orientedX((x+.5)/width,(y+.5)/height,exif),ny=LocalEditsPreviewProfile.orientedY((x+.5)/width,(y+.5)/height,exif),amount=mask.weight(nx,ny);if(amount<=0)continue;
                double r=(original>>>16)&255,g=(original>>>8)&255,b=original&255;
                if(smoothing>0){double rr=0,gg=0,bb=0,weights=0;for(int dy:offsets){int yy=Math.max(0,Math.min(height-1,y+dy));int[] neighbors=ring[yy%slots];for(int dx:offsets){int q=neighbors[Math.max(0,Math.min(width-1,x+dx))];double alpha=(q>>>24)/255.0;if(alpha==0)continue;double qr=(q>>>16)&255,qg=(q>>>8)&255,qb=q&255,dr=qr-r,dg=qg-g,db=qb-b;double w=alpha/(1+(dx*dx+dy*dy)/(double)(radius*radius+1))/(1+(dr*dr+dg*dg+db*db)/denominator);rr+=qr*w;gg+=qg*w;bb+=qb*w;weights+=w;}}if(weights>0){r+=(rr/weights-r)*smoothing;g+=(gg/weights-g)*smoothing;b+=(bb/weights-b)*smoothing;}}
                r=lift(r/255,lift)+settings.warmth/100.0*.055+settings.redness/100.0*.055;g=lift(g/255,lift)+settings.warmth/100.0*.008-settings.redness/100.0*.018;b=lift(b/255,lift)-settings.warmth/100.0*.065-settings.redness/100.0*.006;
                int changed=(original&0xff000000)|(channel(r*255)<<16)|(channel(g*255)<<8)|channel(b*255);output[x]=blend(original,changed,amount);
            }
            check(cancel);pixels.write(output,y,1);
        }
    }
    private static double lift(double value,double amount){return amount>=0?value+amount*(1-value):value*(1+amount);}

    /** A disposable branch: candidate processing cannot feed partially blended pixels into itself. */
    static final class Scratch implements SpatialPreviewFilter.Pixels,AutoCloseable {
        final File file,directory;
        final RandomAccessFile storage;
        final int width,height,exif;
        final byte[] buffer;
        private Scratch(File file,File directory,RandomAccessFile storage,int width,int height,int exif){this.file=file;this.directory=directory;this.storage=storage;this.width=width;this.height=height;this.exif=exif;buffer=new byte[width*4];}
        static Scratch copyOf(SpatialPreviewFilter.Pixels source,int exif,BooleanSupplier cancel,DoubleConsumer progress)throws IOException{
            int width=source.width(),height=source.height();long bytes=4L*width*height;if(bytes>MAX_SCRATCH_BYTES)throw new IOException("照片局部调节暂存超出容量限制。");
            File directory=source.scratchDirectory();if(directory==null){String path=System.getProperty("java.io.tmpdir");if(path==null||path.isEmpty())throw new IOException("局部调节暂存目录不可用。");directory=new File(path);}
            if(!directory.isDirectory()&&!directory.mkdirs())throw new IOException("无法创建局部调节暂存目录。");long free=directory.getUsableSpace();if(free>0&&free<bytes+1024*1024)throw new IOException("存储空间不足，无法完成局部调节。");
            check(cancel);File file=File.createTempFile("huevia-region-",".argb",directory);RandomAccessFile storage=null;Scratch scratch=null;
            try{storage=new RandomAccessFile(file,"rw");storage.setLength(bytes);scratch=new Scratch(file,directory,storage,width,height,exif);int[] row=new int[width];for(int y=0;y<height;y++){check(cancel);source.read(row,y,1);scratch.write(row,y,1);if(progress!=null)progress.accept((y+1.0)/height);}return scratch;}
            catch(IOException|RuntimeException|Error failure){try{if(storage!=null)storage.close();}catch(IOException close){failure.addSuppressed(close);}if(file.exists()&&!file.delete())failure.addSuppressed(new IOException("未能清理局部调节暂存文件。"));throw failure;}
        }
        public int width(){return width;}public int height(){return height;}public int exifOrientation(){return exif;}public File scratchDirectory(){return directory;}
        public void read(int[] dest,int row,int rows)throws IOException{range(dest,row,rows);storage.seek(4L*row*width);for(int y=0;y<rows;y++){storage.readFully(buffer);for(int x=0;x<width;x++){int i=x*4;dest[y*width+x]=((buffer[i]&255)<<24)|((buffer[i+1]&255)<<16)|((buffer[i+2]&255)<<8)|(buffer[i+3]&255);}}}
        public void write(int[] source,int row,int rows)throws IOException{range(source,row,rows);storage.seek(4L*row*width);for(int y=0;y<rows;y++){for(int x=0;x<width;x++){int value=source[y*width+x],i=x*4;buffer[i]=(byte)(value>>>24);buffer[i+1]=(byte)(value>>>16);buffer[i+2]=(byte)(value>>>8);buffer[i+3]=(byte)value;}storage.write(buffer);}}
        private void range(int[] data,int row,int rows)throws IOException{if(data==null||row<0||rows<0||row>height-rows||(long)width*rows>data.length)throw new IOException("局部调节像素行范围无效。");}
        public void close()throws IOException{IOException failure=null;try{storage.close();}catch(IOException close){failure=close;}if(file.exists()&&!file.delete()){IOException delete=new IOException("未能清理局部调节暂存文件。");if(failure==null)failure=delete;else failure.addSuppressed(delete);}if(failure!=null)throw failure;}
    }
}
