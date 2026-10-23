import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:rules/rules.dart';

import '../app/session.dart';
import '../app/store.dart';
import '../theme/theme.dart';
import 'card_detail.dart';
import 'decisions.dart';
import 'fx.dart';
import 'table_controller.dart';
import 'table_widgets.dart';
import 'tour.dart';

/// The game table. Phones in portrait get the opponent on top, you at the bottom and your hand
/// below; wide screens (landscape, browsers) add a side column with the stack and the log.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key});
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  TableController? _ctl;
  GameSession? _session;
  final _keys = TourKeys();
  bool _dialogOpen = false;

  TableController _controller(GameSession s) {
    if (_ctl == null || _session != s) {
      _ctl?.dispose();
      _session = s;
      _ctl = TableController(s);
    }
    return _ctl!;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final store = AppStore.shared;
      if (!store.tourSeen && mounted) showTableTour(context, _keys);
    });
  }

  @override
  void dispose() {
    _ctl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = AppStore.shared;
    final s = store.session;
    if (s == null) return const Scaffold(body: Center(child: Text('No game')));
    final ctl = _controller(s);
    return ListenableBuilder(
      listenable: Listenable.merge([s, ctl, store]),
      builder: (context, _) {
        ctl.sync();
        _maybeOpenDialog(context, ctl);
        final t = GameTheme.of(context);
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            final leave = await _confirmLeave(context, s);
            if (leave && context.mounted) Navigator.of(context).pop();
          },
          child: Scaffold(
            backgroundColor: t.bg,
            body: Stack(children: [
              Positioned.fill(child: TableBackdrop(theme: t)),
              Positioned.fill(
                child: TableFx(
                  ctl: ctl,
                  child: SafeArea(
                    child: LayoutBuilder(builder: (context, box) {
                      final wide = box.maxWidth >= 860 && box.maxWidth > box.maxHeight * 1.05;
                      return wide ? _wide(context, ctl, box) : _narrow(context, ctl, box);
                    }),
                  ),
                ),
              ),
              if (s.state.over) _GameOver(session: s),
            ]),
          ),
        );
      },
    );
  }

  // -------------------------------------------------------------------------------------------
  // Layouts
  // -------------------------------------------------------------------------------------------

  Widget _narrow(BuildContext context, TableController ctl, BoxConstraints box) {
    final me = ctl.me;
    final opp = ctl.session.opponentSeat;
    final short = box.maxHeight < 640;
    return Column(children: [
      _topBar(context, ctl),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: RectProbe(onRect: (fx, r) => fx.bars[opp] = r, child: PlayerBar(ctl: ctl, player: opp, compact: short, onZone: (z) => _zone(context, ctl, opp, z)))),
      Expanded(flex: 5, child: _Battlefield(ctl: ctl, player: opp, mirrored: true, onCard: (id) => _cardTapped(context, ctl, id))),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), child: StackStrip(ctl: ctl, onCard: (id) => _detail(context, ctl, id))),
      Padding(key: _keys.steps, padding: const EdgeInsets.symmetric(horizontal: 6), child: StepStrip(state: ctl.state, me: me)),
      Expanded(flex: 5, child: _Battlefield(key: _keys.battlefield, ctl: ctl, player: me, onCard: (id) => _cardTapped(context, ctl, id))),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: RectProbe(onRect: (fx, r) => fx.bars[me] = r, child: PlayerBar(key: _keys.life, ctl: ctl, player: me, compact: short, onZone: (z) => _zone(context, ctl, me, z)))),
      _Hand(key: _keys.hand, ctl: ctl, height: short ? 112 : (box.maxHeight * 0.2).clamp(112, 190), onCard: (id) => _cardTapped(context, ctl, id)),
      _PromptBar(key: _keys.prompt, ctl: ctl, onOpenChoice: () => _openChoice(context, ctl)),
    ]);
  }

  Widget _wide(BuildContext context, TableController ctl, BoxConstraints box) {
    final me = ctl.me;
    final opp = ctl.session.opponentSeat;
    return Column(children: [
      _topBar(context, ctl),
      Expanded(
        child: Row(children: [
          Expanded(
            child: Column(children: [
              Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: RectProbe(onRect: (fx, r) => fx.bars[opp] = r, child: PlayerBar(ctl: ctl, player: opp, onZone: (z) => _zone(context, ctl, opp, z)))),
              Expanded(child: _Battlefield(ctl: ctl, player: opp, mirrored: true, onCard: (id) => _cardTapped(context, ctl, id))),
              Padding(key: _keys.steps, padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), child: StepStrip(state: ctl.state, me: me)),
              Expanded(child: _Battlefield(key: _keys.battlefield, ctl: ctl, player: me, onCard: (id) => _cardTapped(context, ctl, id))),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: RectProbe(onRect: (fx, r) => fx.bars[me] = r, child: PlayerBar(key: _keys.life, ctl: ctl, player: me, onZone: (z) => _zone(context, ctl, me, z)))),
              _Hand(key: _keys.hand, ctl: ctl, height: (box.maxHeight * 0.24).clamp(130, 230), onCard: (id) => _cardTapped(context, ctl, id)),
            ]),
          ),
          SizedBox(
            width: 300,
            child: Column(children: [
              Padding(padding: const EdgeInsets.all(6), child: StackStrip(ctl: ctl, onCard: (id) => _detail(context, ctl, id))),
              Expanded(child: _LogView(state: ctl.state)),
            ]),
          ),
        ]),
      ),
      _PromptBar(key: _keys.prompt, ctl: ctl, onOpenChoice: () => _openChoice(context, ctl)),
    ]);
  }

  Widget _topBar(BuildContext context, TableController ctl) {
    final t = GameTheme.of(context);
    final s = ctl.session;
    return SizedBox(
      height: 40,
      child: Row(children: [
        IconButton(icon: Icon(Icons.close, color: t.accent), tooltip: 'Leave the table', onPressed: () => Navigator.of(context).maybePop()),
        Expanded(
          child: Text(
            s.isLinked ? s.match?.status ?? '' : (s.thinking ? '${s.playerNames[s.opponentSeat]} is thinking…' : t.label(t.name)),
            style: t.style(12, color: t.muted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        IconButton(icon: Icon(Icons.receipt_long, color: t.accent), tooltip: 'Game log', onPressed: () => _showLog(context, ctl)),
        IconButton(icon: Icon(Icons.help_outline, color: t.accent), tooltip: 'Tour of the table', onPressed: () => showTableTour(context, _keys)),
        PopupMenuButton<String>(
          icon: Icon(Icons.more_vert, color: t.accent),
          onSelected: (v) {
            if (v == 'concede') s.concede();
            if (v == 'passTurn') ctl.perform(PassTurnAction(ctl.me));
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'passTurn', child: Text('Pass until my next decision this turn')),
            PopupMenuItem(value: 'concede', child: Text('Concede')),
          ],
        ),
      ]),
    );
  }

  // -------------------------------------------------------------------------------------------
  // Interactions
  // -------------------------------------------------------------------------------------------

  void _cardTapped(BuildContext context, TableController ctl, int id) {
    if (ctl.tap(id)) return;
    final store = AppStore.shared;
    if (!store.tapToInspect) {
      // Quick play: the first legal action for this card.
      final acts = cardActions(ctl, id);
      final legal = acts.where((a) => a.reason == null).toList();
      if (legal.length == 1) {
        ctl.perform(legal.first.action);
        return;
      }
    }
    _detail(context, ctl, id);
  }

  void _detail(BuildContext context, TableController ctl, int id) {
    showCardDetail(context, ctl: ctl, id: id);
  }

  void _zone(BuildContext context, TableController ctl, int player, Zone z) {
    final ids = z == Zone.graveyard ? ctl.state.player(player).graveyard : ctl.state.player(player).exile;
    showZone(context, ctl: ctl, title: '${ctl.state.player(player).name}: ${z == Zone.graveyard ? 'graveyard' : 'exile'}', ids: List.of(ids.reversed));
  }

  void _showLog(BuildContext context, TableController ctl) {
    showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => SizedBox(height: MediaQuery.of(context).size.height * 0.7, child: _LogView(state: ctl.state)));
  }

  /// Opens a dialog for decisions that aren't made by tapping the table.
  void _maybeOpenDialog(BuildContext context, TableController ctl) {
    final d = ctl.decision;
    if (d == null || _dialogOpen) return;
    if (!needsDialog(ctl, d)) {
      if (d.kind == DecisionKind.payMana && AppStore.shared.autoPay) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (ctl.decision?.digest() == d.digest()) ctl.answer(const []);
        });
      }
      if (d.kind == DecisionKind.damage) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (ctl.decision?.digest() == d.digest()) ctl.answer(const []);
        });
      }
      return;
    }
    _dialogOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!context.mounted) return;
      await openDecisionDialog(context, ctl, d);
      _dialogOpen = false;
      if (mounted) setState(() {});
    });
  }

  void _openChoice(BuildContext context, TableController ctl) {
    final d = ctl.decision;
    if (d == null) return;
    _dialogOpen = true;
    openDecisionDialog(context, ctl, d, force: true).then((_) {
      _dialogOpen = false;
      if (mounted) setState(() {});
    });
  }

  Future<bool> _confirmLeave(BuildContext context, GameSession s) async {
    if (s.state.over) {
      AppStore.shared.endSession();
      return true;
    }
    final r = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Leave the table?'),
        content: Text(s.isLinked ? 'The match stays on this device and on the relays; open it again to continue.' : 'The game is saved; you can resume it from the menu.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Stay')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Leave')),
        ],
      ),
    );
    return r ?? false;
  }
}

/// The actions a card offers the local player, with why each can't be done now.
class CardAction {
  CardAction(this.label, this.action, this.reason);
  final String label;
  final GameAction action;
  final String? reason;
}

List<CardAction> cardActions(TableController ctl, int id) {
  final g = ctl.game;
  final me = ctl.me;
  final o = g.state.objOrNull(id);
  if (o == null) return const [];
  final c = g.chars(id);
  final out = <CardAction>[];
  if ((o.zone == Zone.hand && o.owner == me) || o.playableBy == me || (o.zone == Zone.graveyard && o.owner == me)) {
    if (c.isLand) {
      if (o.zone != Zone.graveyard || o.playableBy == me) {
        final a = PlayLandAction(me, id);
        out.add(CardAction('Play ${c.name}', a, g.whyNot(a)));
      }
    } else {
      final opts = c.abilities.whereType<CastOptionAbility>().map((a) => a.option).toList();
      if (o.zone != Zone.graveyard || o.playableBy == me) {
        final a = CastAction(me, id);
        out.add(CardAction('Cast ${c.name}', a, g.whyNot(a)));
      }
      for (var i = 0; i < opts.length; i++) {
        final opt = opts[i];
        if (opt.kind == CastKind.flashback || opt.kind == CastKind.alternative || opt.kind == CastKind.fromGraveyard) {
          if ((opt.kind == CastKind.alternative) != (o.zone == Zone.hand)) continue;
          final a = CastAction(me, id, option: i);
          out.add(CardAction('${opt.label}${opt.cost != null ? ' ${opt.cost!.text}' : ''}', a, g.whyNot(a)));
        }
      }
    }
  }
  final mineOnTable = o.zone == Zone.battlefield && c.controller == me;
  for (var i = 0; i < c.abilities.length; i++) {
    final ab = c.abilities[i];
    if (ab is ActivatedAbility && (mineOnTable || (o.owner == me && zoneOfKind(ab.zone) == o.zone && o.zone != Zone.battlefield))) {
      final a = ActivateAbilityAction(me, id, i);
      out.add(CardAction(ab.isEquip ? 'Equip' : ab.text, a, g.whyNot(a)));
    } else if (ab is ManaAbility && mineOnTable) {
      final a = ManaAction(me, id, i);
      out.add(CardAction(ab.text, a, g.whyNot(a)));
    }
  }
  return out;
}

class _Battlefield extends StatelessWidget {
  const _Battlefield({super.key, required this.ctl, required this.player, this.mirrored = false, required this.onCard});
  final TableController ctl;
  final int player;
  final bool mirrored;
  final void Function(int id) onCard;

  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final g = ctl.game;
    final s = g.state;
    final landsAsCards = AppStore.shared.landsAsCards;
    final ids = [for (final id in s.battlefield) if (g.chars(id).controller == player) id];
    // Attached auras and equipment ride along with their creature.
    final attached = <int, List<int>>{};
    for (final id in ids) {
      final a = s.obj(id).attachedTo;
      if (a != null) attached.putIfAbsent(a, () => []).add(id);
    }
    final hosts = [for (final id in ids) if (s.obj(id).attachedTo == null || !ids.contains(s.obj(id).attachedTo)) id];
    final lands = [for (final id in hosts) if (g.chars(id).isLand && !g.chars(id).isCreature) id];
    final others = [for (final id in hosts) if (!lands.contains(id)) id];
    final legal = ctl.isLocalPriority ? ctl.legalCards : const <int>{};
    return LayoutBuilder(builder: (context, box) {
      final count = math.max(1, others.length);
      final perRow = math.max(3, (box.maxWidth / 74).floor());
      final rows = (count / perRow).ceil();
      final landH = landsAsCards ? box.maxHeight * 0.36 : 40.0;
      final avail = box.maxHeight - landH - 8;
      final w = math.min(math.min((box.maxWidth - 8) / math.min(count, perRow) - 6, (avail / rows - 6) * 63 / 88), 150.0).clamp(44.0, 150.0);
      Widget cardWith(int id, double width) {
        final under = attached[id] ?? const [];
        final card = Tracked(id: id, child: TableCard(ctl: ctl, id: id, width: width, onTap: () => onCard(id), highlight: legal.contains(id) ? t.accent : null));
        if (under.isEmpty) return card;
        return Stack(key: ValueKey('host$id'), clipBehavior: Clip.none, children: [
          for (var i = 0; i < under.length; i++) Padding(key: ValueKey(under[i]), padding: EdgeInsets.only(left: (i + 1) * width * 0.18, top: (i + 1) * 4), child: Tracked(id: under[i], child: TableCard(ctl: ctl, id: under[i], width: width * 0.9, onTap: () => onCard(under[i])))),
          card,
        ]);
      }

      final creatures = Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: [for (final id in others) cardWith(id, w)]);
      Widget landRow;
      if (landsAsCards) {
        final lw = (landH - 8) * 63 / 88;
        landRow = SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [for (final id in lands) Padding(key: ValueKey(id), padding: const EdgeInsets.only(right: 4), child: Tracked(id: id, child: TableCard(ctl: ctl, id: id, width: lw.clamp(36, 110), onTap: () => onCard(id), highlight: legal.contains(id) ? t.accent : null)))]));
      } else {
        landRow = _GroupedLands(ctl: ctl, player: player, lands: lands, onCard: onCard);
      }
      final children = <Widget>[
        Expanded(child: Center(child: SingleChildScrollView(child: creatures))),
        SizedBox(height: landH, child: Align(alignment: Alignment.centerLeft, child: landRow)),
      ];
      return Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), child: Column(children: mirrored ? children.reversed.toList() : children));
    });
  }
}

/// Lands grouped into labels by name ("Forest ×3, 1 tapped") — Settings → lands as cards.
class _GroupedLands extends StatelessWidget {
  const _GroupedLands({required this.ctl, required this.player, required this.lands, required this.onCard});
  final TableController ctl;
  final int player;
  final List<int> lands;
  final void Function(int id) onCard;

  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final g = ctl.game;
    final groups = <String, List<int>>{};
    for (final id in lands) {
      groups.putIfAbsent(g.chars(id).name, () => []).add(id);
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (final e in groups.entries) ...[
          Builder(builder: (context) {
            final untapped = e.value.where((id) => !g.state.obj(id).tapped).toList();
            final choosable = e.value.any(ctl.isChoosable);
            final selected = e.value.where(ctl.isSelected).length;
            final colors = <String>{};
            for (final id in e.value) {
              for (final a in g.chars(id).abilities.whereType<ManaAbility>()) {
                for (final m in a.produce.possible) {
                  colors.add(m.name);
                }
              }
            }
            return RectProbe(
              key: ValueKey(e.key),
              onRect: (fx, r) => fx.landGroups['$player|${e.key}'] = r,
              child: GestureDetector(
              onTap: () {
                // Tap: the first untapped one that the current choice can use, else the first.
                final pick = e.value.firstWhere((id) => ctl.isChoosable(id) && !ctl.isSelected(id), orElse: () => untapped.isNotEmpty ? untapped.first : e.value.first);
                onCard(pick);
              },
              child: Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: t.panel.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(t.chrome == ChromeStyle.lcars ? 16 : t.radius),
                  border: Border.all(color: selected > 0 ? t.highlight : (choosable ? t.ok : t.muted.withValues(alpha: 0.5)), width: choosable || selected > 0 ? 2.5 : 1),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  ManaPips(colors.map((c) => '{$c}').join(), size: 14),
                  const SizedBox(width: 4),
                  Text('${e.key} ', style: t.style(13, weight: FontWeight.w700)),
                  Text('${untapped.length}/${e.value.length}', style: t.style(13, weight: FontWeight.w900, color: untapped.isEmpty ? t.muted : t.accent)),
                  if (selected > 0) Text('  −$selected', style: t.style(13, weight: FontWeight.w900, color: t.highlight)),
                ]),
              ),
            ),
            );
          }),
        ],
      ]),
    );
  }
}

class _Hand extends StatelessWidget {
  const _Hand({super.key, required this.ctl, required this.height, required this.onCard});
  final TableController ctl;
  final double height;
  final void Function(int id) onCard;

  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final ids = ctl.state.player(ctl.me).hand;
    final legal = ctl.isLocalPriority ? ctl.legalCards : const <int>{};
    final w = (height - 10) * 63 / 88;
    return SizedBox(
      height: height,
      child: ids.isEmpty
          ? Center(child: Text(t.label('No cards in hand'), style: t.small))
          : ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              children: [
                for (final id in ids)
                  Padding(
                    key: ValueKey(id),
                    padding: const EdgeInsets.only(right: 6),
                    child: Tracked(id: id, child: TableCard(ctl: ctl, id: id, width: w, onTap: () => onCard(id), highlight: legal.contains(id) ? t.ok : null)),
                  ),
              ],
            ),
    );
  }
}

/// What to do now, in words, with tall labeled buttons.
class _PromptBar extends StatelessWidget {
  const _PromptBar({super.key, required this.ctl, required this.onOpenChoice});
  final TableController ctl;
  final VoidCallback onOpenChoice;

  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final s = ctl.session;
    final st = ctl.state;
    final d = ctl.decision;
    final error = s.lastError;
    final buttons = <Widget>[];
    String line;
    if (st.over) {
      line = st.winner == ctl.me ? 'You win!' : (st.winner == null ? 'The game is a draw.' : '${st.player(st.winner!).name} wins.');
    } else if (d != null) {
      line = d.prompt;
      buttons.addAll(decisionButtons(context, ctl, d, onOpenChoice));
    } else if (st.pending != null) {
      line = 'Waiting for ${st.player(st.pending!.decision.player).name}: ${st.pending!.decision.prompt}';
    } else if (st.priority == ctl.me) {
      line = AppStore.shared.coachOn ? coachLine(ctl) : '';
      final label = passLabel(ctl);
      buttons.add(Expanded(child: ThemedButton(label, icon: Icons.play_arrow, tall: true, onPressed: () => ctl.perform(PassAction(ctl.me)))));
      if (st.stack.isEmpty && st.active == ctl.me && (st.step == TurnStep.main1 || st.step == TurnStep.main2)) {
        buttons.add(const SizedBox(width: 8));
        buttons.add(Expanded(child: ThemedButton('End turn', icon: Icons.skip_next, tall: true, outlined: true, onPressed: () => ctl.perform(PassTurnAction(ctl.me)))));
      }
    } else {
      line = s.thinking || s.isLinked ? '${st.player(st.priority ?? s.opponentSeat).name} is deciding…' : '';
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      decoration: BoxDecoration(color: t.panel.withValues(alpha: 0.95), border: Border(top: BorderSide(color: t.accent, width: 2))),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (s.notice != null) Text(s.notice!, style: t.style(12, color: t.highlight)),
        if (error != null) Text(error, style: t.style(13, weight: FontWeight.w700, color: t.danger)),
        if (line.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(line, style: t.style(14, weight: FontWeight.w600), maxLines: 3, overflow: TextOverflow.ellipsis)),
        if (buttons.isNotEmpty) Row(children: buttons),
      ]),
    );
  }
}

String passLabel(TableController ctl) {
  final st = ctl.state;
  if (st.stack.isNotEmpty) return st.stack.last.controller == ctl.me ? 'Resolve' : 'OK, let it resolve';
  if (st.active != ctl.me) return 'OK';
  return switch (st.step) {
    TurnStep.main1 => 'To combat',
    TurnStep.main2 => 'End turn',
    TurnStep.beginCombat => 'Declare attackers',
    TurnStep.end => 'Next turn',
    _ => 'Next',
  };
}

/// The coach's line: what you can do right now.
String coachLine(TableController ctl) {
  final st = ctl.state;
  final g = ctl.game;
  final me = ctl.me;
  if (st.stack.isNotEmpty) {
    final top = st.stack.last;
    if (top.controller != me) return '${st.player(top.controller).name} is casting ${top.sourceName}. Respond with an instant, or let it resolve.';
    return '${top.sourceName} is on the stack.';
  }
  if (st.active == me && (st.step == TurnStep.main1 || st.step == TurnStep.main2)) {
    final hasLand = st.player(me).hand.any((id) => g.canPlayLand(me, id));
    final casts = ctl.legalCards.where((id) => st.obj(id).zone == Zone.hand && !g.chars(id).isLand).length;
    if (hasLand && casts > 0) return 'Your main phase: play a land and cast spells (the lit cards), or move on.';
    if (hasLand) return 'Your main phase: tap a land in your hand to play it.';
    if (casts > 0) return 'You can cast the lit cards. Tap one to see it.';
    return st.step == TurnStep.main1 ? 'Nothing more to do here: go to combat to attack.' : 'Nothing more to do: end your turn.';
  }
  if (st.active == me) return 'Your ${st.step.name}.';
  return "${st.player(st.active).name}'s turn. You can respond with instants.";
}

class _LogView extends StatelessWidget {
  const _LogView({required this.state});
  final GameState state;
  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final log = state.log.reversed.take(200).toList();
    return Container(
      margin: const EdgeInsets.all(6),
      decoration: BoxDecoration(color: t.panel.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(t.radius)),
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: log.length,
        itemBuilder: (_, i) {
          final e = log[i];
          final turn = e.kind == 'turn';
          return Padding(
            padding: EdgeInsets.only(top: turn ? 8 : 1),
            child: Text(e.text, style: t.style(turn ? 13 : 12, weight: turn ? FontWeight.w800 : FontWeight.w500, color: turn ? t.accent : t.text)),
          );
        },
      ),
    );
  }
}

class _GameOver extends StatelessWidget {
  const _GameOver({required this.session});
  final GameSession session;
  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final st = session.state;
    final won = st.winner == session.localSeat;
    final loser = st.players.where((p) => p.lost).map((p) => '${p.name}: ${p.lossReason}').join('\n');
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black54,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: ThemedPanel(
              title: won ? 'Victory' : (st.winner == null ? 'Draw' : 'Defeat'),
              color: won ? t.ok : t.danger,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(loser, style: t.body),
                const SizedBox(height: 12),
                ThemedButton('Back to the menu', tall: true, onPressed: () {
                  AppStore.shared.endSession();
                  Navigator.of(context).popUntil((r) => r.isFirst);
                }),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
