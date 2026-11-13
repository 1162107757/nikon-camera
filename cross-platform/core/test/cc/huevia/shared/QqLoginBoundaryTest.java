package cc.huevia.shared;

import cc.huevia.account.*;
import cc.huevia.library.SharedJson;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;

final class QqLoginBoundaryTest {
    private static int checks;
    private static final String OWNER="aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",OTHER="dddddddd-dddd-4ddd-8ddd-dddddddddddd",INSTALL="bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
    private static final String PROVIDER="synthetic-provider-token-for-qq-test";
    private static void yes(boolean value){checks++;if(!value)throw new AssertionError("QQ login boundary "+checks);}
    private static final class Store implements AccountRepository.Store {
        byte[] bytes;public byte[] read(){return bytes==null?null:bytes.clone();}public void write(byte[] value){bytes=value.clone();}public void clear(){bytes=null;}
    }
    private static final class Server implements AccountRepository.Transport {
        int logins;boolean reject;Map<String,Object> last;
        public AccountRepository.Response request(String method,String path,String bearer,byte[] body)throws IOException{
            if(!method.equals("POST")||!path.equals("/auth/qq"))throw new AssertionError("QQ made an unrelated account request");
            logins++;last=SharedJson.object(new String(body,StandardCharsets.UTF_8));
            if(reject)return response(401,SharedRuntime.map("error",SharedRuntime.map("code","qq_verification_failed","message","rejected")));
            return response(200,SharedRuntime.map("tokenType","Bearer","accessToken","a".repeat(43),"expiresAt","2099-01-01T00:00:00Z","user",
                SharedRuntime.map("id",OWNER,"username","","nickname","QQ 合成用户","avatarUrl","","avatarSource","default","provider","qq","status","active","createdAt","2026-01-01T00:00:00Z","lastLoginAt","2026-01-01T00:00:00Z","updatedAt","2026-01-01T00:00:00Z","loginCount",logins)));
        }
    }
    private static AccountRepository.Response response(int status,Map<String,Object> body){return new AccountRepository.Response(status,SharedJson.encode(body).getBytes(StandardCharsets.UTF_8));}
    static int run(Path temporary)throws Exception {
        checks=0;Store store=new Store();Server server=new Server();
        SharedRuntime runtime=new SharedRuntime(Files.createDirectory(temporary.resolve("qq-login")).toString(),store,server,INSTALL);
        Map<String,Object> session=SharedJson.object(runtime.request("account.qq",SharedJson.encode(SharedRuntime.map("owner","","accessToken",PROVIDER))));
        yes(server.logins==1);yes(server.last.keySet().equals(new HashSet<>(Arrays.asList("accessToken","installationId"))));
        yes(PROVIDER.equals(server.last.get("accessToken")));yes(INSTALL.equals(server.last.get("installationId")));
        yes(Boolean.TRUE.equals(session.get("verified")));yes(OWNER.equals(((Map<?,?>)session.get("user")).get("id")));
        yes(!session.containsKey("accessToken"));yes(store.bytes!=null&&!new String(store.bytes,StandardCharsets.UTF_8).contains(PROVIDER));
        runtime.request("account.qq",SharedJson.encode(SharedRuntime.map("owner",OWNER,"accessToken",PROVIDER,"challengeId","ignored","challengeAnswer","ignored","installationId",OTHER)));
        yes(server.logins==2);yes(server.last.size()==2);yes(INSTALL.equals(server.last.get("installationId")));
        try{runtime.request("account.qq",SharedJson.encode(SharedRuntime.map("owner",OTHER,"accessToken",PROVIDER)));throw new AssertionError("Wrong owner accepted");}catch(IOException expected){yes(server.logins==2);}
        try{runtime.request("account.qq",SharedJson.encode(SharedRuntime.map("owner",OWNER,"accessToken","short")));throw new AssertionError("Invalid provider token accepted");}catch(AccountException expected){yes(expected.code.equals("qq_invalid_token"));yes(server.logins==2);}

        Store empty=new Store();Server denied=new Server();denied.reject=true;
        SharedRuntime rejected=new SharedRuntime(Files.createDirectory(temporary.resolve("qq-rejected")).toString(),empty,denied,INSTALL);
        try{rejected.request("account.qq",SharedJson.encode(SharedRuntime.map("owner","","accessToken",PROVIDER)));throw new AssertionError("Unverified OAuth minted a session");}
        catch(AccountException expected){yes(expected.code.equals("qq_verification_failed"));yes(expected.status==401);}
        yes(empty.bytes==null);yes(!SharedJson.object(rejected.request("account.current","{}")).containsKey("user"));
        try{rejected.request("account.register",SharedJson.encode(SharedRuntime.map("username","test_user","password","test-password")));throw new AssertionError("Password registration lost captcha");}
        catch(AccountException expected){yes(expected.code.equals("CHALLENGE_REQUIRED"));yes(denied.logins==1);}

        final byte[][] forwarded={null};final int[] requestCount={0},profileCount={0};
        final String[] profileHeaders={null,null};final List<Map<String,Object>> exchanged=new ArrayList<>();
        AccountRepository.Response marker=new AccountRepository.Response(200,new byte[0]);
        AccountRepository.Transport delegate=new AccountRepository.Transport(){
            public AccountRepository.Response request(String method,String path,String bearer,byte[] body)throws IOException{requestCount[0]++;forwarded[0]=body;if(path.equals("/auth/qq"))exchanged.add(SharedJson.object(new String(body,StandardCharsets.UTF_8)));return marker;}
            public AccountRepository.Response profileRequest(String method,String path,String bearer,byte[] body,String installation,String expected){profileCount[0]++;forwarded[0]=body;profileHeaders[0]=installation;profileHeaders[1]=expected;return marker;}
        };
        SharedQqLoginTransport transport=new SharedQqLoginTransport(delegate,INSTALL);
        byte[] input=SharedJson.encode(SharedRuntime.map("accessToken",PROVIDER,"challengeId","old-proof","challengeAnswer","old-answer","installationId",OTHER)).getBytes(StandardCharsets.UTF_8),original=input.clone();
        yes(transport.request("POST","/auth/qq",null,input)==marker);
        yes(exchanged.get(0).keySet().equals(new HashSet<>(Arrays.asList("accessToken","installationId"))));yes(INSTALL.equals(exchanged.get(0).get("installationId")));
        yes(Arrays.equals(input,original));boolean cleared=true;for(byte b:forwarded[0])cleared&=b==0;yes(cleared);
        byte[] profile={1,2,3};yes(transport.profileRequest("PUT","/auth/profile/avatar","bearer",profile,OTHER,"expected-revision")==marker);
        yes(profileCount[0]==1&&requestCount[0]==1);yes(forwarded[0]==profile);yes(OTHER.equals(profileHeaders[0])&&"expected-revision".equals(profileHeaders[1]));
        yes(transport.request("POST","/auth/register",null,input)==marker);yes(forwarded[0]==input);yes(requestCount[0]==2&&profileCount[0]==1);
        System.out.println("PASS "+checks+" QQ login bridge checks; no captcha, native installation, verified session, owner, registration proof and profile-header delegation");return checks;
    }
    public static void main(String[] args)throws Exception{run(Files.createTempDirectory("huevia-qq-login-"));}
}
