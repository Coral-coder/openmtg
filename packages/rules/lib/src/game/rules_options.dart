/// The adjustable rules of a game (MagicTrek's Settings → Rules, CR 103 and 903 options). They
/// travel inside the start action, so a saved game replays with the rules it began with and a
/// linked match plays by the host's settings. Part of the state digest.
class RulesOptions {
  const RulesOptions({
    this.startingLife = 20,
    this.handSize = 7,
    this.londonMulligan = true,
    this.freeMulligan = false,
    this.firstPlayerDraws = false,
    this.maxHandSize = true,
    this.commander = false,
    this.autoPassWhenNothingToDo = true,
  });

  static const standard = RulesOptions();
  static const commanderGame = RulesOptions(startingLife: 40, freeMulligan: true, commander: true);

  /// 20 normally, 40 in Commander.
  final int startingLife;

  /// Cards in the opening hand, and the maximum hand size when [maxHandSize] is on.
  final int handSize;

  /// London mulligan (CR 103.5): draw seven again and bottom one per mulligan. Off: each mulligan
  /// draws one fewer.
  final bool londonMulligan;

  /// The first mulligan is free (CR 103.5c, multiplayer convention).
  final bool freeMulligan;

  /// The starting player also draws on turn one (normally skipped, CR 103.8a).
  final bool firstPlayerDraws;

  /// Discard down to [handSize] in the cleanup step.
  final bool maxHandSize;

  /// Commander rules (CR 903): command zone, tax, commander damage, color identity.
  final bool commander;

  /// Players with nothing they could do are passed for automatically (like the big clients).
  final bool autoPassWhenNothingToDo;

  RulesOptions copyWith({int? startingLife, int? handSize, bool? londonMulligan, bool? freeMulligan, bool? firstPlayerDraws, bool? maxHandSize, bool? commander, bool? autoPassWhenNothingToDo}) => RulesOptions(
        startingLife: startingLife ?? this.startingLife,
        handSize: handSize ?? this.handSize,
        londonMulligan: londonMulligan ?? this.londonMulligan,
        freeMulligan: freeMulligan ?? this.freeMulligan,
        firstPlayerDraws: firstPlayerDraws ?? this.firstPlayerDraws,
        maxHandSize: maxHandSize ?? this.maxHandSize,
        commander: commander ?? this.commander,
        autoPassWhenNothingToDo: autoPassWhenNothingToDo ?? this.autoPassWhenNothingToDo,
      );

  Map<String, dynamic> toJson() => {
        'life': startingLife,
        'hand': handSize,
        'london': londonMulligan,
        'freeMulligan': freeMulligan,
        'firstDraws': firstPlayerDraws,
        'maxHand': maxHandSize,
        if (commander) 'commander': true,
        if (!autoPassWhenNothingToDo) 'autoPass': false,
      };

  /// Missing keys take the standard value, so older saves and peers still load.
  static RulesOptions fromJson(Map<String, dynamic>? j) {
    if (j == null) return standard;
    return RulesOptions(
      startingLife: (j['life'] as num?)?.toInt() ?? 20,
      handSize: (j['hand'] as num?)?.toInt() ?? 7,
      londonMulligan: j['london'] as bool? ?? true,
      freeMulligan: j['freeMulligan'] as bool? ?? false,
      firstPlayerDraws: j['firstDraws'] as bool? ?? false,
      maxHandSize: j['maxHand'] as bool? ?? true,
      commander: j['commander'] as bool? ?? false,
      autoPassWhenNothingToDo: j['autoPass'] as bool? ?? true,
    );
  }

  String get summary {
    final parts = <String>['$startingLife life', '$handSize-card hands', londonMulligan ? 'London mulligan' : 'classic mulligan'];
    if (freeMulligan) parts.add('first mulligan free');
    if (firstPlayerDraws) parts.add('first player draws');
    if (!maxHandSize) parts.add('no maximum hand size');
    if (commander) parts.add('Commander');
    return parts.join(', ');
  }

  bool get isStandard => digest() == standard.digest();

  String digest() => '$startingLife/$handSize/$londonMulligan/$freeMulligan/$firstPlayerDraws/$maxHandSize/$commander/$autoPassWhenNothingToDo';
}
