// Widget tests: the menu, a game against the computer, and phone-size screenshots of the main
// screens (written to build/screenshots/ for a look at the layout; any overflow fails the test).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmtg/app/sound.dart';
import 'package:openmtg/app/store.dart';
import 'package:openmtg/main.dart';
import 'package:openmtg/theme/theme.dart';
import 'package:rules/rules.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _shot = GlobalKey();

Future<void> _boot(WidgetTester tester, {Size size = const Size(390, 844)}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  Console.available = false;
  SharedPreferences.setMockInitialValues({'tourSeen': true, 'botDelay': 50});
  await tester.runAsync(() => AppStore.shared.init());
  await tester.pumpWidget(RepaintBoundary(key: _shot, child: const OpenMtgApp()));
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _save(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary = _shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('build/screenshots')..createSync(recursive: true);
    File('${dir.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  testWidgets('the menu shows the ways to play and the fan content notice', (tester) async {
    await _boot(tester);
    expect(find.text('Play the computer'), findsOneWidget);
    expect(find.text('Play online with a code'), findsOneWidget);
    expect(find.textContaining('unofficial Fan Content'), findsOneWidget);
    await _save(tester, 'menu');
  });

  testWidgets('a game against the computer: mulligan choice, then the table', (tester) async {
    await _boot(tester);
    await tester.tap(find.text('Play the computer'));
    await tester.pumpAndSettle();
    await _save(tester, 'new-game');
    await tester.tap(find.text('Start the game'));
    await tester.pump(const Duration(milliseconds: 300));
    final s = AppStore.shared.session!;
    expect(s.state.started, isTrue);
    // Play through mulligans: we keep whenever it's our decision.
    for (var i = 0; i < 40 && !s.state.inProgress; i++) {
      if (s.state.pending?.decision.player == s.localSeat) {
        if (find.text('Keep').evaluate().isNotEmpty) {
          await tester.tap(find.text('Keep'));
        } else {
          s.perform(AnswerAction(s.localSeat, s.game.defaultAnswer(s.state.pending!.decision)));
        }
      }
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(s.state.inProgress, isTrue);
    // Let the computer act until it's our turn to decide something.
    for (var i = 0; i < 200 && s.toAct != s.localSeat && !s.state.over; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    await tester.pump(const Duration(milliseconds: 200));
    await _save(tester, 'table');
    expect(find.byType(ThemedButton), findsWidgets);
    AppStore.shared.endSession();
  });

  testWidgets('every theme lays out the menu and settings at phone size', (tester) async {
    await _boot(tester);
    for (final t in Themes.all) {
      await AppStore.shared.setThemeOverride(t.id);
      await tester.pump(const Duration(milliseconds: 50));
      await _save(tester, 'menu-${t.id}');
    }
    await tester.tap(find.byTooltip('Settings').first);
    await tester.pumpAndSettle();
    await _save(tester, 'settings');
    await AppStore.shared.setThemeOverride(null);
  });

  testWidgets('short landscape screen', (tester) async {
    await _boot(tester, size: const Size(844, 390));
    await _save(tester, 'menu-landscape');
    expect(find.text('Play the computer'), findsOneWidget);
  });
}
