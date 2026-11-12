package cc.huevia.shared;

import cc.huevia.library.*;
import java.io.*;
import java.nio.file.*;
import java.util.*;

final class PresetPinsBoundaryTest {
    private static int checks;
    private static void yes(boolean value){checks++;if(!value)throw new AssertionError("Preset pins "+checks);}
    private interface Action{void run()throws Exception;}
    private static void rejects(Action action)throws Exception{checks++;try{action.run();}catch(IOException expected){return;}throw new AssertionError("Invalid pins accepted");}
    static int run(Path temporary)throws Exception{
        checks=0;File root=Files.createDirectory(temporary.resolve("pins")).toFile();
        SharedPresetPins pins=new SharedPresetPins(root);String a="a".repeat(64),b="b".repeat(64),c="c".repeat(64),alice="aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
        yes(pins.read("").isEmpty());pins.set("",a,true);pins.set("",b,true);pins.set("",a,true);
        yes(pins.read("").equals(Arrays.asList(b,a)));yes(new SharedPresetPins(root).read("").equals(Arrays.asList(b,a)));
        List<Object> rows=new ArrayList<>(Arrays.asList(SharedRuntime.map("id",c),SharedRuntime.map("id",a),SharedRuntime.map("id",b),SharedRuntime.map("id","d".repeat(64))));pins.order("",rows);
        yes(((Map<?,?>)rows.get(0)).get("id").equals(b));yes(((Map<?,?>)rows.get(1)).get("id").equals(a));yes(((Map<?,?>)rows.get(2)).get("id").equals(c));yes(Boolean.TRUE.equals(((Map<?,?>)rows.get(0)).get("pinned")));yes(Boolean.FALSE.equals(((Map<?,?>)rows.get(2)).get("pinned")));
        pins.set("",b,false);pins.set("",b,false);yes(pins.read("").equals(List.of(a)));
        yes(pins.read(alice).isEmpty());pins.set(alice,c,true);yes(pins.read("").equals(List.of(a)));yes(pins.read(alice).equals(List.of(c)));
        rejects(()->pins.set("../other",a,true));rejects(()->pins.set("","../outside",true));
        Path pending=root.toPath().resolve("preset-pins");yes(Files.list(pending).noneMatch(path->path.getFileName().toString().endsWith(".part")));
        System.out.println("PASS "+checks+" preset pin checks; multiple pins, stable ordering, persistence, account isolation and unpin");return checks;
    }
    public static void main(String[] args)throws Exception{run(Files.createTempDirectory("preset-pins-test-"));}
}
