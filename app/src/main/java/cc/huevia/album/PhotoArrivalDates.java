package cc.huevia.album;

import android.util.AtomicFile;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.security.MessageDigest;

/** Presentation metadata only. Arrival journaling must never fail an original-photo commit. */
public final class PhotoArrivalDates {
    private PhotoArrivalDates() { }
    public static synchronized long read(File photo) {
        try(DataInputStream in=new DataInputStream(record(photo,false).openRead())) {
            if(in.readInt()!=0x48415231||!in.readUTF().equals(photo.getName()))return 0;
            long date=in.readLong();return date>0&&date<=253402300799999L?date:0;
        }catch(IOException|RuntimeException invalid){return 0;}
    }
    public static synchronized void record(File photo) { write(photo,System.currentTimeMillis()); }
    public static synchronized void recordIfMissing(File photo) { if(read(photo)==0)record(photo); }
    static synchronized void write(File photo,long receivedAt) {
        AtomicFile target=null;FileOutputStream stream=null;
        try {
            target=record(photo,true);stream=target.startWrite();DataOutputStream out=new DataOutputStream(stream);
            out.writeInt(0x48415231);out.writeUTF(photo.getName());out.writeLong(receivedAt);out.flush();target.finishWrite(stream);stream=null;
        }catch(IOException|RuntimeException ignored){if(stream!=null&&target!=null)try{target.failWrite(stream);}catch(RuntimeException alsoIgnored){}}
    }
    public static synchronized void forget(File photo) {
        try{record(photo,false).delete();}catch(IOException|RuntimeException ignored){}
    }
    private static AtomicFile record(File photo,boolean create)throws IOException {
        File original=photo.getCanonicalFile(),parent=original.getParentFile();
        if(parent==null||Files.isSymbolicLink(photo.toPath()))throw new IOException("照片日期路径无效");
        File directory=new File(parent,".huevia-arrivals").getCanonicalFile();
        if(!parent.equals(directory.getParentFile()))throw new IOException("照片日期目录无效");
        if(create&&!directory.isDirectory()&&!directory.mkdirs())throw new IOException("无法保存照片添加时间");
        try{
            byte[] bytes=MessageDigest.getInstance("SHA-256").digest(original.getName().getBytes(StandardCharsets.UTF_8));
            StringBuilder key=new StringBuilder();for(byte value:bytes)key.append(String.format(java.util.Locale.ROOT,"%02x",value&255));
            return new AtomicFile(new File(directory,key+".arrival"));
        }catch(java.security.NoSuchAlgorithmException impossible){throw new AssertionError(impossible);}
    }
}
