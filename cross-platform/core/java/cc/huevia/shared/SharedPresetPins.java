package cc.huevia.shared;

import cc.huevia.library.SharedJson;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.*;
import java.util.*;

/** Device-local ordering, isolated by account (including the guest library). */
final class SharedPresetPins {
    private final File root;
    SharedPresetPins(File root){this.root=root;}
    private Path path(String owner)throws IOException{
        if(!owner.isEmpty()&&!owner.matches("(?i)[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}"))throw new IOException("预设置顶账号无效。");
        try{
            byte[] hash=MessageDigest.getInstance("SHA-256").digest(owner.getBytes(StandardCharsets.UTF_8));StringBuilder key=new StringBuilder();
            for(byte b:hash)key.append(String.format(Locale.ROOT,"%02x",b&255));
            Path directory=root.toPath().resolve("preset-pins");if(Files.isSymbolicLink(directory))throw new IOException("置顶目录无效。");Files.createDirectories(directory);
            Path path=directory.resolve(key+".json");if(Files.isSymbolicLink(path))throw new IOException("置顶文件无效。");return path;
        }catch(NoSuchAlgorithmException impossible){throw new AssertionError(impossible);}
    }
    List<String> read(String owner)throws IOException{
        Path path=path(owner);if(!Files.exists(path))return new ArrayList<>();
        if(!Files.isRegularFile(path)||Files.size(path)>1500000)throw new IOException("置顶记录无法读取。");
        Map<String,Object> data=SharedJson.object(new String(Files.readAllBytes(path),StandardCharsets.UTF_8));
        if(SharedRuntime.integer(data,"schema",0)!=1||!(data.get("ids") instanceof List))throw new IOException("置顶记录无效。");
        List<String> ids=new ArrayList<>();Set<String> seen=new HashSet<>();
        for(Object id:(List<?>)data.get("ids")){if(!(id instanceof String)||!((String)id).matches("[a-f0-9]{64}")||!seen.add((String)id)||ids.size()>=20000)throw new IOException("置顶记录无效。");ids.add((String)id);}return ids;
    }
    void set(String owner,String id,boolean pinned)throws IOException{
        if(!id.matches("[a-f0-9]{64}"))throw new IOException("预设身份无效。");
        List<String> ids=read(owner);if(pinned&&ids.contains(id))return;ids.remove(id);
        if(pinned){if(ids.size()>=20000)throw new IOException("置顶数量超出范围。");ids.add(0,id);}
        Path path=path(owner),pending=Files.createTempFile(path.getParent(),"pins-",".part");
        try{byte[] bytes=SharedJson.encode(SharedRuntime.map("schema",1,"ids",ids)).getBytes(StandardCharsets.UTF_8);
            try(FileOutputStream out=new FileOutputStream(pending.toFile())){out.write(bytes);out.getFD().sync();}
            Files.move(pending,path,StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING);
        }finally{Files.deleteIfExists(pending);}
    }
    void order(String owner,List<Object> rows)throws IOException{
        Map<String,Integer> positions=new HashMap<>();List<String> ids=read(owner);for(int i=0;i<ids.size();i++)positions.put(ids.get(i),i);
        for(Object row:rows){@SuppressWarnings("unchecked") Map<String,Object> value=(Map<String,Object>)row;value.put("pinned",positions.containsKey(value.get("id")));}
        rows.sort(Comparator.comparingInt(row->positions.getOrDefault(((Map<?,?>)row).get("id"),Integer.MAX_VALUE)));
    }
}
