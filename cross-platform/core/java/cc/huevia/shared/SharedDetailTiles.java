package cc.huevia.shared;

import cc.huevia.library.SharedJson;
import java.io.*;
import java.nio.file.*;
import java.security.*;
import java.util.*;
import java.util.function.BooleanSupplier;

/** Read-only capabilities for rendered full-resolution editing planes. */
public final class SharedDetailTiles {
    private final File root;
    private final LinkedHashMap<String,Entry> entries=new LinkedHashMap<>();
    public SharedDetailTiles(File root){this.root=root.getAbsoluteFile();}
    public static final class Entry {
        public final String token,owner,sourcePath,sourceSha,path,detailSha;
        public final int width,height;
        private Entry(String token,String owner,String sourcePath,String sourceSha,String path,String detailSha,int width,int height){this.token=token;this.owner=owner;this.sourcePath=sourcePath;this.sourceSha=sourceSha;this.path=path;this.detailSha=detailSha;this.width=width;this.height=height;}
    }
    public synchronized String remember(String source,String owner,String sourceSha,String detail,int width,int height,BooleanSupplier cancel)throws IOException{
        if(owner==null||owner.length()>64||sourceSha==null||!sourceSha.matches("[0-9a-f]{64}")||width<1||height<1||(long)width*height>100_000_000)throw new IOException("完整细节图身份无效。");
        File original=privateFile(source,false),full=privateFile(detail,true);
        if(!sourceSha.equals(digest(original,cancel)))throw new IOException("原图已变化，请重新打开照片。");
        String detailSha=digest(full,cancel),token=UUID.randomUUID().toString();check(cancel);
        // Hosts delete disposable planes after leaving a child tool. Retire
        // those capabilities before applying the bound, so a still-open
        // editor's full plane survives repeated short-lived tool sessions.
        Iterator<Entry> retired=entries.values().iterator();
        while(retired.hasNext()){check(cancel);if(!new File(retired.next().path).isFile())retired.remove();}
        entries.put(token,new Entry(token,owner,original.getPath(),sourceSha,full.getPath(),detailSha,width,height));
        while(entries.size()>32)entries.remove(entries.keySet().iterator().next());
        return token;
    }
    public synchronized Entry checked(String token,String owner,String path,String sourceSha,BooleanSupplier cancel)throws IOException{
        Entry entry=entries.get(token);
        if(entry==null||!entry.owner.equals(owner)||!entry.sourceSha.equals(sourceSha)||!entry.path.equals(privateFile(path,true).getPath()))throw new IOException("细节图已失效，请重新打开照片。");
        verify(entry,cancel);return entry;
    }
    public void verify(Entry entry,BooleanSupplier cancel)throws IOException{
        if(!entry.sourceSha.equals(digest(privateFile(entry.sourcePath,false),cancel))||!entry.detailSha.equals(digest(privateFile(entry.path,true),cancel)))throw new IOException("原图或细节图已变化，请重新打开照片。");
        check(cancel);
    }
    private File privateFile(String value,boolean preview)throws IOException{
        if(value==null)throw new IOException("细节图路径无效。");
        File supplied=new File(value),file=supplied.getCanonicalFile();Path base=root.toPath(),candidate=file.toPath();
        if(!candidate.startsWith(base)||!file.isFile()||(preview&&!file.getParentFile().equals(new File(root,"previews"))))throw new IOException("细节图不在应用预览目录内。");
        for(Path next=supplied.toPath().toAbsolutePath();next!=null&&next.startsWith(base);next=next.getParent())if(Files.isSymbolicLink(next))throw new IOException("细节图路径无效。");
        return file;
    }
    private static String digest(File file,BooleanSupplier cancel)throws IOException{
        MessageDigest digest;try{digest=MessageDigest.getInstance("SHA-256");}catch(NoSuchAlgorithmException impossible){throw new AssertionError(impossible);}
        byte[] buffer=new byte[65536];try(InputStream in=new FileInputStream(file)){for(int n;(n=in.read(buffer))!=-1;){check(cancel);digest.update(buffer,0,n);}}
        StringBuilder value=new StringBuilder(64);for(byte b:digest.digest())value.append(String.format(Locale.ROOT,"%02x",b&255));return value.toString();
    }
    public static void check(BooleanSupplier cancel)throws InterruptedIOException{if(cancel.getAsBoolean())throw new InterruptedIOException("细节读取已取消。");}
    /** EXIF UNDEFINED (0) and invalid tags mean upright, as in the ordinary renderers. */
    public static int normalizedOrientation(int value){return value>=1&&value<=8?value:1;}
    /** Pixel rectangles are in the upright output plane, with exclusive right/bottom. */
    public static final class Plan {
        public final int sourceWidth,sourceHeight,left,top,right,bottom,width,height,sampleSize,rawLeft,rawTop,rawRight,rawBottom,rawWidth,rawHeight,orientation;
        public Plan(int rawWidth,int rawHeight,int orientation,double left,double top,double right,double bottom,int maxEdge)throws IOException{
            if(rawWidth<1||rawHeight<1||(long)rawWidth*rawHeight>100_000_000||orientation<1||orientation>8||maxEdge<64||maxEdge>2048||!Double.isFinite(left)||!Double.isFinite(top)||!Double.isFinite(right)||!Double.isFinite(bottom)||left<0||top<0||right>1||bottom>1||right<=left||bottom<=top)throw new IOException("细节可见区域无效。");
            this.rawWidth=rawWidth;this.rawHeight=rawHeight;this.orientation=orientation;
            sourceWidth=orientation>=5?rawHeight:rawWidth;sourceHeight=orientation>=5?rawWidth:rawHeight;
            this.left=Math.max(0,Math.min(sourceWidth-1,(int)Math.floor(left*sourceWidth)));this.top=Math.max(0,Math.min(sourceHeight-1,(int)Math.floor(top*sourceHeight)));
            this.right=Math.max(this.left+1,Math.min(sourceWidth,(int)Math.ceil(right*sourceWidth)));this.bottom=Math.max(this.top+1,Math.min(sourceHeight,(int)Math.ceil(bottom*sourceHeight)));
            double x0=sourceX(this.left,this.top),x1=sourceX(this.right,this.bottom),y0=sourceY(this.left,this.top),y1=sourceY(this.right,this.bottom);
            rawLeft=(int)Math.min(x0,x1);rawTop=(int)Math.min(y0,y1);rawRight=(int)Math.max(x0,x1);rawBottom=(int)Math.max(y0,y1);
            int sample=1;while((Math.max(this.right-this.left,this.bottom-this.top)+sample-1)/sample>maxEdge)sample*=2;sampleSize=sample;
            width=Math.max(1,(this.right-this.left+sample-1)/sample);height=Math.max(1,(this.bottom-this.top+sample-1)/sample);
        }
        public double sourceX(double x,double y){switch(orientation){case 2:case 3:return rawWidth-x;case 5:case 6:return y;case 7:case 8:return rawWidth-y;default:return x;}}
        public double sourceY(double x,double y){switch(orientation){case 3:case 4:return rawHeight-y;case 5:case 8:return x;case 6:case 7:return rawHeight-x;default:return y;}}
        public String regionJson(){return SharedJson.encode(SharedRuntime.map("left",(double)left/sourceWidth,"top",(double)top/sourceHeight,"right",(double)right/sourceWidth,"bottom",(double)bottom/sourceHeight));}
    }
}
