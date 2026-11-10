package cc.huevia.rawdevelopmentqa;
import android.graphics.*;
import android.content.Context;
import java.io.*;
import java.lang.reflect.*;
import java.util.*;
import java.util.function.*;
import java.util.zip.CRC32;
import org.json.*;

/** Independent native decoder, chunk/CRC, exact pixel, cancellation and I/O failure checks. */
public final class RawPngWriterChecks {
    public static void run(Context context,JSONArray checks)throws Exception{
        Class<?> writer=Class.forName("cc.huevia.album.RawPngWriter",true,context.getClassLoader());
        Method write=writer.getMethod("write",Bitmap.class,OutputStream.class,BooleanSupplier.class,DoubleConsumer.class);
        for(int[] size:new int[][]{{1,1},{7,33},{401,97},{6064,35},{57,64}}){
            int width=size[0],height=size[1];Random random=new Random(width*1009L+height);int[] source=new int[width*height];
            for(int i=0;i<source.length;i++)source[i]=0xff000000|random.nextInt(0x1000000);
            Bitmap bitmap=Bitmap.createBitmap(source,width,height,Bitmap.Config.ARGB_8888);
            try{
                ByteArrayOutputStream bytes=new ByteArrayOutputStream();double[] previous={0};boolean[] monotonic={true};
                invoke(write,bitmap,bytes,()->false,v->{monotonic[0]&=v>=previous[0];previous[0]=v;});byte[] png=bytes.toByteArray();
                check(checks,"PNG-progress-"+width+"x"+height,monotonic[0]&&previous[0]==1);
                Bitmap decoded=BitmapFactory.decodeByteArray(png,0,png.length);check(checks,"PNG-native-decoder-"+width,decoded!=null&&decoded.getWidth()==width&&decoded.getHeight()==height);
                try{int[] actual=new int[source.length];decoded.getPixels(actual,0,width,0,0,width,height);check(checks,"PNG-exact-all-pixels-"+width+"x"+height,Arrays.equals(source,actual));}finally{if(decoded!=null)decoded.recycle();}
                DataInputStream input=new DataInputStream(new ByteArrayInputStream(png));check(checks,"PNG-signature-"+width,input.readLong()==0x89504e470d0a1a0aL);
                boolean ended=false,srgb=false;int idats=0;
                while(input.available()>0){int n=input.readInt();byte[] type=new byte[4],body=new byte[n];input.readFully(type);input.readFully(body);long declared=input.readInt()&0xffffffffL;CRC32 crc=new CRC32();crc.update(type);crc.update(body);check(checks,"PNG-every-chunk-CRC-"+width,crc.getValue()==declared);String tag=new String(type,java.nio.charset.StandardCharsets.US_ASCII);if(tag.equals("sRGB"))srgb=true;if(tag.equals("IDAT"))idats++;if(tag.equals("IEND"))ended=true;}
                check(checks,"PNG-complete-sRGB-"+width,ended&&srgb&&idats>0);
                boolean[] cancel={false};boolean rejected=false;try{invoke(write,bitmap,new ByteArrayOutputStream(),()->cancel[0],v->{cancel[0]=true;});}catch(InterruptedIOException expected){rejected=true;}check(checks,"PNG-mid-stream-cancel-"+width,rejected);
                rejected=false;try{invoke(write,bitmap,new OutputStream(){public void write(int value)throws IOException{throw new IOException("injected full storage");}},()->false,null);}catch(IOException expected){rejected=true;}check(checks,"PNG-I/O-failure-propagates-"+width,rejected);
            }finally{bitmap.recycle();}
        }
        Bitmap transparent=Bitmap.createBitmap(4,4,Bitmap.Config.ARGB_8888);try{boolean rejected=false;try{invoke(write,transparent,new ByteArrayOutputStream(),()->false,null);}catch(IOException expected){rejected=true;}check(checks,"PNG-refuses-unexpected-alpha-rather-than-dropping-it",rejected);}finally{transparent.recycle();}
    }
    private static void invoke(Method method,Bitmap bitmap,OutputStream output,BooleanSupplier cancel,DoubleConsumer progress)throws Exception{try{method.invoke(null,bitmap,output,cancel,progress);}catch(InvocationTargetException failure){Throwable cause=failure.getCause();if(cause instanceof Exception)throw(Exception)cause;throw new AssertionError(cause);}}
    private static void check(JSONArray checks,String name,boolean pass)throws Exception{checks.put(new JSONObject().put("name",name).put("passed",pass));if(!pass)throw new AssertionError(name);}
}
