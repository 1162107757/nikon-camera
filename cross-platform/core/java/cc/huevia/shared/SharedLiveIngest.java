package cc.huevia.shared;

import cc.huevia.album.PhotoEditStore;
import cc.huevia.library.SharedJson;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InterruptedIOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.StandardCopyOption;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.function.BooleanSupplier;

/** Durable foreground receive intents. A stopped or superseded lease can never publish a late file. */
final class SharedLiveIngest {
    private static final int MAX_OBJECTS=20000,MAX_BYTES=4*1024*1024;
    interface Project {
        Map<String,Object> preset()throws IOException;
        void validate(Map<String,Object> item,Map<String,Object> receipt)throws IOException;
        String apply(Map<String,Object> item,Map<String,Object> receipt)throws IOException;
    }
    private final File root;
    private final Map<String,Lease> leases=new LinkedHashMap<>();
    private static final class Lease {
        final String key,session,watch,token=UUID.randomUUID().toString();
        Lease(String key,String session,String watch){this.key=key;this.session=session;this.watch=watch;}
    }
    SharedLiveIngest(File root)throws IOException{this.root=root.getCanonicalFile();}

    Map<String,Object> request(String operation,String owner,String projectId,Map<String,Object> p,BooleanSupplier cancel,Project project)throws IOException{
        check(cancel);String camera=hash(p,"cameraId"),key=projectId+":"+camera;
        File file=file(owner,projectId,camera);Map<String,Object> state=read(file,projectId,camera);
        if(operation.equals("project.live.state")){
            Map<String,Object> result=snapshot(state,owner,key);result.put("cameraId",camera);return result;
        }
        if(operation.equals("project.live.start")){
            String mode=text(p,"mode",8),session=identifier(p,"session"),watch=identifier(p,"watchId");
            if(!mode.equals("fresh")&&!mode.equals("resume"))throw new IOException("请选择开始或恢复自动收片。");
            boolean trusted=Boolean.TRUE.equals(p.get("trustedCamera"));
            if(mode.equals("resume")){
                if(state==null||!Boolean.TRUE.equals(state.get("active")))throw new IOException("此拍摄任务已停止，请重新开始拍摄。");
                if(!trusted||!Boolean.TRUE.equals(state.get("trustedCamera")))throw new IOException("相机身份无法确认，请重新开始拍摄。");
                // Discovery normalizes removed entries and first-readable cards
                // while starting. Those changes are not replayed by the next poll.
                state.put("cursor",cursor(p.get("cursor")));
            }else{
                preset(project.preset()); // No default still receives and preserves originals.
                if(state!=null)for(Object row:entries(state).values())if("received".equals(object(row).get("status")))throw new IOException("有已接收原图的未完成记录，请先恢复任务。");
                Map<String,Object> previous=state;state=SharedRuntime.map("schema",1,"projectId",projectId,"cameraId",camera,"trustedCamera",trusted,"active",true,"session",session,"watchId",watch,"cursor",cursor(p.get("cursor")),"entries",new LinkedHashMap<String,Object>());
                if(previous!=null)for(Map.Entry<String,Object> row:entries(previous).entrySet())if("done".equals(object(row.getValue()).get("status")))entries(state).put(row.getKey(),row.getValue());
            }
            state.put("active",true);state.put("session",session);state.put("watchId",watch);
            Lease next=new Lease(key,session,watch);check(cancel);persist(file,state);leases.put(owner,next);
            // An intent was durable before catalog/task writes. Repair those writes
            // in the same order after explicit resume, using the frozen source/preset.
            for(Object raw:entries(state).values()){
                Map<String,Object> item=object(raw);
                if("received".equals(item.get("status"))){check(cancel);finish(file,state,item,project);}
            }
            return snapshot(state,owner,key);
        }
        require(state,owner,key,p);
        if(operation.equals("project.live.stop")){
            state.put("active",false);persist(file,state);leases.remove(owner);return snapshot(state,owner,key);
        }
        if(operation.equals("project.live.observe")){
            // A received intent already owns validated original bytes. Complete
            // its catalog/task boundary before handling a reused camera handle.
            for(Object raw:entries(state).values()){
                Map<String,Object> existing=object(raw);
                if("received".equals(existing.get("status"))){check(cancel);finish(file,state,existing,project);}
            }
            boolean replaced=p.containsKey("cursor");Map<String,Object> currentCursor=replaced?cursor(p.get("cursor")):object(state.get("cursor"));
            if(replaced)state.put("cursor",currentCursor);boolean changed=updateCursor(currentCursor,p)||replaced;
            List<Object> acknowledged=new ArrayList<>();List<?> items=list(p,"items",60);
            Map<String,Object> preset=null;
            for(Object raw:items){
                check(cancel);Map<String,Object> incoming=item(raw);String objectKey=(String)incoming.get("objectKey");Map<String,Object> known=entries(state).containsKey(objectKey)?object(entries(state).get(objectKey)):null;
                if(known!=null){
                    same(incoming,known);
                    if("done".equals(known.get("status")))acknowledged.add(objectKey);
                    else if("error".equals(known.get("status"))){known.put("status","waiting");known.put("error","");changed=true;}
                    continue;
                }
                if(baselineContains(currentCursor,objectKey)){acknowledged.add(objectKey);continue;}
                if(entries(state).size()>=MAX_OBJECTS)throw new IOException("自动收片记录已达到本版上限。");
                for(Object previous:entries(state).values()){
                    Map<String,Object> old=object(previous);
                    if(!"done".equals(old.get("status"))&&number(old,"storage")==number(incoming,"storage")&&number(old,"handle")==number(incoming,"handle")){
                        old.put("status","error");old.put("error","相机原文件已变化，已保留原收片记录。");changed=true;
                    }
                }
                if(pendingCount(state)>=128)throw new IOException("已有 128 张照片等待接收，请先完成或停止当前任务。");
                if(preset==null)preset=project.preset();
                incoming.put("presetId",preset(preset));incoming.put("presetName",text(preset,"presetName",240));incoming.put("status","waiting");incoming.put("error","");incoming.put("taskKey","");
                entries(state).put(objectKey,incoming);changed=true;
            }
            for(Object raw:list(p,"unavailable",128)){
                Map<String,Object> gone=object(raw);String objectKey=hash(gone,"objectKey");Object existing=entries(state).get(objectKey);
                if(existing!=null){Map<String,Object> entry=object(existing);if(!"done".equals(entry.get("status"))&&!"received".equals(entry.get("status"))){entry.put("status","error");entry.put("error","changed".equals(gone.get("reason"))?"相机原文件已变化，请检查后重新开始。":"相机中已找不到这张照片。");changed=true;}}
            }
            if(changed){check(cancel);persist(file,state);}Map<String,Object> result=snapshot(state,owner,key);result.put("acknowledged",acknowledged);return result;
        }
        String objectKey=hash(p,"objectKey");Map<String,Object> entry=object(entries(state).get(objectKey));
        if(operation.equals("project.live.failed")){
            if(!"done".equals(entry.get("status"))&&!"received".equals(entry.get("status"))){entry.put("status","error");entry.put("error",text(p,"error",240));persist(file,state);}
            return snapshot(state,owner,key);
        }
        if(operation.equals("project.live.commit")){
            if(Boolean.TRUE.equals(p.get("raw"))||number(p,"handle")!=number(entry,"handle")||number(p,"storage")!=number(entry,"storage")||!text(p,"name",240).equals(entry.get("name"))||size(p)!=size(entry))throw new IOException("相机收片回执与当前照片不符。");
            String sha=hash(p,"sha256");
            if(entry.containsKey("sha256")&&!sha.equals(entry.get("sha256")))throw new IOException("同一相机照片的原文件校验已变化，未覆盖。");
            project.validate(entry,p);check(cancel);
            if(!"done".equals(entry.get("status"))){
                entry.put("sha256",sha);entry.put("sourceFileName",sha+".jpg");entry.put("status","received");entry.put("error","");persist(file,state);
                finish(file,state,entry,project);
            }
            Map<String,Object> result=snapshot(state,owner,key);result.put("acknowledged",java.util.Collections.singletonList(objectKey));return result;
        }
        throw new IOException("未知的自动收片操作。");
    }
    private void finish(File file,Map<String,Object> state,Map<String,Object> entry,Project project)throws IOException{
        Map<String,Object> receipt=SharedRuntime.map("sourceFileName",text(entry,"sourceFileName",80),"sha256",hash(entry,"sha256"),"bytes",size(entry),"name",entry.get("name"));
        project.validate(entry,receipt);String task=project.apply(entry,receipt);entry.put("taskKey",task);entry.put("status","done");entry.put("error","");persist(file,state);
    }
    private void require(Map<String,Object> state,String owner,String key,Map<String,Object> p)throws IOException{
        Lease lease=leases.get(owner);
        if(state==null||!Boolean.TRUE.equals(state.get("active"))||lease==null||!lease.key.equals(key)||!lease.session.equals(state.get("session"))||!lease.watch.equals(state.get("watchId"))||!lease.token.equals(text(p,"token",36))||!lease.session.equals(text(p,"session",64))||!lease.watch.equals(text(p,"watchId",64)))throw new IOException("自动收片任务已变化，请重新打开拍摄项目。");
    }
    private Map<String,Object> snapshot(Map<String,Object> state,String owner,String key)throws IOException{
        if(state==null)return SharedRuntime.map("exists",false,"active",false,"token","","session","","watchId","","trustedCamera",false,"pending",new ArrayList<>(),"completedCount",0,"failedCount",0,"cursor",SharedRuntime.map("baseline",new ArrayList<>(),"baselinePages",new ArrayList<>(),"baselineCount",0,"initializedStorages",new ArrayList<>(),"pending",new ArrayList<>()));
        Map<String,Object> cursor=cursor(state.get("cursor"));List<Object> pending=new ArrayList<>(),hints=new ArrayList<>();int completed=0,failed=0;
        for(Object raw:entries(state).values()){
            Map<String,Object> item=object(raw);
            if("done".equals(item.get("status"))){completed++;continue;}
            if("error".equals(item.get("status")))failed++;
            pending.add(new LinkedHashMap<>(item));
            if("waiting".equals(item.get("status"))||"received".equals(item.get("status")))hints.add(SharedRuntime.map("storage",item.get("storage"),"handle",item.get("handle"),"objectKey",item.get("objectKey")));
        }
        cursor.put("pending",hints);Lease lease=leases.get(owner);
        return SharedRuntime.map("exists",true,"active",state.get("active"),"token",lease!=null&&lease.key.equals(key)?lease.token:"","session",state.get("session"),"watchId",state.get("watchId"),"cameraId",state.get("cameraId"),"trustedCamera",state.get("trustedCamera"),"cursor",cursor,"pending",pending,"completedCount",completed,"failedCount",failed);
    }
    private static Map<String,Object> item(Object value)throws IOException{
        Map<String,Object> p=object(value);String name=text(p,"name",240);
        if(Boolean.TRUE.equals(p.get("raw"))||!name.toLowerCase(java.util.Locale.ROOT).matches("[^/\\\\\\p{Cntrl}]+\\.jpe?g")||name.contains(".."))throw new IOException("自动收片仅接收独立 JPEG 原文件。");
        Map<String,Object> result=SharedRuntime.map("objectKey",hash(p,"objectKey"),"storage",number(p,"storage"),"handle",number(p,"handle"),"name",name,"bytes",size(p),"raw",false);
        for(String dimension:new String[]{"width","height"}){Object n=p.get(dimension);if(n instanceof Number&&((Number)n).longValue()>=0&&((Number)n).longValue()<=100000)result.put(dimension,((Number)n).longValue());}
        String captured=text(p,"capturedAt",64);result.put("capturedAt",captured);return result;
    }
    private static void same(Map<String,Object> a,Map<String,Object> b)throws IOException{
        if(!a.get("objectKey").equals(b.get("objectKey"))||!a.get("name").equals(b.get("name"))||number(a,"storage")!=number(b,"storage")||number(a,"handle")!=number(b,"handle")||size(a)!=size(b))throw new IOException("相机新片记录已变化，未接收。");
    }
    private static Map<String,Object> cursor(Object raw)throws IOException{
        Map<String,Object> p=object(raw),rows=new LinkedHashMap<>();
        for(Object value:baselineRows(p)){Map<String,Object> row=cursorRow(value);String key=pair(row);if(rows.put(key,row)!=null)throw new IOException("相机基线包含重复照片索引。");}
        Map<String,Object> result=SharedRuntime.map("initializedStorages",storages(p.get("initializedStorages")));putBaseline(result,new ArrayList<>(rows.values()));return result;
    }
    private static List<Object> baselineRows(Map<String,Object> p)throws IOException{
        List<Object> result=new ArrayList<>(list(p,"baseline",MAX_OBJECTS));
        for(Object page:list(p,"baselinePages",20)){
            if(!(page instanceof List)||((List<?>)page).size()>1000)throw new IOException("相机基线分页大小无效。");result.addAll((List<?>)page);
        }
        if(result.size()>MAX_OBJECTS)throw new IOException("相机基线已达到本版上限。");return result;
    }
    private static void putBaseline(Map<String,Object> cursor,List<Object> rows){
        List<Object> first=new ArrayList<>(rows.subList(0,Math.min(1000,rows.size()))),pages=new ArrayList<>();
        for(int i=1000;i<rows.size();i+=1000)pages.add(new ArrayList<>(rows.subList(i,Math.min(i+1000,rows.size()))));
        cursor.put("baseline",first);cursor.put("baselinePages",pages);cursor.put("baselineCount",rows.size());
    }
    private static Map<String,Object> cursorRow(Object raw)throws IOException{
        Map<String,Object> p=object(raw);Map<String,Object> row=SharedRuntime.map("storage",number(p,"storage"),"handle",number(p,"handle"));
        if(p.containsKey("objectKey"))row.put("objectKey",hash(p,"objectKey"));return row;
    }
    private static String pair(Map<String,Object> row){return row.get("storage")+":"+row.get("handle");}
    private static boolean baselineContains(Map<String,Object> cursor,String key)throws IOException{for(Object row:baselineRows(cursor))if(key.equals(object(row).get("objectKey")))return true;return false;}
    private static boolean updateCursor(Map<String,Object> cursor,Map<String,Object> p)throws IOException{
        Map<String,Object> rows=new LinkedHashMap<>();for(Object raw:baselineRows(cursor)){Map<String,Object> row=object(raw);rows.put(pair(row),row);}
        boolean changed=false;
        for(Object raw:list(p,"baselineRemoved",MAX_OBJECTS)){Map<String,Object> row=cursorRow(raw);changed|=rows.remove(pair(row))!=null;}
        for(Object raw:list(p,"baselineUpdates",MAX_OBJECTS)){Map<String,Object> row=cursorRow(raw);Object before=rows.put(pair(row),row);changed|=!row.equals(before);}
        if(rows.size()>MAX_OBJECTS)throw new IOException("相机基线已达到本版上限。");
        if(p.containsKey("initializedStorages")){List<Object> storage=storages(p.get("initializedStorages"));changed|=!storage.equals(cursor.get("initializedStorages"));cursor.put("initializedStorages",storage);}
        putBaseline(cursor,new ArrayList<>(rows.values()));return changed;
    }
    private static List<Object> storages(Object raw)throws IOException{
        if(!(raw instanceof List)||((List<?>)raw).size()>256)throw new IOException("相机存储基线无效。");List<Object> result=new ArrayList<>();
        for(Object value:(List<?>)raw){long n=number(SharedRuntime.map("storage",value),"storage");if(result.contains(n))throw new IOException("相机存储基线重复。");result.add(n);}return result;
    }
    private File file(String owner,String project,String camera)throws IOException{
        if(!UUID.fromString(project).toString().equals(project))throw new IOException("拍摄项目标识无效。");
        String ownerKey=PhotoEditStore.hash(owner.getBytes(StandardCharsets.UTF_8));File directory=new File(root,"shared-live-ingest/"+ownerKey+"/"+project);
        for(File part=directory;part!=null&&!part.equals(root);part=part.getParentFile())if(Files.isSymbolicLink(part.toPath())||!part.equals(part.getCanonicalFile()))throw new IOException("自动收片目录指向其他位置。");
        if(!directory.isDirectory()&&!directory.mkdirs())throw new IOException("无法创建自动收片记录。");
        File result=new File(directory,camera+".json");if(Files.isSymbolicLink(result.toPath())||!result.equals(result.getCanonicalFile())||Files.exists(result.toPath(),LinkOption.NOFOLLOW_LINKS)&&!Files.isRegularFile(result.toPath(),LinkOption.NOFOLLOW_LINKS))throw new IOException("自动收片记录不是私有普通文件。");return result;
    }
    private Map<String,Object> read(File file,String project,String camera)throws IOException{
        if(!file.exists())return null;if(file.length()<32||file.length()>MAX_BYTES)throw new IOException("自动收片记录大小无效。");
        Map<String,Object> encoded=SharedJson.object(new String(Files.readAllBytes(file.toPath()),StandardCharsets.UTF_8));String payload=text(encoded,"payload",MAX_BYTES),sha=hash(encoded,"sha256");
        if(!PhotoEditStore.hash(payload.getBytes(StandardCharsets.UTF_8)).equals(sha))throw new IOException("自动收片记录损坏，未重建或覆盖。");Map<String,Object> state=SharedJson.object(payload);
        Object schema=state.get("schema");
        if(!project.equals(state.get("projectId"))||!camera.equals(state.get("cameraId"))||!(schema instanceof Number)||((Number)schema).doubleValue()!=1||!(state.get("active") instanceof Boolean)||!(state.get("trustedCamera") instanceof Boolean))throw new IOException("自动收片记录身份无效。");
        identifier(state,"session");identifier(state,"watchId");state.put("cursor",cursor(state.get("cursor")));Map<String,Object> all=new LinkedHashMap<>(entries(state));
        for(Object raw:list(state,"entryPages",20)){
            Map<String,Object> page=object(raw);if(page.size()>1000)throw new IOException("自动收片记录分页无效。");
            for(Map.Entry<String,Object> row:page.entrySet())if(all.put(row.getKey(),row.getValue())!=null)throw new IOException("自动收片分页记录重复。");
        }
        state.remove("entryPages");state.put("entries",all);if(all.size()>MAX_OBJECTS||pendingCount(state)>128)throw new IOException("自动收片记录数量无效。");
        for(Map.Entry<String,Object> row:all.entrySet()){
            Map<String,Object> entry=object(row.getValue());item(entry);if(!hash(entry,"objectKey").equals(row.getKey()))throw new IOException("自动收片记录身份不符。");preset(entry);text(entry,"error",240);String status=text(entry,"status",16);
            if(!status.equals("waiting")&&!status.equals("error")&&!status.equals("received")&&!status.equals("done"))throw new IOException("自动收片记录状态无效。");
            if(status.equals("received")||status.equals("done")){if(!(hash(entry,"sha256")+".jpg").equals(text(entry,"sourceFileName",80)))throw new IOException("自动收片原文件记录无效。");}
        }
        return state;
    }
    private void persist(File file,Map<String,Object> state)throws IOException{
        if(!file.equals(file.getCanonicalFile())||!file.getParentFile().equals(file.getParentFile().getCanonicalFile())||!file.toPath().startsWith(root.toPath()))throw new IOException("自动收片目录已变化。");
        Map<String,Object> encodedState=new LinkedHashMap<>(state),first=new LinkedHashMap<>(),page=first;List<Object> pages=new ArrayList<>();int count=0;
        for(Map.Entry<String,Object> row:entries(state).entrySet()){
            if(count>0&&count%1000==0){page=new LinkedHashMap<>();pages.add(page);}page.put(row.getKey(),row.getValue());count++;
        }
        encodedState.put("entries",first);encodedState.put("entryPages",pages);
        String payload=SharedJson.encode(encodedState);byte[] encoded=SharedJson.encode(SharedRuntime.map("payload",payload,"sha256",PhotoEditStore.hash(payload.getBytes(StandardCharsets.UTF_8)))).getBytes(StandardCharsets.UTF_8);
        if(encoded.length>MAX_BYTES)throw new IOException("自动收片记录超过本版上限。");
        File temporary=File.createTempFile("live-",".part",file.getParentFile());
        try{try(FileOutputStream output=new FileOutputStream(temporary)){output.write(encoded);output.getFD().sync();}Files.move(temporary.toPath(),file.toPath(),StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING);}finally{Files.deleteIfExists(temporary.toPath());}
    }
    private static Map<String,Object> entries(Map<String,Object> state)throws IOException{return object(state.get("entries"));}
    private static int pendingCount(Map<String,Object> state)throws IOException{int count=0;for(Object value:entries(state).values())if(!"done".equals(object(value).get("status")))count++;return count;}
    private static Map<String,Object> object(Object value)throws IOException{return SharedRuntime.object(value);}
    private static List<?> list(Map<String,Object> p,String key,int max)throws IOException{Object value=p.get(key);if(value==null)return java.util.Collections.emptyList();if(!(value instanceof List)||((List<?>)value).size()>max)throw new IOException("自动收片列表大小无效。");return (List<?>)value;}
    private static String hash(Map<String,Object> p,String key)throws IOException{String value=text(p,key,64);if(!value.matches("[0-9a-f]{64}"))throw new IOException("自动收片校验标识无效："+key);return value;}
    private static String preset(Map<String,Object> p)throws IOException{
        String id=text(p,"presetId",64),name=text(p,"presetName",240);
        if(id.isEmpty()!=name.isEmpty()||!id.isEmpty()&&!id.matches("[0-9a-f]{64}"))throw new IOException("自动收片预设快照无效。");return id;
    }
    private static String identifier(Map<String,Object> p,String key)throws IOException{String value=text(p,key,64);if(!value.matches("[A-Za-z0-9_-]{1,64}"))throw new IOException("自动收片会话标识无效。");return value;}
    private static String text(Map<String,Object> p,String key,int max)throws IOException{String value=SharedRuntime.text(p,key,max);for(int i=0;i<value.length();i++)if(Character.isISOControl(value.charAt(i)))throw new IOException("自动收片文字包含控制符。");return value;}
    private static long number(Map<String,Object> p,String key)throws IOException{Object value=p.get(key);if(!(value instanceof Number)||((Number)value).doubleValue()!=((Number)value).longValue()||((Number)value).longValue()<1||((Number)value).longValue()>=0xffffffffL)throw new IOException("自动收片照片索引无效。");return ((Number)value).longValue();}
    private static long size(Map<String,Object> p)throws IOException{Object value=p.get("bytes");if(!(value instanceof Number)||((Number)value).doubleValue()!=((Number)value).longValue()||((Number)value).longValue()<4||((Number)value).longValue()>512L*1024*1024)throw new IOException("自动收片照片大小无效。");return ((Number)value).longValue();}
    private static void check(BooleanSupplier cancel)throws IOException{if(cancel.getAsBoolean())throw new InterruptedIOException("自动收片操作已停止。");}
}
