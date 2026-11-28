import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'domain.dart';
import 'theme.dart';
import 'widgets.dart';
import 'legacy_sheets.dart';
import 'legacy_glass_sheet.dart';
import 'photo_grid.dart';
import 'album_batch.dart';
import 'album_export_action.dart';
import 'album_selection_actions.dart';
import 'album_batch_presets.dart';
import 'album_edit_status.dart';
import 'album_operations.dart';
import 'photo_collage.dart';
import 'phone_album_categories.dart';
import 'phone_album_picker.dart';

class PhotosPage extends StatefulWidget {
  const PhotosPage({super.key, required this.state});
  final AppState state;
  @override
  State<PhotosPage> createState() => _PhotosPageState();
}

class _PhotosPageState extends State<PhotosPage> with WidgetsBindingObserver {
  AppState get state => widget.state;
  bool phone = false, importing = false, loading = false, more = false;
  bool oldest = false, added = false;
  int nextOffset = 0, generation = 0;
  String access = 'none', query = '', filter = '', error = '';
  String alternateBasis = 'added';
  PhoneAlbumCategory phoneCategory = PhoneAlbumCategory.all;
  int? phoneTotal;
  String phoneAlbum = '';
  List<Json> phoneAlbums = [];
  final albumMenuAnchor = GlobalKey();
  final albumCategoryAnchor = GlobalKey();
  bool canAsk = true;
  StreamSubscription<dynamic>? galleryChanges;
  String get alternateLabel =>
      phone && alternateBasis == 'modified' ? '修改时间' : '添加时间';
  List<Json> phonePhotos = [];
  final Set<String> pendingStars = {};
  final Set<String> selected = {};
  bool selecting = false;
  bool failedNext = false;
  String? selectionOwner;
  late final AlbumEditStatus editStatus = AlbumEditStatus(state);

  String get owner => state.session['user']?['id'] as String? ?? '';

  void selectionAccountChanged() {
    if (selecting &&
        (selectionOwner != owner || state.session['logoutPending'] == true)) {
      endSelection();
    }
  }

  void endSelection() {
    setState(() {
      selecting = false;
      selected.clear();
      selectionOwner = null;
    });
    const AlbumSelectionChanged(false).dispatch(context);
  }

  void toggleSelection(List<Json> rows) {
    if (importing) return;
    rows = rows.where((row) => row['mediaType'] != 'video').toList();
    final ids = rows.map((row) => row['id'] as String).toSet();
    if (!ids.every(selected.contains) && selected.union(ids).length > 100) {
      report(context, '一次最多选择 100 张照片。');
      return;
    }
    setState(() {
      selecting = true;
      selectionOwner ??= owner;
      if (ids.every(selected.contains)) {
        selected.removeAll(ids);
      } else {
        selected.addAll(ids);
      }
    });
    const AlbumSelectionChanged(true).dispatch(context);
  }

  void selectAll(List<Json> rows) {
    rows = rows.where((row) => row['mediaType'] != 'video').toList();
    if (selected.union(rows.map((row) => row['id'] as String).toSet()).length >
        100) {
      report(context, '一次最多选择 100 张照片。');
      return;
    }
    setState(() => selected.addAll(rows.map((row) => row['id'] as String)));
    const AlbumSelectionChanged(true).dispatch(context);
  }

  Future<void> selectedAction(
    List<Json> rows, {
    bool delete = false,
    bool export = false,
    bool collage = false,
    bool applyPreset = false,
  }) async {
    if (!selecting ||
        selectionOwner != owner ||
        state.session['logoutPending'] == true) {
      return;
    }
    final chosen = rows.where((row) => selected.contains(row['id'])).toList();
    if (chosen.isEmpty) return;
    if (collage && (chosen.length < 2 || chosen.length > 9)) {
      report(context, '一次请选择 2–9 张照片进行拼接。');
      return;
    }
    if (chosen.length != selected.length) {
      report(context, '部分所选照片已变化，请刷新后重新选择。');
      return;
    }
    if (applyPreset) {
      await showAlbumBatchPresets(context, state, chosen, phone: phone);
      return;
    }
    await hueRootPage<void>(
      context,
      MaterialPageRoute(
        builder: (_) => collage
            ? PhotoCollagePage(state: state, rows: chosen, phone: phone)
            : delete
            ? AlbumDeletePage(
                state: state,
                rows: chosen,
                phone: phone,
                onDeleted: (ids) {
                  if (!mounted || selectionOwner != owner) return;
                  setState(() {
                    selected.removeAll(ids);
                    if (phone) {
                      phonePhotos.removeWhere((row) => ids.contains(row['id']));
                    }
                  });
                },
              )
            : BatchExportPage(
                state: state,
                rows: chosen,
                phone: phone,
                saveToGallery: export,
                currentEffects: export,
              ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    final saved = state.uiPreferences['album'];
    if (saved is Map) {
      phone = saved['source'] == 'phone';
      filter = saved['filter'] as String? ?? '';
      phoneCategory = PhoneAlbumCategory.restored(
        saved['phoneCategory'] ?? (phone && filter == 'raw' ? 'raw' : 'all'),
      );
      added = saved['added'] == true;
      oldest = saved['oldest'] == true;
    }
    WidgetsBinding.instance.addObserver(this);
    state.addListener(selectionAccountChanged);
    editStatus.addListener(editsChanged);
    editStatus.refresh();
    if (state.core.root.isNotEmpty) {
      galleryChanges = state.core.galleryChanges.listen((event) {
        if (!mounted ||
            !phone ||
            event is! Map ||
            event['kind'] != 'galleryChanged') {
          return;
        }
        generation++;
        setState(() => loading = false);
        unawaited(readAccess());
      }, onError: (Object _) {});
    }
    unawaited(state.refreshStars().catchError((Object _) {}));
    unawaited(readAccess());
  }

  @override
  void dispose() {
    generation++;
    galleryChanges?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    state.removeListener(selectionAccountChanged);
    editStatus.removeListener(editsChanged);
    editStatus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState phase) {
    if (phase == AppLifecycleState.resumed) unawaited(readAccess());
  }

  Future<void> rememberAlbum() async {
    try {
      await state.saveUiPreferences({
        'album': {
          'source': phone ? 'phone' : 'app',
          'filter': filter,
          'phoneCategory': phoneCategory.id,
          'added': added,
          'oldest': oldest,
        },
      });
    } catch (failure) {
      if (mounted) report(context, '相册设置已应用，暂时无法记住这些设置。');
    }
  }

  void editsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> readAccess() async {
    try {
      final result = await state.core.call('gallery.access');
      if (!mounted) return;
      final previous = access;
      setState(() {
        access = result['access'] as String;
        alternateBasis = result['alternateBasis'] as String? ?? 'added';
        canAsk = result['canAsk'] != false;
        if (access == 'none' || previous != access) {
          generation++;
          loading = false;
          phonePhotos = [];
        }
      });
      if (phone && access != 'none') await loadPhone();
    } catch (_) {
      /* The system file picker remains available without library permission. */
    }
  }

  Future<void> loadPhone({bool next = false}) async {
    if (loading || access == 'none' || (next && !more)) return;
    final current = ++generation;
    setState(() {
      loading = true;
      error = '';
    });
    try {
      final result = await state.core.call('gallery.page', {
        'offset': next ? nextOffset : 0,
        'added': added,
        'oldest': oldest,
        'refresh': !next,
        'category': phoneCategory.id,
        'album': phoneAlbum,
        'query': query,
      });
      if (!mounted || current != generation) return;
      setState(() {
        final rows = (result['items'] as List).map(object).toList();
        final unique = <String, Json>{
          if (next)
            for (final row in phonePhotos) row['id'] as String: row,
          for (final row in rows) row['id'] as String: row,
        };
        final offset = result['nextOffset'] as int;
        more = result['hasMore'] == true && (!next || offset > nextOffset);
        phonePhotos = unique.values.toList();
        phoneTotal = (result['total'] as num?)?.toInt();
        if (result['albums'] is List) {
          phoneAlbums = (result['albums'] as List).map(object).toList();
        }
        nextOffset = offset;
      });
      unawaited(editStatus.linkPhoneRows(phonePhotos));
    } catch (failure) {
      if (mounted && current == generation) {
        setState(() {
          failedNext = next;
          error = '$failure';
        });
      }
    } finally {
      if (mounted && current == generation) setState(() => loading = false);
    }
  }

  Future<void> permission() async {
    try {
      final result = await state.core.galleryPermission();
      if (!mounted) return;
      setState(() {
        access = result['access'] as String;
        canAsk = result['canAsk'] != false;
        alternateBasis = result['alternateBasis'] as String? ?? 'added';
      });
      await loadPhone();
    } catch (failure) {
      if (mounted) report(context, failure);
    }
  }

  void source(int index) {
    setState(() => phone = index == 1);
    unawaited(rememberAlbum());
    if (phone && access != 'none') unawaited(loadPhone());
  }

  void selectPhoneCategory(PhoneAlbumCategory category) {
    if (category == phoneCategory || selecting || importing) return;
    setState(() {
      phoneCategory = category;
      generation++;
      loading = false;
      phonePhotos = [];
      phoneTotal = null;
      nextOffset = 0;
      more = false;
      error = '';
    });
    unawaited(rememberAlbum());
    unawaited(loadPhone());
  }

  void showAllPhoneMedia() {
    if (!phone || selecting || importing) return;
    setState(() {
      query = '';
      phoneAlbum = '';
      phoneCategory = PhoneAlbumCategory.all;
      generation++;
      loading = false;
      phonePhotos = [];
      phoneTotal = null;
      nextOffset = 0;
      more = false;
      error = '';
    });
    unawaited(rememberAlbum());
    unawaited(loadPhone());
  }

  Future<void> choosePhoneAlbum() async {
    final fallback = <Json>[
      {
        'id': '',
        'name': '全部相册',
        'count': phoneTotal ?? phonePhotos.length,
        if (phonePhotos.isNotEmpty) 'cover': phonePhotos.first['id'],
      },
    ];
    final choice = await showPhoneAlbumPicker(
      context,
      anchor: albumCategoryAnchor,
      core: state.core,
      albums: phoneAlbums.isEmpty ? fallback : phoneAlbums,
      selected: phoneAlbum,
    );
    if (!mounted || choice == null || choice == phoneAlbum) return;
    setState(() {
      phoneAlbum = choice;
      query = '';
      generation++;
      loading = false;
      phonePhotos = [];
      phoneTotal = null;
      nextOffset = 0;
      more = false;
      error = '';
    });
    unawaited(loadPhone());
  }

  Future<void> pick() async {
    if (importing) return;
    Photo? photo;
    setState(() => importing = true);
    try {
      photo = await state.pickPhoto();
    } catch (failure) {
      if (mounted) report(context, failure);
    } finally {
      if (mounted) setState(() => importing = false);
    }
    if (mounted && photo != null) unawaited(openImportedPhoto(photo));
  }

  Future<void> openImportedPhoto(Photo photo) async {
    try {
      if (mounted) await context.push<void>(photo.editorLocation);
    } catch (failure) {
      if (mounted) report(context, failure);
    }
  }

  Future<void> open(Json row) async {
    if (importing) return;
    if (phone && row['live'] == true) {
      final choice = await showLegacyGlassSheet<String>(
        context,
        builder: (sheet) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text('实况照片'),
                subtitle: Text('编辑静态画面会另存副本，原实况照片保留。'),
              ),
              ListTile(
                leading: const Icon(Icons.motion_photos_on_outlined),
                title: const Text('查看实况'),
                onTap: () => Navigator.pop(sheet, 'preview'),
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('编辑静态照片'),
                onTap: () => Navigator.pop(sheet, 'edit'),
              ),
            ],
          ),
        ),
      );
      if (!mounted || choice == null) return;
      if (choice == 'preview') {
        try {
          await state.core.call('gallery.preview', {'id': row['id']});
        } catch (failure) {
          if (mounted) report(context, failure);
        }
        return;
      }
    }
    if (!phone) {
      final photo = state.photos.firstWhere((photo) => photo.path == row['id']);
      await context.push(photo.editorLocation);
      return;
    }
    Photo? photo;
    setState(() => importing = true);
    try {
      final imported = await state.core.call('gallery.import', {
        'id': row['id'],
      });
      final info = await state.core.call('media.info', {
        'path': imported['path'],
      });
      photo = await state.registerPhoto(
        imported['path'] as String,
        imported['name'] as String,
        info,
      );
      photo = await state.linkPhonePhoto(photo, row);
    } catch (failure) {
      if (mounted) report(context, failure);
    } finally {
      if (mounted) setState(() => importing = false);
    }
    if (mounted && photo != null) unawaited(openImportedPhoto(photo));
  }

  Future<void> search() async {
    final input = TextEditingController(text: query);
    final result = await hueDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('搜索照片'),
        content: TextField(
          controller: input,
          autofocus: true,
          decoration: const InputDecoration(hintText: '输入照片名称'),
          onSubmitted: (value) => Navigator.pop(dialog, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialog, input.text),
            child: const Text('搜索'),
          ),
        ],
      ),
    );
    input.dispose();
    if (result != null && mounted) {
      setState(() {
        query = result;
        generation++;
        loading = false;
      });
      if (phone) await loadPhone();
    }
  }

  Future<void> sort() async {
    var nextAdded = added, nextOldest = oldest;
    final accepted = await showLegacyGlassSheet<bool>(
      context,
      wrap: false,
      builder: (sheet) => StatefulBuilder(
        builder: (context, refresh) => HueFloatingSheet(
          title: '时间排序',
          titleSize: 16,
          sorting: true,
          closeLabel: '关闭排序，放弃未应用修改',
          onReset: () => refresh(() {
            nextAdded = false;
            nextOldest = false;
          }),
          onApply: () => Navigator.pop(sheet, true),
          children: [
            HueSheetChoices(
              title: '排序依据',
              topPadding: 0,
              bottomPadding: 4,
              values: [('taken', '拍摄时间'), ('added', alternateLabel)],
              selected: nextAdded ? 'added' : 'taken',
              columns: 2,
              fontSize: 14,
              verticalInset: 6,
              boldSelection: false,
              onSelected: (value) =>
                  refresh(() => nextAdded = value == 'added'),
            ),
            HueSheetChoices(
              title: '排列顺序',
              topPadding: 10,
              bottomPadding: 4,
              values: const [('newest', '新到旧'), ('oldest', '旧到新')],
              selected: nextOldest ? 'oldest' : 'newest',
              columns: 2,
              fontSize: 14,
              verticalInset: 6,
              boldSelection: false,
              onSelected: (value) =>
                  refresh(() => nextOldest = value == 'oldest'),
            ),
            if (!phone && nextAdded)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 6),
                child: Text(
                  '旧照片没有入库记录时，添加时间使用现存文件时间。',
                  style: TextStyle(
                    fontSize: 12,
                    color: HuePalette.of(context).secondary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (accepted == true && mounted) {
      setState(() {
        added = nextAdded;
        oldest = nextOldest;
      });
      unawaited(rememberAlbum());
      if (phone) await loadPhone();
    }
  }

  Future<void> actions(Json row) async {
    if (phone) return;
    final expectedOwner = owner;
    final photo = state.photos.firstWhere((photo) => photo.path == row['id']);
    final marked = state.starredPhotos.contains(photo.starKey);
    final result = await showLegacyGlassSheet<String>(
      context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(photo.name)),
            ListTile(
              title: Text(marked ? '取消星标' : '标记星标'),
              onTap: () => Navigator.pop(sheet, 'star'),
            ),
            ListTile(
              title: const Text('只看星标照片'),
              onTap: () => Navigator.pop(sheet, 'filter'),
            ),
          ],
        ),
      ),
    );
    if (!mounted ||
        expectedOwner != owner ||
        state.session['logoutPending'] == true) {
      return;
    }
    try {
      if (result == 'star') await state.starPhoto(photo, !marked);
      if (result == 'filter' && mounted) {
        setState(() => filter = filter == 'starred' ? '' : 'starred');
        unawaited(rememberAlbum());
      }
    } catch (failure) {
      if (mounted) report(context, failure);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) {
      final p = HuePalette.of(context),
          compact = MediaQuery.sizeOf(context).height < 480;
      final rows = phone
          ? phonePhotos
                .where(
                  (row) => (row['name'] as String).toLowerCase().contains(
                    query.toLowerCase(),
                  ),
                )
                .toList()
          : state.photos
                .where(
                  (photo) =>
                      photo.name.toLowerCase().contains(query.toLowerCase()) &&
                      (filter != 'raw' || photo.info['raw'] == true) &&
                      (filter != 'starred' ||
                          state.starredPhotos.contains(photo.starKey)),
                )
                .map(
                  (photo) => <String, dynamic>{
                    'id': photo.path,
                    'name': photo.name,
                    'raw': photo.info['raw'] == true,
                    'date': photo.info['addedAt'] ?? 0,
                    'photo': photo,
                  },
                )
                .toList();
      if (!phone && oldest) {
        rows.sort((a, b) => (a['date'] as int).compareTo(b['date'] as int));
      }
      return PopScope(
        canPop: !selecting,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && selecting) endSelection();
        },
        child: Scaffold(
          appBar: selecting
              ? AlbumSelectionHeader(
                  title: '已选 ${selected.length} 张',
                  compact: compact,
                  expanded:
                      MediaQuery.sizeOf(context).width < 420 &&
                      MediaQuery.textScalerOf(context).scale(1) > 1.3,
                  navigation: Tooltip(
                    message: '取消选择',
                    child: TextButton(
                      onPressed: endSelection,
                      style: TextButton.styleFrom(foregroundColor: p.primary),
                      child: const Text('取消'),
                    ),
                  ),
                  actions: [
                    PopupMenuButton<String>(
                      tooltip: '所选照片更多操作',
                      icon: const Icon(Icons.more_horiz),
                      enabled: selected.isNotEmpty,
                      onSelected: (value) => unawaited(
                        value == 'star'
                            ? actions(
                                rows.firstWhere(
                                  (row) => selected.contains(row['id']),
                                ),
                              )
                            : selectedAction(
                                rows,
                                delete: value == 'delete',
                                collage: value == 'collage',
                              ),
                      ),
                      itemBuilder: (_) => [
                        if (!phone && selected.length == 1)
                          const PopupMenuItem(
                            value: 'star',
                            child: Text('照片星标'),
                          ),
                        const PopupMenuItem(
                          value: 'edit',
                          child: Text('编辑所选照片'),
                        ),
                        PopupMenuItem(
                          value: 'collage',
                          enabled: selected.length >= 2 && selected.length <= 9,
                          child: const Text('图片拼接'),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('删除所选照片'),
                        ),
                      ],
                    ),
                    SizedBox(
                      width:
                          64 *
                          MediaQuery.textScalerOf(context).scale(1).clamp(1, 2),
                      height: 48,
                      child: TextButton(
                        onPressed: rows.isEmpty ? null : () => selectAll(rows),
                        child: const Text('全选'),
                      ),
                    ),
                  ],
                )
              : HueHeader(
                  title: '相册',
                  compact: compact,
                  actions: [
                    HueIconButton(
                      kind: HueIconKind.search,
                      label: '搜索照片',
                      iconSize: 20,
                      onPressed: search,
                    ),
                    PopupMenuButton<String>(
                      tooltip: '相册更多操作',
                      padding: EdgeInsets.zero,
                      icon: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: p.card,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: HueIcon(
                            HueIconKind.more,
                            size: 20,
                            color: p.secondary,
                          ),
                        ),
                      ),
                      onSelected: (value) {
                        if (value == 'collage') {
                          unawaited(
                            hueRootPage<void>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PhotoCollagePage(state: state),
                              ),
                            ),
                          );
                        } else if (value == 'sort') {
                          sort();
                        } else if (value == 'raw') {
                          unawaited(pick());
                        } else if (value == 'permission') {
                          unawaited(permission());
                        } else if (value == 'stars') {
                          setState(
                            () => filter = filter == 'starred' ? '' : 'starred',
                          );
                          unawaited(rememberAlbum());
                        } else if (value == 'rawFilter') {
                          setState(() => filter = filter == 'raw' ? '' : 'raw');
                          unawaited(rememberAlbum());
                        } else if (phone) {
                          unawaited(loadPhone());
                        } else {
                          unawaited(state.refreshStars());
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'collage',
                          child: Text('图片拼接'),
                        ),
                        if (phone)
                          const PopupMenuItem(value: 'sort', child: Text('排序')),
                        const PopupMenuItem(
                          value: 'refresh',
                          child: Text('刷新'),
                        ),
                        const PopupMenuItem(
                          value: 'raw',
                          child: Text('RAW 显影'),
                        ),
                        if (!phone)
                          PopupMenuItem(
                            value: 'stars',
                            child: Text(
                              filter == 'starred' ? '显示全部照片' : '只看星标照片',
                            ),
                          ),
                        if (!phone)
                          PopupMenuItem(
                            value: 'rawFilter',
                            child: Text(
                              filter == 'raw' ? '显示全部照片' : '只看 RAW 照片',
                            ),
                          ),
                        if (phone)
                          const PopupMenuItem(
                            value: 'permission',
                            child: Text('权限设置'),
                          ),
                      ],
                    ),
                  ],
                ),
          body: Stack(
            children: [
              Column(
                children: [
                  Offstage(
                    offstage: selecting && compact,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        compact ? 12 : 20,
                        0,
                        compact ? 12 : 20,
                        4,
                      ),
                      child: CapsuleSwitch(
                        labels: const ['手机相册', '应用相册'],
                        selected: phone ? 0 : 1,
                        onSelected: (index) => source(index == 0 ? 1 : 0),
                        enabled: !selecting,
                      ),
                    ),
                  ),
                  if (phone)
                    Offstage(
                      offstage: selecting && compact,
                      child: PhoneAlbumToolbar(
                        anchor: albumMenuAnchor,
                        name:
                            phoneAlbums
                                    .where((album) => album['id'] == phoneAlbum)
                                    .firstOrNull?['name']
                                as String? ??
                            '全部相册',
                        count: access == 'none'
                            ? '未授权'
                            : '${phoneTotal ?? rows.length} 张',
                        onAlbums: selecting || importing || access == 'none'
                            ? null
                            : choosePhoneAlbum,
                        onBatch:
                            selecting ||
                                importing ||
                                !rows.any((row) => row['mediaType'] != 'video')
                            ? null
                            : () => toggleSelection(const []),
                      ),
                    ),
                  if (phone)
                    Offstage(
                      offstage: selecting && compact,
                      child: Padding(
                        key: albumCategoryAnchor,
                        padding: const EdgeInsets.only(bottom: 8),
                        child: PhoneAlbumCategories(
                          selected: phoneCategory,
                          enabled: !selecting && !importing,
                          onSelected: selectPhoneCategory,
                        ),
                      ),
                    ),
                  if (!phone)
                    Offstage(
                      offstage: selecting && compact,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: SizedBox(
                          height: 52,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 4),
                                    child: Text(
                                      phone && access == 'none'
                                          ? '未授权'
                                          : query.isNotEmpty
                                          ? '匹配 ${rows.length} 张 · $query'
                                          : '共 ${phone ? phoneTotal ?? rows.length : rows.length} 张',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        height: 1.35,
                                        color: p.secondary,
                                      ),
                                    ),
                                  ),
                                ),
                                HueIconButton(
                                  kind: HueIconKind.sort,
                                  label:
                                      '排序，${added ? alternateLabel : '拍摄时间'}，${oldest ? '旧到新' : '新到旧'}',
                                  disc: false,
                                  iconSize: 20,
                                  onPressed: selecting ? null : sort,
                                ),
                                if (!selecting)
                                  TextButton(
                                    onPressed:
                                        !rows.any(
                                          (row) => row['mediaType'] != 'video',
                                        )
                                        ? null
                                        : () => toggleSelection(const []),
                                    child: Text(phone ? '批量修图' : '选择'),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (importing || loading)
                    const LinearProgressIndicator(minHeight: 2),
                  if (phone && access == 'limited')
                    TextButton(
                      onPressed: selecting ? null : permission,
                      child: const Text('已允许部分照片 · 管理可访问的照片'),
                    ),
                  Expanded(
                    child: rows.isEmpty
                        ? LayoutBuilder(
                            builder: (context, bounds) => SingleChildScrollView(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minHeight: (bounds.maxHeight - 104).clamp(
                                    0,
                                    double.infinity,
                                  ),
                                ),
                                child: Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: compact ? 16 : 32,
                                    vertical: compact ? 8 : 24,
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      if (!compact)
                                        HueIcon(
                                          HueIconKind.album,
                                          size: 40,
                                          color: p.secondary,
                                        ),
                                      SizedBox(height: compact ? 0 : 20),
                                      Text(
                                        query.isNotEmpty
                                            ? '没有匹配的照片'
                                            : loading
                                            ? '正在整理照片'
                                            : phone && access != 'none'
                                            ? '暂无${phoneCategory == PhoneAlbumCategory.all ? '照片' : phoneCategory.label}'
                                            : phone
                                            ? '浏览手机照片'
                                            : '这里还没有照片',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 20,
                                          height: 1.35,
                                          fontWeight: FontWeight.w700,
                                          color: p.ink,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        error.isNotEmpty
                                            ? error
                                            : phone && access != 'none'
                                            ? phoneCategory ==
                                                      PhoneAlbumCategory.live
                                                  ? '这里显示手机可识别的实况照片。仅允许部分照片时，可管理访问范围。'
                                                  : '当前访问范围内没有此类内容，可切换分类或管理访问范围。'
                                            : phone
                                            ? '允许访问后，即可在这里浏览照片。'
                                            : '编辑或同步保存的照片会出现在这里。',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 15,
                                          height: 1.35,
                                          color: p.secondary,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      FilledButton(
                                        style: FilledButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                          ),
                                          textStyle: const TextStyle(
                                            fontSize: 13,
                                            letterSpacing: .1,
                                          ),
                                        ),
                                        onPressed: importing
                                            ? null
                                            : phone
                                            ? more
                                                  ? () => loadPhone(next: true)
                                                  : access != 'none'
                                                  ? showAllPhoneMedia
                                                  : permission
                                            : () => source(1),
                                        child: Text(
                                          phone
                                              ? more
                                                    ? '继续查找'
                                                    : access != 'none'
                                                    ? query.isNotEmpty ||
                                                              phoneCategory !=
                                                                  PhoneAlbumCategory
                                                                      .all
                                                          ? '查看全部'
                                                          : '刷新'
                                                    : (canAsk
                                                          ? '允许访问照片'
                                                          : '前往照片权限设置')
                                              : '浏览手机照片',
                                        ),
                                      ),
                                      if (phone)
                                        SizedBox(
                                          height: 48,
                                          child: TextButton(
                                            style: TextButton.styleFrom(
                                              minimumSize: const Size(48, 48),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                  ),
                                            ),
                                            onPressed: importing ? null : pick,
                                            child: Text(
                                              '选择指定照片',
                                              style: TextStyle(
                                                fontSize: 12,
                                                letterSpacing: .6,
                                                decoration:
                                                    TextDecoration.underline,
                                                color: p.ink,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          )
                        : PhotoMasonry(
                            key: const ValueKey('album-grid'),
                            rows: rows,
                            phone: phone,
                            core: state.core,
                            edited: editStatus.editedIds(rows, phone: phone),
                            selected: selecting ? selected : null,
                            onGroup: toggleSelection,
                            bottomPadding: selecting
                                ? AlbumSelectionActions.reservedHeight(
                                        context,
                                      ) +
                                      hueNavigationInset(context)
                                : null,
                            onOpen: (row) async {
                              if (selecting) {
                                toggleSelection([row]);
                              } else {
                                await open(row);
                              }
                            },
                            onLongPress: (row) async {
                              toggleSelection([row]);
                            },
                            onMore: phone && (more || error.isNotEmpty)
                                ? () => loadPhone(
                                    next: error.isEmpty || failedNext,
                                  )
                                : null,
                            loadingMore: loading && rows.isNotEmpty,
                            pageError: error.isEmpty ? null : error,
                          ),
                  ),
                ],
              ),
              if (selecting)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height:
                      hueNavigationInset(context) +
                      AlbumSelectionActions.reservedHeight(context),
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            p.surface.withValues(alpha: 0),
                            p.surface.withValues(alpha: .97),
                            p.surface,
                          ],
                          stops: const [0, .45, 1],
                        ),
                      ),
                    ),
                  ),
                ),
              if (selecting)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 20 + hueNavigationInset(context),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.sizeOf(context).width - 48,
                      ),
                      child: AlbumSelectionActions(
                        count: selected.length,
                        onPreset: selected.isEmpty
                            ? null
                            : () => selectedAction(rows, applyPreset: true),
                        onExport: selected.isEmpty
                            ? null
                            : () => selectedAction(rows, export: true),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}
