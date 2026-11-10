package cc.huevia.shared;

import cc.huevia.album.*;
import cc.huevia.library.SharedJson;
import cc.huevia.ptp.*;
import java.io.*;
import java.nio.file.*;
import java.security.*;
import java.util.*;
import java.util.function.*;

/** Shared read-only Wi-Fi session. Handles are scoped to the connection that enumerated them. */
public final class SharedCamera {
    public interface Connectors { PtpIpClient.SocketConnector create(String host,int port,boolean fuji)throws IOException; }
    private final File root;
    private final Connectors connectors;
    private volatile PhotoCameraClient client;
    private volatile String activeJob="";
    private String session="";
    private PtpDeviceInfo device;
    private final List<Long> handles=new ArrayList<>();
    private final Map<Long,PtpObjectInfo> observed=new LinkedHashMap<>();
    public SharedCamera(String root,Connectors connectors)throws IOException{this.root=new File(root).getCanonicalFile();this.connectors=connectors;}
    public void cancel(String job){if(job!=null&&job.equals(activeJob))closeTransport();}
    /** Can run from the host lifecycle thread without changing worker-owned indexes. */
    public void closeTransport(){PhotoCameraClient current=client;if(current!=null)current.close();}
    public synchronized String request(String operation,String json,String job,BooleanSupplier cancel,DoubleConsumer progress)throws IOException{
        activeJob=job;
        try{return SharedJson.encode(execute(operation,SharedJson.object(json),cancel,progress));}
        finally{activeJob="";}
    }
    private Object execute(String operation,Map<String,Object> p,BooleanSupplier cancel,DoubleConsumer progress)throws IOException{
        if(operation.equals("camera.disconnect")){disconnect();return SharedRuntime.map("connected",false);}
        if(operation.equals("camera.connect")){
            disconnect();String host=SharedRuntime.text(p,"host",253);int port=SharedRuntime.integer(p,"port",15740);
            if(host.isEmpty()||port<1||port>65535)throw new IOException("相机地址或端口无效。");
            String protocol=SharedRuntime.text(p,"protocol",32);if(!protocol.equals("nikon")&&!protocol.equals("fujifilm"))throw new IOException("请选择受支持的相机协议。");
            boolean fuji=protocol.equals("fujifilm");PtpIpClient.SocketConnector connector=connectors.create(host,port,fuji);
            PhotoCameraClient next=fuji?new FujifilmPhotoClient(connector):new PtpIpClient(connector);client=next;
            try{
                byte[] guid=guid();device=PtpDeviceInfo.parseRedacted(next.connect(host,port,guid,"Huevia"));
                if(!fuji&&!device.isNikonCamera())throw new IOException("相机未确认尼康协议身份。");
                for(int op:new int[]{0x1004,0x1007,0x1008,0x1009})if(!device.supportsOperation(op))throw new IOException("相机未提供照片读取能力。");
                session=UUID.randomUUID().toString();inventory(cancel);return status();
            }catch(IOException|RuntimeException failure){next.close();client=null;session="";throw failure;}
        }
        if(operation.equals("camera.status"))return status();
        require(p);PhotoCameraClient current=client;
        if(operation.equals("camera.page")){
            int offset=SharedRuntime.integer(p,"offset",0),limit=SharedRuntime.integer(p,"limit",24);
            if(offset<0||offset>handles.size()||limit<1||limit>60)throw new IOException("相机分页参数无效。");
            List<Object> rows=new ArrayList<>();int cursor=offset,scanned=0;boolean raw=Boolean.TRUE.equals(p.get("raw"));
            current.beginPhotoPage();try{
                while(cursor<handles.size()&&rows.size()<limit&&scanned++<300){check(cancel);long handle=handles.get(cursor++);PtpObjectInfo info;
                    try{info=PtpObjectInfo.parse(current.getData(0x1008,65536,handle));}catch(PtpResponseException gone){if(gone.responseCode()==0x2009)continue;throw gone;}
                    PhotoFormat format=PhotoFormat.of(info);if(format!=(raw?PhotoFormat.NEF:PhotoFormat.JPEG))continue;
                    observed.put(handle,info);rows.add(row(handle,info));
                }
            }finally{current.endPhotoPage();}
            return SharedRuntime.map("session",session,"items",rows,"nextOffset",cursor,"hasMore",cursor<handles.size(),"totalHandles",handles.size());
        }
        if(operation.equals("camera.download")){
            long handle=number(p,"handle");PtpObjectInfo before=observed.get(handle);
            if(before==null)throw new IOException("照片不属于当前浏览会话。");
            PhotoFormat format=PhotoFormat.of(before);if(format==PhotoFormat.NEF&&!Boolean.TRUE.equals(p.get("raw")))throw new IOException("请明确选择下载 RAW 原文件。");
            if(before.compressedSize()<4||before.compressedSize()>512L*1024*1024)throw new IOException("相机照片大小超出范围。");
            PtpObjectInfo fresh=PtpObjectInfo.parse(current.getData(0x1008,65536,handle));same(before,fresh);
            File directory=new File(root,"originals");if(!directory.isDirectory()&&!directory.mkdirs())throw new IOException("无法创建照片目录。");
            File temporary=File.createTempFile("camera-",".part",directory);MessageDigest digest;
            try{digest=MessageDigest.getInstance("SHA-256");}catch(NoSuchAlgorithmException impossible){throw new AssertionError(impossible);}
            try{
                try(FileOutputStream output=new FileOutputStream(temporary);OutputStream bytes=new BufferedOutputStream(new DigestOutputStream(output,digest),65536)){
                    current.readTo(0x1009,bytes,512L*1024*1024,before.compressedSize(),(received,total)->{if(cancel.getAsBoolean())current.close();progress.accept(total>0?received/(double)total:0);},handle);bytes.flush();output.getFD().sync();
                }
                check(cancel);if(temporary.length()!=before.compressedSize())throw new IOException("原文件接收不完整。");
                same(before,PtpObjectInfo.parse(current.getData(0x1008,65536,handle)));
                if(format==PhotoFormat.NEF)PhotoFormat.validateNef(temporary,before.compressedSize());else validateJpeg(temporary);
                StringBuilder hash=new StringBuilder();for(byte value:digest.digest())hash.append(String.format(Locale.ROOT,"%02x",value&255));
                check(cancel);File target=new File(directory,hash+(format==PhotoFormat.NEF?".nef":".jpg"));
                if(target.exists()){if(!sameBytes(temporary,target))throw new IOException("已有原文件校验失败。");}else Files.move(temporary.toPath(),target.toPath(),StandardCopyOption.ATOMIC_MOVE);
                return SharedRuntime.map("path",target.getPath(),"name",before.filename(),"sha256",hash.toString(),"bytes",target.length(),"raw",format==PhotoFormat.NEF);
            }finally{Files.deleteIfExists(temporary.toPath());}
        }
        throw new IOException("未知的相机操作。");
    }
    private void inventory(BooleanSupplier cancel)throws IOException{
        handles.clear();observed.clear();long[] storages=PtpStorageIds.parse(client.getData(0x1004,4096));if(storages.length>64)throw new IOException("相机存储空间数量过多。");Set<Long> unique=new LinkedHashSet<>();
        for(long storage:storages){check(cancel);byte[] data;try{data=client.getData(0x1007,1024*1024,storage,0,0);}catch(PtpResponseException error){if(error.responseCode()==0x2013)continue;throw error;}
            for(long handle:PtpObjectHandles.parse(data)){if(handle==0||handle==0xffffffffL)throw new IOException("相机返回无效照片索引。");unique.add(handle);if(unique.size()>20000)throw new IOException("本版最多浏览 20000 个相机对象。");}}
        handles.addAll(unique);Collections.reverse(handles);
    }
    private Object status(){return SharedRuntime.map("connected",client!=null&&client.isOpen(),"session",session,"model",device==null?"":device.model(),"manufacturer",device==null?"":device.manufacturer(),"totalHandles",handles.size());}
    private void require(Map<String,Object> p)throws IOException{if(client==null||!client.isOpen()||!session.equals(SharedRuntime.text(p,"session",64)))throw new IOException("相机会话已改变，请重新读取照片。");}
    public void disconnect(){PhotoCameraClient current=client;client=null;if(current!=null)current.close();session="";device=null;handles.clear();observed.clear();}
    private static void check(BooleanSupplier cancel)throws IOException{if(cancel.getAsBoolean())throw new InterruptedIOException("相机操作已取消。");}
    private byte[] guid()throws IOException{File file=new File(root,"camera-client-guid.bin");if(file.isFile()){byte[] value=Files.readAllBytes(file.toPath());if(value.length==16)return value;}byte[] value=new byte[16];new SecureRandom().nextBytes(value);Files.write(file.toPath(),value);return value;}
    private static long number(Map<String,Object> p,String key)throws IOException{Object value=p.get(key);if(!(value instanceof Number)||((Number)value).doubleValue()!=((Number)value).longValue()||((Number)value).longValue()<1||((Number)value).longValue()>=0xffffffffL)throw new IOException("相机照片索引无效。");return ((Number)value).longValue();}
    private static Object row(long handle,PtpObjectInfo info){return SharedRuntime.map("handle",handle,"name",info.filename(),"bytes",info.compressedSize(),"width",info.imagePixWidth(),"height",info.imagePixHeight(),"capturedAt",info.captureDate(),"raw",PhotoFormat.of(info)==PhotoFormat.NEF);}
    private static void same(PtpObjectInfo a,PtpObjectInfo b)throws IOException{if(!Arrays.equals(a.toBytes(),b.toBytes()))throw new IOException("相机原文件已发生变化，未接收。");}
    private static boolean sameBytes(File a,File b)throws IOException{if(a.length()!=b.length())return false;try(InputStream aa=new FileInputStream(a);InputStream bb=new FileInputStream(b)){byte[] x=new byte[65536],y=new byte[65536];while(true){int n=aa.read(x);if(n==-1)return bb.read()==-1;int off=0;while(off<n){int m=bb.read(y,off,n-off);if(m<1)return false;off+=m;}for(int i=0;i<n;i++)if(x[i]!=y[i])return false;}}}
    private static void validateJpeg(File file)throws IOException{try(RandomAccessFile input=new RandomAccessFile(file,"r")){if(input.readUnsignedShort()!=0xffd8)throw new IOException("相机原文件不是 JPEG。");input.seek(input.length()-2);if(input.readUnsignedShort()!=0xffd9)throw new IOException("相机 JPEG 原文件不完整。");}}
}
