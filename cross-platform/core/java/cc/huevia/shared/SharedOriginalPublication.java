package cc.huevia.shared;

import cc.huevia.album.PhotoEditStore;
import cc.huevia.library.SharedJson;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.Map;
import java.util.function.BooleanSupplier;

/** Byte-exact, bounded JPEG snapshot kept alive until the native album receipt. */
final class SharedOriginalPublication {
    private SharedOriginalPublication() {}
    private static final long LIMIT=512L*1024*1024;
    static Map<String,Object> prepare(File root,String owner,Map<String,Object> inspected,String operation,BooleanSupplier cancel)throws IOException {
        if(!operation.matches("[0-9a-f]{32}"))throw new IOException("原始文件保存标识无效，请重新操作。");
        String sha=(String)inspected.get("sourceSha"),format=(String)inspected.get("format");
        long bytes=((Number)inspected.get("bytes")).longValue();
        if((!format.equals("JPG")&&!format.equals("JPEG"))||bytes<4)throw new IOException("此操作只保存 JPEG 原始文件，其他格式请选择原文件导出。");
        File directory=directory(directory(root,"source-publications"),PhotoEditStore.hash(owner.getBytes(StandardCharsets.UTF_8)));
        File journal=child(directory,operation+".json"),snapshot=child(directory,operation+".jpg");
        String id=PhotoEditStore.hash(("original-jpeg-v1\n"+owner+"\n"+operation).getBytes(StandardCharsets.UTF_8));
        Map<String,Object> receipt=SharedRuntime.map("schema",1,"id",id,"sourceSha",sha,"sha256",sha,"bytes",bytes);
        if(journal.exists()) {
            if(!journal.isFile()||journal.length()>4096)throw new IOException("原始文件保存记录无效。");
            Map<String,Object> prior=SharedJson.object(new String(Files.readAllBytes(journal.toPath()),StandardCharsets.UTF_8));
            if(!id.equals(prior.get("id"))||!sha.equals(prior.get("sha256"))||!sha.equals(prior.get("sourceSha"))||SharedRuntime.integer(prior,"schema",0)!=1||!(prior.get("bytes") instanceof Number)||((Number)prior.get("bytes")).longValue()!=bytes)
                throw new IOException("此保存任务的原始文件已变化，未覆盖或重复保存。");
        } else {
            if(snapshot.exists())throw new IOException("原始文件暂存缺少记录，未覆盖或删除。");
            write(journal,SharedJson.encode(receipt).getBytes(StandardCharsets.UTF_8));
        }
        check(cancel);
        if(!snapshot.exists()) {
            long pending=0;int count=0;File[] files=directory.listFiles();
            if(files==null)throw new IOException("无法检查原始文件暂存空间。");
            for(File file:files)if(file.getName().endsWith(".jpg")||file.getName().endsWith(".part")) {pending+=file.length();count++;}
            if(count>=8||pending>2*LIMIT-bytes)throw new IOException("未完成的原始文件保存较多，请先重试之前的任务。");
            File temporary=File.createTempFile("original-",".part",directory);
            try {
                File source=new File((String)inspected.get("path"));
                try(InputStream in=new FileInputStream(source);FileOutputStream out=new FileOutputStream(temporary)) {
                    int first=in.read(),second=in.read(),third=in.read();
                    if(first!=255||second!=216||third!=255)throw new IOException("原始文件不是完整的 JPEG，未保存。");
                    out.write(first);out.write(second);out.write(third);long copied=3;byte[] buffer=new byte[65536];int n;
                    while((n=in.read(buffer))!=-1){check(cancel);copied+=n;if(copied>bytes)throw new IOException("原始文件已变化，未保存。");out.write(buffer,0,n);}
                    if(copied!=bytes)throw new IOException("原始文件尚未完整保存。");out.getFD().sync();
                }
                check(cancel);if(!sha.equals(PhotoEditStore.hashFile(temporary)))throw new IOException("原始文件校验失败，未保存。");
                Files.move(temporary.toPath(),snapshot.toPath(),StandardCopyOption.ATOMIC_MOVE);
            } finally {Files.deleteIfExists(temporary.toPath());}
        }
        if(!snapshot.isFile()||snapshot.length()!=bytes||!sha.equals(PhotoEditStore.hashFile(snapshot)))throw new IOException("原始文件暂存内容已变化，未覆盖或删除。");
        check(cancel);receipt.put("path",snapshot.getPath());return receipt;
    }
    static void release(File root,String owner,String operation,String sha,long bytes)throws IOException {
        if(!operation.matches("[0-9a-f]{32}")||!sha.matches("[0-9a-f]{64}")||bytes<4||bytes>LIMIT)throw new IOException("原始文件清理标识无效。");
        File directory=directory(directory(root,"source-publications"),PhotoEditStore.hash(owner.getBytes(StandardCharsets.UTF_8)));
        File journal=child(directory,operation+".json"),snapshot=child(directory,operation+".jpg");
        if(!journal.isFile()||journal.length()>4096)throw new IOException("原始文件保存记录不可用。");
        Map<String,Object> prior=SharedJson.object(new String(Files.readAllBytes(journal.toPath()),StandardCharsets.UTF_8));
        if(!sha.equals(prior.get("sha256"))||!(prior.get("bytes") instanceof Number)||((Number)prior.get("bytes")).longValue()!=bytes)throw new IOException("原始文件保存记录不匹配。");
        if(snapshot.exists()) {
            if(!snapshot.isFile()||snapshot.length()!=bytes||!sha.equals(PhotoEditStore.hashFile(snapshot)))throw new IOException("原始文件暂存内容已变化，未删除。");
            Files.delete(snapshot.toPath());
        }
        // The tiny binding survives: reusing an operation for another source is rejected.
    }
    private static File directory(File parent,String name)throws IOException {
        File file=child(parent.getCanonicalFile(),name);
        if(!file.isDirectory()&&!file.mkdir())throw new IOException("无法创建原始文件暂存目录。");return file;
    }
    private static File child(File parent,String name)throws IOException {
        File file=new File(parent,name);
        if(Files.isSymbolicLink(file.toPath())||!parent.equals(file.getCanonicalFile().getParentFile()))throw new IOException("原始文件暂存路径无效。");return file;
    }
    private static void write(File file,byte[] value)throws IOException {
        File temporary=File.createTempFile("original-record-",".part",file.getParentFile());
        try {try(FileOutputStream out=new FileOutputStream(temporary)){out.write(value);out.getFD().sync();}Files.move(temporary.toPath(),file.toPath(),StandardCopyOption.ATOMIC_MOVE);}
        finally {Files.deleteIfExists(temporary.toPath());}
    }
    private static void check(BooleanSupplier cancel)throws InterruptedIOException {
        if(Thread.currentThread().isInterrupted()||(cancel!=null&&cancel.getAsBoolean()))throw new InterruptedIOException("原始文件保存已取消。");
    }
}
