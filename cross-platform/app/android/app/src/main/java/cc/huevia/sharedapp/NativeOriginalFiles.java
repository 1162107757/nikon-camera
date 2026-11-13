package cc.huevia.sharedapp;

import android.app.Activity;
import android.content.*;
import android.database.Cursor;
import android.net.Uri;
import android.os.ParcelFileDescriptor;
import android.provider.DocumentsContract;
import android.util.AtomicFile;
import cc.huevia.album.PhotoEditStore;
import cc.huevia.library.SharedJson;
import cc.huevia.shared.SharedRuntime;
import io.flutter.plugin.common.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.function.BooleanSupplier;

/** Persistent SAF folder grants and byte-exact, idempotent original publication. */
final class NativeOriginalFiles implements MethodChannel.MethodCallHandler {
    static final int PICK_FOLDER=0x6f30;
    private final Activity activity;
    private final SharedRuntime runtime;
    private final ExecutorService worker=Executors.newSingleThreadExecutor();
    private final Set<String> cancelled=ConcurrentHashMap.newKeySet();
    private MethodChannel.Result picker;
    private String pickerOwner;
    NativeOriginalFiles(Activity activity,SharedRuntime runtime){this.activity=activity;this.runtime=runtime;}
    @Override public void onMethodCall(MethodCall call,MethodChannel.Result result){
        try{
            if(call.method.equals("chooseTarget")){
                if(picker!=null)throw new IOException("请先完成当前文件夹选择。");
                String owner=call.argument("owner");if(owner==null)owner="";
                picker=result;pickerOwner=owner;
                final String selectedOwner=owner;
                worker.execute(()->{try{runtime.guardOwner(selectedOwner);activity.runOnUiThread(()->{if(picker!=result)return;try{Intent intent=new Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION|Intent.FLAG_GRANT_WRITE_URI_PERMISSION|Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION|Intent.FLAG_GRANT_PREFIX_URI_PERMISSION);activity.startActivityForResult(intent,PICK_FOLDER);}catch(RuntimeException failure){picker=null;pickerOwner=null;result.error("FILES_TARGET",failure.getMessage(),null);}});}catch(Exception failure){activity.runOnUiThread(()->{if(picker==result){picker=null;pickerOwner=null;result.error("FILES_TARGET",failure.getMessage(),null);}});}});
                return;
            }
            if(call.method.equals("cancel")){String operation=call.argument("operationId");if(operation!=null)cancelled.add(operation);result.success(null);return;}
            if(!call.method.equals("publishOriginal")){result.notImplemented();return;}
            String json=SharedJson.encode(call.arguments);Map<String,Object> p=SharedJson.object(json);String operation=SharedRuntime.text(p,"operationId",32);cancelled.remove(operation);
            worker.execute(()->{try{String value=publish(json,()->cancelled.contains(operation));activity.runOnUiThread(()->result.success(value));}catch(Exception failure){activity.runOnUiThread(()->result.error("FILES_PUBLICATION",failure.getMessage(),null));}finally{cancelled.remove(operation);}});
        }catch(Exception failure){result.error("FILES_PUBLICATION",failure.getMessage(),null);}
    }
    boolean onActivityResult(int request,int code,Intent data){
        if(request!=PICK_FOLDER)return false;MethodChannel.Result reply=picker;String owner=pickerOwner;picker=null;pickerOwner=null;if(reply==null)return true;
        if(code!=Activity.RESULT_OK||data==null||data.getData()==null){reply.success(null);return true;}
        worker.execute(()->{try{
            runtime.guardOwner(owner);Uri tree=data.getData();if(!DocumentsContract.isTreeUri(tree)||!"content".equals(tree.getScheme()))throw new IOException("请选择系统文件提供者的文件夹。");
            int grants=data.getFlags()&(Intent.FLAG_GRANT_READ_URI_PERMISSION|Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
            if(grants!=(Intent.FLAG_GRANT_READ_URI_PERMISSION|Intent.FLAG_GRANT_WRITE_URI_PERMISSION))throw new IOException("此文件夹未授予完整读写权限，请重新选择。");
            activity.getContentResolver().takePersistableUriPermission(tree,grants);
            String id=UUID.randomUUID().toString().replace("-","");String name=folderName(tree);
            write(record(owner,"file-targets",id),SharedRuntime.map("schema",1,"owner",owner,"id",id,"name",name,"tree",tree.toString()));
            String value=SharedJson.encode(SharedRuntime.map("id",id,"name",name));activity.runOnUiThread(()->reply.success(value));
        }catch(Exception failure){activity.runOnUiThread(()->reply.error("FILES_TARGET",failure.getMessage(),null));}});return true;
    }
    /** Also callable on the host's existing serial request worker for files.publishOriginal. */
    synchronized String publish(String json,BooleanSupplier cancel)throws IOException {
        Map<String,Object> p=SharedJson.object(json);String owner=SharedRuntime.text(p,"owner",64),operation=SharedRuntime.text(p,"operationId",32),target=SharedRuntime.text(p,"targetId",32);
        if(!operation.matches("[0-9a-f]{32}")||!target.matches("[0-9a-f]{32}"))throw new IOException("文件保存任务或目标标识无效。");runtime.guardOwner(owner);check(cancel);
        Map<String,Object> selected=read(record(owner,"file-targets",target));if(selected==null||!owner.equals(selected.get("owner"))||!target.equals(selected.get("id")))throw new IOException("文件夹授权记录不可用，请重新选择目标。");
        Uri tree=Uri.parse((String)selected.get("tree"));boolean permission=false;
        for(UriPermission grant:activity.getContentResolver().getPersistedUriPermissions())if(grant.getUri().equals(tree)&&grant.isReadPermission()&&grant.isWritePermission())permission=true;
        if(!permission)throw new IOException("文件夹访问权限已失效，请重新选择文件夹；未重复保存。");
        Map<String,Object> source=SharedJson.object(runtime.prepareOriginalPublication(json,cancel));String sha=(String)source.get("sha256"),format=(String)source.get("format");long bytes=((Number)source.get("bytes")).longValue();File file=new File((String)source.get("path"));
        AtomicFile journal=record(owner,"file-publications",operation);Map<String,Object> receipt=read(journal);boolean existing=receipt!=null;
        String name=safeName(SharedRuntime.text(p,"filename",256),operation,format);
        if(receipt==null){receipt=SharedRuntime.map("schema",1,"owner",owner,"targetId",target,"operationId",operation,"sha256",sha,"bytes",bytes,"name",name,"state","preparing","uri","");write(journal,receipt);}
        if(!owner.equals(receipt.get("owner"))||!target.equals(receipt.get("targetId"))||!sha.equals(receipt.get("sha256"))||number(receipt,"bytes")!=bytes||!name.equals(receipt.get("name")))throw new IOException("文件保存任务已绑定其他内容或目标，未覆盖或重复保存。");
        Uri document=null;String address=(String)receipt.get("uri");
        if(address!=null&&!address.isEmpty()){
            document=Uri.parse(address);if(!DocumentsContract.isChildDocument(activity.getContentResolver(),treeDocument(tree),document))throw new IOException("上次保存的文件不在授权文件夹，未继续写入。");
            if("complete".equals(receipt.get("state"))){verify(document,sha,bytes,cancel);return finish(owner,operation,target,document,sha,bytes,existing);}
            if(!prefixMatches(document,file,bytes,cancel))throw new IOException("未完成文件已被修改，未覆盖；请先在 Files 中核对。");
        }else{
            List<Uri> found=find(tree,name);if(found.size()>1)throw new IOException("目标文件夹存在多份本任务文件，未重复保存。");
            if(found.size()==1){document=found.get(0);verify(document,sha,bytes,cancel);receipt.put("uri",document.toString());receipt.put("state","complete");write(journal,receipt);return finish(owner,operation,target,document,sha,bytes,true);}
            check(cancel);document=DocumentsContract.createDocument(activity.getContentResolver(),treeDocument(tree),format.equals("NEF")?"image/x-nikon-nef":"image/jpeg",name);
            if(document==null)throw new IOException("无法在所选文件夹创建原文件。");receipt.put("uri",document.toString());receipt.put("state","pending");write(journal,receipt);
        }
        runtime.guardOwner(owner);check(cancel);ParcelFileDescriptor descriptor=activity.getContentResolver().openFileDescriptor(document,"rwt");if(descriptor==null)throw new IOException("无法写入所选文件夹。");
        try(InputStream in=new FileInputStream(file);ParcelFileDescriptor.AutoCloseOutputStream out=new ParcelFileDescriptor.AutoCloseOutputStream(descriptor)){
            byte[] buffer=new byte[65536];long total=0;int count;while((count=in.read(buffer))!=-1){check(cancel);total+=count;if(total>bytes)throw new IOException("原文件快照已变化。");out.write(buffer,0,count);}if(total!=bytes)throw new IOException("原文件快照不完整。");out.flush();out.getFD().sync();
        }
        verify(document,sha,bytes,cancel);runtime.guardOwner(owner);receipt.put("state","complete");write(journal,receipt);return finish(owner,operation,target,document,sha,bytes,existing);
    }
    private String finish(String owner,String operation,String target,Uri uri,String sha,long bytes,boolean existing)throws IOException {
        runtime.releaseOriginalPublication(SharedJson.encode(SharedRuntime.map("owner",owner,"operationId",operation,"sha256",sha,"bytes",bytes)));
        return SharedJson.encode(SharedRuntime.map("published",true,"owner",owner,"operationId",operation,"targetKind","folder","uri",uri.toString(),"targetId",target,"sha256",sha,"bytes",bytes,"verified",true,"existing",existing));
    }
    private Uri treeDocument(Uri tree){return DocumentsContract.buildDocumentUriUsingTree(tree,DocumentsContract.getTreeDocumentId(tree));}
    private String folderName(Uri tree){try(Cursor row=activity.getContentResolver().query(treeDocument(tree),new String[]{DocumentsContract.Document.COLUMN_DISPLAY_NAME},null,null,null)){if(row!=null&&row.moveToFirst())return row.getString(0);}catch(RuntimeException ignored){}return "已授权的文件夹";}
    private List<Uri> find(Uri tree,String name)throws IOException {
        List<Uri> found=new ArrayList<>();Uri children=DocumentsContract.buildChildDocumentsUriUsingTree(tree,DocumentsContract.getTreeDocumentId(tree));
        try(Cursor rows=activity.getContentResolver().query(children,new String[]{DocumentsContract.Document.COLUMN_DOCUMENT_ID,DocumentsContract.Document.COLUMN_DISPLAY_NAME},null,null,null)){
            if(rows==null)throw new IOException("无法读取目标文件夹，请检查授权。");int scanned=0;while(rows.moveToNext()){if(++scanned>20000)throw new IOException("目标文件夹过大，请选择独立的照片文件夹。");if(name.equals(rows.getString(1)))found.add(DocumentsContract.buildDocumentUriUsingTree(tree,rows.getString(0)));}
        }return found;
    }
    private boolean prefixMatches(Uri uri,File source,long bytes,BooleanSupplier cancel)throws IOException {
        try(InputStream current=activity.getContentResolver().openInputStream(uri);InputStream original=new FileInputStream(source)){
            if(current==null)throw new IOException("未完成文件暂不可读。");byte[] a=new byte[65536],b=new byte[65536];long total=0;int count;
            while((count=current.read(a))!=-1){check(cancel);total+=count;if(total>bytes)return false;int at=0;while(at<count){int n=original.read(b,at,count-at);if(n<1)return false;at+=n;}for(int i=0;i<count;i++)if(a[i]!=b[i])return false;}return true;
        }
    }
    private void verify(Uri uri,String sha,long bytes,BooleanSupplier cancel)throws IOException {
        MessageDigest hash;try{hash=MessageDigest.getInstance("SHA-256");}catch(NoSuchAlgorithmException impossible){throw new AssertionError(impossible);}long total=0;
        try(InputStream in=activity.getContentResolver().openInputStream(uri)){if(in==null)throw new IOException("保存后的文件暂不可读，请稍后核对。");byte[] buffer=new byte[65536];int count;while((count=in.read(buffer))!=-1){check(cancel);total+=count;if(total>bytes)throw new IOException("目标文件内容已变化，未覆盖。");hash.update(buffer,0,count);}}
        StringBuilder actual=new StringBuilder();for(byte value:hash.digest())actual.append(String.format(Locale.ROOT,"%02x",value&255));if(total!=bytes||!sha.contentEquals(actual))throw new IOException("文件长度或 SHA-256 未通过读回核对；未自动重复保存。");
    }
    private AtomicFile record(String owner,String kind,String id)throws IOException {
        if(id==null||!id.matches("[0-9a-f]{32}"))throw new IOException("文件记录标识无效。");File base=directory(runtime.root(),kind),folder=directory(base,PhotoEditStore.hash(owner.getBytes(StandardCharsets.UTF_8))),path=new File(folder,id+".json");
        if(Files.isSymbolicLink(path.toPath())||Files.isSymbolicLink(new File(path+".bak").toPath()))throw new IOException("文件记录不能是链接。");return new AtomicFile(path);
    }
    private static File directory(File parent,String name)throws IOException{File path=new File(parent,name);if(Files.isSymbolicLink(path.toPath())||!parent.getCanonicalFile().equals(path.getCanonicalFile().getParentFile())||!path.isDirectory()&&!path.mkdir())throw new IOException("无法创建文件发布记录。");return path.getCanonicalFile();}
    private static Map<String,Object> read(AtomicFile file)throws IOException{if(!file.getBaseFile().exists())return null;if(file.getBaseFile().length()>16384)throw new IOException("文件保存记录过大。");try(InputStream in=file.openRead();ByteArrayOutputStream out=new ByteArrayOutputStream()){byte[] buffer=new byte[4096];int count;while((count=in.read(buffer))!=-1){if(out.size()+count>16384)throw new IOException("文件保存记录过大。");out.write(buffer,0,count);}Map<String,Object> value=SharedJson.object(new String(out.toByteArray(),StandardCharsets.UTF_8));if(number(value,"schema")!=1)throw new IOException("文件保存记录版本无效。");return value;}}
    private static void write(AtomicFile file,Map<String,Object> value)throws IOException{FileOutputStream out=null;try{out=file.startWrite();out.write(SharedJson.encode(value).getBytes(StandardCharsets.UTF_8));out.getFD().sync();file.finishWrite(out);out=null;}finally{if(out!=null)file.failWrite(out);}}
    private static long number(Map<String,Object> p,String key)throws IOException{Object value=p.get(key);if(!(value instanceof Number))throw new IOException("文件保存记录无效。");return ((Number)value).longValue();}
    private static String safeName(String value,String operation,String format){String name=value.replaceAll("[\\p{Cntrl}\\\\/]","_").trim();int dot=name.lastIndexOf('.');if(dot>0)name=name.substring(0,dot);while(name.length()>90)name=name.substring(0,name.offsetByCodePoints(name.length(),-1));if(name.isEmpty())name="original";return name+"__Huevia_"+operation+(format.equals("NEF")?".NEF":".jpg");}
    private static void check(BooleanSupplier cancel)throws IOException{if(Thread.currentThread().isInterrupted()||cancel.getAsBoolean())throw new InterruptedIOException("原文件保存已停止；已创建的未完成文件保留以供核对。");}
    void dispose(){if(picker!=null){picker.error("CANCELLED","文件夹选择已取消。",null);picker=null;}worker.shutdownNow();}
}
