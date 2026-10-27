package cc.huevia.album;

import android.content.Context;
import android.os.Build;
import java.io.File;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.Comparator;
import java.util.List;

/** Production local deletion and project sequencing against the real gallery/provider host facade. */
public final class PhotoAlbumDeletionHostTest {
    private static int checks;
    public static void main(String[] args) throws Exception {
        Path root = Files.createTempDirectory("photo-album-deletion-");
        try {
            removesBothCopiesAndEveryProjectReference(root.resolve("normal"));
            removesInternalSourceReferencesWithExternalStorageAvailable(root.resolve("internal"));
            providerFailureRetainsSourceAndSupportsPartialRetry(root.resolve("partial"));
            metadataFailureKeepsSourceAfterPublicDeletion(root.resolve("metadata"));
            rejectsForeignAndIncompleteFiles(root.resolve("invalid"));
            transferableReservationsExcludeQueuedMutations();
            effectsDeleteBeforeOriginalsAndFailuresProtectEveryAlias(root.resolve("effect-failure"));
            effectOnlyKeepsTheOriginalAndUnselectedEffectsProtectIt(root.resolve("effect-only"));
            failedStackedEffectProtectsItsImmediateInput(root.resolve("stacked"));
            wholeGroupDeletesBothPrivateEffectAliasesAndOnePublication(root.resolve("alias-delete"), 35);
            wholeGroupDeletesBothPrivateEffectAliasesAndOnePublication(root.resolve("alias-delete-legacy"), 28);
            appOnlyDeletionPreservesPublicCopiesAndAllowsExplicitReceive(root.resolve("app-only"));
            appOnlyMetadataFailureKeepsBothCopiesForRetry(root.resolve("app-only-retry"));
            System.out.println("PASS: " + checks + " local photo deletion checks");
        } finally { try (var files = Files.walk(root)) { for (Path file : files.sorted(Comparator.reverseOrder()).toList()) Files.deleteIfExists(file); } }
    }
    private static void removesBothCopiesAndEveryProjectReference(Path root) throws Exception {
        Fixture f = new Fixture(root); DownloadedPhoto one = f.photo("original.JPG", 11), two = f.photo("kept.JPG", 22);
        PhotoLiveProject a = f.store.create("A"), b = f.store.create("B");
        f.store.record(a.id, "1".repeat(64), one); f.store.record(a.id, "2".repeat(64), two); f.store.record(b.id, "3".repeat(64), one);
        String uri = f.gallery.publish(one); f.gallery.publish(two);
        var row = f.context.resolver.rows.values().stream().filter(item -> item.uri.equals(uri)).findFirst().orElseThrow(); row.name = "renamed.jpg"; row.path = "Pictures/Moved/";
        PhotoDeleteResult result = f.delete(List.of(one, one));
        check(result.total == 1 && result.deleted == 1 && result.failed == 0, "Duplicate selected paths have one successful terminal deletion");
        check(!one.file().exists() && two.file().isFile() && f.context.resolver.rows.size() == 1, "Only the selected private original and its moved/renamed owned public copy are removed");
        check(f.store.get(a.id).photoCount == 1 && f.store.get(b.id).photoCount == 0 && f.store.get(a.id).totalBytes == two.byteSize(), "Every project count and persisted byte total excludes the deleted source");
        PhotoLiveProjectStore restored = new PhotoLiveProjectStore(f.catalog.toFile(), f.originals.toFile());
        check(restored.list().size() == 2 && restored.get(a.id).photos.get(0).file().equals(two.file().getCanonicalFile()), "Catalog remains readable after unlink and cold reconstruction");
        try { result.deletedPhotos.clear(); throw new AssertionError("mutable result"); } catch (UnsupportedOperationException expected) { checks++; }
    }
    private static void appOnlyDeletionPreservesPublicCopiesAndAllowsExplicitReceive(Path root) throws Exception {
        Fixture f = new Fixture(root);
        String identity = "9".repeat(64);
        PhotoOriginalStore originals = new PhotoOriginalStore(f.originals.toFile());
        Path temporary = f.originals.resolve("receive.part"); Files.write(temporary, jpeg(67));
        DownloadedPhoto original = originals.commit(identity, temporary.toFile(), "camera-original.JPG");
        DownloadedPhoto effect = f.effect(original, "6".repeat(64), "Warm", 71), kept = f.photo("kept.JPG", 78);
        PhotoLiveProject first = f.store.create("First"), second = f.store.create("Second");
        f.store.record(first.id, identity, original); f.store.record(second.id, identity, original);
        f.store.record(second.id, "8".repeat(64), kept);
        f.gallery.publish(original); f.gallery.publish(effect);
        int publicCount = f.context.resolver.rows.size(), publicDeletes = f.context.resolver.deletes;
        // Even a public row moved to another owner cannot interfere with an app-only removal.
        for (var row : f.context.resolver.rows.values()) row.owner = "user.modified.owner";
        PhotoDeleteResult removed;
        try (PhotoLocalTasks.Lease ignored = PhotoLocalTasks.delete()) { removed = new PhotoAlbumDeletion(f.context, false).delete(List.of(original, effect, original)); }
        check(removed.deleted == 2 && removed.failed == 0 && removed.total == 2, "App-only batch merges duplicate selections and removes the original and its selected effect");
        check(!original.file().exists() && !effect.file().exists() && kept.file().isFile(), "App-only delete unlinks only the selected app files");
        check(f.context.resolver.rows.size() == publicCount && f.context.resolver.deletes == publicDeletes, "App-only deletion never queries ownership for deletion or removes a phone-album copy");
        check(f.store.get(first.id).photoCount == 0 && f.store.get(second.id).photoCount == 1, "App-only deletion removes every selected original project reference and retains other members");
        check(originals.find(identity, original.filename(), original.byteSize()) == null, "Completion index does not reuse a deliberately deleted app original");
        Files.write(temporary, jpeg(67)); DownloadedPhoto received = originals.commit(identity, temporary.toFile(), original.filename());
        check(received.file().isFile() && originals.find(identity, original.filename(), received.byteSize()) != null, "An explicit future receive safely recreates a deleted original without stale completion errors");
        check(f.context.resolver.rows.size() == publicCount && f.context.resolver.deletes == publicDeletes, "Receiving again does not remove the preserved phone-album copies");
    }
    private static void appOnlyMetadataFailureKeepsBothCopiesForRetry(Path root) throws Exception {
        Fixture f = new Fixture(root); DownloadedPhoto original = f.photo("original.JPG", 87);
        PhotoLiveProject project = f.store.create("Retry"); f.store.record(project.id, "7".repeat(64), original); f.gallery.publish(original);
        int publicCount = f.context.resolver.rows.size(), publicDeletes = f.context.resolver.deletes;
        Path blocker = f.catalog.resolve(project.id + ".project.part"); Files.createDirectories(blocker); Files.writeString(blocker.resolve("hold"), "test-owned");
        PhotoDeleteResult failed;
        try (PhotoLocalTasks.Lease ignored = PhotoLocalTasks.delete()) { failed = new PhotoAlbumDeletion(f.context, false).delete(List.of(original)); }
        check(failed.deleted == 0 && failed.failed == 1 && original.file().isFile(), "App-only metadata failure preserves its app source with an explicit per-file error");
        check(f.context.resolver.rows.size() == publicCount && f.context.resolver.deletes == publicDeletes, "App-only metadata failure leaves every phone-album copy untouched");
        Files.delete(blocker.resolve("hold")); Files.delete(blocker);
        PhotoDeleteResult retried;
        try (PhotoLocalTasks.Lease ignored = PhotoLocalTasks.delete()) { retried = new PhotoAlbumDeletion(f.context, false).delete(List.of(original)); }
        check(retried.deleted == 1 && retried.failed == 0 && !original.file().exists() && f.store.get(project.id).photoCount == 0, "App-only retry removes the app file and project member consistently");
        check(f.context.resolver.rows.size() == publicCount && f.context.resolver.deletes == publicDeletes, "Successful app-only retry still preserves all phone-album copies");
    }
    private static void providerFailureRetainsSourceAndSupportsPartialRetry(Path root) throws Exception {
        Fixture f = new Fixture(root); DownloadedPhoto good = f.photo("good.JPG", 32), protectedPhoto = f.photo("protected.JPG", 47);
        PhotoLiveProject p = f.store.create("Partial"); f.store.record(p.id, "a".repeat(64), good); f.store.record(p.id, "b".repeat(64), protectedPhoto);
        f.gallery.publish(good); String protectedUri = f.gallery.publish(protectedPhoto);
        var protectedRow = f.context.resolver.rows.values().stream().filter(item -> item.uri.equals(protectedUri)).findFirst().orElseThrow(); protectedRow.owner = "foreign.application";
        byte[] original = Files.readAllBytes(protectedPhoto.file().toPath());
        PhotoDeleteResult result = f.delete(List.of(good, protectedPhoto));
        check(result.total == 2 && result.deleted == 1 && result.failed == 1 && !result.failures.get(0).message.isEmpty(), "Mixed provider outcomes remain explicit per-file partial results");
        check(!good.file().exists() && Arrays.equals(original, Files.readAllBytes(protectedPhoto.file().toPath())), "Provider ownership failure never deletes its private source");
        check(f.store.get(p.id).photoCount == 1 && f.store.get(p.id).photos.get(0).file().equals(protectedPhoto.file().getCanonicalFile()), "Failed item retains project membership while successful membership is removed");
        protectedRow.owner = f.context.getPackageName(); PhotoDeleteResult retry = f.delete(List.of(protectedPhoto));
        check(retry.deleted == 1 && retry.failed == 0 && f.context.resolver.rows.isEmpty() && f.store.get(p.id).photoCount == 0, "A later ownership-correct retry completes locally without camera acquisition");
    }
    private static void removesInternalSourceReferencesWithExternalStorageAvailable(Path root) throws Exception {
        Fixture f = new Fixture(root); Path internal = f.context.getFilesDir().toPath().resolve("pictures/camera-album"); Files.createDirectories(internal);
        Path file = internal.resolve("internal-original.JPG"); Files.write(file, jpeg(27)); DownloadedPhoto photo = new DownloadedPhoto(file.toFile(), "internal-original.JPG");
        PhotoLiveProjectStore internalStore = new PhotoLiveProjectStore(f.catalog.toFile(), internal.toFile()); PhotoLiveProject project = internalStore.create("Internal");
        internalStore.record(project.id, "d".repeat(64), photo); f.gallery.publish(photo);
        PhotoDeleteResult result = f.delete(List.of(photo));
        check(result.deleted == 1 && result.failed == 0 && !Files.exists(file) && f.context.resolver.rows.isEmpty(), "An internal original deletes both copies even when external Pictures is available");
        check(internalStore.get(project.id).photoCount == 0 && f.store.get(project.id).photoCount == 0, "Internal-source cleanup removes every catalog entry rather than leaving a missing-source member");
    }
    private static void metadataFailureKeepsSourceAfterPublicDeletion(Path root) throws Exception {
        Fixture f = new Fixture(root); DownloadedPhoto photo = f.photo("source.JPG", 58); PhotoLiveProject p = f.store.create("Blocked"); f.store.record(p.id, "c".repeat(64), photo); f.gallery.publish(photo);
        Path blocked = f.catalog.resolve(p.id + ".project.part"); Files.createDirectories(blocked); Files.writeString(blocked.resolve("keep"), "occupied");
        PhotoDeleteResult failed = f.delete(List.of(photo));
        check(failed.failed == 1 && failed.deleted == 0 && photo.file().isFile() && f.context.resolver.rows.isEmpty(), "Failed project cleanup keeps the app source even after its public copy was deleted");
        Files.delete(blocked.resolve("keep")); Files.delete(blocked); check(f.store.get(p.id).photoCount == 1, "Committed membership survives failed project cleanup");
        PhotoDeleteResult retried = f.delete(List.of(photo));
        check(retried.deleted == 1 && retried.failed == 0 && !photo.file().exists() && f.store.get(p.id).photoCount == 0, "Retry tolerates the already-deleted public URI and commits private removal");
    }
    private static void rejectsForeignAndIncompleteFiles(Path root) throws Exception {
        Fixture f = new Fixture(root); Path foreign = root.resolve("foreign.JPG"); Files.write(foreign, jpeg(91));
        DownloadedPhoto incomplete = f.photo("incomplete.JPG", 17); Files.write(incomplete.file().toPath(), new byte[]{(byte) 255, (byte) 216, 1});
        PhotoDeleteResult result = f.delete(List.of(new DownloadedPhoto(foreign.toFile(), "foreign.JPG"), incomplete));
        check(result.failed == 2 && result.deleted == 0 && Files.isRegularFile(foreign) && incomplete.file().isFile(), "Foreign paths and incomplete input do not reach destructive provider/file operations");
        check(f.context.resolver.deletes == 0, "Rejected app files cause no system-gallery deletion");
    }
    private static void transferableReservationsExcludeQueuedMutations() throws Exception {
        PhotoLocalTasks.Lease saving = PhotoLocalTasks.use();
        try { PhotoLocalTasks.delete(); throw new AssertionError("active use ignored"); } catch (IOException expected) { checks++; }
        Thread completed = new Thread(saving::close); completed.start(); completed.join(); saving.close();
        try (PhotoLocalTasks.Lease deleting = PhotoLocalTasks.delete()) {
            try { PhotoLocalTasks.use(); throw new AssertionError("exclusive use ignored"); } catch (IOException expected) { checks++; }
            try { PhotoLocalTasks.delete(); throw new AssertionError("second delete ignored"); } catch (IOException expected) { checks++; }
        }
        try (PhotoLocalTasks.Lease usableAgain = PhotoLocalTasks.use()) { checks++; }
    }
    private static void effectsDeleteBeforeOriginalsAndFailuresProtectEveryAlias(Path root) throws Exception {
        Fixture f = new Fixture(root); DownloadedPhoto original = f.photo("DSC_1.JPG", 60), alias = f.photo("legacy-alias.JPG", 60), other = f.photo("DSC_2.JPG", 62);
        DownloadedPhoto effect = f.effect(original, "a".repeat(64), "Bluesky", 61);
        f.gallery.publish(original); f.gallery.publish(alias); String effectUri = f.gallery.publish(effect); f.gallery.publish(other);
        var row = f.context.resolver.rows.values().stream().filter(item -> item.uri.equals(effectUri)).findFirst().orElseThrow(); row.owner = "foreign.application";
        PhotoDeleteResult failed = f.delete(List.of(original, alias, effect, other));
        check(failed.deleted == 1 && failed.failed == 3 && !other.file().exists(), "An unrelated group deletes while a failed effect protects all original aliases");
        check(original.file().isFile() && alias.file().isFile() && effect.file().isFile() && f.context.resolver.rows.size() == 2, "Both private aliases and the original system-album copy remain usable after effect deletion fails");
        row.owner = f.context.getPackageName(); PhotoDeleteResult retry = f.delete(List.of(original, alias, effect));
        check(retry.deleted == 3 && retry.failed == 0 && f.context.resolver.rows.isEmpty(), "A corrected retry removes effects first and tolerates shared original publication URIs");
    }
    private static void effectOnlyKeepsTheOriginalAndUnselectedEffectsProtectIt(Path root) throws Exception {
        Fixture f = new Fixture(root); DownloadedPhoto original = f.photo("DSC_3.JPG", 70), effect = f.effect(original, "b".repeat(64), "Film", 71);
        String originalUri = f.gallery.publish(original); f.gallery.publish(effect);
        PhotoDeleteResult blocked = f.delete(List.of(original));
        check(blocked.deleted == 0 && blocked.failed == 1 && original.file().isFile() && f.context.resolver.rows.size() == 2, "A request omitting an existing dependent effect cannot orphan it");
        PhotoDeleteResult effectOnly = f.delete(List.of(effect));
        check(effectOnly.deleted == 1 && effectOnly.failed == 0 && original.file().isFile() && f.context.resolver.rows.size() == 1, "Effect-only deletion preserves the original in the app and in the system album");
        check(f.context.resolver.rows.values().iterator().next().uri.equals(originalUri), "The original retains its existing system-album URI");
        check(f.delete(List.of(original)).deleted == 1, "An original becomes removable after its effects are gone");
    }
    private static void failedStackedEffectProtectsItsImmediateInput(Path root) throws Exception {
        Fixture f = new Fixture(root); DownloadedPhoto original = f.photo("DSC_4.JPG", 80), parent = f.effect(original, "c".repeat(64), "First", 81), child = f.effect(parent, "d".repeat(64), "Second", 82);
        f.gallery.publish(original); f.gallery.publish(parent); String childUri = f.gallery.publish(child);
        var row = f.context.resolver.rows.values().stream().filter(item -> item.uri.equals(childUri)).findFirst().orElseThrow(); row.owner = "foreign.application";
        PhotoDeleteResult result = f.delete(List.of(original, parent, child));
        check(result.deleted == 0 && result.failed == 3 && original.file().isFile() && parent.file().isFile() && child.file().isFile(), "A failed old stacked effect preserves every immediate input and its original");
    }
    private static void wholeGroupDeletesBothPrivateEffectAliasesAndOnePublication(Path root, int sdk) throws Exception {
        Fixture f = new Fixture(root); Build.VERSION.SDK_INT = sdk;
        android.os.Environment.setPublicPicturesForTest(root.resolve("public/Pictures").toFile());
        DownloadedPhoto original = f.photo("DSC_5.JPG", 90), effect = f.effect(original, "e".repeat(64), "Shared", 91);
        Path internal = f.context.getFilesDir().toPath().resolve("pictures/camera-album"); Files.createDirectories(internal);
        Path copy = internal.resolve(effect.file().getName()); Files.copy(effect.file().toPath(), copy);
        DownloadedPhoto alias = new DownloadedPhoto(copy.toFile(), effect.filename());
        f.gallery.publish(original); String first = f.gallery.publish(effect), second = f.gallery.publish(alias);
        check(first.equals(second) && f.context.resolver.rows.size() == 2, "Two verified private effect aliases share one public version while the original remains separate");
        PhotoLiveProject project = f.store.create("Shared aliases"); f.store.record(project.id, "f".repeat(64), original);
        int before = f.context.resolver.deletes; PhotoDeleteResult result = f.delete(List.of(original, effect, alias));
        check(result.deleted == 3 && result.failed == 0 && !original.file().exists() && !effect.file().exists() && !alias.file().exists(), "Whole-group deletion removes the original and every selected private effect alias across both directories");
        check(f.context.resolver.rows.isEmpty() && f.context.resolver.deletes == before + 2, "The shared effect URI is deleted once, plus the one separate original URI");
        check(f.store.get(project.id).photoCount == 0, "The group deletion also removes its project reference");
    }
    private static final class Fixture {
        final Context context; final Path originals, catalog; final PhotoLiveGallery gallery; final PhotoLiveProjectStore store;
        Fixture(Path root) throws Exception {
            Build.VERSION.SDK_INT = 35; context = new Context(root.toFile()); originals = root.resolve("external/Pictures/camera-album"); catalog = context.getFilesDir().toPath().resolve("photo-live-projects");
            Files.createDirectories(originals); store = new PhotoLiveProjectStore(catalog.toFile(), originals.toFile()); gallery = new PhotoLiveGallery(context);
        }
        DownloadedPhoto photo(String name, int seed) throws IOException { File file = originals.resolve(name).toFile(); Files.write(file.toPath(), jpeg(seed)); return new DownloadedPhoto(file, name); }
        DownloadedPhoto effect(DownloadedPhoto source, String preset, String name, int seed) throws Exception {
            String sourceSha = PhotoOriginalStore.contentId(source.file());
            String key = java.util.HexFormat.of().formatHex(java.security.MessageDigest.getInstance("SHA-256").digest((sourceSha + "\n" + preset + "\n" + PhotoPresetRenderer.MODEL_VERSION).getBytes(java.nio.charset.StandardCharsets.UTF_8)));
            DownloadedPhoto effect = photo("effect-" + key + "__Effect.JPG", seed);
            Path records = context.getFilesDir().toPath().resolve("photo-preset-results"); Files.createDirectories(records);
            try (var output = new java.io.DataOutputStream(Files.newOutputStream(records.resolve(key + ".record")))) { output.writeInt(0x50424531); output.writeLong(effect.byteSize()); output.writeUTF(PhotoOriginalStore.contentId(effect.file())); }
            new PhotoPresetSources(context.getFilesDir(), context.getExternalFilesDir("Pictures")).bind(effect, source, preset, name, () -> false);
            return effect;
        }
        PhotoDeleteResult delete(List<DownloadedPhoto> photos) throws IOException { try (PhotoLocalTasks.Lease ignored = PhotoLocalTasks.delete()) { return new PhotoAlbumDeletion(context).delete(photos); } }
    }
    private static byte[] jpeg(int seed) { return new byte[]{(byte) 255, (byte) 216, (byte) seed, 1, 2, 3, (byte) 255, (byte) 217}; }
    private static void check(boolean condition, String message) { if (!condition) throw new AssertionError(message); checks++; }
}
