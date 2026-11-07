package cc.huevia.ui;

import android.animation.ValueAnimator;
import android.content.Context;
import android.content.res.ColorStateList;
import android.graphics.*;
import android.graphics.drawable.*;
import android.view.*;
import android.widget.*;
import cc.huevia.ncp.PhotoQuickPreset;

/** Photo-first editor: text destinations below one directly accessible tool rail. */
final class PhotoCompactDock extends LinearLayout {
    static final int OPTIMIZE=0,FILTER=1,PORTRAIT=2,ADJUST=3,CROP=4,ADVANCED=5,RECIPE=6,BORDER=7;
    static final int PANEL_HEIGHT_DP=184;
    private static final int[] DESTINATIONS={FILTER,ADJUST,CROP,PORTRAIT,BORDER};
    interface Host {
        boolean ready();boolean canUndo();boolean canRedo();void history(boolean redo);
        Bitmap thumbnail();int quickStyle();int quickAmount();boolean quickBusy();String quickMessage();
        void quick(int style);void quickAmount(int amount);void beginDrag();void endDrag();
        void legacy(int mode);void portrait(int section);String effectLabel();void reset();void openComposition();
    }
    private static final int BG=0xff141415,PANEL=0xff201f1d,TEXT=0xfff6f1eb,MUTED=0xffbab1a7,ACCENT=PhotoPrismaStyle.YELLOW;
    private final Host host;
    private final FrameLayout panels,compare;
    private final View legacy;
    private final LinearLayout quickPanel,portraitPanel;
    private final Button[] tabs=new Button[DESTINATIONS.length];
    private final LinearLayout[] cards=new LinearLayout[4],portraitTools=new LinearLayout[4];
    private final ImageView[] previews=new ImageView[4];
    private final Button undo,redo;
    private final SeekBar quickSlider,portraitSlider;
    private final TextView quickValue,portraitValue,quickHint,effectName;
    private final HorizontalScrollView navigation;
    private Bitmap shownThumbnail;
    private int mode=FILTER;
    private boolean updating;

    PhotoCompactDock(Context context,View legacy,Host host){
        super(context);this.host=host;this.legacy=legacy;
        setOrientation(VERTICAL);setBackgroundColor(Color.TRANSPARENT);setTag("compact-editor-dock");
        LinearLayout history=row();history.setPadding(dp(12),0,dp(12),0);history.setBackgroundColor(Color.TRANSPARENT);
        undo=icon(AppIcon.Kind.UNDO,"撤销",()->host.history(false));
        redo=icon(AppIcon.Kind.REDO,"重做",()->host.history(true));
        history.addView(undo,new LayoutParams(dp(48),dp(48)));
        history.addView(redo,new LayoutParams(dp(48),dp(48)));
        effectName=text("原图",10,0xeeffffff);effectName.setTag("editor-effect-name");effectName.setGravity(Gravity.CENTER);effectName.setSingleLine(true);effectName.setEllipsize(android.text.TextUtils.TruncateAt.END);history.addView(effectName,new LayoutParams(0,dp(48),1));
        compare=new FrameLayout(context);compare.setTag("editor-original-compare-mount");
        Button reset=icon(AppIcon.Kind.REFRESH,"重置编辑",host::reset);reset.setTag("editor-reset");reset.setBackground(PhotoPrismaStyle.iconFace(context,AppIcon.Kind.REFRESH,0x6e0e1513));history.addView(reset,new LayoutParams(dp(48),dp(48)));addView(history);

        panels=new FrameLayout(context);panels.setTag("compact-editor-panels");
        addView(panels,new LayoutParams(-1,panelHeightPx()));
        quickPanel=column();quickPanel.setPadding(dp(16),dp(8),dp(16),dp(8));
        quickPanel.setTag("editor-quick-panel");panels.addView(quickPanel,new FrameLayout.LayoutParams(-1,-1));
        LinearLayout choices=row();String[] names={"原图","自然","通透","人像"};
        for(int i=0;i<4;i++){
            final int style=i;LinearLayout card=column();cards[i]=card;
            card.setGravity(Gravity.CENTER_HORIZONTAL);card.setFocusable(true);card.setClickable(true);
            card.setTag("editor-quick-style-"+i);card.setContentDescription("快速优化，"+names[i]);
            card.setBackground(new RippleDrawable(ColorStateList.valueOf(0x22ffe335),null,shape(Color.WHITE,9)));
            ImageView image=new ImageView(context);image.setScaleType(ImageView.ScaleType.CENTER_CROP);
            image.setBackground(shape(0xff33302c,9));image.setClipToOutline(true);
            image.setImportantForAccessibility(IMPORTANT_FOR_ACCESSIBILITY_NO);previews[i]=image;
            card.addView(image,new LayoutParams(-1,dp(52)));
            TextView caption=text(names[i],12,MUTED);caption.setGravity(Gravity.CENTER);
            LayoutParams cp=new LayoutParams(-1,scaled(22));cp.topMargin=dp(4);card.addView(caption,cp);
            card.setOnClickListener(v->host.quick(style));LayoutParams p=new LayoutParams(0,-2,1);
            if(i>0)p.leftMargin=dp(10);choices.addView(card,p);
        }
        quickPanel.addView(choices,new LayoutParams(-1,0,1));
        LinearLayout qv=row();
        quickHint=text("强度",11,MUTED);quickHint.setSingleLine(true);
        quickHint.setAccessibilityLiveRegion(ACCESSIBILITY_LIVE_REGION_POLITE);
        qv.addView(quickHint,new LayoutParams(scaled(52),-1));
        quickSlider=slider("优化强度",false);qv.addView(quickSlider,new LayoutParams(0,dp(48),1));
        quickValue=text("0",12,ACCENT);quickValue.setGravity(Gravity.END|Gravity.CENTER_VERTICAL);
        qv.addView(quickValue,new LayoutParams(scaled(32),-1));
        quickPanel.addView(qv,new LayoutParams(-1,dp(48)));

        portraitPanel=column();portraitPanel.setTag("editor-portrait-panel");
        portraitPanel.setPadding(dp(16),dp(8),dp(16),dp(4));
        panels.addView(portraitPanel,new FrameLayout.LayoutParams(-1,-1));
        LinearLayout ph=row();ph.addView(text("自然精修",11,MUTED),new LayoutParams(scaled(64),-1));
        portraitSlider=slider("人像自然精修强度",true);
        ph.addView(portraitSlider,new LayoutParams(0,dp(48),1));
        portraitValue=text("0",12,ACCENT);portraitValue.setGravity(Gravity.END|Gravity.CENTER_VERTICAL);
        ph.addView(portraitValue,new LayoutParams(scaled(40),-1));portraitPanel.addView(ph,new LayoutParams(-1,dp(48)));
        portraitPanel.addView(new View(context),new LayoutParams(1,0,1));
        LinearLayout people=row();String[] groups={"自然精修","皮肤","面部","塑形"};
        AppIcon.Kind[] peopleIcons={AppIcon.Kind.CLEANUP,AppIcon.Kind.TINT,AppIcon.Kind.PERSON,AppIcon.Kind.BODY};
        for(int i=0;i<4;i++){
            final int section=i;
            LinearLayout item=PhotoWorkspaceUi.toolEntry(context,groups[i],"editor-portrait-section-"+i,peopleIcons[i],()->{
                if(section==0)host.quick(PhotoQuickPreset.PORTRAIT);else host.portrait(section);
            });
            portraitTools[i]=item;
            people.addView(item,new LayoutParams(0,PhotoWorkspaceUi.entryHeight(context),1));
        }
        portraitPanel.addView(people);
        panels.addView(legacy,new FrameLayout.LayoutParams(-1,-1));

        navigation=new HorizontalScrollView(context);navigation.setTag("editor-primary-navigation");
        navigation.setFillViewport(true);navigation.setHorizontalScrollBarEnabled(false);
        navigation.setOverScrollMode(OVER_SCROLL_NEVER);navigation.setBackgroundColor(Color.TRANSPARENT);
        navigation.setContentDescription("编辑分类，左右滑动查看更多");
        LinearLayout nav=row();nav.setPadding(dp(14),0,dp(14),0);String[] labels={"滤镜","调节","裁切","人像","边框"};
        for(int i=0;i<DESTINATIONS.length;i++){
            final int selected=DESTINATIONS[i];Button tab=action(labels[i],()->choose(selected));tabs[i]=tab;
            tab.setTag("editor-primary-"+selected);tab.setSingleLine(true);
            styleTab(tab,i,false);
            tab.setOnLongClickListener(v->{if(selected==CROP)host.openComposition();else if(selected==FILTER)host.legacy(ADVANCED);return selected==CROP||selected==FILTER;});nav.addView(tab,new LayoutParams(0,primaryHeight(),1));
        }
        navigation.addView(nav,new HorizontalScrollView.LayoutParams(-1,-1));
        addView(navigation,1,new LayoutParams(-1,primaryHeight()));refresh();
    }

    FrameLayout comparisonMount(){return null;}
    int mode(){return mode;}
    int panelHeightDp(){return PANEL_HEIGHT_DP;}
    int panelHeightPx(){return PhotoPrismaStyle.compact(getContext())?dp(160):scaled(PANEL_HEIGHT_DP);}
    private int primaryHeight(){return PhotoPrismaStyle.compact(getContext())?dp(67):scaled(67);}
    void choose(int next){
        host.endDrag();mode=next==ADVANCED?ADJUST:next;
        host.legacy(mode);
        refresh();
        for(int i=0;i<DESTINATIONS.length;i++)if(mode==DESTINATIONS[i])PhotoWorkspaceUi.revealChoice(navigation,tabs[i]);
        if(ValueAnimator.areAnimatorsEnabled()){
            panels.animate().cancel();panels.setTranslationY(dp(5));
            panels.animate().translationY(0).setDuration(180).start();
        }
    }
    void refresh(){
        updating=true;boolean usable=host.ready();effectName.setText(host.effectLabel());
        undo.setEnabled(host.canUndo());redo.setEnabled(host.canRedo());
        undo.setAlpha(undo.isEnabled()?1:.3f);redo.setAlpha(redo.isEnabled()?1:.3f);
        quickPanel.setVisibility(mode==OPTIMIZE?VISIBLE:GONE);
        portraitPanel.setVisibility(mode==PORTRAIT?VISIBLE:GONE);
        legacy.setVisibility(mode!=OPTIMIZE&&mode!=PORTRAIT?VISIBLE:GONE);
        int panelHeight=panelHeightPx();
        if(panels.getLayoutParams().height!=panelHeight){panels.getLayoutParams().height=panelHeight;panels.requestLayout();}
        for(int i=0;i<tabs.length;i++){
            styleTab(tabs[i],i,mode==DESTINATIONS[i]);
            tabs[i].setEnabled(usable);tabs[i].setAlpha(usable?1:.45f);
        }
        int selected=host.quickStyle();
        for(int i=0;i<4;i++){
            cards[i].setEnabled(usable);cards[i].setAlpha(usable?1:.4f);
            ((TextView)cards[i].getChildAt(1)).setTextColor(i==selected?PhotoPrismaStyle.SELECTION_LABEL:MUTED);
            GradientDrawable border=shape(Color.TRANSPARENT,9);if(i==selected)border.setStroke(dp(1),PhotoPrismaStyle.SELECTION_FRAME);
            previews[i].setForeground(border);cards[i].setSelected(i==selected);
            portraitTools[i].setEnabled(usable&&!host.quickBusy());portraitTools[i].setAlpha(portraitTools[i].isEnabled()?1:.4f);
        }
        Bitmap thumb=host.thumbnail();
        if(thumb!=shownThumbnail){shownThumbnail=thumb;for(ImageView image:previews)image.setImageBitmap(thumb);}
        quickSlider.setProgress(host.quickAmount());
        quickSlider.setEnabled(usable&&!host.quickBusy()&&selected>0);
        quickValue.setText(selected>0?String.valueOf(host.quickAmount()):"—");
        quickHint.setText(host.quickBusy()?"分析中":selected<0?"已调整":"强度");
        quickHint.setContentDescription(host.quickBusy()?"正在分析照片":host.quickMessage().isEmpty()?"效果强度":host.quickMessage());
        portraitSlider.setProgress(selected==PhotoQuickPreset.PORTRAIT?host.quickAmount():0);
        portraitSlider.setEnabled(usable&&!host.quickBusy()&&selected==PhotoQuickPreset.PORTRAIT);
        portraitValue.setText(host.quickBusy()?"分析中":selected==PhotoQuickPreset.PORTRAIT?String.valueOf(host.quickAmount()):"—");
        updating=false;
    }
    private void styleTab(Button tab,int index,boolean selected){
        AppIcon.Kind[] icons={AppIcon.Kind.FILTER,AppIcon.Kind.ADJUST,AppIcon.Kind.CROP,AppIcon.Kind.PERSON,AppIcon.Kind.FRAME};
        tab.setTextSize(10.5f);tab.setTypeface(Typeface.create("sans-serif",Typeface.NORMAL));tab.setTextColor(selected?ACCENT:Color.WHITE);tab.setSelected(selected);
        tab.setGravity(Gravity.CENTER);tab.setPadding(0,dp(3),0,dp(2));tab.setCompoundDrawablePadding(dp(4));tab.setIncludeFontPadding(false);
        Drawable icon=PhotoPrismaStyle.circle(getContext(),icons[index],selected);icon.setBounds(0,0,dp(39),dp(39));tab.setCompoundDrawables(null,icon,null,null);tab.setBackgroundColor(Color.TRANSPARENT);tab.setBackgroundTintList(null);
        tab.setContentDescription(tab.getText()+(selected?"，当前工具":"")+(DESTINATIONS[index]==CROP?"，长按打开精细构图":DESTINATIONS[index]==FILTER?"，长按查看全部滤镜":""));
    }
    private SeekBar slider(String description,boolean portrait){
        SeekBar b=new SeekBar(getContext());b.setTag(portrait?"editor-portrait-quick-slider":"editor-quick-slider");
        b.setMax(100);b.setProgressTintList(ColorStateList.valueOf(ACCENT));
        b.setThumbTintList(ColorStateList.valueOf(ACCENT));PhotoPrismaStyle.slider(getContext(),b);b.setContentDescription(description);
        b.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener(){
            public void onProgressChanged(SeekBar bar,int value,boolean user){if(user&&!updating){host.quickAmount(value);quickValue.setText(String.valueOf(value));portraitValue.setText(String.valueOf(value));}}
            public void onStartTrackingTouch(SeekBar bar){host.beginDrag();}
            public void onStopTrackingTouch(SeekBar bar){host.endDrag();}
        });return b;
    }
    private Button icon(AppIcon.Kind kind,String label,Runnable action){
        Button b=action("",action);b.setBackground(PhotoPrismaStyle.iconFace(getContext(),kind,Color.TRANSPARENT));
        b.setContentDescription(label);b.setPadding(0,0,0,0);return b;
    }
    private Button action(String label,Runnable action){
        Button b=new Button(getContext());b.setText(label);b.setAllCaps(false);b.setTextSize(12);b.setTextColor(MUTED);
        b.setMinWidth(0);b.setMinimumWidth(0);b.setMinHeight(dp(48));b.setMinimumHeight(dp(48));
        b.setPadding(dp(5),0,dp(5),0);b.setStateListAnimator(null);b.setBackgroundTintList(null);
        b.setBackground(new RippleDrawable(ColorStateList.valueOf(0x22ffe335),null,shape(Color.WHITE,8)));
        b.setOnClickListener(v->action.run());return b;
    }
    private LinearLayout column(){LinearLayout v=new LinearLayout(getContext());v.setOrientation(VERTICAL);return v;}
    private LinearLayout row(){LinearLayout v=new LinearLayout(getContext());v.setGravity(Gravity.CENTER_VERTICAL);return v;}
    private TextView text(String value,int size,int color){
        TextView v=new TextView(getContext());v.setText(value);v.setTextSize(size);v.setTextColor(color);
        v.setGravity(Gravity.CENTER_VERTICAL);v.setIncludeFontPadding(false);return v;
    }
    private GradientDrawable shape(int color,int radius){GradientDrawable d=new GradientDrawable();d.setColor(color);d.setCornerRadius(dp(radius));return d;}
    private int dp(float value){return Math.round(value*getResources().getDisplayMetrics().density);}
    private int scaled(float value){return dp(value*Math.max(1,getResources().getConfiguration().fontScale));}
}
