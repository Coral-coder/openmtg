import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:rules/rules.dart';

import '../app/store.dart';
import '../app/updater.dart';
import '../net/relay.dart';
import '../theme/theme.dart';

const fanContentNotice =
    'OpenMTG is unofficial Fan Content permitted under the Fan Content Policy. Not approved or endorsed by Wizards of the Coast. Portions of the materials used are property of Wizards of the Coast. ©Wizards of the Coast LLC. Card data and images courtesy of Scryfall. Free, with no ads and nothing to buy.';

class MainMenuScreen extends StatelessWidget {
  const MainMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppStore.shared;
    final t = GameTheme.of(context);
    final saved = store.savedGame;
    return ThemedScreen(
      title: 'OpenMTG',
      subtitle: 'Every card. The full rules. A theme for every world.',
      backdrop: true,
      actions: [IconButton(icon: Icon(Icons.settings, color: t.chrome == ChromeStyle.lcars ? t.accent : t.accent), tooltip: 'Settings', onPressed: () => Navigator.pushNamed(context, '/settings'))],
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(children: [
            if (saved != null) ...[
              ThemedButton('Resume game', subtitle: 'Turn ${saved['turn'] ?? '?'} · ${(saved['names'] as List).join(' vs ')}', tall: true, icon: Icons.play_circle, color: t.highlight, onPressed: () {
                if (store.resumeLocalGame() != null) Navigator.pushNamed(context, '/game');
              }),
              const SizedBox(height: 10),
            ],
            ThemedButton('Play the computer', tall: true, icon: Icons.smart_toy, onPressed: () => Navigator.pushNamed(context, '/new', arguments: false)),
            const SizedBox(height: 10),
            ThemedButton('Play online with a code', subtitle: 'Browser or phone, anywhere', tall: true, icon: Icons.public, color: t.accent2, onPressed: () => Navigator.pushNamed(context, '/remote')),
            const SizedBox(height: 10),
            if (!kIsWeb) ...[
              ThemedButton('Play nearby', subtitle: 'Wi‑Fi or Bluetooth', tall: true, icon: Icons.wifi_tethering, color: t.accent2, onPressed: () => Navigator.pushNamed(context, '/local')),
              const SizedBox(height: 10),
            ],
            ThemedButton('Two players, one device', tall: true, icon: Icons.people, outlined: true, onPressed: () => Navigator.pushNamed(context, '/new', arguments: true)),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: ThemedButton('Decks', icon: Icons.style, outlined: true, onPressed: () => Navigator.pushNamed(context, '/decks'))),
              const SizedBox(width: 10),
              Expanded(child: ThemedButton('Cards', icon: Icons.collections, outlined: true, onPressed: () => Navigator.pushNamed(context, '/cards'))),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: ThemedButton('How to play', icon: Icons.school, outlined: true, onPressed: () => Navigator.pushNamed(context, '/help'))),
              const SizedBox(width: 10),
              Expanded(child: ThemedButton('Settings', icon: Icons.tune, outlined: true, onPressed: () => Navigator.pushNamed(context, '/settings'))),
            ]),
            const SizedBox(height: 18),
            ThemedPanel(
              child: Text(
                '${store.db.length} cards loaded · ${store.data.coverage['supported'] ?? '?'} of ${store.data.coverage['total'] ?? '?'} cards fully supported so far',
                style: t.small,
              ),
            ),
            const SizedBox(height: 10),
            Text(fanContentNotice, style: t.style(11, weight: FontWeight.w400, color: t.muted)),
          ]),
        ),
      ),
    );
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppStore.shared;
    final t = GameTheme.of(context);
    Widget toggle(String key, String title, String sub, bool v) => SwitchListTile(value: v, onChanged: (x) => store.setBool(key, x), title: Text(title, style: t.body), subtitle: Text(sub, style: t.small));
    final r = store.rules;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => ThemedScreen(
        title: 'Settings',
        child: ListView(children: [
          const ThemedHeader('You'),
          TextFormField(
            initialValue: store.playerName,
            style: t.body,
            decoration: InputDecoration(labelText: 'Your name', filled: true, fillColor: t.panel),
            onFieldSubmitted: store.setPlayerName,
            onChanged: store.setPlayerName,
          ),
          const ThemedHeader('Theme'),
          Text('A theme follows your deck\'s main set; pick one here to always use it.', style: t.small),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ChoiceChip(label: const Text('From the deck'), selected: store.themeOverride == null, onSelected: (_) => store.setThemeOverride(null)),
            for (final th in Themes.all) ChoiceChip(label: Text(th.name), selected: store.themeOverride == th.id, onSelected: (_) => store.setThemeOverride(th.id)),
          ]),
          const ThemedHeader('Table'),
          toggle('tapToInspect', 'Tap a card to see it', 'Opens the card large with what it can do. Off: a tap plays it when there is only one thing to do.', store.tapToInspect),
          toggle('landsAsCards', 'Lands as cards', 'Off: lands are grouped into labels like "Forest 3/4".', store.landsAsCards),
          toggle('autoPay', 'Pay mana automatically', 'Off: choose which lands to tap.', store.autoPay),
          toggle('coachOn', 'Coach hints', 'A line on the table saying what you can do now.', store.coachOn),
          toggle('soundOn', 'Sounds', "Short sounds in the theme's style.", store.soundOn),
          toggle('hapticsOn', 'Vibration', 'On phones.', store.hapticsOn),
          ListTile(
            title: Text('Computer speed', style: t.body),
            subtitle: Slider(value: (1200 - store.botDelay).toDouble().clamp(0, 1100), min: 0, max: 1100, divisions: 11, onChanged: (v) => store.setBotDelay(1200 - v.round())),
          ),
          ListTile(title: Text('Show the table tour again', style: t.body), trailing: const Icon(Icons.replay), onTap: () => store.setBool('tourSeen', false)),
          const ThemedHeader('Rules'),
          Text('These travel with the game: a match uses the host\'s rules.', style: t.small),
          ListTile(
            title: Text('Starting life', style: t.body),
            trailing: DropdownButton<int>(value: r.startingLife, items: [for (final v in const [20, 25, 30, 40]) DropdownMenuItem(value: v, child: Text('$v'))], onChanged: (v) => store.setRules(r.copyWith(startingLife: v))),
          ),
          ListTile(
            title: Text('Opening hand', style: t.body),
            trailing: DropdownButton<int>(value: r.handSize, items: [for (final v in const [5, 6, 7, 8]) DropdownMenuItem(value: v, child: Text('$v cards'))], onChanged: (v) => store.setRules(r.copyWith(handSize: v))),
          ),
          SwitchListTile(value: r.londonMulligan, onChanged: (v) => store.setRules(r.copyWith(londonMulligan: v)), title: Text('London mulligan', style: t.body), subtitle: Text('Off: classic (draw one fewer each time).', style: t.small)),
          SwitchListTile(value: r.freeMulligan, onChanged: (v) => store.setRules(r.copyWith(freeMulligan: v)), title: Text('First mulligan free', style: t.body)),
          SwitchListTile(value: r.firstPlayerDraws, onChanged: (v) => store.setRules(r.copyWith(firstPlayerDraws: v)), title: Text('First player draws on turn one', style: t.body)),
          SwitchListTile(value: r.maxHandSize, onChanged: (v) => store.setRules(r.copyWith(maxHandSize: v)), title: Text('Maximum hand size', style: t.body)),
          if (!r.isStandard) TextButton(onPressed: () => store.setRules(RulesOptions.standard), child: const Text('Back to the standard rules')),
          if (Updater.shared.supported) ...[
            const ThemedHeader('Updates'),
            SwitchListTile(value: Updater.shared.autoDownload, onChanged: (v) => Updater.shared.setAutoDownload(v).then((_) => store.refresh()), title: Text('Download updates automatically', style: t.body)),
          ],
          const ThemedHeader('Online'),
          Text('Public Nostr relays carry online matches (encrypted with the match code).', style: t.small),
          for (final relay in store.relays) ListTile(dense: true, title: Text(relay, style: t.small)),
          TextButton(onPressed: () => store.setRelays(defaultRelays), child: const Text('Use the default relays')),
          const ThemedHeader('Card data'),
          ListenableBuilder(
            listenable: store.data,
            builder: (context, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(store.data.hasFull ? 'Full database: ${store.db.length} cards (${store.db.version}).' : 'Bundled: ${store.data.pool.length} cards. Download the full database to browse every card.', style: t.small),
              const SizedBox(height: 6),
              ThemedButton(store.data.downloading ? 'Downloading…' : (store.data.hasFull ? 'Refresh the card database' : 'Download every card'), outlined: true, onPressed: store.data.downloading ? null : store.data.downloadFull),
              if (store.data.error != null) Text(store.data.error!, style: t.style(12, color: t.danger)),
            ]),
          ),
          const SizedBox(height: 20),
          Text(fanContentNotice, style: t.style(11, weight: FontWeight.w400, color: t.muted)),
        ]),
      ),
    );
  }
}

class HowToPlayScreen extends StatelessWidget {
  const HowToPlayScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    Widget section(String title, String body) => Padding(padding: const EdgeInsets.only(bottom: 12), child: ThemedPanel(title: title, child: Text(body, style: t.body)));
    return ThemedScreen(
      title: 'How to play',
      child: ListView(children: [
        section('The goal', 'Bring your opponent from 20 life to 0. Each turn you draw a card, may play one land, cast spells with the mana your lands make, and attack with your creatures.'),
        section('Your turn', 'Untap, upkeep, draw. In your main phase play a land and cast creatures and sorceries. In combat choose attackers; your opponent chooses blockers. After combat there is a second main phase, then the end step.'),
        section('Mana', 'Tap lands for mana. A spell shows its cost in its top right corner: colored symbols need that color, numbers can be paid with any mana. The table pays for you (Settings can let you choose).'),
        section('Priority and the stack', 'When a spell is cast, the other player may respond with instants before it resolves. The table stops when you can respond and passes for you when you can\'t.'),
        section('Combat', 'Attackers tap (unless they have vigilance). Each blocker blocks one attacker. Damage happens at once: creatures with damage equal to their toughness die. Flying can only be blocked by flying or reach; trample spills extra damage onto the player.'),
        section('Reading a card', 'Tap any card to see it large, what it can do right now, and why something is not possible. Cards the engine does not fully support yet say so, with the exact text it can\'t handle.'),
      ]),
    );
  }
}
