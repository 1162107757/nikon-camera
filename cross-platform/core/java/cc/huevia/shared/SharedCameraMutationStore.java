package cc.huevia.shared;

import cc.huevia.library.SharedJson;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.*;
import java.util.*;

/** Durable evidence precedes every camera mutation. No recovery path replays a command. */
final class SharedCameraMutationStore {
    private final File file;
    SharedCameraMutationStore(File root,String name)throws IOException {
        File directory=new File(root,"camera-actions");
        if(!directory.isDirectory()&&!directory.mkdirs())throw new IOException("无法创建相机操作记录。");
        file=new File(directory,name+".json");
    }
    Map<String,Object> read()throws IOException {
        if(!file.isFile())return new LinkedHashMap<>();
        if(file.length()>2*1024*1024)throw new IOException("相机操作记录超出范围，请先核对相机。");
        return SharedJson.object(new String(Files.readAllBytes(file.toPath()),StandardCharsets.UTF_8));
    }
    void save(Map<String,Object> value)throws IOException {
        File temporary=new File(file.getParentFile(),file.getName()+".part");
        try(FileOutputStream out=new FileOutputStream(temporary)){
            out.write(SharedJson.encode(value).getBytes(StandardCharsets.UTF_8));out.getFD().sync();
        }
        Files.move(temporary.toPath(),file.toPath(),StandardCopyOption.REPLACE_EXISTING,StandardCopyOption.ATOMIC_MOVE);
    }
    static String sha(byte[] bytes) {
        try{StringBuilder out=new StringBuilder();for(byte value:MessageDigest.getInstance("SHA-256").digest(bytes))out.append(String.format(Locale.ROOT,"%02x",value&255));return out.toString();}
        catch(NoSuchAlgorithmException impossible){throw new AssertionError(impossible);}
    }
    static String serial(String raw){String value=raw==null?"":raw.trim();return value.isEmpty()||value.length()>256||value.matches("[0\\s-]+")||value.matches("(?i)(unknown|none|null|n/a|unavailable)")||value.matches(".*[\\p{Cntrl}].*")?"":value;}
}
