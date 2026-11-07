package cc.huevia.ui;

import android.app.Activity;
import android.content.Context;
import android.content.res.ColorStateList;
import android.graphics.Bitmap;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.text.TextUtils;
import android.view.Gravity;
import android.view.View;
import android.widget.*;
import cc.huevia.album.*;
import cc.huevia.ncp.PresetPreviewProfile;
import java.io.IOException;
import java.util.*;
import java.util.function.BooleanSupplier;
import java.util.function.Consumer;

/** One frozen selection shared by quick save, advanced settings, previews and the real export queue. */
public final class PhotoVersionExport {
    private final int TEXT,MUTED,ACCENT,FIELD;
    public static final class Choice {
        public final String id,label;
        public final PhotoPresetBatch.Edit edit;
        public final PhotoExportDialog.Item item;
        public final boolean current;
        public final PresetPreviewProfile profile;
        Choice(String id,String label,PhotoPresetBatch.Edit edit,PhotoExportDialog.Item item,boolean current) throws IOException {this.id=id;this.label=label;this.edit=edit;this.item=item;this.current=current;this.profile=edit.draft==null?cc.huevia.ncp.AdjustedPreviewProfile.of(null,cc.huevia.ncp.PhotoAdjustments.NONE):edit.draft.profile();}
    }
    public static final class Data {
        public final List<Choice> choices;
        public final int photoCount,allCount;
        public final boolean hasVersions,allOverLimit;
        Data(List<Choice> choices,int photos,int all,boolean versions,boolean over){this.choices=Collections.unmodifiableList(choices);photoCount=photos;allCount=all;hasVersions=versions;allOverLimit=over;}
    }
    /** Worker only. Saved versions always use their own bytes; only an explicit active edit carries a profile. */
    public static Data prepare(Context context,List<DownloadedPhoto> photos,PhotoPresetBatch.Edit active,Bitmap activeThumbnail,String owner,BooleanSupplier cancel) throws IOException {
        LocalPhotoRepository repository=new LocalPhotoRepository(context);
        PhotoVersionExportPlan plan=PhotoVersionExportPlan.create(repository.appPhotos(cancel),photos);
        boolean editing=active!=null&&active.draft!=null;
        boolean over=plan.photoCount>1&&plan.entries.size()>PhotoPresetBatch.MAX_BATCH;
        List<Choice> choices=new ArrayList<>();Set<String> names=new HashSet<>();
        for(PhotoVersionExportPlan.Entry entry:plan.entries){
            if(cancel.getAsBoolean())throw new java.io.InterruptedIOException("导出准备已取消。");
            if(over&&!entry.current)continue;
            String filename=editing?PhotoVersionExportPlan.uniqueFilename(photos.get(0).filename(),entry.label,names):entry.outputFilename;
            PhotoPresetBatch.Edit edit=PhotoPresetBatch.Edit.saved(PhotoPresetBatch.Source.local(entry.photo),PhotoExportSpec.full(),PhotoEditStore.hashFile(entry.photo.file())).withAccount(owner);
            if(entry.multiple||editing)edit=edit.withOutputFilename(filename);
            PhotoPresetRenderer.Dimensions size=PhotoPresetRenderer.dimensions(entry.photo.file(),null);
            Bitmap thumb=null;try{thumb=repository.thumbnail(entry.photo,128);}catch(IOException|RuntimeException|OutOfMemoryError ignored){}
            choices.add(new Choice(entry.id,entry.label,edit,new PhotoExportDialog.Item(filename,size.width,size.height,thumb,entry.label),!editing&&entry.current));
        }
        if(editing){
            PhotoPresetRenderer.Dimensions size=PhotoPresetRenderer.dimensions(active.source.localPhoto().file(),active.draft.profile());
            String name=PhotoVersionExportPlan.uniqueFilename(photos.get(0).filename(),"当前编辑",names);
            PhotoPresetBatch.Edit frozen=active.withAccount(owner).withOutputFilename(name);
            choices.add(0,new Choice("active:"+active.draft.identity(),"当前编辑",frozen,new PhotoExportDialog.Item(name,size.width,size.height,activeThumbnail,"当前编辑"),true));
        }
        if(choices.isEmpty())throw new IOException("没有可导出的照片版本。");
        return new Data(choices,plan.photoCount,plan.entries.size()+(editing?1:0),plan.hasVersions()||editing,over);
    }
    private final Activity activity;
    private final Data data;
    private final BooleanSupplier valid;
    private final Consumer<List<PhotoPresetBatch.Edit>> accepted;
    private final Consumer<PhotoQuickSaveDialog> onQuick;
    private final Consumer<PhotoExportDialog> onAdvanced;
    private final Runnable original,raw;
    private final Set<String> selected=new LinkedHashSet<>();
    private PhotoQuickSaveDialog quick;
    private PhotoExportDialog advanced;
    private boolean closed,allVersions;
    public PhotoVersionExport(Activity activity,Data data,BooleanSupplier valid,Consumer<List<PhotoPresetBatch.Edit>> accepted,Consumer<PhotoQuickSaveDialog> onQuick,Consumer<PhotoExportDialog> onAdvanced,Runnable original,Runnable raw){
        UiPalette palette=new UiPalette(activity);TEXT=palette.text;MUTED=palette.secondary;ACCENT=palette.primary;FIELD=palette.container;
        this.activity=activity;this.data=data;this.valid=valid;this.accepted=accepted;this.onQuick=onQuick;this.onAdvanced=onAdvanced;this.original=original;this.raw=raw;
        for(Choice choice:data.choices)if(choice.current)selected.add(choice.id);
    }
    public void show(){showQuick();}
    public void close(){closed=true;if(quick!=null)quick.dismiss();if(advanced!=null)advanced.dismiss();quick=null;advanced=null;}
    private boolean valid(){return !closed&&valid.getAsBoolean()&&!activity.isFinishing()&&!activity.isDestroyed();}
    private List<Choice> chosen(){List<Choice> result=new ArrayList<>();for(Choice choice:data.choices)if(selected.contains(choice.id))result.add(choice);return result;}
    private List<PhotoPresetBatch.Edit> edits(){List<PhotoPresetBatch.Edit> result=new ArrayList<>();for(Choice choice:chosen())result.add(choice.edit);return Collections.unmodifiableList(result);}
    private List<PhotoExportDialog.Item> items(){List<PhotoExportDialog.Item> result=new ArrayList<>();for(Choice choice:chosen())result.add(choice.item);return result;}
    private String summary(){
        if(selected.isEmpty())return "请选择导出版本";
        if(data.photoCount>1)return data.photoCount+" 张照片 · "+(allVersions?"全部 "+selected.size()+" 个版本":"各自当前版本");
        if(selected.size()==1)return chosen().get(0).label;
        return "已选 "+selected.size()+" 个版本";
    }
    private void accept(PhotoExportSpec spec,PhotoSaveTarget target,boolean newCopy){
        if(!valid()||selected.isEmpty()||selected.size()>PhotoPresetBatch.MAX_BATCH)return;
        List<PhotoPresetBatch.Edit> frozen=new ArrayList<>();
        // A fresh export always creates gallery copies; a retry keeps its existing frozen receipt.
        for(PhotoPresetBatch.Edit edit:PhotoExportAvailability.withSpec(edits(),spec))frozen.add(edit.withDestination(PhotoSaveTarget.PHONE_ALBUM,true));
        accepted.accept(Collections.unmodifiableList(frozen));
    }
    private void showQuick(){
        if(!valid())return;
        quick=PhotoQuickSaveDialog.show(activity,items(),this::accept,this::showAdvanced);onQuick.accept(quick);
        if(quick==null)return;
        if(data.hasVersions)quick.setVersionContent(versionChoices());
        refreshSummary();
    }
    private void refreshSummary(){if(quick!=null&&quick.isShowing())quick.setVersionItems(items(),summary());}
    private View versionChoices(){
        LinearLayout list=new LinearLayout(quick.getContext());list.setOrientation(LinearLayout.VERTICAL);list.setTag("export-version-choices");
        if(data.photoCount>1){
            CheckBox all=new PhotoChoiceCheck(quick.getContext());all.setText("导出全部版本");all.setTag("export-all-versions");all.setTextSize(13);all.setTextColor(TEXT);all.setMinHeight(dp(48));all.setPadding(0,0,0,0);all.setChecked(allVersions);all.setEnabled(!data.allOverLimit);list.addView(all,new LinearLayout.LayoutParams(-1,dp(48)));
            if(data.allOverLimit){TextView limit=label("全部共 "+data.allCount+" 个版本，每次最多 100 个",12,MUTED);limit.setMaxLines(2);list.addView(limit);}
            all.setOnCheckedChangeListener((v,checked)->{allVersions=checked;selected.clear();for(Choice choice:data.choices)if(checked||choice.current)selected.add(choice.id);refreshSummary();});
        }else{
            TextView title=label("导出版本 · 可多选",12,MUTED);title.setPadding(0,dp(4),0,dp(4));list.addView(title);
            for(Choice choice:data.choices){
                LinearLayout row=new LinearLayout(quick.getContext());row.setTag("export-version-row:"+choice.id);row.setGravity(Gravity.CENTER_VERTICAL);row.setMinimumHeight(dp(56));
                CheckBox check=new PhotoChoiceCheck(quick.getContext());check.setTag("export-version-check:"+choice.id);check.setChecked(selected.contains(choice.id));check.setContentDescription("导出版本 "+choice.label+(choice.current?"，当前版本":""));row.addView(check,new LinearLayout.LayoutParams(dp(48),dp(48)));
                ImageView image=new ImageView(quick.getContext());image.setScaleType(ImageView.ScaleType.CENTER_CROP);if(choice.item.thumbnail!=null)image.setImageBitmap(choice.item.thumbnail);else image.setImageDrawable(new AppIcon(AppIcon.Kind.PRESETS,MUTED,density()));image.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);GradientDrawable face=new GradientDrawable();face.setColor(FIELD);face.setCornerRadius(dp(6));image.setBackground(face);image.setClipToOutline(true);row.addView(image,new LinearLayout.LayoutParams(dp(40),dp(40)));
                TextView name=label(choice.label,13,TEXT);name.setTag("export-version-name");name.setSingleLine(true);name.setEllipsize(TextUtils.TruncateAt.END);name.setTooltipText(choice.label);name.setPadding(dp(10),0,dp(4),0);row.addView(name,new LinearLayout.LayoutParams(0,-2,1));
                if(choice.current){TextView current=label("当前",11,MUTED);current.setSingleLine(true);row.addView(current,new LinearLayout.LayoutParams(-2,-2));}
                check.setOnCheckedChangeListener((v,checked)->{if(checked)selected.add(choice.id);else selected.remove(choice.id);refreshSummary();});row.setOnClickListener(v->check.setChecked(!check.isChecked()));list.addView(row,new LinearLayout.LayoutParams(-1,-2));
            }
        }
        return list;
    }
    private void showAdvanced(){
        if(!valid()||selected.isEmpty()||selected.size()>PhotoPresetBatch.MAX_BATCH){showQuick();return;}
        advanced=PhotoExportDialog.show(activity,items(),this::accept,original,raw);onAdvanced.accept(advanced);
        if(advanced==null)return;
        if(data.hasVersions)advanced.setVersionAction(this::showQuick);
        List<PhotoExportPreview.Request> previews=new ArrayList<>();
        for(Choice choice:chosen()){PhotoPresetBatch.Edit edit=choice.edit;previews.add(new PhotoExportPreview.Request(activity,edit.source.localPhoto().file(),edit.draft==null?edit.expectedSourceSha:edit.draft.sourceSha,edit.draft==null?"saved:"+edit.expectedSourceSha:edit.draft.identity(),choice.profile,this::valid));}
        advanced.setPreviewRequests(previews);
    }
    private TextView label(String value,int size,int color){TextView text=new TextView(quick.getContext());text.setText(value);text.setTextSize(size);text.setTextColor(color);text.setGravity(Gravity.CENTER_VERTICAL);text.setIncludeFontPadding(false);return text;}
    private float density(){return activity.getResources().getDisplayMetrics().density;}
    private int dp(float value){return Math.round(value*density());}
}
