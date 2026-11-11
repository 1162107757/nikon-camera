package cc.huevia.sharedapp;

import android.graphics.*;
import android.media.ExifInterface;
import cc.huevia.account.AccountRepository;
import java.io.*;
import java.util.function.BooleanSupplier;

/** Original AvatarImages geometry and JPEG policy, decoding from the bounded owned file. */
final class NativeAvatar {
    private NativeAvatar(){}
    static byte[] prepare(File source,BooleanSupplier cancel)throws IOException{
        if(!source.isFile()||source.length()<4||source.length()>20L*1024*1024)throw invalid();
        Bitmap decoded=null,oriented=null,square=null;
        try{
            check(cancel);BitmapFactory.Options bounds=new BitmapFactory.Options();bounds.inJustDecodeBounds=true;
            BitmapFactory.decodeFile(source.getPath(),bounds);
            if(bounds.outWidth<64||bounds.outHeight<64||bounds.outWidth>32768||bounds.outHeight>32768||(long)bounds.outWidth*bounds.outHeight>128000000)throw invalid();
            BitmapFactory.Options options=new BitmapFactory.Options();options.inSampleSize=1;
            while(Math.max(bounds.outWidth,bounds.outHeight)/options.inSampleSize>2048)options.inSampleSize*=2;
            decoded=BitmapFactory.decodeFile(source.getPath(),options);if(decoded==null)throw invalid();
            int orientation=ExifInterface.ORIENTATION_NORMAL;
            try{orientation=new ExifInterface(source.getPath()).getAttributeInt(ExifInterface.TAG_ORIENTATION,orientation);}catch(IOException ignored){}
            Matrix matrix=new Matrix();
            switch(orientation){
                case ExifInterface.ORIENTATION_FLIP_HORIZONTAL:matrix.setScale(-1,1);break;
                case ExifInterface.ORIENTATION_ROTATE_180:matrix.setRotate(180);break;
                case ExifInterface.ORIENTATION_FLIP_VERTICAL:matrix.setScale(1,-1);break;
                case ExifInterface.ORIENTATION_TRANSPOSE:matrix.setRotate(90);matrix.postScale(-1,1);break;
                case ExifInterface.ORIENTATION_ROTATE_90:matrix.setRotate(90);break;
                case ExifInterface.ORIENTATION_TRANSVERSE:matrix.setRotate(270);matrix.postScale(-1,1);break;
                case ExifInterface.ORIENTATION_ROTATE_270:matrix.setRotate(270);break;
            }
            check(cancel);oriented=matrix.isIdentity()?decoded:Bitmap.createBitmap(decoded,0,0,decoded.getWidth(),decoded.getHeight(),matrix,true);
            int side=Math.min(oriented.getWidth(),oriented.getHeight()),size=Math.min(512,Math.max(64,side));
            square=Bitmap.createBitmap(size,size,Bitmap.Config.ARGB_8888);Canvas canvas=new Canvas(square);canvas.drawColor(Color.WHITE);
            Rect crop=new Rect((oriented.getWidth()-side)/2,(oriented.getHeight()-side)/2,(oriented.getWidth()+side)/2,(oriented.getHeight()+side)/2);
            canvas.drawBitmap(oriented,crop,new Rect(0,0,size,size),new Paint(Paint.ANTI_ALIAS_FLAG|Paint.FILTER_BITMAP_FLAG));
            byte[] result=null;
            for(int quality=92;quality>=52;quality-=10){check(cancel);ByteArrayOutputStream output=new ByteArrayOutputStream();if(!square.compress(Bitmap.CompressFormat.JPEG,quality,output))throw invalid();result=output.toByteArray();if(result.length<=AccountRepository.MAX_AVATAR_BYTES)break;}
            if(result==null||result.length>AccountRepository.MAX_AVATAR_BYTES)throw invalid();return result;
        }catch(OutOfMemoryError|RuntimeException failure){throw invalid();}
        finally{if(square!=null)square.recycle();if(oriented!=null&&oriented!=decoded)oriented.recycle();if(decoded!=null)decoded.recycle();}
    }
    private static void check(BooleanSupplier cancel)throws InterruptedIOException{if(Thread.currentThread().isInterrupted()||cancel!=null&&cancel.getAsBoolean())throw new InterruptedIOException("头像处理已取消。");}
    private static IOException invalid(){return new IOException("请选择有效图片，原图需小于 20 MB，尺寸至少 64×64。");}
}
