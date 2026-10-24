# OpenMTG

A free, fan-made Magic: The Gathering game: every card from Scryfall, a rules engine built on
the Comprehensive Rules, and a visual theme for each set or universe. One Flutter codebase for
the browser (GitHub Pages), Android and iOS. It grew out of
[MagicTrek](https://github.com/coral-coder/magictrek).

- Play in the browser: <https://coral-coder.github.io/openmtg/play/> (once Pages is on)
- The plan, architecture and milestones: [docs/PLAN.md](docs/PLAN.md)

## Layout

| Path | What |
| --- | --- |
| `packages/tcg_core/` | What every card game shares: the match contract (a seed plus moves, with a fingerprint that's the same on every platform), the seeded generator and the stable sort. |
| `packages/tcg_app/` | The game-independent app shell: lockstep networking (Nostr relays, Wi‑Fi, Bluetooth), the shared match session, themes and their fonts, synthesized sounds, notifications, the Android self-updater. |
| `packages/mtg_ui/` | The Magic app on that shell: title, menu, table, decks, card database, settings, store; plus the bundled card pool (`assets/data/pool.json`). |
| `packages/rules/` | The rules engine, pure Dart and deterministic. `lib/src/game/` is organised by CR area, `lib/src/oracle/` turns oracle text into the ability IR, `lib/src/ai/` is the computer player. |
| `packages/rules/bin/build_db.dart` | Scryfall bulk data → `cards.json`, `printings.json`, `coverage.json`, `manifest.json`. |
| `packages/rules/bin/chaos.dart` | Plays hundreds of bot games and replays each from its log, comparing fingerprints. |
| `packages/rules/bin/cards.dart` | Coverage of one set, or one card's parse: `dart run bin/cards.dart test/fixtures/fdn.json "Llanowar Elves"`. |
| `lib/main.dart` | OpenMTG itself: runs the Magic app from `mtg_ui`. |
| `site/` | The landing page; the web build goes under `/play/`, the card data under `/data/`. |
| `tools/fetch_scryfall.sh` | Downloads Scryfall's bulk files politely. |

## Working on it

    flutter pub get
    (cd packages/rules && dart test && dart run bin/chaos.dart --games 200)
    flutter test                      # widget tests; phone-size screenshots land in build/screenshots/
    flutter run -d chrome

    # The card database from Scryfall (about 105 MB of downloads):
    tools/fetch_scryfall.sh .scryfall-cache
    (cd packages/rules && dart run bin/build_db.dart --oracle ../../.scryfall-cache/oracle-cards.jsonl.gz \
        --default ../../.scryfall-cache/default-cards.jsonl.gz --out ../../build/data)

App id: `com.lightwave.openmtg.app` (Android and iOS). Version 1.0.0.

## Releases

The word **build** in a commit subject (or `*u`) releases both platforms from that commit;
`*b` archives iOS without uploading. A `v*` tag also releases.

- `.github/workflows/android-release.yml`: signed APK as a GitHub Release with `OpenMTG.apk` and
  `update.json`; installed copies update themselves from it.
- `.github/workflows/ios-testflight.yml`: archives with cloud signing and uploads to TestFlight.
- `.github/workflows/pages.yml`: the website, the browser game and the card data, on pushes to
  main and weekly.
- `.github/workflows/flutter-ci.yml`: engine tests, chaos harness, coverage floor, analyzer,
  widget tests and a web build on every branch and pull request.

## Setting up the repository

**GitHub Pages**: Settings → Pages → Source: *GitHub Actions*. The `github-pages` environment
deploys from `main`.

**iOS / TestFlight**: run *Actions → Set up app repo* in `Coral-coder/Dev_deploy_setup` with
`repos = openmtg` (its `SECRETS_TOKEN` must include this repository). That copies
`APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (required) and the optional ones.
Then register the app: either add `APPLE_ID` and `FASTLANE_SESSION` (from
`fastlane spaceauth -u you@example.com`) so the workflow creates the App Store Connect record,
or create it once by hand (Apps → + → New App, bundle ID `com.lightwave.openmtg.app`, name
OpenMTG). Optional repository variables: `BUNDLE_ID`, `APP_NAME`, `APP_SKU`.

**Android signing** (so every release can update the last one in place), either:
- add a `SECRETS_TOKEN` secret (a classic token with `repo`, or fine-grained with *Secrets: read
  and write* on this repo): the first release creates a keystore and stores
  `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`,
  `ANDROID_KEY_PASSWORD`, attaching an encrypted backup to the run; or
- set those four secrets yourself from a key made with
  `keytool -genkeypair -keystore openmtg.jks -storetype PKCS12 -alias openmtg -keyalg RSA -keysize 2048 -validity 36500`.

Workflows need read and write permissions (Settings → Actions → General → Workflow
permissions) for publishing releases.

## Legal

OpenMTG is unofficial Fan Content permitted under the Fan Content Policy. Not approved/endorsed
by Wizards. Portions of the materials used are property of Wizards of the Coast. ©Wizards of the
Coast LLC. Card data and images courtesy of [Scryfall](https://scryfall.com); images are shown
whole, never cropped. Free, no ads, nothing to buy. The themes are fan tributes inspired by their
settings, drawn from scratch, and not affiliated with their owners.
