import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:go_router/go_router.dart';

import 'domain.dart';
import 'theme.dart';
import 'widgets.dart';
import 'legacy_presets.dart';
import 'legacy_sheets.dart';
import 'legacy_glass_sheet.dart';
import 'legacy_preset_details.dart';
import 'submission_editor.dart';
import 'personal_sync.dart';
import 'preset_context_menu.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, required this.state});
  final AppState state;
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  int tab = 0, page = 1, generation = 0, onlineTotal = 0;
  String category = '', query = '';
  // Keep the original bridge error for diagnostics. UI uses fixed copy below.
  String? error;
  late (String, bool) sessionIdentity;
  (String, bool) get currentSessionIdentity => (
    widget.state.session['user']?['id'] as String? ?? '',
    widget.state.session['logoutPending'] == true,
  );
  bool busy = false, hasMore = false, requestInFlight = false;
  bool importing = false;
  bool failedNext = false;
  ({bool next, bool refresh})? pendingLoad;
  List<Preset> online = [];
  List<String> categories = [];
  Timer? searchDelay;
  String notice = '';
  bool searching = false;
  String format = '', download = 'all';
  final filters = <int, ({String category, String format, String download})>{};

  Future<void> showFilters(List<String> choices) async {
    FocusManager.instance.primaryFocus?.unfocus();
    var nextCategory = category, nextFormat = format, nextDownload = download;
    final ordered = <String>[
      for (final value in ['人像', '风景', '胶片', '黑白', '日常', '夜景'])
        if (choices.contains(value)) value,
      ...choices.where(
        (value) =>
            !['人像', '风景', '胶片', '黑白', '日常', '夜景', '未分类', ''].contains(value),
      ),
      if (choices.contains('未分类')) '未分类',
    ];
    final accepted = await showLegacyGlassSheet<bool>(
      context,
      wrap: false,
      builder: (sheet) => StatefulBuilder(
        builder: (context, refresh) => HueFloatingSheet(
          title: '筛选',
          closeLabel: '关闭筛选，放弃未应用修改',
          onReset: () => refresh(() {
            nextCategory = '';
            nextFormat = '';
            nextDownload = 'all';
          }),
          onApply: () => Navigator.pop(sheet, true),
          children: [
            HueSheetChoices(
              title: '风格',
              values: [('', '全部'), for (final value in ordered) (value, value)],
              selected: nextCategory,
              columns: 4,
              onSelected: (value) => refresh(() => nextCategory = value),
            ),
            if (tab == 1)
              HueSheetChoices(
                title: '下载状态',
                values: const [
                  ('all', '全部'),
                  ('missing', '未下载'),
                  ('saved', '已下载'),
                ],
                selected: nextDownload,
                onSelected: (value) => refresh(() => nextDownload = value),
              ),
            HueSheetChoices(
              title: '预设类型',
              values: const [('', '全部'), ('NCP', 'NCP'), ('NP3', 'NP3')],
              selected: nextFormat,
              onSelected: (value) => refresh(() => nextFormat = value),
            ),
          ],
        ),
      ),
    );
    if (accepted == true && mounted) {
      setState(() {
        category = nextCategory;
        format = nextFormat;
        download = nextDownload;
      });
      unawaited(rememberFilters());
      if (tab == 1) await load();
    }
  }

  void selectSource(int value) {
    if (value == tab) return;
    filters[tab] = (category: category, format: format, download: download);
    final selected =
        filters[value] ?? (category: '', format: '', download: 'all');
    searchDelay?.cancel();
    generation++;
    pendingLoad = null;
    setState(() {
      tab = value;
      category = selected.category;
      format = selected.format;
      download = selected.download;
      busy = false;
      error = null;
      notice = '';
    });
    unawaited(rememberFilters());
    if (value == 1) unawaited(load());
  }

  void restoreFilters() {
    final saved = widget.state.uiPreferences;
    for (final index in [0, 1]) {
      final row = saved[index == 0 ? 'presetLocal' : 'presetOnline'];
      if (row is Map) {
        filters[index] = (
          category: row['category'] as String? ?? '',
          format: row['format'] as String? ?? '',
          download: row['download'] as String? ?? 'all',
        );
      }
    }
    tab = saved['presetSource'] == 'online' ? 1 : 0;
    final selected = filters[tab];
    if (selected != null) {
      category = selected.category;
      format = selected.format;
      download = selected.download;
    }
  }

  Future<void> rememberFilters() async {
    filters[tab] = (category: category, format: format, download: download);
    Json row(int index) {
      final value =
          filters[index] ?? (category: '', format: '', download: 'all');
      return {
        'category': value.category,
        'format': value.format,
        'download': value.download,
      };
    }

    try {
      await widget.state.saveUiPreferences({
        'presetSource': tab == 1 ? 'online' : 'local',
        'presetLocal': row(0),
        'presetOnline': row(1),
      });
    } catch (failure) {
      if (mounted) report(context, '筛选已应用，暂时无法记住筛选条件。');
    }
  }

  @override
  void initState() {
    super.initState();
    sessionIdentity = currentSessionIdentity;
    restoreFilters();
    widget.state.addListener(refreshState);
    if (tab == 1) unawaited(load());
  }

  void refreshState() {
    if (!mounted) return;
    if (sessionIdentity != currentSessionIdentity) {
      resetOnlineOwner();
    } else {
      setState(() {});
    }
  }

  void resetOnlineOwner() {
    searchDelay?.cancel();
    generation++;
    pendingLoad = null;
    sessionIdentity = currentSessionIdentity;
    setState(() {
      // Only the old account's transient view is retired; no cache file or
      // downloaded preset is removed or rewritten.
      online = [];
      categories = [];
      onlineTotal = 0;
      page = 1;
      hasMore = failedNext = false;
      error = null;
      notice = '';
      busy = false;
    });
    if (tab == 1 && !sessionIdentity.$2) unawaited(load());
  }

  @override
  void didUpdateWidget(covariant LibraryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      oldWidget.state.removeListener(refreshState);
      widget.state.addListener(refreshState);
      resetOnlineOwner();
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(refreshState);
    searchDelay?.cancel();
    generation++;
    super.dispose();
  }

  void searchChanged(String value) {
    searchDelay?.cancel();
    generation++;
    setState(() {
      query = value;
      if (tab == 1) {
        online = [];
        hasMore = false;
        busy = true;
      }
    });
    if (tab == 1) {
      searchDelay = Timer(
        const Duration(milliseconds: 220),
        () => unawaited(load()),
      );
    }
  }

  Future<void> load({bool next = false, bool refresh = false}) async {
    if (!mounted || tab != 1 || currentSessionIdentity.$2) return;
    if (next && (!hasMore || busy || requestInFlight)) return;
    if (requestInFlight) {
      generation++;
      pendingLoad = (next: next, refresh: refresh);
      setState(() => busy = true);
      return;
    }
    requestInFlight = true;
    final request = ++generation;
    final requestState = widget.state, requestOwner = currentSessionIdentity;
    bool accepted() =>
        mounted &&
        tab == 1 &&
        request == generation &&
        identical(requestState, widget.state) &&
        requestOwner == currentSessionIdentity &&
        !requestOwner.$2;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final searching =
          query.trim().isNotEmpty ||
          format.isNotEmpty ||
          download != 'all' ||
          category == '未分类';
      final value = await widget.state.core.call(
        searching ? 'online.search' : 'online.page',
        searching
            ? {'query': query, 'category': category, 'refresh': refresh}
            : {
                'page': next ? page + 1 : 1,
                'pageSize': 24,
                'category': category,
                'fileFormat': format,
              },
      );
      if (!accepted()) return;
      final rows = (value['items'] as List)
          .map((row) => Preset(object(row), online: true))
          .toList();
      setState(() {
        final cached = value['fromCache'] == true;
        final unavailable = value['available'] == false;
        final diagnostic = value['message'] as String? ?? '';
        if (unavailable) {
          // An unavailable response is not an authoritative empty catalog.
          failedNext = next;
          error = diagnostic.isEmpty ? '在线预设暂不可用。' : diagnostic;
          notice = '';
          return;
        }
        final previousPage = page;
        final unique = <String, Preset>{
          if (next)
            for (final item in online) item.id: item,
          for (final item in rows) item.id: item,
        };
        final progressed = !next || unique.length > online.length;
        if (!cached || unique.isNotEmpty || online.isEmpty) {
          online = unique.values.toList();
        }
        page = value['page'] as int? ?? (next ? previousPage + 1 : 1);
        hasMore =
            !searching &&
            value['hasMore'] == true &&
            progressed &&
            (!next || page > previousPage);
        onlineTotal = (value['total'] as num?)?.toInt() ?? online.length;
        categories = List<String>.from(value['categories'] as List)
            .where((item) => item.isNotEmpty)
            .toList();
        failedNext = false;
        notice = '';
        error = cached ? (diagnostic.isEmpty ? '使用离线缓存。' : diagnostic) : null;
      });
    } catch (failure) {
      if (accepted()) {
        setState(() {
          failedNext = next;
          error = '$failure';
        });
      }
    } finally {
      requestInFlight = false;
      if (accepted()) setState(() => busy = false);
      final pending = pendingLoad;
      pendingLoad = null;
      if (mounted && tab == 1 && pending != null) {
        unawaited(load(next: pending.next, refresh: pending.refresh));
      }
    }
  }

  Future<void> retryOnline() => load(next: failedNext, refresh: true);

  Future<void> import() async {
    final selected = await hueDialog<bool>(
      context: context,
      builder: (dialog) {
        final palette = HuePalette.of(dialog);
        return Dialog(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '添加预设',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    HueIconButton(
                      kind: HueIconKind.close,
                      label: '关闭添加预设',
                      disc: false,
                      iconSize: 20,
                      onPressed: () => Navigator.pop(dialog),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Material(
                  color: palette.container,
                  borderRadius: BorderRadius.circular(14),
                  child: ListTile(
                    minVerticalPadding: 14,
                    leading: const HueIcon(HueIconKind.file),
                    title: const Text('从文件导入', style: TextStyle(fontSize: 14)),
                    subtitle: const Text(
                      'NCP · NP3',
                      style: TextStyle(fontSize: 12),
                    ),
                    trailing: const HueIcon(HueIconKind.chevron, size: 16),
                    onTap: () => Navigator.pop(dialog, true),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '仅保存到本机',
                        style: TextStyle(
                          fontSize: 12,
                          color: palette.secondary,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(dialog);
                        context.push('/account');
                      },
                      child: const Text('登录同步', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    if (selected == true) await importFile();
  }

  Future<void> importFile() async {
    if (importing) return;
    setState(() => importing = true);
    try {
      if (!await widget.state.pickPreset()) return;
      if (mounted && widget.state.presets.isNotEmpty) {
        await detail(widget.state.presets.first);
      }
    } catch (error) {
      if (mounted) report(context, error);
    } finally {
      if (mounted) setState(() => importing = false);
    }
  }

  Future<void> detail(Preset preset) => hueRootPage<void>(
    context,
    MaterialPageRoute(
      builder: (page) => LegacyPresetDetails(
        state: widget.state,
        preset: preset,
        onCategory: () => editCategory(preset),
        onRemove: () {
          Navigator.pop(page);
          unawaited(remove(preset));
        },
        onShare: () async {
          try {
            final file = await widget.state.core.call('library.export', {
              'id': preset.id,
            });
            if (!mounted) return;
            await SharePlus.instance.share(
              ShareParams(
                sharePositionOrigin: shareAnchor(context),
                files: [XFile(file['path'] as String)],
                fileNameOverrides: [file['name'] as String],
              ),
            );
          } catch (failure) {
            if (mounted) report(context, failure);
          }
        },
        onDownload: () async {
          try {
            await widget.state.core.call('online.download', {
              'preset': preset.data,
              'owner': widget.state.session['user']?['id'] as String? ?? '',
            });
            await widget.state.refreshLibrary();
            if (page.mounted) Navigator.pop(page);
          } catch (failure) {
            if (mounted) report(context, failure);
          }
        },
      ),
    ),
  );
  Future<void> presetActions(Preset preset) async {
    final owner = widget.state.session['user']?['id'] as String? ?? '';
    final pinned = preset.pinned;
    bool current() =>
        mounted &&
        widget.state.session['logoutPending'] != true &&
        (widget.state.session['user']?['id'] as String? ?? '') == owner;
    if (!current()) return;
    final action = await showPresetContextMenu(
      context: context,
      presetName: preset.name,
      pinned: pinned,
    );
    if (!current() || action == null) return;
    if (action == PresetContextAction.remove) {
      await remove(preset);
      return;
    }
    if (action == PresetContextAction.pin) {
      try {
        await widget.state.pinPreset(preset, !pinned);
      } catch (failure) {
        if (mounted && current()) report(context, failure);
      }
    }
  }

  Future<void> editCategory(Preset preset) async {
    final owner = widget.state.session['user']?['id'] as String? ?? '';
    final input = TextEditingController(text: preset.category);
    final value = await hueDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('预设分类'),
        content: TextField(
          controller: input,
          maxLength: 24,
          decoration: const InputDecoration(labelText: '分类名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialog, input.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    input.dispose();
    if (value == null) return;
    try {
      await widget.state.core.call('library.category', {
        'id': preset.id,
        'category': value,
        'owner': owner,
      });
      await widget.state.refreshLibrary();
    } catch (error) {
      if (mounted) report(context, error);
    }
  }

  Future<void> remove(Preset preset) async {
    final owner = widget.state.session['user']?['id'] as String? ?? '';
    final value = await hueDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('移除预设？'),
        content: Text(
          owner.isEmpty
              ? preset.name
              : '${preset.name}\n\n从本机和当前账号的云端预设中移除，云端变更会在下次同步时提交。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (value != true) return;
    try {
      await widget.state.core.call('library.remove', {
        'id': preset.id,
        'owner': owner,
      });
      await widget.state.refreshLibrary();
    } catch (error) {
      if (mounted) report(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final source = tab == 0 ? widget.state.presets : online;
    final saved = widget.state.presets
        .map((preset) => preset.data['sha256'] ?? preset.id)
        .toSet();
    final rows = source
        .where(
          (preset) =>
              (format.isEmpty || preset.format == format) &&
              (tab == 0 ||
                  download == 'all' ||
                  (saved.contains(preset.data['sha256']) ==
                      (download == 'saved'))) &&
              (tab == 1 ||
                  category.isEmpty ||
                  (category == '未分类'
                      ? preset.category.isEmpty
                      : preset.category == category)) &&
              (tab == 1 ||
                  query.isEmpty ||
                  '${preset.name} ${preset.author} ${preset.category}'
                      .toLowerCase()
                      .contains(query.toLowerCase())),
        )
        .toList();
    final allCategories = {
      ...source.map(
        (preset) => preset.category.isEmpty ? '未分类' : preset.category,
      ),
      if (tab == 1) ...categories,
      if (category.isNotEmpty) category,
    }.toList();
    final activeFilters =
        category.isNotEmpty || format.isNotEmpty || download != 'all';
    final onlineFailure = tab == 1 && error != null;
    final onlineFailureText = rows.isNotEmpty
        ? '暂时无法连接在线预设，已保留缓存。'
        : '暂时无法连接在线预设，请重试或使用我的预设。';
    final displayedCount = tab == 1 && download == 'all' && format.isEmpty
        ? onlineTotal
        : rows.length;
    final palette = HuePalette.of(context);
    final compact = MediaQuery.sizeOf(context).height < 480;
    return Scaffold(
      appBar: HueHeader(
        title: '预设',
        compact: compact,
        leading: searching
            ? TextField(
                autofocus: true,
                onChanged: searchChanged,
                decoration: const InputDecoration(
                  hintText: '搜索预设',
                  isDense: true,
                ),
              )
            : null,
        actions: [
          if (searching)
            TextButton(
              onPressed: () {
                setState(() => searching = false);
                searchChanged('');
              },
              child: const Text('取消'),
            )
          else ...[
            HueIconButton(
              kind: HueIconKind.search,
              label: '搜索预设',
              onPressed: () => setState(() => searching = true),
            ),
            HueIconButton(
              kind: HueIconKind.plus,
              label: tab == 0 ? '导入本地预设' : '发布预设',
              filled: true,
              onPressed: importing
                  ? null
                  : tab == 0
                  ? import
                  : () => openSubmissionEditor(context, widget.state, null),
            ),
          ],
        ],
      ),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerScrolled) => [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: CapsuleSwitch(
                    labels: const ['在线预设', '我的预设'],
                    selected: 1 - tab,
                    onSelected: (value) => selectSource(1 - value),
                  ),
                ),
                if (tab == 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: SizedBox(
                      height: 44,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: InkWell(
                          onTap: () => widget.state.session['user'] == null
                              ? context.push('/account')
                              : hueRootPage<void>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        PersonalSyncPage(state: widget.state),
                                  ),
                                ),
                          child: Text(
                            widget.state.session['user'] == null
                                ? '仅保存在本机 · 登录后可同步云端 ›'
                                : '个人预设 · 管理云端同步 ›',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.2,
                              color: palette.secondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(20, 2, 20, 10),
                  child: Row(
                    children: [
                      for (final item in ['', ...allCategories])
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: SizedBox(
                            height: 48,
                            child: Center(
                              child: Material(
                                color: category == item
                                    ? palette.primaryContainer
                                    : palette.container,
                                borderRadius: BorderRadius.circular(18),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(18),
                                  onTap: () {
                                    setState(() => category = item);
                                    unawaited(rememberFilters());
                                    if (tab == 1) unawaited(load());
                                  },
                                  child: Container(
                                    constraints: const BoxConstraints(
                                      minWidth: 48,
                                    ),
                                    height: 36,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      item.isEmpty ? '全部' : item,
                                      style: TextStyle(
                                        fontSize: 12,
                                        height: 1.2,
                                        fontWeight: category == item
                                            ? FontWeight.w700
                                            : FontWeight.w400,
                                        color: category == item
                                            ? palette.onPrimaryContainer
                                            : palette.ink,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 2, 20, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          tab == 0 ? '我的色彩' : '发现色彩',
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.2,
                            fontWeight: FontWeight.w700,
                            color: palette.ink,
                          ),
                        ),
                      ),
                      Text(
                        '$displayedCount 份',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.2,
                          color: palette.secondary,
                        ),
                      ),
                      HueIconButton(
                        kind: HueIconKind.adjust,
                        label:
                            category.isNotEmpty ||
                                format.isNotEmpty ||
                                download != 'all'
                            ? '筛选预设，已应用条件'
                            : '筛选预设',
                        disc: false,
                        iconSize: 20,
                        onPressed: () => showFilters(allCategories),
                      ),
                    ],
                  ),
                ),
                if (notice.isNotEmpty && error == null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    child: Text(notice),
                  ),
                if (onlineFailure && rows.isNotEmpty && !failedNext)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          onlineFailureText,
                          style: TextStyle(
                            fontSize: 13,
                            color: palette.secondary,
                          ),
                        ),
                        Wrap(
                          spacing: 12,
                          children: [
                            TextButton(
                              onPressed: busy ? null : retryOnline,
                              child: const Text('重试加载'),
                            ),
                            TextButton(
                              onPressed: () => selectSource(0),
                              child: const Text('我的预设'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                if (busy || importing)
                  const LinearProgressIndicator(minHeight: 2),
              ],
            ),
          ),
        ],
        body: RefreshIndicator(
          onRefresh: () =>
              tab == 0 ? widget.state.refreshLibrary() : load(refresh: true),
          child: rows.isEmpty
              ? LayoutBuilder(
                  builder: (context, bounds) => SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.only(
                      bottom: hueNavigationInset(context),
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight:
                            (bounds.maxHeight - hueNavigationInset(context))
                                .clamp(0, double.infinity),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            HueIcon(
                              HueIconKind.presets,
                              size: 32,
                              color: palette.secondary,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              busy
                                  ? '正在读取预设'
                                  : onlineFailure
                                  ? onlineFailureText
                                  : activeFilters && error == null
                                  ? '没有符合条件的预设'
                                  : tab == 0
                                  ? '把喜欢的色彩带在身边'
                                  : '暂时没有在线预设',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 18,
                                height: 1.2,
                                fontWeight: FontWeight.w700,
                                color: palette.ink,
                              ),
                            ),
                            if (!onlineFailure) ...[
                              const SizedBox(height: 8),
                              Text(
                                activeFilters && error == null
                                    ? '试试其他筛选条件。'
                                    : tab == 0
                                    ? '添加 NCP、NP3，或从在线预设库下载喜欢的色彩。'
                                    : '可稍后刷新，或先使用我的预设。',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  height: 1.2,
                                  color: palette.secondary,
                                ),
                              ),
                            ],
                            const SizedBox(height: 20),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: busy || importing
                                    ? null
                                    : onlineFailure
                                    ? retryOnline
                                    : activeFilters && error == null
                                    ? () {
                                        setState(() {
                                          category = '';
                                          format = '';
                                          download = 'all';
                                        });
                                        unawaited(rememberFilters());
                                        if (tab == 1) unawaited(load());
                                      }
                                    : tab == 0
                                    ? import
                                    : load,
                                child: Text(
                                  activeFilters && error == null
                                      ? '清除筛选'
                                      : onlineFailure
                                      ? '重试加载'
                                      : tab == 0
                                      ? '添加本地预设'
                                      : '重新加载',
                                ),
                              ),
                            ),
                            if (tab == 1)
                              TextButton(
                                onPressed: () => selectSource(0),
                                child: const Text('我的预设'),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
              : LegacyPresetGrid(
                  rows: rows,
                  core: widget.state.core,
                  owner: widget.state.session['user']?['id'] as String? ?? '',
                  onOpen: detail,
                  onRemove: presetActions,
                  loadingMore: tab == 1 && busy,
                  pageError: onlineFailure && failedNext
                      ? onlineFailureText
                      : null,
                  onLocal: onlineFailure && failedNext
                      ? () => selectSource(0)
                      : null,
                  onMore: tab == 1 && (hasMore || error != null)
                      ? onlineFailure
                            ? failedNext
                                  ? retryOnline
                                  : null
                            : () => load(next: true)
                      : null,
                ),
        ),
      ),
    );
  }
}
