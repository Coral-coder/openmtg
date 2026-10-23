import 'package:flutter/material.dart';
import 'package:rules/rules.dart';

import '../app/store.dart';
import '../theme/theme.dart';
import 'card_view.dart';
import 'table_controller.dart';

/// Whether a decision is made in a dialog (rather than by tapping the table).
bool needsDialog(TableController ctl, Decision d) {
  switch (d.kind) {
    case DecisionKind.modes || DecisionKind.number || DecisionKind.order:
      return true;
    case DecisionKind.option:
      return d.labels.length > 3;
    case DecisionKind.targets || DecisionKind.cards:
      return !_allOnTable(ctl, d.options);
    case DecisionKind.payMana:
      return false;
    default:
      return false;
  }
}

bool _allOnTable(TableController ctl, List<int> options) {
  for (final e in options) {
    if (isPlayerEntity(e)) continue;
    final o = ctl.state.objOrNull(e);
    if (o == null) return false;
    if (o.zone == Zone.battlefield || o.zone == Zone.stack) continue;
    if (o.zone == Zone.hand && o.owner == ctl.me) continue;
    return false;
  }
  return true;
}

/// The prompt bar's buttons for a decision made on the table.
List<Widget> decisionButtons(BuildContext context, TableController ctl, Decision d, VoidCallback openChoice) {
  final t = GameTheme.of(context);
  final out = <Widget>[];
  void add(Widget w) {
    if (out.isNotEmpty) out.add(const SizedBox(width: 8));
    out.add(Expanded(child: w));
  }

  switch (d.kind) {
    case DecisionKind.mulligan:
      add(ThemedButton('Mulligan', tall: true, outlined: true, onPressed: () => ctl.answer(const [0])));
      add(ThemedButton('Keep', tall: true, icon: Icons.check, onPressed: () => ctl.answer(const [1])));
    case DecisionKind.yesNo:
      add(ThemedButton(d.labels.isNotEmpty ? d.labels[0] : 'No', tall: true, outlined: true, onPressed: () => ctl.answer(const [0])));
      add(ThemedButton(d.labels.length > 1 ? d.labels[1] : 'Yes', tall: true, icon: Icons.check, onPressed: () => ctl.answer(const [1])));
    case DecisionKind.option:
      if (d.labels.length <= 3) {
        for (var i = 0; i < d.labels.length; i++) {
          add(ThemedButton(d.labels[i], tall: true, outlined: i == 0 && d.labels.length > 1, onPressed: () => ctl.answer([i])));
        }
      } else {
        add(ThemedButton('Choose', tall: true, onPressed: openChoice));
      }
    case DecisionKind.targets || DecisionKind.cards:
      if (needsDialog(ctl, d)) {
        add(ThemedButton('Choose…', tall: true, onPressed: openChoice));
      } else if (!(d.min == 1 && d.max == 1)) {
        add(ThemedButton(ctl.selected.isEmpty && d.min == 0 ? 'None' : 'Confirm (${ctl.selected.length})', tall: true, icon: Icons.check, onPressed: ctl.canConfirm ? ctl.confirm : null));
      }
      if (d.cancellable) add(ThemedButton('Cancel', tall: true, outlined: true, color: t.danger, onPressed: ctl.cancel));
    case DecisionKind.attackers:
      add(ThemedButton(ctl.attacks.isEmpty ? 'No attacks' : 'Attack with ${ctl.attacks.length}', tall: true, icon: Icons.flash_on, color: ctl.attacks.isEmpty ? null : t.danger, onPressed: ctl.confirm));
      if (ctl.attacks.length < d.options.length) {
        add(ThemedButton('All', tall: true, outlined: true, onPressed: () {
          for (final id in d.options) {
            ctl.attacks[id] = ctl.defaultAttackTarget(d, id);
          }
          ctl.confirm();
        }));
      }
    case DecisionKind.blockers:
      add(ThemedButton(ctl.blocks.isEmpty ? 'No blocks' : 'Block (${ctl.blocks.length})', tall: true, icon: Icons.shield, onPressed: ctl.confirm));
    case DecisionKind.payMana:
      if (AppStore.shared.autoPay) break;
      add(ThemedButton('Pay automatically', tall: true, outlined: true, onPressed: () => ctl.answer(const [])));
      add(ThemedButton('Pay (${ctl.payment.length})', tall: true, icon: Icons.check, onPressed: ctl.payment.isEmpty ? null : ctl.confirm));
      if (d.cancellable) add(ThemedButton('Cancel', tall: true, outlined: true, color: t.danger, onPressed: ctl.cancel));
    case DecisionKind.damage || DecisionKind.divide:
      add(ThemedButton('Assign automatically', tall: true, onPressed: () => ctl.answer(const [])));
    case DecisionKind.modes || DecisionKind.number || DecisionKind.order:
      add(ThemedButton('Choose…', tall: true, onPressed: openChoice));
      if (d.cancellable) add(ThemedButton('Cancel', tall: true, outlined: true, color: t.danger, onPressed: ctl.cancel));
  }
  return out;
}

/// Shows the dialog for [d]; closes itself when answered.
Future<void> openDecisionDialog(BuildContext context, TableController ctl, Decision d, {bool force = false}) async {
  switch (d.kind) {
    case DecisionKind.modes:
      await showDialog<void>(context: context, builder: (_) => _ModesDialog(ctl: ctl, d: d));
    case DecisionKind.number:
      await showDialog<void>(context: context, builder: (_) => _NumberDialog(ctl: ctl, d: d));
    case DecisionKind.order:
      await showDialog<void>(context: context, builder: (_) => _OrderDialog(ctl: ctl, d: d));
    case DecisionKind.option:
      await showDialog<void>(
        context: context,
        builder: (c) => SimpleDialog(title: Text(d.prompt), children: [
          for (var i = 0; i < d.labels.length; i++)
            SimpleDialogOption(
              onPressed: () {
                Navigator.pop(c);
                ctl.answer([i]);
              },
              child: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(d.labels[i])),
            ),
          if (d.cancellable)
            SimpleDialogOption(
              onPressed: () {
                Navigator.pop(c);
                ctl.cancel();
              },
              child: const Text('Cancel'),
            ),
        ]),
      );
    case DecisionKind.targets || DecisionKind.cards:
      if (needsDialog(ctl, d) || force) await showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (_) => _PickCards(ctl: ctl, d: d));
    default:
      break;
  }
}

class _ModesDialog extends StatefulWidget {
  const _ModesDialog({required this.ctl, required this.d});
  final TableController ctl;
  final Decision d;
  @override
  State<_ModesDialog> createState() => _ModesDialogState();
}

class _ModesDialogState extends State<_ModesDialog> {
  final picked = <int>[];
  @override
  Widget build(BuildContext context) {
    final d = widget.d;
    final t = GameTheme.of(context);
    return AlertDialog(
      title: Text(d.prompt),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < d.labels.length; i++)
            CheckboxListTile(
              value: picked.contains(i),
              enabled: d.options.contains(i),
              title: Text(d.labels[i], style: t.body),
              onChanged: (v) => setState(() {
                if (v == true) {
                  if (d.max == 1) picked.clear();
                  if (picked.length < d.max) picked.add(i);
                } else {
                  picked.remove(i);
                }
              }),
            ),
        ]),
      ),
      actions: [
        if (d.cancellable)
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              widget.ctl.cancel();
            },
            child: const Text('Cancel'),
          ),
        FilledButton(
          onPressed: picked.length >= d.min && picked.length <= d.max
              ? () {
                  Navigator.pop(context);
                  widget.ctl.answer(List.of(picked)..sort());
                }
              : null,
          child: const Text('Choose'),
        ),
      ],
    );
  }
}

class _NumberDialog extends StatefulWidget {
  const _NumberDialog({required this.ctl, required this.d});
  final TableController ctl;
  final Decision d;
  @override
  State<_NumberDialog> createState() => _NumberDialogState();
}

class _NumberDialogState extends State<_NumberDialog> {
  late int v = widget.d.max;
  @override
  Widget build(BuildContext context) {
    final d = widget.d;
    final t = GameTheme.of(context);
    return AlertDialog(
      title: Text(d.prompt),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('$v', style: t.style(40, weight: FontWeight.w900, color: t.accent)),
        if (d.max > d.min) Slider(value: v.toDouble(), min: d.min.toDouble(), max: d.max.toDouble(), divisions: d.max - d.min, onChanged: (x) => setState(() => v = x.round())),
      ]),
      actions: [
        if (d.cancellable)
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              widget.ctl.cancel();
            },
            child: const Text('Cancel'),
          ),
        FilledButton(
          onPressed: () {
            Navigator.pop(context);
            widget.ctl.answer([v]);
          },
          child: const Text('OK'),
        ),
      ],
    );
  }
}

class _OrderDialog extends StatefulWidget {
  const _OrderDialog({required this.ctl, required this.d});
  final TableController ctl;
  final Decision d;
  @override
  State<_OrderDialog> createState() => _OrderDialogState();
}

class _OrderDialogState extends State<_OrderDialog> {
  late final List<int> order = List.of(widget.d.options);
  @override
  Widget build(BuildContext context) {
    final d = widget.d;
    String label(int e) {
      if (d.labels.isNotEmpty && d.options.length == d.labels.length) {
        final i = d.options.indexOf(e);
        if (i >= 0) return d.labels[i];
      }
      return widget.ctl.game.nameOf(e);
    }

    return AlertDialog(
      title: Text(d.prompt),
      content: SizedBox(
        width: 360,
        height: 320,
        child: ReorderableListView(
          onReorder: (a, b) => setState(() {
            final x = order.removeAt(a);
            order.insert(b > a ? b - 1 : b, x);
          }),
          children: [for (final e in order) ListTile(key: ValueKey(e), leading: const Icon(Icons.drag_handle), title: Text(label(e)))],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () {
            Navigator.pop(context);
            widget.ctl.answer(List.of(order));
          },
          child: const Text('OK'),
        ),
      ],
    );
  }
}

/// Choosing cards that aren't on the table (library, graveyard, an opponent's hand).
class _PickCards extends StatefulWidget {
  const _PickCards({required this.ctl, required this.d});
  final TableController ctl;
  final Decision d;
  @override
  State<_PickCards> createState() => _PickCardsState();
}

class _PickCardsState extends State<_PickCards> {
  final picked = <int>[];
  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final d = widget.d;
    final g = widget.ctl.game;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(children: [
          Padding(padding: const EdgeInsets.all(12), child: Text(d.prompt, style: t.heading)),
          Expanded(
            child: GridView.extent(
              maxCrossAxisExtent: 150,
              childAspectRatio: 63 / 88,
              padding: const EdgeInsets.all(8),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              children: [
                for (final e in d.options)
                  GestureDetector(
                    onTap: () => setState(() {
                      if (picked.contains(e)) {
                        picked.remove(e);
                      } else if (picked.length < d.max) {
                        picked.add(e);
                      } else if (d.max == 1) {
                        picked
                          ..clear()
                          ..add(e);
                      }
                    }),
                    child: Container(
                      decoration: BoxDecoration(border: Border.all(color: picked.contains(e) ? t.highlight : Colors.transparent, width: 4), borderRadius: BorderRadius.circular(8)),
                      child: isPlayerEntity(e)
                          ? Center(child: Text(g.state.player(entityPlayer(e)).name, style: t.heading))
                          : CardPicture(def: g.state.obj(e).isToken ? null : g.db[g.state.obj(e).cardName], chars: g.chars(e), size: 'normal'),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              if (d.cancellable)
                Expanded(
                  child: ThemedButton('Cancel', outlined: true, color: t.danger, onPressed: () {
                    Navigator.pop(context);
                    widget.ctl.cancel();
                  }),
                ),
              if (d.cancellable) const SizedBox(width: 8),
              Expanded(
                child: ThemedButton(picked.isEmpty && d.min == 0 ? 'None' : 'Choose (${picked.length})', icon: Icons.check, onPressed: picked.length >= d.min && picked.length <= d.max
                    ? () {
                        Navigator.pop(context);
                        widget.ctl.answer(List.of(picked));
                      }
                    : null),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
