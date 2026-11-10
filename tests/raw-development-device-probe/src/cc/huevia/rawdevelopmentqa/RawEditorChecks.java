package cc.huevia.rawdevelopmentqa;

import android.app.Activity;
import android.app.Instrumentation;
import android.content.ContentValues;
import android.content.Context;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.net.Uri;
import android.os.SystemClock;
import android.provider.MediaStore;
import android.view.View;
import android.view.ViewGroup;
import android.widget.TextView;
import java.io.*;
import java.lang.reflect.*;
import java.nio.file.Files;
import java.security.MessageDigest;
import java.util.*;
import java.util.function.BooleanSupplier;
import org.json.*;

/** The actual MediaStore RAW -> ordinary editor -> full-size renderer path, without a camera. */
public final class RawEditorChecks {
    private static final BooleanSupplier NEVER = () -> false;
    public static void run(RawDevelopmentProbe probe, Context context, File directory, JSONArray checks) throws Exception {
        ClassLoader loader = context.getClassLoader(); Class<?> sourceType = Class.forName("cc.huevia.album.RawEditorSource", true, loader);
        Class<?> formatType = Class.forName("cc.huevia.album.PhotoSourceFormat", true, loader), photoType = Class.forName("cc.huevia.album.DownloadedPhoto", true, loader);
        Class<?> repositoryType = Class.forName("cc.huevia.album.LocalPhotoRepository", true, loader), editorType = Class.forName("cc.huevia.ui.PhotoFilterEditor", true, loader);
        String owner = (String) editorType.getMethod("accountOwner", Context.class).invoke(null, context), nonce = UUID.randomUUID().toString();
        File source = new File(directory, "RAW179-" + nonce + ".dng"); SyntheticDng.write(source, 384, 256, 1);
        // A unique sensor pixel makes cleanup independent of all prior test runs.
        try (RandomAccessFile unique = new RandomAccessFile(source, "rw")) { unique.seek(source.length()-2); unique.writeShort(nonce.hashCode() & 0x0fff); }
        String rawSha = sha(source); Uri media = null; Activity activity = null; Object photo = null, developed = null;
        Set<File> cleanup = new LinkedHashSet<>();
        try {
            ContentValues values = new ContentValues(); values.put(MediaStore.Images.Media.DISPLAY_NAME, source.getName());
            values.put(MediaStore.Images.Media.MIME_TYPE, "image/x-adobe-dng"); values.put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/Huevia-QA179/");
            media = context.getContentResolver().insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values);
            check(checks, "actual-MediaStore-RAW-fixture-created", media != null);
            try (OutputStream output = context.getContentResolver().openOutputStream(media); InputStream input = new FileInputStream(source)) { input.transferTo(output); }
            Object repository = repositoryType.getConstructor(Context.class).newInstance(context);
            Object selected = repositoryType.getMethod("describe", Uri.class).invoke(repository, media);
            check(checks, "RAW-description-accepted", (Boolean) invoke(selected, "raw"));
            Object page = repositoryType.getMethod("phonePage", int.class, int.class).invoke(repository, 0, 120);
            boolean present = false; for (Object item : (List<?>) get(page, "photos")) present |= media.equals(get(item, "uri"));
            check(checks, "RAW-visible-in-real-phone-query", present);
            photo = repositoryType.getMethod("importPhoto", selected.getClass(), String.class, BooleanSupplier.class).invoke(repository, selected, owner, NEVER);
            File jpeg = (File) invoke(photo, "file"); cleanup.add(jpeg);
            String key = jpeg.getName().substring(0, jpeg.getName().indexOf("__")); cleanup.add(new File(jpeg.getParentFile(), key + ".raw-editor"));
            cleanup.add(new File(context.getFilesDir(), "raw-editor-sources/" + rawSha + ".dng"));
            Class<?> developer = Class.forName("cc.huevia.album.RawDeveloper", true, loader), settings = Class.forName("cc.huevia.ncp.RawDevelopmentSettings", true, loader);
            developed = developer.getMethod("develop", Context.class, File.class, String.class, settings, BooleanSupplier.class, java.util.function.DoubleConsumer.class)
                    .invoke(null, context, source, owner, settings.getField("DEFAULT").get(null), NEVER, null);
            File png = (File) get(developed, "workingFile"); cleanup.add(png); cleanup.add(new File(png.getPath().replace(".png", ".record")));
            check(checks, "original-RAW-bytes-unchanged", rawSha.equals(sha(source)));
            check(checks, "private-sensor-original-retained-exactly", rawSha.equals(sha(new File(context.getFilesDir(), "raw-editor-sources/"+rawSha+".dng"))));
            check(checks, "working-source-is-full-size-JPEG", dimensions(jpeg, 384, 256));
            check(checks, "source-format-survives-working-JPEG", "DNG".equals(formatType.getMethod("label", photoType).invoke(null, photo)));
            String jpegSha = sha(jpeg); long timestamp = jpeg.lastModified();
            File drafts=new File(context.getFilesDir(),"photo-edit-drafts/"+hash(owner.getBytes(java.nio.charset.StandardCharsets.UTF_8)));
            for(String suffix:new String[]{".draft",".draft.bak",".draft.new"})cleanup.add(new File(drafts,jpegSha+suffix));
            Object repeated = sourceType.getMethod("prepare", Context.class, File.class, String.class, String.class, long.class, BooleanSupplier.class)
                    .invoke(null, context, source, source.getName(), owner, 0L, NEVER);
            check(checks, "reopen-reuses-verified-workspace", jpeg.equals(invoke(repeated,"file")) && jpegSha.equals(sha(jpeg)) && timestamp == jpeg.lastModified());
            boolean cancelled = false;
            try { sourceType.getMethod("prepare",Context.class,File.class,String.class,String.class,long.class,BooleanSupplier.class).invoke(null,context,source,source.getName(),owner,0L,(BooleanSupplier)()->true); }
            catch (InvocationTargetException expected) { cancelled = expected.getCause() instanceof InterruptedIOException; }
            check(checks,"pre-cancelled-import-stops-without-rewriting",cancelled && jpegSha.equals(sha(jpeg)));
            activity = probe.startActivitySync(new Intent().setClassName("cc.huevia","cc.huevia.MainActivity").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)); final Activity host = activity;
            until(probe, () -> Boolean.TRUE.equals(get(host,"ready")), "main-ready", checks);
            final Object opened = photo;
            ui(probe, () -> call(host,"openLocalPhoto",new Class<?>[]{photoType},opened));
            until(probe, () -> editor(host)!=null && Boolean.TRUE.equals(get(editor(host),"ready")) && get(editor(host),"current")!=null,"RAW-bound-to-ordinary-ready-editor",checks);
            Object editor = editor(host); check(checks,"RAW-editor-does-not-lock-tools",!(Boolean)get(editor,"unrecoverableSaved"));
            TextView format = (TextView) host.getWindow().getDecorView().findViewWithTag("editor-source-format");
            check(checks,"editor-small-DNG-format-visible",format!=null && format.isShown() && format.getText().toString().equals("DNG · 编辑照片"));
            check(checks,"editor-format-single-line-and-fits",format.getLineCount()==1 && format.getPaint().measureText(format.getText().toString())<=format.getWidth()+1 && format.getTextSize()/format.getResources().getDisplayMetrics().scaledDensity<=10.1);
            capture(probe,"raw-editor.png");
            ui(probe,()->call(editor,"setAdjustmentMode",new Class<?>[]{boolean.class},true));
            Class<?> adjustments = Class.forName("cc.huevia.ncp.PhotoAdjustments",true,loader), parameter=Class.forName("cc.huevia.ncp.PhotoAdjustments$Parameter",true,loader);
            @SuppressWarnings({"rawtypes","unchecked"}) Object exposure=Enum.valueOf((Class)parameter,"EXPOSURE");
            Object manual=adjustments.getMethod("with",parameter,int.class).invoke(get(editor,"adjustments"),exposure,10);
            ui(probe,()->{check(checks,"RAW-basic-adjustment-accepted",(Boolean)call(editor,"setEditingAdjustments",new Class<?>[]{adjustments},manual));call(editor,"edited",new Class<?>[]{});});
            until(probe,()->get(editor,"current")!=null && get(editor,"adjustments").equals(manual),"RAW-adjustment-state-applied",checks);
            Class<?> profileType=Class.forName("cc.huevia.ncp.PresetPreviewProfile",true,loader),rendererType=Class.forName("cc.huevia.album.PhotoPresetRenderer",true,loader),progressType=Class.forName("cc.huevia.album.PhotoPresetRenderer$Progress",true,loader);
            Object profile=call(editor,"currentProfile",new Class<?>[]{}),renderer=rendererType.getMethod("forContext",Context.class).invoke(null,context);
            File exported=new File(directory,"raw-edited-export.jpg");
            rendererType.getMethod("render",File.class,File.class,profileType,BooleanSupplier.class,progressType).invoke(renderer,jpeg,exported,profile,NEVER,null);
            check(checks,"RAW-adjustment-full-size-export",dimensions(exported,384,256) && !sha(exported).equals(jpegSha));
            check(checks,"RAW-export-preserves-sensor-and-working-source",rawSha.equals(sha(source))&&jpegSha.equals(sha(jpeg)));
            for (String tool : new String[]{"showPalette","showCleanup","showComposition","showDetails","showExport"}) {
                ui(probe,()->call(editor,tool,new Class<?>[]{}));
                until(probe,()->get(editor,tool.equals("showDetails")?"detailDialog":"popup")!=null,"RAW-opens-"+tool,checks);
                ui(probe,()->call(editor,"dismissPopup",new Class<?>[]{}));
            }
            for(boolean curves:new boolean[]{true,false}) {ui(probe,()->call(editor,"showColor",new Class<?>[]{boolean.class},curves));until(probe,()->get(editor,"popup")!=null,curves?"RAW-curves-available":"RAW-HSL-available",checks);ui(probe,()->call(editor,"dismissPopup",new Class<?>[]{}));}
            capture(probe,"raw-adjustments.png");
            // Return to the real application album and inspect the thumbnail marker, without opening another design fixture.
            Object panel=get(host,"localPhotoEditor"); ui(probe,()->{call(panel,"goBack",new Class<?>[]{});call(host,"render",new Class<?>[]{});call(get(host,"localAlbum"),"refresh",new Class<?>[]{});});
            until(probe,()->host.getWindow().getDecorView().findViewWithTag("photo-source-format")!=null,"actual-album-format-marker-visible",checks);
            List<View> badges=new ArrayList<>(); collect(host.getWindow().getDecorView(),"photo-source-format",badges); boolean rawBadge=false;
            for(View view:badges){TextView badge=(TextView)view;if("DNG".equals(badge.getText().toString()))rawBadge=true;check(checks,"small-format-label-bounded",badge.getLineCount()==1&&badge.getWidth()<=badge.getResources().getDisplayMetrics().density*60&&badge.getHeight()<=badge.getResources().getDisplayMetrics().density*32);}
            check(checks,"album-shows-source-DNG-label",rawBadge); capture(probe,"raw-album.png");
            slotManager(probe,host,loader,checks);
            Intent direct=new Intent().setClassName("cc.huevia","cc.huevia.RawDevelopActivity")
                    .putExtra("raw_source_path",source.getPath()).putExtra("raw_source_sha",rawSha).putExtra("raw_owner",owner).putExtra("raw_edit_directly",true);
            ui(probe,()->host.startActivityForResult(direct,7319));
            until(probe,()->{Object e=editor(host);if(e==null||!(Boolean)get(e,"ready"))return false;Object bound=get(e,"bound");return bound!=null&&!jpeg.equals(invoke(bound,"file"));},"RAW-camera-entry-auto-reaches-full-editor",checks);
            Object directPhoto=get(editor(host),"bound");File directJpeg=(File)invoke(directPhoto,"file");cleanup.add(directJpeg);
            String directKey=directJpeg.getName().substring(0,directJpeg.getName().indexOf("__"));cleanup.add(new File(context.getFilesDir(),"local-photo-sources/"+directKey+".raw-development"));
            check(checks,"RAW-auto-handoff-keeps-source-name-and-format",sourceType.getMethod("jpegName",String.class).invoke(null,source.getName()).equals(invoke(directPhoto,"filename"))&&"DNG".equals(formatType.getMethod("label",photoType).invoke(null,directPhoto)));
            capture(probe,"raw-camera-entry.png");
            check(checks,"source-preserved-after-all-editor-actions",rawSha.equals(sha(source)));
        } finally {
            if(activity!=null){final Activity host=activity;ui(probe,host::finish);SystemClock.sleep(350);}
            if(media!=null)context.getContentResolver().delete(media,null,null);
            for(File file:cleanup)Files.deleteIfExists(file.toPath());
        }
    }
    private static Object editor(Activity host)throws Exception{Object panel=get(host,"localPhotoEditor");return panel==null?null:get(panel,"filterEditor");}
    private static void slotManager(RawDevelopmentProbe probe,Activity host,ClassLoader loader,JSONArray checks)throws Exception{
        Class<?> snapshotType=Class.forName("cc.huevia.usb.UsbPictureControlProbe$Result",true,loader),itemType=Class.forName("cc.huevia.usb.UsbPictureControlProbe$ItemRecord",true,loader);
        Class<?> connectionType=Class.forName("cc.huevia.MainActivity$CameraConnection",true,loader),wirelessType=Class.forName("cc.huevia.usb.WirelessPictureControl",true,loader);
        Constructor<?> constructor=connectionType.getDeclaredConstructor(String.class,int.class,wirelessType);constructor.setAccessible(true);
        Object connection=constructor.newInstance("127.0.0.1",15740,null),snapshot=snapshotType.getConstructor().newInstance();
        snapshotType.getField("model").set(snapshot,"QA Nikon");snapshotType.getField("operations").set(snapshot,new int[]{0x90ce});List<Object> slots=new ArrayList<>();
        for(int item=201;item<=209;item++){
            byte[] bytes=new byte[item==207?614:36];if(item==207){bytes[0]=1;byte[] title="QA delete".getBytes(java.nio.charset.StandardCharsets.US_ASCII);System.arraycopy(title,0,bytes,2,title.length);byte[] parameters={0,0,0,12,8,0,0,0,0,0,0,0,0,1};System.arraycopy(parameters,0,bytes,22,parameters.length);bytes[36]=0x49;bytes[37]=0x30;for(int i=0;i<=256;i++){int value=Math.min(i*256,65535);bytes[100+i*2]=(byte)(value>>>8);bytes[101+i*2]=(byte)value;}}
            Constructor<?> recordConstructor=itemType.getDeclaredConstructor(int.class,byte[].class);recordConstructor.setAccessible(true);Object record=recordConstructor.newInstance(item,bytes);itemType.getField("parsed").set(record,true);itemType.getField("empty").set(record,item!=207);itemType.getField("registrationName").set(record,item==207?"QA delete":"");slots.add(record);
        }
        ui(probe,()->call(host,"showCameraSlots",new Class<?>[]{connectionType,snapshotType,List.class},connection,snapshot,slots));
        android.app.AlertDialog manager=(android.app.AlertDialog)get(host,"slotManagerDialog");check(checks,"native-slot-manager-visible",manager.isShowing());
        capture(probe,"slot-manager.png");View label=findText(manager.getWindow().getDecorView(),"C7 · QA delete");check(checks,"native-slot-label-matches-target-and-name",label!=null);
        ui(probe,()->{View hit=label;while(hit!=null&&!hit.isClickable())hit=hit.getParent() instanceof View?(View)hit.getParent():null;if(hit==null)throw new AssertionError("no slot action");hit.performClick();});
        android.app.AlertDialog confirm=(android.app.AlertDialog)get(host,"slotDeleteDialog");check(checks,"native-delete-confirmation-visible",confirm!=null&&confirm.isShowing());
        check(checks,"native-delete-confirmation-names-exact-slot",findText(confirm.getWindow().getDecorView(),"删除 C7？")!=null);
        check(checks,"native-delete-explicit-action-and-cancel",confirm.getButton(android.content.DialogInterface.BUTTON_POSITIVE)!=null&&confirm.getButton(android.content.DialogInterface.BUTTON_NEGATIVE)!=null);
        capture(probe,"slot-confirmation.png");ui(probe,()->confirm.getButton(android.content.DialogInterface.BUTTON_NEGATIVE).performClick());check(checks,"native-delete-cancel-closes-without-task",!confirm.isShowing()&&get(host,"activeSlotDelete")==null);
    }
    private static View findText(View v,String text){if(v instanceof TextView&&text.contentEquals(((TextView)v).getText()))return v;if(v instanceof ViewGroup)for(int i=0;i<((ViewGroup)v).getChildCount();i++){View found=findText(((ViewGroup)v).getChildAt(i),text);if(found!=null)return found;}return null;}
    private static Object get(Object owner,String name)throws Exception{Field f=owner.getClass().getDeclaredField(name);f.setAccessible(true);return f.get(owner);}
    private static Object invoke(Object owner,String name)throws Exception{return call(owner,name,new Class<?>[]{});}
    private static Object call(Object owner,String name,Class<?>[] types,Object...args)throws Exception{Method m=owner.getClass().getDeclaredMethod(name,types);m.setAccessible(true);try{return m.invoke(owner,args);}catch(InvocationTargetException e){Throwable cause=e.getCause();if(cause instanceof Exception)throw(Exception)cause;throw new RuntimeException(cause);}}
    private interface Work{void run()throws Exception;}private interface Condition{boolean test()throws Exception;}
    private static void ui(Instrumentation probe,Work work)throws Exception{Throwable[] error={null};probe.runOnMainSync(()->{try{work.run();}catch(Throwable e){error[0]=e;}});if(error[0]!=null)throw new Exception(error[0]);probe.waitForIdleSync();}
    private static void until(Instrumentation p,Condition condition,String name,JSONArray checks)throws Exception{long end=SystemClock.uptimeMillis()+15000;while(SystemClock.uptimeMillis()<end){p.waitForIdleSync();try{if(condition.test()){check(checks,name,true);return;}}catch(Exception ignored){}SystemClock.sleep(30);}check(checks,name,false);}
    private static void check(JSONArray checks,String name,boolean pass)throws Exception{checks.put(new JSONObject().put("name",name).put("passed",pass));if(!pass)throw new AssertionError(name);}
    private static boolean dimensions(File file,int width,int height){BitmapFactory.Options o=new BitmapFactory.Options();o.inJustDecodeBounds=true;BitmapFactory.decodeFile(file.getPath(),o);return o.outWidth==width&&o.outHeight==height&&"image/jpeg".equals(o.outMimeType);}
    private static void collect(View view,String tag,List<View> found){if(tag.equals(view.getTag())&&view.isShown())found.add(view);if(view instanceof ViewGroup)for(int i=0;i<((ViewGroup)view).getChildCount();i++)collect(((ViewGroup)view).getChildAt(i),tag,found);}
    private static String sha(File file)throws Exception{return hash(Files.readAllBytes(file.toPath()));}
    private static String hash(byte[] bytes)throws Exception{byte[] hash=MessageDigest.getInstance("SHA-256").digest(bytes);StringBuilder s=new StringBuilder();for(byte b:hash)s.append(String.format(Locale.ROOT,"%02x",b&255));return s.toString();}
    private static void capture(RawDevelopmentProbe p,String name)throws Exception{p.waitForIdleSync();Bitmap bitmap=p.getUiAutomation().takeScreenshot();try(FileOutputStream out=new FileOutputStream(new File(p.output,name))){if(bitmap==null||!bitmap.compress(Bitmap.CompressFormat.PNG,100,out))throw new IOException("Screenshot failed");}finally{if(bitmap!=null)bitmap.recycle();}}
}
