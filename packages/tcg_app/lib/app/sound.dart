import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

import '../theme/theme.dart';

enum Fx {
  tap, confirm, deny, draw, attack, damage, alert, victory, defeat, chirp,
  /// A spell flies to the stack.
  cast,
  /// A land is put down.
  land,
  /// A permanent arrives on the battlefield.
  summon,
  /// A creature dies or a permanent is put into a graveyard.
  dies,
  /// A player gains life.
  heal,
  /// A player loses life.
  hit,
  /// A new turn begins.
  turn,
  /// Blockers are declared.
  block,
  /// The title screen's opening chord.
  title,
}

/// Haptics and short synthesized sounds in the current theme's style (so no audio files are
/// needed): console beeps for the starship, bells for the classic table, chiptune squares for
/// the comic theme.
class Console {
  Console._();
  static final Console shared = Console._();
  bool soundOn = true, hapticsOn = true;
  SoundStyle _style = const SoundStyle();

  /// Switches the sound set (regenerates the waves).
  void setStyle(SoundStyle s) {
    if (s.wave == _style.wave && s.base == _style.base) return;
    _style = s;
    for (final fx in Fx.values) {
      _waves[fx] = _wave(fx, s);
    }
  }
  final Map<Fx, Uint8List> _waves = {};
  final List<AudioPlayer> _players = [];
  int _next = 0;

  /// Off in widget tests (no audio plugin there).
  static bool available = true;

  Future<void> init() async {
    if (!available) return;
    for (final fx in Fx.values) {
      _waves[fx] = _wave(fx, _style);
    }
    for (var i = 0; i < 6; i++) {
      try {
        final p = AudioPlayer();
        await p.setReleaseMode(ReleaseMode.stop);
        await p.setVolume(0.5);
        _players.add(p);
      } catch (_) {
        break; // no audio on this platform (tests)
      }
    }
  }

  /// Plays [fx] after [ms] milliseconds (to spread out a burst of sounds).
  void playAfter(Fx fx, int ms) {
    if (_players.isEmpty || !soundOn) return;
    if (ms <= 0) return play(fx);
    Future.delayed(Duration(milliseconds: ms), () => play(fx));
  }

  void play(Fx fx) {
    if (soundOn && _players.isNotEmpty) {
      final p = _players[_next++ % _players.length];
      final bytes = _waves[fx];
      if (bytes != null) p.play(BytesSource(bytes, mimeType: 'audio/wav')).catchError((_) {});
    }
    if (!hapticsOn) return;
    switch (fx) {
      case Fx.tap:
      case Fx.draw:
      case Fx.chirp:
      case Fx.cast:
      case Fx.land:
      case Fx.summon:
      case Fx.heal:
      case Fx.turn:
      case Fx.title:
        HapticFeedback.lightImpact();
      case Fx.attack:
      case Fx.damage:
      case Fx.hit:
      case Fx.dies:
      case Fx.block:
        HapticFeedback.heavyImpact();
      case Fx.confirm:
      case Fx.victory:
        HapticFeedback.mediumImpact();
      case Fx.deny:
      case Fx.defeat:
      case Fx.alert:
        HapticFeedback.vibrate();
    }
  }

  /// A short sound as 16-bit mono WAV: tones that may slide in pitch, with optional noise
  /// (impacts, whooshes) and a faint echo, shaped by the theme's [SoundStyle].
  static Uint8List _wave(Fx fx, SoundStyle style) {
    const rate = 22050.0;
    final k = style.base / 1320;
    // (start Hz, end Hz, seconds, noise 0..1)
    final notes = switch (fx) {
      Fx.tap => [(1400.0, 1400.0, 0.03, 0.0)],
      Fx.chirp => [(1800.0, 1800.0, 0.03, 0.0), (2400.0, 2400.0, 0.04, 0.0)],
      Fx.confirm => [(900.0, 900.0, 0.05, 0.0), (1300.0, 1300.0, 0.07, 0.0)],
      Fx.deny => [(400.0, 400.0, 0.08, 0.0), (300.0, 300.0, 0.1, 0.0)],
      Fx.draw => [(900.0, 1700.0, 0.07, 0.35)],
      Fx.attack => [(500.0, 900.0, 0.06, 0.2), (900.0, 1300.0, 0.06, 0.2), (1300.0, 1700.0, 0.1, 0.1)],
      Fx.damage => [(220.0, 90.0, 0.16, 0.5)],
      Fx.alert => [(880.0, 880.0, 0.12, 0.0), (660.0, 660.0, 0.12, 0.0), (880.0, 880.0, 0.12, 0.0)],
      Fx.victory => [(660.0, 660.0, 0.1, 0.0), (880.0, 880.0, 0.1, 0.0), (1100.0, 1100.0, 0.1, 0.0), (1320.0, 1320.0, 0.4, 0.0)],
      Fx.defeat => [(500.0, 480.0, 0.15, 0.0), (400.0, 380.0, 0.15, 0.0), (300.0, 200.0, 0.45, 0.1)],
      Fx.cast => [(600.0, 1800.0, 0.14, 0.45), (1500.0, 1500.0, 0.08, 0.0)],
      Fx.land => [(160.0, 80.0, 0.12, 0.35)],
      Fx.summon => [(660.0, 660.0, 0.06, 0.0), (990.0, 990.0, 0.06, 0.0), (1320.0, 1320.0, 0.16, 0.0)],
      Fx.dies => [(700.0, 120.0, 0.28, 0.6)],
      Fx.heal => [(880.0, 1320.0, 0.12, 0.0), (1320.0, 1760.0, 0.16, 0.0)],
      Fx.hit => [(300.0, 110.0, 0.14, 0.55)],
      Fx.turn => [(660.0, 660.0, 0.08, 0.0), (880.0, 880.0, 0.14, 0.0)],
      Fx.block => [(400.0, 260.0, 0.1, 0.4), (260.0, 260.0, 0.06, 0.2)],
      Fx.title => [(440.0, 440.0, 0.12, 0.0), (660.0, 660.0, 0.12, 0.0), (880.0, 880.0, 0.12, 0.0), (1320.0, 1320.0, 0.55, 0.0)],
    };
    var samples = <double>[];
    var seed = 12345; // fixed noise, so every play of a sound is the same
    double noise() {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      return seed / 0x3fffffff - 1;
    }

    for (final (f0, f1, d, nz) in notes) {
      final n = (rate * d * (style.decay / 0.1).clamp(0.6, 2.5)).round();
      var ph = 0.0;
      for (var i = 0; i < n; i++) {
        final u = i / n;
        final f = (f0 + (f1 - f0) * u) * k;
        ph += 2 * math.pi * f / rate;
        final env = math.min(1.0, i / 200) * math.min(1.0, (n - i) / 400);
        final tone = switch (style.wave) {
          'square' => math.sin(ph) >= 0 ? 0.6 : -0.6,
          'triangle' => 2 / math.pi * math.asin(math.sin(ph)),
          'bell' => (math.sin(ph) + 0.4 * math.sin(2.76 * ph)) * math.exp(-4 * u),
          _ => math.sin(ph) + 0.15 * math.sin(2 * ph),
        };
        samples.add(((1 - nz) * tone + nz * noise() * (1 - u)) * env);
      }
    }
    // A faint echo makes the short blips sound less dry.
    const echo = (rate * 0.07) ~/ 1;
    final wet = List<double>.filled(samples.length + echo * 2, 0);
    for (var i = 0; i < samples.length; i++) {
      wet[i] += samples[i];
      wet[i + echo] += samples[i] * 0.28;
      wet[i + echo * 2] += samples[i] * 0.1;
    }
    samples = wet;
    final pcm = [for (final v in samples) (v * 10000).round().clamp(-32767, 32767)];
    final byteCount = pcm.length * 2;
    final b = BytesBuilder();
    void put32(int v) => b.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
    void put16(int v) => b.add([v & 0xFF, (v >> 8) & 0xFF]);
    b.add('RIFF'.codeUnits);
    put32(36 + byteCount);
    b.add('WAVE'.codeUnits);
    b.add('fmt '.codeUnits);
    put32(16);
    put16(1);
    put16(1);
    put32(rate.toInt());
    put32(rate.toInt() * 2);
    put16(2);
    put16(16);
    b.add('data'.codeUnits);
    put32(byteCount);
    for (final s in pcm) {
      put16(s & 0xFFFF);
    }
    return b.toBytes();
  }
}
