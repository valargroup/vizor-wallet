import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:desktop_window_bootstrap/desktop_window_bootstrap.dart';

import 'app.dart';
import 'src/core/layout/app_layout.dart';
import 'src/rust/frb_generated.dart';

void log(String message) => debugPrint('[zcash] $message');

Future<void> main() async {
  log('main: starting');
  WidgetsFlutterBinding.ensureInitialized();
  log('main: initializing RustLib');
  await RustLib.init();
  // Order matters: window_manager creates and shows the NSWindow inside
  // `initializeDesktopWindow`; the acrylic setup is only effective once
  // that window exists.
  log('main: initializing desktop window (no-op on mobile/web)');
  await initializeDesktopWindow();
  if (isDesktopLayoutPlatform) {
    log('main: initializing desktop window visuals');
    await DesktopWindowBootstrap.initialize();
    await showDesktopWindow();
  }
  log('main: launching app');
  runApp(const ProviderScope(child: ZcashWalletApp()));
}
