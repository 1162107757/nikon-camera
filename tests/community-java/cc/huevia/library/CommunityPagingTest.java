package cc.huevia.library;
import java.io.*;
import java.net.URL;
import java.security.cert.Certificate;
import java.nio.file.Files;
import java.nio.charset.StandardCharsets;
import java.util.*;
import javax.net.ssl.HttpsURLConnection;
import cc.huevia.account.AccountJson;

/** Public feed paging contract; no internet, image decoding or camera access. */
public final class CommunityPagingTest {
    static int checks;static Map<String,Object> answer;static String address;static int calls;
    public static void main(String[] args)throws Exception{
        File directory=Files.createTempDirectory("huevia-paging-").toFile();
        SecureHttpClient http=new SecureHttpClient(url->{address=url.toString();calls++;return new Mock(url,AccountJson.stringify(answer).getBytes(StandardCharsets.UTF_8));});
        OnlinePresetRepository repository=new OnlinePresetRepository(directory,new PresetLibrary(directory),http);
        try{repository.fetchPage(1,20,"");throw new AssertionError();}catch(IOException expected){check(calls==0,"unmanaged endpoint cannot be expanded into community routes");}
        repository.useManagedEndpoint("https://managed.example.test/preset-library/catalog.json");
        Map<String,Object> preset=new LinkedHashMap<>(Map.of("id","19bd1434-e597-4f27-808d-9b86eb8d983d","name","胶片","description","","category","胶片","sha256","a".repeat(64),"byteLength",8,"fileUrl","https://managed.example.test/file.ncp","previewUrl","","compatibleModels",List.of()));
        preset.put("author",Map.of("id","42ee04c3-b4de-4992-8e22-6ec528b01d92","nickname","摄影师","avatarUrl",""));preset.put("source","community");
        answer=new LinkedHashMap<>(Map.of("items",List.of(preset),"page",1,"pageSize",20,"total",41,"hasMore",true,"categories",List.of("","胶片","人像")));
        OnlinePresetRepository.PageResult result=repository.fetchPage(1,20,"胶片");check(result.presets.size()==1&&result.total==41&&result.hasMore,"first page does not impose legacy256 total cap");
        check(result.categories.equals(List.of("","胶片","人像")),"global categories retained including uncategorized");check(result.presets.get(0).authorName.equals("摄影师"),"feed attribution retained");
        check(address.equals("https://managed.example.test/preset-library/community/feed?page=1&pageSize=20&category=%E8%83%B6%E7%89%87"),"fixed product page URL and escaped category");
        repository.fetchPage(1,20,"__uncategorized__");check(address.endsWith("category=__uncategorized__"),"uncategorized sentinel preserved");repository.fetchPage(1,20,"");check(address.endsWith("category="),"empty category means all");
        int before=calls;for(int[] bad:new int[][]{{0,20},{1,0},{1,101},{100001,20}})try{repository.fetchPage(bad[0],bad[1],"");throw new AssertionError();}catch(IOException expected){check(calls==before,"invalid page rejected before HTTP");}
        for(String key:new String[]{"total","page","pageSize"}){Object previous=answer.put(key,-1);try{repository.fetchPage(1,20,"");throw new AssertionError();}catch(IOException expected){check(true,"page bounds validated");}answer.put(key,previous);}
        Object previous=answer.put("items",List.of(preset,preset));try{repository.fetchPage(1,20,"");throw new AssertionError();}catch(IOException expected){check(true,"duplicate row IDs rejected");}answer.put("items",previous);
        previous=answer.put("hasMore","true");try{repository.fetchPage(1,20,"");throw new AssertionError();}catch(IOException expected){check(true,"hasMore strict boolean");}answer.put("hasMore",previous);
        previous=answer.put("categories",List.of("全部"));try{repository.fetchPage(1,20,"");throw new AssertionError();}catch(IOException expected){check(true,"reserved category cannot become real category");}answer.put("categories",previous);
        formatFiltering(repository,preset);
        System.out.println("Community paging: "+checks+" checks passed (host-only).");
    }
    static void formatFiltering(OnlinePresetRepository repository,Map<String,Object> legacy)throws Exception{
        Map<String,Object> np3=new LinkedHashMap<>(legacy);np3.put("fileFormat","NP3");np3.put("fileUrl","https://managed.example.test/file.np3");
        answer=new LinkedHashMap<>(Map.of("items",List.of(legacy),"page",1,"pageSize",20,"total",21,"hasMore",true,"categories",List.of("","胶片","人像"),"fileFormat","NCP"));
        OnlinePresetRepository.PageResult result=repository.fetchPage(1,20,"胶片","NCP");
        check(address.endsWith("category=%E8%83%B6%E7%89%87&fileFormat=NCP"),"format and category sent together");
        check(result.fileFormat.equals("NCP")&&result.presets.get(0).fileFormat.equals("NCP"),"legacy missing format belongs to NCP filter");
        check(result.total==21&&result.hasMore&&result.presets.size()==1,"filtered total and hasMore retained without current-page recount");
        check(result.categories.equals(List.of("","胶片","人像")),"format filtering keeps global categories");
        answer.put("fileFormat","NP3");answer.put("items",List.of(np3));
        result=repository.fetchPage(1,20,"__uncategorized__","NP3");
        check(address.endsWith("category=__uncategorized__&fileFormat=NP3"),"NP3 combines with uncategorized sentinel");
        check(result.fileFormat.equals("NP3")&&result.presets.get(0).fileFormat.equals("NP3"),"NP3 response format retained");
        answer.put("page",2);answer.put("items",List.of());answer.put("hasMore",false);
        result=repository.fetchPage(2,20,"","NP3");
        check(result.page==2&&result.total==21&&!result.hasMore&&result.presets.isEmpty(),"filtered later/empty page keeps server pagination");
        answer.put("page",1);answer.put("items",List.of(np3));answer.put("fileFormat","");
        check(repository.fetchPage(1,20,"","").fileFormat.isEmpty(),"all-format response acknowledged");
        check(!address.contains("fileFormat="),"all-format URL remains backward compatible");
        check(repository.fetchPage(1,20,"",null).presets.size()==1,"null format is all");
        check(repository.fetchPage(1,20,"").presets.get(0).fileFormat.equals("NP3"),"old overload returns both supported formats");
        answer.remove("fileFormat");check(repository.fetchPage(1,20,"").fileFormat.isEmpty(),"old all-format service remains compatible");
        expectFailure(()->repository.fetchPage(1,20,"","NP3"),"old server ignoring filter rejected");
        for(Object bad:new Object[]{"NCP","ncp","UNKNOWN",true,1}){
            answer.put("fileFormat",bad);expectFailure(()->repository.fetchPage(1,20,"","NP3"),"wrong acknowledgement rejected");
        }
        answer.put("fileFormat",null);expectFailure(()->repository.fetchPage(1,20,""),"explicit null acknowledgement rejected");
        answer.put("fileFormat","NP3");answer.put("items",List.of(legacy));
        expectFailure(()->repository.fetchPage(1,20,"","NP3"),"mismatched row rejected instead of silently dropping page items");
        int before=calls;
        for(String bad:new String[]{"ncp","np3"," NCP","NP3 ","NCP&category=胶片","ALL","JPEG"})
            expectFailure(()->repository.fetchPage(1,20,"",bad),"invalid format rejected before HTTP");
        check(calls==before,"invalid formats perform no network requests");
        check(repository.cachedCatalog().status.equals("no_cache"),"paging never writes a partial manifest cache");
    }
    interface Request{void run()throws Exception;}
    static void expectFailure(Request request,String label)throws Exception{try{request.run();throw new AssertionError(label);}catch(IOException expected){check(true,label);}}
    static void check(boolean value,String name){if(!value)throw new AssertionError(name);checks++;}
    static final class Mock extends HttpsURLConnection{
        final byte[] bytes;Mock(URL url,byte[] bytes){super(url);this.bytes=bytes;}
        public int getResponseCode(){return 200;}public long getContentLengthLong(){return bytes.length;}public InputStream getInputStream(){return new ByteArrayInputStream(bytes);}public String getHeaderField(String key){return null;}
        public void disconnect(){}public void connect(){}public boolean usingProxy(){return false;}public String getCipherSuite(){return"TEST";}public Certificate[] getLocalCertificates(){return new Certificate[0];}public Certificate[] getServerCertificates(){return new Certificate[0];}
    }
}
