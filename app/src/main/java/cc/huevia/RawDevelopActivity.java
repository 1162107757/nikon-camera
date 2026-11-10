package cc.huevia;

import cc.huevia.ui.AppDialog;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Context;
import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.content.res.ColorStateList;
import android.content.res.Configuration;
import android.database.Cursor;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Color;
import android.graphics.ColorSpace;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.RippleDrawable;
import android.graphics.drawable.StateListDrawable;
import android.media.ExifInterface;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.provider.OpenableColumns;
import android.view.Gravity;
import android.view.View;
import android.view.Window;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.ScrollView;
import android.widget.SeekBar;
import android.widget.TextView;
import cc.huevia.album.PhotoEditStore;
import cc.huevia.album.RawDeveloper;
import cc.huevia.ncp.RawDevelopmentSettings;
import cc.huevia.ui.AppIcon;
import cc.huevia.ui.PhotoFilterEditor;
import cc.huevia.ui.PhotoGlassDrawable;
import cc.huevia.ui.PhotoImageView;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.io.RandomAccessFile;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Locale;
import java.util.UUID;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

/** Explicit full RAW development. Original sensor files are read-only; handoff is an 8-bit JPEG copy. */
public final class RawDevelopActivity extends Activity {
    public static final String EXTRA_EDIT_DIRECTLY="raw_edit_directly", EXTRA_SOURCE_NAME="raw_source_name";
    public static final String EXTRA_SOURCE_PATH="raw_source_path",EXTRA_OWNER="raw_owner",EXTRA_SOURCE_SHA="raw_source_sha";
    public static final String EXTRA_DEVELOPED_JPEG_PATH="raw_developed_jpeg_path",EXTRA_RAW_SHA="raw_developed_source_sha",EXTRA_JPEG_SHA="raw_developed_jpeg_sha",EXTRA_WORKING_IDENTITY="raw_developed_working_identity";
    private static final int PICK_RAW=7311,SAVE_PNG=7312,BG=0xff0a0908,TEXT=0xfff6f1eb,MUTED=0xffc3b9af,ACCENT=0xfff2b48c;
    private static final long MAX_SOURCE=1024L*1024*1024;
    private final Handler main=new Handler(Looper.getMainLooper());
    private final AtomicInteger generation=new AtomicInteger();
    private final ThreadPoolExecutor worker=new ThreadPoolExecutor(1,1,0,TimeUnit.SECONDS,new ArrayBlockingQueue<>(1),r->{Thread t=new Thread(r,"raw-development-ui");t.setDaemon(true);return t;},new ThreadPoolExecutor.DiscardOldestPolicy());
    private final List<File> ownedInputs=Collections.synchronizedList(new ArrayList<>());
    private final List<File> pendingHandoffs=Collections.synchronizedList(new ArrayList<>());
    private final ArrayList<PhotoGlassDrawable> glasses=new ArrayList<>();
    private String owner="",displayName="",sourceSha="",expectedSourceSha="";
    private File source;
    private long sourceLength,sourceModified;
    private RawDevelopmentSettings settings=RawDevelopmentSettings.DEFAULT,appliedSettings;
    private RawDeveloper.Info info;
    private RawDeveloper.Result result,pendingSave;
    private Bitmap preview;
    private PhotoImageView image;
    private TextView filename,metric,status,exposureValue,temperatureValue,tintValue;
    private Button whiteBalance,highlights,quality,colorMode,save,edit;
    private ProgressBar progress;
    private SeekBar exposure,temperature,tint,tracking;
    private LinearLayout customWhiteBalance;
    private boolean updating,busy,picking,transferring,paused;
    private volatile boolean destroyed;
    private final Runnable develop=this::develop;
    private final Runnable validity=new Runnable(){public void run(){if(destroyed||paused)return;if(!owner.equals(PhotoFilterEditor.accountOwner(RawDevelopActivity.this))){cancelCurrent();finish();return;}if(source!=null&&(!source.isFile()||source.length()!=sourceLength||source.lastModified()!=sourceModified)){cancelCurrent();result=null;info=null;source=null;clearPreview();refreshInfo();setBusy(false,"");message("RAW 原文件已变化，请重新选择。",true);}main.postDelayed(this,750);}};
    public static Intent intent(Context context,File source,String owner){Intent intent=new Intent(context,RawDevelopActivity.class);if(source!=null)intent.putExtra(EXTRA_SOURCE_PATH,source.getAbsolutePath());intent.putExtra(EXTRA_OWNER,owner==null?"":owner);return intent;}
    @Override public void onCreate(Bundle saved){
        setTheme(R.style.AppThemeDark);super.onCreate(saved);owner=getIntent().hasExtra(EXTRA_OWNER)?getIntent().getStringExtra(EXTRA_OWNER):PhotoFilterEditor.accountOwner(this);if(owner==null)owner="";
        if(saved!=null){displayName=saved.getString("name","");expectedSourceSha=saved.getString("expectedSha","");restoreSettings(saved);}
        buildUi();if(!owner.equals(PhotoFilterEditor.accountOwner(this))){finish();return;}
        String path=saved==null?getIntent().getStringExtra(EXTRA_SOURCE_PATH):saved.getString("source",null);if(saved==null)expectedSourceSha=getIntent().getStringExtra(EXTRA_SOURCE_SHA);if(expectedSourceSha==null)expectedSourceSha="";
        if(path!=null){try{source=checkedSource(new File(path));if(displayName.isEmpty())displayName=source.getName();rememberSourceStat();if(isOwnedInputDirectory(source.getParentFile()))ownedInputs.add(source.getParentFile());inspect();}catch(IOException invalid){source=null;message(invalid.getMessage(),true);}}
        else if(saved==null&&getIntent().getData()!=null)readUri(getIntent().getData(),getIntent().getFlags());
        else if(saved==null)main.post(this::pickRaw);
    }
    private void buildUi(){
        for(PhotoGlassDrawable glass:glasses)glass.close();glasses.clear();if(image!=null)image.setPhoto(null);
        boolean landscape=getResources().getConfiguration().orientation==Configuration.ORIENTATION_LANDSCAPE;
        Window window=getWindow();
        // Android 16's PhoneWindow requires a DecorView before getInsetsController().
        View decor=window.getDecorView();
        window.setStatusBarColor(BG);window.setNavigationBarColor(BG);
        window.addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS);
        if(Build.VERSION.SDK_INT>=29){window.setStatusBarContrastEnforced(false);window.setNavigationBarContrastEnforced(false);}
        if(Build.VERSION.SDK_INT>=30){
            window.setDecorFitsSystemWindows(false);
            WindowInsetsController controls=window.getInsetsController();
            if(controls!=null)controls.setSystemBarsAppearance(0,WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS|WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS);
        }else decor.setSystemUiVisibility(View.SYSTEM_UI_FLAG_LAYOUT_STABLE|View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN|View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION);
        FrameLayout page=new FrameLayout(this);page.setTag("raw-development-page");page.setBackgroundColor(BG);page.setOnApplyWindowInsetsListener((v,insets)->{if(Build.VERSION.SDK_INT>=30){android.graphics.Insets safe=insets.getInsets(WindowInsets.Type.systemBars()|WindowInsets.Type.displayCutout());v.setPadding(safe.left,safe.top,safe.right,safe.bottom);}else v.setPadding(insets.getSystemWindowInsetLeft(),insets.getSystemWindowInsetTop(),insets.getSystemWindowInsetRight(),insets.getSystemWindowInsetBottom());return insets;});
        FrameLayout stage=new FrameLayout(this);FrameLayout.LayoutParams sp=new FrameLayout.LayoutParams(-1,-1);if(landscape)sp.rightMargin=dp(280);page.addView(stage,sp);image=new PhotoImageView(this);image.setTag("raw-development-image");image.setPlaceholderText("选择 NEF / DNG");image.setOnPhotoTransformChanged(this::refreshGlass);stage.addView(image,new FrameLayout.LayoutParams(-1,-1));if(preview!=null&&!preview.isRecycled())image.setPhoto(preview);
        LinearLayout header=row();header.setPadding(dp(8),0,dp(8),0);header.setBackground(new GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM,new int[]{0xb0000000,0x00000000}));Button back=button("",this::finish);AppIcon backIcon=new AppIcon(AppIcon.Kind.BACK,TEXT,density());backIcon.setBounds(0,0,dp(22),dp(22));back.setCompoundDrawables(backIcon,null,null,null);back.setContentDescription("返回，保留 RAW 原文件");header.addView(back,new LinearLayout.LayoutParams(dp(44),dp(48)));LinearLayout names=column();names.setGravity(Gravity.CENTER);TextView title=text("RAW 显影",13,TEXT);title.setTypeface(Typeface.create("sans-serif-medium",Typeface.NORMAL));names.addView(title);filename=text(displayName,11,MUTED);filename.setSingleLine(true);filename.setEllipsize(android.text.TextUtils.TruncateAt.MIDDLE);filename.setGravity(Gravity.CENTER);names.addView(filename,new LinearLayout.LayoutParams(-1,dp(20)));header.addView(names,new LinearLayout.LayoutParams(0,dp(48),1));Button choose=button("选择",this::pickRaw);choose.setTag("raw-development-choose");header.addView(choose,new LinearLayout.LayoutParams(dp(52),dp(48)));stage.addView(header,new FrameLayout.LayoutParams(-1,dp(52),Gravity.TOP));
        metric=text("",11,TEXT);metric.setTag("raw-development-metric");metric.setPadding(dp(10),0,dp(10),0);metric.setGravity(Gravity.CENTER);metric.setSingleLine(true);glass(metric,12);FrameLayout.LayoutParams mp=new FrameLayout.LayoutParams(-2,dp(30),Gravity.TOP|Gravity.END);mp.topMargin=dp(62);mp.rightMargin=dp(12);stage.addView(metric,mp);
        LinearLayout controls=column();controls.setTag("raw-development-controls");controls.setPadding(dp(8),dp(8),dp(8),dp(8));if(landscape)controls.setBackgroundColor(0xff181614);else glass(controls,20);
        ScrollView scroll=new ScrollView(this);scroll.setFillViewport(false);LinearLayout body=column();scroll.addView(body,new ScrollView.LayoutParams(-1,-2));controls.addView(scroll,landscape?new LinearLayout.LayoutParams(-1,0,1):new LinearLayout.LayoutParams(-1,-2));
        LinearLayout choices=row();colorMode=button("",this::chooseColorMode);colorMode.setTag("raw-development-color");whiteBalance=button("",this::chooseWhiteBalance);whiteBalance.setTag("raw-development-wb");highlights=button("",this::chooseHighlights);highlights.setTag("raw-development-highlights");quality=button("",this::chooseQuality);quality.setTag("raw-development-demosaic");Button[] options={colorMode,whiteBalance,highlights,quality};float[] optionWidths={1.05f,1.05f,1.3f,.6f};for(int i=0;i<options.length;i++){Button button=options[i];button.setTextSize(12);button.setSingleLine(true);button.setPadding(dp(4),0,dp(4),0);choices.addView(button,new LinearLayout.LayoutParams(0,dp(44),optionWidths[i]));}body.addView(choices);
        exposure=new SeekBar(this);exposure.setMax(100);exposure.setTag("raw-development-exposure");exposureValue=parameterRow(body,"曝光",exposure);exposure.setContentDescription("RAW 曝光，负5到正5EV");
        customWhiteBalance=column();temperature=new SeekBar(this);temperature.setMax(100);temperature.setTag("raw-development-temperature");temperatureValue=parameterRow(customWhiteBalance,"色温",temperature);temperature.setContentDescription("RAW 色温，2000到12000K");tint=new SeekBar(this);tint.setMax(200);tint.setTag("raw-development-tint");tintValue=parameterRow(customWhiteBalance,"色调",tint);tint.setContentDescription("RAW 色调，负100到正100");body.addView(customWhiteBalance);
        status=text("选择 RAW 原文件",11,MUTED);status.setTag("raw-development-status");status.setMaxLines(2);status.setPadding(dp(8),dp(4),dp(8),dp(6));status.setAccessibilityLiveRegion(View.ACCESSIBILITY_LIVE_REGION_POLITE);body.addView(status);
        progress=new ProgressBar(this,null,android.R.attr.progressBarStyleHorizontal);progress.setMax(100);progress.setProgressTintList(ColorStateList.valueOf(ACCENT));progress.setProgressBackgroundTintList(ColorStateList.valueOf(0x445c5148));progress.setVisibility(View.INVISIBLE);controls.addView(progress,new LinearLayout.LayoutParams(-1,dp(3)));
        LinearLayout actions=row();actions.setPadding(dp(4),dp(8),dp(4),dp(4));
        save=actionButton("保存 PNG",true,this::savePng);save.setTag("raw-development-save-png");
        edit=actionButton("编辑副本",false,this::editCopy);edit.setTag("raw-development-edit-copy");
        edit.setContentDescription("创建完整尺寸的8-bit sRGB JPEG副本，进入照片编辑");
        LinearLayout.LayoutParams saveLayout=new LinearLayout.LayoutParams(0,dp(48),1);saveLayout.rightMargin=dp(10);
        actions.addView(save,saveLayout);actions.addView(edit,new LinearLayout.LayoutParams(0,dp(48),1));controls.addView(actions);
        FrameLayout.LayoutParams panel=landscape?new FrameLayout.LayoutParams(dp(280),-1,Gravity.END):new FrameLayout.LayoutParams(-1,-2,Gravity.BOTTOM);if(!landscape){panel.leftMargin=dp(12);panel.rightMargin=dp(12);panel.bottomMargin=dp(12);}page.addView(controls,panel);setContentView(page);
        watch(exposure,()->settings=settings.withExposure(exposure.getProgress()-50));watch(temperature,()->settings=settings.withTemperature(2000+temperature.getProgress()*100));watch(tint,()->settings=settings.withTint(tint.getProgress()-100));refreshSettings();refreshInfo();updateActions();if(busy)setBusy(true,transferring?"保存中…":"显影中…");else if(result!=null&&settings.equals(appliedSettings))setBusy(false,result.colorStatus);
    }
    private TextView parameterRow(LinearLayout parent,String label,SeekBar slider){LinearLayout row=row();TextView caption=text(label,12,MUTED);row.addView(caption,new LinearLayout.LayoutParams(dp(38),dp(42)));caption.setGravity(Gravity.CENTER_VERTICAL);slider.setProgressTintList(ColorStateList.valueOf(ACCENT));slider.setThumbTintList(ColorStateList.valueOf(ACCENT));slider.setProgressBackgroundTintList(ColorStateList.valueOf(0x666b5b4b));row.addView(slider,new LinearLayout.LayoutParams(0,dp(42),1));TextView value=text("",11,TEXT);value.setGravity(Gravity.END|Gravity.CENTER_VERTICAL);row.addView(value,new LinearLayout.LayoutParams(dp(58),dp(42)));row.setPadding(dp(8),0,dp(8),0);parent.addView(row);return value;}
    private void watch(SeekBar slider,Runnable update){slider.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener(){public void onProgressChanged(SeekBar bar,int value,boolean user){if(!user||updating)return;update.run();refreshSettings();if(tracking!=bar)scheduleDevelop();else updateActions();}public void onStartTrackingTouch(SeekBar bar){tracking=bar;main.removeCallbacks(develop);}public void onStopTrackingTouch(SeekBar bar){tracking=null;scheduleDevelop();}});}
    private void refreshSettings(){updating=true;exposure.setProgress(settings.exposureTenths+50);temperature.setProgress((settings.temperatureKelvin-2000)/100);tint.setProgress(settings.tint+100);updating=false;exposureValue.setText(String.format(Locale.ROOT,"%+.1f EV",settings.exposureTenths/10.0));temperatureValue.setText(settings.temperatureKelvin+"K");tintValue.setText((settings.tint>0?"+":"")+settings.tint);colorMode.setText(settings.colorMode==RawDevelopmentSettings.ColorMode.CAMERA_JPEG?"相机色彩":"中性色彩");colorMode.setContentDescription("色彩还原，"+(settings.colorMode==RawDevelopmentSettings.ColorMode.CAMERA_JPEG?"相机 JPEG 色彩":"中性色彩"));whiteBalance.setText(settings.whiteBalance==RawDevelopmentSettings.WhiteBalance.CAMERA?"相机 WB":settings.whiteBalance==RawDevelopmentSettings.WhiteBalance.AUTO?"自动 WB":"自定义 WB");highlights.setText(settings.highlightMode==0?"高光·裁切":settings.highlightMode==2?"高光·混合":"高光·恢复");quality.setText(settings.demosaicQuality==3?"AHD":"线性");customWhiteBalance.setVisibility(settings.whiteBalance==RawDevelopmentSettings.WhiteBalance.CUSTOM?View.VISIBLE:View.GONE);refreshGlass();}
    private void chooseColorMode(){new AppDialog.Builder(this).setTitle("色彩还原")
            .setSingleChoiceItems(new String[]{"相机 JPEG 色彩（近似）","中性色彩"},settings.colorMode.ordinal(),(d,i)->{settings=settings.withColorMode(RawDevelopmentSettings.ColorMode.values()[i]);refreshSettings();scheduleDevelop();d.dismiss();}).setNegativeButton("取消",null).show();}
    private void chooseWhiteBalance(){String[] labels={"相机白平衡","自动白平衡","自定义色温／色调"};new AppDialog.Builder(this).setTitle("白平衡").setSingleChoiceItems(labels,settings.whiteBalance.ordinal(),(d,i)->{settings=settings.withWhiteBalance(RawDevelopmentSettings.WhiteBalance.values()[i]);refreshSettings();scheduleDevelop();d.dismiss();}).setNegativeButton("取消",null).show();}
    private void chooseHighlights(){String[] labels={"裁切","混合保留","重建恢复"};int current=settings.highlightMode==0?0:settings.highlightMode==2?1:2;new AppDialog.Builder(this).setTitle("高光处理").setSingleChoiceItems(labels,current,(d,i)->{settings=settings.withHighlights(new int[]{0,2,3}[i]);refreshSettings();scheduleDevelop();d.dismiss();}).setNegativeButton("取消",null).show();}
    private void chooseQuality(){new AppDialog.Builder(this).setTitle("去马赛克").setSingleChoiceItems(new String[]{"线性","AHD"},settings.demosaicQuality==3?1:0,(d,i)->{settings=settings.withDemosaicQuality(i==1?3:0);refreshSettings();scheduleDevelop();d.dismiss();}).setNegativeButton("取消",null).show();}
    private void pickRaw(){
        if(destroyed||transferring||picking)return;
        picking=true;
        Intent open=new Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("*/*")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION|Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION);
        try{startActivityForResult(open,PICK_RAW);}
        catch(ActivityNotFoundException missing){
            // Some phone systems disable DocumentsUI but still provide a content picker.
            Intent fallback=new Intent(Intent.ACTION_GET_CONTENT).addCategory(Intent.CATEGORY_OPENABLE).setType("*/*")
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            try{startActivityForResult(fallback,PICK_RAW);}
            catch(ActivityNotFoundException|SecurityException unavailable){documentPickerFailed(unavailable);}
        }catch(SecurityException denied){documentPickerFailed(denied);}
    }
    private void documentPickerFailed(RuntimeException failure){
        picking=false;
        pendingSave=null;
        message(failure instanceof SecurityException
                ?"系统拒绝打开文件选择器，请检查文件应用权限后重试。"
                :"无法打开系统文件选择器，请启用手机的“文件”应用后重试。",true);
    }
    @Override protected void onActivityResult(int requestCode,int resultCode,Intent data){super.onActivityResult(requestCode,resultCode,data);picking=false;if(resultCode!=RESULT_OK||data==null||data.getData()==null){pendingSave=null;return;}if(!owner.equals(PhotoFilterEditor.accountOwner(this))){finish();return;}if(requestCode==PICK_RAW)readUri(data.getData(),data.getFlags());else if(requestCode==SAVE_PNG){RawDeveloper.Result frozen=pendingSave;pendingSave=null;if(frozen!=null)writePng(frozen,data.getData());else message("保存状态已重置，请重新显影并选择位置。",true);}}
    private void readUri(Uri uri,int flags){
        if(uri==null)return;try{int granted=flags&(Intent.FLAG_GRANT_READ_URI_PERMISSION|Intent.FLAG_GRANT_WRITE_URI_PERMISSION);if((flags&Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)!=0)getContentResolver().takePersistableUriPermission(uri,granted);}catch(SecurityException ignored){}
        cancelCurrent();source=null;result=null;info=null;sourceSha="";expectedSourceSha="";clearPreview();refreshInfo();setBusy(true,"读取 RAW 文件…");int token=generation.get();File folder=new File(getCacheDir(),"raw-develop-input-"+UUID.randomUUID());ownedInputs.add(folder);
        worker.execute(()->{boolean accepted=false;try{check(token);if(!folder.mkdirs())throw new IOException("RAW 暂存目录不可用。");File file=new File(folder,"source.raw");String name=queryName(uri);try(InputStream in=getContentResolver().openInputStream(uri);FileOutputStream out=new FileOutputStream(file)){if(in==null)throw new IOException("无法读取所选文件。");byte[] buffer=new byte[256*1024];long count=0;int n;while((n=in.read(buffer))!=-1){check(token);count+=n;if(count>MAX_SOURCE)throw new IOException("RAW 文件超过 1 GB，无法在手机中处理。");out.write(buffer,0,n);}if(count==0)throw new IOException("所选文件为空。");out.flush();out.getFD().sync();}check(token);accepted=true;main.post(()->{if(!valid(token)){removeInput(folder);return;}source=file;displayName=name;rememberSourceStat();filename.setText(displayName);inspect();});}catch(Exception error){postError(token,error);}finally{if(!accepted)removeInput(folder);}});
    }
    private String queryName(Uri uri){try(Cursor cursor=getContentResolver().query(uri,new String[]{OpenableColumns.DISPLAY_NAME},null,null,null)){if(cursor!=null&&cursor.moveToFirst()){String name=cursor.getString(0);if(name!=null&&!name.trim().isEmpty())return name;}}catch(RuntimeException ignored){}return "RAW 原文件";}
    private void inspect(){
        if(source==null||destroyed)return;cancelCurrent();setBusy(true,"读取 RAW 参数…");final int token=generation.get();final File file=source;final String expected=expectedSourceSha;
        worker.execute(()->{try{check(token);if(!RawDeveloper.available())throw new IOException("此设备的 RAW 显影组件不可用。");String sha=PhotoEditStore.hashFile(file);if(!expected.isEmpty()&&!expected.equalsIgnoreCase(sha))throw new IOException("RAW 原文件内容已变化，请重新选择。");RawDeveloper.Info read=RawDeveloper.inspect(file);check(token);main.post(()->{if(!valid(token))return;info=read;sourceSha=sha;expectedSourceSha=sha;setBusy(false,"");refreshInfo();develop();});}catch(Exception|OutOfMemoryError error){postError(token,error);}});
    }
    private void scheduleDevelop(){updateActions();main.removeCallbacks(develop);if(source!=null&&info!=null&&!destroyed&&!transferring)main.postDelayed(develop,180);}
    private void develop(){
        if(source==null||info==null||destroyed||paused||transferring)return;cancelCurrent();final int token=generation.get();final File input=source;final String expectedSha=sourceSha;final RawDevelopmentSettings frozen=settings;setBusy(true,"显影中…");
        worker.execute(()->{Bitmap bitmap=null;try{check(token);AtomicInteger last=new AtomicInteger(-1);RawDeveloper.Result next=RawDeveloper.develop(this,input,owner,frozen,()->!valid(token),value->{int percent=Math.min(99,Math.max(0,(int)Math.round(value*100)));if(last.getAndSet(percent)!=percent)main.post(()->{if(valid(token)){progress.setProgress(percent);status.setText((percent>=95?"保存中 ":"显影中 ")+percent+"%");}});});check(token);if(!expectedSha.equalsIgnoreCase(next.sourceSha))throw new IOException("RAW 原文件内容已变化，请重新选择。");BitmapFactory.Options options=new BitmapFactory.Options();options.inJustDecodeBounds=true;BitmapFactory.decodeFile(next.workingFile.getPath(),options);if(options.outWidth!=next.info.width||options.outHeight!=next.info.height)throw new IOException("完整显影尺寸核对失败。");int sample=1;while(Math.max(options.outWidth,options.outHeight)/(double)sample>1440)sample*=2;options.inJustDecodeBounds=false;options.inSampleSize=sample;options.inScaled=false;options.inPreferredConfig=Bitmap.Config.ARGB_8888;options.inPreferredColorSpace=ColorSpace.get(ColorSpace.Named.SRGB);bitmap=BitmapFactory.decodeFile(next.workingFile.getPath(),options);if(bitmap==null)throw new IOException("显影成品已生成，但预览读取失败。");bitmap.setDensity(Bitmap.DENSITY_NONE);check(token);Bitmap shown=bitmap;bitmap=null;main.post(()->{if(!valid(token)){shown.recycle();return;}Bitmap old=preview;preview=shown;image.setPhotoPreservingTransform(shown);if(old!=null&&!old.isRecycled())old.recycle();result=next;appliedSettings=frozen;info=next.info;sourceSha=next.sourceSha;setBusy(false,next.colorStatus);refreshInfo();refreshGlass();if(getIntent().getBooleanExtra(EXTRA_EDIT_DIRECTLY,false))editCopy();});}catch(Exception|OutOfMemoryError error){postError(token,error);}finally{if(bitmap!=null)bitmap.recycle();}});
    }
    private void savePng(){
        if(!ready()||picking)return;
        pendingSave=result;picking=true;
        Intent create=new Intent(Intent.ACTION_CREATE_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("image/png")
                .putExtra(Intent.EXTRA_TITLE,baseName()+"_RAW.png")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION|Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
        try{startActivityForResult(create,SAVE_PNG);}
        catch(ActivityNotFoundException|SecurityException unavailable){documentPickerFailed(unavailable);}
    }
    private void writePng(RawDeveloper.Result frozen,Uri destination){
        final File rawInput=source;cancelCurrent();transferring=true;setBusy(true,"保存 PNG…");int token=generation.get();worker.execute(()->{try{check(token);if(rawInput==null||!frozen.sourceSha.equals(PhotoEditStore.hashFile(rawInput)))throw new IOException("RAW 原文件已变化，请重新选择。");if(!frozen.workingSha.equals(PhotoEditStore.hashFile(frozen.workingFile)))throw new IOException("显影成品已变化，请重新显影。");try(InputStream in=new FileInputStream(frozen.workingFile);OutputStream out=getContentResolver().openOutputStream(destination,"w")){if(out==null)throw new IOException("所选位置不可写入。");byte[] bytes=new byte[256*1024];int n;while((n=in.read(bytes))!=-1){check(token);out.write(bytes,0,n);}out.flush();}check(token);main.post(()->{if(valid(token)){transferring=false;setBusy(false,"PNG 已保存");}});}catch(Exception error){main.post(()->{if(valid(token)){transferring=false;setBusy(false,"");message("PNG 保存未完成，请重新选择位置重试。",true);}});}});
    }
    private void editCopy(){
        if(!ready())return;final RawDeveloper.Result frozen=result;final File rawInput=source;cancelCurrent();transferring=true;setBusy(true,"准备编辑副本…");final int token=generation.get();
        worker.execute(()->{Bitmap bitmap=null;File target=null;boolean queued=false;try{check(token);if(rawInput==null||!frozen.sourceSha.equals(PhotoEditStore.hashFile(rawInput)))throw new IOException("RAW 原文件已变化，请重新选择。");if(!frozen.workingSha.equals(PhotoEditStore.hashFile(frozen.workingFile)))throw new IOException("显影成品已变化，请重新显影。");cc.huevia.album.RawEditorSource.retainOriginal(this,rawInput,displayName,()->!valid(token));File root=new File(getFilesDir(),"raw-developed-handoff").getCanonicalFile();if(!root.isDirectory()&&!root.mkdirs())throw new IOException("编辑副本目录不可用。");long needed=(long)frozen.info.width*frozen.info.height*4+8L*1024*1024;if(root.getUsableSpace()>0&&root.getUsableSpace()<needed)throw new IOException("存储空间不足，无法创建完整编辑副本。");target=new File(root,UUID.randomUUID()+".jpg");pendingHandoffs.add(target);BitmapFactory.Options options=new BitmapFactory.Options();options.inScaled=false;options.inSampleSize=1;options.inPreferredConfig=Bitmap.Config.ARGB_8888;options.inPreferredColorSpace=ColorSpace.get(ColorSpace.Named.SRGB);bitmap=BitmapFactory.decodeFile(frozen.workingFile.getPath(),options);if(bitmap==null||bitmap.getWidth()!=frozen.info.width||bitmap.getHeight()!=frozen.info.height)throw new IOException("无法读取完整显影像素，未缩小图片。");check(token);try(FileOutputStream out=new FileOutputStream(target)){if(!bitmap.compress(Bitmap.CompressFormat.JPEG,100,out))throw new IOException("编辑副本编码失败。");out.flush();out.getFD().sync();}bitmap.recycle();bitmap=null;check(token);cc.huevia.album.RawEditorSource.writeMetadata(rawInput,target,frozen.info);verifyJpeg(target,frozen.info.width,frozen.info.height);String sha=PhotoEditStore.hashFile(target);check(token);File handoff=target;queued=true;main.post(()->{if(!valid(token)){removeHandoff(handoff);return;}Intent result=new Intent().putExtra(EXTRA_DEVELOPED_JPEG_PATH,handoff.getAbsolutePath()).putExtra(EXTRA_RAW_SHA,frozen.sourceSha).putExtra(EXTRA_JPEG_SHA,sha).putExtra(EXTRA_WORKING_IDENTITY,frozen.cacheIdentity).putExtra(EXTRA_SOURCE_NAME,displayName).putExtra(EXTRA_OWNER,owner);pendingHandoffs.remove(handoff);setResult(RESULT_OK,result);transferring=false;finish();});}catch(Exception|OutOfMemoryError error){postError(token,error);}finally{if(bitmap!=null)bitmap.recycle();if(target!=null&&!queued)removeHandoff(target);}});
    }
    private boolean ready(){return !busy&&!transferring&&result!=null&&settings.equals(appliedSettings)&&owner.equals(PhotoFilterEditor.accountOwner(this));}
    private void updateActions(){boolean ready=ready();if(save!=null){save.setEnabled(ready);edit.setEnabled(ready);}boolean adjustable=source!=null&&info!=null&&!transferring;for(View control:new View[]{colorMode,whiteBalance,highlights,quality,exposure,temperature,tint})if(control!=null)control.setEnabled(adjustable);}
    private void refreshInfo(){filename.setText(displayName);metric.setVisibility(info==null?View.GONE:View.VISIBLE);if(info!=null){metric.setText(info.width+"×"+info.height+" · 8-bit sRGB");metric.setContentDescription(info.make+" "+info.model+"，完整显影输出"+info.width+"乘"+info.height+"像素，8-bit sRGB");}}
    private void clearPreview(){if(image!=null)image.setPhoto(null);if(preview!=null&&!preview.isRecycled())preview.recycle();preview=null;}
    private void setBusy(boolean value,String text){busy=value;progress.setVisibility(value?View.VISIBLE:View.INVISIBLE);if(value)progress.setProgress(0);if(text!=null&&!text.isEmpty()){status.setText(text);status.setTextColor(MUTED);}updateActions();}
    private void message(String value,boolean error){status.setText(value==null?"RAW 显影未完成，请重试。":value);status.setTextColor(error?0xffffb4a7:MUTED);refreshGlass();}
    private void postError(int token,Throwable error){main.post(()->{if(!valid(token))return;transferring=false;setBusy(false,"");message(error instanceof OutOfMemoryError?"完整 RAW 处理内存不足，未缩小图片。":error.getMessage(),true);});}
    private void cancelCurrent(){generation.incrementAndGet();main.removeCallbacks(develop);worker.getQueue().clear();}
    private boolean valid(int token){return !destroyed&&token==generation.get()&&owner.equals(PhotoFilterEditor.accountOwner(this));}
    private void check(int token)throws IOException{if(!valid(token)||Thread.currentThread().isInterrupted())throw new IOException("RAW 操作已取消。");}
    private void rememberSourceStat(){sourceLength=source.length();sourceModified=source.lastModified();}
    private File checkedSource(File file)throws IOException{File canonical=file.getCanonicalFile();boolean privateFile=inside(canonical,getFilesDir())||inside(canonical,getCacheDir())||getExternalFilesDir(null)!=null&&inside(canonical,getExternalFilesDir(null));if(!privateFile||!canonical.isFile()||canonical.length()<1||canonical.length()>MAX_SOURCE)throw new IOException("RAW 文件不可读取，请重新选择。");return canonical;}
    private static boolean inside(File child,File root)throws IOException{return child.getCanonicalPath().startsWith(root.getCanonicalPath()+File.separator);}
    private boolean isOwnedInputDirectory(File file){try{return file!=null&&file.getName().matches("raw-develop-input-[a-f0-9-]{36}")&&file.getCanonicalFile().getParentFile().equals(getCacheDir().getCanonicalFile());}catch(IOException invalid){return false;}}
    private void removeInput(File directory){if(!isOwnedInputDirectory(directory))return;File file=new File(directory,"source.raw");if(file.isFile())file.delete();directory.delete();ownedInputs.remove(directory);}
    private void removeHandoff(File file){try{File root=new File(getFilesDir(),"raw-developed-handoff").getCanonicalFile();if(file.getCanonicalFile().getParentFile().equals(root)&&file.getName().matches("[a-f0-9-]{36}\\.jpg")&&file.isFile())file.delete();}catch(IOException ignored){}pendingHandoffs.remove(file);}
    private static void verifyJpeg(File file,int width,int height)throws IOException{BitmapFactory.Options bounds=new BitmapFactory.Options();bounds.inJustDecodeBounds=true;BitmapFactory.decodeFile(file.getPath(),bounds);if(bounds.outWidth!=width||bounds.outHeight!=height||!"image/jpeg".equals(bounds.outMimeType))throw new IOException("编辑副本完整尺寸核对失败。");try(RandomAccessFile input=new RandomAccessFile(file,"r")){if(input.length()<4||input.readUnsignedShort()!=0xffd8)throw new IOException("编辑副本 JPEG 不完整。");input.seek(input.length()-2);if(input.readUnsignedShort()!=0xffd9)throw new IOException("编辑副本 JPEG 尚未写入完成。");}}
    private String baseName(){String name=displayName.replaceAll("[\\p{Cntrl}\\\\/:*?\"<>|]","_");int dot=name.lastIndexOf('.');if(dot>0)name=name.substring(0,dot);return name.isEmpty()?"RAW":name.substring(0,Math.min(80,name.length()));}
    @Override protected void onResume(){super.onResume();paused=false;if(!owner.equals(PhotoFilterEditor.accountOwner(this))){finish();return;}main.removeCallbacks(validity);main.post(validity);if(source!=null&&!picking&&!transferring&&!busy&&(result==null||!settings.equals(appliedSettings))){if(info==null)inspect();else scheduleDevelop();}else if(!busy&&!transferring){progress.setVisibility(View.INVISIBLE);updateActions();}}
    @Override protected void onStop(){paused=true;main.removeCallbacks(validity);cancelCurrent();boolean interrupted=busy;boolean transfer=transferring;busy=false;transferring=false;if(interrupted)setBusy(false,transfer?"保存已取消，可重试":source==null?"读取已取消，请重新选择":"显影已暂停");super.onStop();}
    @Override public void onConfigurationChanged(Configuration config){super.onConfigurationChanged(config);buildUi();}
    @Override protected void onSaveInstanceState(Bundle out){if(source!=null)out.putString("source",source.getAbsolutePath());out.putString("name",displayName);out.putString("expectedSha",expectedSourceSha);out.putInt("wb",settings.whiteBalance.ordinal());out.putInt("kelvin",settings.temperatureKelvin);out.putInt("tint",settings.tint);out.putInt("exposure",settings.exposureTenths);out.putInt("highlights",settings.highlightMode);out.putInt("quality",settings.demosaicQuality);out.putInt("color",settings.colorMode.ordinal());super.onSaveInstanceState(out);}
    private void restoreSettings(Bundle state){try{int wb=state.getInt("wb",0);settings=new RawDevelopmentSettings(RawDevelopmentSettings.WhiteBalance.values()[wb],state.getInt("kelvin",5500),state.getInt("tint",0),state.getInt("exposure",0),state.getInt("highlights",2),state.getInt("quality",3),RawDevelopmentSettings.ColorMode.values()[state.getInt("color",0)]);}catch(RuntimeException invalid){settings=RawDevelopmentSettings.DEFAULT;}}
    @Override protected void onDestroy(){destroyed=true;generation.incrementAndGet();main.removeCallbacksAndMessages(null);worker.getQueue().clear();File keep=isChangingConfigurations()&&source!=null&&isOwnedInputDirectory(source.getParentFile())?source.getParentFile():null;worker.execute(()->{List<File> dirs; synchronized(ownedInputs){dirs=new ArrayList<>(ownedInputs);}for(File directory:dirs)if(!directory.equals(keep))removeInput(directory);List<File> handoffs;synchronized(pendingHandoffs){handoffs=new ArrayList<>(pendingHandoffs);}for(File handoff:handoffs)removeHandoff(handoff);});worker.shutdown();for(PhotoGlassDrawable glass:glasses)glass.close();glasses.clear();if(image!=null)image.setPhoto(null);if(preview!=null&&!preview.isRecycled())preview.recycle();preview=null;super.onDestroy();}
    private void glass(View owner,float radius){PhotoGlassDrawable glass=new PhotoGlassDrawable(image,owner,density(),radius);owner.setBackground(glass);glasses.add(glass);}
    private void refreshGlass(){for(PhotoGlassDrawable glass:glasses)glass.refresh();}
    private Button actionButton(String label,boolean primary,Runnable action){
        Button b=button(label,action);b.setTextSize(13);b.setTypeface(Typeface.create("sans-serif-medium",Typeface.NORMAL));
        b.setMinHeight(dp(48));b.setMinWidth(dp(48));b.setPadding(dp(12),0,dp(12),0);b.setSingleLine(true);
        b.setTextColor(new ColorStateList(new int[][]{new int[]{-android.R.attr.state_enabled},new int[]{}},
                new int[]{0xffbab1a7,primary?0xff352016:TEXT}));
        GradientDrawable disabled=shape(0xff292724,14);disabled.setStroke(dp(1),0xff4c4640);
        GradientDrawable normal=shape(primary?ACCENT:0xff33302c,14);
        if(!primary)normal.setStroke(dp(1),0xff4c4640);
        GradientDrawable focused=shape(primary?ACCENT:0xff33302c,14);focused.setStroke(dp(2),primary?TEXT:ACCENT);
        StateListDrawable surfaces=new StateListDrawable();
        surfaces.addState(new int[]{-android.R.attr.state_enabled},disabled);
        surfaces.addState(new int[]{android.R.attr.state_focused},focused);surfaces.addState(new int[]{},normal);
        b.setBackground(new RippleDrawable(ColorStateList.valueOf(primary?0x26352016:0x2bf6f1eb),surfaces,shape(Color.WHITE,14)));
        return b;
    }
    private Button button(String label,Runnable action){Button b=new Button(this);b.setText(label);b.setTextSize(12);b.setAllCaps(false);b.setTextColor(TEXT);b.setMinHeight(0);b.setMinimumHeight(0);b.setMinWidth(0);b.setMinimumWidth(0);b.setIncludeFontPadding(false);b.setPadding(dp(6),0,dp(6),0);b.setStateListAnimator(null);b.setBackground(new RippleDrawable(ColorStateList.valueOf(0x22ffffff),shape(Color.TRANSPARENT,14),null));b.setOnClickListener(v->action.run());return b;}
    private TextView text(String value,float size,int color){TextView t=new TextView(this);t.setText(value);t.setTextSize(size);t.setTextColor(color);t.setIncludeFontPadding(false);return t;}
    private GradientDrawable shape(int fill,float radius){GradientDrawable shape=new GradientDrawable();shape.setColor(fill);shape.setCornerRadius(dp(radius));return shape;}
    private LinearLayout row(){LinearLayout layout=new LinearLayout(this);layout.setGravity(Gravity.CENTER_VERTICAL);return layout;}
    private LinearLayout column(){LinearLayout layout=new LinearLayout(this);layout.setOrientation(LinearLayout.VERTICAL);return layout;}
    private float density(){return getResources().getDisplayMetrics().density;}
    private int dp(float value){return Math.round(value*density());}
}
