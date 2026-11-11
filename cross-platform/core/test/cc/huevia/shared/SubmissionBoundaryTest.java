package cc.huevia.shared;

import cc.huevia.library.SharedJson;
import cc.huevia.community.SubmissionDraftStore;
import cc.huevia.ncp.NcpCompatibilityFixtures;
import java.io.*;
import java.nio.file.*;
import java.util.*;

final class SubmissionBoundaryTest {
    private static final String OWNER="11111111-1111-4111-8111-111111111111",OTHER="22222222-2222-4222-8222-222222222222",POST="33333333-3333-4333-8333-333333333333",ASSET="ncp-"+cc.huevia.album.PhotoEditStore.hash(NcpCompatibilityFixtures.ncp());
    private static int checks;
    private interface Action{void run()throws Exception;}
    private static void yes(boolean value){checks++;if(!value)throw new AssertionError("Submission boundary "+checks);}
    private static void rejects(Action action)throws Exception{checks++;try{action.run();}catch(IOException|IllegalArgumentException expected){return;}throw new AssertionError("Unsafe submission accepted");}
    private static Map<String,Object> request(SharedSubmissions flow,String op,Map<String,Object> payload)throws IOException{
        Map<String,Object> p=SharedRuntime.map("owner",OWNER,"slot","new");p.putAll(payload);return flow.request("submission."+op,SharedJson.object(SharedJson.encode(p)),()->false);
    }
    private static Map<String,Object> draft(Map<String,Object> envelope)throws IOException{return SharedRuntime.object(envelope.get("draft"));}
    private static final class Fake implements SharedSubmissions.Api {
        int writes,uploads,submits;boolean loseSave=true,loseSubmit=true,switchOwner,rejectWrite,allowGet;String[] current;
        final List<Map<String,Object>> bodies=new ArrayList<>();
        public Map<String,Object> get(String owner,String path)throws IOException{if(allowGet)return SharedRuntime.map("submission",server(false));throw new IOException("offline");}
        public Map<String,Object> upload(String owner,String kind,String name,byte[] bytes,String mime){uploads++;return SharedRuntime.map("asset",SharedRuntime.map("id",ASSET,"name",name));}
        public Map<String,Object> write(String owner,String method,String path,Map<String,Object> body)throws IOException{
            yes(OWNER.equals(owner));bodies.add(SharedJson.object(SharedJson.encode(body)));writes++;
            if(rejectWrite)throw new cc.huevia.community.CommunityException("REVISION_CONFLICT",409,"refresh required");
            if(switchOwner){current[0]=OTHER;return SharedRuntime.map("submission",server(false));}
            if(path.endsWith("/submit")){submits++;if(loseSubmit){loseSubmit=false;throw new IOException("submit response lost");}return SharedRuntime.map("submission",server(true));}
            if(loseSave){loseSave=false;throw new IOException("save response lost");}return SharedRuntime.map("submission",server(false));
        }
        private Map<String,Object> server(boolean submitted)throws IOException{return SharedJson.object(SharedJson.encode(SharedRuntime.map("id",POST,"revision",submitted?2:1,"status",submitted?"pending":"draft","name","测试","fileAssetId",ASSET)));}
    }
    static int run(Path temporary)throws Exception{
        checks=0;Path root=Files.createDirectory(temporary.resolve("submissions"));String[] current={OWNER};Fake api=new Fake();api.current=current;
        SharedSubmissions flow=new SharedSubmissions(root.toFile(),api,owner->{if(!owner.equals(current[0]))throw new IOException("owner changed");});
        Map<String,Object> first=draft(request(flow,"load",Map.of()));yes(first.containsKey("createKey"));
        request(flow,"persist",SharedRuntime.map("draft",SharedRuntime.map("name","测试","rightsConfirmed",true)));
        byte[] ncp=NcpCompatibilityFixtures.ncp();Map<String,Object> staged=SharedJson.object(SharedImport.stageSubmission(new ByteArrayInputStream(ncp),"test.ncp","ncp",OWNER,root.toString(),()->false));
        yes(((String)staged.get("path")).contains("submission-incoming"));
        Map<String,Object> attach=new LinkedHashMap<>(staged);attach.put("kind","ncp");request(flow,"attach",attach);
        yes(!Files.exists(Path.of((String)staged.get("path"))));
        SharedImport.stageSubmission(new ByteArrayInputStream(ncp),"test.ncp","ncp",OWNER,root.toString(),()->false);
        rejects(()->request(flow,"attach",SharedRuntime.map("kind","ncp","path",staged.get("path"),"name","../bad.ncp")));
        Map<String,Object> other=SharedJson.object(SharedImport.stageSubmission(new ByteArrayInputStream(ncp),"test.ncp","ncp",OTHER,root.toString(),()->false));
        rejects(()->request(flow,"attach",SharedRuntime.map("kind","ncp","path",other.get("path"),"name","test.ncp")));
        rejects(()->request(flow,"save",SharedRuntime.map("draft",SharedRuntime.map("name","测试","rightsConfirmed",true),"submit",true)));
        Map<String,Object> frozen=draft(request(flow,"load",Map.of()));yes(Boolean.TRUE.equals(frozen.get("savePending"))&&api.uploads==1);
        request(flow,"persist",SharedRuntime.map("draft",SharedRuntime.map("name","changed","rightsConfirmed",false)));
        yes("测试".equals(draft(request(flow,"load",Map.of())).get("name")));
        // Even the other retry button must preserve the originally reviewed submit intent.
        rejects(()->request(flow,"save",SharedRuntime.map("draft",SharedRuntime.map("name","changed"),"submit",false)));
        yes(api.uploads==1&&api.writes==3&&api.submits==1&&api.bodies.get(0).equals(api.bodies.get(1)));
        Map<String,Object> pending=draft(request(flow,"load",Map.of()));yes(Boolean.TRUE.equals(pending.get("submitPending"))&&!Boolean.TRUE.equals(pending.get("savePending")));
        rejects(()->request(flow,"save",SharedRuntime.map("draft",Map.of(),"submit",false)));
        Map<String,Object> complete=draft(request(flow,"save",SharedRuntime.map("draft",Map.of(),"submit",true)));
        yes("pending".equals(complete.get("status"))&&api.writes==4&&api.submits==2&&api.bodies.get(2).equals(api.bodies.get(3)));
        Map<String,Object> next=draft(request(flow,"load",Map.of()));yes(!next.containsKey("id")&&!next.get("createKey").equals(first.get("createKey")));
        Map<String,Object> archived=draft(request(flow,"load",SharedRuntime.map("slot",POST)));yes(POST.equals(archived.get("id"))&&!archived.containsKey("filePath"));
        rejects(()->request(flow,"persist",SharedRuntime.map("draft",SharedRuntime.map("name","x".repeat(161)))));
        rejects(()->SharedImport.stageSubmission(new ByteArrayInputStream(ncp),"bad.np3","ncp",OWNER,root.toString(),()->false));
        rejects(()->SharedImport.stageSubmission(new ByteArrayInputStream(new byte[4*1024*1024+1]),"big.png","preview",OWNER,root.toString(),()->false));
        rejects(()->SharedImport.stageSubmission(new ByteArrayInputStream(ncp),"test.ncp","ncp",OWNER,root.toString(),()->true));
        try(java.util.stream.Stream<Path> files=Files.walk(root.resolve("submission-incoming"))){yes(files.noneMatch(p->p.toString().endsWith(".part")));}
        // Switching authors after a response cannot write its receipt into the new owner's draft.
        request(flow,"persist",SharedRuntime.map("draft",SharedRuntime.map("name","测试","rightsConfirmed",true)));
        request(flow,"attach",attach);api.switchOwner=true;
        rejects(()->request(flow,"save",SharedRuntime.map("draft",SharedRuntime.map("name","测试","rightsConfirmed",true),"submit",false)));
        yes(!Files.exists(root.resolve("shared-submissions").resolve(OTHER)));
        current[0]=OWNER;yes(Boolean.TRUE.equals(draft(request(flow,"load",Map.of())).get("savePending")));
        rejects(()->request(flow,"reload",SharedRuntime.map("discardLocal",true)));
        api.switchOwner=false;request(flow,"save",SharedRuntime.map("draft",Map.of(),"submit",false));api.rejectWrite=true;
        rejects(()->request(flow,"save",SharedRuntime.map("draft",SharedRuntime.map("name","修改","rightsConfirmed",true),"submit",false)));
        Map<String,Object> conflict=draft(request(flow,"load",Map.of()));yes(!Boolean.TRUE.equals(conflict.get("savePending"))&&"修改".equals(conflict.get("name")));
        rejects(()->request(flow,"reload",Map.of()));api.allowGet=true;
        Map<String,Object> refreshed=draft(request(flow,"reload",SharedRuntime.map("discardLocal",true)));
        yes("测试".equals(refreshed.get("name"))&&!refreshed.containsKey("filePath")&&!Boolean.TRUE.equals(refreshed.get("localDirty")));
        System.out.println("PASS "+checks+" durable submission checks; lost save/submit replies, account ownership, staged attachment limits");return checks;
    }
}
