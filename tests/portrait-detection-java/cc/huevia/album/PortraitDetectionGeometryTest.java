package cc.huevia.album;

import java.io.IOException;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.BooleanSupplier;

/** Production geometry only. Android bitmap/detector stubs are never executed on the host JVM. */
public final class PortraitDetectionGeometryTest {
    private static int checks;
    private static Method consensus, duplicate;
    private static final BooleanSupplier NEVER = () -> false;

    public static void main(String[] args) throws Exception {
        Class<?> detection = Class.forName("cc.huevia.album.PhotoPortraitDetection");
        consensus = detection.getDeclaredMethod("consensusMatches", List.class, List.class, BooleanSupplier.class);
        duplicate = detection.getDeclaredMethod("duplicate", double[].class, double[].class);
        consensus.setAccessible(true);
        duplicate.setAccessible(true);
        consensusGeometry();
        duplicateGeometry();
        invalidAnchors();
        cancellation();
        System.out.println("PortraitDetectionGeometryTest: " + checks + " checks passed");
    }

    private static void consensusGeometry() throws Exception {
        expect("empty-primary", matches(Collections.emptyList(), list(eye(0, 0, 20))), new boolean[0]);
        expect("empty-secondary", matches(list(eye(0, 0, 20)), Collections.emptyList()), false);
        expect("identical-anchors", matches(list(eye(10, 20, 20)), list(eye(10, 20, 20))), true);
        expect("translation-at-limit", matches(list(eye(0, 0, 20)), list(eye(6, 0, 20))), true);
        expect("translation-beyond-limit", matches(list(eye(0, 0, 20)), list(eye(6.0001, 0, 20))), false);
        expect("diagonal-within-limit", matches(list(eye(0, 0, 20)), list(eye(4.2, 4.2, 20))), true);
        expect("diagonal-not-axis-only", matches(list(eye(0, 0, 20)), list(eye(4.3, 4.3, 20))), false);
        expect("scale-lower-boundary", matches(list(eye(0, 0, 20)), list(eye(0, 0, 15))), true);
        expect("scale-below-boundary", matches(list(eye(0, 0, 20)), list(eye(0, 0, 14.99))), false);
        expect("scale-upper-boundary", matches(list(eye(0, 0, 20)), list(eye(0, 0, 26.6))), true);
        expect("scale-above-boundary", matches(list(eye(0, 0, 20)), list(eye(0, 0, 26.61))), false);
        expect("mean-eye-distance-boundary", matches(list(eye(0, 0, 20)), list(eye(5.25, 0, 15))), true);
        expect("mean-eye-distance-beyond", matches(list(eye(0, 0, 20)), list(eye(5.251, 0, 15))), false);
        expect("roll-at-twenty", matches(list(eye(0, 0, 20, -5)), list(eye(0, 0, 20, 15))), true);
        expect("roll-beyond-twenty", matches(list(eye(0, 0, 20, -5)), list(eye(0, 0, 20, 15.001))), false);
        expect("opposite-roll-rejected", matches(list(eye(0, 0, 20, -40)), list(eye(0, 0, 20, 40))), false);
        expect("roll-wrap-is-small-angle", matches(list(eye(0, 0, 20, 179)), list(eye(0, 0, 20, -179))), true);
        expect("roll-wrap-inclusive", matches(list(eye(0, 0, 20, 170)), list(eye(0, 0, 20, -170))), true);
        expect("roll-wrap-beyond", matches(list(eye(0, 0, 20, 170)), list(eye(0, 0, 20, -169.999))), false);
        expect("legacy-three-field-anchors", matches(list(eye(0, 0, 20)), list(eye(0, 0, 20))), true);
        expect("confidence-does-not-replace-geometry", matches(list(eye(0, 0, 20, 0, .35)), list(eye(10, 0, 20, 0, 1))), false);
        expect("confidence-not-top-one", matches(list(eye(0, 0, 20, 0, .35), eye(60, 0, 20, 0, .99)),
                list(eye(1, 0, 20, 0, .9), eye(59, 0, 20, 0, .35))), true, true);
        expect("one-secondary-used-once", matches(list(eye(0, 0, 20), eye(5, 0, 20)), list(eye(1, 0, 20))), true, false);
        expect("nearest-not-primary-order", matches(list(eye(0, 0, 20), eye(5, 0, 20)), list(eye(4, 0, 20))), false, true);
        expect("multiple-secondary-permutation", matches(list(eye(0, 0, 20), eye(50, 0, 20), eye(100, 0, 20)),
                list(eye(101, 0, 20), eye(1, 0, 20), eye(51, 0, 20))), true, true, true);
        expect("unmatched-middle-does-not-block-others", matches(list(eye(0, 0, 20), eye(50, 0, 20), eye(100, 0, 20)),
                list(eye(1, 0, 20), eye(99, 0, 20))), true, false, true);
        double[] a = eye(4, 5, 20, -4, .8), b = eye(5, 5, 20, -4, .9);
        double[] beforeA = a.clone(), beforeB = b.clone();
        matches(Collections.singletonList(a), Collections.singletonList(b));
        check("consensus-does-not-mutate-primary", Arrays.equals(a, beforeA));
        check("consensus-does-not-mutate-secondary", Arrays.equals(b, beforeB));
    }

    private static void duplicateGeometry() throws Exception {
        check("same-face-is-duplicate", dup(eye(20, 30, 20, 5), eye(20, 30, 20, 5)));
        check("near-anchor-is-duplicate", dup(eye(0, 0, 20, 0), eye(5, 0, 20, 0)));
        check("duplicate-distance-inclusive", dup(eye(0, 0, 20, 0), eye(7, 0, 20, 0)));
        check("duplicate-distance-beyond", !dup(eye(0, 0, 20, 0), eye(7.001, 0, 20, 0)));
        check("duplicate-distance-euclidean", !dup(eye(0, 0, 20, 0), eye(5, 5, 20, 0)));
        check("nearby-real-faces-not-merged", !dup(eye(0, 0, 20, 0), eye(12, 0, 20, 0)));
        check("different-y-real-faces-not-merged", !dup(eye(0, 0, 20, 0), eye(0, 12, 20, 0)));
        check("duplicate-roll-inclusive", dup(eye(0, 0, 20, -5), eye(0, 0, 20, 15)));
        check("different-roll-not-merged", !dup(eye(0, 0, 20, -5), eye(0, 0, 20, 15.001)));
        check("duplicate-roll-wrap", dup(eye(0, 0, 20, 179), eye(0, 0, 20, -179)));
        check("duplicate-scale-lower-inclusive", dup(eye(0, 0, 20, 0), eye(0, 0, 14, 0)));
        check("duplicate-scale-lower-beyond", !dup(eye(0, 0, 20, 0), eye(0, 0, 13.99, 0)));
        check("duplicate-scale-upper-inclusive", dup(eye(0, 0, 20, 0), eye(0, 0, 20 / .7, 0)));
        check("duplicate-scale-upper-beyond", !dup(eye(0, 0, 20, 0), eye(0, 0, 20 / .7 + .01, 0)));
        check("small-face-controls-merge-radius", !dup(eye(0, 0, 20, 0), eye(5.1, 0, 14, 0)));
        check("optional-confidence-keeps-spatial-meaning", dup(eye(0, 0, 20, 0, .35), eye(1, 0, 20, 0, 1)));
        check("legacy-three-field-duplicate", dup(eye(0, 0, 20), eye(1, 0, 20)));
        double[] a = eye(0, 0, 20, -4, .8), b = eye(1, 0, 14, 4, .9);
        check("duplicate-symmetry", dup(a, b) == dup(b, a));
        double[] beforeA = a.clone(), beforeB = b.clone();
        dup(a, b);
        check("duplicate-does-not-mutate-primary", Arrays.equals(a, beforeA));
        check("duplicate-does-not-mutate-secondary", Arrays.equals(b, beforeB));
    }

    private static void invalidAnchors() throws Exception {
        double[][] invalid = {null, eye(), eye(0, 0), eye(0, 0, 0), eye(0, 0, -1),
                eye(Double.NaN, 0, 20), eye(0, Double.POSITIVE_INFINITY, 20),
                eye(0, 0, Double.NaN), eye(0, 0, Double.POSITIVE_INFINITY),
                eye(0, 0, 20, Double.NaN), eye(0, 0, 20, Double.NEGATIVE_INFINITY)};
        for (int i = 0; i < invalid.length; i++) {
            expect("invalid-primary-" + i, matches(Collections.singletonList(invalid[i]), list(eye(0, 0, 20))), false);
            expect("invalid-secondary-" + i, matches(list(eye(0, 0, 20)), Collections.singletonList(invalid[i])), false);
            check("invalid-duplicate-" + i, !dup(invalid[i], eye(0, 0, 20)) && !dup(eye(0, 0, 20), invalid[i]));
        }
        expect("invalid-anchor-does-not-steal-nearest", matches(list(eye(0, 0, 20), eye(50, 0, 20)),
                list(eye(0, 0, 20, Double.NaN), eye(1, 0, 20), eye(49, 0, 20))), true, true);
    }

    private static void cancellation() throws Exception {
        expectCancellation("immediate-cancel", () -> (boolean[]) invoke(consensus,
                list(eye(0, 0, 20)), list(eye(0, 0, 20)), (BooleanSupplier) () -> true));
        AtomicInteger requests = new AtomicInteger();
        expectCancellation("cancel-during-matching", () -> (boolean[]) invoke(consensus,
                list(eye(0, 0, 20), eye(50, 0, 20), eye(100, 0, 20)),
                list(eye(0, 0, 20), eye(50, 0, 20), eye(100, 0, 20)),
                (BooleanSupplier) () -> requests.incrementAndGet() > 1));
        check("cancel-polled-after-first-match", requests.get() > 1);
        Thread.currentThread().interrupt();
        try {
            expectCancellation("thread-interruption", () -> matches(list(eye(0, 0, 20)), list(eye(0, 0, 20))));
            check("interrupt-flag-preserved", Thread.currentThread().isInterrupted());
        } finally { Thread.interrupted(); }
    }

    private interface Operation { boolean[] run() throws Exception; }
    private static void expectCancellation(String name, Operation operation) throws Exception {
        try { operation.run(); throw new AssertionError(name + " did not cancel"); }
        catch (IOException expected) { check(name, true); }
    }
    private static double[] eye(double... fields) { return fields; }
    private static List<double[]> list(double[]... anchors) { return Arrays.asList(anchors); }
    private static boolean[] matches(List<double[]> a, List<double[]> b) throws Exception {
        return (boolean[]) invoke(consensus, a, b, NEVER);
    }
    private static boolean dup(double[] a, double[] b) throws Exception { return (boolean) invoke(duplicate, a, b); }
    private static Object invoke(Method method, Object... arguments) throws Exception {
        try { return method.invoke(null, arguments); }
        catch (InvocationTargetException error) {
            if (error.getCause() instanceof Exception) throw (Exception) error.getCause();
            throw error;
        }
    }
    private static void expect(String name, boolean[] actual, boolean... expected) {
        check(name, Arrays.equals(actual, expected));
    }
    private static void check(String name, boolean result) {
        if (!result) throw new AssertionError(name);
        checks++;
    }
}
