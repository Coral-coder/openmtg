# OpenMTG plan

A free, fan-made Magic: The Gathering game: every card, the Comprehensive Rules, a visual theme
per set or universe. One Flutter codebase for the browser (GitHub Pages), Android and iOS. It grows
out of [MagicTrek](https://github.com/coral-coder/magictrek), which played only the Star Trek set.

Priorities, in order: **the website and browser play first**, then Android and iOS together.

## 1. Architecture

```
packages/rules/        Pure Dart. No Flutter, no I/O, no clock, no unseeded randomness.
  lib/src/util/        SplitMix64 shuffler on fixnum Int64, value equality, digests
  lib/src/cards/       Card definitions (faces, mana costs, types) and the card database
  lib/src/oracle/      Oracle text → ability IR, with the exact unhandled text per card
  lib/src/ir/          The ability IR: costs, effects, targets, conditions, statics, triggers
  lib/src/game/        Game state and the rules, one file per Comprehensive Rules area
  lib/src/ai/          Computer player
  lib/src/formats/     Format legality, deck validation, starter decks / cube
  bin/                 cards.dart (build DB, coverage report), chaos.dart (bot games + replay)
  test/                One test file per rules area, plus the chaos harness
lib/                   The Flutter app
  app/                 Settings store, sessions, saved games, sounds, card DB loader, image cache, updater
  net/                 Lockstep protocol and transports (Nostr relays, LAN, Bluetooth)
  theme/               Theme system and the themes
  ui/                  Screens and widgets
site/                  Landing page (GitHub Pages root); the web build goes under /play/
tools/                 Data pipeline scripts run by CI
.github/workflows/     flutter-ci, pages, android-release, ios-testflight, card-data
```

The app depends on `packages/rules` by path. Engine tests run with `dart test` (seconds, no
Flutter); widget tests and phone-size screenshots run with `flutter test`.

### Determinism (sacred)

A game is a **seed plus an ordered list of actions**. Every device replays the same actions to the
same state, and `GameState.digest()` (a canonical text hashed with SHA-256) must match everywhere.

- Randomness only from `SeededRng` (SplitMix64 on `Int64`, exact on web and native).
- No `DateTime.now()`, no `Random()`, no `HashMap`/`HashSet` in `packages/rules`. Dart's default
  `{}` maps and sets are insertion-ordered (`LinkedHashMap`), which is deterministic; a lint test
  greps the engine for the forbidden names.
- Every player choice (targets, modes, X, blockers, damage assignment, ordering triggers, scry…)
  is an action in the log. The engine never asks the UI anything it doesn't record.
- `bin/chaos.dart` plays hundreds of bot games from random seeds, then replays each from its log
  and checks every digest. It runs in CI and before every push.

### Multiplayer (kept from MagicTrek)

`lib/net/protocol.dart` is MagicTrek's lockstep protocol, generalised from two seats to N:

- every move is saved on the device with a fingerprint (digest) of the game after it;
- each move names the fingerprint it was made from, so it is never applied to another history;
- on reconnect the devices swap fingerprint lists, find the last shared move and rewind to it;
- if histories split, the first seat's (host's) moves stand; a crashed device resumes from its log.

Transports: Nostr relays (play by code, encrypted; the only one in a browser), Wi‑Fi (UDP
discovery, TCP, typed-in IP), Bluetooth LE. Ported unchanged except for N seats.

## 2. Rules engine mapped to the Comprehensive Rules

The engine is organised around the CR, not around a growing parser. Each row is a file (or a
group) under `packages/rules/lib/src/game/` with its own tests.

| CR | Area | Design |
| --- | --- | --- |
| 100–123 | Basics | `state.dart`: players, objects, zones (400–408), counters (122), ownership/control (108), timestamps (613.7). Objects get a new id when they change zones (400.7). |
| 106, 605 | Mana, mana abilities | `mana.dart`: mana pool per player with typed mana (color, source restrictions later), emptied between steps. Mana abilities resolve immediately, never use the stack. Auto-payer finds a payment; the player may pick sources. |
| 107 | Numbers, symbols | `cards/mana_cost.dart`: generic, colored, hybrid, Phyrexian, snow, X. |
| 116–117 | Special actions, priority | `priority.dart`: APNAP priority passing; all pass in succession with empty stack → step ends; with an object → top resolves. Per-player **stops** live in the state (set by actions), so automatic passing is deterministic and the same on every device. |
| 500–514 | Turn structure | `turn.dart`: phases and steps, untap (502), upkeep, draw (504), main, combat steps, end, cleanup (514: discard, damage wears off, "until end of turn" ends; repeats if needed). Extra turns/phases later. |
| 506–511 | Combat | `combat.dart`: attack declarations (players, planeswalkers, battles), requirements/restrictions (menace, can't block, flying/reach, defender), blocks incl. multiple blockers, first/double strike damage steps, trample, deathtouch-lethal, damage assignment among blockers as the attacker chooses (current rules: no damage assignment order), lifelink, banding never. |
| 601–602 | Casting, activating | `cast.dart`: the 601.2 sequence (announce, modes, splice/additional/alternative costs, X, targets, divide, total cost with increases/reductions/locks, mana abilities, pay). Any illegal step rewinds (723-style restore). |
| 603 | Triggered abilities | `triggers.dart`: an event bus; triggers waiting to go on the stack are put there next time a player would get priority, APNAP, the controller ordering their own. Leaves-the-battlefield triggers "look back" (603.10) using last known information. Intervening-if checked twice. Delayed and reflexive triggers. |
| 604, 611–613 | Static abilities, continuous effects | `layers.dart`: characteristics are computed, never stored: copiable values (layer 1), control (2), text (3), type (4), color (5), abilities (6), P/T (7a–7d), in timestamp order with dependency (613.8) for the cases cards need. Effects from resolved spells lock their affected set (611.2c). |
| 608 | Resolving | `resolve.dart`: targets rechecked; fizzles if all illegal; effect IR interpreted step by step. |
| 614–616 | Replacement and prevention | `replace.dart`: every event that can be replaced (zone change, draw, damage, life gain/loss, counters, tokens, ETB tapped/with counters) goes through one pipeline; each effect applies once per event; the affected player/controller orders them (616.1). |
| 700–701 | Keyword actions | `effects.dart`: destroy, exile, sacrifice, scry, surveil, mill, fight, create tokens, investigate, explore, proliferate, amass, connive, discover, … |
| 702 | Keyword abilities | `keywords.dart`: evergreen keywords as static data read by combat and the layers; costed keywords (kicker, flashback, cycling, equip, ward, …) compile to IR abilities. |
| 704 | State-based actions | `sba.dart`: all of 704.5 in a loop until none apply, then triggers. |
| 706–712 | Copies, face-down, DFC, split, flip, adventure, meld, prototype | `cards/faces.dart` + layer 1: a card has faces; which face is up is status; copies use copiable values. |
| 714–717 | Sagas, classes, rooms (attractions later) | Lore counters / class levels / unlocked doors as counters/status; chapter triggers from IR. |
| 306, 310 | Planeswalkers, battles | Loyalty abilities (once per turn, sorcery speed), damage removes loyalty/defense; battle protector. |
| 103, 903 | Starting the game, mulligans, Commander | `start.dart`: London/classic/free mulligan options from MagicTrek, play/draw, commander zone, tax, color identity, 40 life, commander damage. |
| 800–806 | Multiplayer | N players in seat order, APNAP everywhere, leaving the game (800.4), attack-left/right options later. |

### The ability IR

Oracle text compiles to data, not code: `Ability` = kind (spell / activated / triggered / static /
mana / replacement / keyword) + `Cost` + `TargetSpec`s + `Effect` tree + conditions. Effects are
small sealed classes (`DealDamage(amount, to)`, `Draw(n, who)`, `CreateToken(spec, n)`,
`ModifyPT(+x,+y, duration, filter)`, `Sequence`, `Optional`, `Choose(modes)`,
`IfThen(condition)`, …) interpreted by `effects.dart`. Quantities (`Amount`) and object filters
(`Filter`) are data too, so "each creature you control with power 2 or less" is one filter.

### Choices without callbacks

When the engine needs a decision mid-resolution it records a `Decision` (who, what, options) and
stops. The next action must answer it. Resolution is re-run from a snapshot with the answers so far,
so effects never need to be written as state machines, and the log stays a flat list of actions.

### Coverage

The parser splits oracle text into abilities and must consume every one completely. Anything it
can't is recorded verbatim. A card is **supported** only if nothing is left over and every layout
feature it uses is implemented. `dart run rules:cards coverage` prints per set and per format;
CI publishes `coverage.json` with the site and fails if coverage of the milestone pool drops.
Unsupported cards can be viewed (with the unhandled text highlighted) but not played in rated or
online games.

## 3. Card data pipeline

- **Source**: Scryfall bulk data (`oracle_cards` and `default_cards`, JSONL), downloaded by
  `tools/build_card_db.py` (CI job `card-data`, weekly or by hand). Scryfall guidelines: a
  `User-Agent`, at most ~10 API requests a second, bulk files for everything bulk.
- **Output** (`build/data/`, published with the site under `/data/`, and bundled for offline):
  - `cards.json` — one row per oracle card: name, faces (cost, type line, oracle text, P/T,
    loyalty, defense), colors, identity, keywords, layout, legalities as a compact code string,
    produced mana, the default printing's Scryfall id, and the list of set codes. Columnar,
    gzip ≈ 3–4 MB.
  - `printings.json` — every printing (set, number, rarity, Scryfall id, artist), fetched only
    when you browse printings.
  - `sets.json` — set names, dates, types, for the theme picker and coverage tables.
  - `manifest.json` — data version, Scryfall timestamp, engine version used for coverage. The app
    checks it on launch and downloads newer data in the background.
- **Images** are never bundled: `cards.scryfall.io` URLs are built from the Scryfall id and cached
  (browser HTTP cache on web, a file cache on phones). Card images are shown whole, never cropped,
  so the artist and copyright line stay visible; art crops are only used where Scryfall offers them
  as `art_crop` with the artist credited next to it.

## 4. Theme system

`lib/theme/` defines `GameTheme`: palette (surfaces, accents, mana colors, text), typography
(Google Fonts-free bundled fonts or system fonts), **chrome** (how panels, buttons, headers and the
card frame overlay are drawn — a small painter interface), a **table backdrop** painter, and a
**sound set**. A theme is picked from the deck's main set (`setThemes` maps set codes and
universes) or forced in Settings.

First themes, each inspired by its setting and drawn from scratch (no logos, fonts or trade dress):

| Theme | For | Look |
| --- | --- | --- |
| Starship console | Star Trek (`trk`, `trc`) | MagicTrek's LCARS-style elbows, pills and starfield, ported |
| Classic | everything else | parchment and dark wood, mana-colour accents |
| Crystal | Final Fantasy (`fin`, `fic`) | deep blue menus with white-bordered windows, crystal glints |
| Four elements | Avatar (`tla`, `tle`) | ink-wash paper, four element accents |
| Web-slinger | Spider-Man (`spm`) | halftone comic panels, bold outlines |

## 5. Milestones

**M1 — Playable foundation (this stage).**
- Plan (this file), repo, CI, Pages with the landing page and the web build under `/play/`.
- Engine core across the CR areas above, enough for the milestone pool: Foundations (FDN) cards the
  parser fully supports, plus basic lands, as a cube and as starter decks.
- Two-player games: vs the computer, pass-and-play, and device-to-device over relays (web and
  phones); LAN and Bluetooth on phones.
- Card database screen with coverage per set and format; coverage report in CI.
- Tests per rules area, chaos harness, widget tests, phone-size screenshots.

**M2 — Widen the core.** All remaining FDN cards, then Standard sets one at a time
(Duskmourn, Bloomburrow, Aetherdrift, Tarkir: Dragonstorm, Edge of Eternities…), each mechanic
with tests. Deck builder with format legality for every format. Full replacement/prevention and
layer dependencies. Android and iOS releases (signed APK + in-app updater, TestFlight).

**M3 — Multiplayer and Commander.** N-player games, command zone, commander tax and damage,
2–4 players over relays, Commander precons.

**M4 — Every card, as far as it goes.** Older sets by mechanic family (DFCs, split, adventure,
flip, meld, sagas, classes, rooms, battles, planeswalkers…). Pioneer → Modern → Legacy/Vintage
pools; Pauper; cube and Limited (draft with bots).

**M5 — Polish.** Stronger computer player (search on top of heuristics), more themes, sounds,
tutorial per theme, accessibility.

## 6. Legal

Fan content under the Wizards of the Coast Fan Content Policy: free, no paywall, no ads. The app
and the site say "OpenMTG is unofficial Fan Content permitted under the Fan Content Policy. Not
approved/endorsed by Wizards. Portions of the materials used are property of Wizards of the
Coast. ©Wizards of the Coast LLC." Card data and images come from Scryfall, credited on every
screen that shows them. Forge (GPL-3) may be read for ideas only; no GPL code is copied unless
the project is relicensed. XMage (MIT) code may be reused with attribution in `NOTICE`.

## 7. Working rules

- The app version stays at 1.0.0 until the owner changes it.
- The word "build" (or `*u`) in a commit subject starts TestFlight and Android releases; it is
  only used when a build is asked for.
- Every rules change comes with a test; the chaos harness runs before every push.
