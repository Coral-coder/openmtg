// The OpenMTG app: title, menu, table, decks, card database and settings.
import 'package:flutter/material.dart';

import 'package:tcg_app/tcg_app.dart';
import 'app/store.dart';
import 'ui/database.dart';
import 'ui/decks.dart';
import 'ui/lobbies.dart';
import 'ui/menu.dart';
import 'ui/table.dart';
import 'ui/title.dart';


class OpenMtgApp extends StatefulWidget {
  const OpenMtgApp({super.key});
  @override
  State<OpenMtgApp> createState() => _OpenMtgAppState();
}

class _OpenMtgAppState extends State<OpenMtgApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppStore.shared.init().then((_) => Notifications.shared.requestPermission());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    AppStore.shared.session?.appInForeground = state == AppLifecycleState.resumed;
  }

  @override
  Widget build(BuildContext context) {
    final store = AppStore.shared;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final theme = store.theme;
        return ThemeScope(
          theme: theme,
          child: MaterialApp(
            title: 'OpenMTG',
            theme: theme.material(),
            debugShowCheckedModeBanner: false,
            builder: (context, child) => ThemeScope(theme: store.theme, child: child ?? const SizedBox()),
            home: store.ready ? const TitleScreen() : const _Loading(),
            onGenerateRoute: (settings) {
              final args = settings.arguments;
              final page = switch (settings.name) {
                '/new' => NewGameScreen(hotseat: args as bool),
                '/game' => const GameScreen(),
                '/remote' => const RemoteLobbyScreen(),
                '/local' => const LocalLobbyScreen(),
                '/decks' => const DeckListScreen(),
                '/deck' => DeckEditorScreen(deckId: args as String),
                '/cards' => const CardDatabaseScreen(),
                '/settings' => const SettingsScreen(),
                '/help' => const HowToPlayScreen(),
                _ => const MainMenuScreen(),
              };
              return MaterialPageRoute(builder: (_) => page, settings: settings);
            },
          ),
        );
      },
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    return Scaffold(
      backgroundColor: t.bg,
      body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Text('OpenMTG', style: t.title), const SizedBox(height: 16), SizedBox(width: 140, child: LinearProgressIndicator(color: t.accent))])),
    );
  }
}
