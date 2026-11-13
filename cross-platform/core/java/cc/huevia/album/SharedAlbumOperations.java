package cc.huevia.album;

import cc.huevia.library.SharedJson;
import cc.huevia.shared.SharedRuntime;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.function.BooleanSupplier;

/** Explicit album deletion scopes. Stable identities are recorded before any unlink. */
public final class SharedAlbumOperations {
    private SharedAlbumOperations(){}
    public static String request(SharedRuntime runtime,String operation,String json,BooleanSupplier cancel)throws IOException {
        Map<String,Object> p=SharedJson.object(json);String owner=SharedRuntime.text(p,"owner",64);runtime.guardOwner(owner);check(cancel);
        String id=SharedRuntime.text(p,"operationId",32);if(!id.matches("[0-9a-f]{32}"))throw new IOException("删除任务标识无效。");
        File root=runtime.root().getCanonicalFile(),directory=new File(root,"album-deletions");checked(root,directory);if(!directory.isDirectory()&&!directory.mkdirs())throw new IOException("无法记录删除任务。");
        File record=new File(directory,id+".json");checked(root,record);
        Map<String,Object> frozen;
        if(record.exists()){
            if(record.length()>512*1024)throw new IOException("删除任务记录过大。");frozen=SharedJson.object(new String(Files.readAllBytes(record.toPath()),StandardCharsets.UTF_8));
            if(!owner.equals(frozen.get("owner"))||!operation.equals(frozen.get("operation"))||!SharedRuntime.text(p,"path",4096).equals(frozen.get("path")))throw new IOException("删除任务与当前选择不符。");
            if(Boolean.TRUE.equals(frozen.get("deleted"))){if(operation.equals("album.deleteOriginal")&&new File((String)frozen.get("path")).exists())throw new IOException("原图删除后该路径出现了文件，请重新选择范围，未删除此文件。");return SharedJson.encode(frozen);}
        }else{
            File source=runtime.privateFile(SharedRuntime.text(p,"path",4096));File originals=new File(root,"originals").getCanonicalFile();
            if(!originals.equals(source.getParentFile())||!source.isFile())throw new IOException("只能删除选中的应用相册原图。");
            String sha=runtime.sourceIdentity(source.getPath(),true);String expected=SharedRuntime.text(p,"expectedSourceSha",64);if(!expected.isEmpty()&&!sha.equals(expected))throw new IOException("原图内容已变化，未删除。");
            frozen=SharedRuntime.map("schema",1,"owner",owner,"operation",operation,"path",source.getPath(),"sourceSha",sha,"bytes",source.length(),"deleted",false);
            if(operation.equals("album.deleteVersions")){
                Map<String,Object> versions=SharedJson.object(runtime.request("version.list",SharedJson.encode(SharedRuntime.map("owner",owner,"path",source.getPath())),cancel,v->{}));List<Object> ids=new ArrayList<>();
                Set<String> available=new HashSet<>();for(Object value:(List<?>)versions.get("items"))available.add((String)SharedRuntime.object(value).get("id"));
                Object requested=p.get("versionIds");if(requested!=null){if(!(requested instanceof List)||((List<?>)requested).size()>1000)throw new IOException("成品删除范围无效。");for(Object value:(List<?>)requested){if(!(value instanceof String)||!available.contains(value))throw new IOException("成品版本已变化，请重新选择删除范围。");if(!ids.contains(value))ids.add(value);}}
                else ids.addAll(available);frozen.put("versionIds",ids);frozen.put("removed",new ArrayList<>());
            }else if(!operation.equals("album.deleteOriginal"))throw new IOException("未知的删除范围。");
            write(record,frozen);
        }
        if(operation.equals("album.deleteVersions")){
            List<Object> removed=new ArrayList<>((List<?>)frozen.get("removed"));
            for(Object version:(List<?>)frozen.get("versionIds")){check(cancel);runtime.guardOwner(owner);if(removed.contains(version))continue;runtime.request("version.delete",SharedJson.encode(SharedRuntime.map("owner",owner,"id",version)),cancel,v->{});removed.add(version);frozen.put("removed",removed);write(record,frozen);}
        }else if(operation.equals("album.deleteOriginal")){
            File source=new File((String)frozen.get("path"));checked(root,source);check(cancel);runtime.guardOwner(owner);
            if(source.exists()){
                if(!source.isFile()||source.length()!=((Number)frozen.get("bytes")).longValue()||!PhotoEditStore.hashFile(source).equals(frozen.get("sourceSha")))throw new IOException("原图已变化，未删除。");
                new PhotoLiveProjectStore(new File(root,"photo-live-projects"),source.getParentFile()).removeFile(source,source.length(),(String)frozen.get("sourceSha"));
                check(cancel);runtime.guardOwner(owner);Files.delete(source.toPath());
            }
        }else throw new IOException("未知的删除范围。");
        frozen.put("deleted",true);write(record,frozen);return SharedJson.encode(frozen);
    }
    private static void checked(File root,File file)throws IOException{if(!file.getCanonicalFile().equals(file)||!file.toPath().startsWith(root.toPath()))throw new IOException("删除路径无效。");for(File part=file;part!=null&&!part.equals(root);part=part.getParentFile())if(Files.isSymbolicLink(part.toPath()))throw new IOException("删除路径不能是链接。");}
    private static void write(File file,Map<String,Object> value)throws IOException{File temp=File.createTempFile("deletion-",".part",file.getParentFile());try(FileOutputStream out=new FileOutputStream(temp)){out.write(SharedJson.encode(value).getBytes(StandardCharsets.UTF_8));out.getFD().sync();}try{Files.move(temp.toPath(),file.toPath(),StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING);}finally{Files.deleteIfExists(temp.toPath());}}
    private static void check(BooleanSupplier cancel)throws InterruptedIOException{if(Thread.currentThread().isInterrupted()||cancel.getAsBoolean())throw new InterruptedIOException("删除已停止，已完成的系统操作仍然保留。");}
}
