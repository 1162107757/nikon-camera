package cc.huevia.album;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.ColorSpace;
import android.media.ExifInterface;
import android.util.AtomicFile;
import cc.huevia.ncp.RawDevelopmentSettings;
import java.io.*;
import java.nio.file.Files;
import java.nio.file.StandardCopyOption;
import java.util.Locale;
import java.util.function.BooleanSupplier;

/** Worker-only bridge into the ordinary editor. Sensor bytes are retained, never edited. */
public final class RawEditorSource {
    private RawEditorSource() { }
    public static File retainOriginal(Context context, File source, String name, BooleanSupplier cancel) throws IOException {
        check(cancel);
        String sha = PhotoEditStore.hashFile(source), extension = PhotoSourceFormat.rawExtension(name);
        if (extension.isEmpty()) extension = "raw";
        File directory = new File(context.getFilesDir(), "raw-editor-sources");
        mkdir(directory);
        File target = new File(directory, sha + "." + extension);
        if (!target.exists()) copy(source, target, sha, cancel);
        check(cancel);
        if (!sha.equals(PhotoEditStore.hashFile(source)) || !sha.equals(PhotoEditStore.hashFile(target)))
            throw new IOException("RAW 原文件已变化，请重新选择。");
        return target;
    }
    public static DownloadedPhoto prepare(Context context, File source, String name, String owner, long date,
                                           BooleanSupplier cancel) throws IOException {
        check(cancel);if(source==null||!source.isFile()||source.length()<64||source.length()>1024L*1024*1024||Files.isSymbolicLink(source.toPath()))throw new IOException("RAW 原文件不可读取。");
        String sourceSha=PhotoEditStore.hashFile(source),identity=RawDeveloper.cacheIdentity(sourceSha,RawDevelopmentSettings.DEFAULT);
        String extension = PhotoSourceFormat.rawExtension(name);
        if (extension.isEmpty()) extension = "raw";
        String key = "raw-" + extension + "-" + sourceSha + "-" + identity;
        File pictures = new File(context.getFilesDir(), "pictures/camera-album"); mkdir(pictures);
        String filename = jpegName(name);
        File target = new File(pictures, key + "__" + filename), receipt = new File(pictures, key + ".raw-editor");
        if (target.isFile() && receipt.isFile()) {
            try (DataInputStream input = new DataInputStream(new FileInputStream(receipt))) {
                if (input.readInt() == 0x52454431 && sourceSha.equals(input.readUTF())
                        && identity.equals(input.readUTF()) && PhotoEditStore.hashFile(target).equals(input.readUTF())&&input.read()==-1) {
                    File kept=retainOriginal(context,source,name,cancel);if(!kept.getName().startsWith(sourceSha+"."))throw new IOException("RAW 原文件已变化。");
                    check(cancel); return new DownloadedPhoto(target, filename, "", "", date > 0 ? date : target.lastModified());
                }
            } catch (IOException invalid) { throw new IOException("RAW 编辑副本校验失败，请重新显影。", invalid); }
            throw new IOException("RAW 编辑副本来源不符，请重新显影。");
        }
        if (target.exists()) throw new IOException("RAW 编辑副本尚未核对，请重新显影。");
        RawDeveloper.inspect(source);check(cancel);File original=retainOriginal(context,source,name,cancel);
        RawDeveloper.Result result=RawDeveloper.develop(context,original,owner,RawDevelopmentSettings.DEFAULT,cancel,value->{});
        if(!sourceSha.equals(result.sourceSha)||!identity.equals(result.cacheIdentity))throw new IOException("RAW 原文件已变化，请重新选择。");
        File temporary = File.createTempFile("raw-editor-", ".part", pictures);
        Bitmap bitmap = null;
        try {
            BitmapFactory.Options options = new BitmapFactory.Options(); options.inScaled = false; options.inSampleSize = 1;
            options.inPreferredConfig = Bitmap.Config.ARGB_8888; options.inPreferredColorSpace = ColorSpace.get(ColorSpace.Named.SRGB);
            bitmap = BitmapFactory.decodeFile(result.workingFile.getPath(), options);
            if (bitmap == null || bitmap.getWidth() != result.info.width || bitmap.getHeight() != result.info.height)
                throw new IOException("无法读取完整 RAW 显影结果，未缩小图片。");
            check(cancel);
            try (FileOutputStream output = new FileOutputStream(temporary)) {
                if (!bitmap.compress(Bitmap.CompressFormat.JPEG, 100, output)) throw new IOException("RAW 编辑副本生成失败。");
                output.flush(); output.getFD().sync();
            }
            bitmap.recycle(); bitmap = null;
            writeMetadata(original, temporary, result.info);
            check(cancel);
            if (!result.sourceSha.equals(PhotoEditStore.hashFile(original)) || !result.workingSha.equals(PhotoEditStore.hashFile(result.workingFile)))
                throw new IOException("RAW 显影结果发生变化，请重试。");
            String sha = PhotoEditStore.hashFile(temporary);
            AtomicFile record = new AtomicFile(receipt); FileOutputStream stream = null;
            try {
                stream = record.startWrite(); DataOutputStream output = new DataOutputStream(stream);
                output.writeInt(0x52454431); output.writeUTF(result.sourceSha); output.writeUTF(result.cacheIdentity); output.writeUTF(sha);
                output.flush(); stream.getFD().sync(); check(cancel); record.finishWrite(stream); stream = null;
            } finally { if (stream != null) record.failWrite(stream); }
            Files.move(temporary.toPath(), target.toPath(), StandardCopyOption.ATOMIC_MOVE);
            if (date > 0) target.setLastModified(date);
            PhotoArrivalDates.recordIfMissing(target);
            return new DownloadedPhoto(target, filename, "", "", date > 0 ? date : target.lastModified());
        } catch (OutOfMemoryError memory) { throw new IOException("完整 RAW 处理内存不足，请关闭其他应用后重试。", memory); }
        finally { if (bitmap != null) bitmap.recycle(); temporary.delete(); }
    }
    public static String jpegName(String rawName) {
        String name = rawName == null ? "RAW" : rawName.replaceAll("[\\p{Cntrl}\\\\/:*?\"<>|]", "_");
        int dot = name.lastIndexOf('.'); if (dot > 0) name = name.substring(0, dot);
        if (name.isBlank()) name = "RAW";
        return name.substring(0, Math.min(80, name.length())) + ".jpg";
    }
    /** Keep ordinary shooting/frame captions available; pixels are already oriented and converted to sRGB. */
    public static void writeMetadata(File original,File jpeg,RawDeveloper.Info info)throws IOException{
        ExifInterface output=new ExifInterface(jpeg.getPath());
        try{
            ExifInterface input=new ExifInterface(original.getPath());
            for(String tag:new String[]{"DateTimeOriginal","DateTimeDigitized","DateTime","SubSecTimeOriginal","OffsetTimeOriginal",
                    "ExposureTime","FNumber","ISOSpeedRatings","PhotographicSensitivity","FocalLength","FocalLengthIn35mmFilm",
                    "ExposureBiasValue","LensModel","Artist","Copyright"}){
                String value=input.getAttribute(tag);if(value!=null)output.setAttribute(tag,value);
            }
        }catch(IOException|RuntimeException unsupported){/* LibRaw may support a camera whose EXIF is unknown to Android. */}
        output.setAttribute(ExifInterface.TAG_ORIENTATION,"1");output.setAttribute("ColorSpace","1");
        output.setAttribute("Make",info.make);output.setAttribute("Model",info.model);output.saveAttributes();
    }
    private static void copy(File source, File target, String expectedSha, BooleanSupplier cancel) throws IOException {
        if (target.getParentFile().getUsableSpace() < source.length() + 16L * 1024 * 1024)
            throw new IOException("存储空间不足，无法保留 RAW 原文件。");
        File temporary = File.createTempFile("raw-source-", ".part", target.getParentFile());
        try {
            try (InputStream input = new FileInputStream(source); FileOutputStream output = new FileOutputStream(temporary)) {
                byte[] buffer = new byte[256 * 1024]; int n;
                while ((n = input.read(buffer)) != -1) { check(cancel); output.write(buffer, 0, n); }
                output.flush(); output.getFD().sync();
            }
            check(cancel);
            if(!expectedSha.equals(PhotoEditStore.hashFile(temporary))||!expectedSha.equals(PhotoEditStore.hashFile(source)))
                throw new IOException("读取期间 RAW 已变化，未保留不完整副本。");
            Files.move(temporary.toPath(), target.toPath(), StandardCopyOption.ATOMIC_MOVE);
        } finally { temporary.delete(); }
    }
    private static void mkdir(File directory) throws IOException { if (!directory.isDirectory() && !directory.mkdirs()) throw new IOException("RAW 工作目录不可用。"); }
    private static void check(BooleanSupplier cancel) throws IOException { if (Thread.currentThread().isInterrupted() || cancel != null && cancel.getAsBoolean()) throw new InterruptedIOException("RAW 编辑准备已取消。"); }
}
