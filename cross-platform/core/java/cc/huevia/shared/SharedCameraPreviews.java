package cc.huevia.shared;

import java.io.*;
import java.nio.file.*;
import java.security.*;
import java.util.*;
import java.util.function.BooleanSupplier;

/** Camera-generated JPEG previews only. Never downloads or registers a source photograph. */
final class SharedCameraPreviews {
    static final int MAX_BYTES=8*1024*1024,MAX_FILES=64;
    static final long CACHE_BYTES=32L*1024*1024;
    private final File root;
    SharedCameraPreviews(File root)throws IOException{this.root=root.getCanonicalFile();}
    String key(String session,long handle,byte[] metadata){
        try{MessageDigest hash=MessageDigest.getInstance("SHA-256");hash.update((session+"\n"+handle+"\n").getBytes(java.nio.charset.StandardCharsets.UTF_8));hash.update(metadata);StringBuilder text=new StringBuilder();for(byte b:hash.digest())text.append(String.format(Locale.ROOT,"%02x",b&255));return text.toString();}
        catch(NoSuchAlgorithmException impossible){throw new AssertionError(impossible);}
    }
    File cached(String key)throws IOException{
        File target=file(key,".jpg");if(!target.isFile())return null;
        if(!complete(target))return null;target.setLastModified(System.currentTimeMillis());return target;
    }
    File store(String key,byte[] jpeg,BooleanSupplier cancel)throws IOException{
        if(jpeg==null||jpeg.length<4||jpeg.length>MAX_BYTES||(jpeg[0]&255)!=255||(jpeg[1]&255)!=216||(jpeg[jpeg.length-2]&255)!=255||(jpeg[jpeg.length-1]&255)!=217)throw new IOException("相机未返回完整 JPEG 缩略图，请重试或接收原文件后查看。");
        check(cancel);File target=file(key,".jpg"),part=file(key,".part");trim(target,jpeg.length);
        try{
            try(FileOutputStream output=new FileOutputStream(part)){for(int offset=0;offset<jpeg.length;){check(cancel);int count=Math.min(65536,jpeg.length-offset);output.write(jpeg,offset,count);offset+=count;}output.getFD().sync();}
            check(cancel);Files.move(part.toPath(),target.toPath(),StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING);return target;
        }finally{Files.deleteIfExists(part.toPath());}
    }
    private File file(String key,String suffix)throws IOException{
        if(!key.matches("[a-f0-9]{64}"))throw new IOException("缩略图标识无效。");
        File directory=new File(root,"camera-previews");
        if(Files.isSymbolicLink(directory.toPath())||!directory.getCanonicalFile().getParentFile().equals(root))throw new IOException("缩略图缓存目录无效。");
        if(!directory.isDirectory()&&!directory.mkdirs())throw new IOException("无法创建缩略图缓存。");
        File target=new File(directory,key+suffix);
        if(Files.isSymbolicLink(target.toPath())||!target.getCanonicalFile().getParentFile().equals(directory.getCanonicalFile()))throw new IOException("缩略图缓存路径无效。");return target;
    }
    private void trim(File target,int needed)throws IOException{
        File[] entries=target.getParentFile().listFiles();if(entries==null)throw new IOException("无法读取缩略图缓存。");
        List<File> own=new ArrayList<>();long bytes=0;
        for(File file:entries)if(file.isFile()&&!Files.isSymbolicLink(file.toPath())&&file.getName().matches("[a-f0-9]{64}\\.(jpg|part)")){own.add(file);bytes+=file.length();}
        if(target.isFile()){bytes-=target.length();own.remove(target);}
        own.sort(Comparator.comparingLong(File::lastModified));int count=own.size();
        for(File file:own){if(bytes+needed<=CACHE_BYTES&&count<MAX_FILES)break;long length=file.length();Files.delete(file.toPath());bytes-=length;count--;}
        if(bytes+needed>CACHE_BYTES||count>=MAX_FILES)throw new IOException("缩略图缓存已满，请稍后重试。");
    }
    private static boolean complete(File file)throws IOException{
        if(file.length()<4||file.length()>MAX_BYTES)return false;
        try(RandomAccessFile input=new RandomAccessFile(file,"r")){if(input.readUnsignedShort()!=0xffd8)return false;input.seek(input.length()-2);return input.readUnsignedShort()==0xffd9;}
    }
    private static void check(BooleanSupplier cancel)throws InterruptedIOException{if(cancel.getAsBoolean())throw new InterruptedIOException("缩略图读取已取消。");}
}
