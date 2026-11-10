package cc.huevia;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.atomic.*;

public final class AppCrashDiagnosticsTest {
    private static int checks;
    public static void main(String[] args) throws Exception {
        Path root=Files.createTempDirectory("app-stability184-");
        try {
            AtomicInteger delegated=new AtomicInteger();AtomicReference<Throwable> passed=new AtomicReference<>();
            Thread.UncaughtExceptionHandler previous=(thread,error)->{delegated.incrementAndGet();passed.set(error);};
            File directory=root.resolve("records").toFile();
            AppCrashDiagnostics.CrashRecorder recorder=new AppCrashDiagnostics.CrashRecorder(directory,"sdk=31\nmodel=Test Magic\nversion=184",previous);
            Throwable first=new IllegalStateException("original-failure",new IOException("original-cause"));
            recorder.uncaughtException(Thread.currentThread(),first);
            yes(delegated.get()==1&&passed.get()==first,"Original failure delegated exactly once");
            Path file=directory.toPath().resolve("last-crash.txt");String record=Files.readString(file);
            yes(record.contains("original-failure")&&record.contains("original-cause")&&record.contains("sdk=31"),"Durable stack/cause/device metadata");
            yes(record.contains("recordedAtEpochMillis=")&&record.contains("heapMax="),"Timestamp and heap evidence");
            yes(!Files.exists(directory.toPath().resolve("last-crash.txt.tmp")),"Atomic commit leaves no tentative record");
            Throwable huge=new RuntimeException("型".repeat(100000));
            recorder.uncaughtException(Thread.currentThread(),huge);
            byte[] bytes=Files.readAllBytes(file);
            yes(bytes.length<=AppCrashDiagnostics.MAX_BYTES,"Huge Unicode stack remains within byte cap");
            yes(new String(bytes,StandardCharsets.UTF_8).contains("stackTruncated=true"),"Truncation is explicit");
            yes(delegated.get()==2&&passed.get()==huge,"Large failure is still delegated unchanged");
            Path blocked=root.resolve("not-a-directory");Files.writeString(blocked,"sentinel");
            new AppCrashDiagnostics.CrashRecorder(blocked.toFile(),"",previous).uncaughtException(Thread.currentThread(),first);
            yes(delegated.get()==3&&passed.get()==first,"Disk recording failure cannot swallow the original crash");
            yes(Files.readString(blocked).equals("sentinel"),"Unavailable record directory is not overwritten");
            RuntimeException sentinel=new RuntimeException("previous-handler-result");
            AppCrashDiagnostics.CrashRecorder throwing=new AppCrashDiagnostics.CrashRecorder(directory,"",(thread,error)->{throw sentinel;});
            try{throwing.uncaughtException(Thread.currentThread(),first);throw new AssertionError("Previous handler result swallowed");}
            catch(RuntimeException actual){yes(actual==sentinel,"Previous handler behavior propagates");}
            yes(AppCrashDiagnostics.boundedRead(new ByteArrayInputStream("abcdef".getBytes(StandardCharsets.UTF_8)),3).equals("abc"),"Diagnostic input reader obeys its bound");
            System.out.println("PASS AppCrashDiagnosticsTest "+checks+" checks; atomic bounded local evidence and original-handler chaining.");
        }finally{try(var paths=Files.walk(root)){for(Path p:paths.sorted(Comparator.reverseOrder()).toList())Files.deleteIfExists(p);}}
    }
    private static void yes(boolean pass,String label){checks++;if(!pass)throw new AssertionError(label);}
}
