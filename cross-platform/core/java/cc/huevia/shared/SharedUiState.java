package cc.huevia.shared;

import cc.huevia.library.SharedJson;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

/** Small, non-account UI preferences; only validated fields are written. */
final class SharedUiState {
    private final File file;
    SharedUiState(File root){file=new File(root,"shared-ui-state-v1.json");}
    Map<String,Object> read()throws IOException{
        Map<String,Object> value=new LinkedHashMap<>();value.put("schema",1);
        if(!file.exists())return value;
        if(!file.isFile()||file.length()>16384)throw new IOException("界面偏好文件无法读取。");
        try(InputStream in=new FileInputStream(file)){
            ByteArrayOutputStream buffer=new ByteArrayOutputStream();byte[] part=new byte[1024];int count;
            while((count=in.read(part))!=-1){if(count==0||buffer.size()+count>16384)throw new IOException("界面偏好文件过大或读取失败。");buffer.write(part,0,count);}
            byte[] bytes=buffer.toByteArray();
            Map<String,Object> saved=SharedJson.object(new String(bytes,StandardCharsets.UTF_8));
            if(SharedRuntime.integer(saved,"schema",0)!=1)throw new IOException("界面偏好版本不受支持。");
            for(Map.Entry<String,Object> entry:saved.entrySet())if(!entry.getKey().equals("schema"))value.put(entry.getKey(),validate(entry.getKey(),entry.getValue()));
        }
        return value;
    }
    Map<String,Object> update(Map<String,Object> patch)throws IOException{
        Map<String,Object> value=read();
        for(Map.Entry<String,Object> entry:patch.entrySet())value.put(entry.getKey(),validate(entry.getKey(),entry.getValue()));
        byte[] encoded=SharedJson.encode(value).getBytes(StandardCharsets.UTF_8);
        File pending=File.createTempFile("ui-state-",".part",file.getParentFile());
        try{
            try(FileOutputStream out=new FileOutputStream(pending)){out.write(encoded);out.getFD().sync();}
            java.nio.file.Files.move(pending.toPath(),file.toPath(),java.nio.file.StandardCopyOption.ATOMIC_MOVE,java.nio.file.StandardCopyOption.REPLACE_EXISTING);
        }finally{java.nio.file.Files.deleteIfExists(pending.toPath());}
        return value;
    }
    private static Object validate(String key,Object raw)throws IOException{
        if(key.equals("presetSource"))return choice(raw,"local","online");
        if(key.equals("presetLocal")||key.equals("presetOnline")){
            Map<String,Object> input=SharedRuntime.object(raw);keys(input,"category","format","download");
            String category=SharedRuntime.text(input,"category",96);
            if(category.codePointCount(0,category.length())>24||category.codePoints().anyMatch(Character::isISOControl))throw new IOException("筛选分类无效。");
            return SharedRuntime.map("category",category,"format",choice(input.get("format"),"","NCP","NP3"),"download",choice(input.get("download"),"all","saved","missing"));
        }
        if(key.equals("album")){
            Map<String,Object> input=SharedRuntime.object(raw);keys(input,"source","filter","added","oldest");
            if(!(input.get("added") instanceof Boolean)||!(input.get("oldest") instanceof Boolean))throw new IOException("相册排序偏好无效。");
            return SharedRuntime.map("source",choice(input.get("source"),"app","phone"),"filter",choice(input.get("filter"),"","starred","raw"),"added",input.get("added"),"oldest",input.get("oldest"));
        }
        throw new IOException("未知的界面偏好。");
    }
    private static String choice(Object raw,String... allowed)throws IOException{
        if(raw instanceof String)for(String value:allowed)if(value.equals(raw))return value;
        throw new IOException("界面偏好选项无效。");
    }
    private static void keys(Map<String,Object> value,String... allowed)throws IOException{
        if(!value.keySet().equals(new HashSet<>(Arrays.asList(allowed))))throw new IOException("界面偏好字段无效。");
    }
}
