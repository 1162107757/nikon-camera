import 'dart:math' as math;

import 'package:flutter/material.dart';

enum RetouchMoreAction {
  healHistory,
  manageToneCards,
  toggleToneScope,
  toggleFace,
  deleteFace,
  undoLastHeal,
  resetPortrait,
}

class RetouchHealEntry {
  const RetouchHealEntry({
    required this.index,
    required this.x,
    required this.y,
  });
  final int index;
  final double x, y;
}

class RetouchToneCard {
  const RetouchToneCard({
    required this.id,
    required this.name,
    required this.rgb,
  });
  final String id, name;
  final int rgb;
}

enum RetouchTonePickerAction { preview, sample }

class RetouchTonePickerResult {
  const RetouchTonePickerResult(this.action, this.rgb);
  final RetouchTonePickerAction action;
  final int rgb;
}

Future<RetouchTonePickerResult?> showRetouchCustomTone(
  BuildContext context, {
  required int rgb,
  required List<RetouchToneCard> cards,
  required Future<List<RetouchToneCard>> Function(String name, int rgb) onSave,
  ValueChanged<int>? onChanged,
}) => showDialog<RetouchTonePickerResult>(
  context: context,
  barrierColor: Colors.black.withValues(alpha: .42),
  builder: (_) => _CustomToneDialog(
    rgb: rgb,
    cards: cards,
    onSave: onSave,
    onChanged: onChanged,
  ),
);

/// Original 84 dp tone rail card, including the split original-colour swatch.
class RetouchToneCardButton extends StatelessWidget {
  const RetouchToneCardButton({
    super.key,
    required this.name,
    required this.rgb,
    required this.selected,
    required this.onTap,
    this.original = false,
    this.onLongPress,
  });
  final String name;
  final int rgb;
  final bool selected, original;
  final VoidCallback? onTap, onLongPress;
  @override
  Widget build(BuildContext context) => Semantics(
    label:
        '$name肤色${selected ? '，已选中' : ''}${onLongPress == null ? '' : '，长按删除个人色卡'}',
    selected: selected,
    button: true,
    enabled: onTap != null,
    onTap: onTap,
    onLongPress: onTap == null ? null : onLongPress,
    child: ExcludeSemantics(
      child: Opacity(
        opacity: onTap == null ? .4 : 1,
        child: SizedBox(
          width: MediaQuery.textScalerOf(context).scale(10) >= 12 ? 104 : 84,
          height: 84,
          child: Material(
            color: selected ? const Color(0x18121c17) : Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: selected
                  ? const BorderSide(color: Color(0xffbbb9a1))
                  : BorderSide.none,
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              onLongPress: onTap == null ? null : onLongPress,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Column(
                  children: [
                    CustomPaint(
                      size: const Size(40, 40),
                      painter: _ToneSwatch(rgb, original, selected),
                    ),
                    SizedBox(
                      height: 36,
                      child: Center(
                        child: Text(
                          name,
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            color: selected
                                ? Colors.white
                                : const Color(0xfff4f5f7),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _ToneSwatch extends CustomPainter {
  _ToneSwatch(this.rgb, this.original, this.selected);
  final int rgb;
  final bool original, selected;
  @override
  void paint(Canvas canvas, Size size) {
    final area = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(2),
      const Radius.circular(10),
    );
    canvas.drawRRect(
      area,
      Paint()
        ..color = original ? const Color(0xffb9a99a) : Color(0xff000000 | rgb),
    );
    if (original) {
      canvas.save();
      canvas.clipRect(
        Rect.fromLTRB(size.width / 2, 0, size.width, size.height),
      );
      canvas.drawRRect(area, Paint()..color = const Color(0xffe4d9ce));
      canvas.restore();
    }
    if (selected) {
      final brightness =
          .2126 * ((rgb >> 16) & 255) +
          .7152 * ((rgb >> 8) & 255) +
          .0722 * (rgb & 255);
      canvas.drawPath(
        Path()
          ..moveTo(size.width * .28, size.height * .51)
          ..lineTo(size.width * .44, size.height * .67)
          ..lineTo(size.width * .74, size.height * .34),
        Paint()
          ..color = original || brightness > 150
              ? const Color(0xff30241c)
              : Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(_ToneSwatch old) =>
      old.rgb != rgb || old.original != original || old.selected != selected;
}

class RetouchMoreState {
  const RetouchMoreState({
    required this.selectedFace,
    required this.faceEnabled,
    required this.heals,
    required this.hasPortrait,
    required this.skinMode,
    required this.tonePerFace,
    required this.toneCardCount,
    this.enabled = true,
  });
  final int? selectedFace;
  final bool faceEnabled, hasPortrait, skinMode, tonePerFace, enabled;
  final int toneCardCount;
  final List<RetouchHealEntry> heals;
}

// PhotoPortraitDialog.showMore ordering and UiPalette's editor-dark palette.
const _card = Color(0xff292724), _text = Color(0xfff6f1eb);
const _secondary = Color(0xffbab1a7), _primary = Color(0xfff3b493);
const _primaryContainer = Color(0xff51382d), _error = Color(0xffffb4a7);

Future<RetouchMoreAction?> showRetouchMoreMenu(
  BuildContext context, {
  required RetouchMoreState state,
}) {
  final overlay =
      Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
  final anchor = context.findRenderObject() as RenderBox;
  final rect =
      anchor.localToGlobal(Offset.zero, ancestor: overlay) & anchor.size;
  final face = state.selectedFace != null && state.selectedFace! >= 0;
  PopupMenuItem<RetouchMoreAction> item(
    RetouchMoreAction action,
    String label, [
    bool available = true,
  ]) => PopupMenuItem(
    value: action,
    enabled: state.enabled && available,
    height: 48,
    textStyle: TextStyle(
      fontSize: 14,
      color: _text.withValues(alpha: state.enabled && available ? 1 : .4),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 14,
        color: _text.withValues(alpha: state.enabled && available ? 1 : .4),
      ),
    ),
  );
  return showMenu<RetouchMoreAction>(
    context: context,
    position: RelativeRect.fromRect(rect, Offset.zero & overlay.size),
    color: _card,
    surfaceTintColor: Colors.transparent,
    constraints: const BoxConstraints(minWidth: 196, maxWidth: 320),
    items: [
      item(RetouchMoreAction.healHistory, '逐处撤销祛痘', state.heals.isNotEmpty),
      if (state.skinMode) ...[
        item(
          RetouchMoreAction.manageToneCards,
          '管理个人色卡',
          state.toneCardCount > 0,
        ),
        item(
          RetouchMoreAction.toggleToneScope,
          state.tonePerFace ? '全图肤色调节' : '逐人肤色调节（高级）',
        ),
      ],
      item(
        RetouchMoreAction.toggleFace,
        face && !state.faceEnabled ? '启用此人脸' : '停用此人脸',
        face,
      ),
      item(RetouchMoreAction.deleteFace, '删除此人脸', face),
      item(RetouchMoreAction.undoLastHeal, '撤回上一处祛痘', state.heals.isNotEmpty),
      item(RetouchMoreAction.resetPortrait, '重置人像精修'),
    ],
  );
}

Future<int?> showRetouchHealingHistory(
  BuildContext context, {
  required List<RetouchHealEntry> heals,
}) => showDialog<int>(
  context: context,
  barrierColor: Colors.black.withValues(alpha: .42),
  builder: (dialog) => _PortraitDialog(
    title: '选择要撤销的祛痘记录',
    actions: [_DialogButton('关闭', () => Navigator.pop(dialog))],
    child: _ChoiceList(
      children: [
        for (final entry in heals)
          _Choice(
            text:
                '撤销第 ${entry.index + 1} 处 · ${(entry.x * 100).round()}%, ${(entry.y * 100).round()}%',
            onTap: () => Navigator.pop(dialog, entry.index),
          ),
      ],
    ),
  ),
);

Future<List<int>?> showRetouchBlemishCandidates(
  BuildContext context, {
  required List<RetouchHealEntry> candidates,
}) => showDialog<List<int>>(
  context: context,
  barrierColor: Colors.black.withValues(alpha: .42),
  builder: (_) => _BlemishCandidatesDialog(candidates: candidates),
);

class _BlemishCandidatesDialog extends StatefulWidget {
  const _BlemishCandidatesDialog({required this.candidates});
  final List<RetouchHealEntry> candidates;
  @override
  State<_BlemishCandidatesDialog> createState() =>
      _BlemishCandidatesDialogState();
}

class _BlemishCandidatesDialogState extends State<_BlemishCandidatesDialog> {
  late final selected = {
    for (final candidate in widget.candidates) candidate.index,
  };
  void toggle(int index) => setState(() {
    if (!selected.remove(index)) selected.add(index);
  });
  @override
  Widget build(BuildContext context) => _PortraitDialog(
    title: '修复疑似小瑕疵',
    actions: [
      _DialogButton('取消', () => Navigator.pop(context)),
      _DialogButton(
        '修复所选',
        () => Navigator.pop(context, [
          for (final candidate in widget.candidates)
            if (selected.contains(candidate.index)) candidate.index,
        ]),
        primary: true,
      ),
    ],
    child: _ChoiceList(
      children: [
        for (final candidate in widget.candidates)
          Semantics(
            checked: selected.contains(candidate.index),
            label:
                '第 ${candidate.index + 1} 处 · ${(candidate.x * 100).round()}%, ${(candidate.y * 100).round()}%',
            onTap: () => toggle(candidate.index),
            child: ExcludeSemantics(
              child: InkWell(
                onTap: () => toggle(candidate.index),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '第 ${candidate.index + 1} 处 · ${(candidate.x * 100).round()}%, ${(candidate.y * 100).round()}%',
                            style: const TextStyle(fontSize: 14, color: _text),
                          ),
                        ),
                        Checkbox(
                          value: selected.contains(candidate.index),
                          onChanged: (_) => toggle(candidate.index),
                          activeColor: _primary,
                          checkColor: _card,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

Future<bool> confirmRetouchReset(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: .42),
      builder: (dialog) => _PortraitDialog(
        title: '重置人像精修？',
        message: '清除本次照片的肤色、磨皮、面部调整、塑形、选区修正和祛痘。仍可撤销。',
        actions: [
          _DialogButton('取消', () => Navigator.pop(dialog, false)),
          _DialogButton('重置', () => Navigator.pop(dialog, true), primary: true),
        ],
      ),
    ) ??
    false;

Future<int?> showRetouchOriginalChoices(
  BuildContext context, {
  required String title,
  required List<String> items,
  int? selected,
}) => showDialog<int>(
  context: context,
  barrierColor: Colors.black.withValues(alpha: .42),
  builder: (dialog) => _PortraitDialog(
    title: title,
    actions: [_DialogButton('取消', () => Navigator.pop(dialog))],
    child: _ChoiceList(
      children: [
        for (var i = 0; i < items.length; i++)
          _Choice(
            text: items[i],
            onTap: () => Navigator.pop(dialog, i),
            selected: selected == i,
          ),
      ],
    ),
  ),
);

Future<int?> showRetouchOriginalPopupChoices(
  BuildContext anchor, {
  required List<String> items,
  int? selected,
}) {
  final overlay =
      Navigator.of(anchor).overlay!.context.findRenderObject() as RenderBox;
  final box = anchor.findRenderObject() as RenderBox;
  final rect = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
  return showMenu<int>(
    context: anchor,
    position: RelativeRect.fromRect(rect, Offset.zero & overlay.size),
    color: _card,
    surfaceTintColor: Colors.transparent,
    constraints: const BoxConstraints(minWidth: 196, maxWidth: 320),
    items: [
      for (var i = 0; i < items.length; i++)
        CheckedPopupMenuItem<int>(
          value: i,
          checked: selected == i,
          height: 48,
          child: Text(
            items[i],
            style: const TextStyle(fontSize: 14, color: _text),
          ),
        ),
    ],
  );
}

Future<bool> confirmRetouchOriginalAction(
  BuildContext context, {
  required String title,
  required String message,
  required String positive,
}) async =>
    await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: .42),
      builder: (dialog) => _PortraitDialog(
        title: title,
        message: message,
        actions: [
          _DialogButton('取消', () => Navigator.pop(dialog, false)),
          _DialogButton(
            positive,
            () => Navigator.pop(dialog, true),
            primary: true,
            danger: positive.contains('删除') || positive.contains('清空'),
          ),
        ],
      ),
    ) ??
    false;

Future<int?> showRetouchOriginalInteger(
  BuildContext context, {
  required String title,
  required int value,
  int min = 0,
  int max = 100,
}) => showDialog<int>(
  context: context,
  barrierColor: Colors.black.withValues(alpha: .42),
  builder: (_) =>
      _OriginalIntegerDialog(title: title, value: value, min: min, max: max),
);

class _OriginalIntegerDialog extends StatefulWidget {
  const _OriginalIntegerDialog({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
  });
  final String title;
  final int value, min, max;
  @override
  State<_OriginalIntegerDialog> createState() => _OriginalIntegerDialogState();
}

class _OriginalIntegerDialogState extends State<_OriginalIntegerDialog> {
  late final input = TextEditingController(text: '${widget.value}')
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: '${widget.value}'.length,
    );
  String? error;
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  void accept() {
    final raw = input.text, value = int.tryParse(input.text);
    if (!RegExp(r'^[+-]?\d+$').hasMatch(raw) ||
        value == null ||
        value < widget.min ||
        value > widget.max) {
      setState(() => error = '请输入${widget.min}至${widget.max}的整数');
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) => _PortraitDialog(
    title: widget.title,
    actions: [
      _DialogButton('取消', () => Navigator.pop(context)),
      _DialogButton('确定', accept, primary: true),
    ],
    child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: TextField(
        key: const ValueKey('retouch-exact-value'),
        controller: input,
        keyboardType: TextInputType.number,
        maxLines: 1,
        style: const TextStyle(fontSize: 14, color: _text),
        decoration: InputDecoration(errorText: error, errorMaxLines: 2),
        onSubmitted: (_) => accept(),
      ),
    ),
  );
}

Future<List<RetouchToneCard>?> showRetouchToneCards(
  BuildContext context, {
  required List<RetouchToneCard> cards,
  required Future<List<RetouchToneCard>> Function(String id) onDelete,
}) => showDialog<List<RetouchToneCard>>(
  context: context,
  barrierColor: Colors.black.withValues(alpha: .42),
  barrierDismissible: false,
  builder: (_) => _ToneCardsDialog(cards: cards, onDelete: onDelete),
);

Future<bool> confirmRetouchDeleteToneCard(
  BuildContext context, {
  required RetouchToneCard card,
}) async =>
    await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: .42),
      builder: (dialog) => _PortraitDialog(
        title: '删除「${card.name}」？',
        message: '照片中已经使用的颜色会保留。',
        actions: [
          _DialogButton('取消', () => Navigator.pop(dialog, false)),
          _DialogButton(
            '删除',
            () => Navigator.pop(dialog, true),
            primary: true,
            danger: true,
          ),
        ],
      ),
    ) ??
    false;

Future<List<RetouchToneCard>?> showRetouchSaveToneCard(
  BuildContext context, {
  required List<RetouchToneCard> cards,
  required int rgb,
  required Future<List<RetouchToneCard>> Function(String name, int rgb) onSave,
}) => showDialog<List<RetouchToneCard>>(
  context: context,
  barrierColor: Colors.black.withValues(alpha: .42),
  barrierDismissible: false,
  builder: (_) => _SaveToneCardDialog(cards: cards, rgb: rgb, onSave: onSave),
);

class _ToneCardsDialog extends StatefulWidget {
  const _ToneCardsDialog({required this.cards, required this.onDelete});
  final List<RetouchToneCard> cards;
  final Future<List<RetouchToneCard>> Function(String id) onDelete;
  @override
  State<_ToneCardsDialog> createState() => _ToneCardsDialogState();
}

class _ToneCardsDialogState extends State<_ToneCardsDialog> {
  late List<RetouchToneCard> cards = List.of(widget.cards);
  bool busy = false;
  String? error;
  Future<void> remove(RetouchToneCard card) async {
    final confirmed = await confirmRetouchDeleteToneCard(context, card: card);
    if (!mounted || confirmed != true) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final next = await widget.onDelete(card.id);
      if (mounted) setState(() => cards = List.of(next));
    } catch (_) {
      if (mounted) setState(() => error = '色卡未能删除，请重试。');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: _PortraitDialog(
      title: '管理个人色卡',
      message: error ?? (cards.isEmpty ? '在自定义肤色中保存个人色卡。' : null),
      busy: busy,
      actions: [
        _DialogButton('关闭', busy ? null : () => Navigator.pop(context, cards)),
      ],
      child: _ChoiceList(
        children: [
          for (final card in cards)
            _Choice(
              text: '删除 · ${card.name}',
              onTap: busy ? null : () => remove(card),
            ),
        ],
      ),
    ),
  );
}

class _SaveToneCardDialog extends StatefulWidget {
  const _SaveToneCardDialog({
    required this.cards,
    required this.rgb,
    required this.onSave,
  });
  final List<RetouchToneCard> cards;
  final int rgb;
  final Future<List<RetouchToneCard>> Function(String name, int rgb) onSave;
  @override
  State<_SaveToneCardDialog> createState() => _SaveToneCardDialogState();
}

class _SaveToneCardDialogState extends State<_SaveToneCardDialog> {
  final name = TextEditingController();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final value = name.text.trim();
    final issue = value.isEmpty || value.length > 12
        ? '请为色卡填写 1–12 个字的名称。'
        : widget.cards.length >= 12
        ? '个人色卡已满（12 张），请先删除一张再保存。'
        : widget.cards.any((card) => card.rgb == (widget.rgb & 0xffffff))
        ? '这个颜色已经保存在个人色卡中。'
        : widget.cards.any(
            (card) => card.name.toLowerCase() == value.toLowerCase(),
          )
        ? '已有同名色卡，请换一个名称。'
        : null;
    if (issue != null) {
      setState(() => error = issue);
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final cards = await widget.onSave(value, widget.rgb & 0xffffff);
      if (mounted) Navigator.pop(context, cards);
    } catch (_) {
      if (mounted) setState(() => error = '色卡未能保存，请重试。');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: _PortraitDialog(
      title: '保存个人色卡',
      message: '仅保存在这台设备，最多 12 张。',
      busy: busy,
      actions: [
        _DialogButton('取消', busy ? null : () => Navigator.pop(context)),
        _DialogButton(
          '保存',
          busy ? null : save,
          primary: true,
          accent: const Color(0xffffe335),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
        child: TextField(
          key: const ValueKey('skin-tone-name'),
          controller: name,
          enabled: !busy,
          maxLength: 12,
          maxLines: 1,
          style: const TextStyle(fontSize: 14, color: _text),
          decoration: InputDecoration(
            hintText: '例如：日常暖肤',
            hintStyle: const TextStyle(color: _secondary),
            errorText: error,
            errorMaxLines: 3,
            counterText: '',
          ),
          onSubmitted: busy ? null : (_) => save(),
        ),
      ),
    ),
  );
}

class _CustomToneDialog extends StatefulWidget {
  const _CustomToneDialog({
    required this.rgb,
    required this.cards,
    required this.onSave,
    this.onChanged,
  });
  final int rgb;
  final List<RetouchToneCard> cards;
  final Future<List<RetouchToneCard>> Function(String name, int rgb) onSave;
  final ValueChanged<int>? onChanged;
  @override
  State<_CustomToneDialog> createState() => _CustomToneDialogState();
}

class _CustomToneDialogState extends State<_CustomToneDialog> {
  late HSVColor hsv = HSVColor.fromColor(Color(0xff000000 | widget.rgb));
  late List<RetouchToneCard> cards = List.of(widget.cards);
  String message = '保存的色卡可在其他照片中使用。';
  int get rgb => hsv.toColor().toARGB32() & 0xffffff;
  void finish(RetouchTonePickerAction action) =>
      Navigator.pop(context, RetouchTonePickerResult(action, rgb));
  Future<void> save() async {
    final next = await showRetouchSaveToneCard(
      context,
      cards: cards,
      rgb: rgb,
      onSave: widget.onSave,
    );
    if (mounted && next != null) {
      setState(() {
        cards = List.of(next);
        message = '已保存，可在肤色栏中重复使用。';
      });
    }
  }

  void update(HSVColor value) {
    setState(() => hsv = value);
    widget.onChanged?.call(rgb);
  }

  void position(Offset point, Size size) => update(
    hsv
        .withSaturation(
          ((point.dx - 4) / math.max(1, size.width - 8)).clamp(0, 1),
        )
        .withValue(
          1 - ((point.dy - 4) / math.max(1, size.height - 8)).clamp(0, 1),
        ),
  );
  @override
  Widget build(BuildContext context) {
    final color = Color(0xff000000 | rgb);
    final width = math.min(520.0, MediaQuery.sizeOf(context).width - 24);
    final height = math.min(560.0, MediaQuery.sizeOf(context).height * .68);
    final foreground = color.computeLuminance() > .179
        ? Colors.black
        : Colors.white;
    return Dialog(
      backgroundColor: _card,
      surfaceTintColor: Colors.transparent,
      alignment: Alignment.bottomCenter,
      insetPadding: const EdgeInsets.fromLTRB(12, 24, 12, 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SizedBox(
        width: width,
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '自定义肤色',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: _text,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭肤色选择器',
                    onPressed: () => finish(RetouchTonePickerAction.preview),
                    icon: const Icon(Icons.close, color: _text),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Column(
                  children: [
                    Container(
                      key: const ValueKey('skin-tone-preview'),
                      height: 52,
                      color: color,
                      alignment: Alignment.center,
                      child: Text(
                        '预览  #${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}',
                        style: TextStyle(fontSize: 14, color: foreground),
                      ),
                    ),
                    SizedBox(
                      height: 152,
                      child: LayoutBuilder(
                        builder: (_, bounds) => Semantics(
                          label: '饱和度和明度色盘，横向调整饱和度，纵向调整明度',
                          child: GestureDetector(
                            key: const ValueKey('skin-tone-sv'),
                            onPanDown: (details) =>
                                position(details.localPosition, bounds.biggest),
                            onPanUpdate: (details) =>
                                position(details.localPosition, bounds.biggest),
                            child: CustomPaint(
                              size: bounds.biggest,
                              painter: _SaturationValue(hsv),
                            ),
                          ),
                        ),
                      ),
                    ),
                    for (var axis = 0; axis < 3; axis++)
                      SizedBox(
                        height: 48,
                        child: Row(
                          children: [
                            SizedBox(
                              width: 56,
                              child: Text(
                                ['色相', '饱和度', '明度'][axis],
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xfff4f5f7),
                                ),
                              ),
                            ),
                            Expanded(
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  activeTrackColor: const Color(0xffffe335),
                                  thumbColor: const Color(0xffffe335),
                                  trackHeight: 2,
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 8,
                                  ),
                                ),
                                child: Slider(
                                  key: ValueKey(
                                    [
                                      'skin-tone-hue',
                                      'skin-tone-saturation',
                                      'skin-tone-value',
                                    ][axis],
                                  ),
                                  min: 0,
                                  max: axis == 0 ? 360 : 100,
                                  value: axis == 0
                                      ? hsv.hue
                                      : (axis == 1
                                                ? hsv.saturation
                                                : hsv.value) *
                                            100,
                                  divisions: axis == 0 ? 360 : 100,
                                  semanticFormatterCallback: (v) =>
                                      '${['色相', '饱和度', '明度'][axis]} ${v.round()}${axis == 0 ? '°' : '%'}',
                                  onChanged: (value) => update(
                                    axis == 0
                                        ? hsv.withHue(value)
                                        : axis == 1
                                        ? hsv.withSaturation(value / 100)
                                        : hsv.withValue(value / 100),
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 44,
                              child: Text(
                                '${(axis == 0 ? hsv.hue : (axis == 1 ? hsv.saturation : hsv.value) * 100).round()}${axis == 0 ? '°' : '%'}',
                                textAlign: TextAlign.end,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xffc8cdca),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: _pickerAction(
                            '照片取色',
                            'skin-tone-sample',
                            () => finish(RetouchTonePickerAction.sample),
                          ),
                        ),
                        Expanded(
                          child: _pickerAction('保存色卡', 'skin-tone-save', save),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          message,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xffc8cdca),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pickerAction(String label, String key, VoidCallback action) =>
      TextButton(
        key: ValueKey(key),
        onPressed: action,
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xffffe335),
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          textStyle: const TextStyle(fontSize: 13),
        ),
        child: Text(label),
      );
}

class _SaturationValue extends CustomPainter {
  _SaturationValue(this.hsv);
  final HSVColor hsv;
  @override
  void paint(Canvas canvas, Size size) {
    final area = (Offset.zero & size).deflate(4);
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(area, const Radius.circular(10)));
    canvas.drawRect(
      area,
      Paint()
        ..shader = LinearGradient(
          colors: [Colors.white, hsv.withSaturation(1).withValue(1).toColor()],
        ).createShader(area),
    );
    canvas.drawRect(
      area,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black],
        ).createShader(area),
    );
    final point = Offset(
      area.left + hsv.saturation * area.width,
      area.top + (1 - hsv.value) * area.height,
    );
    canvas.drawCircle(
      point,
      8,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = const Color(0x99000000),
    );
    canvas.drawCircle(
      point,
      8,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SaturationValue old) => old.hsv != hsv;
}

class _PortraitDialog extends StatelessWidget {
  const _PortraitDialog({
    required this.title,
    this.message,
    this.child,
    this.busy = false,
    required this.actions,
  });
  final String title;
  final String? message;
  final Widget? child;
  final bool busy;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: _card,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                color: _text,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (message != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Text(
                message!,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.22,
                  color: _secondary,
                ),
              ),
            ),
          if (child != null) Flexible(child: child!),
          if (busy)
            const LinearProgressIndicator(minHeight: 2, color: _primary),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: OverflowBar(
              alignment: MainAxisAlignment.end,
              spacing: 8,
              children: actions,
            ),
          ),
        ],
      ),
    ),
  );
}

class _ChoiceList extends StatelessWidget {
  const _ChoiceList({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Column(mainAxisSize: MainAxisSize.min, children: children),
  );
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.text,
    required this.onTap,
    this.selected = false,
  });
  final String text;
  final VoidCallback? onTap;
  final bool selected;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            text,
            style: TextStyle(
              fontSize: 14,
              color: (selected ? _primary : _text).withValues(
                alpha: onTap == null ? .4 : 1,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _DialogButton extends StatelessWidget {
  const _DialogButton(
    this.text,
    this.onPressed, {
    this.primary = false,
    this.danger = false,
    this.accent,
  });
  final String text;
  final VoidCallback? onPressed;
  final bool primary, danger;
  final Color? accent;
  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onPressed,
    style: TextButton.styleFrom(
      foregroundColor:
          accent ?? (primary ? (danger ? _error : _primary) : _secondary),
      backgroundColor: primary && !danger
          ? _primaryContainer
          : Colors.transparent,
      minimumSize: const Size(64, 48),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      side: primary && danger
          ? BorderSide(color: _error.withValues(alpha: .35))
          : BorderSide.none,
    ),
    child: Text(text),
  );
}
