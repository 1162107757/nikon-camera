package cc.huevia.shared;

import cc.huevia.account.*;
import cc.huevia.library.SharedJson;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;

final class RegistrationBoundaryTest {
    private static int checks;
    private static final String OWNER="aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",INSTALL="bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",PROOF="cccccccc-cccc-cccc-cccc-cccccccccccc";
    private static void yes(boolean value){checks++;if(!value)throw new AssertionError("Registration boundary "+checks);}
    private static final class Store implements AccountRepository.Store {
        byte[] bytes;public byte[] read(){return bytes==null?null:bytes.clone();}public void write(byte[] value){bytes=value.clone();}public void clear(){bytes=null;}
    }
    private static final class Server implements AccountRepository.Transport {
        int registrations;boolean expired;
        public AccountRepository.Response request(String method,String path,String token,byte[] bytes)throws IOException{
            if(!path.equals("/auth/register"))throw new AssertionError("Registration triggered an unrelated account request");
            registrations++;Map<String,Object> body=SharedJson.object(new String(bytes,StandardCharsets.UTF_8));
            yes(PROOF.equals(body.get("challengeId")));yes(INSTALL.equals(body.get("installationId")));yes("ABCD".equals(body.get("challengeAnswer")));yes("test_user".equals(body.get("username")));
            if(expired)return response(400,SharedRuntime.map("error",SharedRuntime.map("code","CHALLENGE_EXPIRED","message","expired")));
            Map<String,Object> user=SharedRuntime.map("id",OWNER,"username","test_user","nickname","","avatarUrl","","avatarSource","default","provider","password","status","active","createdAt","2026-01-01T00:00:00Z","lastLoginAt","2026-01-01T00:00:00Z","updatedAt","2026-01-01T00:00:00Z","loginCount",1);
            return response(201,SharedRuntime.map("tokenType","Bearer","accessToken","a".repeat(43),"expiresAt","2099-01-01T00:00:00Z","user",user));
        }
        private AccountRepository.Response response(int status,Map<String,Object> value){return new AccountRepository.Response(status,SharedJson.encode(value).getBytes(StandardCharsets.UTF_8));}
    }
    static int run(Path temporary)throws Exception{
        checks=0;Path root=Files.createDirectory(temporary.resolve("registration"));Store store=new Store();Server server=new Server();SharedRuntime runtime=new SharedRuntime(root.toString(),store,server,INSTALL);
        Map<String,Object> payload=SharedRuntime.map("username","Test_User","password","local-test-password","challengeId",PROOF,"challengeAnswer","ABCD");
        Map<String,Object> session=SharedJson.object(runtime.request("account.register",SharedJson.encode(payload)));
        yes(Boolean.TRUE.equals(session.get("verified")));yes(OWNER.equals(((Map<?,?>)session.get("user")).get("id")));yes(!session.containsKey("accessToken")&&!session.containsKey("password"));yes(store.bytes!=null);
        yes(((Map<?,?>)SharedJson.object(runtime.request("account.current","{}")).get("user")).get("id").equals(OWNER));yes(server.registrations==1);
        SharedRuntime reopened=new SharedRuntime(root.toString(),store,server,INSTALL);yes(((Map<?,?>)SharedJson.object(reopened.request("account.current","{}")).get("user")).get("id").equals(OWNER));yes(server.registrations==1);
        Store empty=new Store();server.expired=true;SharedRuntime rejected=new SharedRuntime(Files.createDirectory(temporary.resolve("registration-rejected")).toString(),empty,server,INSTALL);
        try{rejected.request("account.register",SharedJson.encode(payload));throw new AssertionError("Expired challenge accepted");}
        catch(AccountException expected){yes(expected.code.equals("CHALLENGE_EXPIRED"));yes(expected.status==400);}
        yes(empty.bytes==null);yes(!SharedJson.object(rejected.request("account.current","{}")).containsKey("user"));
        System.out.println("PASS "+checks+" registration bridge checks; exact proof/installation, immediate session, persistence, no token exposure and explicit challenge failure");return checks;
    }
}
