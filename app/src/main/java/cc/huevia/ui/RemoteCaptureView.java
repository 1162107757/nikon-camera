package cc.huevia.ui;

import android.app.Activity;
import android.app.Dialog;
import android.content.res.ColorStateList;
import android.graphics.*;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.RippleDrawable;
import android.graphics.drawable.Drawable;
import android.text.SpannableString;
import android.text.Spanned;
import android.text.style.RelativeSizeSpan;
import android.os.Handler;
import android.os.Looper;
import android.os.Bundle;
import android.os.SystemClock;
import android.view.*;
import android.view.accessibility.AccessibilityNodeInfo;
import android.widget.*;
import cc.huevia.remote.*;
import cc.huevia.ncp.PhotoHistogram;
import java.util.*;

/**
 * THESIS: full camera frame, compact identity, current readings and one clear shutter.
 * OWN-WORLD: approved remote-capture-20261024 prototype; #121313, #F3B493, system sp.
 * STORY: connect, inspect frame/histogram, focus, capture, verify, optionally transfer.
 * FIRST VIEWPORT: small header, image with movable 190x64 histogram, four readings,
 * centered 84dp shutter; landscape image left and 217dp control rail right.
 * FORM: native Android implementation of the user-approved code-led prototype.
 * FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance.
 */
public final class RemoteCaptureView extends LinearLayout {
    static final int BG=0xff121313,PANEL=0xff272625,TEXT=0xfff6f1eb,SECONDARY=0xffbeb9b2,ACCENT=0xfff3b493,INK=0xff352016,LINE=0xff343535;
    private final Activity activity;
    private final RemoteCaptureController controller;
    private final boolean landscape;
    private final Handler main=new Handler(Looper.getMainLooper());
    private final TextView identity,battery,mode,status;
    private final TextView[] values=new TextView[4];
    private final View shutter,focus,recentAction;
    private final ImageView recentImage;
    private Switch sheetTransfer;
    private final FrameStage stage;
    private final View histogramAction,gridAction;
    private boolean grid,histogram=true,rgb;
    private float histogramX=.03f,histogramY=1f;
    private Dialog sheet;
    private Chart sheetChart;
    private TextView sheetStatus;
    private ImageView sheetPhoto;
    private Button acknowledge;
    private Button checkedRecent,lumaMode,rgbMode,recentImport;
    private String sheetPurpose="";
    private final Map<TextView,java.util.function.Supplier<String>> liveDetails=new LinkedHashMap<>();
    private boolean updating;
    private RemoteCaptureController.State state;
    private final Runnable tick=new Runnable(){@Override public void run(){if(!isAttachedToWindow())return;update();main.postDelayed(this,500);}};
    public RemoteCaptureView(Activity activity,RemoteCaptureController controller,boolean landscape){
        super(activity);this.activity=activity;this.controller=controller;this.landscape=landscape;
        setOrientation(VERTICAL);setBackgroundColor(BG);
        LinearLayout top=row();top.setPadding(dp(8),0,dp(8),0);
        top.addView(icon(AppIcon.Kind.BACK,"返回同步",activity::finish));
        TextView title=text("遥控拍摄",landscape?15:17,TEXT,true);top.addView(title,new LayoutParams(0,-2,1));
        LinearLayout device=row();device.setPadding(dp(landscape?6:20),0,dp(landscape?6:20),0);
        identity=text("相机 · Wi-Fi",landscape?10:11,SECONDARY,false);device.addView(identity,new LayoutParams(0,-2,1));
        battery=text("—",landscape?10:11,SECONDARY,false);Drawable batteryGlyph=new CaptureGlyph(0,SECONDARY);batteryGlyph.setBounds(0,0,dp(16),dp(16));battery.setCompoundDrawables(batteryGlyph,null,null,null);battery.setCompoundDrawablePadding(dp(5));device.addView(battery);
        if(landscape){top.setPadding(dp(8),0,0,0);top.addView(device,new LayoutParams(dp(217),dp(48)));addView(top,new LayoutParams(-1,dp(48)));}
        else{addView(top,new LayoutParams(-1,dp(48)));addView(device,new LayoutParams(-1,dp(32)));}
        LinearLayout body=new LinearLayout(activity);body.setOrientation(landscape?HORIZONTAL:VERTICAL);addView(body,new LayoutParams(-1,0,1));
        LinearLayout imageColumn=column();
        LinearLayout tools=row();tools.setPadding(dp(12),0,dp(4),0);tools.setBackgroundColor(0xff090a0a);
        mode=text("—",11,TEXT,false);tools.addView(mode,landscape?new LayoutParams(-2,-2):new LayoutParams(0,-2,1));
        if(landscape){tools.setBackgroundColor(Color.TRANSPARENT);mode.setBackground(shape(0xc0090a0a,8));mode.setPadding(dp(8),dp(8),dp(8),dp(8));tools.addView(new View(activity),new LayoutParams(0,1,1));}
        LinearLayout toolButtons=row();if(landscape)toolButtons.setBackground(shape(0xd10b0c0c,10));
        toolButtons.addView(icon(AppIcon.Kind.SETTINGS,"拍摄设置",this::settings));
        histogramAction=icon(AppIcon.Kind.HISTOGRAM,"显示或收起直方图",()->{histogram=!histogram;update();});toolButtons.addView(histogramAction);
        gridAction=icon(AppIcon.Kind.GRID,"切换构图网格",()->{grid=!grid;update();});toolButtons.addView(gridAction);
        toolButtons.addView(icon(AppIcon.Kind.INFO,"查看机身参数",this::parameters));tools.addView(toolButtons);
        stage=new FrameStage();
        if(landscape){FrameLayout picture=new FrameLayout(activity);picture.addView(stage,new FrameLayout.LayoutParams(-1,-1));picture.addView(tools,new FrameLayout.LayoutParams(-1,dp(48),Gravity.TOP));imageColumn.addView(picture,new LayoutParams(-1,0,1));}
        else{imageColumn.addView(tools,new LayoutParams(-1,dp(48)));imageColumn.addView(stage,new LayoutParams(-1,0,1));}
        body.addView(imageColumn,landscape?new LayoutParams(0,-1,1):new LayoutParams(-1,0,1));
        LinearLayout controls=column();controls.setBackgroundColor(BG);
        LinearLayout readings=column();
        String[] labels={"快门","光圈","ISO","曝光补偿"};
        for(int r=0;r<(landscape?2:1);r++){
            LinearLayout line=row();line.setPadding(dp(10),dp(7),dp(10),dp(7));
            for(int c=0;c<(landscape?2:4);c++){
                int i=r*2+c;LinearLayout cell=column();cell.setGravity(Gravity.CENTER);
                values[i]=text("—",landscape?18:20,TEXT,true);values[i].setGravity(Gravity.CENTER);values[i].setFontFeatureSettings("tnum");cell.addView(values[i]);
                TextView label=text(labels[i],11,SECONDARY,false);label.setGravity(Gravity.CENTER);label.setPadding(0,dp(3),0,0);cell.addView(label);
                line.addView(cell,new LayoutParams(0,-2,1));
            }
            readings.addView(line,new LayoutParams(-1,-2));
        }
        controls.addView(readings);controls.addView(divider());
        status=text("读取相机",12,SECONDARY,false);status.setGravity(Gravity.CENTER);status.setPadding(dp(12),dp(8),dp(12),dp(8));status.setSingleLine(true);status.setEllipsize(android.text.TextUtils.TruncateAt.END);status.setMinHeight(dp(48));
        status.setOnClickListener(v->{if(state!=null&&state.outcome==RemoteCaptureController.Outcome.UNKNOWN)checkResult();else statusDetails();});
        controls.addView(status,new LayoutParams(-1,-2));
        LinearLayout release=row();release.setPadding(dp(12),dp(4),dp(12),dp(8));
        LinearLayout recent=column();recentAction=recent;recent.setGravity(Gravity.CENTER);recent.setContentDescription("查看最近拍摄");recent.setFocusable(true);recent.setClickable(true);recent.setBackground(ripple(0));recent.setOnClickListener(v->recent());
        recentImage=new ImageView(activity);recentImage.setScaleType(ImageView.ScaleType.CENTER_CROP);recentImage.setPadding(dp(13),dp(13),dp(13),dp(13));recentImage.setImageDrawable(new AppIcon(AppIcon.Kind.ALBUM,SECONDARY,getResources().getDisplayMetrics().density));recentImage.setBackground(shape(0xff20211f,12));recentImage.setClipToOutline(true);recent.addView(recentImage,new LayoutParams(dp(48),dp(48)));
        TextView recentCaption=text("最近拍摄",9,SECONDARY,false);recentCaption.setGravity(Gravity.CENTER);recentCaption.setPadding(0,dp(4),0,0);recent.addView(recentCaption);release.addView(recent,new LayoutParams(0,dp(72),1));
        shutter=new Shutter();shutter.setContentDescription("拍照");shutter.setFocusable(true);shutter.setClickable(true);shutter.setOnClickListener(v->controller.capture());int size=dp(landscape?74:84);release.addView(shutter,new LayoutParams(size,size));
        LinearLayout focusColumn=column();focusColumn.setGravity(Gravity.CENTER);focus=icon(AppIcon.Kind.EXPAND,"自动对焦",()->{stage.focusX=.5f;stage.focusY=.5f;stage.focusVisible=true;controller.focus(null,null);});focusColumn.addView(focus);TextView focusCaption=text("对焦",9,SECONDARY,false);focusCaption.setGravity(Gravity.CENTER);focusCaption.setPadding(0,dp(4),0,0);focusColumn.addView(focusCaption);release.addView(focusColumn,new LayoutParams(0,dp(72),1));controls.addView(release,new LayoutParams(-1,-2));
        if(landscape){ScrollView scroller=new ScrollView(activity);scroller.setFillViewport(false);scroller.setVerticalScrollBarEnabled(false);scroller.addView(controls);body.addView(scroller,new LayoutParams(dp(217),-1));}
        else body.addView(controls,new LayoutParams(-1,-2));
        update();
    }
    @Override protected void onAttachedToWindow(){super.onAttachedToWindow();main.post(tick);}
    @Override protected void onDetachedFromWindow(){main.removeCallbacks(tick);dismissSheet();super.onDetachedFromWindow();}
    public void update(){
        state=controller.state();updating=true;
        identity.setText((state.connected?"•  ":"")+state.model+(state.connected?" · Wi-Fi":" · "+state.connectionStatus));identity.setSingleLine(true);identity.setEllipsize(android.text.TextUtils.TruncateAt.END);
        Long charge=state.parameters.get(0x5001);battery.setText(charge!=null&&charge>=0&&charge<=100?charge+"%":"—");battery.setContentDescription("相机电量 "+battery.getText());
        mode.setText(state.mode()+"  "+state.focus()+" · "+state.release());
        int[] codes={0x500d,0x5007,0x500f,0x5010};for(int i=0;i<4;i++){String value=state.value(codes[i]);if(i==3&&state.parameters.containsKey(codes[i])){SpannableString number=new SpannableString(value+" EV");number.setSpan(new RelativeSizeSpan(.55f),value.length(),number.length(),Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);values[i].setText(number);}else values[i].setText(value);}
        boolean staleParameters=state.connected&&SystemClock.elapsedRealtime()-state.parametersAt>=5000;
        status.setText(staleParameters&&!state.importing&&state.outcome==RemoteCaptureController.Outcome.IDLE?"参数更新中":state.compactMessage());status.setTextColor(state.outcome==RemoteCaptureController.Outcome.UNKNOWN?0xffffb4a7:SECONDARY);
        status.setContentDescription(status.getText()+"，"+(state.outcome==RemoteCaptureController.Outcome.UNKNOWN?"核对拍摄结果":"查看状态详情"));
        shutter.setEnabled(state.canCapture);shutter.invalidate();focus.setEnabled(state.canFocus);focus.setAlpha(state.canFocus?1:.4f);
        if(sheetTransfer!=null){sheetTransfer.setChecked(state.transfer);sheetTransfer.setEnabled(!state.working);}histogramAction.setSelected(histogram);histogramAction.setAlpha(1f);gridAction.setSelected(grid);gridAction.setAlpha(1f);
        ((ImageButton)histogramAction).setColorFilter(histogram?ACCENT:TEXT,PorterDuff.Mode.SRC_IN);((ImageButton)gridAction).setColorFilter(grid?ACCENT:TEXT,PorterDuff.Mode.SRC_IN);
        if(android.os.Build.VERSION.SDK_INT>=30){gridAction.setStateDescription(grid?"已开启":"未开启");histogramAction.setStateDescription(histogram?"已显示":"已收起");}
        if(state.thumbnail!=null){recentImage.setPadding(0,0,0,0);recentImage.setImageBitmap(state.thumbnail);}
        recentAction.setEnabled(state.recent!=null||state.outcome==RemoteCaptureController.Outcome.UNKNOWN);recentAction.setAlpha(recentAction.isEnabled()?1:.45f);
        stage.setContentDescription(state.canPointFocus?"实时取景画面，轻点选择对焦位置":state.histogramFresh()?"实时取景画面，使用对焦按钮对焦":"实时取景暂不可用");stage.invalidate();stage.chart.invalidate();
        stage.chart.setVisibility(histogram?VISIBLE:GONE);
        boolean staleFrame=state.frame!=null&&SystemClock.elapsedRealtime()-state.frame.receivedAt>3000;
        boolean curtain=!state.connected||!state.liveEnabled||state.viewPaused||state.frame==null||staleFrame;
        stage.curtain.setVisibility(curtain?VISIBLE:GONE);
        stage.curtainText.setText(state.opening?"连接中":!state.connected?state.connectionStatus:state.importing?"传输中 · 取景暂停":!state.liveEnabled?"取景已关闭":state.viewPaused||staleFrame?"取景已暂停":"等待取景");
        stage.retry.setText(!state.connected?"重连":"恢复取景");stage.retry.setVisibility(state.opening||state.importing?GONE:VISIBLE);
        if(sheetChart!=null)sheetChart.invalidate();if(sheetStatus!=null)sheetStatus.setText(sheetPurpose.equals("check")||sheetPurpose.equals("status")?state.message:state.histogramFresh()?"根据当前取景帧更新。":"上次取景 · 已暂停");if(sheetPhoto!=null&&state.thumbnail!=null)sheetPhoto.setImageBitmap(state.thumbnail);if(acknowledge!=null)acknowledge.setVisibility(controller.mayAcknowledge()?VISIBLE:GONE);if(checkedRecent!=null)checkedRecent.setVisibility(state.outcome==RemoteCaptureController.Outcome.CONFIRMED&&state.recent!=null?VISIBLE:GONE);
        if(lumaMode!=null){lumaMode.setSelected(!rgb);rgbMode.setSelected(rgb);lumaMode.setBackground(ripple(!rgb?ACCENT:0xff191a18));rgbMode.setBackground(ripple(rgb?ACCENT:0xff191a18));lumaMode.setTextColor(!rgb?INK:TEXT);rgbMode.setTextColor(rgb?INK:TEXT);}
        if(recentImport!=null){boolean available=state.connected&&!state.working&&state.imported==null;recentImport.setEnabled(available);recentImport.setAlpha(available?1:.45f);recentImport.setText(!state.connected?"请先重连":state.imported!=null?"已传入 App":state.working?"处理中":"传入 App");}
        for(Map.Entry<TextView,java.util.function.Supplier<String>> item:liveDetails.entrySet())item.getKey().setText(item.getValue().get());
        updating=false;
    }
    public void saveUi(Bundle out){out.putBoolean("grid",grid);out.putBoolean("histogram",histogram);out.putBoolean("rgb",rgb);out.putFloat("histogramX",histogramX);out.putFloat("histogramY",histogramY);}
    public void restoreUi(Bundle in){if(in==null)return;grid=in.getBoolean("grid",false);histogram=in.getBoolean("histogram",true);rgb=in.getBoolean("rgb",false);histogramX=in.getFloat("histogramX",.03f);histogramY=in.getFloat("histogramY",1f);stage.post(()->{stage.chart.setX(histogramX*Math.max(0,stage.getWidth()-stage.chart.getWidth()));stage.chart.setY(histogramY*Math.max(0,stage.getHeight()-stage.chart.getHeight()));});update();}
    private View icon(AppIcon.Kind kind,String label,Runnable action){ImageButton b=new ImageButton(activity);b.setImageDrawable(kind==AppIcon.Kind.GRID?new CaptureGlyph(1,TEXT):kind==AppIcon.Kind.EXPAND?new CaptureGlyph(2,TEXT):new AppIcon(kind,TEXT,getResources().getDisplayMetrics().density));b.setImageTintList(new ColorStateList(new int[][]{new int[]{android.R.attr.state_selected},new int[]{}},new int[]{ACCENT,TEXT}));b.setPadding(dp(13),dp(13),dp(13),dp(13));b.setBackground(ripple(0));b.setContentDescription(label);b.setTooltipText(label);b.setOnClickListener(v->action.run());b.setLayoutParams(new LayoutParams(dp(48),dp(48)));return b;}
    private LinearLayout column(){LinearLayout v=new LinearLayout(activity);v.setOrientation(VERTICAL);return v;}
    private LinearLayout row(){LinearLayout v=new LinearLayout(activity);v.setOrientation(HORIZONTAL);v.setGravity(Gravity.CENTER_VERTICAL);return v;}
    private TextView text(String value,float size,int color,boolean bold){TextView t=new TextView(activity);t.setText(value);t.setTextSize(size);t.setTextColor(color);t.setIncludeFontPadding(false);t.setTypeface(Typeface.create(bold?"sans-serif-medium":"sans-serif",Typeface.NORMAL));return t;}
    private View divider(){View line=new View(activity);line.setBackgroundColor(LINE);return withHeight(line,1);}
    private View withHeight(View view,int height){view.setLayoutParams(new LayoutParams(-1,dp(height)));return view;}
    private GradientDrawable shape(int color,float radius){GradientDrawable d=new GradientDrawable();d.setColor(color);d.setCornerRadius(dp(radius));return d;}
    private RippleDrawable ripple(int color){return new RippleDrawable(ColorStateList.valueOf(0x26f3b493),shape(color,12),shape(-1,12));}
    private int dp(float v){return Math.round(v*getResources().getDisplayMetrics().density);}
    private interface Toggle {void set(boolean value);}
    private Switch toggle(String title,boolean checked,Toggle action){Switch s=new Switch(activity);s.setText(title);s.setTextSize(13);s.setTextColor(TEXT);s.setChecked(checked);s.setMinHeight(dp(48));s.setSwitchMinWidth(dp(36));s.setSwitchPadding(dp(10));s.setThumbTintList(new ColorStateList(new int[][]{new int[]{android.R.attr.state_checked},new int[]{}},new int[]{ACCENT,0xffcbc7bf}));s.setTrackTintList(new ColorStateList(new int[][]{new int[]{android.R.attr.state_checked},new int[]{}},new int[]{0xffa36b4c,0xff66645f}));s.setOnCheckedChangeListener((v,on)->{if(!updating)action.set(on);});return s;}
    private Button action(String title,Runnable run){Button b=new Button(activity);b.setText(title);b.setTextSize(13);b.setAllCaps(false);b.setTextColor(INK);b.setBackground(ripple(ACCENT));b.setMinHeight(dp(48));b.setOnClickListener(v->run.run());return b;}
    private void statusDetails(){
        if(state==null)return;
        LinearLayout panel=openSheet("状态详情");sheetPurpose="status";
        boundDetail(panel,"连接",()->state.connectionStatus);
        sheetStatus=text(state.message,13,TEXT,false);sheetStatus.setPadding(0,dp(12),0,dp(12));panel.addView(sheetStatus);
        if(!state.viewMessage.isEmpty())note(panel,state.viewMessage);
        if(state.importing)note(panel,state.importProgress.details(cc.huevia.album.PhotoTransferProgress.now()));
        if(!state.connected&&!state.opening)panel.addView(action("重连",()->{dismissSheet();controller.reconnect();}),new LayoutParams(-1,dp(48)));
        else if(state.connected&&state.viewPaused&&!state.importing)panel.addView(action("恢复取景",()->{dismissSheet();controller.retryView();}),new LayoutParams(-1,dp(48)));
    }
    private LinearLayout openSheet(String title){
        dismissSheet();sheet=new Dialog(activity);LinearLayout panel=column();panel.setPadding(dp(20),dp(14),dp(20),dp(20));panel.setBackground(shape(PANEL,24));
        LinearLayout heading=row();TextView name=text(title,17,TEXT,true);heading.addView(name,new LayoutParams(0,-2,1));heading.addView(icon(AppIcon.Kind.CLOSE,"关闭",this::dismissSheet));panel.addView(heading);
        ScrollView scroll=new ScrollView(activity);scroll.setFillViewport(false);scroll.addView(panel);sheet.setContentView(scroll);sheet.setOnDismissListener(d->{sheet=null;sheetChart=null;sheetPhoto=null;sheetStatus=null;acknowledge=null;recentImport=null;sheetTransfer=null;});
        Window window=sheet.getWindow();window.setBackgroundDrawableResource(android.R.color.transparent);window.addFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND);WindowManager.LayoutParams p=window.getAttributes();p.dimAmount=.55f;p.gravity=landscape?Gravity.RIGHT:Gravity.BOTTOM;p.width=landscape?dp(390):getWidth();p.height=landscape?-1:-2;window.setAttributes(p);sheet.show();window.setLayout(landscape?dp(390):getWidth(),landscape?-1:Math.min(dp(600),Math.round(getHeight()*.78f)));return panel;
    }
    private void dismissSheet(){if(sheet!=null){Dialog value=sheet;sheet=null;value.dismiss();}sheetChart=null;sheetPhoto=null;sheetStatus=null;acknowledge=null;checkedRecent=null;lumaMode=rgbMode=recentImport=null;sheetTransfer=null;sheetPurpose="";liveDetails.clear();}
    private void note(LinearLayout panel,String copy){TextView t=text(copy,11,SECONDARY,false);t.setLineSpacing(dp(4),1);t.setPadding(0,dp(10),0,dp(14));panel.addView(t);}
    private Switch setting(LinearLayout panel,String title,String description,boolean checked,Toggle action){Switch s=toggle(title,checked,action);panel.addView(s,new LayoutParams(-1,dp(48)));note(panel,description);panel.addView(divider());return s;}
    private void settings(){LinearLayout panel=openSheet("拍摄设置");detail(panel,"照片保存位置","相机存储卡");
        sheetTransfer=setting(panel,"拍后传入 App","照片仍保存在相机，JPEG 另传入 App",state.transfer,controller::setTransfer);
        setting(panel,"实时取景","关闭后仍可查看参数和按快门",state.liveEnabled,on->{controller.setLiveEnabled(on);});
        setting(panel,"构图网格","仅辅助构图，不写入照片",grid,on->{grid=on;update();});
        Button details=action("查看机身参数",this::parameters);details.setBackground(ripple(0));details.setTextColor(TEXT);details.setGravity(Gravity.CENTER_VERTICAL|Gravity.LEFT);details.setPadding(0,0,dp(8),0);details.setCompoundDrawablesWithIntrinsicBounds(null,null,new AppIcon(AppIcon.Kind.CHEVRON,TEXT,getResources().getDisplayMetrics().density),null);panel.addView(details,new LayoutParams(-1,dp(48)));panel.addView(divider());
        Button disconnect=action("断开相机连接",()->{dismissSheet();controller.disconnect();});disconnect.setTextColor(0xffffb4a7);disconnect.setBackground(ripple(0));LayoutParams gap=new LayoutParams(-1,dp(48));gap.topMargin=dp(12);panel.addView(disconnect,gap);note(panel,"返回同步会结束取景，保留相机连接。原始文件保存位置沿用同步设置。");update();}
    private void detail(LinearLayout panel,String label,String value){LinearLayout line=row();line.setPadding(0,dp(14),0,dp(14));TextView key=text(label,13,SECONDARY,false);line.addView(key,new LayoutParams(0,-2,1));TextView val=text(value,13,TEXT,false);val.setGravity(Gravity.END);line.addView(val,new LayoutParams(0,-2,1));panel.addView(line);panel.addView(divider());}
    private void boundDetail(LinearLayout panel,String label,java.util.function.Supplier<String> value){LinearLayout line=row();line.setPadding(0,dp(14),0,dp(14));TextView key=text(label,13,SECONDARY,false);line.addView(key,new LayoutParams(0,-2,1));TextView val=text(value.get(),13,TEXT,false);val.setGravity(Gravity.END);line.addView(val,new LayoutParams(0,-2,1));panel.addView(line);panel.addView(divider());liveDetails.put(val,value);}
    private void parameters(){LinearLayout panel=openSheet("机身当前参数");note(panel,"参数只读，请在相机上调整。未提供的项目显示 —。");boundDetail(panel,"机型",()->state.model);boundDetail(panel,"拍摄模式",()->state.mode());boundDetail(panel,"快门",()->state.value(0x500d));boundDetail(panel,"光圈",()->state.value(0x5007));boundDetail(panel,"ISO",()->state.value(0x500f));boundDetail(panel,"曝光补偿",()->state.value(0x5010)+" EV");boundDetail(panel,"对焦模式",()->state.focus());boundDetail(panel,"释放模式",()->state.release());boundDetail(panel,"图像品质",()->state.quality());note(panel,"相机当前未开放的能力保持禁用；取景中断和相机断开分别显示。");}
    private void histogram(){LinearLayout panel=openSheet("取景直方图");sheetStatus=text(state.histogramFresh()?"根据当前取景帧更新。":"上次取景 · 已暂停",11,SECONDARY,false);sheetStatus.setPadding(0,dp(10),0,dp(16));panel.addView(sheetStatus);
        LinearLayout modes=row();lumaMode=action("亮度",()->{rgb=false;update();});rgbMode=action("RGB",()->{rgb=true;update();});modes.addView(lumaMode,new LayoutParams(0,dp(48),1));LayoutParams rgbParams=new LayoutParams(0,dp(48),1);rgbParams.leftMargin=dp(8);modes.addView(rgbMode,rgbParams);panel.addView(modes);
        sheetChart=new Chart(true);LayoutParams chartParams=new LayoutParams(-1,dp(160));chartParams.topMargin=dp(20);panel.addView(sheetChart,chartParams);detail(panel,"暗部","亮部");
        note(panel,"R 红     G 绿     B 蓝");Switch show=toggle("显示在取景页",histogram,on->{histogram=on;update();});panel.addView(show,new LayoutParams(-1,dp(48)));note(panel,"点按放大，拖动小图可调整位置。取景图经过相机处理，分布仅供曝光参考，不是 RAW 原始数据。");update();}
    private void recent(){if(state.recent==null){if(state.outcome==RemoteCaptureController.Outcome.UNKNOWN)checkResult();return;}LinearLayout panel=openSheet("最近拍摄");sheetPhoto=new ImageView(activity);sheetPhoto.setScaleType(ImageView.ScaleType.FIT_CENTER);if(state.thumbnail!=null)sheetPhoto.setImageBitmap(state.thumbnail);panel.addView(sheetPhoto,new LayoutParams(-1,dp(210)));detail(panel,"文件",state.recent.object.filename());detail(panel,"状态",state.imported==null?"已保存到相机":"已传入 App");if(state.recent.jpeg()&&state.imported==null){recentImport=action("传入 App",()->{if(!controller.state().connected||controller.state().working){update();return;}controller.importRecent();dismissSheet();});panel.addView(recentImport,new LayoutParams(-1,dp(48)));if(!state.connected)note(panel,"相机已断开。预览仍可查看，返回取景页重新连接后可传入 JPEG。");update();}else if(!state.recent.jpeg())note(panel,"当前为 RAW；本页仅自动传入 JPEG。可返回同步查看原文件。");}
    private void checkResult(){LinearLayout panel=openSheet("核对拍摄结果");sheetPurpose="check";note(panel,"快门请求没有收到完整结果。为避免重复拍摄，不会自动重发。请先查看相机的最近照片，再恢复拍摄。");panel.addView(action("查看相机最近照片",()->{controller.verifyUnknown();}),new LayoutParams(-1,dp(48)));sheetStatus=text(state.message,12,SECONDARY,false);sheetStatus.setPadding(0,dp(16),0,dp(16));panel.addView(sheetStatus);acknowledge=action("已核对相机，恢复拍摄",()->{controller.acknowledgeChecked();dismissSheet();});acknowledge.setVisibility(controller.mayAcknowledge()?VISIBLE:GONE);panel.addView(acknowledge,new LayoutParams(-1,dp(48)));checkedRecent=action("查看最近拍摄",this::recent);checkedRecent.setVisibility(GONE);panel.addView(checkedRecent,new LayoutParams(-1,dp(48)));}
    private final class CaptureGlyph extends Drawable {
        final int kind;final Paint paint=new Paint(Paint.ANTI_ALIAS_FLAG);
        CaptureGlyph(int kind,int color){this.kind=kind;paint.setColor(color);paint.setStyle(Paint.Style.STROKE);paint.setStrokeWidth(1.7f);paint.setStrokeCap(Paint.Cap.ROUND);paint.setStrokeJoin(Paint.Join.ROUND);}
        @Override public void draw(Canvas c){int save=c.save();c.translate(getBounds().left,getBounds().top);c.scale(getBounds().width()/24f,getBounds().height()/24f);
            if(kind==0){c.drawRoundRect(1,6,21,18,2,2,paint);c.drawLine(23,10,23,14,paint);c.drawLine(5,10,15,10,paint);c.drawLine(5,14,15,14,paint);}
            else if(kind==1){c.drawRoundRect(3,3,21,21,1,1,paint);for(int n:new int[]{9,15}){c.drawLine(n,3,n,21,paint);c.drawLine(3,n,21,n,paint);}}
            else{for(int x:new int[]{3,21})for(int y:new int[]{3,21}){c.drawLine(x,y,x+(x==3?5:-5),y,paint);c.drawLine(x,y,x,y+(y==3?5:-5),paint);}c.drawCircle(12,12,3,paint);}c.restoreToCount(save);}
        @Override public void setAlpha(int alpha){paint.setAlpha(alpha);invalidateSelf();}
        @Override public void setColorFilter(ColorFilter filter){paint.setColorFilter(filter);invalidateSelf();}
        @Override public int getOpacity(){return PixelFormat.TRANSLUCENT;}
        @Override public int getIntrinsicWidth(){return dp(24);}@Override public int getIntrinsicHeight(){return dp(24);}
    }
    private final class Shutter extends View {
        final Paint paint=new Paint(Paint.ANTI_ALIAS_FLAG);
        Shutter(){super(activity);}
        @Override protected void onDraw(Canvas canvas){float cx=getWidth()/2f,cy=getHeight()/2f,r=Math.min(cx,cy)-dp(2);paint.setColor(ACCENT);paint.setAlpha(isEnabled()?255:105);paint.setStyle(Paint.Style.STROKE);paint.setStrokeWidth(dp(2));canvas.drawCircle(cx,cy,r,paint);paint.setStyle(Paint.Style.FILL);canvas.drawCircle(cx,cy,r-dp(7),paint);if(state!=null&&(state.outcome==RemoteCaptureController.Outcome.PREPARING||state.outcome==RemoteCaptureController.Outcome.CAPTURING)){paint.setColor(INK);canvas.drawRoundRect(cx-dp(10),cy-dp(10),cx+dp(10),cy+dp(10),dp(3),dp(3),paint);}if(isFocused()){paint.setStyle(Paint.Style.STROKE);paint.setColor(TEXT);paint.setStrokeWidth(dp(2));canvas.drawCircle(cx,cy,r-dp(3),paint);}}
        @Override public void onInitializeAccessibilityNodeInfo(AccessibilityNodeInfo info){super.onInitializeAccessibilityNodeInfo(info);info.setClassName(Button.class.getName());}
    }
    private final class FrameStage extends FrameLayout {
        final Paint paint=new Paint(Paint.ANTI_ALIAS_FLAG|Paint.FILTER_BITMAP_FLAG);
        final RectF image=new RectF();final Chart chart=new Chart(false);final LinearLayout curtain;final TextView curtainText;final Button retry;
        float focusX=.5f,focusY=.5f;boolean focusVisible;
        float downX,downY,startX,startY;boolean dragging;Double tapX,tapY;
        FrameStage(){super(activity);setWillNotDraw(false);setBackgroundColor(0xff090a0a);setFocusable(true);setClickable(true);
            FrameLayout.LayoutParams chartLayout=new FrameLayout.LayoutParams(dp(190),dp(64),Gravity.BOTTOM|Gravity.LEFT);chartLayout.setMargins(dp(12),0,dp(12),dp(4));addView(chart,chartLayout);chart.setContentDescription("取景直方图，点按放大，拖动调整位置");chart.setFocusable(true);chart.setOnClickListener(v->histogram());
            chart.setOnTouchListener((v,event)->{switch(event.getActionMasked()){case MotionEvent.ACTION_DOWN:downX=event.getRawX();downY=event.getRawY();startX=chart.getX();startY=chart.getY();dragging=false;return true;case MotionEvent.ACTION_MOVE:float dx=event.getRawX()-downX,dy=event.getRawY()-downY;if(Math.hypot(dx,dy)>dp(8))dragging=true;if(dragging){chart.setX(Math.max(0,Math.min(getWidth()-chart.getWidth(),startX+dx)));chart.setY(Math.max(0,Math.min(getHeight()-chart.getHeight(),startY+dy)));histogramX=chart.getX()/Math.max(1,getWidth()-chart.getWidth());histogramY=chart.getY()/Math.max(1,getHeight()-chart.getHeight());}return true;case MotionEvent.ACTION_UP:if(!dragging)v.performClick();return true;case MotionEvent.ACTION_CANCEL:return true;default:return false;}});
            curtain=column();curtain.setGravity(Gravity.CENTER);curtain.setPadding(dp(24),dp(16),dp(24),dp(16));curtain.setBackgroundColor(0xd9121313);curtainText=text("等待实时画面…",14,TEXT,false);curtainText.setGravity(Gravity.CENTER);curtain.addView(curtainText);retry=action("恢复实时取景",()->{if(!state.connected)controller.reconnect();else{controller.setLiveEnabled(true);controller.retryView();}});LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(-2,dp(48));p.topMargin=dp(12);curtain.addView(retry,p);addView(curtain,new FrameLayout.LayoutParams(-1,-1));chart.bringToFront();}
        @Override protected void onSizeChanged(int w,int h,int oldw,int oldh){super.onSizeChanged(w,h,oldw,oldh);chart.post(()->{chart.setX(histogramX*Math.max(0,w-chart.getWidth()));chart.setY(histogramY*Math.max(0,h-chart.getHeight()));});}
        @Override protected void onDraw(Canvas canvas){super.onDraw(canvas);image.setEmpty();if(state==null||state.frame==null)return;Bitmap b=state.frame.bitmap;if(b.isRecycled())return;float scale=Math.min(getWidth()/(float)b.getWidth(),getHeight()/(float)b.getHeight());float width=b.getWidth()*scale,height=b.getHeight()*scale;image.set((getWidth()-width)/2,(getHeight()-height)/2,(getWidth()+width)/2,(getHeight()+height)/2);paint.setAlpha(255);canvas.drawBitmap(b,null,image,paint);
            if(grid){paint.setColor(0x88ffffff);paint.setStrokeWidth(dp(1));for(int i=1;i<3;i++){canvas.drawLine(image.left+image.width()*i/3,image.top,image.left+image.width()*i/3,image.bottom,paint);canvas.drawLine(image.left,image.top+image.height()*i/3,image.right,image.top+image.height()*i/3,paint);}}
            if(focusVisible&&state.canFocus){paint.setColor(state.frame.wire.focusKnown&&state.frame.wire.focused?0xff9ac8ae:ACCENT);paint.setStyle(Paint.Style.STROKE);paint.setStrokeWidth(dp(2));float x=image.left+focusX*image.width(),y=image.top+focusY*image.height();canvas.drawRect(x-dp(24),y-dp(20),x+dp(24),y+dp(20),paint);paint.setStyle(Paint.Style.FILL);}}
        @Override public boolean onTouchEvent(MotionEvent e){if(e.getActionMasked()==MotionEvent.ACTION_UP&&state!=null&&state.canPointFocus&&image.contains(e.getX(),e.getY())){focusX=(e.getX()-image.left)/image.width();focusY=(e.getY()-image.top)/image.height();tapX=(double)focusX;tapY=(double)focusY;performClick();invalidate();return true;}return state!=null&&state.canPointFocus;}
        @Override public boolean performClick(){super.performClick();if(state!=null&&state.canFocus){focusVisible=true;controller.focus(tapX,tapY);tapX=tapY=null;}return true;}
    }
    private final class Chart extends View {
        final boolean large;final Paint ink=new Paint(Paint.ANTI_ALIAS_FLAG);final Path path=new Path();
        Chart(boolean large){super(activity);this.large=large;setBackground(shape(0xff191a18,9));}
        @Override protected void onDraw(Canvas canvas){super.onDraw(canvas);if(state==null)return;boolean fresh=state.histogramFresh();int pad=dp(9),top=large?dp(12):dp(23),bottom=getHeight()-dp(8);ink.setStyle(Paint.Style.FILL);ink.setTextSize(dp(large?11:9)*getResources().getConfiguration().fontScale);ink.setColor(fresh?TEXT:SECONDARY);if(!large)canvas.drawText(fresh?"取景"+(rgb?" · RGB":" · 亮度"):state.frame==null?"等待取景":"上次取景 · 已暂停",pad,dp(14),ink);
            PhotoHistogram data=state.frame==null?null:state.frame.histogram;if(data==null)return;long max=rgb?data.sharedRgbMaximum():data.max(PhotoHistogram.Channel.LUMINANCE);if(max<1)return;
            PhotoHistogram.Channel[] channels=rgb?new PhotoHistogram.Channel[]{PhotoHistogram.Channel.RED,PhotoHistogram.Channel.GREEN,PhotoHistogram.Channel.BLUE}:new PhotoHistogram.Channel[]{PhotoHistogram.Channel.LUMINANCE};int[] colors=rgb?new int[]{0xffff707c,0xff95cca8,0xff79a9ff}:new int[]{0xffc7c4bb};
            for(int c=0;c<channels.length;c++){path.reset();path.moveTo(pad,bottom);for(int x=0;x<256;x++){float px=pad+x*(getWidth()-2f*pad)/255,py=bottom-data.count(channels[c],x)*(bottom-top)/(float)max;path.lineTo(px,py);}path.lineTo(getWidth()-pad,bottom);if(!rgb){path.close();ink.setStyle(Paint.Style.FILL);ink.setColor(colors[c]);ink.setAlpha(fresh?190:70);canvas.drawPath(path,ink);}ink.setStyle(Paint.Style.STROKE);ink.setStrokeWidth(dp(large?1.5f:1));ink.setColor(colors[c]);ink.setAlpha(fresh?255:90);canvas.drawPath(path,ink);}ink.setAlpha(255);ink.setStyle(Paint.Style.FILL);
        }
    }
}
