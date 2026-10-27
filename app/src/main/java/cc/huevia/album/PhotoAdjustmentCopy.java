package cc.huevia.album;

import cc.huevia.ncp.PhotoAdjustments;
import java.io.IOException;
import java.util.*;
import java.util.function.BooleanSupplier;

/** Worker-only adjustment copy. Each write and undo compares the complete previous draft. */
public final class PhotoAdjustmentCopy {
    public static final class Target {
        public final String sha;
        public final PhotoEditStore.Draft expected, visible;
        public Target(String sha,PhotoEditStore.Draft expected,PhotoEditStore.Draft visible){
            if(sha==null||!sha.matches("[0-9a-f]{64}")||expected!=null&&!sha.equals(expected.sourceSha)||visible!=null&&!sha.equals(visible.sourceSha))throw new IllegalArgumentException("原图身份无效。");
            this.sha=sha;this.expected=expected;this.visible=visible;
        }
    }
    private static final class Change {
        final Target target;final PhotoEditStore.Draft next;
        Change(Target target,PhotoEditStore.Draft next){this.target=target;this.next=next;}
    }
    public static final class Receipt {
        private final List<Change> changes;
        public final int skipped;
        private Receipt(List<Change> changes,int skipped){this.changes=new ArrayList<>(changes);this.skipped=skipped;}
        public int changed(){return changes.size();}
        /** A newer edit is retained. A second call is safe and simply reports those entries as conflicts. */
        public synchronized int undo(PhotoEditStore store)throws IOException{return undo(store,null);}
        public synchronized int undo(PhotoEditStore store,BooleanSupplier allowed)throws IOException{int restored=0;for(Change c:changes){check(allowed);if(store.replace(c.target.sha,c.next,c.target.expected))restored++;}return restored;}
    }
    public static Receipt apply(PhotoEditStore store,List<Target> targets,PhotoAdjustments source,boolean basic,boolean curves,boolean hsl,BooleanSupplier allowed)throws IOException{
        if(store==null||source==null||targets==null||targets.isEmpty()||targets.size()>100||!basic&&!curves&&!hsl)throw new IOException("请选择照片和要复制的调节项。");
        List<Change> planned=new ArrayList<>(),written=new ArrayList<>();Set<String> distinct=new HashSet<>();int skipped=0;
        for(Target target:targets){
            if(target==null||!distinct.add(target.sha))throw new IOException("选中的照片原图重复。");
            PhotoEditStore.Draft base=target.visible==null?new PhotoEditStore.Draft(target.sha,null,"无滤镜",0,false):target.visible;
            PhotoAdjustments next=base.adjustments.copyFrom(source,basic,curves,hsl);
            if(next.equals(base.adjustments)){skipped++;continue;}
            planned.add(new Change(target,new PhotoEditStore.Draft(base.sourceSha,base.presetBytes(),base.name,base.strength,next,base.geometry,base.border,base.localEdits,false)));
        }
        try{
            check(allowed);
            for(Change change:planned){check(allowed);if(!store.replace(change.target.sha,change.target.expected,change.next))throw new IOException("照片设置已变化，请重新选择。");written.add(change);}
            check(allowed);return new Receipt(written,skipped);
        }catch(IOException failure){
            int conflicts=0;for(int i=written.size()-1;i>=0;i--){Change c=written.get(i);try{if(!store.replace(c.target.sha,c.next,c.target.expected))conflicts++;}catch(IOException rollback){failure.addSuppressed(rollback);conflicts++;}}
            if(conflicts>0)throw new IOException("复制中止，部分照片已有新设置，请逐张核对。",failure);
            throw failure;
        }
    }
    private static void check(BooleanSupplier allowed)throws IOException{if(Thread.currentThread().isInterrupted()||allowed!=null&&!allowed.getAsBoolean())throw new IOException("账号或任务已变化，复制已取消。");}
}
