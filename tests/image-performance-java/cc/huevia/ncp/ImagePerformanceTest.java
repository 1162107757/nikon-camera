package cc.huevia.ncp;

import java.io.IOException;
import java.io.InterruptedIOException;
import java.util.Arrays;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Random;
import java.util.function.IntUnaryOperator;
import static cc.huevia.ncp.PhotoAdjustments.Parameter.*;

/** Exact regression against the frozen 107 kernels, plus bounded row-storage observations. */
public final class ImagePerformanceTest {
    private static long checks, comparedPixels;
    private static volatile long sink;
    private static final java.util.Map<String,Long> benchmarkHashes = new java.util.HashMap<>();

    public static void main(String[] args) throws Exception {
        if (args.length > 0 && "--bench".equals(args[0])) { benchmark(); return; }
        colour(); spatial(); cancellationAndFailure();
        System.out.println("PASS image-performance checks=" + checks + " comparedPixels=" + comparedPixels);
    }

    private static void colour() {
        List<PhotoAdjustments> settings = new ArrayList<>();
        settings.add(PhotoAdjustments.NONE);
        for (PhotoAdjustments.Parameter p : PhotoAdjustments.Parameter.values()) {
            for (int value : new int[]{p.min, Math.max(p.min, -1), 0, 1, p.max}) settings.add(PhotoAdjustments.NONE.with(p, value));
        }
        Random random = new Random(108);
        for (int n = 0; n < 24; n++) {
            int[] values = new int[PhotoAdjustments.Parameter.values().length];
            for (PhotoAdjustments.Parameter p : PhotoAdjustments.Parameter.values()) values[p.ordinal()] = p.min + random.nextInt(p.max - p.min + 1);
            settings.add(new PhotoAdjustments(values));
        }
        PhotoCurves curve = PhotoCurves.NONE.withPoints(0, new int[]{0,5,55,42,130,153,210,226,255,252})
                .withPoints(2, new int[]{0,0,127,110,255,255});
        PhotoHsl hsl = PhotoHsl.NONE.with(0,0,14).with(1,1,-22).with(5,2,18);
        PhotoAdjustments basic = PhotoAdjustments.NONE.with(EXPOSURE,7).with(CONTRAST,24).with(BRIGHTNESS,10)
                .with(HIGHLIGHTS,-20).with(SHADOWS,26).with(WHITES,-12).with(BLACKS,7)
                .with(TEMPERATURE,8).with(TINT,-4).with(SATURATION,5).with(VIBRANCE,20);
        settings.add(basic); settings.add(basic.withCurves(curve)); settings.add(basic.withHsl(hsl)); settings.add(basic.withCurves(curve).withHsl(hsl));
        PresetPreviewProfile preset = new PresetPreviewProfile() {
            public String registrationName() { return "deterministic point profile"; }
            public String modelVersion() { return "test-point-v1"; }
            public double mapTone(double x) { return x; }
            public int applyArgb(int x) { return x ^ 0x003c5a17; }
        };
        for (PhotoAdjustments setting : settings) {
            for (PresetPreviewProfile base : new PresetPreviewProfile[]{null, preset}) {
                PresetPreviewProfile old = LegacyAdjustedReference.of(base, setting), next = AdjustedPreviewProfile.of(base, setting);
                check(old.modelVersion().equals(next.modelVersion()), "model identity");
                for (int i = 0; i < 8192; i++) {
                    int pixel = i < 1024 ? ((i / 256 * 85) << 24) | ((i & 255) * 0x010101) : random.nextInt();
                    check(old.applyArgb(pixel) == next.applyArgb(pixel), "ARGB output changed"); comparedPixels++;
                }
            }
        }
    }

    private static void spatial() throws Exception {
        int[][] dimensions = {{1,1},{1,2},{2,1},{2,3},{3,2},{17,31},{31,17},{64,29},{801,3},{1601,3},{2401,5},{3201,3},{6000,7},{3,1601},{5,2401},{3,6000}};
        double[] amounts = {-1, 0, 1};
        for (int[] size : dimensions) for (double sharp : amounts) for (double mid : amounts) for (double clarity : amounts) {
            for (boolean scaled : new boolean[]{false, true}) compare(size[0], size[1], sharp, mid, clarity, scaled, 0);
        }
        for (double sharp : new double[]{-.73, -.01, .01, .37, .99}) {
            compare(83,59,sharp,0,0,true,1);
            compare(1601,39,sharp,0,0,true,2);
        }
        // Cross the former 91-row and 123-row ring boundaries on real output arrays.
        compare(6000,121,.37,0,0,true,0);
        compare(8192,163,1,0,0,true,1);
        // Keep all three scales when either additional band contributes, even at tiny values.
        compare(2401,17,.37,0,.00001,true,2);
        compare(2401,17,.37,.00001,0,true,2);
        Trace next = new Trace(6000,200,0); SpatialPreviewFilter.applyScaled(next,new SpatialPreviewFilter.Settings(.37,0,0),x->x,()->false,null);
        Trace old = new Trace(6000,200,0); LegacySpatialReference.applyScaled(old,new LegacySpatialReference.Settings(.37,0,0),x->x,()->false,null);
        check(next.firstWriteReadCount == 5 && old.firstWriteReadCount == 46, "only-sharpening retains precisely the required future halo");
        check(Arrays.equals(next.data, old.data), "small-ring exact output");
        System.out.println("SHARPENING_HALO width=6000 firstWriteReads old=" + old.firstWriteReadCount + " new=" + next.firstWriteReadCount);
    }

    private static void compare(int w,int h,double s,double m,double c,boolean scaled,int pattern) throws Exception {
        Trace old = new Trace(w,h,pattern), next = new Trace(w,h,pattern);
        int[] untouched = next.data.clone(); int[] oldCalls = {0}, nextCalls = {0};
        IntUnaryOperator a = x -> { oldCalls[0]++; return x ^ 0xa53c5a17; };
        IntUnaryOperator b = x -> { nextCalls[0]++; return x ^ 0xa53c5a17; };
        List<Double> op = new ArrayList<>(), np = new ArrayList<>();
        if (scaled) {
            LegacySpatialReference.applyScaled(old,new LegacySpatialReference.Settings(s,m,c),a,()->false,op::add);
            SpatialPreviewFilter.applyScaled(next,new SpatialPreviewFilter.Settings(s,m,c),b,()->false,np::add);
        } else {
            LegacySpatialReference.apply(old,new LegacySpatialReference.Settings(s,m,c),a,63,()->false,op::add);
            SpatialPreviewFilter.apply(next,new SpatialPreviewFilter.Settings(s,m,c),b,63,()->false,np::add);
        }
        check(Arrays.equals(old.data,next.data), "spatial output " + w + "x" + h + " " + s + "/" + m + "/" + c + " scaled=" + scaled);
        check(op.equals(np), "progress values");
        check(oldCalls[0] == w*h && nextCalls[0] == w*h, "one transform per pixel");
        check(next.reads == h && next.writes == h && old.reads == h && old.writes == h, "each row read/written once");
        for (int i = 0; i < next.data.length; i++) check((next.data[i] & 0xff000000) == (untouched[i] & 0xff000000), "alpha preserved");
        comparedPixels += (long)w*h;
    }

    private static void cancellationAndFailure() throws Exception {
        SpatialPreviewFilter.Settings settings = new SpatialPreviewFilter.Settings(.6,0,0);
        Trace initial = new Trace(31,53,0);
        expectFailure(() -> SpatialPreviewFilter.applyScaled(initial,settings,x->x,()->true,null), InterruptedIOException.class);
        check(initial.reads == 0 && initial.writes == 0, "cancel before I/O");
        Trace midway = new Trace(31,53,0);
        expectFailure(() -> SpatialPreviewFilter.applyScaled(midway,settings,x->x,()->midway.writes==3,null), InterruptedIOException.class);
        check(midway.writes == 3, "cancel at completed row boundary");
        Trace readFailure = new Trace(31,53,0); readFailure.failRead = 2;
        expectFailure(() -> SpatialPreviewFilter.applyScaled(readFailure,settings,x->x,()->false,null), IOException.class);
        check(readFailure.reads == 2, "read failure propagation");
        Trace writeFailure = new Trace(31,53,0); writeFailure.failWrite = 3;
        expectFailure(() -> SpatialPreviewFilter.applyScaled(writeFailure,settings,x->x,()->false,null), IOException.class);
        check(writeFailure.writes == 3, "write failure propagation");
        Thread.currentThread().interrupt();
        try { expectFailure(() -> SpatialPreviewFilter.applyScaled(initial,settings,x->x,()->false,null), InterruptedIOException.class); check(Thread.currentThread().isInterrupted(), "interrupt preserved"); }
        finally { Thread.interrupted(); }
        // Keep the legacy three-scale memory boundary. No pixel allocation is needed to exercise preflight.
        StreamStore huge = new StreamStore(12000,8000);
        expectFailure(() -> SpatialPreviewFilter.applyScaled(huge,new SpatialPreviewFilter.Settings(.6,0,.1),x->x,()->false,null), IOException.class);
        check(huge.reads == 0, "three-scale over-budget fails before I/O");
        // Only-sharpening now fits the work-buffer cap; stop immediately after preloading B1.
        StreamStore sharpen = new StreamStore(12000,8000);
        expectFailure(() -> SpatialPreviewFilter.applyScaled(sharpen,settings,x->x,()->sharpen.reads>=1,null), InterruptedIOException.class);
        check(sharpen.reads == 1, "large only-sharpening passes bounded-memory preflight");
    }

    private static void benchmark() throws Exception {
        for (int i = 0; i < 2; i++) { time(false,1600,1000); time(true,1600,1000); }
        double[] old = new double[3], next = new double[3];
        for (int i = 0; i < 3; i++) {
            if ((i&1)==0) { old[i]=time(false,6000,4000); next[i]=time(true,6000,4000); }
            else { next[i]=time(true,6000,4000); old[i]=time(false,6000,4000); }
        }
        Arrays.sort(old);Arrays.sort(next);
        System.out.printf(Locale.ROOT,"SHARPENING_24MP oldMedianMs=%.3f newMedianMs=%.3f ratio=%.3f sink=%d%n",old[1],next[1],old[1]/next[1],sink);
        System.out.println("Host streaming pixel-kernel benchmark; no Android Bitmap, JPEG codec, disk, or physical-device claim.");
    }
    private static double time(boolean current,int w,int h) throws Exception {
        StreamStore store = new StreamStore(w,h); long before = System.nanoTime();
        if (current) SpatialPreviewFilter.applyScaled(store,new SpatialPreviewFilter.Settings(.6,0,0),x->x,()->false,null);
        else LegacySpatialReference.applyScaled(store,new LegacySpatialReference.Settings(.6,0,0),x->x,()->false,null);
        double elapsed=(System.nanoTime()-before)/1000000.0;
        String key=w+"x"+h;Long previous=benchmarkHashes.putIfAbsent(key,store.hash);
        check(previous==null||previous.longValue()==store.hash,"large stream output hash changed");
        sink=store.hash;return elapsed;
    }

    private static final class Trace implements SpatialPreviewFilter.Pixels, LegacySpatialReference.Pixels {
        final int w,h;final int[] data;int reads,writes,firstWriteReadCount=-1,failRead=-1,failWrite=-1;
        Trace(int w,int h,int pattern){this.w=w;this.h=h;data=new int[w*h];Random random=new Random(w*97L+h*13L+pattern);for(int i=0;i<data.length;i++){int p=random.nextInt();data[i]=pattern==1?(p|0xff000000):pattern==2?(i%7==0?0:p&0x7fffffff):p;}}
        public int width(){return w;}public int height(){return h;}
        public void read(int[] target,int row,int rows)throws IOException{if(row==failRead)throw new IOException("read fixture");check(rows==1&&row==reads&&row>=writes,"ordered original rows");System.arraycopy(data,row*w,target,0,w);reads++;}
        public void write(int[] source,int row,int rows)throws IOException{if(row==failWrite)throw new IOException("write fixture");check(rows==1&&row==writes&&row<reads,"ordered output rows");if(firstWriteReadCount<0)firstWriteReadCount=reads;System.arraycopy(source,0,data,row*w,w);writes++;}
    }
    private static final class StreamStore implements SpatialPreviewFilter.Pixels, LegacySpatialReference.Pixels {
        final int w,h;int reads,writes;long hash;
        StreamStore(int w,int h){this.w=w;this.h=h;}public int width(){return w;}public int height(){return h;}
        public void read(int[] target,int row,int rows){if(rows!=1||row!=reads||row<writes)throw new AssertionError("stream read");for(int x=0;x<w;x++){int v=(x*1664525+row*1013904223);target[x]=0xff000000|(v&0xffffff);}reads++;}
        public void write(int[] source,int row,int rows){if(rows!=1||row!=writes||row>=reads)throw new AssertionError("stream write");for(int value:source)hash=hash*31+value;writes++;}
    }
    private interface Throwing {void run()throws Exception;}
    private static void expectFailure(Throwing action,Class<? extends Exception> type)throws Exception{try{action.run();throw new AssertionError("missing failure");}catch(Exception e){check(type.isInstance(e),"failure type");}}
    private static void check(boolean value,String message){checks++;if(!value)throw new AssertionError(message);}
}
