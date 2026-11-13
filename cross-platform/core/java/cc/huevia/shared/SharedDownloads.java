package cc.huevia.shared;

import cc.huevia.album.PhotoEditStore;
import cc.huevia.library.SharedJson;
import cc.huevia.ptp.PtpObjectInfo;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.function.BooleanSupplier;

/** Durable manual download intentions and native byte receipts, isolated by owner. */
public final class SharedDownloads {
    private static final Object LOCK=new Object();
    private SharedDownloads(){}
    public static Object request(SharedRuntime runtime,String operation,Map<String,Object> p,BooleanSupplier cancel)throws IOException {
        String owner=SharedRuntime.text(p,"owner",64);runtime.guardOwner(owner);
        synchronized(LOCK){
            check(cancel);File directory=directory(runtime.root(),owner);
            if(operation.equals("downloads.list")){
                List<Object> summaries=new ArrayList<>(),issues=new ArrayList<>();File[] files=directory.listFiles((d,n)->n.matches("[a-f0-9]{32}\\.json"));
                if(files==null)throw new IOException("下载记录目录不可用。");Arrays.sort(files,Comparator.comparingLong(File::lastModified).reversed());
                for(File file:files){if(summaries.size()>=32)break;try{Map<String,Object> q=read(file,owner);int done=0;for(Object v:rows(q)){String phase=(String)SharedRuntime.object(v).get("phase");if(phase.equals("completed")||phase.equals("skipped"))done++;}
                    summaries.add(SharedRuntime.map("id",q.get("id"),"phase",q.get("phase"),"count",rows(q).size(),"done",done,"cameraId",q.get("cameraId"),"target",q.get("target"),"createdAt",q.get("createdAt")));}
                    catch(IOException corrupt){issues.add(SharedRuntime.map("id",file.getName().substring(0,32),"error","记录损坏或不可读取；保留原文件，未恢复或重传。"));}}
                return SharedRuntime.map("items",summaries,"issues",issues);
            }
            if(operation.equals("downloads.create")){
                String camera=hex(SharedRuntime.text(p,"cameraId",64),64),session=SharedRuntime.text(p,"session",64);
                if(session.isEmpty()||!(p.get("trusted") instanceof Boolean))throw new IOException("请先连接并核对相机。");
                Object input=p.get("items");if(!(input instanceof List)||((List<?>)input).isEmpty()||((List<?>)input).size()>100)throw new IOException("每个下载队列请选择 1–100 张照片。");
                Map<String,Object> target=target(SharedRuntime.object(p.get("target")));
                String id=UUID.randomUUID().toString().replace("-","");List<Object> items=new ArrayList<>();Set<String> seen=new HashSet<>();
                for(Object value:(List<?>)input){Map<String,Object> row=SharedRuntime.object(value);String descriptor=hex(SharedRuntime.text(row,"descriptor",64),64),name=SharedRuntime.text(row,"name",255);
                    long handle=number(row,"handle",1,0xfffffffeL),bytes=number(row,"bytes",4,512L*1024*1024),storage=number(row,"storage",0,0xffffffffL);
                    if(name.isEmpty()||name.matches(".*[/\\\\\\p{Cntrl}].*")||!seen.add(descriptor)||!(row.get("raw") instanceof Boolean))throw new IOException("照片记录重复或无效，请刷新相机目录。");
                    String itemId=hash(id+"\n"+items.size()+"\n"+descriptor).substring(0,32);
                    items.add(SharedRuntime.map("id",itemId,"handle",handle,"storage",storage,"descriptor",descriptor,"name",name,"bytes",bytes,"raw",row.get("raw"),"phase","pending","error",""));
                }
                File[] existing=directory.listFiles((d,n)->n.endsWith(".json"));if(existing==null||existing.length>=64)throw new IOException("下载记录较多，请先移除已完成记录。");
                Map<String,Object> q=SharedRuntime.map("schema",1,"id",id,"owner",owner,"cameraId",camera,"trusted",p.get("trusted"),"session",session,"target",new LinkedHashMap<>(target),"items",items,"phase","paused","createdAt",System.currentTimeMillis());
                write(child(directory,id+".json"),q);return q;
            }
            String id=hex(SharedRuntime.text(p,"id",32),32);File file=child(directory,id+".json");Map<String,Object> q=read(file,owner);
            if(operation.equals("downloads.get"))return q;
            if(operation.equals("downloads.remove")){if(q.get("phase").equals("running"))throw new IOException("请先停止下载。");Files.delete(file.toPath());return SharedRuntime.map("removed",true);}
            if(operation.equals("downloads.bind")){
                if(!Boolean.TRUE.equals(p.get("confirmed")))throw new IOException("请明确核对当前相机后再恢复。");
                q.put("cameraId",hex(SharedRuntime.text(p,"cameraId",64),64));String session=SharedRuntime.text(p,"session",64);if(session.isEmpty()||!(p.get("trusted") instanceof Boolean))throw new IOException("当前相机记录无效。");q.put("session",session);q.put("trusted",p.get("trusted"));
            }else if(operation.equals("downloads.resume")){q.put("phase","running");}
            else if(operation.equals("downloads.pause")){q.put("phase","paused");}
            else if(operation.equals("downloads.finish")){
                for(Object value:rows(q))if(!Arrays.asList("completed","skipped").contains(SharedRuntime.object(value).get("phase")))throw new IOException("队列还有未完成照片。");q.put("phase","done");
            }else{
                Map<String,Object> row=item(q,SharedRuntime.text(p,"itemId",32));String phase=SharedRuntime.text(p,"phase",32);
                if(!operation.equals("downloads.item")||!Arrays.asList("receiving","completed","failed","skipped").contains(phase))throw new IOException("下载队列操作无效。");
                if(row.get("phase").equals("completed")&&!phase.equals("completed"))throw new IOException("已完成记录不可改成待下载。");
                if(phase.equals("completed")){
                    Map<String,Object> receipt=SharedRuntime.object(row.get("receipt"));validateReceipt(runtime.root(),row,receipt,cancel);
                    if(!SharedRuntime.object(q.get("target")).get("kind").equals("app")){
                        Map<String,Object> saved=SharedRuntime.object(p.get("publication"));validatePublication(q,row,receipt,saved);row.put("publication",new LinkedHashMap<>(saved));
                    }
                }
                if(phase.equals("receiving")&&!q.get("phase").equals("running"))throw new IOException("请先明确开始或恢复此下载队列。");
                if(phase.equals("receiving")&&row.containsKey("receipt"))throw new IOException("原文件已经接收，请从校验入库阶段恢复。");
                row.put("phase",phase);row.put("error",SharedRuntime.text(p,"error",500));
            }
            check(cancel);write(file,q);return q;
        }
    }
    public static void validateTransfer(File root,Map<String,Object> p,String cameraId,boolean trusted,String session,PtpObjectInfo info)throws IOException {
        if(!p.containsKey("queueId"))return;
        synchronized(LOCK){String owner=SharedRuntime.text(p,"owner",64);Map<String,Object> q=read(queueFile(root,owner,SharedRuntime.text(p,"queueId",32)),owner);
            if(!q.get("phase").equals("running"))throw new IOException("此下载队列尚未开始或已经停止。");
            if(!q.get("cameraId").equals(cameraId)||!(Boolean.TRUE.equals(q.get("trusted"))&&trusted||q.get("session").equals(session)))throw new IOException("下载队列的相机身份已变化，请明确核对后恢复。");
            Map<String,Object> row=item(q,SharedRuntime.text(p,"itemId",32));String descriptor=PhotoEditStore.hash(info.toBytes());
            if(!row.get("descriptor").equals(descriptor)||((Number)row.get("bytes")).longValue()!=info.compressedSize()||((Number)row.get("storage")).longValue()!=info.storageId()||!Objects.equals(row.get("raw"),SharedCamera.photoFormat(info)==cc.huevia.album.PhotoFormat.NEF)||!row.get("name").equals(info.filename())||!row.get("phase").equals("receiving"))throw new IOException("队列照片已经变化或不在接收阶段。");
        }
    }
    public static void recordTransfer(File root,Map<String,Object> p,Map<String,Object> receipt)throws IOException {
        if(!p.containsKey("queueId"))return;
        synchronized(LOCK){String owner=SharedRuntime.text(p,"owner",64);File file=queueFile(root,owner,SharedRuntime.text(p,"queueId",32));Map<String,Object> q=read(file,owner),row=item(q,SharedRuntime.text(p,"itemId",32));
            validateReceipt(root,row,receipt,()->false);
            if(row.containsKey("receipt")){if(!SharedRuntime.object(row.get("receipt")).get("sha256").equals(receipt.get("sha256")))throw new IOException("已接收原文件摘要不匹配，未替换原记录。");return;}
            if(Arrays.asList("completed","skipped").contains(row.get("phase")))return; // Late native acknowledgements never regress a terminal GUI receipt.
            if(!row.get("phase").equals("receiving"))throw new IOException("原文件不在此队列的接收阶段，未覆盖记录。");
            row.put("receipt",new LinkedHashMap<>(receipt));row.put("phase","received");row.put("error","");write(file,q);
        }
    }
    private static void validateReceipt(File root,Map<String,Object> row,Map<String,Object> value,BooleanSupplier cancel)throws IOException {
        File source=receiptSource(root,row,value);String sha=(String)value.get("sha256");
        if(!source.isFile()||source.length()!=((Number)row.get("bytes")).longValue())throw new IOException("接收原文件的记录无效。");
        check(cancel);if(!sha.equals(PhotoEditStore.hashFile(source)))throw new IOException("接收原文件已变化，未标记完成。");check(cancel);
    }
    private static File receiptSource(File root,Map<String,Object> row,Map<String,Object> value)throws IOException {
        String sha=hex(SharedRuntime.text(value,"sha256",64),64),extension=Boolean.TRUE.equals(row.get("raw"))?".nef":".jpg";
        File base=root.getCanonicalFile(),originals=new File(base,"originals"),source=new File(SharedRuntime.text(value,"path",32768)),expected=new File(originals,sha+extension).getCanonicalFile();
        if(Files.isSymbolicLink(originals.toPath())||!originals.getCanonicalFile().getParentFile().equals(base)||Files.isSymbolicLink(source.toPath())||!source.getCanonicalFile().equals(expected)||number(value,"bytes",4,512L*1024*1024)!=((Number)row.get("bytes")).longValue()||!Objects.equals(row.get("raw"),value.get("raw"))||!row.get("name").equals(SharedRuntime.text(value,"name",255)))throw new IOException("原文件路径、格式或长度与队列不一致。");return source;
    }
    private static Map<String,Object> target(Map<String,Object> value)throws IOException {
        String kind=SharedRuntime.text(value,"kind",16);if(!Arrays.asList("app","system","folder").contains(kind))throw new IOException("请选择有效保存位置。");
        Map<String,Object> result=SharedRuntime.map("kind",kind);if(kind.equals("folder")){result.put("id",hex(SharedRuntime.text(value,"id",32),32));String name=SharedRuntime.text(value,"name",256);if(!name.isEmpty())result.put("name",name);}return result;
    }
    private static void validatePublication(Map<String,Object> q,Map<String,Object> row,Map<String,Object> source,Map<String,Object> saved)throws IOException {
        Map<String,Object> destination=SharedRuntime.object(q.get("target"));String kind=(String)destination.get("kind");
        String uri=SharedRuntime.text(saved,"uri",4096),identifier=SharedRuntime.text(saved,"identifier",4096),address=uri.isEmpty()?identifier:uri;
        if(!Boolean.TRUE.equals(saved.get("published"))||!Boolean.TRUE.equals(saved.get("verified"))||address.isEmpty()||address.matches(".*[\\p{Cntrl}].*")||!q.get("owner").equals(saved.get("owner"))||!row.get("id").equals(saved.get("operationId"))||!source.get("sha256").equals(saved.get("sha256"))||number(saved,"bytes",4,512L*1024*1024)!=((Number)source.get("bytes")).longValue()||!kind.equals(saved.get("targetKind")))throw new IOException("目标位置的原字节收据未通过身份、长度或 SHA 核对。");
        if(kind.equals("folder")&&(!destination.get("id").equals(saved.get("targetId"))||!uri.matches("(?:content|file)://.+")))throw new IOException("文件夹保存收据与已确认目标不一致。");
        if(kind.equals("system")&&!uri.isEmpty()&&!uri.matches("content://media/(external|external_primary)/images/media/[0-9]+"))throw new IOException("系统相册保存地址无效。");
    }
    @SuppressWarnings("unchecked") private static List<Object> rows(Map<String,Object> q)throws IOException{Object value=q.get("items");if(!(value instanceof List)||((List<?>)value).isEmpty()||((List<?>)value).size()>100)throw new IOException("下载记录损坏。");return (List<Object>)value;}
    private static Map<String,Object> item(Map<String,Object> q,String id)throws IOException{hex(id,32);for(Object value:rows(q)){Map<String,Object> row=SharedRuntime.object(value);if(id.equals(row.get("id")))return row;}throw new IOException("照片不属于此下载队列。");}
    private static Map<String,Object> read(File file,String owner)throws IOException{
        if(Files.isSymbolicLink(file.toPath())||!file.isFile()||file.length()>1024*1024)throw new IOException("下载记录不可用。");Map<String,Object> q=SharedJson.object(new String(Files.readAllBytes(file.toPath()),StandardCharsets.UTF_8));
        if(SharedRuntime.integer(q,"schema",0)!=1||!owner.equals(q.get("owner"))||!file.getName().equals(hex(SharedRuntime.text(q,"id",32),32)+".json"))throw new IOException("下载记录账号或标识无效。");
        hex(SharedRuntime.text(q,"cameraId",64),64);if(!(q.get("trusted") instanceof Boolean)||SharedRuntime.text(q,"session",64).isEmpty()||!Arrays.asList("paused","running","done").contains(q.get("phase")))throw new IOException("下载记录的相机或阶段损坏。");number(q,"createdAt",1,Long.MAX_VALUE);target(SharedRuntime.object(q.get("target")));
        Set<String> ids=new HashSet<>(),descriptors=new HashSet<>();boolean terminal=true;File root=file.getParentFile().getParentFile().getParentFile();
        for(Object value:rows(q)){Map<String,Object> row=SharedRuntime.object(value);String id=hex(SharedRuntime.text(row,"id",32),32),descriptor=hex(SharedRuntime.text(row,"descriptor",64),64),name=SharedRuntime.text(row,"name",255),phase=SharedRuntime.text(row,"phase",32);
            if(!ids.add(id)||!descriptors.add(descriptor)||name.isEmpty()||name.matches(".*[/\\\\\\p{Cntrl}].*")||!(row.get("raw") instanceof Boolean)||!Arrays.asList("pending","receiving","received","completed","failed","skipped").contains(phase))throw new IOException("下载照片记录损坏。");
            number(row,"handle",1,0xfffffffeL);number(row,"storage",0,0xffffffffL);number(row,"bytes",4,512L*1024*1024);SharedRuntime.text(row,"error",500);
            Map<String,Object> receipt=null;if(row.containsKey("receipt")){receipt=SharedRuntime.object(row.get("receipt"));receiptSource(root,row,receipt);if(phase.equals("pending")||phase.equals("receiving"))throw new IOException("下载阶段与原文件收据不一致。");}
            if((phase.equals("received")||phase.equals("completed"))&&receipt==null)throw new IOException("下载阶段缺少原文件收据。");
            if(phase.equals("completed")&&!SharedRuntime.object(q.get("target")).get("kind").equals("app"))validatePublication(q,row,receipt,SharedRuntime.object(row.get("publication")));
            if(!phase.equals("completed")&&!phase.equals("skipped"))terminal=false;
        }
        if(q.get("phase").equals("done")&&!terminal)throw new IOException("队列完成阶段与照片记录不一致。");return q;
    }
    private static File queueFile(File root,String owner,String id)throws IOException{return child(directory(root,owner),hex(id,32)+".json");}
    private static File directory(File root,String owner)throws IOException{
        if(!owner.isEmpty()&&!owner.matches("(?i)[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}"))throw new IOException("下载记录账号无效。");
        File top=child(root.getCanonicalFile(),"camera-downloads");if(!top.isDirectory()&&!top.mkdir())throw new IOException("下载目录不可用。");File directory=child(top,hash(owner));if(!directory.isDirectory()&&!directory.mkdir())throw new IOException("下载账号目录不可用。");return directory;
    }
    private static File child(File parent,String name)throws IOException{File file=new File(parent,name);if(Files.isSymbolicLink(file.toPath())||!file.getCanonicalFile().getParentFile().equals(parent.getCanonicalFile()))throw new IOException("下载记录路径无效。");return file;}
    private static void write(File file,Map<String,Object> q)throws IOException{byte[] data=SharedJson.encode(q).getBytes(StandardCharsets.UTF_8);if(data.length>1024*1024)throw new IOException("下载记录过大。");File pending=File.createTempFile("queue-",".part",file.getParentFile());try{try(FileOutputStream out=new FileOutputStream(pending)){out.write(data);out.getFD().sync();}Files.move(pending.toPath(),file.toPath(),StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING);}finally{Files.deleteIfExists(pending.toPath());}}
    private static long number(Map<String,Object> p,String key,long min,long max)throws IOException{Object v=p.get(key);if(!(v instanceof Number)||((Number)v).doubleValue()!=((Number)v).longValue()||((Number)v).longValue()<min||((Number)v).longValue()>max)throw new IOException("照片记录数值无效。");return ((Number)v).longValue();}
    private static String hex(String value,int n)throws IOException{if(!value.matches("[a-f0-9]{"+n+"}"))throw new IOException("下载记录摘要或标识无效。");return value;}
    private static String hash(String text){return PhotoEditStore.hash(text.getBytes(StandardCharsets.UTF_8));}
    private static void check(BooleanSupplier cancel)throws InterruptedIOException{if(Thread.currentThread().isInterrupted()||cancel!=null&&cancel.getAsBoolean())throw new InterruptedIOException("下载队列操作已停止。");}
}
