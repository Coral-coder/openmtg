import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:rules/rules.dart';

import '../app/platform/files.dart';
import '../theme/theme.dart';

/// Card images come from Scryfall's image CDN on demand and are cached (the browser's cache on
/// the web, a file cache on phones). They are always shown whole, so the artist credit and the
/// copyright line stay visible (Scryfall's image guidelines).
class ScryfallImage extends ImageProvider<ScryfallImage> {
  const ScryfallImage(this.url);
  final String url;

  static int _inFlight = 0;
  static final _queue = <Completer<void>>[];

  @override
  Future<ScryfallImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(ScryfallImage key, ImageDecoderCallback decode) => MultiFrameImageStreamCompleter(codec: _load(decode), scale: 1);

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final name = 'img/${Uri.parse(url).pathSegments.skip(1).join('_')}';
    var bytes = await readCacheBytes(name);
    if (bytes == null) {
      // A few downloads at a time: polite to the CDN and kind to phones.
      while (_inFlight >= 6) {
        final c = Completer<void>();
        _queue.add(c);
        await c.future;
      }
      _inFlight++;
      try {
        final r = await http.get(Uri.parse(url));
        if (r.statusCode != 200) throw StateError('HTTP ${r.statusCode}');
        bytes = r.bodyBytes;
        unawaited(writeCacheBytes(name, bytes));
      } finally {
        _inFlight--;
        if (_queue.isNotEmpty) _queue.removeAt(0).complete();
      }
    }
    return decode(await ui.ImmutableBuffer.fromUint8List(Uint8List.fromList(bytes)));
  }

  @override
  bool operator ==(Object other) => other is ScryfallImage && other.url == url;
  @override
  int get hashCode => url.hashCode;
}

ImageProvider cardImageProvider(String url) => kIsWeb ? NetworkImage(url) : ScryfallImage(url);

/// The card's image, or a drawn frame while it loads, offline, or for tokens.
class CardPicture extends StatelessWidget {
  const CardPicture({super.key, required this.def, this.chars, this.size = 'normal', this.width, this.back = false});
  final CardDef? def;
  final Chars? chars;
  final String size;
  final double? width;
  final bool back;

  @override
  Widget build(BuildContext context) {
    final url = def?.imageUrl(size: size, back: back) ?? '';
    final frame = TextCardFrame(def: def, chars: chars);
    if (url.isEmpty) return frame;
    return Image(
      image: cardImageProvider(url),
      fit: BoxFit.contain,
      gaplessPlayback: true,
      frameBuilder: (context, child, frameNo, sync) => frameNo == null && !sync ? frame : child,
      errorBuilder: (context, e, st) => frame,
    );
  }
}

/// A card drawn from its text, in the theme's colors (tokens, loading, offline).
class TextCardFrame extends StatelessWidget {
  const TextCardFrame({super.key, this.def, this.chars});
  final CardDef? def;
  final Chars? chars;

  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final c = chars;
    final name = c?.name ?? def?.name ?? '';
    final cost = c?.manaCost?.text ?? def?.front.manaCost?.text ?? '';
    final type = c == null ? (def?.front.typeLine ?? '') : _typeLine(c);
    final text = def?.front.oracleText ?? (c == null ? '' : c.abilities.map((a) => a.text).where((s) => s.isNotEmpty).join('\n'));
    final colors = c?.colors ?? def?.front.colors.toSet() ?? const {};
    final frameColor = colors.length == 1 ? t.manaColor(colors.first.symbol) : (colors.length > 1 ? const Color(0xFFD8B65A) : const Color(0xFFB9B4AA));
    final pt = c?.power != null ? '${c!.power}/${c.toughness}' : ((def?.front.power != null) ? '${def!.front.power}/${def!.front.toughness}' : null);
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth.isFinite ? box.maxWidth : 120.0;
      final s = (w / 120).clamp(0.4, 3.0);
      return Container(
        decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(6 * s)),
        padding: EdgeInsets.all(4 * s),
        child: Container(
          decoration: BoxDecoration(color: Color.lerp(frameColor, Colors.white, 0.55), borderRadius: BorderRadius.circular(4 * s), border: Border.all(color: frameColor, width: 2 * s)),
          padding: EdgeInsets.all(3 * s),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(name, style: TextStyle(fontSize: 9.5 * s, fontWeight: FontWeight.w800, color: Colors.black), maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (cost.isNotEmpty) ManaPips(cost, size: 9 * s),
            ]),
            SizedBox(height: 2 * s),
            Expanded(flex: 5, child: Container(decoration: BoxDecoration(color: Color.lerp(frameColor, Colors.black, 0.25), borderRadius: BorderRadius.circular(2 * s)))),
            SizedBox(height: 2 * s),
            Text(type, style: TextStyle(fontSize: 7.5 * s, fontWeight: FontWeight.w700, color: Colors.black), maxLines: 1, overflow: TextOverflow.ellipsis),
            SizedBox(height: 2 * s),
            Expanded(
              flex: 5,
              child: Container(
                padding: EdgeInsets.all(2 * s),
                color: const Color(0xFFF7F2E4),
                child: Text(text, style: TextStyle(fontSize: 7 * s, color: Colors.black, height: 1.15), overflow: TextOverflow.fade),
              ),
            ),
            if (pt != null)
              Align(
                alignment: Alignment.centerRight,
                child: Container(
                  margin: EdgeInsets.only(top: 2 * s),
                  padding: EdgeInsets.symmetric(horizontal: 4 * s, vertical: 1 * s),
                  decoration: BoxDecoration(color: const Color(0xFFF7F2E4), borderRadius: BorderRadius.circular(3 * s), border: Border.all(color: frameColor)),
                  child: Text(pt, style: TextStyle(fontSize: 9 * s, fontWeight: FontWeight.w900, color: Colors.black)),
                ),
              ),
          ]),
        ),
      );
    });
  }

  static String _typeLine(Chars c) {
    final l = [...c.supertypes.map((s) => s.label), ...c.types.map((t) => t.label)].join(' ');
    return c.subtypes.isEmpty ? l : '$l — ${c.subtypes.join(' ')}';
  }
}
