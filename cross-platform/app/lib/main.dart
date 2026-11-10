import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'domain.dart';
import 'editor.dart';
import 'raw_develop.dart';
import 'library.dart';
import 'photos.dart';
import 'profile.dart';
import 'camera.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState(HueviaCore());
  runApp(HueviaApp(state: state));
  unawaited(state.initialize());
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
      ShellRoute(
        builder: (context, state, child) =>
            HomeFrame(location: state.uri.path, child: child),
        routes: [
          GoRoute(
            path: '/presets',
            builder: (_, _) => LibraryPage(state: widget.state),
          ),
          GoRoute(
            path: '/photos',
            builder: (_, _) => PhotosPage(state: widget.state),
          ),
          GoRoute(
            path: '/camera',
            builder: (_, _) => CameraPage(state: widget.state),
          ),
          GoRoute(
            path: '/account',
            builder: (_, _) => AccountPage(state: widget.state),
          ),
        ],
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
              ? RawDevelopPage(state: widget.state, photo: photo)
              : EditorPage(state: widget.state, photo: photo);
        },
      ),
    ],
  );
  @override
  void dispose() {
    router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.state,
    builder: (context, _) => MaterialApp.router(
      title: 'Huevia',
      debugShowCheckedModeBanner: false,
      theme: hueviaTheme(Brightness.light),
      darkTheme: hueviaTheme(Brightness.dark),
      routerConfig: router,
      builder: (context, child) {
        if (widget.state.ready) return child!;
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

class HomeFrame extends StatelessWidget {
  const HomeFrame({super.key, required this.location, required this.child});
  final String location;
  final Widget child;
  static const paths = ['/presets', '/photos', '/camera', '/account'];
  @override
  Widget build(BuildContext context) => Scaffold(
    body: child,
    bottomNavigationBar: NavigationBar(
      selectedIndex: paths.indexOf(location).clamp(0, 3),
      onDestinationSelected: (index) => context.go(paths[index]),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.tune_rounded), label: '预设'),
        NavigationDestination(
          icon: Icon(Icons.photo_library_outlined),
          label: '照片',
        ),
        NavigationDestination(
          icon: Icon(Icons.camera_alt_outlined),
          label: '相机',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline_rounded),
          label: '我的',
        ),
      ],
    ),
  );
}
