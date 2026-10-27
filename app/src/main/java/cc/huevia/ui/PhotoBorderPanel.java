package cc.huevia.ui;

import android.app.*;
import android.content.*;
import android.content.res.ColorStateList;
import android.graphics.*;
import android.graphics.drawable.*;
import android.os.*;
import android.text.*;
import android.view.*;
import android.widget.*;
import cc.huevia.album.*;
import cc.huevia.ncp.*;
import java.io.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.function.Consumer;

/** Prototype border strip with real previews; secondary controls live in the settings sheet. */
public final class PhotoBorderPanel implements AutoCloseable {
    public interface Host {
        PhotoBorder border();PhotoCaptureInfo capture();boolean ready();String identity();Bitmap thumbnail();PresetPreviewProfile colour();
        void change(PhotoBorder border);void undo();void redo();boolean canUndo();boolean canRedo();void error(String message);
        default void startDrag(){}default void dragChange(PhotoBorder border){change(border);}default void endDrag(){}
    }
    private static final int TEXT=0xffffffff,MUTED=0x9effffff,ACCENT=0xfff2b48c,FIELD=0xff292724;
    private final Activity activity;private final Host host;private final Handler main=new Handler(Looper.getMainLooper());
    private final ExecutorService worker=Executors.newSingleThreadExecutor();private volatile boolean closed;private volatile int request;private int tab;private String thumbKey="",lastSource="";private PhotoBorder lastBorder=PhotoBorder.NONE;
    private LinearLayout root,body,cards;private final Button[] tabs=new Button[3];private final ImageView[] images=new ImageView[4];private final LinearLayout[] tiles=new LinearLayout[4];private final TextView[] labels=new TextView[4];
    private final TextView[] informationValues=new TextView[6];private final LinearLayout[] informationRows=new LinearLayout[6];
    private Button undo,redo;private Dialog popup,fieldDialog;private boolean manualCamera,settingsOpen;
    private SeekBar appearanceTracking;private String appearanceIdentity="";
    public PhotoBorderPanel(Activity a,Host h){activity=a;host=h;}
    public View create(){
        root=column();root.setTag("border-prototype-panel");root.setBackgroundColor(0xff131110);
        styles();buildInformationSummary();refresh();return root;
    }
    private void styles(){
        HorizontalScrollView scroll=new HorizontalScrollView(activity);scroll.setTag("border-template-strip");scroll.setHorizontalScrollBarEnabled(false);
        cards=row();cards.setPadding(dp(12),dp(12),dp(12),dp(4));scroll.addView(cards);
        root.addView(scroll,new LinearLayout.LayoutParams(-1,scaled(82)+dp(16)));
        for(int i=0;i<4;i++){
            final int template=i;LinearLayout tile=column();tile.setGravity(Gravity.CENTER);tile.setTag("border-template-"+i);
            ImageView preview=new ImageView(activity);preview.setScaleType(ImageView.ScaleType.FIT_CENTER);preview.setPadding(dp(2),dp(2),dp(2),dp(2));preview.setClipToOutline(true);
            tile.addView(preview,new LinearLayout.LayoutParams(-1,scaled(62)));
            TextView label=text(PhotoBorder.TEMPLATES[i],10.5f,0xa8ffffff);label.setGravity(Gravity.CENTER);label.setSingleLine(true);
            tile.addView(label,new LinearLayout.LayoutParams(-1,scaled(20)));
            tile.setOnClickListener(v->{if(host.ready())host.change(host.border().withTemplate(template));});tile.setContentDescription(PhotoBorder.TEMPLATES[i]);tile.setFocusable(true);
            tile.setForeground(new RippleDrawable(ColorStateList.valueOf(0x22f2b48c),null,shape(Color.WHITE,10)));
            LinearLayout.LayoutParams size=new LinearLayout.LayoutParams(scaled(70),scaled(82));if(i<3)size.rightMargin=dp(9);cards.addView(tile,size);
            images[i]=preview;tiles[i]=tile;labels[i]=label;
        }
    }
    private void buildInformationSummary(){
        ScrollView scroll=new ScrollView(activity);scroll.setTag("border-information-scroll");scroll.setFillViewport(false);scroll.setVerticalScrollBarEnabled(false);
        LinearLayout list=column();list.setPadding(dp(16),dp(4),dp(16),dp(8));scroll.addView(list);
        String[] names={"机型","焦距","光圈","快门","ISO","拍摄时间"};
        for(int i=0;i<names.length;i++){
            final int index=i;LinearLayout line=summaryRow(names[i]);TextView value=text("",11.5f,TEXT);value.setTypeface(Typeface.create("sans-serif-medium",Typeface.NORMAL));value.setGravity(Gravity.END|Gravity.CENTER_VERTICAL);value.setSingleLine(true);value.setEllipsize(TextUtils.TruncateAt.END);
            line.addView(value,new LinearLayout.LayoutParams(0,-1,1));
            line.setTag("border-information-"+i);line.setOnClickListener(v->{if(index==0)showCamera();else editField(index-1,names[index]);});line.setFocusable(true);
            list.addView(line,new LinearLayout.LayoutParams(-1,scaled(38)));informationRows[i]=line;informationValues[i]=value;
        }
        LinearLayout settings=summaryRow("设置");((TextView)settings.getChildAt(0)).setTextColor(ACCENT);settings.setTag("border-settings-entry");settings.setOnClickListener(v->showSettings(2));settings.setFocusable(true);settings.setContentDescription("边框设置，样式、显示项、Logo与外观；包含撤销和重做");
        list.addView(settings,new LinearLayout.LayoutParams(-1,scaled(38)));root.addView(scroll,new LinearLayout.LayoutParams(-1,0,1));
    }
    private LinearLayout summaryRow(String name){
        LinearLayout line=row();TextView label=text(name,11.5f,MUTED);label.setSingleLine(true);label.setPadding(0,0,dp(8),0);line.addView(label,new LinearLayout.LayoutParams(scaled(60),-1));
        LayerDrawable surface=new LayerDrawable(new Drawable[]{shape(Color.TRANSPARENT,0),shape(0x12ffffff,0)});surface.setLayerHeight(1,Math.max(1,dp(.5f)));surface.setLayerGravity(1,Gravity.BOTTOM|Gravity.FILL_HORIZONTAL);
        line.setBackground(new RippleDrawable(ColorStateList.valueOf(0x22f2b48c),surface,null));return line;
    }
    public void refresh(){
        if(root==null)return;String source=host.identity();PhotoBorder b=host.border();boolean changed=!source.equals(lastSource)||!b.equals(lastBorder);
        if(!source.equals(lastSource)){request++;thumbKey="";}lastSource=source;lastBorder=b;
        if(undo!=null){undo.setEnabled(host.ready()&&host.canUndo());undo.setAlpha(undo.isEnabled()?1:.35f);}if(redo!=null){redo.setEnabled(host.ready()&&host.canRedo());redo.setAlpha(redo.isEnabled()?1:.35f);}
        for(int i=0;i<4;i++){
            boolean active=i==b.template;GradientDrawable face=shape(0xff1a1715,10);face.setStroke(dp(2),active?ACCENT:Color.TRANSPARENT);images[i].setBackground(face);images[i].setPadding(dp(2),dp(2),dp(2),dp(2));
            tiles[i].setSelected(active);tiles[i].setEnabled(host.ready());labels[i].setTextColor(active?ACCENT:0xa8ffffff);labels[i].setTypeface(Typeface.create(active?"sans-serif-medium":"sans-serif",Typeface.NORMAL));tiles[i].setContentDescription(PhotoBorder.TEMPLATES[i]+(active?"，已选择":""));
        }
        String[] names={"机型","焦距","光圈","快门","ISO","拍摄时间"};
        for(int i=0;i<6;i++){
            String raw=i==0?PhotoCaptureInfo.friendly(host.capture().model(b)):host.capture().field(b,i-1);
            String origin=i==0?(b.automatic?"EXIF":"手动"):(b.field(i-1).isEmpty()?"EXIF":"自定义");
            if(raw.isEmpty())origin="";String visible=raw.isEmpty()?"未记录":raw;
            informationValues[i].setText(visible);informationValues[i].setTextColor(raw.isEmpty()?MUTED:TEXT);informationValues[i].setTypeface(Typeface.create(raw.isEmpty()?"sans-serif":"sans-serif-medium",Typeface.NORMAL));
            informationRows[i].setTooltipText(names[i]+" · "+visible+" · "+(origin.isEmpty()?"原图无此记录":origin)+" · "+(b.shows(i)?"已显示":"已隐藏"));
            informationRows[i].setEnabled(host.ready());informationRows[i].setContentDescription(names[i]+"，"+visible+"，"+(origin.isEmpty()?"原图无此记录":origin)+"，"+(b.shows(i)?"已显示":"已隐藏")+"，轻点编辑");
        }
        if(settingsOpen&&changed&&appearanceTracking==null)renderSettingsBody();if(appearanceTracking==null)requestThumbnails();
    }
    private void showSettings(int selectedTab){
        if(!host.ready())return;dismiss();manualCamera=false;tab=selectedTab;
        LinearLayout content=column();content.setBackground(shape(0xff242321,22));content.setPadding(dp(16),dp(8),dp(16),dp(16));
        LinearLayout title=row();TextView heading=text("边框设置",14,TEXT);heading.setTypeface(Typeface.create("sans-serif-medium",Typeface.NORMAL));title.addView(heading,new LinearLayout.LayoutParams(0,dp(48),1));title.addView(iconButton(AppIcon.Kind.CLOSE,"关闭边框设置",this::dismiss),new LinearLayout.LayoutParams(dp(48),dp(48)));content.addView(title);
        LinearLayout head=row();String[] names={"样式","信息","外观"};for(int i=0;i<3;i++){final int n=i;tabs[i]=button(names[i],()->{tab=n;rebuildBody();});head.addView(tabs[i],new LinearLayout.LayoutParams(0,dp(48),1));}
        undo=iconButton(AppIcon.Kind.UNDO,"撤销边框调整",()->{host.undo();refresh();});redo=iconButton(AppIcon.Kind.REDO,"重做边框调整",()->{host.redo();refresh();});head.addView(undo,new LinearLayout.LayoutParams(dp(48),dp(48)));head.addView(redo,new LinearLayout.LayoutParams(dp(48),dp(48)));content.addView(head);
        body=column();content.addView(body,new LinearLayout.LayoutParams(-1,dp(Math.min(336,Math.max(120,activity.getResources().getConfiguration().screenHeightDp-168)))));
        renderSettingsBody();show(content);settingsOpen=true;refresh();
    }
    private void rebuildBody(){refresh();if(settingsOpen)renderSettingsBody();}
    private void renderSettingsBody(){
        if(body==null)return;body.removeAllViews();for(int i=0;i<3;i++)if(tabs[i]!=null){tabs[i].setTextColor(i==tab?ACCENT:MUTED);tabs[i].setSelected(i==tab);tabs[i].setTypeface(Typeface.create(i==tab?"sans-serif-medium":"sans-serif",Typeface.NORMAL));tabs[i].setBackground(underline(i==tab));tabs[i].setPadding(dp(8),0,dp(8),0);}
        if(tab==0){ScrollView scroll=new ScrollView(activity);LinearLayout list=column();for(int i=0;i<4;i++){final int template=i;Button choice=button(PhotoBorder.TEMPLATES[i],()->{if(host.ready())host.change(host.border().withTemplate(template));});choice.setGravity(Gravity.CENTER_VERTICAL);choice.setTextColor(i==host.border().template?ACCENT:TEXT);choice.setSelected(i==host.border().template);choice.setTypeface(Typeface.create(i==host.border().template?"sans-serif-medium":"sans-serif",Typeface.NORMAL));list.addView(choice,new LinearLayout.LayoutParams(-1,dp(48)));}scroll.addView(list);body.addView(scroll,new LinearLayout.LayoutParams(-1,-1));}
        else if(tab==1)information();else appearance();
    }
    private void requestThumbnails(){Bitmap source=host.thumbnail();if(!host.ready()||source==null)return;PhotoBorder settings=host.border();PhotoCaptureInfo capture=host.capture();PresetPreviewProfile profile=host.colour();String key=System.identityHashCode(source)+":"+profile.modelVersion()+":"+settings.identity();if(key.equals(thumbKey))return;thumbKey=key;final int token=++request;worker.execute(()->{if(closed||token!=request)return;Bitmap colour=null;Bitmap[] outputs=new Bitmap[4];try{colour=PhotoFilterEditor.renderColour(source,profile);PhotoBorderRenderer renderer=new PhotoBorderRenderer(activity.getAssets());for(int i=0;i<4;i++){if(closed||token!=request)return;outputs[i]=renderer.apply(colour,settings.withTemplate(i),capture);}Bitmap[] result=outputs;main.post(()->{if(closed||token!=request||cards==null)return;for(int i=0;i<4;i++)images[i].setImageBitmap(result[i]);});}catch(Exception|OutOfMemoryError error){main.post(()->{if(!closed&&token==request)host.error(error.getMessage()==null?"边框预览暂不可用。":error.getMessage());});}});}
    private void information(){
        ScrollView scroll=new ScrollView(activity);LinearLayout list=column();
        String[] names={"机型","焦距","光圈","快门","ISO","拍摄时间"};PhotoBorder b=host.border();final String identity=host.identity();
        for(int i=0;i<names.length;i++){
            final int index=i;LinearLayout line=row(),entry=row();
            String raw=i==0?PhotoCaptureInfo.friendly(host.capture().model(b)):host.capture().field(b,i-1);
            String visible=raw.isEmpty()?"未记录":raw;
            TextView label=text(names[i],11.5f,MUTED);label.setPadding(0,0,dp(8),0);
            entry.addView(label,new LinearLayout.LayoutParams(scaled(60),-1));
            TextView value=text(visible,11.5f,raw.isEmpty()?MUTED:TEXT);value.setTypeface(Typeface.create(raw.isEmpty()?"sans-serif":"sans-serif-medium",Typeface.NORMAL));value.setGravity(Gravity.END|Gravity.CENTER_VERTICAL);
            entry.addView(value,new LinearLayout.LayoutParams(0,-1,1));
            entry.setBackground(new RippleDrawable(ColorStateList.valueOf(0x22f2b48c),shape(Color.TRANSPARENT,10),null));entry.setPadding(0,0,0,0);
            entry.setOnClickListener(v->{if(index==0)showCamera();else editField(index-1,names[index]);});entry.setEnabled(host.ready());entry.setFocusable(true);
            entry.setContentDescription(names[i]+"，"+visible+"，轻点编辑");entry.setTooltipText(names[i]+" · "+visible);
            line.addView(entry,new LinearLayout.LayoutParams(0,dp(48),1));
            CheckBox show=new CheckBox(activity);show.setButtonTintList(ColorStateList.valueOf(ACCENT));show.setChecked(b.shows(i));show.setEnabled(host.ready());show.setContentDescription("显示"+names[i]);
            show.setOnCheckedChangeListener((v,checked)->{if(host.ready()&&identity.equals(host.identity())&&b.equals(host.border()))host.change(b.withVisible(index,checked));});
            line.addView(show,new LinearLayout.LayoutParams(dp(48),dp(48)));list.addView(line);
        }
        scroll.addView(list);body.addView(scroll,new LinearLayout.LayoutParams(-1,-1));
    }
    private void editField(int index,String name){if(!host.ready())return;PhotoBorder starting=host.border();final String identity=host.identity();EditText input=input("留空使用原图");input.setText(starting.field(index));input.setSelectAllOnFocus(true);showFieldDialog(new PhotoEditorTypography.Builder(themed()).setTitle(name).setMessage("原图值："+(host.capture().field(starting.withField(index,""),index).isEmpty()?"未记录":host.capture().field(starting.withField(index,""),index))).setView(input).setNegativeButton("取消",null).setPositiveButton("应用",(d,w)->{if(host.ready()&&identity.equals(host.identity())&&starting.equals(host.border()))try{host.change(starting.withField(index,input.getText().toString()));rebuildBody();}catch(IllegalArgumentException invalid){host.error(invalid.getMessage());}}).create());}
    private void appearance(){
        ScrollView scroll=new ScrollView(activity);LinearLayout list=column();String[] names={"边距","圆角","阴影","模糊"};final PhotoBorder starting=host.border();final String identity=host.identity();
        int[] values={starting.margin,starting.corner,starting.shadow,starting.blur};
        for(int i=0;i<4;i++){
            final int index=i,min=i==0?50:0,max=i==0?160:i==2?150:200;LinearLayout line=row();line.addView(text(names[i],12,TEXT),new LinearLayout.LayoutParams(dp(66),dp(48)));
            SeekBar seek=new SeekBar(activity);seek.setTag("border-appearance-"+i);seek.setMax(max-min);seek.setProgress(values[i]-min);seek.setEnabled(host.ready());seek.setProgressTintList(ColorStateList.valueOf(ACCENT));seek.setThumbTintList(ColorStateList.valueOf(ACCENT));seek.setContentDescription(names[i]);line.addView(seek,new LinearLayout.LayoutParams(0,dp(48),1));
            TextView value=text(values[i]+"%",11,MUTED);value.setGravity(Gravity.END|Gravity.CENTER_VERTICAL);line.addView(value,new LinearLayout.LayoutParams(dp(44),dp(48)));
            seek.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener(){
                public void onProgressChanged(SeekBar s,int v,boolean user){value.setText((v+min)+"%");if(!user||!host.ready()||!identity.equals(host.identity()))return;if(appearanceTracking==s)host.dragChange(host.border().withAppearance(index,v+min));else host.change(host.border().withAppearance(index,v+min));}
                public void onStartTrackingTouch(SeekBar s){endAppearanceDrag();if(!host.ready()||!identity.equals(host.identity()))return;appearanceTracking=s;appearanceIdentity=identity;host.startDrag();}
                public void onStopTrackingTouch(SeekBar s){if(appearanceTracking==s)endAppearanceDrag();}
            });list.addView(line);
        }
        Button logo=button("Logo · "+new String[]{"跟随模板","彩色","白色","黑色"}[starting.logo],this::chooseLogo);logo.setEnabled(host.ready());list.addView(logo,new LinearLayout.LayoutParams(-1,dp(48)));
        Button reset=button("恢复默认",()->{if(host.ready()&&identity.equals(host.identity())&&starting.equals(host.border()))host.change(starting.reset());rebuildBody();});reset.setEnabled(host.ready());reset.setTooltipText("恢复当前模板的默认设置");list.addView(reset,new LinearLayout.LayoutParams(-1,dp(48)));
        scroll.addView(list);body.addView(scroll,new LinearLayout.LayoutParams(-1,-1));
    }
    public void showCamera(){if(!host.ready())return;manualCamera=!host.border().automatic;showCameraSheet();}
    private void showCameraSheet(){dismiss();final PhotoBorder starting=host.border();final String identity=host.identity();LinearLayout content=column();content.setBackground(shape(0xff242321,22));content.setPadding(dp(20),dp(8),dp(20),dp(16));LinearLayout title=row();TextView heading=text("机型",14,TEXT);heading.setTypeface(Typeface.create("sans-serif-medium",Typeface.NORMAL));heading.setTooltipText("仅修改边框显示，不修改原片信息");title.addView(heading,new LinearLayout.LayoutParams(0,dp(48),1));title.addView(iconButton(AppIcon.Kind.CLOSE,"关闭",this::dismiss),new LinearLayout.LayoutParams(dp(48),dp(48)));content.addView(title);LinearLayout modes=row();Button auto=button("自动",()->{manualCamera=false;showCameraSheet();}),manual=button("手动",()->{manualCamera=true;showCameraSheet();});styleMode(auto,!manualCamera);styleMode(manual,manualCamera);modes.addView(auto,new LinearLayout.LayoutParams(0,dp(48),1));LinearLayout.LayoutParams manualSize=new LinearLayout.LayoutParams(0,dp(48),1);manualSize.leftMargin=dp(6);modes.addView(manual,manualSize);content.addView(modes);String detected=PhotoCaptureInfo.friendly(host.capture().model);TextView detectedLabel=text(detected.isEmpty()?"原图无机型信息":"识别："+detected,11.5f,MUTED);detectedLabel.setSingleLine(true);detectedLabel.setEllipsize(TextUtils.TruncateAt.END);detectedLabel.setTooltipText(detected.isEmpty()?"原图未记录机型，可手动选择":"来自原始照片："+detected);content.addView(detectedLabel,new LinearLayout.LayoutParams(-1,dp(32)));
        if(!manualCamera){content.addView(primaryButton("使用识别结果",()->{if(host.ready()&&identity.equals(host.identity())&&starting.equals(host.border()))host.change(starting.withCamera(true,"",""));dismiss();rebuildBody();}),new LinearLayout.LayoutParams(-1,dp(48)));show(content);return;}
        EditText search=input("搜索机型");content.addView(search,new LinearLayout.LayoutParams(-1,dp(48)));HorizontalScrollView chips=new HorizontalScrollView(activity);chips.setHorizontalScrollBarEnabled(false);LinearLayout brands=row();chips.addView(brands);content.addView(chips,new LinearLayout.LayoutParams(-1,dp(48)));String[] brandKeys={"NIKON","FUJIFILM","SONY","CANON"},brandLabels={"尼康","富士","索尼","佳能"};String initial=PhotoCaptureInfo.brandKey(host.capture().brand(starting));final String[] chosenBrand={Arrays.asList(brandKeys).contains(initial)?initial:"NIKON"},chosenModel={host.capture().model(starting)};ScrollView rowsScroll=new ScrollView(activity);LinearLayout rows=column();rowsScroll.addView(rows);content.addView(rowsScroll,new LinearLayout.LayoutParams(-1,0,1));final Runnable[] populate={null};populate[0]=()->{rows.removeAllViews();String query=search.getText().toString().trim().toLowerCase(Locale.ROOT);LinkedHashSet<String> models=new LinkedHashSet<>();if(chosenBrand[0].equals(host.capture().brand)&&!host.capture().model.isEmpty())models.add(host.capture().model);if(chosenBrand[0].equals(host.capture().brand(starting))&&!host.capture().model(starting).isEmpty())models.add(host.capture().model(starting));models.addAll(Arrays.asList(models(chosenBrand[0])));for(String m:models){if(!PhotoCaptureInfo.friendly(m).toLowerCase(Locale.ROOT).contains(query))continue;Button choice=button(PhotoCaptureInfo.friendly(m),()->{chosenModel[0]=m;populate[0].run();});choice.setTextColor(m.equals(chosenModel[0])?ACCENT:TEXT);if(m.equals(chosenModel[0])){Drawable check=new AppIcon(AppIcon.Kind.CHECK,ACCENT,activity.getResources().getDisplayMetrics().density);check.setBounds(0,0,dp(16),dp(16));choice.setCompoundDrawablesRelative(null,null,check,null);choice.setCompoundDrawablePadding(dp(8));}choice.setTypeface(Typeface.create(m.equals(chosenModel[0])?"sans-serif-medium":"sans-serif",Typeface.NORMAL));choice.setGravity(Gravity.CENTER_VERTICAL);rows.addView(choice,new LinearLayout.LayoutParams(-1,dp(48)));}for(int i=0;i<brands.getChildCount();i++){Button brand=(Button)brands.getChildAt(i);boolean selected=brandKeys[i].equals(chosenBrand[0]);brand.setTextColor(selected?ACCENT:MUTED);brand.setTypeface(Typeface.create(selected?"sans-serif-medium":"sans-serif",Typeface.NORMAL));}};for(int i=0;i<4;i++){final int n=i;brands.addView(button(brandLabels[i],()->{chosenBrand[0]=brandKeys[n];chosenModel[0]="";populate[0].run();}),new LinearLayout.LayoutParams(dp(72),dp(48)));}search.addTextChangedListener(new TextWatcher(){public void beforeTextChanged(CharSequence s,int st,int count,int after){}public void afterTextChanged(Editable e){}public void onTextChanged(CharSequence s,int st,int before,int count){populate[0].run();}});populate[0].run();content.addView(button("自定义机型",()->{EditText custom=input("输入机型，最多 96 个字符");custom.setText(chosenModel[0]);showFieldDialog(new PhotoEditorTypography.Builder(themed()).setTitle("自定义机型").setView(custom).setNegativeButton("取消",null).setPositiveButton("使用",(d,w)->{if(host.ready()&&identity.equals(host.identity())&&starting.equals(host.border()))try{host.change(starting.withCamera(false,chosenBrand[0],custom.getText().toString()));dismiss();rebuildBody();}catch(IllegalArgumentException invalid){host.error(invalid.getMessage());}}).create());}),new LinearLayout.LayoutParams(-1,dp(48)));content.addView(primaryButton("使用机型",()->{if(chosenModel[0].isEmpty()){host.error("请先选择机型，或输入自定义机型。");return;}if(host.ready()&&identity.equals(host.identity())&&starting.equals(host.border()))host.change(starting.withCamera(false,chosenBrand[0],chosenModel[0]));dismiss();rebuildBody();}),new LinearLayout.LayoutParams(-1,dp(48)));show(content);
    }
    private static String[] models(String brand){switch(brand){case "NIKON":return new String[]{"NIKON Z 6_2","NIKON Z 6_3","NIKON Z f","NIKON Z 8","NIKON Z 9","NIKON Z 5","NIKON Z 7_2","NIKON Z 50","NIKON Z fc","NIKON D850","NIKON D750"};case "FUJIFILM":return new String[]{"X-T20","X-T30 II","X-T4","X-T5","X-S20","X100VI","X-H2","GFX100 II"};case "SONY":return new String[]{"ILCE-7M3","ILCE-7M4","ILCE-7RM5","ILCE-7CM2","ILCE-6700"};default:return new String[]{"Canon EOS R5","Canon EOS R6 Mark II","Canon EOS R8","Canon EOS R50"};}}
    private void show(LinearLayout content){Dialog d=new Dialog(activity);popup=d;d.requestWindowFeature(Window.FEATURE_NO_TITLE);boolean compact=activity.getResources().getConfiguration().screenHeightDp<520;if(compact&&manualCamera){for(int i=0;i<content.getChildCount();i++)if(content.getChildAt(i) instanceof ScrollView){content.getChildAt(i).setLayoutParams(new LinearLayout.LayoutParams(-1,dp(192)));}ScrollView scroll=new ScrollView(activity);scroll.addView(content);d.setContentView(scroll);}else d.setContentView(content);Window window=d.getWindow();if(window!=null){window.setBackgroundDrawableResource(android.R.color.transparent);window.setGravity(Gravity.BOTTOM);window.setDimAmount(.35f);window.addFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND);window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE);}d.show();PhotoEditorTypography.apply(d);if(window!=null)window.setLayout(-1,manualCamera?(int)(activity.getResources().getDisplayMetrics().heightPixels*(compact?.95:.76)):-2);d.setOnDismissListener(v->{if(popup==d){popup=null;clearSettings();}});}
    public void invalidate(){request++;thumbKey="";dismiss();}
    public boolean dismiss(){endAppearanceDrag();boolean had=popup!=null||fieldDialog!=null;if(fieldDialog!=null){Dialog d=fieldDialog;fieldDialog=null;d.dismiss();}if(popup!=null){Dialog d=popup;popup=null;d.dismiss();}clearSettings();return had;}
    private void endAppearanceDrag(){if(appearanceTracking==null)return;appearanceTracking=null;String identity=appearanceIdentity;appearanceIdentity="";if(host.ready()&&identity.equals(host.identity()))host.endDrag();}
    private void clearSettings(){settingsOpen=false;endAppearanceDrag();body=null;undo=null;redo=null;Arrays.fill(tabs,null);}
    private void showFieldDialog(AlertDialog d){if(fieldDialog!=null)fieldDialog.dismiss();fieldDialog=d;d.setOnDismissListener(v->{if(fieldDialog==d)fieldDialog=null;});d.show();PhotoEditorTypography.apply(d);}
    private void chooseLogo(){if(!host.ready())return;final String identity=host.identity();final PhotoBorder starting=host.border();showFieldDialog(new PhotoEditorTypography.Builder(themed()).setTitle("Logo 样式").setSingleChoiceItems(new String[]{"跟随模板","彩色","白色","黑色"},starting.logo,(d,w)->{if(host.ready()&&identity.equals(host.identity())&&starting.equals(host.border()))host.change(starting.withLogo(w));d.dismiss();rebuildBody();}).setNegativeButton("取消",null).create());}
    private Context themed(){return new ContextThemeWrapper(activity,cc.huevia.R.style.AppThemeDark);}
    private EditText input(String hint){EditText e=new EditText(themed());e.setTextColor(TEXT);e.setHintTextColor(MUTED);e.setTextSize(13);e.setTypeface(Typeface.create("sans-serif",Typeface.NORMAL));e.setIncludeFontPadding(false);e.setGravity(Gravity.CENTER_VERTICAL);e.setSingleLine(true);e.setHint(hint);e.setBackground(shape(FIELD,12));e.setPadding(dp(12),0,dp(12),0);e.setFilters(new InputFilter[]{new InputFilter.LengthFilter(96)});return e;}
    private LinearLayout column(){LinearLayout r=new LinearLayout(activity);r.setOrientation(1);return r;}private LinearLayout row(){LinearLayout r=new LinearLayout(activity);r.setGravity(Gravity.CENTER_VERTICAL);r.setBaselineAligned(false);return r;}
    private TextView text(String s,float size,int color){TextView v=new TextView(activity);v.setText(s);v.setTextSize(size);v.setTextColor(color);v.setGravity(Gravity.CENTER_VERTICAL);v.setIncludeFontPadding(false);v.setSingleLine(true);v.setEllipsize(TextUtils.TruncateAt.END);return v;}
    private Button button(String name,Runnable action){Button b=new Button(themed());b.setText(name);b.setAllCaps(false);b.setTextSize(12);b.setTypeface(Typeface.create("sans-serif",Typeface.NORMAL));b.setTextColor(ACCENT);b.setIncludeFontPadding(false);b.setSingleLine(true);b.setEllipsize(TextUtils.TruncateAt.END);b.setGravity(Gravity.CENTER);b.setMinWidth(0);b.setMinimumWidth(0);b.setMinHeight(dp(48));b.setMinimumHeight(dp(48));b.setBackgroundTintList(null);b.setBackground(new RippleDrawable(ColorStateList.valueOf(0x22f3b493),shape(Color.TRANSPARENT,10),null));b.setPadding(dp(8),0,dp(8),0);b.setStateListAnimator(null);b.setOnClickListener(v->action.run());return b;}
    private Button primaryButton(String name,Runnable action){Button b=button(name,action);b.setBackground(faceRipple(ACCENT,Color.TRANSPARENT,34,10));b.setPadding(dp(12),0,dp(12),0);b.setTextColor(0xff352016);b.setTypeface(Typeface.create("sans-serif-medium",Typeface.NORMAL));b.setTooltipText("仅修改边框显示，不修改原片信息");return b;}
    private void styleMode(Button b,boolean selected){b.setSelected(selected);b.setBackground(faceRipple(selected?ACCENT:FIELD,selected?Color.TRANSPARENT:0x30ffffff,32,10));b.setPadding(dp(8),0,dp(8),0);b.setTextColor(selected?0xff352016:MUTED);b.setTypeface(Typeface.create(selected?"sans-serif-medium":"sans-serif",Typeface.NORMAL));}
    private Drawable faceRipple(int fill,int stroke,int height,int radius){return new RippleDrawable(ColorStateList.valueOf(0x22f3b493),new ButtonFace(fill,stroke,height,radius),new ButtonFace(Color.WHITE,Color.TRANSPARENT,height,radius));}
    /** A compact face centred in the full 48dp hit area; background and mask share bounds. */
    private final class ButtonFace extends Drawable {
        private final int fill,stroke,height,radius;private final Paint paint=new Paint(Paint.ANTI_ALIAS_FLAG);private final RectF face=new RectF();private int alpha=255;
        ButtonFace(int fill,int stroke,int height,int radius){this.fill=fill;this.stroke=stroke;this.height=height;this.radius=radius;}
        @Override public void draw(Canvas canvas){Rect bounds=getBounds();float half=Math.min(dp(height),bounds.height())/2f;face.set(bounds.left,bounds.exactCenterY()-half,bounds.right,bounds.exactCenterY()+half);paint.setStyle(Paint.Style.FILL);paint.setColor(fill);paint.setAlpha(Color.alpha(fill)*alpha/255);canvas.drawRoundRect(face,dp(radius),dp(radius),paint);if(Color.alpha(stroke)>0){float width=Math.max(1,dp(1));face.inset(width/2,width/2);paint.setStyle(Paint.Style.STROKE);paint.setStrokeWidth(width);paint.setColor(stroke);paint.setAlpha(Color.alpha(stroke)*alpha/255);float corner=Math.max(0,dp(radius)-width/2);canvas.drawRoundRect(face,corner,corner,paint);}}
        @Override public void setAlpha(int alpha){this.alpha=alpha;invalidateSelf();}
        @Override public void setColorFilter(ColorFilter filter){paint.setColorFilter(filter);invalidateSelf();}
        @Override public int getOpacity(){return PixelFormat.TRANSLUCENT;}
    }
    private Button iconButton(AppIcon.Kind kind,String name,Runnable action){Button b=button("",action);b.setCompoundDrawablesRelativeWithIntrinsicBounds(new AppIcon(kind,TEXT,activity.getResources().getDisplayMetrics().density),null,null,null);b.setPadding(dp(12),0,dp(12),0);b.setContentDescription(name);return b;}
    private ImageView icon(AppIcon.Kind kind,int color){ImageView i=new ImageView(activity);i.setImageDrawable(new AppIcon(kind,color,activity.getResources().getDisplayMetrics().density));i.setScaleType(ImageView.ScaleType.FIT_CENTER);return i;}
    private Drawable underline(boolean active){LayerDrawable d=new LayerDrawable(new Drawable[]{shape(Color.TRANSPARENT,0),shape(active?ACCENT:Color.TRANSPARENT,1)});d.setLayerSize(1,dp(18),dp(2));d.setLayerGravity(1,Gravity.BOTTOM|Gravity.CENTER_HORIZONTAL);d.setLayerInset(1,0,0,0,dp(5));return d;}
    private GradientDrawable shape(int color,int radius){GradientDrawable d=new GradientDrawable();d.setColor(color);d.setCornerRadius(dp(radius));return d;}
    private int dp(float n){return Math.round(n*activity.getResources().getDisplayMetrics().density);}
    private int scaled(float n){return dp(n*activity.getResources().getConfiguration().fontScale);}
    @Override public void close(){closed=true;request++;dismiss();worker.shutdownNow();main.removeCallbacksAndMessages(null);}
}
