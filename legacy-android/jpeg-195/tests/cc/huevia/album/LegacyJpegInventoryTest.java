package cc.huevia.album;

import cc.huevia.ptp.PtpObjectInfo;
import cc.huevia.ptp.PtpResponseException;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InterruptedIOException;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

/** Pure read-only PTP fixtures. No Android classes, camera writes, source rewrites or original downloads. */
public final class LegacyJpegInventoryTest {
    private static int checks,cases;
    private interface Action { void run() throws Exception; }
    private static void yes(boolean value,String reason){checks++;if(!value)throw new AssertionError(reason+" (check "+checks+")");}
    private static void run(String name,Action action)throws Exception{
        cases++;
        try{action.run();}catch(Exception|AssertionError failure){throw new AssertionError(name,failure);}
    }
    private static void rejects(Action action,String reason)throws Exception{
        checks++;try{action.run();}catch(IOException expected){return;}throw new AssertionError(reason);
    }
    public static void main(String[] args)throws Exception{
        run("successful-empty JPEG filter falls back",LegacyJpegInventoryTest::emptyFilterFallsBack);
        run("nonempty JPEG filter does not enumerate all formats",LegacyJpegInventoryTest::nonemptyFilterStaysFiltered);
        run("known format rejection falls back",LegacyJpegInventoryTest::unsupportedFormatFallsBack);
        run("a genuinely empty readable card stays distinguishable",LegacyJpegInventoryTest::trueEmptyCard);
        run("partial and fully unavailable cards stay distinguishable",LegacyJpegInventoryTest::unavailableCards);
        run("other transport/status failures are not an empty album",LegacyJpegInventoryTest::otherErrors);
        run("cancellation brackets each fallback read",LegacyJpegInventoryTest::cancellation);
        run("card and unique-handle bounds",LegacyJpegInventoryTest::limitsAndDeduplication);
        run("invalid and truncated handle datasets",LegacyJpegInventoryTest::invalidDatasets);
        run("standard and generic JPEG metadata classification",LegacyJpegInventoryTest::jpegClassification);
        run("NEF, video and associations remain separate",LegacyJpegInventoryTest::nonJpegClassification);
        System.out.println("PASS LEGACY_JPEG_195_CHECKS="+checks+" CASES="+cases);
    }

    private static void emptyFilterFallsBack()throws Exception{
        Script peer=new Script().storages(1).filtered(1,new long[0]).all(1,3,4,5);
        LegacyJpegInventory.Result result=read(peer);
        counts(result,1,1,0,3);sameHandles(result,3,4,5);peer.finished();
        yes(peer.calls.size()==3,"one explicit all-format retry after successful empty filter");
    }
    private static void nonemptyFilterStaysFiltered()throws Exception{
        Script peer=new Script().storages(1).filtered(1,10,11);
        LegacyJpegInventory.Result result=read(peer);counts(result,1,1,0,2);sameHandles(result,10,11);peer.finished();
        yes(peer.calls.size()==2,"nonempty format query must not unnecessarily enumerate RAW");
    }
    private static void unsupportedFormatFallsBack()throws Exception{
        Script peer=new Script().storages(1).filteredFailure(1,0x2014).all(1,22,23);
        LegacyJpegInventory.Result result=read(peer);counts(result,1,1,0,2);sameHandles(result,22,23);peer.finished();
    }
    private static void trueEmptyCard()throws Exception{
        Script peer=new Script().storages(1).filtered(1,new long[0]).all(1,new long[0]);
        LegacyJpegInventory.Result result=read(peer);counts(result,1,1,0,0);peer.finished();
        Script none=new Script().storages();result=read(none);counts(result,0,0,0,0);none.finished();
    }
    private static void unavailableCards()throws Exception{
        Script partial=new Script().storages(1,2).filteredFailure(1,0x2013).filtered(2,7);
        LegacyJpegInventory.Result result=read(partial);counts(result,2,1,1,1);sameHandles(result,7);partial.finished();
        Script all=new Script().storages(1,2).filteredFailure(1,0x2013).filteredFailure(2,0x2013);
        result=read(all);counts(result,2,0,2,0);all.finished();
        Script afterEmpty=new Script().storages(1).filtered(1,new long[0]).allFailure(1,0x2013);
        result=read(afterEmpty);counts(result,1,0,1,0);afterEmpty.finished();
        Script afterUnsupported=new Script().storages(1).filteredFailure(1,0x2014).allFailure(1,0x2013);
        result=read(afterUnsupported);counts(result,1,0,1,0);afterUnsupported.finished();
    }
    private static void otherErrors()throws Exception{
        for(int status:new int[]{0x2002,0x2003,0x2004,0x2005,0x2019}){
            Script peer=new Script().storages(1).filteredFailure(1,status);
            checks++;
            try{read(peer);throw new AssertionError("non-fallback status was accepted: "+status);}
            catch(PtpResponseException expected){yes(expected.responseCode()==status,"preserve the real camera response code");}
            peer.finished();yes(peer.calls.size()==2,"unexpected error cannot trigger unrequested fallback");
        }
        Script fallback=new Script().storages(1).filtered(1,new long[0]).allFailure(1,0x2003);
        rejects(()->read(fallback),"terminal session error in fallback cannot produce a success snapshot");fallback.finished();
        Script network=new Script().storages(1).failure(0x1007,new IOException("controlled transport interrupted"),1,0x3801,0);
        rejects(()->read(network),"transport error cannot be interpreted as no JPEG");network.finished();
        Script storageError=new Script().failure(0x1004,new PtpResponseException(0x2003,1));
        rejects(()->read(storageError),"GetStorageIDs failure must propagate");storageError.finished();
    }
    private static void cancellation()throws Exception{
        Script before=new Script().storages(1);Cancel cancelled=new Cancel();cancelled.cancelled=true;
        rejects(()->read(before,cancelled),"cancelled inventory must not start an I/O");yes(before.calls.isEmpty(),"no GetStorageIDs after cancellation");
        Script afterStorage=new Script().storages(1);Cancel storageCancel=new Cancel();afterStorage.afterRead=()->storageCancel.cancelled=true;
        rejects(()->read(afterStorage,storageCancel),"cancellation after storage read must be noticed");afterStorage.finished();
        Script beforeFallback=new Script().storages(1).filtered(1,new long[0]);Cancel filterCancel=new Cancel();
        beforeFallback.afterRead=()->{if(beforeFallback.calls.size()==2)filterCancel.cancelled=true;};
        rejects(()->read(beforeFallback,filterCancel),"empty-filter cancellation must prevent fallback");beforeFallback.finished();yes(beforeFallback.calls.size()==2,"no fallback transaction after cancellation");
        Script afterFallback=new Script().storages(1).filtered(1,new long[0]).all(1,1,2);Cancel fallbackCancel=new Cancel();
        afterFallback.afterRead=()->{if(afterFallback.calls.size()==3)fallbackCancel.cancelled=true;};
        rejects(()->read(afterFallback,fallbackCancel),"cancellation after fallback must not publish its result");afterFallback.finished();
        Script unsupported=new Script().storages(1).filteredFailure(1,0x2014);Cancel unsupportedCancel=new Cancel();
        unsupported.afterRead=()->{if(unsupported.calls.size()==2)unsupportedCancel.cancelled=true;};
        rejects(()->read(unsupported,unsupportedCancel),"cancelled rejected-filter request must not send fallback");unsupported.finished();
        Script duringLoop=new Script().storages(1).filtered(1,range(10000));final boolean[] collecting={false};final int[] iterations={0};
        duringLoop.afterRead=()->{if(duringLoop.calls.size()==2)collecting[0]=true;};
        LegacyJpegInventory.Cancellation loopCancel=()->{if(collecting[0]&&++iterations[0]>=4)throw new InterruptedIOException("controlled loop cancellation");};
        rejects(()->read(duringLoop,loopCancel),"large handle collection must remain cancellable");duringLoop.finished();
    }
    private static void limitsAndDeduplication()throws Exception{
        Script sixtyFive=new Script().storages(range(65));rejects(()->read(sixtyFive),"65 storage IDs exceed the supported bound");sixtyFive.finished();
        long[] sixtyFour=range(64);Script maxCards=new Script().storages(sixtyFour);
        for(long storage:sixtyFour)maxCards.filtered(storage,new long[0]).all(storage,new long[0]);
        LegacyJpegInventory.Result result=read(maxCards);counts(result,64,64,0,0);maxCards.finished();
        Script maxHandles=new Script().storages(1).filtered(1,range(20000));result=read(maxHandles);counts(result,1,1,0,20000);maxHandles.finished();
        Script over=new Script().storages(1).filtered(1,range(20001));rejects(()->read(over),"20001 unique objects exceed the bound");over.finished();
        Script duplicate=new Script().storages(1,2).filtered(1,1,1,2).filtered(2,2,3,3);
        result=read(duplicate);counts(result,2,2,0,3);sameHandles(result,1,2,3);duplicate.finished();
        Script repeatedMax=new Script().storages(1,2).filtered(1,range(20000)).filtered(2,range(20000));
        result=read(repeatedMax);counts(result,2,2,0,20000);repeatedMax.finished();
    }
    private static void invalidDatasets()throws Exception{
        for(long invalid:new long[]{0,0xffffffffL}){
            Script peer=new Script().storages(1).filtered(1,1,invalid);
            rejects(()->read(peer),"reserved/zero object handle cannot enter the snapshot");peer.finished();
        }
        Script truncated=new Script().storages(1).data(0x1007,concat(le32(2),le32(1)),1,0x3801,0);
        rejects(()->read(truncated),"truncated UINT32 array must fail");truncated.finished();
        Script trailing=new Script().storages(1).data(0x1007,concat(array(1),new byte[]{1}),1,0x3801,0);
        rejects(()->read(trailing),"trailing bytes must not silently alter array parsing");trailing.finished();
        Script malformedStorage=new Script().data(0x1004,concat(le32(2),le32(1)));
        rejects(()->read(malformedStorage),"malformed storage list must fail before card queries");malformedStorage.finished();
    }
    private static void jpegClassification(){
        format(0x3801,"DSC_0001.JPG",0,PhotoFormat.JPEG);
        format(0x3801,"DSC_0001.JPEG",0,PhotoFormat.JPEG);
        for(int generic:new int[]{0,0x3000}){
            format(generic,"DSC_0001.JPG",0,PhotoFormat.JPEG);
            format(generic,"DSC_0001.jpeg",0,PhotoFormat.JPEG);
            format(generic,"mixed.JpEg",0,PhotoFormat.JPEG);
            for(String invalid:new String[]{"folder/DSC.JPG","folder\\DSC.JPG","../DSC.JPG","bad\n.JPG","bad\t.jpg","no-extension","DSC.jpg.tmp","DSC.jpe"})format(generic,invalid,0,PhotoFormat.OTHER);
        }
    }
    private static void nonJpegClassification(){
        yes(PhotoFormat.of(null)==PhotoFormat.OTHER,"null metadata remains unknown");
        for(int type:new int[]{0,0x3000,0x3801,0xb103})format(type,"DSC_0001.NEF",0,PhotoFormat.NEF);
        format(0x3001,"folder.JPG",0,PhotoFormat.OTHER);format(0x3001,"folder.NEF",1,PhotoFormat.OTHER);
        format(0x3801,"folder.JPG",1,PhotoFormat.OTHER);format(0,"folder.jpg",1,PhotoFormat.OTHER);
        format(0x300a,"clip.AVI",0,PhotoFormat.OTHER);format(0x3000,"clip.MOV",0,PhotoFormat.OTHER);
        format(0x380b,"photo.jpg",0,PhotoFormat.OTHER);format(0xb103,"photo.jpg",0,PhotoFormat.OTHER);
        format(0x3000,"DSC.ARW",0,PhotoFormat.OTHER);format(0x3000,"DSC.CR3",0,PhotoFormat.OTHER);
    }
    private static void format(int code,String name,int association,PhotoFormat expected){
        PtpObjectInfo info=new PtpObjectInfo.Builder().storageId(1).objectFormat(code).associationType(association).filename(name).compressedSize(128).build();
        yes(PhotoFormat.of(info)==expected,"source format classification changed for controlled type/name");
        try{yes(PhotoFormat.of(PtpObjectInfo.parse(info.toBytes()))==expected,"classification must survive actual ObjectInfo binary parsing");}
        catch(IOException impossible){throw new AssertionError("controlled descriptor failed its round trip",impossible);}
    }
    private static LegacyJpegInventory.Result read(Script peer)throws IOException{return read(peer,new Cancel());}
    private static LegacyJpegInventory.Result read(Script peer,LegacyJpegInventory.Cancellation cancel)throws IOException{
        return LegacyJpegInventory.read(peer,cancel,(stage,count,detail)->{yes(stage!=null&&!stage.isEmpty(),"diagnostic stage must be present");});
    }
    private static void counts(LegacyJpegInventory.Result result,int storages,int readable,int unavailable,int handles){
        yes(result.storageCount==storages,"storage count");yes(result.readableStorages==readable,"readable storage count");yes(result.unavailableStorages==unavailable,"unavailable storage count");yes(result.handles.length==handles,"unique handle count");
    }
    private static void sameHandles(LegacyJpegInventory.Result result,long... expected){
        Set<Long> actual=new LinkedHashSet<>(),wanted=new LinkedHashSet<>();for(long handle:result.handles)actual.add(handle);for(long handle:expected)wanted.add(handle);
        yes(actual.equals(wanted),"inventory contains exactly the expected unique objects");
    }
    private static final class Cancel implements LegacyJpegInventory.Cancellation {
        boolean cancelled;
        @Override public void check()throws IOException{if(cancelled)throw new InterruptedIOException("controlled cancellation");}
    }
    private static final class Step {
        final int operation;final long[] parameters;final byte[] data;final IOException failure;
        Step(int operation,long[] parameters,byte[] data,IOException failure){this.operation=operation;this.parameters=parameters;this.data=data;this.failure=failure;}
    }
    private static final class Script implements LegacyJpegInventory.Reader {
        final List<Step> steps=new ArrayList<>(),calls=new ArrayList<>();Runnable afterRead=()->{};
        Script storages(long... storages){return data(0x1004,array(storages));}
        Script filtered(long storage,long... handles){return data(0x1007,array(handles),storage,0x3801,0);}
        Script all(long storage,long... handles){return data(0x1007,array(handles),storage,0,0);}
        Script filteredFailure(long storage,int code){return failure(0x1007,new PtpResponseException(code,1),storage,0x3801,0);}
        Script allFailure(long storage,int code){return failure(0x1007,new PtpResponseException(code,1),storage,0,0);}
        Script data(int operation,byte[] data,long... parameters){steps.add(new Step(operation,parameters,data,null));return this;}
        Script failure(int operation,IOException failure,long... parameters){steps.add(new Step(operation,parameters,null,failure));return this;}
        @Override public byte[] read(String stage,int operation,int limit,long... parameters)throws IOException{
            yes(!steps.isEmpty(),"unexpected camera operation; no original/thumbnail reads allowed");
            Step next=steps.remove(0);calls.add(next);yes(next.operation==operation,"PTP operation order");yes(Arrays.equals(next.parameters,parameters),"PTP format/storage parameters");
            yes(limit==(operation==0x1004?4096:1024*1024),"bounded dataset read size");
            afterRead.run();if(next.failure!=null)throw next.failure;return next.data;
        }
        void finished(){yes(steps.isEmpty(),"expected bounded camera transactions were not completed");}
    }
    private static long[] range(int count){long[] values=new long[count];for(int i=0;i<count;i++)values[i]=i+1L;return values;}
    private static byte[] array(long... values){ByteArrayOutputStream bytes=new ByteArrayOutputStream();bytes.writeBytes(le32(values.length));for(long value:values)bytes.writeBytes(le32(value));return bytes.toByteArray();}
    private static byte[] le32(long value){return new byte[]{(byte)value,(byte)(value>>>8),(byte)(value>>>16),(byte)(value>>>24)};}
    private static byte[] concat(byte[]... values){ByteArrayOutputStream bytes=new ByteArrayOutputStream();for(byte[] value:values)bytes.writeBytes(value);return bytes.toByteArray();}
}
