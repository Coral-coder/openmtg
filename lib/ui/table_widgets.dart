import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:rules/rules.dart';

import '../theme/theme.dart';
import 'card_view.dart';
import 'table_controller.dart';

/// A card on the table: image or frame, rotated when tapped, with counters, damage, current P/T
/// and combat markers. The badges sit on the art and the P/T box, never on the bottom strip
/// with the artist and copyright.
class TableCard extends StatelessWidget {
  const TableCard({super.key, required this.ctl, required this.id, required this.width, this.onTap, this.onLongPress, this.highlight});
  final TableController ctl;
  final int id;
  final double width;
  final VoidCallback? onTap, onLongPress;

  /// Glow color when the card can be acted on (null: none).
  final Color? highlight;

  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final g = ctl.game;
    final o = g.state.obj(id);
    final c = g.chars(id);
    final def = o.isToken ? null : g.db[o.copyOfCard ?? o.cardName];
    final h = width * 88 / 63;
    final printed = def == null ? null : (int.tryParse(def.front.power ?? ''), int.tryParse(def.front.toughness ?? ''));
    final ptChanged = c.power != null && (printed == null || printed.$1 != c.power || printed.$2 != c.toughness || o.damage > 0);
    final choosable = ctl.isChoosable(id);
    final selected = ctl.isSelected(id);
    final glow = selected ? t.highlight : (choosable ? t.ok : highlight);
    final attacking = o.attacking != null;
    final blocking = o.blocking.isNotEmpty;
    Widget card = SizedBox(
      width: width,
      height: h,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(child: ClipRRect(borderRadius: BorderRadius.circular(width * 0.05), child: CardPicture(def: def, chars: c, size: width > 150 ? 'normal' : 'small'))),
        if (glow != null)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(width * 0.05), border: Border.all(color: glow, width: selected ? 3.5 : 2.5), boxShadow: [BoxShadow(color: glow.withValues(alpha: 0.55), blurRadius: 10)]),
              ),
            ),
          ),
        if (ptChanged)
          Positioned(
            right: width * 0.03,
            bottom: h * 0.075,
            child: _Badge(text: '${c.power}/${(c.toughness ?? 0) - o.damage}', color: o.damage > 0 ? t.danger : (c.power! > (printed?.$1 ?? 0) ? t.ok : const Color(0xFF222222)), size: width),
          ),
        if (o.counters.entries.any((e) => e.value > 0 && e.key != 'loyalty' && e.key != '+1/+1' && e.key != '-1/-1'))
          Positioned(left: width * 0.04, top: h * 0.32, child: _Badge(text: o.counters.entries.where((e) => e.value > 0 && e.key != 'loyalty' && !e.key.contains('/')).map((e) => '${e.value} ${e.key}').join('\n'), color: const Color(0xFF3A3A55), size: width)),
        if ((o.counters['+1/+1'] ?? 0) > 0) Positioned(left: width * 0.04, top: h * 0.2, child: _Badge(text: '+${o.counters['+1/+1']}', color: t.ok, size: width)),
        if (c.isPlaneswalker) Positioned(right: width * 0.03, bottom: h * 0.075, child: _Badge(text: '${o.counters['loyalty'] ?? 0}', color: const Color(0xFF222222), size: width * 1.2)),
        if (attacking) Positioned(top: -6, left: 0, right: 0, child: Center(child: _Badge(text: 'ATTACKING', color: t.danger, size: width))),
        if (blocking) Positioned(top: -6, left: 0, right: 0, child: Center(child: _Badge(text: 'BLOCKING', color: t.accent2, size: width))),
        if (ctl.attacks.containsKey(id)) Positioned(top: -6, left: 0, right: 0, child: Center(child: _Badge(text: 'ATTACK', color: t.danger, size: width))),
        if (ctl.blocks.containsKey(id)) Positioned(top: -6, left: 0, right: 0, child: Center(child: _Badge(text: 'BLOCKS ${g.nameOf(ctl.blocks[id]!)}', color: t.accent2, size: width))),
        if (o.controlSince >= g.state.turn && c.isCreature && !c.has(Kw.haste) && o.controller == g.state.active)
          Positioned(right: width * 0.04, top: h * 0.2, child: Icon(Icons.hourglass_bottom, size: width * 0.16, color: Colors.white70, shadows: const [Shadow(blurRadius: 3)])),
      ]),
    );
    if (o.tapped) {
      card = SizedBox(width: h, height: width, child: Center(child: Transform.rotate(angle: math.pi / 2, child: card)));
    }
    return Semantics(
      button: true,
      label: '${c.name}${o.tapped ? ', tapped' : ''}${c.power != null ? ', ${c.power}/${c.toughness}' : ''}',
      child: GestureDetector(onTap: onTap, onLongPress: onLongPress, child: card),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color, required this.size});
  final String text;
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: size * 0.05, vertical: size * 0.01),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(size * 0.06), border: Border.all(color: Colors.white70, width: 1)),
        child: Text(text, textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: (size * 0.13).clamp(8, 18), fontWeight: FontWeight.w900, height: 1.05)),
      );
}

/// One player's line: name, life, cards, mana pool. Tappable as a target.
class PlayerBar extends StatelessWidget {
  const PlayerBar({super.key, required this.ctl, required this.player, this.onZone, this.compact = false});
  final TableController ctl;
  final int player;
  final void Function(Zone zone)? onZone;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final s = ctl.state;
    final p = s.player(player);
    final e = playerEntity(player);
    final choosable = ctl.isChoosable(e);
    final selected = ctl.isSelected(e);
    final active = s.active == player;
    final acting = (s.pending?.decision.player ?? s.priority) == player;
    final pool = <String, int>{};
    for (final m in p.pool) {
      pool[m.type.name] = (pool[m.type.name] ?? 0) + 1;
    }
    Widget chip(IconData icon, String n, String tip, {VoidCallback? onTap}) => Tooltip(
          message: tip,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
              child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 16, color: t.muted), const SizedBox(width: 2), Text(n, style: t.style(13, color: t.text))]),
            ),
          ),
        );
    final border = selected ? t.highlight : (choosable ? t.ok : (acting ? t.accent : Colors.transparent));
    return GestureDetector(
      onTap: choosable ? () => ctl.tap(e) : null,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: compact ? 2 : 4),
        decoration: BoxDecoration(
          color: t.panel.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(t.chrome == ChromeStyle.lcars ? 18 : t.radius),
          border: Border.all(color: border, width: choosable || selected ? 3 : 1.5),
        ),
        child: Row(children: [
          if (active) Padding(padding: const EdgeInsets.only(right: 4), child: Icon(Icons.play_arrow, size: 18, color: t.accent)),
          Flexible(child: Text(p.name, style: t.style(14, weight: FontWeight.w800, color: p.lost ? t.muted : t.text), maxLines: 1, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          Semantics(
            label: 'Life ${p.life}',
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: Text('${p.life}', key: ValueKey(p.life), style: t.style(compact ? 20 : 24, weight: FontWeight.w900, color: p.life <= 5 ? t.danger : t.accent)),
            ),
          ),
          if (p.poison > 0) Padding(padding: const EdgeInsets.only(left: 6), child: Text('☠${p.poison}', style: t.style(14, color: t.ok))),
          const Spacer(),
          for (final m in pool.entries) Padding(padding: const EdgeInsets.only(right: 2), child: ManaPips('{${m.key}}' * m.value, size: 14)),
          chip(Icons.style, '${p.hand.length}', 'Cards in hand'),
          chip(Icons.layers, '${p.library.length}', 'Library'),
          chip(Icons.delete_outline, '${p.graveyard.length}', 'Graveyard', onTap: onZone == null ? null : () => onZone!(Zone.graveyard)),
          if (p.exile.isNotEmpty) chip(Icons.block, '${p.exile.length}', 'Exile', onTap: onZone == null ? null : () => onZone!(Zone.exile)),
        ]),
      ),
    );
  }
}

/// Steps of the turn, the current one lit.
class StepStrip extends StatelessWidget {
  const StepStrip({super.key, required this.state, required this.me});
  final GameState state;
  final int me;

  static const _short = {
    TurnStep.untap: 'Untap',
    TurnStep.upkeep: 'Upkeep',
    TurnStep.draw: 'Draw',
    TurnStep.main1: 'Main',
    TurnStep.beginCombat: 'Combat',
    TurnStep.declareAttackers: 'Attack',
    TurnStep.declareBlockers: 'Block',
    TurnStep.firstStrikeDamage: 'First strike',
    TurnStep.combatDamage: 'Damage',
    TurnStep.endCombat: 'End combat',
    TurnStep.main2: 'Main 2',
    TurnStep.end: 'End',
    TurnStep.cleanup: 'Cleanup',
  };

  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final mine = state.active == me;
    final steps = [TurnStep.upkeep, TurnStep.draw, TurnStep.main1, TurnStep.beginCombat, TurnStep.declareAttackers, TurnStep.declareBlockers, TurnStep.combatDamage, TurnStep.main2, TurnStep.end];
    var cur = state.step;
    if (cur == TurnStep.firstStrikeDamage) cur = TurnStep.combatDamage;
    if (cur == TurnStep.endCombat) cur = TurnStep.combatDamage;
    if (cur == TurnStep.untap) cur = TurnStep.upkeep;
    if (cur == TurnStep.cleanup) cur = TurnStep.end;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        Text(t.label(mine ? 'Your turn ${state.turn}' : '${state.player(state.active).name} · turn ${state.turn}'), style: t.style(12, weight: FontWeight.w800, color: mine ? t.accent : t.accent2)),
        const SizedBox(width: 8),
        for (final s in steps)
          Container(
            margin: const EdgeInsets.only(right: 3),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: s == cur ? (mine ? t.accent : t.accent2) : t.panel.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(t.chrome == ChromeStyle.lcars ? 10 : 4)),
            child: Text(t.label(_short[s]!), style: t.style(11, weight: FontWeight.w700, color: s == cur ? t.buttonText : t.muted)),
          ),
      ]),
    );
  }
}

/// The stack, top first.
class StackStrip extends StatelessWidget {
  const StackStrip({super.key, required this.ctl, required this.onCard});
  final TableController ctl;
  final void Function(int id) onCard;

  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final s = ctl.state;
    if (s.stack.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(color: t.panel.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(t.radius), border: Border.all(color: t.accent3, width: 1.5)),
      child: Row(children: [
        RotatedBox(quarterTurns: 3, child: Text(t.label('Stack'), style: t.style(11, weight: FontWeight.w800, color: t.accent3))),
        const SizedBox(width: 6),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final item in s.stack.reversed)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: item.objId != null && s.objOrNull(item.objId!) != null
                      ? GestureDetector(
                          onTap: ctl.isChoosable(item.objId!) ? () => ctl.tap(item.objId!) : () => onCard(item.objId!),
                          child: Container(
                            decoration: BoxDecoration(border: Border.all(color: ctl.isSelected(item.objId!) ? t.highlight : (ctl.isChoosable(item.objId!) ? t.ok : Colors.transparent), width: 3), borderRadius: BorderRadius.circular(6)),
                            child: SizedBox(width: 62, height: 86, child: CardPicture(def: ctl.game.db[s.obj(item.objId!).cardName], chars: ctl.game.chars(item.objId!), size: 'small')),
                          ),
                        )
                      : Container(
                          width: 150,
                          height: 86,
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(color: t.surface, borderRadius: BorderRadius.circular(6), border: Border.all(color: t.accent3)),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(item.sourceName, style: t.style(11, weight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis),
                            Expanded(child: Text(item.ability?.text ?? '', style: t.style(10, weight: FontWeight.w500, color: t.muted), overflow: TextOverflow.fade)),
                          ]),
                        ),
                ),
            ]),
          ),
        ),
      ]),
    );
  }
}
