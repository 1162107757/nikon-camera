package cc.huevia.legacyexport;

import cc.huevia.library.SharedJson;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.security.KeyStore;
import java.util.*;
import javax.crypto.Cipher;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

/** Read only: the normal store's repair path may delete the KeyStore alias, so it is not used here. */
final class LegacyAccountProfile {
    static Map<String,Object> read(File noBackup)throws IOException{
        File directory=new File(noBackup,"account"),base=new File(directory,"session.enc"),backup=new File(directory,"session.enc.bak");
        // AtomicFile treats a present backup as authoritative. Read it without renaming either file.
        File selected=backup.exists()?backup:base;if(!selected.exists())return new LinkedHashMap<>();
        byte[] envelope=null,plain=null;
        try{
            if(Files.isSymbolicLink(selected.toPath())||!selected.getCanonicalFile().getParentFile().equals(directory.getCanonicalFile())||selected.length()<30||selected.length()>96*1024)throw new IOException();
            envelope=Files.readAllBytes(selected.toPath());if(envelope[0]!=1||envelope[1]!=12)throw new IOException();
            KeyStore keys=KeyStore.getInstance("AndroidKeyStore");keys.load(null);
            java.security.Key stored=keys.getKey("cc.huevia.account.session.v1",null);if(!(stored instanceof SecretKey))throw new IOException();
            Cipher cipher=Cipher.getInstance("AES/GCM/NoPadding");cipher.init(Cipher.DECRYPT_MODE,stored,new GCMParameterSpec(128,envelope,2,12));cipher.updateAAD("nikon-account-v1".getBytes(StandardCharsets.US_ASCII));
            plain=cipher.doFinal(envelope,14,envelope.length-14);if(plain.length>64*1024)throw new IOException();
            Map<String,Object> document=SharedJson.object(new String(plain,StandardCharsets.UTF_8));Object user=document.get("user");if(!(user instanceof Map))throw new IOException();
            Map<?,?> identity=(Map<?,?>)user;Object id=identity.get("id");if(!(id instanceof String)||!((String)id).matches("[a-fA-F0-9]{8}(?:-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}"))throw new IOException();
            Map<String,Object> result=new LinkedHashMap<>();for(String key:List.of("id","provider","username","nickname")){Object value=identity.get(key);if(value instanceof String&&((String)value).length()<=240)result.put(key,value);}return result;
        }catch(Exception failure){throw new IOException("旧账号资料无法只读核对。为保护原会话与账号专属草稿，未继续导出；原账号文件和密钥未更改。");}
        finally{if(envelope!=null)Arrays.fill(envelope,(byte)0);if(plain!=null)Arrays.fill(plain,(byte)0);}
    }
}
