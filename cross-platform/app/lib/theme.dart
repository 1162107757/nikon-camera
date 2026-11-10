import 'package:flutter/material.dart';

ThemeData hueviaTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final surface = Color(dark ? 0xff201f1d : 0xfff8f7f4);
  final ink = Color(dark ? 0xfff6f1eb : 0xff242320);
  final secondary = Color(dark ? 0xffcac2b8 : 0xff635d53);
  final primary = Color(dark ? 0xfff3b493 : 0xffb3432d);
  final scheme =
      ColorScheme.fromSeed(seedColor: primary, brightness: brightness).copyWith(
        surface: surface,
        onSurface: ink,
        onSurfaceVariant: secondary,
        primary: primary,
        onPrimary: Color(dark ? 0xff492316 : 0xffffffff),
        primaryContainer: Color(dark ? 0xff633b2a : 0xfff4d6c0),
        onPrimaryContainer: Color(dark ? 0xffffdbc7 : 0xff85311f),
        surfaceContainer: Color(dark ? 0xff34312d : 0xffeeece6),
        surfaceContainerLow: Color(dark ? 0xff292724 : 0xffffffff),
        outlineVariant: Color(dark ? 0xff4c4640 : 0xffe4dfd8),
        error: Color(dark ? 0xffffb4a7 : 0xffad3b30),
      );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: surface,
    appBarTheme: AppBarTheme(
      backgroundColor: surface,
      foregroundColor: ink,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      elevation: 0,
      indicatorColor: scheme.surfaceContainer,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    textTheme: Typography.material2021(platform: TargetPlatform.android).black
        .apply(bodyColor: ink, displayColor: ink),
  );
}

class CapsuleSwitch extends StatelessWidget {
  const CapsuleSwitch({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelected,
  });
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelected;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: const StadiumBorder(),
        color: colors.surfaceContainer,
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
          children: [
            for (var i = 0; i < labels.length; i++)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: i == labels.length - 1 ? 0 : 3,
                  ),
                  child: Material(
                    color: i == selected
                        ? colors.surfaceContainerLow
                        : Colors.transparent,
                    shape: const StadiumBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      customBorder: const StadiumBorder(),
                      onTap: () => onSelected(i),
                      child: Semantics(
                        selected: i == selected,
                        button: true,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 48),
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 10,
                                horizontal: 8,
                              ),
                              child: Text(
                                labels[i],
                                style: TextStyle(
                                  fontWeight: i == selected
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
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
    );
  }
}
