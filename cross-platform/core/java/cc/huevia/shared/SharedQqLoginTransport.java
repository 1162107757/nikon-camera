package cc.huevia.shared;

import cc.huevia.account.AccountRepository;
import cc.huevia.library.SharedJson;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.Map;
import java.util.Arrays;

/** Adds native installation rate-limit identity only to QQ session exchange.
 * Original repository and profile-header contracts remain unchanged. */
final class SharedQqLoginTransport implements AccountRepository.Transport {
    private final AccountRepository.Transport delegate;
    private final String installation;
    SharedQqLoginTransport(AccountRepository.Transport delegate,String installation){
        if(delegate==null||installation==null||!installation.matches("(?i)[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}"))throw new IllegalArgumentException("QQ transport installation is invalid");
        this.delegate=delegate;this.installation=installation;
    }
    public AccountRepository.Response request(String method,String path,String bearer,byte[] body)throws IOException{
        if("POST".equals(method)&&"/auth/qq".equals(path)){
            if(body==null)throw new IOException("QQ 授权凭据无效，请重新登录。");
            Map<String,Object> value=SharedJson.object(new String(body,StandardCharsets.UTF_8));
            value.remove("challengeId");value.remove("challengeAnswer");
            value.put("installationId",installation);
            byte[] exchange=SharedJson.encode(value).getBytes(StandardCharsets.UTF_8);
            try{return delegate.request(method,path,bearer,exchange);}
            finally{Arrays.fill(exchange,(byte)0);value.clear();}
        }
        return delegate.request(method,path,bearer,body);
    }
    public AccountRepository.Response profileRequest(String method,String path,String bearer,byte[] body,String installationId,String expectedUpdatedAt)throws IOException{
        return delegate.profileRequest(method,path,bearer,body,installationId,expectedUpdatedAt);
    }
}
