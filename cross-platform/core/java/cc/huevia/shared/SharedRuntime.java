package cc.huevia.shared;

import cc.huevia.account.*;
import cc.huevia.community.*;
import cc.huevia.library.*;
import java.io.*;
import java.nio.file.*;
import java.util.*;

/** Serial worker entry point shared by Android and the translated Apple implementation. */
public final class SharedRuntime {
    private final File root;
    private final PresetLibrary library;
    private final OnlinePresetRepository online;
    private final AccountRepository accounts;
    private final CommunityRepository community;
    public SharedRuntime(String directory, AccountRepository.Store store, AccountRepository.Transport transport)throws IOException {
        root=new File(directory).getCanonicalFile();
        if(!root.isDirectory()&&!root.mkdirs())throw new IOException("无法打开应用资料目录。");
        library=new PresetLibrary(root);
        online=new OnlinePresetRepository(root,library);
        online.initializeDefaultEndpoint(OnlinePresetRepository.MANAGED_CATALOG_URL);
        accounts=new AccountRepository(store,transport);
        community=new CommunityRepository(accounts);
        accounts.restore();
    }
    public File root(){return root;}
    public byte[] preset(String id)throws IOException{return id==null||id.isEmpty()?new byte[0]:library.readPreset(id);}
    public synchronized String request(String operation,String json)throws IOException {
        Map<String,Object> p=SharedJson.object(json);Object result;
        switch(operation){
            case "core.schema":return CoreEngine.schema();
            case "library.list":{
                library.refresh();List<Object> rows=new ArrayList<>();for(PresetRecord r:library.list())rows.add(r.toMap());
                result=map("items",rows,"diagnostics",library.diagnostics());break;
            }
            case "library.import":{
                File file=privateFile(text(p,"path",4096));long length=file.length();
                if(length<1||length>1024*1024)throw new IOException("预设文件大小无效。");
                PresetLibrary.AddResult added=library.importFile(text(p,"name",240),Files.readAllBytes(file.toPath()));
                result=map("record",added.record.toMap(),"added",added.added);break;
            }
            case "library.remove":{
                PresetLibrary.RemoveResult removed=library.remove(text(p,"id",64));result=map("warnings",removed.cleanupWarnings);break;
            }
            case "library.category":result=library.setCategory(text(p,"id",64),text(p,"category",100)).toMap();break;
            case "library.export":{
                String id=text(p,"id",64);byte[] bytes=library.readPreset(id);PresetRecord record=library.findBySha256(id);
                File dir=new File(root,"shared-exports");if(!dir.isDirectory()&&!dir.mkdirs())throw new IOException("无法创建分享文件。");
                String name=record.originalFileName.replaceAll("[^\\p{L}\\p{N}._-]","_");
                if(name.isEmpty())name=id+"."+record.fileFormat.toLowerCase(Locale.ROOT);
                File output=new File(dir,id+"-"+name);Files.write(output.toPath(),bytes);
                result=map("path",output.getPath(),"name",name);break;
            }
            case "library.inspect":result=SharedJson.object(CoreEngine.inspectPreset(preset(text(p,"id",64))));break;
            case "online.page":{
                OnlinePresetRepository.PageResult page=online.fetchPage(integer(p,"page",1),integer(p,"pageSize",24),text(p,"category",100),text(p,"fileFormat",8));
                List<Object> rows=new ArrayList<>();for(OnlinePreset r:page.presets)rows.add(onlineMap(r));
                result=map("items",rows,"total",page.total,"hasMore",page.hasMore,"page",page.page,"categories",page.categories);break;
            }
            case "online.download":{
                PresetLibrary.AddResult added=online.download(OnlinePreset.fromMap(object(p.get("preset"))),null);
                result=map("record",added.record.toMap(),"added",added.added);break;
            }
            case "account.current":result=session(accounts.cachedSession());break;
            case "account.challenge":result=accounts.challenge(text(p,"installationId",128));break;
            case "account.login":result=session(accounts.login(text(p,"username",32),text(p,"password",256)));break;
            case "account.register":result=session(accounts.register(text(p,"username",32),text(p,"password",256),text(p,"challengeId",128),text(p,"challengeAnswer",128),text(p,"installationId",128)));break;
            case "account.qq":result=session(accounts.loginWithQq(text(p,"accessToken",4096),text(p,"challengeId",128),text(p,"challengeAnswer",128),text(p,"installationId",128)));break;
            case "account.refresh":result=session(accounts.refresh());break;
            case "account.logout":accounts.logout();result=map("loggedOut",true);break;
            case "community.get":result=community.get(text(p,"path",2048),Boolean.TRUE.equals(p.get("login")));break;
            case "community.write":result=community.writeForOwner(text(p,"method",6),text(p,"path",2048),object(p.get("body")),text(p,"ownerId",64));break;
            default:throw new IOException("未知的应用操作："+operation);
        }
        return SharedJson.encode(result);
    }
    public File privateFile(String path)throws IOException {
        File original=new File(path),file=original.getCanonicalFile();
        if(!file.toPath().startsWith(root.toPath())||Files.isSymbolicLink(original.toPath())||!file.isFile())throw new IOException("文件不在应用资料目录内。");
        return file;
    }
    public static Map<String,Object> map(Object... values){Map<String,Object> m=new LinkedHashMap<>();for(int i=0;i<values.length;i+=2)m.put((String)values[i],values[i+1]);return m;}
    @SuppressWarnings("unchecked") public static Map<String,Object> object(Object value)throws IOException{if(!(value instanceof Map))throw new IOException("操作数据格式无效。");return (Map<String,Object>)value;}
    public static String text(Map<String,Object> m,String key,int max)throws IOException{Object v=m.get(key);if(v==null)return "";if(!(v instanceof String)||((String)v).length()>max)throw new IOException("操作文字超出范围："+key);return (String)v;}
    public static int integer(Map<String,Object> m,String key,int fallback)throws IOException{Object v=m.get(key);if(v==null)return fallback;if(!(v instanceof Number)||((Number)v).doubleValue()!=((Number)v).intValue())throw new IOException("操作数字无效："+key);return ((Number)v).intValue();}
    private static Object session(AccountRepository.Session session){
        if(session==null)return null;AccountRepository.User u=session.user;
        return map("user",map("id",u.id,"username",u.username,"nickname",u.nickname,"avatarUrl",u.avatarUrl,"avatarSource",u.avatarSource,"provider",u.provider,"updatedAt",u.updatedAt),"expiresAt",session.expiresAt,"verified",session.verified);
    }
    private static Object onlineMap(OnlinePreset r){return map("id",r.id,"name",r.name,"description",r.description,"fileUrl",r.fileUrl,"sha256",r.sha256,"byteLength",r.byteLength,"previewUrl",r.previewUrl,"compatibleModels",r.compatibleModels,"category",r.category,"authorName",r.authorName,"source",r.source,"fileFormat",r.fileFormat);}
}
