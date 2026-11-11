import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'hue_icons.dart';
export 'hue_icons.dart';

// The two original UiPalette.java palettes, without Material seed generation.
class HuePalette extends ThemeExtension<HuePalette> {
  const HuePalette({required this.dark, required this.home});
  final bool dark, home;
  Color get surface => Color(
    dark
        ? 0xff201f1d
        : home
        ? 0xfff8f7f4
        : 0xfffafaf8,
  );
  Color get container => Color(
    dark
        ? home
              ? 0xff34312d
              : 0xff33302c
        : home
        ? 0xffeeece6
        : 0xffefede9,
  );
  Color get card => Color(dark ? 0xff292724 : 0xffffffff);
  Color get ink => Color(
    dark
        ? 0xfff6f1eb
        : home
        ? 0xff242320
        : 0xff262320,
  );
  Color get secondary => Color(
    dark
        ? home
              ? 0xffcac2b8
              : 0xffbab1a7
        : home
        ? 0xff635d53
        : 0xff706a63,
  );
  Color get primary => Color(
    home
        ? dark
              ? 0xfff1ece4
              : 0xff242420
        : dark
        ? 0xfff3b493
        : 0xffb3432d,
  );
  Color get onPrimary => Color(
    home
        ? dark
              ? 0xff29251f
              : 0xffffffff
        : dark
        ? 0xff352016
        : 0xffffffff,
  );
  Color get primaryContainer => Color(
    home
        ? dark
              ? 0xfff1ece4
              : 0xff242420
        : dark
        ? 0xff51382d
        : 0xfff4d6c0,
  );
  Color get onPrimaryContainer => Color(
    home
        ? dark
              ? 0xff29251f
              : 0xffffffff
        : dark
        ? 0xfff3b493
        : 0xff85311f,
  );
  Color get outline => Color(dark ? 0xff4c4640 : 0xffe4dfd8);
  Color get action => Color(
    home
        ? dark
              ? 0xfff1ece4
              : 0xff242420
        : dark
        ? 0xfff0e8df
        : 0xff46413b,
  );
  Color get onAction => Color(
    dark
        ? home
              ? 0xff29251f
              : 0xff26211c
        : 0xffffffff,
  );
  Color get glass => Color(
    home
        ? dark
              ? 0xee2c2a26
              : 0xeeffffff
        : dark
        ? 0xf0292724
        : 0xf5fafaf8,
  );
  @override
  HuePalette copyWith({bool? dark, bool? home}) =>
      HuePalette(dark: dark ?? this.dark, home: home ?? this.home);
  @override
  HuePalette lerp(covariant HuePalette? other, double t) =>
      t < .5 || other == null ? this : other;
  static HuePalette of(BuildContext context) =>
      Theme.of(context).extension<HuePalette>()!;
}

ThemeData hueviaTheme(Brightness brightness, {bool home = true}) {
  final p = HuePalette(dark: brightness == Brightness.dark, home: home);
  final scheme = ColorScheme(
    brightness: brightness,
    primary: p.primary,
    onPrimary: p.onPrimary,
    primaryContainer: p.primaryContainer,
    onPrimaryContainer: p.onPrimaryContainer,
    secondary: p.secondary,
    onSecondary: p.card,
    error: Color(p.dark ? 0xffffb4a7 : 0xffad3b30),
    onError: p.card,
    surface: p.surface,
    onSurface: p.ink,
    onSurfaceVariant: p.secondary,
    outline: p.outline,
    outlineVariant: p.outline,
    surfaceContainer: p.container,
    surfaceContainerLow: p.card,
    surfaceTint: Colors.transparent,
  );
  TextStyle style(double size, {bool bold = false, Color? color}) => TextStyle(
    fontSize: size,
    letterSpacing: 0,
    height: 1.2,
    fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
    color: color ?? p.ink,
  );
  final text = TextTheme(
    bodySmall: style(12, color: p.secondary),
    bodyMedium: style(14),
    bodyLarge: style(15),
    titleSmall: style(13, bold: true),
    titleMedium: style(15, bold: true),
    titleLarge: style(18, bold: true),
    headlineSmall: style(26)
        .copyWith(fontWeight: FontWeight.w500, letterSpacing: -.52),
    headlineMedium: style(28, bold: true),
    labelLarge: style(15),
  );
  final button = ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    ),
    shape: const WidgetStatePropertyAll(StadiumBorder()),
    textStyle: const WidgetStatePropertyAll(
      TextStyle(fontSize: 15, height: 1.2),
    ),
    elevation: const WidgetStatePropertyAll(0),
  );
  OutlineInputBorder border(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: color),
  );
  return ThemeData(
    useMaterial3: false,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.surface,
    canvasColor: p.surface,
    fontFamily: 'Roboto',
    textTheme: text,
    extensions: [p],
    appBarTheme: AppBarTheme(
      backgroundColor: p.surface,
      foregroundColor: p.ink,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: p.surface,
        statusBarIconBrightness: p.dark ? Brightness.light : Brightness.dark,
        systemNavigationBarColor: p.surface,
        systemNavigationBarDividerColor: p.surface,
        systemNavigationBarIconBrightness: p.dark
            ? Brightness.light
            : Brightness.dark,
      ),
    ),
    cardTheme: CardThemeData(
      color: p.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    dividerColor: p.outline,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      border: border(p.outline),
      enabledBorder: border(p.outline),
      focusedBorder: border(p.primary),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: button.copyWith(
        backgroundColor: WidgetStatePropertyAll(p.action),
        foregroundColor: WidgetStatePropertyAll(p.onAction),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: button.copyWith(
        backgroundColor: WidgetStatePropertyAll(p.action),
        foregroundColor: WidgetStatePropertyAll(p.onAction),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: button.copyWith(
        backgroundColor: WidgetStatePropertyAll(p.container),
        foregroundColor: WidgetStatePropertyAll(p.ink),
        side: const WidgetStatePropertyAll(BorderSide.none),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: button.copyWith(
        foregroundColor: WidgetStatePropertyAll(p.secondary),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: p.ink,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.card,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      constraints: const BoxConstraints.tightFor(width: 520),
      barrierColor: Colors.black.withValues(alpha: p.dark ? .42 : .28),
      titleTextStyle: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: p.ink,
      ),
      contentTextStyle: TextStyle(
        fontSize: 14,
        color: p.secondary,
        height: 1.2,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: p.primary,
      inactiveTrackColor: p.outline,
      thumbColor: p.primary,
      trackHeight: 3,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
    ),
  );
}

class CapsuleSwitch extends StatelessWidget {
  const CapsuleSwitch({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelected,
    this.enabled = true,
  });
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelected;
  final bool enabled;
  @override
  Widget build(BuildContext context) {
    final p = HuePalette.of(context);
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: p.container,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: Opacity(
                opacity: enabled ? 1 : .68,
                child: Semantics(
                  enabled: enabled,
                  selected: i == selected,
                  button: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: enabled ? () => onSelected(i) : null,
                    child: Center(
                      child: Container(
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: i == selected
                              ? p.home && p.dark
                                    ? const Color(0xff4b4640)
                                    : p.card
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          labels[i],
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.2,
                            fontWeight: i == selected
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: i == selected ? p.ink : p.secondary,
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
    );
  }
}

class HueHeader extends StatelessWidget implements PreferredSizeWidget {
  const HueHeader({
    super.key,
    required this.title,
    this.actions = const [],
    this.back = false,
    this.leading,
    this.navigation,
    this.endPadding = 16,
    this.compact = false,
  });
  final String title;
  final List<Widget> actions;
  final bool back, compact;
  final Widget? leading;
  final Widget? navigation;
  final double endPadding;
  @override
  Size get preferredSize => Size.fromHeight(
    compact
        ? 48
        : back
        ? 60
        : 64,
  );
  @override
  Widget build(BuildContext context) {
    final p = HuePalette.of(context);
    return ColoredBox(
      color: p.surface,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: preferredSize.height,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              back || navigation != null ? 8 : 20,
              compact ? 0 : 8,
              endPadding,
              compact ? 0 : 4,
            ),
            child: Row(
              children: [
                ?navigation,
                if (navigation != null) const SizedBox(width: 8),
                if (back)
                  HueIconButton(
                    kind: HueIconKind.back,
                    label: '返回',
                    onPressed: () => Navigator.maybePop(context),
                    disc: false,
                  ),
                Expanded(
                  child:
                      leading ??
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: back || compact || navigation != null
                              ? 18
                              : 26,
                          height: 1.17,
                          letterSpacing: back || compact ? -.36 : -.52,
                          fontWeight: FontWeight.w500,
                          color: p.ink,
                        ),
                      ),
                ),
                ...actions,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HueIconButton extends StatelessWidget {
  const HueIconButton({
    super.key,
    required this.kind,
    required this.label,
    required this.onPressed,
    this.filled = false,
    this.disc = true,
    this.iconSize,
  });
  final HueIconKind kind;
  final String label;
  final VoidCallback? onPressed;
  final bool filled, disc;
  final double? iconSize;
  @override
  Widget build(BuildContext context) {
    final p = HuePalette.of(context);
    return Semantics(
      button: true,
      label: label,
      enabled: onPressed != null,
      child: Tooltip(
        message: label,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: Material(
              color: disc
                  ? filled
                        ? p.primaryContainer
                        : p.card
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: onPressed,
                child: SizedBox(
                  width: disc ? 36 : 48,
                  height: disc ? 36 : 48,
                  child: Center(
                    child: HueIcon(
                      kind,
                      size: iconSize ?? (disc ? 18 : 24),
                      color: filled ? p.onPrimaryContainer : p.ink,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class HueGlass extends StatelessWidget {
  const HueGlass({super.key, required this.child, this.radius = 40});
  final Widget child;
  final double radius;
  @override
  Widget build(BuildContext context) {
    final p = HuePalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: const Color(0xff302b23)
                .withValues(alpha: p.dark ? 0.3 : 0.06),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          enabled: !MediaQuery.disableAnimationsOf(context),
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: p.glass,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: Color(p.dark ? 0x35ffffff : 0x18302b23),
                width: .5,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

double hueNavigationInset(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= 600
    ? 0
    : 79 +
          (MediaQuery.textScalerOf(context).scale(1) - 1.2).clamp(
                0,
                double.infinity,
              ) *
              24;
