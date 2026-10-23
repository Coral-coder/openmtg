/// An object's characteristics after continuous effects (CR 109.3, 613).
library;

import '../cards/card.dart';
import '../cards/mana.dart';
import '../ir/ir.dart';
import 'state.dart';

class Chars {
  Chars({
    required this.name,
    required this.types,
    required this.subtypes,
    required this.supertypes,
    required this.colors,
    required this.manaCost,
    required this.power,
    required this.toughness,
    required this.loyalty,
    required this.defense,
    required this.abilities,
    required this.controller,
    required this.owner,
  });

  String name;
  Set<CardType> types;
  List<String> subtypes;
  Set<Supertype> supertypes;
  Set<Color> colors;
  ManaCost? manaCost;
  int? power, toughness;
  int? loyalty, defense;
  List<Ability> abilities;
  PlayerId controller;
  final PlayerId owner;

  /// Keywords and rule flags, from keyword abilities and layer-6 grants.
  final Set<Kw> keywords = {};
  bool allCreatureTypes = false;

  Chars copy() => Chars(
        name: name,
        types: Set.of(types),
        subtypes: List.of(subtypes),
        supertypes: Set.of(supertypes),
        colors: Set.of(colors),
        manaCost: manaCost,
        power: power,
        toughness: toughness,
        loyalty: loyalty,
        defense: defense,
        abilities: List.of(abilities),
        controller: controller,
        owner: owner,
      )
        ..keywords.addAll(keywords)
        ..allCreatureTypes = allCreatureTypes;

  bool get isCreature => types.contains(CardType.creature);
  bool get isLand => types.contains(CardType.land);
  bool get isArtifact => types.contains(CardType.artifact);
  bool get isEnchantment => types.contains(CardType.enchantment);
  bool get isPlaneswalker => types.contains(CardType.planeswalker);
  bool get isBattle => types.contains(CardType.battle);
  bool get isInstant => types.contains(CardType.instant);
  bool get isSorcery => types.contains(CardType.sorcery);
  bool get isPermanentCard => types.any((t) => t.isPermanentType);
  bool get isLegendary => supertypes.contains(Supertype.legendary);
  bool get isAura => types.contains(CardType.enchantment) && subtypes.contains('Aura');
  bool get isEquipment => types.contains(CardType.artifact) && subtypes.contains('Equipment');
  int get manaValue => manaCost?.manaValue ?? 0;

  bool has(Kw k) => keywords.any((x) => x.name == k.name);
  bool hasName(String n) => keywords.any((x) => x.name == n);
  Iterable<Kw> kws(String n) => keywords.where((x) => x.name == n);

  bool hasSubtype(String s) => subtypes.contains(s) || (allCreatureTypes && _isCreatureType(s));

  static bool _isCreatureType(String s) => !const {'Aura', 'Equipment', 'Vehicle', 'Food', 'Treasure', 'Clue', 'Saga', 'Forest', 'Island', 'Mountain', 'Plains', 'Swamp'}.contains(s);
}
