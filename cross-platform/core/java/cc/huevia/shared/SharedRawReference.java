package cc.huevia.shared;

import java.io.*;
import java.nio.file.Files;
import java.security.*;
import java.util.*;
import java.util.function.BooleanSupplier;

/** Explicit same-frame JPEG evidence. No filename-based automatic association. */
public final class SharedRawReference {
    public static final long MAX_BYTES=16L*1024*1024;
    private SharedRawReference(){}
    public static final class Reference {
        public final File file;
        public final String sha256,sourceSha;
        private Reference(File file,String sha,String source){this.file=file;sha256=sha;sourceSha=source;}
        public void verifySource(String source)throws IOException{if(!sourceSha.equals(source))throw new IOException("JPEG 参考不属于这张 RAW，请重新选择参考照片。");}
        public void verify(BooleanSupplier cancel)throws IOException{if(!sha256.equals(hash(file,MAX_BYTES,cancel)))throw new IOException("JPEG 参考原文件已变化，请重新选择。");}
    }
    public static Map<String,Object> describe(File root,File source,String path,BooleanSupplier cancel)throws IOException{
        source=checked(root,source.getPath());
        File reference=checked(root,path);jpeg(reference);
        if(reference.equals(source.getCanonicalFile()))throw new IOException("RAW 原文件不能作为 JPEG 参考。");
        return SharedRuntime.map("path",reference.getPath(),"sha256",hash(reference,MAX_BYTES,cancel),"sourceSha",hash(source,1024L*1024*1024,cancel));
    }
    public static String describeJson(File root,File source,String path,BooleanSupplier cancel)throws IOException{return cc.huevia.library.SharedJson.encode(describe(root,source,path,cancel));}
    public static Reference resolve(File root,String descriptor,BooleanSupplier cancel)throws IOException{
        if(descriptor==null||descriptor.isEmpty())return null;
        Map<String,Object> value=cc.huevia.library.SharedJson.object(descriptor);
        String sha=SharedRuntime.text(value,"sha256",64),source=SharedRuntime.text(value,"sourceSha",64);
        if(!sha.matches("[0-9a-f]{64}")||!source.matches("[0-9a-f]{64}"))throw new IOException("JPEG 参考身份无效，请重新选择。");
        File file=checked(root,SharedRuntime.text(value,"path",32768));jpeg(file);
        Reference reference=new Reference(file,sha,source);reference.verify(cancel);return reference;
    }
    private static File checked(File root,String path)throws IOException{
        if(path==null||path.isEmpty())throw new IOException("请选择 JPEG 参考照片。");
        File input=new File(path),canonical=input.getCanonicalFile(),originals=new File(root,"originals").getCanonicalFile();
        if(!canonical.toPath().startsWith(originals.toPath())||canonical.equals(originals)||Files.isSymbolicLink(input.toPath())||!canonical.isFile())throw new IOException("JPEG 参考必须先导入应用原图库。");
        return canonical;
    }
    private static void jpeg(File file)throws IOException{
        if(file.length()<4||file.length()>MAX_BYTES)throw new IOException("请选择 16MB 以内的完整 JPEG 参考照片。");
        try(RandomAccessFile input=new RandomAccessFile(file,"r")){
            if(input.readUnsignedShort()!=0xffd8)throw new IOException("参考照片必须为 JPEG 原文件。");
            input.seek(input.length()-2);if(input.readUnsignedShort()!=0xffd9)throw new IOException("JPEG 参考尚未完整接收。");
        }
    }
    private static String hash(File file,long maximum,BooleanSupplier cancel)throws IOException{
        if(!file.isFile()||file.length()<4||file.length()>maximum)throw new IOException("参考或 RAW 原文件大小无效。");
        long length=file.length(),modified=file.lastModified();MessageDigest digest;
        try{digest=MessageDigest.getInstance("SHA-256");}catch(NoSuchAlgorithmException impossible){throw new AssertionError(impossible);}
        byte[] buffer=new byte[65536];try(InputStream input=new FileInputStream(file)){int count;while((count=input.read(buffer))!=-1){if(cancel.getAsBoolean())throw new InterruptedIOException("JPEG 参考核对已取消。");digest.update(buffer,0,count);}}
        if(file.length()!=length||file.lastModified()!=modified)throw new IOException("核对期间原文件发生变化。");
        StringBuilder result=new StringBuilder(64);for(byte value:digest.digest())result.append(Character.forDigit((value>>>4)&15,16)).append(Character.forDigit(value&15,16));return result.toString();
    }
}
