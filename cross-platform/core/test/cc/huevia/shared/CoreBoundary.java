package cc.huevia.shared;

import cc.huevia.account.AccountRepository;
import cc.huevia.library.SharedJson;
import cc.huevia.library.PresetLibrary;
import cc.huevia.album.PhotoEditStore;
import cc.huevia.ncp.NcpCompatibilityFixtures;
import java.io.*;
import java.nio.file.*;
import java.util.*;

/** Real filesystem and account-store failures must not disable the offline library. */
public final class CoreBoundary {
    private CoreBoundary(){}
    private static int checks;
    private static final class LockedStore implements AccountRepository.Store {
        public byte[] read()throws IOException{throw new IOException("Store locked");}
        public void write(byte[] value)throws IOException{throw new IOException("Store locked");}
        public void clear()throws IOException{throw new IOException("Store locked");}
    }
    private static final class NoNetwork implements AccountRepository.Transport {
        public AccountRepository.Response request(String method,String path,String token,byte[] body){throw new AssertionError("Offline initialization performed a network request");}
    }
    private interface Action {void run()throws Exception;}
    private static void yes(boolean value){checks++;if(!value)throw new AssertionError("Shared boundary check "+checks);}
    private static void rejects(Action action)throws Exception{checks++;try{action.run();}catch(IOException expected){return;}throw new AssertionError("Invalid shared request was accepted");}
    public static int run()throws Exception{
        checks=0;Path temporary=Files.createTempDirectory("huevia-shared-boundary-");
        try{
            Path root=temporary.resolve("private");
            SharedRuntime runtime=new SharedRuntime(root.toString(),new LockedStore(),new NoNetwork());
            Map<String,Object> current=SharedJson.object(runtime.request("account.current","{}"));
            yes(Boolean.TRUE.equals(current.get("logoutPending")));yes(!current.containsKey("user"));yes(!((String)current.get("storageWarning")).isEmpty());
            Map<String,Object> library=SharedJson.object(runtime.request("library.list","{}"));yes(((List<?>)library.get("items")).isEmpty());
            byte[] installation=Files.readAllBytes(root.resolve("account-installation.txt"));
            new SharedRuntime(root.toString(),new LockedStore(),new NoNetwork());yes(Arrays.equals(installation,Files.readAllBytes(root.resolve("account-installation.txt"))));
            Path outside=temporary.resolve("outside.ncp");Files.write(outside,new byte[]{1,2,3,4});
            rejects(()->runtime.privateFile(outside.toString()));
            rejects(()->runtime.request("library.import",SharedJson.encode(SharedRuntime.map("path",outside.toString(),"name","outside.ncp"))));
            yes(Arrays.equals(new byte[]{1,2,3,4},Files.readAllBytes(outside)));
            SharedRecipe recipe=new SharedRecipe("{\"schema\":1,\"values\":[0,10,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],\"geometry\":{\"turns\":1,\"mirrored\":true},\"palette\":{\"color\":20,\"tone\":-10,\"amount\":50}}");
            yes(recipe.adjustments.values()[1]==10);yes(recipe.geometry.turns==1&&recipe.geometry.mirrored);yes(recipe.adjustments.palette.color==20&&recipe.adjustments.palette.amount==50);
            rejects(()->new SharedRecipe("{\"schema\":2}"));rejects(()->new SharedRecipe("{\"values\":[1]}"));rejects(()->new SharedRecipe("{\"hsl\":[1,2]}"));rejects(()->new SharedRecipe("{\"strength\":101}"));rejects(()->new SharedRecipe("{\"localData\":\"!!!!\"}"));
            SharedCaptureInfo capture=new SharedCaptureInfo("{\"Make\":\"NIKON CORPORATION\",\"Model\":\"NIKON Z 6_2\",\"FocalLength\":\"500/10\",\"FNumber\":\"28/10\",\"ExposureTime\":\"1/125\",\"ISOSpeedRatings\":\"400\",\"DateTimeOriginal\":\"2026:11:10 08:09:10\"}");
            yes(capture.brand.equals("NIKON"));yes(capture.parameters(cc.huevia.ncp.PhotoBorder.NONE).equals("50mm  F2.8  1/125s  ISO400"));
            yes(capture.field(cc.huevia.ncp.PhotoBorder.NONE,4).equals("2026-11-10 08:09:10"));
            File source=root.resolve("source.jpg").toFile();Files.write(source.toPath(),new byte[]{10,20,30,40});
            PresetLibrary presets=new PresetLibrary(root.toFile());byte[] original=NcpCompatibilityFixtures.ncp();
            String presetId=presets.importFile("frozen.ncp",original).record.sha256;
            SharedEdits edits=new SharedEdits(root.toFile(),presets);
            String edit=SharedJson.encode(SharedRuntime.map("presetId",presetId,"strength",75));
            PhotoEditStore.Draft frozen=edits.freeze(source,"alice",edit);
            yes(Arrays.equals(original,frozen.presetBytes()));yes(frozen.strength==75);
            presets.remove(presetId);
            PhotoEditStore.Draft reopened=edits.freeze(source,"alice",edit);
            yes(Arrays.equals(original,reopened.presetBytes()));yes(frozen.identity().equals(reopened.identity()));
            yes(frozen.profile().modelVersion().equals(reopened.profile().modelVersion()));
            yes(edits.load(source,"bob")==null);
            edits.markExported("alice",frozen);yes(edits.load(source,"alice").exported);
            PhotoEditStore.Draft changed=edits.freeze(source,"alice",SharedJson.encode(SharedRuntime.map("presetId",presetId,"strength",50)));
            edits.markExported("alice",frozen);yes(!edits.load(source,"alice").exported);yes(edits.load(source,"alice").identity().equals(changed.identity()));
            String roundTrip=SharedJson.encode(SharedEdits.recipe(changed));yes(changed.identity().equals(edits.freeze(source,"alice",roundTrip).identity()));
            rejects(()->runtime.freezeEdit(source.getPath(),"alice",edit));
            String sourceSha=edits.sourceIdentity(source,false);Files.write(source.toPath(),new byte[]{40,30,20,10});
            yes(!sourceSha.equals(edits.sourceIdentity(source,true)));
            yes(SharedRawSettings.parse("{}").equals(cc.huevia.ncp.RawDevelopmentSettings.DEFAULT));
            cc.huevia.ncp.RawDevelopmentSettings rawSettings=SharedRawSettings.parse("{\"whiteBalance\":\"CUSTOM\",\"temperature\":4800,\"tint\":10,\"exposure\":5,\"colorMode\":\"NEUTRAL\"}");
            yes(SharedRawSettings.parse(SharedRawSettings.json(rawSettings)).equals(rawSettings));
            rejects(()->SharedRawSettings.parse("{\"quality\":2}"));rejects(()->SharedRawSettings.parse("{\"exposure\":51}"));
            rejects(()->SharedRawSettings.parse("{\"temperature\":1999}"));rejects(()->SharedRawSettings.parse("{\"whiteBalance\":\"unknown\"}"));
            rejects(()->runtime.request("personal.status","{\"owner\":\"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa\"}"));
            checks+=PersonalSyncBoundaryTest.run(temporary);
            checks+=RecipeBoundaryTest.run(temporary);
            System.out.println("PASS "+checks+" shared boundary checks; offline account, private paths, immutable preset drafts, owner isolation and export snapshots");
            return checks;
        }finally{
            Path guard=temporary.toFile().getCanonicalFile().toPath();
            Path systemTemp=new File(System.getProperty("java.io.tmpdir")).getCanonicalFile().toPath();
            if(!guard.startsWith(systemTemp)||!temporary.getFileName().toString().startsWith("huevia-shared-boundary-"))throw new IOException("Unsafe test cleanup path");
            remove(temporary.toFile(),guard);
        }
    }
    private static void remove(File file,Path guard)throws IOException{
        if(Files.isSymbolicLink(file.toPath())){Files.deleteIfExists(file.toPath());return;}
        if(!file.getCanonicalFile().toPath().startsWith(guard))throw new IOException("Test cleanup escaped its temporary directory");
        File[] children=file.listFiles();if(children!=null)for(File child:children)remove(child,guard);if(file.exists()&&!file.delete())throw new IOException("Cannot remove test workspace");
    }
}
