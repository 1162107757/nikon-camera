package cc.huevia.shared;

import cc.huevia.account.AccountRepository;
import cc.huevia.library.*;
import java.io.*;
import java.util.*;
import java.util.function.*;

/** Original personal-sync state machine, with owner and cancellation checks at request boundaries. */
public final class SharedPersonal {
    private final PersonalPresetSync sync;
    private final AccountRepository accounts;
    private final PersonalPresetSync.Backend api;
    public SharedPersonal(File root,PresetLibrary library,AccountRepository accounts,String installation)throws IOException {
        sync=new PersonalPresetSync(root,library);this.accounts=accounts;api=new PersonalPresetApi(accounts,installation);
    }
    public static String currentOwner(AccountRepository accounts){AccountRepository.Session s=accounts.cachedSession();return s==null||accounts.isLogoutPending()?"":s.user.id;}
    public boolean visible(String id){return sync.visible(currentOwner(accounts),id);}
    public void added(PresetRecord record)throws IOException{String owner=currentOwner(accounts);if(!owner.isEmpty())sync.markAdded(owner,record);}
    public void deleted(String id)throws IOException{String owner=currentOwner(accounts);if(!owner.isEmpty())sync.markDeleted(owner,id);}
    public void restoreMetadata()throws IOException{String owner=currentOwner(accounts);if(!owner.isEmpty())sync.restoreCachedMetadata(owner);}
    private void guard(String owner)throws IOException{if(owner.isEmpty()||!owner.equals(currentOwner(accounts)))throw new IOException("账号已改变，请重新打开个人同步。");}
    private void check(String owner,BooleanSupplier cancel)throws IOException{guard(owner);if(cancel.getAsBoolean())throw new InterruptedIOException("同步已取消，已完成的项目仍会保留。");}
    private static boolean choice(Map<String,Object> p,String key)throws IOException{Object value=p.get(key);if(!(value instanceof Boolean))throw new IOException("请明确选择同步范围或保留的版本。");return (Boolean)value;}
    public Map<String,Object> status(String owner)throws IOException{guard(owner);return SharedRuntime.map("owner",owner,"consentNeeded",sync.consentNeeded(owner),"unclaimed",sync.unclaimed().size(),"conflicts",sync.conflicts(owner));}
    public Map<String,Object> request(String operation,Map<String,Object> p,BooleanSupplier cancel,DoubleConsumer progress)throws IOException {
        String owner=SharedRuntime.text(p,"owner",64);check(owner,cancel);
        switch(operation){
            case "personal.status":return status(owner);
            case "personal.consent":sync.consent(owner,choice(p,"includeExisting"));break;
            case "personal.resolve":sync.resolveConflicts(owner,choice(p,"keepLocal"));break;
            case "personal.sync":
                if(sync.consentNeeded(owner))throw new IOException("请先选择是否将现有本机预设加入当前账号。");
                sync.sync(owner,new PersonalPresetSync.Backend(){
                    public List<Map<String,Object>> list(String id,String after)throws IOException{check(owner,cancel);guard(id);return api.list(id,after);}
                    public byte[] download(String id,String hash)throws IOException{check(owner,cancel);guard(id);return api.download(id,hash);}
                    public long put(String id,String hash,Map<String,Object> metadata,byte[] bytes,long revision)throws IOException{check(owner,cancel);guard(id);return api.put(id,hash,metadata,bytes,revision);}
                    public void delete(String id,String hash,long revision)throws IOException{check(owner,cancel);guard(id);api.delete(id,hash,revision);}
                },(done,total)->progress.accept(total==0?1:Math.max(0,Math.min(1,done/(double)total))));
                check(owner,cancel);break;
            default:throw new IOException("未知的个人同步操作。");
        }
        return status(owner);
    }
}
