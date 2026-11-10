package cc.huevia.ui;

import android.Manifest;
import android.app.Activity;
import android.app.AlertDialog;
import android.content.ActivityNotFoundException;
import android.content.ClipData;
import android.content.Intent;
import android.content.res.ColorStateList;
import android.graphics.Bitmap;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.RippleDrawable;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.Parcelable;
import android.provider.Settings;
import android.text.TextUtils;
import android.util.LruCache;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.AbsListView;
import android.widget.BaseAdapter;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ListView;
import android.widget.ProgressBar;
import android.widget.PopupMenu;
import android.widget.ScrollView;
import android.widget.TextView;
import cc.huevia.album.DownloadedPhoto;
import cc.huevia.album.LocalPhotoRepository;
import cc.huevia.album.PhotoLibraryCatalog;
import cc.huevia.album.PhotoPresetBatch;
import java.io.IOException;
import java.io.File;
import java.text.DateFormat;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Date;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;

/**
 * THESIS: Choose local photographs, refine them, and publish only the chosen versions.
 * OWN-WORLD: Approved warm-white/graphite palette, fixed-size photo marks and native sp labels.
 * STORY: Browse phone or durable app photos, select, edit, then explicitly choose a destination.
 * FIRST VIEWPORT: Two sources, visible access/scope status, date groups and a lazy photo grid.
 * FORM: Approved two-source local library inside the incumbent Android application; code-led extension.
 * FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review,
 * the verdict, DESIGN.md, and every shipping raster carrying its provenance.
 */
public final class LocalAlbumPanel implements AutoCloseable {
    public interface Host {
        void changed();
        void open(DownloadedPhoto photo);
        void batch(List<DownloadedPhoto> photos);
        void export(List<DownloadedPhoto> photos);
        void feedback(String title, String message);
        default void addFilters() { }
    }
    public static final int REQUEST_PHONE_ACCESS = 7410, REQUEST_PICK_PHOTOS = 7411;
    private static final int PAGE_SIZE = 120;
    private final Activity activity;
    private final Host host;
    private final PhotoPresetBatch photoPresets;
    private final LocalPhotoRepository repository;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private final ThreadPoolExecutor images = new ThreadPoolExecutor(2, 2, 0, TimeUnit.MILLISECONDS, new ArrayBlockingQueue<>(24));
    private final LruCache<String, Bitmap> thumbnails = new LruCache<String, Bitmap>(12 * 1024 * 1024) {
        @Override protected int sizeOf(String key, Bitmap bitmap) { return bitmap.getAllocationByteCount(); }
    };
    private final Set<String> pendingThumbs = new HashSet<>(), failedThumbs = new HashSet<>();
    private final List<Item> phonePhotos = new ArrayList<>(), appPhotos = new ArrayList<>();
    private final Set<String> selected = new LinkedHashSet<>();
    private final Parcelable[] positions = new Parcelable[2];
    private final String[] positionKeys = {"", ""};
    private final int[] positionRows = new int[2], positionTops = new int[2];
    private boolean positionRestorePending;
    private boolean positionRestoreApplied;
    private int positionRestoreRequest;
    private final List<Row> rows = new ArrayList<>();
    private final Runnable presetChanged = () -> main.post(this::refreshApp);
    private final Runnable thumbnailChanged = this::thumbnailsChanged;
    private UiPalette palette;
    private LinearLayout root, selectionBar, summaryRow;
    private GlassBar selectionDock;
    private Boolean narrowDock;
    private Button phoneTab, appTab, permissionButton, batchButton, exportButton, selectButton, pickerButton, cancelButton;
    private ImageView moreButton;
    private TextView scope, status, selectionCount;
    private ProgressBar progress;
    private ListView list;
    private FrameLayout body;
    private LinearLayout empty;
    private View emptyContainer;
    private TextView emptyTitle, emptyText;
    private PhotoAdapter adapter;
    private boolean phone, selecting, closed, active, loadingPhone, loadingApp, importing, phoneMore, phoneLoaded, appLoaded, compactLayout, dockUsingList;
    private int phoneOffset, phoneRequest, appRequest, importRequest, imageEpoch, gridColumns = 3;
    private String phoneError = "", appError = "", workStatus = "";
    private String pendingDateSelection;

    public LocalAlbumPanel(Activity activity, PhotoPresetBatch photoPresets, Host host) {
        this.activity = activity; this.photoPresets = photoPresets; this.host = host; repository = new LocalPhotoRepository(activity);
        if (photoPresets != null) photoPresets.addObserver(presetChanged);
    }
    public String title() { return "相册"; }
    public boolean hasSelectionDock() { return selecting || importing; }
    public View createHeaderAction() {
        UiPalette colors = UiPalette.home(activity);
        moreButton = new ImageView(activity);
        moreButton.setImageDrawable(new AppIcon(AppIcon.Kind.MORE_HORIZONTAL, colors.secondary, density()));
        moreButton.setPadding(dp(14), dp(14), dp(14), dp(14));
        moreButton.setBackground(new android.graphics.drawable.InsetDrawable(new RippleDrawable(ColorStateList.valueOf(0x15000000), shape(colors.card, dp(18)), null), dp(6), dp(6), dp(6), dp(6)));
        moreButton.setPadding(dp(14), dp(14), dp(14), dp(14)); moreButton.setContentDescription("相册更多操作"); moreButton.setTag("local-album-more");
        moreButton.setFocusable(true); moreButton.setEnabled(!importing);
        moreButton.setOnClickListener(view -> showMoreActions());
        moreButton.setLayoutParams(new LinearLayout.LayoutParams(dp(48), dp(48)));
        LinearLayout actions = new LinearLayout(activity);
        ImageView search = new ImageView(activity); search.setImageDrawable(new AppIcon(AppIcon.Kind.SEARCH, colors.text, density()));
        search.setPadding(dp(14), dp(14), dp(14), dp(14)); search.setBackground(new android.graphics.drawable.InsetDrawable(shape(colors.card, dp(18)), dp(6), dp(6), dp(6), dp(6)));
        search.setPadding(dp(14), dp(14), dp(14), dp(14)); search.setContentDescription("搜索照片"); search.setFocusable(true); search.setOnClickListener(v -> searchPhotos()); search.setEnabled(!hasSelectionDock());
        actions.addView(search, new LinearLayout.LayoutParams(dp(48), dp(48))); actions.addView(moreButton); return actions;
    }
    public void saveState(Bundle state) {
        savePosition(); state.putBoolean("localAlbumPhone", phone);
        state.putParcelable("localAlbumAppPosition", positions[0]); state.putParcelable("localAlbumPhonePosition", positions[1]);
        for (int i = 0; i < 2; i++) { state.putString("localAlbumAnchor" + i, positionKeys[i]); state.putInt("localAlbumRow" + i, positionRows[i]); state.putInt("localAlbumTop" + i, positionTops[i]); }
    }
    public void restoreState(Bundle state) {
        if (state == null) return; phone = state.getBoolean("localAlbumPhone", false);
        positions[0] = state.getParcelable("localAlbumAppPosition"); positions[1] = state.getParcelable("localAlbumPhonePosition");
        for (int i = 0; i < 2; i++) { positionKeys[i] = state.getString("localAlbumAnchor" + i, ""); positionRows[i] = state.getInt("localAlbumRow" + i); positionTops[i] = state.getInt("localAlbumTop" + i); }
    }
    public View createView() {
        boolean compact = compactHeight();
        if (root != null) {
            if (palette.dark == UiPalette.home(activity).dark && compactLayout == compact) { savePosition(); restorePosition(); return root; }
            savePosition(); root = null;
        }
        compactLayout = compact;
        palette = UiPalette.home(activity);
        root = new SubcategorySwipeLayout(activity,()->phone?1:0,2,index->{(index==1?phoneTab:appTab).performClick();},()->!closed&&appTab!=null&&phoneTab!=null&&appTab.isEnabled()&&phoneTab.isEnabled()); root.setBackgroundColor(palette.surface); root.setTag("local-album-root");
        LinearLayout tabs = new LinearLayout(activity); tabs.setGravity(Gravity.CENTER_VERTICAL); tabs.setPadding(dp(compactLayout ? 12 : 20), 0, dp(compactLayout ? 12 : 20), dp(4));
        tabs.setTag("local-album-sources");
        appTab = button("应用相册", () -> switchTab(false)); phoneTab = button("手机相册", () -> switchTab(true));
        appTab.setTag("local-album-source-app"); phoneTab.setTag("local-album-source-phone");
        appTab.setTextSize(13); phoneTab.setTextSize(13); appTab.setSingleLine(true); phoneTab.setSingleLine(true);
        LinearLayout track=new LinearLayout(activity);track.setGravity(Gravity.CENTER_VERTICAL);track.setPadding(dp(4),0,dp(4),0);track.setBackground(shape(palette.container,dp(24)));track.setTag("local-album-source-track");
        track.addView(appTab, new LinearLayout.LayoutParams(0, dp(48), 1));
        track.addView(phoneTab, new LinearLayout.LayoutParams(0, dp(48), 1));
        tabs.addView(track,new LinearLayout.LayoutParams(-1,dp(48)));
        root.addView(tabs);
        ((SubcategorySwipeLayout)root).setMotionAnchor(tabs);
        scope = text("", 12, palette.secondary); scope.setMaxLines(1); scope.setEllipsize(TextUtils.TruncateAt.END); scope.setTag("local-album-count");
        status = text("", 12, palette.secondary); status.setMaxLines(1); status.setEllipsize(TextUtils.TruncateAt.END); status.setMaxWidth(dp(116));
        status.setGravity(Gravity.CENTER_VERTICAL); status.setPadding(dp(8), 0, dp(8), 0);
        progress = new ProgressBar(activity);
        summaryRow = new LinearLayout(activity); summaryRow.setGravity(Gravity.CENTER_VERTICAL); summaryRow.setPadding(dp(compactLayout ? 12 : 24), 0, dp(compactLayout ? 12 : 20), dp(4)); summaryRow.setTag("local-album-summary");
        summaryRow.addView(scope, new LinearLayout.LayoutParams(0, -2, 1)); summaryRow.addView(progress, new LinearLayout.LayoutParams(dp(20), dp(20))); summaryRow.addView(status, new LinearLayout.LayoutParams(-2, -2));
        selectButton = smallAction("选择", () -> { if (selecting) { if (current().size() > LocalPhotoRepository.MAX_BATCH) { host.feedback("最多选择 100 张", "请按日期或逐张选择照片。"); return; } for (Item item : current()) selected.add(item.key); } else { selecting = true; selected.clear(); } updateSelection(); }); selectButton.setTag("local-album-select"); selectButton.setContentDescription("选择照片进行批量操作");
        LinearLayout.LayoutParams selectParams = new LinearLayout.LayoutParams(-2, dp(48)); selectParams.leftMargin = dp(8); summaryRow.addView(selectButton, selectParams);
        root.addView(summaryRow, new LinearLayout.LayoutParams(-1, dp(52)));
        body = new FrameLayout(activity); root.addView(body, new LinearLayout.LayoutParams(-1, 0, 1));
        positionRestorePending = false; positionRestoreApplied = false; positionRestoreRequest++;
        list = new ListView(activity) {
            @Override protected void onLayout(boolean changed, int left, int top, int right, int bottom) { super.onLayout(changed, left, top, right, bottom); if (!positionRestorePending || positionRestoreApplied) { positionRestorePending = false; positionRestoreApplied = false; savePosition(); } }
            @Override protected void onDetachedFromWindow() { savePosition(); super.onDetachedFromWindow(); }
        }; list.setDivider(null); list.setClipToPadding(false); list.setPadding(dp(compactLayout ? 8 : 15), 0, dp(compactLayout ? 8 : 15), dp(navReserve() + 8));
        list.setSelector(android.R.color.transparent); list.setCacheColorHint(palette.surface); adapter = new PhotoAdapter(); list.setAdapter(adapter); body.addView(list, new FrameLayout.LayoutParams(-1, -1));
        list.setOnScrollListener(new AbsListView.OnScrollListener() {
            public void onScrollStateChanged(AbsListView view, int state) { if (state == SCROLL_STATE_IDLE) adapter.notifyDataSetChanged(); }
            public void onScroll(AbsListView view, int first, int count, int total) { savePosition(); if (phone && count > 0 && total > 0 && first + count >= total - 2 && phoneMore && !loadingPhone && phoneError.isEmpty()) loadPhone(false); }
        });
        empty = new LinearLayout(activity); empty.setOrientation(LinearLayout.VERTICAL); empty.setGravity(Gravity.CENTER); empty.setPadding(dp(compactLayout ? 16 : 32), dp(compactLayout ? 8 : 24), dp(compactLayout ? 16 : 32), dp(compactLayout ? 8 : 24));
        ImageView emptyIcon = new ImageView(activity); emptyIcon.setImageDrawable(new AppIcon(AppIcon.Kind.ALBUM, palette.secondary, density())); empty.addView(emptyIcon, new LinearLayout.LayoutParams(dp(40), dp(40)));
        if (compactLayout) emptyIcon.setVisibility(View.GONE);
        emptyTitle = text("", 20, palette.text); emptyTitle.setGravity(Gravity.CENTER); emptyTitle.setTypeface(null, Typeface.BOLD); emptyTitle.setPadding(0, dp(compactLayout ? 0 : 20), 0, dp(8)); empty.addView(emptyTitle);
        emptyText = text("", 15, palette.secondary); emptyText.setGravity(Gravity.CENTER); emptyText.setLineSpacing(dp(3), 1); empty.addView(emptyText);
        permissionButton = button("允许访问照片", () -> { if (phone) requestAccess(); else switchTab(true); }); permissionButton.setTag("local-album-permission"); HueTheme.styleAction(permissionButton,palette,true);
        LinearLayout.LayoutParams permissionParams = new LinearLayout.LayoutParams(-2, -2); permissionParams.topMargin = dp(compactLayout ? 8 : 16); empty.addView(permissionButton, permissionParams);
        pickerButton = dockAction("选择指定照片", false, this::pickPhotos); pickerButton.setTag("local-album-picker"); pickerButton.setContentDescription("通过系统选择器选择指定照片");
        pickerButton.setTextSize(12); pickerButton.setPaintFlags(pickerButton.getPaintFlags() | android.graphics.Paint.UNDERLINE_TEXT_FLAG);
        empty.addView(pickerButton, new LinearLayout.LayoutParams(-2, dp(48)));
        ScrollView guidance = new ScrollView(activity); guidance.setFillViewport(true); guidance.addView(empty, new ScrollView.LayoutParams(-1, -2)); emptyContainer = guidance;
        FrameLayout.LayoutParams guidanceParams = new FrameLayout.LayoutParams(-1, -1); guidanceParams.bottomMargin = dp(navReserve()); body.addView(guidance, guidanceParams);
        selectionDock = new GlassBar(activity, palette); selectionDock.setTag("local-album-selection-dock"); selectionDock.setBackdrop(list); dockUsingList = true; narrowDock = null;
        selectionBar = new LinearLayout(activity); selectionBar.setOrientation(LinearLayout.HORIZONTAL); selectionBar.setGravity(Gravity.CENTER_VERTICAL); selectionBar.setPadding(dp(6), dp(4), dp(6), dp(4)); selectionBar.setTag("local-album-selection-actions");
        cancelButton = dockAction("取消", false, this::cancelSelection); cancelButton.setTag("local-album-cancel-selection"); cancelButton.setContentDescription("取消选择");
        selectionBar.addView(cancelButton, new LinearLayout.LayoutParams(-2, dp(48)));
        selectionCount = text("", 12, palette.secondary); selectionCount.setGravity(Gravity.CENTER); selectionCount.setSingleLine(true); selectionCount.setEllipsize(TextUtils.TruncateAt.END); selectionCount.setIncludeFontPadding(false); selectionCount.setTag("local-album-selection-count"); selectionCount.setAccessibilityLiveRegion(View.ACCESSIBILITY_LIVE_REGION_POLITE);
        selectionBar.addView(selectionCount, new LinearLayout.LayoutParams(0, -2, 1));
        exportButton = dockAction("导出", false, this::exportSelected); exportButton.setTag("local-album-batch-export"); exportButton.setContentDescription("按每张照片当前修图设置保存到手机相册");
        LinearLayout.LayoutParams exportParams = new LinearLayout.LayoutParams(-2, dp(48)); exportParams.leftMargin = dp(4); selectionBar.addView(exportButton, exportParams);
        batchButton = dockAction("批量编辑", true, () -> prepareSelected(false)); batchButton.setTag("local-album-batch-edit"); batchButton.setContentDescription("批量编辑所选照片");
        LinearLayout.LayoutParams editParams = new LinearLayout.LayoutParams(-2, dp(48)); editParams.leftMargin = dp(4); selectionBar.addView(batchButton, editParams);
        selectionDock.addView(selectionBar, new FrameLayout.LayoutParams(-1, -1));
        FrameLayout.LayoutParams dockParams = new FrameLayout.LayoutParams(-1, dp(56), Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL); dockParams.leftMargin = dockParams.rightMargin = dp(16); dockParams.bottomMargin = dp(14); body.addView(selectionDock, dockParams);
        body.addOnLayoutChangeListener((view, left, top, right, bottom, oldLeft, oldTop, oldRight, oldBottom) -> {
            layoutSelectionDock();
            if (compactLayout && resolvedColumns() != gridColumns) { savePosition(); rebuildRows(); restorePosition(); }
        });
        rebuildRows(); restorePosition(); updateState(); refreshApp(); return root;
    }
    private int navReserve() {
        if (hasSelectionDock()) return 80;
        boolean floating = activity.getResources().getConfiguration().screenWidthDp < 600;
        if (!floating) return 0;
        return 104 + Math.round(Math.max(0f, activity.getResources().getConfiguration().fontScale - 1.2f) * 24f);
    }
    private boolean compactHeight() {
        android.content.res.Configuration config = activity.getResources().getConfiguration();
        return config.screenHeightDp < 480 && config.screenWidthDp > config.screenHeightDp;
    }
    public void resume() {
        if (closed) return; active = true;
        // Permission/selection can change in Settings or after backgrounding; never trust an old snapshot.
        invalidatePhone(); refreshApp(); if (phone && repository.access() != LocalPhotoRepository.Access.NONE) loadPhone(true);
        updateState();
    }
    public void pause() { active = false; savePosition(); }
    public boolean canGoBack() { return selecting || importing; }
    public boolean goBack() {
        if (hasSelectionDock()) { cancelSelection(); return true; }
        return false;
    }
    private void cancelSelection() {
        pendingDateSelection = null;
        if (importing) { importRequest++; importing = false; workStatus = ""; }
        selecting = false; selected.clear(); updateSelection();
    }
    public void refresh() {
        if (closed || importing) return;
        if (phone) { invalidatePhone(); if (repository.access() != LocalPhotoRepository.Access.NONE) loadPhone(true); else updateState(); }
        else refreshApp();
    }
    private void refreshApp() {
        if (closed || loadingApp) return; loadingApp = true; appError = ""; int request = ++appRequest; updateState();
        worker.execute(() -> {
            List<PhotoLibraryCatalog.PhotoGroup> groups = null; String error = "";
            try { groups = repository.appPhotos(() -> closed || request != appRequest); }
            catch (IOException | RuntimeException failure) { error = message(failure); }
            List<PhotoLibraryCatalog.PhotoGroup> result = groups; String failure = error;
            main.post(() -> {
                if (closed || request != appRequest) return; loadingApp = false; appLoaded = true; appError = failure;
                if (result != null) { appPhotos.clear(); for (PhotoLibraryCatalog.PhotoGroup group : result) appPhotos.add(Item.local(group)); }
                if (!phone) { preserveSelection(); savePosition(); rebuildRows(); restorePosition(); } updateState();
            });
        });
    }
    private void invalidatePhone() {
        pendingDateSelection = null;
        phoneRequest++; loadingPhone = false; phonePhotos.clear(); phoneOffset = 0; phoneMore = false; phoneLoaded = false; phoneError = "";
        imageEpoch++; thumbnails.evictAll(); failedThumbs.clear();
        if (phone) { selected.clear(); rebuildRows(); }
    }
    private void loadPhone(boolean replace) {
        if (closed || loadingPhone || repository.access() == LocalPhotoRepository.Access.NONE) return;
        loadingPhone = true; phoneError = ""; int request = ++phoneRequest; int offset = replace ? 0 : phoneOffset; updateState();
        worker.execute(() -> {
            LocalPhotoRepository.Page page = null; String error = "";
            try { page = repository.phonePage(offset, PAGE_SIZE); } catch (IOException | RuntimeException failure) { error = message(failure); }
            LocalPhotoRepository.Page result = page; String failure = error;
            main.post(() -> {
                if (closed || request != phoneRequest) return; loadingPhone = false; phoneLoaded = true; phoneError = failure;
                if (result != null) {
                    if (replace) phonePhotos.clear(); Set<String> known = new HashSet<>(); for (Item item : phonePhotos) known.add(item.key);
                    for (LocalPhotoRepository.PhonePhoto photo : result.photos) if (known.add(photo.key)) phonePhotos.add(Item.phone(photo));
                    phoneOffset = result.nextOffset; phoneMore = result.hasMore;
                } else if (repository.access() == LocalPhotoRepository.Access.NONE) phonePhotos.clear();
                if (phone) { preserveSelection(); rebuildRows(); if (replace) restorePosition(); } updateState();
                if (pendingDateSelection != null) {
                    String date = pendingDateSelection; pendingDateSelection = null;
                    if (phone && failure.isEmpty()) for (Row row : rows) if (date.equals(row.header)) { toggleDate(row); break; }
                }
            });
        });
    }
    private void switchTab(boolean value) {
        if (phone == value || importing || selecting) return;
        SubcategorySwipeLayout.changeSource(root,phone?1:0,value?1:0,()->{
            pendingDateSelection = null; savePosition(); phone = value; selected.clear();
            rebuildRows(); restorePosition(); updateState(); host.changed();
            if (phone && !phoneLoaded && repository.access() != LocalPhotoRepository.Access.NONE) loadPhone(true);
            if (!phone && !appLoaded) refreshApp();
        },()->root);
    }
    private void requestAccess() {
        if (Build.VERSION.SDK_INT >= 34) activity.requestPermissions(new String[]{Manifest.permission.READ_MEDIA_IMAGES, Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED}, REQUEST_PHONE_ACCESS);
        else if (Build.VERSION.SDK_INT >= 33) activity.requestPermissions(new String[]{Manifest.permission.READ_MEDIA_IMAGES}, REQUEST_PHONE_ACCESS);
        else activity.requestPermissions(new String[]{Manifest.permission.READ_EXTERNAL_STORAGE}, REQUEST_PHONE_ACCESS);
    }
    private void showMoreActions() {
        PopupMenu menu = new PopupMenu(activity, moreButton);
        menu.getMenu().add(0, 1, 0, "刷新").setEnabled(!importing);
        menu.getMenu().add(0, 5, 2, "RAW 显影").setEnabled(!importing);
        if (phone && repository.access() == LocalPhotoRepository.Access.PARTIAL) menu.getMenu().add(0, 3, 2, "重新选择可访问照片").setEnabled(!importing);
        if (phone) menu.getMenu().add(0, 4, 3, "权限设置");
        menu.setOnMenuItemClickListener(item -> {
            if (item.getItemId() == 1) refresh();
            else if (item.getItemId() == 3) requestAccess();
            else if (item.getItemId() == 5) activity.startActivityForResult(cc.huevia.RawDevelopActivity.intent(activity,null,PhotoFilterEditor.accountOwner(activity)),7319);
            else if (item.getItemId() == 4) {
                try { activity.startActivity(new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:" + activity.getPackageName()))); }
                catch (ActivityNotFoundException unavailable) { host.feedback("无法打开设置", "请在系统设置中找到本应用，调整照片访问权限。"); }
            }
            return true;
        }); menu.show();
    }
    private void pickPhotos() {
        if (importing) return;
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("image/*");
        intent.putExtra(Intent.EXTRA_MIME_TYPES, new String[]{"image/jpeg", "image/png"}); intent.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true);
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION);
        try { activity.startActivityForResult(intent, REQUEST_PICK_PHOTOS); }
        catch (ActivityNotFoundException unavailable) { host.feedback("无法选择照片", "系统未提供照片文件选择器。请授权浏览手机照片后重试。"); }
    }
    public boolean onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        if (requestCode != REQUEST_PHONE_ACCESS) return false;
        invalidatePhone(); if (repository.access() != LocalPhotoRepository.Access.NONE) loadPhone(true); else { phoneError = "未获得手机照片访问权限。仍可使用「选择照片」，应用相册照片可继续编辑。"; updateState(); } return true;
    }
    public boolean onActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode != REQUEST_PICK_PHOTOS) return false;
        if (resultCode != Activity.RESULT_OK || data == null) return true;
        LinkedHashSet<Uri> chosen = new LinkedHashSet<>(); if (data.getData() != null) chosen.add(data.getData());
        ClipData clips = data.getClipData(); if (clips != null) for (int i = 0; i < clips.getItemCount(); i++) chosen.add(clips.getItemAt(i).getUri());
        chosen.remove(null);
        if (chosen.size() > LocalPhotoRepository.MAX_BATCH) { host.feedback("最多选择 100 张", "本次未读取照片。请重新选择不超过 100 张 JPEG 或 PNG 照片。"); return true; }
        if (chosen.isEmpty()) return true;
        int offered = data.getFlags();
        if ((offered & Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION) != 0) for (Uri uri : chosen) {
            try { activity.getContentResolver().takePersistableUriPermission(uri, offered & Intent.FLAG_GRANT_READ_URI_PERMISSION); }
            catch (SecurityException | IllegalArgumentException unavailable) { /* Durable app copies, rather than this grant, are the editing boundary. */ }
        }
        List<Uri> uris = new ArrayList<>(chosen); prepareUris(uris); return true;
    }
    public void acceptRawDevelopment(Intent data){
        if(data==null)return;
        String path=data.getStringExtra(cc.huevia.RawDevelopActivity.EXTRA_DEVELOPED_JPEG_PATH);
        if(path==null)return;final File source=new File(path);
        final String jpegSha=data.getStringExtra(cc.huevia.RawDevelopActivity.EXTRA_JPEG_SHA),rawSha=data.getStringExtra(cc.huevia.RawDevelopActivity.EXTRA_RAW_SHA),identity=data.getStringExtra(cc.huevia.RawDevelopActivity.EXTRA_WORKING_IDENTITY);
        final String scope=PhotoFilterEditor.accountOwner(activity);
        if(closed||importing||!scope.equals(data.getStringExtra(cc.huevia.RawDevelopActivity.EXTRA_OWNER))){
            try{worker.execute(()->repository.discardDevelopedHandoff(source,jpegSha));}catch(RejectedExecutionException ignored){}
            if(!closed)host.feedback("未导入显影副本",importing?"照片正在导入，请稍后重新生成副本。":"账号已变化，请重新显影。");return;
        }
        beginImport();final int request=importRequest;
        worker.execute(()->{try{
            DownloadedPhoto photo=repository.importDevelopedJpeg(source,jpegSha,rawSha,identity,()->cancelImport(request)||!scope.equals(PhotoFilterEditor.accountOwner(activity)));
            main.post(()->{if(cancelImport(request))return;finishImport();if(scope.equals(PhotoFilterEditor.accountOwner(activity))){refreshApp();host.open(photo);}});
        }catch(Exception failure){main.post(()->{if(!cancelImport(request)){finishImport();if(scope.equals(PhotoFilterEditor.accountOwner(activity)))host.feedback("未导入显影副本",message(failure));}});}finally{repository.discardDevelopedHandoff(source,jpegSha);}});
    }
    private void prepareUris(List<Uri> uris) {
        if (importing) return; beginImport(); int request = importRequest;
        worker.execute(() -> {
            List<Item> items = new ArrayList<>(); String error = "";
            try { for (Uri uri : uris) { if (cancelImport(request)) return; items.add(Item.phone(repository.describe(uri))); } }
            catch (IOException | RuntimeException failure) { error = message(failure); }
            List<Item> result = items; String failure = error;
            main.post(() -> {
                if (cancelImport(request)) return;
                if (!failure.isEmpty()) { finishImport(); host.feedback("未打开照片", failure); return; }
                boolean png = result.stream().anyMatch(item -> item.phone.png());
                if (png) { finishImport(); confirmPng(result, result.size() == 1); } else runImport(result, result.size() == 1, request);
            });
        });
    }
    private void clicked(Item item) {
        if (importing) return;
        if (selecting) { toggle(item); return; }
        savePosition(); if (item.photo != null) host.open(item.photo); else confirmPng(Collections.singletonList(item), true);
    }
    private void toggle(Item item) {
        if (!selected.remove(item.key)) {
            if (selected.size() >= LocalPhotoRepository.MAX_BATCH) { host.feedback("最多选择 100 张", "请先处理当前所选照片，再选择其他照片。"); return; }
            selected.add(item.key);
        }
        selecting = true; updateSelection();
    }
    private List<String> dateKeys(Row row) {
        List<String> keys = new ArrayList<>();
        for (Item item : row.items) if (current().contains(item)) keys.add(item.key);
        return keys;
    }
    private void toggleDate(Row row) {
        if (closed || importing) return;
        List<String> keys = dateKeys(row); if (keys.isEmpty()) return;
        // The last loaded date may continue on the next MediaStore page. Read metadata first,
        // so a small tail never masquerades as the complete date group. No photo is imported.
        boolean all = cc.huevia.album.PhotoGroupSelection.state(keys, selected) == cc.huevia.album.PhotoGroupSelection.State.ALL;
        if (!all && phone && phoneMore && !current().isEmpty() && row.items.contains(current().get(current().size()-1)) && keys.size() <= LocalPhotoRepository.MAX_BATCH) {
            pendingDateSelection = row.header; loadPhone(false); return;
        }
        if (!cc.huevia.album.PhotoGroupSelection.toggle(keys, selected, LocalPhotoRepository.MAX_BATCH)) {
            host.feedback("整组超过选择上限", "每次最多选择 100 张，可长按照片后逐张选择。"); return;
        }
        savePosition(); selecting = true; updateSelection(); restorePosition();
    }
    private void prepareSelected(boolean single) {
        if (importing || selected.isEmpty()) return; List<Item> items = new ArrayList<>();
        for (Item item : current()) if (selected.contains(item.key)) items.add(item);
        confirmPng(items, single);
    }
    private void exportSelected() {
        if (closed || importing || phone || selected.isEmpty()) return;
        List<DownloadedPhoto> photos = new ArrayList<>();
        for (Item item : appPhotos) if (selected.contains(item.key) && item.photo != null) photos.add(item.photo);
        if (photos.size() != selected.size()) { host.feedback("照片暂不可用", "部分所选照片已变化，请刷新后重新选择。"); return; }
        // Keep selection on dismissal; export freezes exactly each card's current saved version.
        host.export(Collections.unmodifiableList(photos));
    }
    private void confirmPng(List<Item> items, boolean single) {
        if (items.stream().noneMatch(item -> item.phone != null && item.phone.png())) { beginImport(); runImport(items, single, importRequest); return; }
        new AppDialog.Builder(activity).setTitle("以白底编辑 PNG")
                .setMessage("PNG 源文件会完整保留在应用相册。编辑使用白底 JPEG 工作副本，透明区域会变白。手机原图保持原样。")
                .setNegativeButton("取消", null).setPositiveButton("继续编辑", (dialog, which) -> { beginImport(); runImport(items, single, importRequest); }).show();
    }
    private void beginImport() { importing = true; importRequest++; workStatus = "正在准备照片…"; updateState(); host.changed(); }
    private boolean cancelImport(int request) { return closed || request != importRequest || Thread.currentThread().isInterrupted(); }
    private void runImport(List<Item> items, boolean single, int request) {
        worker.execute(() -> {
            List<DownloadedPhoto> ready = new ArrayList<>(); String error = ""; long total = 0;
            try {
                for (int i = 0; i < items.size(); i++) {
                    if (cancelImport(request)) return; Item item = items.get(i); final int index = i + 1;
                    main.post(() -> { if (!cancelImport(request)) { workStatus = "正在准备 " + index + " / " + items.size() + " 张"; updateState(); } });
                    if (item.phone != null && item.phone.bytes > 0 && total + item.phone.bytes > 1024L * 1024 * 1024) throw new IOException("一次处理的手机照片总量不能超过 1 GB。已完成的工作副本保留在应用相册。");
                    DownloadedPhoto photo = item.photo == null ? repository.importPhoto(item.phone, () -> cancelImport(request)) : item.photo;
                    if (item.phone != null) {
                        total += Math.max(photo.byteSize(), Math.max(0, item.phone.bytes));
                        if (total > 1024L * 1024 * 1024) throw new IOException("一次处理的手机照片总量不能超过 1 GB。已完成的工作副本保留在应用相册。");
                    }
                    // Same strict source boundary as the existing editor and batch renderer.
                    if (photoPresets != null) photoPresets.processingOriginalFor(photo, () -> cancelImport(request));
                    ready.add(photo);
                }
            } catch (IOException | RuntimeException failure) { error = message(failure); }
            catch (OutOfMemoryError memory) { error = "照片超出当前可用内存，请减少照片数量或选择较小的照片。"; }
            List<DownloadedPhoto> result = ready; String failure = error;
            main.post(() -> {
                if (cancelImport(request)) return; finishImport(); refreshApp();
                if (!failure.isEmpty()) { host.feedback("未开始编辑", failure + (result.isEmpty() ? "" : "\n已准备的 " + result.size() + " 张副本保留在应用相册。")); return; }
                selecting = false; selected.clear(); updateSelection();
                if (single && !result.isEmpty()) host.open(result.get(0)); else if (!result.isEmpty()) host.batch(Collections.unmodifiableList(result));
            });
        });
    }
    private void finishImport() { importing = false; workStatus = ""; updateState(); host.changed(); }
    private String albumQuery = "";
    private List<Item> current() {
        List<Item> source = phone ? phonePhotos : appPhotos;
        if (albumQuery.isEmpty()) return source;
        List<Item> matches = new ArrayList<>(); String query = albumQuery.toLowerCase(Locale.ROOT);
        for (Item item : source) if (item.name().toLowerCase(Locale.ROOT).contains(query)) matches.add(item); return matches;
    }
    private void searchPhotos() {
        if (hasSelectionDock()) return;
        android.widget.EditText input = new android.widget.EditText(activity); input.setSingleLine(true); input.setText(albumQuery); input.setTextSize(15);
        input.setTextColor(UiPalette.home(activity).text); input.setHintTextColor(UiPalette.home(activity).secondary);
        input.setHint(phone && phoneMore ? "搜索已载入的照片" : "输入照片名称"); input.setPadding(dp(20), dp(12), dp(20), dp(12));
        new AppDialog.Builder(activity).setTitle("搜索照片").setView(input).setPositiveButton("搜索", (d,w) -> { savePosition(); albumQuery = input.getText().toString().trim(); rebuildRows(); updateState(); })
            .setNeutralButton("清除", (d,w) -> { albumQuery = ""; rebuildRows(); updateState(); }).setNegativeButton("取消", null).show();
    }
    private void preserveSelection() { Set<String> available = new HashSet<>(); for (Item item : current()) available.add(item.key); selected.retainAll(available); }
    private void savePosition() {
        // A detached editor background or an outstanding restore is not a new browsing position.
        if (list == null || positionRestorePending || !list.isAttachedToWindow() || !list.isShown() || list.getChildCount() == 0) return;
        int first = list.getFirstVisiblePosition(); if (first < 0 || first >= rows.size()) return;
        int tab = phone ? 1 : 0; positions[tab] = list.onSaveInstanceState();
        positionKeys[tab] = rowKey(rows.get(first)); positionRows[tab] = first; positionTops[tab] = list.getChildAt(0).getTop() - list.getPaddingTop();
    }
    private void restorePosition() {
        int request = ++positionRestoreRequest;
        if (list == null) return;
        int tab = phone ? 1 : 0; Parcelable saved = positions[tab];
        positionRestorePending = true; positionRestoreApplied = false;
        if (rows.isEmpty()) return;
        ListView targetList = list;
        targetList.post(() -> {
            // Attaching the reused ListView can replace its sync state; restore after that lifecycle step.
            if (closed || list != targetList || request != positionRestoreRequest || tab != (phone ? 1 : 0) || !targetList.isAttachedToWindow() || rows.isEmpty()) return;
            positionRestoreApplied = true;
            if (saved != null) targetList.onRestoreInstanceState(saved);
            if (!positionKeys[tab].isEmpty()) {
                int target = Math.min(positionRows[tab], rows.size() - 1);
                for (int i = 0; i < rows.size(); i++) if (matchesPositionKey(rows.get(i), positionKeys[tab])) { target = i; break; }
                targetList.setSelectionFromTop(target, positionTops[tab]);
            } else if (saved == null) targetList.setSelectionFromTop(0, 0);
        });
    }
    private static String rowKey(Row row) { return row.header != null ? "date:" + row.header : row.items.isEmpty() ? "" : "photo:" + row.items.get(0).key; }
    private static boolean matchesPositionKey(Row row, String key) { if (row.header != null) return key.equals("date:" + row.header); for (Item item : row.items) if (key.equals("photo:" + item.key)) return true; return false; }
    private void rebuildRows() {
        gridColumns = resolvedColumns();
        rows.clear(); String lastDate = ""; Row row = null, header = null;
        for (Item item : current()) {
            String date = cc.huevia.album.PhotoDateGroups.label(item.date);
            if (!date.equals(lastDate)) { header = Row.header(date); rows.add(header); lastDate = date; row = null; }
            header.items.add(item);
            if (row == null || row.items.size() == columns() * (compactLayout ? 1 : 3)) { row = new Row(); rows.add(row); } row.items.add(item);
        }
        if (adapter != null) adapter.notifyDataSetChanged();
    }
    private int columns() { return gridColumns; }
    private int resolvedColumns() {
        if (!compactLayout) return activity.getResources().getConfiguration().screenWidthDp >= 600 ? 4 : 2;
        if (hasSelectionDock()) return gridColumns;
        float scale = activity.getResources().getConfiguration().fontScale;
        int width = body != null && body.getWidth() > 0 ? Math.round(body.getWidth() / density()) : Math.min(720, activity.getResources().getConfiguration().screenWidthDp);
        int height = body != null && body.getHeight() > 0 ? Math.round(body.getHeight() / density()) : activity.getResources().getConfiguration().screenHeightDp - 140;
        int availableWidth = Math.max(48, width - 16);
        int edge = Math.max(48, Math.min(120, height - navReserve() - Math.round(48 * scale)));
        int maximum = Math.max(1, availableWidth / 54);
        return Math.min(maximum, Math.max(3, (availableWidth + edge + 5) / (edge + 6)));
    }
    private void updateSelection() { if (adapter != null) adapter.notifyDataSetChanged(); updateState(); host.changed(); }
    private void updateState() {
        if (root == null) return;
        LocalPhotoRepository.Access access = repository.access(); boolean loading = phone ? loadingPhone : loadingApp;
        phoneTab.setText("手机相册");
        phoneTab.setTextColor(phone ? palette.text : palette.secondary); appTab.setTextColor(phone ? palette.secondary : palette.text);
        phoneTab.setSelected(phone); appTab.setSelected(!phone);
        phoneTab.setBackground(new android.graphics.drawable.InsetDrawable(shape(phone ? palette.dark ? 0xff4B4640 : palette.card : android.graphics.Color.TRANSPARENT,dp(20)),0,dp(4),0,dp(4)));
        appTab.setBackground(new android.graphics.drawable.InsetDrawable(shape(!phone ? palette.dark ? 0xff4B4640 : palette.card : android.graphics.Color.TRANSPARENT,dp(20)),0,dp(4),0,dp(4)));
        phoneTab.setTypeface(Typeface.create(phone ? "sans-serif-medium" : "sans-serif", Typeface.NORMAL)); appTab.setTypeface(Typeface.create(phone ? "sans-serif" : "sans-serif-medium", Typeface.NORMAL));
        scope.setText(phone && access == LocalPhotoRepository.Access.NONE ? "未授权" : (phone && access == LocalPhotoRepository.Access.PARTIAL ? "已授权 · " : "") + "共 " + current().size() + (phone && phoneMore ? "+" : "") + " 张");
        if (!albumQuery.isEmpty()) scope.setText("匹配 " + current().size() + " 张 · " + albumQuery);
        scope.setContentDescription(phone ? (access == LocalPhotoRepository.Access.PARTIAL ? "仅浏览已授权照片，" : "手机照片，") + scope.getText() : "应用相册照片，" + scope.getText());
        permissionButton.setText(!phone ? "浏览手机照片" : access == LocalPhotoRepository.Access.PARTIAL ? "选择更多照片" : "允许访问照片");
        permissionButton.setVisibility(phone ? (access != LocalPhotoRepository.Access.FULL ? View.VISIBLE : View.GONE) : (current().isEmpty() && !loading && appError.isEmpty() ? View.VISIBLE : View.GONE));
        selectButton.setVisibility(!current().isEmpty() && !importing ? View.VISIBLE : View.GONE); selectButton.setEnabled(!importing); selectButton.setText(selecting ? "全选" : "选择"); selectButton.setContentDescription(selecting ? "全选当前已载入的照片" : "选择照片进行批量操作");
        boolean dockVisible = hasSelectionDock();
        phoneTab.setEnabled(!dockVisible); appTab.setEnabled(!dockVisible); phoneTab.setAlpha(dockVisible ? .68f : 1f); appTab.setAlpha(dockVisible ? .68f : 1f); permissionButton.setEnabled(!dockVisible);
        pickerButton.setVisibility(phone && access == LocalPhotoRepository.Access.NONE && !dockVisible ? View.VISIBLE : View.GONE); pickerButton.setEnabled(!dockVisible); if (moreButton != null) moreButton.setEnabled(!dockVisible);
        summaryRow.setVisibility(View.VISIBLE);
        progress.setVisibility(loading || importing ? View.VISIBLE : View.GONE);
        String error = phone ? phoneError : appError;
         status.setText(importing ? workStatus : loading ? "读取中…" : !error.isEmpty() ? "读取失败" : "");
        status.setVisibility(status.getText().length() == 0 ? View.GONE : View.VISIBLE);
        status.setTextColor(!error.isEmpty() && !importing ? palette.error : palette.secondary);
        boolean showEmpty = current().isEmpty(); emptyContainer.setVisibility(showEmpty ? View.VISIBLE : View.GONE); list.setVisibility(showEmpty ? View.GONE : View.VISIBLE);
        emptyTitle.setText(!albumQuery.isEmpty() && current().isEmpty() ? "没有匹配的照片" : loading ? "正在整理照片" : phone && access == LocalPhotoRepository.Access.NONE ? "浏览手机照片" : !error.isEmpty() ? "照片暂时无法读取" : phone ? "没有可显示的照片" : "这里还没有照片");
        emptyText.setText(!albumQuery.isEmpty() && current().isEmpty() ? "换个名称搜索，或清除搜索条件。" : loading ? "" : phone && access == LocalPhotoRepository.Access.NONE ? "允许访问后，即可在这里浏览照片。" : !error.isEmpty() ? error + "\n可在更多操作中刷新。" : phone ? "仅显示已授权的 JPEG / PNG 照片。" : "编辑或同步保存的照片会出现在这里。");
        selectionDock.setVisibility(dockVisible ? View.VISIBLE : View.GONE); selectionBar.setVisibility(dockVisible ? View.VISIBLE : View.GONE); selectionCount.setText(importing ? "准备中" : selected.isEmpty() ? "未选择" : "已选 " + selected.size() + " 张"); selectionCount.setContentDescription(importing ? workStatus : selectionCount.getText());
        batchButton.setText(phone ? "批量编辑" : "编辑"); batchButton.setMinWidth(dp(phone ? 96 : 60)); batchButton.setMinimumWidth(dp(phone ? 96 : 60));
        batchButton.setEnabled(!selected.isEmpty() && !importing);
        exportButton.setVisibility(phone ? View.GONE : View.VISIBLE);
        exportButton.setEnabled(!selected.isEmpty() && !importing && photoPresets != null && !photoPresets.isActive());
        exportButton.setAlpha(exportButton.isEnabled() ? 1f : .45f);
        list.setPadding(list.getPaddingLeft(), 0, list.getPaddingRight(), dp(navReserve() + 8));
        FrameLayout.LayoutParams guidanceParams = (FrameLayout.LayoutParams) emptyContainer.getLayoutParams(); if (guidanceParams.bottomMargin != dp(navReserve())) { guidanceParams.bottomMargin = dp(navReserve()); emptyContainer.setLayoutParams(guidanceParams); }
        if (dockUsingList == showEmpty) { dockUsingList = !showEmpty; selectionDock.setBackdrop(dockUsingList ? list : null); }
        layoutSelectionDock();
    }
    private void layoutSelectionDock() {
        if (selectionDock == null || body.getWidth() <= 0) return;
        int available = Math.max(dp(48), body.getWidth() - dp(32));
        int width = Math.min(dp(420), available);
        FrameLayout.LayoutParams params = (FrameLayout.LayoutParams) selectionDock.getLayoutParams(); if (params.width != width) { params.width = width; selectionDock.setLayoutParams(params); }
        boolean narrow = body.getWidth() < dp(350);
        if (narrowDock != null && narrowDock == narrow) return;
        narrowDock = narrow;
        cancelButton.setMinWidth(dp(narrow ? 48 : 66)); cancelButton.setMinimumWidth(dp(narrow ? 48 : 66)); cancelButton.setPadding(dp(narrow ? 6 : 8), 0, dp(narrow ? 6 : 8), 0);
        selectionCount.setTextSize(narrow ? 11 : 12);
        dockIcon(cancelButton, narrow ? null : AppIcon.Kind.CLOSE, 15);
        dockIcon(exportButton, narrow ? null : AppIcon.Kind.DOWNLOAD, 16);
    }
    private final class PhotoAdapter extends BaseAdapter {
        public int getCount() { return rows.size(); }
        public Object getItem(int position) { return rows.get(position); }
        public long getItemId(int position) { return position; }
        public int getViewTypeCount() { return 2; }
        public int getItemViewType(int position) { return rows.get(position).header != null ? 0 : 1; }
        public boolean areAllItemsEnabled() { return false; }
        public boolean isEnabled(int position) { return false; }
        public View getView(int position, View recycled, ViewGroup parent) {
            Row row = rows.get(position);
            if (row.header != null) {
                LocalDateHeader header = recycled instanceof LocalDateHeader ? (LocalDateHeader) recycled : new LocalDateHeader();
                header.label.setText(row.header); header.label.setTextSize(13); header.count.setText(row.items.size() + " 张照片"); header.count.setVisibility(selecting ? View.GONE : View.VISIBLE); header.check.setVisibility(selecting ? View.VISIBLE : View.GONE);
                List<String> keys = dateKeys(row);
                header.check.bind(row.header, cc.huevia.album.PhotoGroupSelection.state(keys, selected), keys.size());
                header.check.setEnabled(!importing && !keys.isEmpty()); header.check.setOnClickListener(v -> toggleDate(row));
                return header;
            }
            LinearLayout strip = recycled instanceof LinearLayout ? (LinearLayout) recycled : new LinearLayout(activity); strip.removeAllViews(); strip.setBaselineAligned(false);
            int count = columns();
            for (int column = 0; column < count; column++) {
                LinearLayout stack = new LinearLayout(activity); stack.setOrientation(LinearLayout.VERTICAL);
                LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(0, -2, 1); params.setMargins(dp(5), 0, dp(5), 0);
                for (int index = column; index < row.items.size(); index += count) {
                    int rank = index / count; float[] pattern = column % 2 == 0 ? new float[]{1.45f, .93f, 1.14f} : new float[]{1.14f, 1.45f, .93f};
                    View tile = photoTile(row.items.get(index), compactLayout ? 1f : pattern[rank % 3]);
                    LinearLayout.LayoutParams tileParams = new LinearLayout.LayoutParams(-1, -2); tileParams.bottomMargin = dp(10); stack.addView(tile, tileParams);
                }
                strip.addView(stack, params);
            }
            return strip;
        }
    }
    private View photoTile(Item item, final float ratio) {
                LinearLayout tile = new LinearLayout(activity); tile.setOrientation(LinearLayout.VERTICAL);
                FrameLayout frame = new FrameLayout(activity) { @Override protected void onMeasure(int width, int height) { super.onMeasure(width, View.MeasureSpec.makeMeasureSpec(Math.round(View.MeasureSpec.getSize(width)*ratio), View.MeasureSpec.EXACTLY)); } };
                frame.setBackground(shape(palette.container,dp(17)));frame.setClipToOutline(true); ImageView image = new ImageView(activity); image.setScaleType(ImageView.ScaleType.CENTER_CROP); frame.addView(image, new FrameLayout.LayoutParams(-1, -1));
                String key = item.thumbKey(); image.setTag(key); Bitmap cached = thumbnails.get(key); if (cached != null) image.setImageBitmap(cached); else { image.setImageDrawable(new PhotoPlaceholder(activity, palette, failedThumbs.contains(key))); requestThumbnail(item, image); }
                if (selecting) {
                    boolean picked = selected.contains(item.key);
                    int accent = palette.primaryContainer;
                    ImageView check = new ImageView(activity); check.setTag("local-album-selection-indicator"); check.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO); check.setPadding(dp(3.5f), dp(3.5f), dp(3.5f), dp(3.5f));
                    GradientDrawable circle = new GradientDrawable(); circle.setShape(GradientDrawable.OVAL); circle.setColor(picked ? accent : 0x80141412); if (!picked) circle.setStroke(dp(1.5f), 0xE6FFFFFF); check.setBackground(circle);
                    if (picked) check.setImageDrawable(new AppIcon(AppIcon.Kind.CHECK, palette.onPrimaryContainer, density()));
                    FrameLayout.LayoutParams mark = new FrameLayout.LayoutParams(dp(22), dp(22), Gravity.TOP | Gravity.END); mark.setMargins(0, dp(10), dp(10), 0); frame.addView(check, mark);
                    if (picked) { GradientDrawable ring = shape(android.graphics.Color.TRANSPARENT, dp(17)); ring.setStroke(dp(2), palette.card); frame.setForeground(ring); }
                }
                tile.addView(frame, new LinearLayout.LayoutParams(-1, -2));
                TextView filename = text(item.name(), 12, palette.text); filename.setMaxLines(1); filename.setEllipsize(TextUtils.TruncateAt.END); filename.setPadding(dp(2), dp(compactLayout ? 4 : 6), dp(2), dp(compactLayout ? 2 : 4));if(compactLayout)tile.addView(filename);
                tile.setContentDescription(item.name() + (item.group == null ? "" : "，当前版本 " + currentVersionName(item.group) + "，" + item.group.versions.size() + " 个版本") + (cached != null ? "" : failedThumbs.contains(key) ? "，预览暂不可用" : "，预览加载中") + (selected.contains(item.key) ? "，已选择" : ""));
                tile.setBackground(new RippleDrawable(ColorStateList.valueOf(palette.primaryContainer), null, shape(palette.card, 0)));
                tile.setOnClickListener(view -> clicked(item)); tile.setOnLongClickListener(view -> { if (!importing) toggle(item); return true; });
                if (!selecting && item.group != null && item.group.versions.size() > 1) {
                    View versions = homeVersionBadge(item); versions.setTag("local-album-version-badge"); FrameLayout.LayoutParams badge = new FrameLayout.LayoutParams(-2, dp(48), Gravity.TOP | Gravity.END);
                    badge.setMargins(dp(5), 0, dp(5), 0); frame.addView(versions, badge);
                }
        return tile;
    }
    private View homeVersionBadge(Item item) {
        FrameLayout hit = new FrameLayout(activity); TextView label = text(item.group.versions.size() + " 个版本", 10, palette.text);
        label.setSingleLine(true); label.setGravity(Gravity.CENTER); label.setPadding(dp(7), 0, dp(7), 0);
        label.setBackground(shape(palette.dark ? 0xEE292724 : 0xEEFFFFFF, dp(11)));
        hit.addView(label, new FrameLayout.LayoutParams(-2, dp(23), Gravity.TOP | Gravity.END));
        ((FrameLayout.LayoutParams)label.getLayoutParams()).topMargin = dp(8);
        hit.setMinimumWidth(dp(48)); hit.setContentDescription("选择照片版本，当前 " + currentVersionName(item.group) + "，共 " + item.group.versions.size() + " 个版本");
        hit.setEnabled(!importing); hit.setFocusable(!importing); hit.setOnClickListener(v -> chooseVersion(item.group)); return hit;
    }
    private void chooseVersion(PhotoLibraryCatalog.PhotoGroup group) {
        if (selecting || importing) return; String[] labels = new String[group.versions.size()];
        for (int i = 0; i < labels.length; i++) labels[i] = group.versionLabel(group.versions.get(i).photo);
        new AppDialog.Builder(activity).setTitle("选择照片版本").setItems(labels, (dialog, which) -> {
            savePosition(); DownloadedPhoto chosen = group.versions.get(which).photo;
            worker.execute(() -> { try { repository.selectVersion(group, chosen); main.post(() -> { if (!closed) { refreshApp(); host.open(chosen); } }); }
                catch (IOException error) { main.post(() -> { if (!closed) host.feedback("未切换版本", message(error)); }); } });
        }).setNegativeButton("取消", null).show();
    }
    private String currentVersionName(PhotoLibraryCatalog.PhotoGroup group) { return group.versionLabel(group.display); }
    private final class LocalDateHeader extends LinearLayout {
        final TextView label, count; final PhotoGroupCheck check;
        LocalDateHeader() {
            super(activity); setTag("local-album-date-header"); setGravity(Gravity.CENTER_VERTICAL); setPadding(dp(8), dp(compactLayout ? 0 : 6), 0, 0);
            label = text("",14,palette.text); label.setTypeface(null,Typeface.BOLD); label.setSingleLine(true); label.setEllipsize(TextUtils.TruncateAt.END);
            if (android.os.Build.VERSION.SDK_INT >= 28) label.setAccessibilityHeading(true);
            addView(label,new LinearLayout.LayoutParams(0,-2,1));
            count = text("", 11, palette.secondary); count.setPadding(dp(8), 0, dp(8), 0); count.setGravity(Gravity.CENTER_VERTICAL); addView(count, new LinearLayout.LayoutParams(-2, dp(48)));
            check = new PhotoGroupCheck(activity,palette.primaryContainer,palette.onPrimaryContainer,palette.secondary);
            addView(check,new LinearLayout.LayoutParams(dp(48),dp(48)));
        }
    }
    private void requestThumbnail(Item item, ImageView view) {
        String key = item.thumbKey(); if (closed || pendingThumbs.contains(key) || failedThumbs.contains(key)) return;
        int epoch = imageEpoch; pendingThumbs.add(key);
        try {
            images.execute(() -> {
                Bitmap bitmap = null; try { bitmap = item.phone == null ? repository.thumbnail(item.photo, dp(180)) : repository.thumbnail(item.phone, dp(180)); }
                catch (IOException | RuntimeException | OutOfMemoryError ignored) { }
                Bitmap result = bitmap;
                main.post(() -> {
                    pendingThumbs.remove(key); if (closed || epoch != imageEpoch) { if (result != null) result.recycle(); return; }
                    if (result != null) { thumbnails.put(key, result); if (key.equals(view.getTag())) view.setImageBitmap(result); }
                    else { failedThumbs.add(key); if (key.equals(view.getTag())) view.setImageDrawable(new PhotoPlaceholder(activity, palette, true)); }
                    main.removeCallbacks(thumbnailChanged); main.postDelayed(thumbnailChanged, 45);
                });
            });
        } catch (RejectedExecutionException full) { pendingThumbs.remove(key); }
    }
    private void thumbnailsChanged() { if (!closed && adapter != null) adapter.notifyDataSetChanged(); }
    private static final class Item {
        String key; long date; DownloadedPhoto photo; LocalPhotoRepository.PhonePhoto phone; PhotoLibraryCatalog.PhotoGroup group;
        static Item local(PhotoLibraryCatalog.PhotoGroup group) { Item item = new Item(); item.group = group; item.photo = group.display; item.key = group.id; item.date = group.photoDate; return item; }
        static Item phone(LocalPhotoRepository.PhonePhoto photo) { Item item = new Item(); item.phone = photo; item.key = photo.key; item.date = photo.date; return item; }
        String name() { return phone == null ? photo.filename() : phone.filename; }
        String thumbKey() { return phone == null ? photo.file().getPath() + "|" + photo.byteSize() + "|" + photo.downloadedAt() : phone.thumbnailKey(); }
    }
    private static final class Row { String header; final List<Item> items = new ArrayList<>(); static Row header(String date) { Row row = new Row(); row.header = date; return row; } }
    private Button button(String label, Runnable action) {
        Button button = new Button(activity); button.setText(label); button.setAllCaps(false); button.setTextSize(14); button.setTextColor(palette.primary);
        button.setMinHeight(dp(48)); button.setMinimumHeight(dp(48)); button.setMinWidth(dp(48)); button.setMinimumWidth(dp(48)); button.setPadding(dp(12), 0, dp(12), 0);
        HueTheme.styleAction(button,palette,false);
        button.setOnClickListener(view -> action.run()); return button;
    }
    private Button smallAction(String label, Runnable action) {
        Button result = button(label, action); result.setTextSize(13); result.setSingleLine(true);
        result.setTypeface(Typeface.create("sans-serif", Typeface.NORMAL)); result.setTextColor(palette.secondary);
        result.setStateListAnimator(null); result.setElevation(0); result.setTranslationZ(0);
        result.setBackgroundTintList(null); result.setBackground(new android.graphics.drawable.InsetDrawable(new RippleDrawable(ColorStateList.valueOf(palette.primaryContainer), shape(palette.container, dp(16)), null), 0, dp(8), 0, dp(8)));
        result.setPadding(dp(12), 0, dp(12), 0); return result;
    }
    private Button dockAction(String label, boolean primary, Runnable action) {
        Button result = button(label, action); result.setTextSize(13); result.setSingleLine(true); result.setIncludeFontPadding(false); result.setLetterSpacing(0);
        result.setTypeface(Typeface.create(primary ? "sans-serif-medium" : "sans-serif", Typeface.NORMAL));
        result.setMinHeight(dp(48)); result.setMinimumHeight(dp(48)); result.setStateListAnimator(null); result.setElevation(0); result.setTranslationZ(0); result.setBackgroundTintList(null);
        result.setTextColor(new ColorStateList(new int[][]{new int[]{-android.R.attr.state_enabled}, new int[]{}}, new int[]{palette.secondary, primary ? palette.onPrimaryContainer : palette.secondary}));
        android.graphics.drawable.StateListDrawable fill = new android.graphics.drawable.StateListDrawable();
        fill.addState(new int[]{-android.R.attr.state_enabled}, shape(primary ? palette.container : android.graphics.Color.TRANSPARENT, dp(22)));
        fill.addState(new int[]{}, shape(primary ? palette.primaryContainer : android.graphics.Color.TRANSPARENT, dp(22)));
        result.setBackground(new android.graphics.drawable.InsetDrawable(new RippleDrawable(ColorStateList.valueOf(palette.dark ? 0x33FFFFFF : 0x15000000), fill, shape(palette.card, dp(22))), 0, dp(2), 0, dp(2)));
        result.setPadding(dp(primary ? 14 : 8), 0, dp(primary ? 14 : 8), 0);
        return result;
    }
    private void dockIcon(Button button, AppIcon.Kind kind, int size) {
        AppIcon drawable = kind == null ? null : new AppIcon(kind, palette.secondary, density());
        if (drawable != null) drawable.setBounds(0, 0, dp(size), dp(size));
        button.setCompoundDrawables(drawable, null, null, null); button.setCompoundDrawablePadding(dp(4));
    }
    private void icon(Button button, AppIcon.Kind kind) { AppIcon icon = new AppIcon(kind, palette.primary, density()); icon.setBounds(0, 0, dp(18), dp(18)); button.setCompoundDrawables(icon, null, null, null); button.setCompoundDrawablePadding(dp(6)); }
    private TextView text(String value, int size, int color) { TextView text = new TextView(activity); text.setText(value); text.setTextSize(size); text.setTextColor(color); return text; }
    private GradientDrawable shape(int color, int radius) { GradientDrawable drawable = new GradientDrawable(); drawable.setColor(color); drawable.setCornerRadius(radius); return drawable; }
    private float density() { return activity.getResources().getDisplayMetrics().density; }
    private int dp(float value) { return Math.round(value * density()); }
    private static String message(Throwable error) { String text = error.getMessage(); return text == null || text.isBlank() ? "无法读取照片，请刷新或重新选择后重试。" : text; }
    @Override public void close() {
        if (closed) return; closed = true; phoneRequest++; appRequest++; importRequest++; imageEpoch++;
        if (photoPresets != null) photoPresets.removeObserver(presetChanged);
        worker.shutdownNow(); images.shutdownNow(); thumbnails.evictAll(); pendingThumbs.clear(); failedThumbs.clear();
        main.removeCallbacks(thumbnailChanged);
    }
}
