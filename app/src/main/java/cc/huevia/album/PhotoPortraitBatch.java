package cc.huevia.album;
import android.content.Context;
import android.graphics.*;
import android.media.ExifInterface;
import cc.huevia.ncp.*;
import java.io.*;
import java.util.*;
import java.util.function.*;

/** Coordinate-free portrait synchronization; each target owns fresh inference and a guarded draft. */
public final class PhotoPortraitBatch {
    private PhotoPortraitBatch(){}
    private static final class Change {final String sha;final PhotoEditStore.Draft before,after;Change(String s,PhotoEditStore.Draft b,PhotoEditStore.Draft a){sha=s;before=b;after=a;}}
    public static final class Receipt {
        private final List<Change> changes;Receipt(List<Change> c){changes=new ArrayList<>(c);}
        public int changed(){return changes.size();}
        public synchronized int undo(PhotoEditStore store,BooleanSupplier allowed)throws IOException{int restored=0;for(Change c:changes){check(allowed);if(store.replace(c.sha,c.after,c.before))restored++;}return restored;}
    }
    public static Receipt apply(Context context,PhotoPresetBatch batch,List<DownloadedPhoto> photos,String owner,boolean natural,BooleanSupplier allowed,BiConsumer<Integer,Integer> progress)throws IOException{
        if(photos==null||photos.isEmpty()||photos.size()>100)throw new IOException("每次请选择 1–100 张照片。");PhotoEditStore store=new PhotoEditStore(context.getFilesDir(),owner);PhotoPortrait source=null;ArrayList<Change> plans=new ArrayList<>(),written=new ArrayList<>();HashSet<String> seen=new HashSet<>();
        for(int i=0;i<photos.size();i++){
            check(allowed);if(progress!=null)progress.accept(i+1,photos.size());DownloadedPhoto selected=photos.get(i),original=batch.processingOriginalFor(selected);String sha=PhotoEditStore.hashFile(original.file());PhotoEditStore.Draft before=store.read(sha);
            boolean restore=before!=null&&(!before.exported||PhotoPresetBatch.matchesSavedDraft(selected,before));if(PhotoPresetBatch.isSavedEffect(selected)&&!restore)throw new IOException(selected.filename()+" 的修图草稿与所选版本不符，请选择可恢复的原图或版本。");
            PhotoEditStore.Draft visible=restore?before:new PhotoEditStore.Draft(sha,null,"无滤镜",0,false);if(!natural&&source==null){source=visible.localEdits.portrait;if(source.isEmpty())throw new IOException("第一张照片还没有人像设置，请先精修第一张，或选择批量自然精修。");}
            if(!seen.add(sha))continue;Bitmap analysis=decode(original.file());PhotoPersonAnalysis.Result found;try{found=PhotoPersonAnalysis.analyze(context,analysis,()->!allowed.getAsBoolean()||Thread.currentThread().isInterrupted());}finally{analysis.recycle();}
            PhotoPortrait next=merge(visible.localEdits.portrait,source,found,natural);if(!sha.equals(PhotoEditStore.hashFile(original.file())))throw new IOException("照片在分析期间发生变化，请重新选择。");
            PhotoEditStore.Draft after=new PhotoEditStore.Draft(sha,visible.presetBytes(),visible.name,visible.strength,visible.adjustments,visible.geometry,visible.border,visible.localEdits.withPortrait(next),false);plans.add(new Change(sha,before,after));
        }
        try{for(Change c:plans){check(allowed);if(!store.replace(c.sha,c.before,c.after))throw new IOException("目标照片有新编辑，本次同步已停止。");written.add(c);}check(allowed);return new Receipt(written);}
        catch(IOException failure){int conflicts=0;for(int i=written.size()-1;i>=0;i--){Change c=written.get(i);try{if(!store.replace(c.sha,c.after,c.before))conflicts++;}catch(IOException e){failure.addSuppressed(e);conflicts++;}}if(conflicts>0)throw new IOException("同步中止，部分照片已有独立新编辑，请逐张核对。",failure);throw failure;}
    }
    public static PhotoPortrait merge(PhotoPortrait target,PhotoPortrait source,PhotoPersonAnalysis.Result found,boolean natural){
        ArrayList<PhotoPortrait.Face> faces=new ArrayList<>();boolean[] used=new boolean[target.faces().size()];PhotoPortrait.Face template=source==null||source.faces().isEmpty()?null:source.faces().get(0);
        for(PhotoPortrait.Face detected:found.faces){PhotoPortrait.Face next=detected;int match=-1;double distance=.15;for(int i=0;i<target.faces().size();i++){PhotoPortrait.Face f=target.faces().get(i);double d=Math.hypot(f.cx-detected.cx,f.cy-detected.cy);if(!used[i]&&d<distance){distance=d;match=i;}}if(match>=0){used[match]=true;PhotoPortrait.Face old=target.faces().get(match);next=old.withBounds(detected.cx,detected.cy,detected.rx,detected.ry,detected.roll).withLandmarks(detected.landmarks).withSkinMask(detected.skinMask);}if(!natural&&template!=null)next=next.withSettings(template.settings).withRetouch(template.retouch).withTone(template.tone);faces.add(next);}
        for(int i=0;i<used.length;i++)if(!used[i]){PhotoPortrait.Face old=target.faces().get(i);if(!natural&&template!=null)old=old.withSettings(template.settings).withRetouch(template.retouch).withTone(template.tone);faces.add(old);if(faces.size()>=PhotoPortrait.MAX_FACES)break;}
        if(faces.size()>PhotoPortrait.MAX_FACES)faces.subList(PhotoPortrait.MAX_FACES,faces.size()).clear();PhotoPortrait result=target.withFaces(faces).withGlobalSkinMask(found.skin);
        if(natural)return result.withRetouch(result.retouch.with(PortraitRetouch.Parameter.NATURAL,50));
        result=result.withSkinSmoothing(source.skinSmoothing).withRetouch(source.retouch);
        if(!source.globalTone.isNeutral())result=result.withGlobalTone(source.globalTone);else if(template==null||template.tone.isNeutral())result=result.withGlobalTone(source.globalTone);
        return result;
    }
    private static Bitmap decode(File file)throws IOException{
        BitmapFactory.Options bounds=new BitmapFactory.Options();bounds.inJustDecodeBounds=true;BitmapFactory.decodeFile(file.getPath(),bounds);if(bounds.outWidth<1||bounds.outHeight<1)throw new IOException("无法读取完整照片。");BitmapFactory.Options o=new BitmapFactory.Options();o.inPreferredConfig=Bitmap.Config.ARGB_8888;int sample=1;while(Math.max(bounds.outWidth,bounds.outHeight)/sample>1600)sample*=2;o.inSampleSize=sample;Bitmap b=BitmapFactory.decodeFile(file.getPath(),o);if(b==null)throw new IOException("照片分析预览解码失败。");int exif=new ExifInterface(file.getPath()).getAttributeInt("Orientation",1);float[][] matrices={{1,0,0,0,1,0,0,0,1},{-1,0,0,0,1,0,0,0,1},{-1,0,0,0,-1,0,0,0,1},{1,0,0,0,-1,0,0,0,1},{0,1,0,1,0,0,0,0,1},{0,-1,0,1,0,0,0,0,1},{0,-1,0,-1,0,0,0,0,1},{0,1,0,-1,0,0,0,0,1}};if(exif>=2&&exif<=8){Matrix m=new Matrix();m.setValues(matrices[exif-1]);Bitmap rotated=Bitmap.createBitmap(b,0,0,b.getWidth(),b.getHeight(),m,true);if(rotated!=b)b.recycle();b=rotated;}return b;
    }
    private static void check(BooleanSupplier allowed)throws InterruptedIOException{if(Thread.currentThread().isInterrupted()||!allowed.getAsBoolean())throw new InterruptedIOException("账号、页面或任务已变化，人像同步已停止。");}
}
