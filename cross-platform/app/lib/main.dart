import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';

import 'domain.dart';
import 'editor.dart';
import 'raw_develop.dart';
import 'library.dart';
import 'photos.dart';
import 'profile.dart';
import 'camera.dart';
import 'theme.dart';
import 'settings.dart';
import 'appearance.dart';
import 'community_activity.dart';
import 'app_stability.dart';
import 'album_batch.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  AppStability.install();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Roboto reference fonts',
    ], await rootBundle.loadString('assets/fonts/Roboto-APACHE-2.0.txt'));
  });
  unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
  PaintingBinding.instance.imageCache.maximumSizeBytes = 32 << 20;
  final state = AppState(HueviaCore());
  runApp(HueviaApp(state: state));
  unawaited(state.initialize().then((_) => readAppearance(state.core.root)));
}

class HueviaApp extends StatefulWidget {
  const HueviaApp({super.key, required this.state});
  final AppState state;
  @override
  State<HueviaApp> createState() => _HueviaAppState();
}

class _HueviaAppState extends State<HueviaApp> {
  late final GoRouter router = GoRouter(
    initialLocation: '/presets',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigation) => HomeFrame(
          location: state.uri.path,
          navigation: navigation,
          child: navigation,
        ),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/presets',
                builder: (_, _) => LibraryPage(state: widget.state),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/camera',
                builder: (_, _) => CameraPage(state: widget.state),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/photos',
                builder: (_, _) => PhotosPage(state: widget.state),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (_, _) => SettingsPage(state: widget.state),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/account',
        builder: (_, _) => AccountPage(state: widget.state),
      ),
      GoRoute(
        path: '/photo/:id',
        builder: (_, route) {
          final candidates = widget.state.photos.where(
            (photo) => photo.id == route.pathParameters['id'],
          );
          final photo = candidates.length == 1 ? candidates.first : null;
          return photo == null
              ? const Scaffold(body: Center(child: Text('照片已不可用，请返回相册重新选择。')))
              : photo.info['raw'] == true
              ? RawDevelopPage(
                  key: ValueKey('raw-${photo.id}'),
                  state: widget.state,
                  photo: photo,
                  automaticallyEdit: true,
                )
              : EditorPage(
                  key: ValueKey('edit-${photo.id}'),
                  state: widget.state,
                  photo: photo,
                );
        },
      ),
    ],
  );
  void routeChanged() {
    widget.state.cameraVisible.value =
        router.routeInformationProvider.value.uri.path == '/camera';
  }

  @override
  void initState() {
    super.initState();
    router.routerDelegate.addListener(routeChanged);
    routeChanged();
  }

  @override
  void dispose() {
    router.routerDelegate.removeListener(routeChanged);
    router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.state, appearanceMode]),
    builder: (context, _) => MaterialApp.router(
      title: 'Huevia',
      debugShowCheckedModeBanner: false,
      theme: hueviaTheme(Brightness.light),
      darkTheme: hueviaTheme(Brightness.dark),
      themeMode: appearanceMode.value,
      routerConfig: router,
      builder: (context, child) {
        if (widget.state.ready) {
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: Theme.of(context).appBarTheme.systemOverlayStyle!,
            child: CommunityActivity(state: widget.state, child: child!),
          );
        }
        return Scaffold(
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Huevia',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (widget.state.failure == null) ...[
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        const Text('正在打开照片与预设库'),
                      ] else ...[
                        Text(widget.state.failure!),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: widget.state.initialize,
                          child: const Text('重新打开'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

class HomeFrame extends StatefulWidget {
  const HomeFrame({
    super.key,
    required this.location,
    required this.child,
    this.navigation,
  });
  final String location;
  final Widget child;
  final StatefulNavigationShell? navigation;
  static const paths = ['/presets', '/camera', '/photos', '/settings'];
  @override
  State<HomeFrame> createState() => _HomeFrameState();
}

class _HomeFrameState extends State<HomeFrame> {
  bool albumSelecting = false;
  String get location => widget.location;
  Widget get child => widget.child;
  StatefulNavigationShell? get navigation => widget.navigation;
  static const paths = HomeFrame.paths;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: NotificationListener<AlbumSelectionChanged>(
      onNotification: (notification) {
        if (albumSelecting != notification.active) {
          setState(() => albumSelecting = notification.active);
        }
        return true;
      },
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, bounds) {
            final rail = bounds.maxWidth >= 600;
            final scale = MediaQuery.textScalerOf(context).scale(1);
            final p = HuePalette.of(context);
            final density = MediaQuery.devicePixelRatioOf(context);
            double snap(double value) => (value * density).round() / density;
            final height = snap(
              65.0 + ((scale - 1.2).clamp(0, double.infinity) * 24).round(),
            );
            final width = snap((bounds.maxWidth - 48).clamp(0.0, 360.0));
            final innerPixels = ((width - 2 * snap(4)) * density).round();
            final navigation = Padding(
              padding: EdgeInsets.symmetric(
                horizontal: rail ? 8 : snap(4),
                vertical: rail ? 6 : snap(4),
              ),
              child: Flex(
                direction: rail ? Axis.vertical : Axis.horizontal,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < paths.length; i++)
                    if (rail)
                      _destination(context, i, true)
                    else
                      SizedBox(
                        width:
                            ((innerPixels * (i + 1) / 4).floor() -
                                (innerPixels * i / 4).floor()) /
                            density,
                        child: _destination(context, i, false),
                      ),
                ],
              ),
            );
            return Stack(
              children: [
                Positioned.fill(
                  left: rail && !(albumSelecting && location == '/photos')
                      ? 80
                      : 0,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: child,
                    ),
                  ),
                ),
                if (rail && !(albumSelecting && location == '/photos'))
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: 80,
                    child: ColoredBox(color: p.glass, child: navigation),
                  )
                else if (!rail && !(albumSelecting && location == '/photos'))
                  Positioned(
                    left:
                        ((bounds.maxWidth - width) * density / 2).floor() /
                        density,
                    bottom: snap(14),
                    child: SizedBox(
                      width: width,
                      height: height,
                      child: HueGlass(child: navigation),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    ),
  );

  Widget _destination(BuildContext context, int index, bool rail) {
    final selected = paths.indexOf(location) == index;
    final p = HuePalette.of(context);
    final label = ['预设', '同步', '相册', '设置'][index];
    void select() {
      if (navigation != null) {
        navigation!.goBranch(index);
      } else {
        context.go(paths[index]);
      }
    }

    final item = Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      onTap: select,
      child: Material(
        color: selected && !rail ? p.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(40),
        child: InkWell(
          borderRadius: BorderRadius.circular(40),
          onTap: select,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 54,
                  height: 26,
                  decoration: rail && selected
                      ? BoxDecoration(
                          color: p.primaryContainer,
                          borderRadius: BorderRadius.circular(16),
                        )
                      : null,
                  child: Center(
                    child: SizedBox(
                      width: 26,
                      height: 26,
                      child: Stack(
                        alignment: Alignment.center,
                        clipBehavior: Clip.none,
                        children: [
                          HueIcon(
                            [
                              HueIconKind.presets,
                              HueIconKind.camera,
                              HueIconKind.album,
                              HueIconKind.settings,
                            ][index],
                            size: 23,
                            color: selected
                                ? p.onPrimaryContainer
                                : p.secondary,
                          ),
                          if (index == 3 &&
                              CommunityActivity.unreadOf(context) > 0)
                            Positioned(
                              top: 0,
                              right: 0,
                              child: ExcludeSemantics(
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.error,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.2,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                    color: selected
                        ? (rail ? p.ink : p.onPrimaryContainer)
                        : p.secondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return rail ? SizedBox(height: 72, child: item) : item;
  }
}
