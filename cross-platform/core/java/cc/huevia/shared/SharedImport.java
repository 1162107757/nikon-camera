package cc.huevia.shared;

import cc.huevia.album.PhotoEditStore;
import cc.huevia.library.SharedJson;
import java.io.*;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.security.*;
import java.util.*;
import java.util.function.BooleanSupplier;

/** Native document streams never travel through the Flutter channel or UI heap. */
public final class SharedImport {
    private SharedImport(){}
    private static final Set<String> PHOTOS=new HashSet<>(Arrays.asList("jpg","jpeg","png","heic","heif","webp","nef","nrw","dng","arw","cr2","cr3","raf","rw2","orf","pef","srw"));
    public static String copy(InputStream input,String name,boolean preset,String directory,BooleanSupplier cancel)throws IOException{
        return copyOwned(input,name,preset,directory,cancel,"","");
    }
    public static String stageSubmission(InputStream input,String name,String kind,String owner,String directory,BooleanSupplier cancel)throws IOException{
        if(!"ncp".equals(kind)&&!"preview".equals(kind)){if(input!=null)input.close();throw new IOException("投稿文件类型无效。");}
        return copyOwned(input,name,"ncp".equals(kind),directory,cancel,kind,owner);
    }
    public static String stageAvatar(InputStream input,String name,String owner,String directory,BooleanSupplier cancel)throws IOException{
        return copyOwned(input,name,false,directory,cancel,"avatar",owner);
    }
    private static String copyOwned(InputStream input,String name,boolean preset,String directory,BooleanSupplier cancel,String submissionKind,String owner)throws IOException{
        try(InputStream source=Objects.requireNonNull(input)){
            check(cancel);
            boolean submission=!submissionKind.isEmpty(),avatar=submissionKind.equals("avatar");
            if(submission){cc.huevia.community.CommunityRepository.id(owner);if(!submissionKind.equals("ncp")&&!submissionKind.equals("preview")&&!avatar)throw new IOException("投稿文件类型无效。");}
            if(name==null||name.isEmpty()||name.length()>1024||name.indexOf('/')>=0||name.indexOf('\\')>=0||!StandardCharsets.UTF_8.newEncoder().canEncode(name)||name.codePoints().anyMatch(Character::isISOControl))throw new IOException("所选文件名称无效。");
            int dot=name.lastIndexOf('.');String ext=dot<0?"":name.substring(dot+1).toLowerCase(Locale.ROOT);
            if(!avatar&&(submission?(preset?!ext.equals("ncp"):!Arrays.asList("jpg","jpeg","png","webp").contains(ext)):(preset?!ext.equals("ncp")&&!ext.equals("np3"):!PHOTOS.contains(ext))))throw new IOException("请选择受支持的文件格式。");
            if(avatar&&ext.isEmpty())ext="image";
            long limit=preset?1024*1024:avatar?20L*1024*1024:submission?4L*1024*1024:1024L*1024*1024;
            File base=new File(directory).getCanonicalFile();
            if(submission){File parent=new File(base,avatar?"avatar-incoming":"submission-incoming");if(!parent.getCanonicalFile().getParentFile().equals(base)||Files.isSymbolicLink(parent.toPath())||!parent.isDirectory()&&!parent.mkdirs())throw new IOException("无法创建账号图片导入目录。");base=parent.getCanonicalFile();}
            File folder=new File(base,submission?owner:preset?"incoming":"originals");
            if(!folder.getCanonicalFile().getParentFile().equals(base)||Files.isSymbolicLink(folder.toPath())||!folder.isDirectory()&&!folder.mkdirs())throw new IOException("无法创建文件导入目录。");
            File temp=File.createTempFile("import-",".part",folder);
            try{
                MessageDigest digest;try{digest=MessageDigest.getInstance("SHA-256");}catch(NoSuchAlgorithmException impossible){throw new AssertionError(impossible);}
                long size=0;byte[] buffer=new byte[65536];
                try(FileOutputStream output=new FileOutputStream(temp)){
                    int count;while((count=source.read(buffer))!=-1){check(cancel);if(count==0)continue;size+=count;if(size>limit)throw new IOException("文件大小超出允许范围。");output.write(buffer,0,count);digest.update(buffer,0,count);}
                    if(size==0)throw new IOException("所选文件为空。");output.getFD().sync();
                }
                StringBuilder sha=new StringBuilder();for(byte value:digest.digest())sha.append(String.format(Locale.ROOT,"%02x",value&255));
                File target=new File(folder,sha+"."+ext);boolean created=false;check(cancel);
                synchronized(SharedImport.class){
                    if(target.exists())verify(target,size,sha.toString());
                    else try{Files.move(temp.toPath(),target.toPath());created=true;}
                    catch(FileAlreadyExistsException duplicate){verify(target,size,sha.toString());}
                }
                return SharedJson.encode(SharedRuntime.map("path",target.getPath(),"name",name,"bytes",size,"sha256",sha.toString(),"created",created));
            }finally{Files.deleteIfExists(temp.toPath());}
        }
    }
    private static void verify(File target,long size,String sha)throws IOException{
        if(Files.isSymbolicLink(target.toPath())||!target.isFile()||target.length()!=size||!PhotoEditStore.hashFile(target).equals(sha))throw new IOException("已有同名原文件校验失败，未覆盖。");
    }
    private static void check(BooleanSupplier cancel)throws IOException{if(Thread.currentThread().isInterrupted()||cancel!=null&&cancel.getAsBoolean())throw new InterruptedIOException("文件导入已取消。");}
}
