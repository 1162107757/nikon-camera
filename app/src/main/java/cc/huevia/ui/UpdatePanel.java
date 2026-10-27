package cc.huevia.ui;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.content.ClipData;
import android.content.SharedPreferences;
import android.content.res.ColorStateList;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.view.Gravity;
import android.view.View;
import android.widget.*;
import cc.huevia.updates.AppUpdateManager;
import java.util.Locale;

/** The progress views update in place; camera pages never rebuild for update-download ticks. */
public final class UpdatePanel implements AutoCloseable {
    public interface Host {
        void onChanged();
        default int bottomNavigationInset() { return 0; }
        boolean idleForAutomaticCheck();
        default boolean readyForMandatoryUpdate() { return idleForAutomaticCheck(); }
        void onFeedback(String title, String message);
        void onAvailable(String version, Runnable show);
        void beforeInstall(Runnable proceed);
    }
    private final Activity activity;
    private final Host host;
    private final AppUpdateManager updates;
    private final SharedPreferences promptPrefs;
    private final Handler main = new Handler(Looper.getMainLooper());
    private static final long REMIND_AFTER = 8L * 60 * 60 * 1000;
    private UiPalette colors;
    private boolean open, waitingPermission, pendingResume, hostVisible, closed, openingPrompt, promptMandatory;
    private AlertDialog prompt;
    private String promptKey = "";
    private TextView promptVersion, promptNotes, promptStatus, promptDetail, promptMeta;
    private ProgressBar promptProgress;
    private final Runnable foregroundCheck = new Runnable() {
        @Override public void run() {
            if (closed || !hostVisible) return;
            automaticCheck(); main.postDelayed(this, 30_000);
        }
    };
    private long installEpoch;
    private LinearLayout content;
    private TextView status, detail, releaseName, notes, channel;
    private TextView releaseMeta;
    private LinearLayout notesGroup;
    private ProgressBar progress;
    private Button primary, secondary, check;
    public UpdatePanel(Activity activity, Host host) {
        this.activity = activity; this.host = host;
        colors = new UiPalette(activity);
        promptPrefs = activity.getSharedPreferences("app-update-prompts", Activity.MODE_PRIVATE);
        updates = new AppUpdateManager(activity, new AppUpdateManager.Listener() {
            @Override public void changed() { refresh(); }
            @Override public void available() { maybePrompt(); }
        });
    }
    public boolean isOpen() { return open; }
    public boolean isMandatoryBlocking() { return updates.mandatory(); }
    public void open() { open = true; host.onChanged(); if (updates.release == null && !updates.downloading) updates.check(false); maybePrompt(); }
    public void goBack() {
        if (updates.mandatory()) { maybePrompt(); return; }
        installEpoch++; open = false; content = null; host.onChanged();
    }
    public void automaticCheck() {
        if (closed || !hostVisible) return;
        updates.autoCheck(host.idleForAutomaticCheck() || updates.mandatory()); maybePrompt();
    }
    public void onResume() {
        hostVisible = true;
        updates.resume();
        main.removeCallbacks(foregroundCheck); main.post(foregroundCheck);
        if (waitingPermission) { waitingPermission = false;
            if (activity.getPackageManager().canRequestPackageInstalls()) pendingResume = true;
            else host.onFeedback("尚未允许安装", "可在系统设置中允许 Huevia 安装应用，再点击安装更新。");
        }
        if (pendingResume) { pendingResume = false; install(); }
        maybePrompt();
    }
    public void onPause() { hostVisible = false; installEpoch++; main.removeCallbacks(foregroundCheck); dismissPrompt(); updates.pause(); }
    public View createView(UiPalette palette) {
        colors = palette; ScrollView scroll = new ScrollView(activity); scroll.setClipToPadding(false); scroll.setFillViewport(true); scroll.setBackgroundColor(colors.surface);
        content = new LinearLayout(activity); content.setOrientation(LinearLayout.VERTICAL);
        content.setPadding(dp(22), dp(8), dp(22), dp(28) + Math.max(0, host.bottomNavigationInset())); scroll.addView(content);
        LinearLayout meta = row();
        TextView current = label("当前 " + version(), 13, false); current.setTextColor(colors.secondary);
        meta.addView(current, new LinearLayout.LayoutParams(0, -2, 1));
        channel = label("", 13, true); channel.setMinHeight(dp(48)); channel.setGravity(Gravity.CENTER);
        channel.setPadding(dp(14), 0, 0, 0); channel.setFocusable(true); channel.setOnClickListener(v -> chooseChannel());
        meta.addView(channel); content.addView(meta);
        LinearLayout panel = new LinearLayout(activity); panel.setOrientation(LinearLayout.VERTICAL);
        panel.setPadding(dp(20), dp(24), dp(20), dp(20)); panel.setBackground(shape(colors.card, 22));
        LinearLayout.LayoutParams card = new LinearLayout.LayoutParams(-1, -2); card.topMargin = dp(12); content.addView(panel, card);
        LinearLayout hero = row(); ImageView glyph = new ImageView(activity);
        glyph.setImageDrawable(new AppIcon(AppIcon.Kind.DOWNLOAD, colors.onPrimaryContainer, activity.getResources().getDisplayMetrics().density));
        glyph.setBackground(shape(colors.primaryContainer, 18)); glyph.setPadding(dp(15), dp(15), dp(15), dp(15));
        glyph.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO); hero.addView(glyph, new LinearLayout.LayoutParams(dp(56), dp(56)));
        LinearLayout copy = new LinearLayout(activity); copy.setOrientation(LinearLayout.VERTICAL); copy.setPadding(dp(16), 0, 0, 0);
        status = label("", 13, false); status.setTextColor(colors.secondary); status.setAccessibilityLiveRegion(View.ACCESSIBILITY_LIVE_REGION_POLITE); copy.addView(status);
        releaseName = label("", 25, true); releaseName.setPadding(0, dp(5), 0, 0); copy.addView(releaseName);
        hero.addView(copy, new LinearLayout.LayoutParams(0, -2, 1)); panel.addView(hero);
        releaseMeta = label("", 13, false); releaseMeta.setTextColor(colors.secondary); releaseMeta.setPadding(0, dp(18), 0, dp(4)); panel.addView(releaseMeta);
        progress = new ProgressBar(activity, null, android.R.attr.progressBarStyleHorizontal); progress.setMax(100);
        progress.setProgressTintList(ColorStateList.valueOf(colors.primary)); progress.setIndeterminateTintList(ColorStateList.valueOf(colors.primary));
        LinearLayout.LayoutParams track = new LinearLayout.LayoutParams(-1, dp(4)); track.topMargin = dp(16); panel.addView(progress, track);
        detail = label("", 13, false); detail.setPadding(0, dp(12), 0, dp(4)); panel.addView(detail);
        primary = action("", this::primaryAction, true); LinearLayout.LayoutParams mainAction = new LinearLayout.LayoutParams(-1, -2); mainAction.topMargin = dp(20); panel.addView(primary, mainAction);
        secondary = action("取消下载", updates::cancel, false); panel.addView(secondary, new LinearLayout.LayoutParams(-1, -2));
        notesGroup = new LinearLayout(activity); notesGroup.setOrientation(LinearLayout.VERTICAL); notesGroup.setPadding(dp(2), dp(26), dp(2), dp(10));
        TextView notesTitle = label("更新内容", 16, true); notesGroup.addView(notesTitle);
        notes = label("", 15, false); notes.setTextColor(colors.secondary); notes.setLineSpacing(dp(5), 1); notes.setPadding(0, dp(12), 0, 0); notesGroup.addView(notes);
        content.addView(notesGroup);
        check = action("重新检查", () -> updates.check(false), false); content.addView(check, new LinearLayout.LayoutParams(-1, -2));
        TextView explanation = label("安装前请先完成相机任务。", 12, false); explanation.setTextColor(colors.secondary);
        explanation.setPadding(dp(4), dp(16), dp(4), 0); content.addView(explanation);
        refresh(); return scroll;
    }
    private LinearLayout row() { LinearLayout row = new LinearLayout(activity); row.setOrientation(LinearLayout.HORIZONTAL); row.setGravity(Gravity.CENTER_VERTICAL); return row; }
    private void chooseChannel() {
        if (updates.mandatory()) { maybePrompt(); return; }
        if (updates.downloading || updates.checking || updates.verifying) { host.onFeedback("请稍后切换", "请先完成检查、取消下载或等待校验完成。"); return; }
        new AlertDialog.Builder(activity).setTitle("更新通道").setSingleChoiceItems(new String[]{"正式版", "测试版"}, "beta".equals(updates.channel()) ? 1 : 0,
                (dialog, which) -> { dialog.dismiss(); updates.channel(which == 1 ? "beta" : "stable"); }).setNegativeButton("取消", null).show();
    }
    private void primaryAction() {
        if (updates.release == null) { updates.check(false); return; }
        if (updates.verified) { install(); return; }
        if (updates.metered()) new AlertDialog.Builder(activity).setTitle("使用流量下载？")
                .setMessage("安装包约 " + size() + "，可能产生移动数据费用。")
                .setNegativeButton("稍后", null).setPositiveButton("继续下载", (d,w) -> updates.download(true)).show();
        else updates.download(false);
    }
    private void install() {
        final long token = ++installEpoch;
        updates.verifyForInstall(() -> {
            if (token == installEpoch && hostVisible && open && !activity.isFinishing())
                host.beforeInstall(() -> { if (token == installEpoch && hostVisible && open && !activity.isFinishing()) openInstaller(); });
        });
    }
    private void openInstaller() {
        if (!activity.getPackageManager().canRequestPackageInstalls()) {
            new AlertDialog.Builder(activity).setTitle("允许安装 Huevia 更新")
                    .setMessage("请在系统设置中允许此来源，返回后继续安装。")
                    .setNegativeButton("稍后", null).setPositiveButton("前往设置", (d,w) -> {
                        waitingPermission = true;
                        try { activity.startActivity(new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:" + activity.getPackageName()))); }
                        catch (RuntimeException failure) { waitingPermission = false; host.onFeedback("无法打开安装设置", "请在系统设置中允许 Huevia 安装应用。"); }
                    }).show(); return;
        }
        Uri uri = updates.installerUri(); if (uri == null) return;
        try {
            Intent intent = new Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            intent.setClipData(ClipData.newRawUri("Huevia update", uri)); activity.startActivity(intent);
        } catch (RuntimeException failure) { host.onFeedback("无法打开安装程序", "安装包已保留，请稍后重试。"); }
    }
    private void refresh() {
        if (closed) return;
        refreshPage();
        if (prompt != null && prompt.isShowing()) {
            if (updates.release == null || !promptKey.equals(releaseKey()) || promptMandatory != updates.mandatory()) dismissPrompt();
            else refreshPrompt();
        }
        maybePrompt();
    }
    private void refreshPage() {
        if (!open || content == null || status == null) return;
        AppUpdateManager.Release release = updates.release;
        boolean locked = updates.checking || updates.downloading || updates.verifying;
        channel.setText(("beta".equals(updates.channel()) ? "测试版" : "正式版") + (updates.mandatory() ? "" : "  ›"));
        channel.setContentDescription("更新通道，" + channel.getText()); channel.setEnabled(!locked && !updates.mandatory());
        status.setText(updates.checking ? "检查更新中" : updates.verifying ? "校验安装包" : updates.downloading ? "下载更新" : updates.verified ? "可以安装" : updates.mandatory() ? "需要更新" : release != null ? "有新版本" : updates.status);
        releaseName.setText(release == null ? "Huevia" : release.name);
        releaseMeta.setText(release == null ? "使用当前通道检查新版本" : size() + (updates.mandatory() ? " · 更新后继续使用" : " · 下载后确认安装"));
        notes.setText(release == null ? "" : release.notes); notesGroup.setVisibility(release == null || release.notes.isEmpty() ? View.GONE : View.VISIBLE);
        progress.setVisibility(locked ? View.VISIBLE : View.GONE); progress.setIndeterminate(updates.verifying || updates.checking); progress.setProgress(updates.progress);
        detail.setText(!updates.error.isEmpty() ? updates.error : updates.downloading ? updates.status + " · " + updates.progress + "%" : updates.verifying ? "正在核对文件与版本状态" : "");
        detail.setTextColor(updates.error.isEmpty() ? colors.secondary : colors.error); detail.setVisibility(detail.length() == 0 ? View.GONE : View.VISIBLE);
        primary.setText(release == null ? updates.checking ? "检查中…" : "检查更新" : updates.verified ? "安装更新" : updates.downloading ? "下载中 · " + updates.progress + "%" : updates.verifying ? "校验中…" : updates.error.isEmpty() ? "下载更新" : "重试下载");
        primary.setEnabled(!locked); primary.setAlpha(locked ? .55f : 1);
        secondary.setVisibility(updates.downloading && !updates.mandatory() ? View.VISIBLE : View.GONE);
        check.setVisibility(release != null ? View.VISIBLE : View.GONE); check.setEnabled(!updates.checking); check.setAlpha(updates.checking ? .55f : 1);
    }
    private String releaseKey() {
        AppUpdateManager.Release release = updates.release;
        return release == null ? "" : release.channel + ":" + release.id + ":" + release.code + ":" + release.hash;
    }
    private void maybePrompt() {
        if (closed || !hostVisible || openingPrompt || activity.isFinishing() || updates.release == null || prompt != null) return;
        boolean required = updates.mandatory();
        if (required ? !host.readyForMandatoryUpdate() : !host.idleForAutomaticCheck()) return;
        if (!required) {
            if (open || !updates.metadataChecked() || updates.checking || updates.downloading || updates.verifying) return;
            long elapsed = System.currentTimeMillis() - promptPrefs.getLong("shownAt", 0);
            if (releaseKey().equals(promptPrefs.getString("release", "")) && elapsed >= 0 && elapsed < REMIND_AFTER) return;
        }
        showPrompt(required);
    }
    private void showPrompt(boolean required) {
        openingPrompt = true;
        try {
            if (required && !open) { open = true; host.onChanged(); }
            final String key = releaseKey();
            LinearLayout body = new LinearLayout(activity); body.setOrientation(LinearLayout.VERTICAL); body.setPadding(dp(24), dp(4), dp(24), dp(8));
            promptVersion = label("", 24, true); promptVersion.setTag("update-prompt-version"); body.addView(promptVersion);
            promptMeta = label("", 13, false); promptMeta.setTextColor(colors.secondary); promptMeta.setPadding(0, dp(6), 0, dp(2)); body.addView(promptMeta);
            promptStatus = label("", 13, false); promptStatus.setTag("update-required-message"); promptStatus.setPadding(0, dp(10), 0, dp(8)); body.addView(promptStatus);
            promptProgress = new ProgressBar(activity, null, android.R.attr.progressBarStyleHorizontal); promptProgress.setTag("update-prompt-progress"); promptProgress.setMax(100); promptProgress.setProgressTintList(ColorStateList.valueOf(colors.primary)); body.addView(promptProgress, new LinearLayout.LayoutParams(-1, dp(5)));
            promptDetail = label("", 12, false); promptDetail.setTag("update-prompt-detail"); promptDetail.setPadding(0, dp(8), 0, dp(4)); promptDetail.setAccessibilityLiveRegion(View.ACCESSIBILITY_LIVE_REGION_POLITE); body.addView(promptDetail);
            promptNotes = label("", 14, false); promptNotes.setTag("update-prompt-notes"); promptNotes.setLineSpacing(dp(3), 1); promptNotes.setPadding(0, dp(12), 0, dp(4)); body.addView(promptNotes);
            ScrollView scroll = new ScrollView(activity) {
                @Override protected void onMeasure(int width, int height) {
                    int limit = Math.min(dp(320), activity.getResources().getDisplayMetrics().heightPixels / 2);
                    super.onMeasure(width, View.MeasureSpec.makeMeasureSpec(limit, View.MeasureSpec.AT_MOST));
                }
            };
            scroll.setFillViewport(false); scroll.addView(body);
            AlertDialog dialog = new AlertDialog.Builder(activity).setTitle(required ? "需要更新" : "发现新版本").setView(scroll)
                    .setPositiveButton(required ? "下载更新" : "立即更新", null)
                    .setNegativeButton(required ? "退出应用" : "稍后", null)
                    .setCancelable(!required).create();
            if (required) dialog.setButton(AlertDialog.BUTTON_NEUTRAL, "重新检查", (android.content.DialogInterface.OnClickListener) null);
            prompt = dialog; promptKey = key; promptMandatory = required;
            dialog.setCanceledOnTouchOutside(!required);
            dialog.setOnDismissListener(d -> {
                if (prompt == dialog) { prompt = null; main.post(this::maybePrompt); }
            });
            dialog.show(); PhotoEditorTypography.apply(dialog);
            dialog.getWindow().setBackgroundDrawable(shape(colors.card, 22));
            dialog.getWindow().getDecorView().setClipToOutline(true);
            dialog.getWindow().getDecorView().setTag("update-prompt-dialog");
            Button updateAction = dialog.getButton(AlertDialog.BUTTON_POSITIVE);
            updateAction.setTextColor(colors.onAction); updateAction.setBackgroundTintList(null); updateAction.setBackground(shape(colors.action, 24));
            updateAction.setPadding(dp(18), dp(8), dp(18), dp(8)); updateAction.setMinHeight(dp(48));
            updateAction.setOnClickListener(v -> {
                if (!key.equals(releaseKey())) { refresh(); return; }
                if (!required) { dismissPrompt(); open(); }
                primaryAction();
            });
            dialog.getButton(AlertDialog.BUTTON_NEGATIVE).setOnClickListener(v -> {
                if (required) activity.finishAndRemoveTask(); else dismissPrompt();
            });
            if (required) dialog.getButton(AlertDialog.BUTTON_NEUTRAL).setOnClickListener(v -> updates.check(false));
            else promptPrefs.edit().putString("release", key).putLong("shownAt", System.currentTimeMillis()).apply();
            refreshPrompt();
        } finally { openingPrompt = false; }
    }
    private void refreshPrompt() {
        if (prompt == null || updates.release == null) return;
        boolean locked = updates.checking || updates.downloading || updates.verifying;
        promptVersion.setText(updates.release.name);
        promptMeta.setText("Huevia · " + size() + " · " + ("beta".equals(updates.release.channel) ? "测试版" : "正式版"));
        promptNotes.setText(updates.release.notes); promptNotes.setVisibility(updates.release.notes.isEmpty() ? View.GONE : View.VISIBLE);
        promptStatus.setText(updates.downloading ? "正在下载 · " + updates.progress + "%" : updates.verifying ? "正在校验安装包…" : updates.checking ? "正在检查更新…" : promptMandatory ? "更新后可继续使用" : "新版本已可下载");
        promptProgress.setVisibility(locked ? View.VISIBLE : View.GONE); promptProgress.setIndeterminate(updates.checking || updates.verifying); promptProgress.setProgress(updates.progress);
        promptDetail.setText(updates.error); promptDetail.setTextColor(colors.error); promptDetail.setVisibility(updates.error.isEmpty() ? View.GONE : View.VISIBLE);
        Button positive = prompt.getButton(AlertDialog.BUTTON_POSITIVE);
        positive.setText(updates.verified ? "安装更新" : updates.downloading ? "正在下载" : updates.verifying ? "正在校验" : updates.error.isEmpty() ? (promptMandatory ? "下载更新" : "立即更新") : "重试下载"); positive.setEnabled(!locked);
        if (promptMandatory) prompt.getButton(AlertDialog.BUTTON_NEUTRAL).setEnabled(!updates.checking);
    }
    private void dismissPrompt() {
        AlertDialog old = prompt; prompt = null;
        if (old != null) old.dismiss();
    }
    private String size() { return updates.release == null ? "" : String.format(Locale.CHINA, "%.1f MiB", updates.release.bytes / 1048576d); }
    private String version() { try { return activity.getPackageManager().getPackageInfo(activity.getPackageName(),0).versionName; } catch (Exception ignored) { return ""; } }
    private TextView label(String value, int size, boolean bold) { TextView view = new TextView(activity); view.setText(value); view.setTextSize(size); view.setTextColor(colors.text); if (bold) view.setTypeface(Typeface.DEFAULT, Typeface.BOLD); return view; }
    private Button action(String value, Runnable click, boolean filled) { Button view = new Button(activity); view.setText(value); view.setTextSize(15); view.setAllCaps(false); view.setTextColor(filled ? colors.onAction : colors.text); view.setBackgroundTintList(null); view.setBackground(shape(filled ? colors.action : android.graphics.Color.TRANSPARENT, 26)); view.setMinHeight(dp(52)); view.setPadding(dp(18), dp(10), dp(18), dp(10)); view.setOnClickListener(v -> click.run()); return view; }
    private GradientDrawable shape(int color, int radius) { GradientDrawable value = new GradientDrawable(); value.setColor(color); value.setCornerRadius(dp(radius)); return value; }
    private int dp(float value) { return Math.round(value * activity.getResources().getDisplayMetrics().density); }
    @Override public void close() { closed = true; hostVisible = false; main.removeCallbacks(foregroundCheck); dismissPrompt(); content = null; updates.close(); }
}
