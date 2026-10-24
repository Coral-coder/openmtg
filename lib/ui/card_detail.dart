import 'package:flutter/material.dart';
import 'package:rules/rules.dart';

import 'package:tcg_app/tcg_app.dart';
import 'card_view.dart';
import 'table.dart';
import 'table_controller.dart';

/// A card shown large with what it can do now (and why not), its full text, and anything the
/// engine doesn't handle yet.
Future<void> showCardDetail(BuildContext context, {required TableController ctl, required int id}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (c) => ListenableBuilder(
      listenable: ctl.session,
      builder: (c, _) {
        final g = ctl.game;
        final o = g.state.objOrNull(id);
        if (o == null) return const SizedBox(height: 80);
        final def = o.isToken ? null : g.db[o.copyOfCard ?? o.cardName];
        final acts = cardActions(ctl, id);
        return CardDetailView(
          def: def,
          chars: g.chars(id),
          back: o.face == 1 && (def?.layout.isDoubleFaced ?? false),
          status: _status(ctl, id),
          actions: [
            for (final a in acts)
              _ActionRow(
                label: a.label,
                reason: a.reason,
                onTap: a.reason != null
                    ? null
                    : () {
                        Navigator.pop(c);
                        ctl.perform(a.action);
                      },
              ),
          ],
        );
      },
    ),
  );
}

String _status(TableController ctl, int id) {
  final g = ctl.game;
  final o = g.state.obj(id);
  final parts = <String>[];
  if (o.zone != Zone.battlefield) parts.add('In ${o.owner == ctl.me ? 'your' : "${g.state.player(o.owner).name}'s"} ${o.zone.name}');
  if (o.tapped) parts.add('tapped');
  if (o.damage > 0) parts.add('${o.damage} damage');
  for (final e in o.counters.entries) {
    if (e.value > 0) parts.add('${e.value} ${e.key} counter${e.value == 1 ? '' : 's'}');
  }
  if (o.attacking != null) parts.add('attacking');
  if (o.zone == Zone.battlefield && o.controlSince >= g.state.turn && g.chars(id).isCreature && !g.chars(id).has(Kw.haste)) parts.add('summoning sick');
  if (o.isToken) parts.add('token');
  return parts.join(' · ');
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.label, required this.reason, required this.onTap});
  final String label;
  final String? reason;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ThemedButton(label, tall: true, onPressed: onTap),
        if (reason != null) Padding(padding: const EdgeInsets.only(top: 2, left: 6), child: Text(reason!, style: t.style(12, color: t.muted))),
      ]),
    );
  }
}

class CardDetailView extends StatelessWidget {
  const CardDetailView({super.key, required this.def, this.chars, this.back = false, this.status = '', this.actions = const []});
  final CardDef? def;

  /// Shows the back face (a transformed or back-face-up double-faced card).
  final bool back;
  final Chars? chars;
  final String status;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final d = def;
    final parsed = d == null ? null : OracleParser.parse(d);
    final h = MediaQuery.of(context).size.height;
    final wide = MediaQuery.of(context).size.width > 700;
    final image = ConstrainedBox(
      constraints: BoxConstraints(maxHeight: wide ? h * 0.7 : h * 0.45, maxWidth: 420),
      child: AspectRatio(aspectRatio: 63 / 88, child: CardPicture(def: d, chars: chars, size: 'large', back: back)),
    );
    final info = Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text(chars?.name ?? d?.name ?? '', style: t.heading),
      if (status.isNotEmpty) Text(status, style: t.small),
      const SizedBox(height: 8),
      ...actions,
      if (d != null) ...[
        Text(d.typeLine, style: t.style(13, weight: FontWeight.w700, color: t.muted)),
        const SizedBox(height: 4),
        SelectableText(d.oracleText, style: t.body),
        const SizedBox(height: 8),
        if (parsed != null && !parsed.supported)
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: t.danger.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6), border: Border.all(color: t.danger)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Not supported yet', style: t.style(13, weight: FontWeight.w800, color: t.danger)),
              for (final u in parsed.unsupported) Text('• $u', style: t.style(12, weight: FontWeight.w500)),
              Text('It can be viewed but not played in rated or online games.', style: t.small),
            ]),
          )
        else if (parsed != null)
          Row(children: [Icon(Icons.verified, size: 16, color: t.ok), const SizedBox(width: 4), Text('Fully supported', style: t.style(12, color: t.ok))]),
        const SizedBox(height: 6),
        Text('${d.artist.isEmpty ? '' : 'Illustrated by ${d.artist} · '}${d.imageSet.toUpperCase()} #${d.imageNumber} · image from Scryfall', style: t.small),
      ],
    ]);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SingleChildScrollView(
          child: wide
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [image, const SizedBox(width: 16), Expanded(child: info)])
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Center(child: image), const SizedBox(height: 12), info]),
        ),
      ),
    );
  }
}

/// A graveyard or exile, as a grid.
Future<void> showZone(BuildContext context, {required TableController ctl, required String title, required List<int> ids}) {
  final t = GameTheme.of(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (c) => SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(children: [
          Padding(padding: const EdgeInsets.all(12), child: Text(title, style: t.heading)),
          Expanded(
            child: ids.isEmpty
                ? Center(child: Text('Empty', style: t.small))
                : GridView.extent(
                    maxCrossAxisExtent: 140,
                    childAspectRatio: 63 / 88,
                    padding: const EdgeInsets.all(8),
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    children: [
                      for (final id in ids)
                        GestureDetector(
                          onTap: () {
                            Navigator.pop(c);
                            showCardDetail(context, ctl: ctl, id: id);
                          },
                          child: CardPicture(def: ctl.game.db[ctl.state.obj(id).cardName], chars: ctl.game.chars(id), size: 'normal'),
                        ),
                    ],
                  ),
          ),
        ]),
      ),
    ),
  );
}
