package cc.huevia.shared;

import java.io.*;
import java.nio.file.*;
import java.util.*;
import cc.huevia.library.SharedJson;

final class UiStateBoundaryTest {
    static int run(Path temporary)throws Exception{
        Path root=Files.createDirectory(temporary.resolve("ui-preferences"));SharedUiState store=new SharedUiState(root.toFile());int checks=0;
        if(store.read().size()!=1)throw new AssertionError("New UI state is not empty");checks++;
        Map<String,Object> local=SharedRuntime.map("category","人像","format","NP3","download","all");
        store.update(SharedRuntime.map("presetLocal",local,"presetSource","local"));
        store.update(SharedRuntime.map("presetOnline",SharedRuntime.map("category","","format","NCP","download","saved")));
        Map<String,Object> saved=new SharedUiState(root.toFile()).read();
        if(!local.equals(saved.get("presetLocal")))throw new AssertionError("Separate source preference overwritten");checks++;
        if(!"saved".equals(SharedRuntime.object(saved.get("presetOnline")).get("download")))throw new AssertionError("Online preference not restored");checks++;
        store.update(SharedRuntime.map("album",SharedRuntime.map("source","phone","filter","raw","added",true,"oldest",false)));
        if(!Boolean.TRUE.equals(SharedRuntime.object(new SharedUiState(root.toFile()).read().get("album")).get("added")))throw new AssertionError("Album preference not restored");checks++;
        byte[] before=Files.readAllBytes(root.resolve("shared-ui-state-v1.json"));
        for(Map<String,Object> invalid:Arrays.asList(SharedRuntime.map("unknown","x"),SharedRuntime.map("presetSource","unexpected"),SharedRuntime.map("presetLocal",SharedRuntime.map("category","x","format","CR3","download","all")),SharedRuntime.map("album",SharedRuntime.map("source","phone","filter","raw","added","true","oldest",false)))){
            try{store.update(invalid);throw new AssertionError("Invalid UI state accepted");}catch(IOException expected){checks++;}
            if(!Arrays.equals(before,Files.readAllBytes(root.resolve("shared-ui-state-v1.json"))))throw new AssertionError("Rejected UI state changed file");checks++;
        }
        Files.write(root.resolve("shared-ui-state-v1.json"),"{broken".getBytes(java.nio.charset.StandardCharsets.UTF_8));
        try{store.update(SharedRuntime.map("presetSource","online"));throw new AssertionError("Corrupt preferences replaced");}catch(IOException expected){checks++;}
        return checks;
    }
}
