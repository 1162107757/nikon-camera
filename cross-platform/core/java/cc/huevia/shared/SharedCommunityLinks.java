package cc.huevia.shared;

import cc.huevia.community.CommunityRepository;
import cc.huevia.library.OnlinePreset;
import cc.huevia.library.SharedJson;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;

/** Public discussion IDs are associated with bytes, never guessed from names. */
final class SharedCommunityLinks {
    private static final int MAX_BYTES=2*1024*1024, MAX_LINKS=10000;
    private final File root,file;
    SharedCommunityLinks(File root)throws IOException{
        this.root=root.getCanonicalFile();file=new File(this.root,"shared-community-links-v1.json");
    }
    private void owned()throws IOException{
        if(!file.getCanonicalFile().getParentFile().equals(root)||Files.isSymbolicLink(file.toPath()))
            throw new IOException("评论关联资料路径无效。");
    }
    Map<String,String> snapshot()throws IOException{
        owned();Map<String,String> result=new LinkedHashMap<>();if(!file.exists())return result;
        ByteArrayOutputStream bytes=new ByteArrayOutputStream();
        try(InputStream input=new FileInputStream(file)){
            byte[] buffer=new byte[8192];int n;
            while((n=input.read(buffer))!=-1){if(bytes.size()+n>MAX_BYTES)throw new IOException("评论关联资料过大。");bytes.write(buffer,0,n);}
        }
        Map<String,Object> document=SharedJson.object(new String(bytes.toByteArray(),StandardCharsets.UTF_8));
        if(SharedRuntime.integer(document,"schema",-1)!=1||!document.keySet().equals(new HashSet<>(Arrays.asList("schema","links"))))
            throw new IOException("评论关联资料格式无效。");
        Map<String,Object> links=SharedRuntime.object(document.get("links"));
        if(links.size()>MAX_LINKS)throw new IOException("评论关联资料过大。");
        for(Map.Entry<String,Object> entry:links.entrySet()){
            sha(entry.getKey());if(!(entry.getValue() instanceof String))throw new IOException("评论关联资料格式无效。");
            result.put(entry.getKey(),CommunityRepository.id((String)entry.getValue()));
        }
        return result;
    }
    Map<String,String> optionalSnapshot(){try{return snapshot();}catch(IOException ignored){return Collections.emptyMap();}}
    void remember(String sourceSha,String discussionId)throws IOException{
        sha(sourceSha);CommunityRepository.id(discussionId);Map<String,String> links=snapshot();
        links.put(sourceSha,discussionId);if(links.size()>MAX_LINKS)throw new IOException("评论关联资料过大。");
        byte[] encoded=SharedJson.encode(SharedRuntime.map("schema",1,"links",links)).getBytes(StandardCharsets.UTF_8);
        if(encoded.length>MAX_BYTES)throw new IOException("评论关联资料过大。");
        File pending=File.createTempFile("community-links-",".part",root);
        try{
            try(FileOutputStream out=new FileOutputStream(pending)){out.write(encoded);out.getFD().sync();}
            Files.move(pending.toPath(),file.toPath(),StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING);
        }finally{Files.deleteIfExists(pending.toPath());}
    }
    static Map<String,Object> match(String sourceSha,List<OnlinePreset> catalog)throws IOException{
        sha(sourceSha);Set<String> matches=new LinkedHashSet<>();
        for(OnlinePreset preset:catalog)if(sourceSha.equals(preset.sha256)){
            try{matches.add(CommunityRepository.id(preset.id));}catch(IOException legacyNonDiscussionId){/* Old catalogs may have non-UUID IDs. */}
        }
        if(matches.size()>1)return SharedRuntime.map("status","ambiguous","message","找到多个内容相同的在线条目，未自动关联评论。");
        if(matches.isEmpty())return SharedRuntime.map("status","missing","message","这份预设暂未关联在线讨论。");
        return SharedRuntime.map("status","linked","id",matches.iterator().next());
    }
    private static void sha(String value)throws IOException{
        if(value==null||!value.matches("[a-f0-9]{64}"))throw new IOException("预设文件标识无效。");
    }
}
