/*
 *     Ongaku — an Apple Music style edition of Musify.
 *     Based on Musify, Copyright (C) 2026 Valeri Gokadze.
 *
 *     This program is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version. See <https://www.gnu.org/licenses/>.
 */

import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/main.dart';
import 'package:musify/models/position_data.dart';
import 'package:musify/ongaku/l10n/ongaku_strings.dart';
import 'package:musify/ongaku/lyrics/synced_lyrics.dart';
import 'package:musify/widgets/spinner.dart';

/// Apple Music style lyrics: the line being sung is bright and kept in view,
/// the others are dimmed. Tapping a line jumps to it.
class SyncedLyricsView extends StatelessWidget {
  const SyncedLyricsView({
    super.key,
    this.fontSize = 30,
    this.padding = const EdgeInsets.fromLTRB(28, 24, 28, 24),
  });

  final double fontSize;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MediaItem?>(
      stream: audioHandler.mediaItem,
      initialData: audioHandler.mediaItem.valueOrNull,
      builder: (context, snapshot) {
        final item = snapshot.data;
        if (item == null) return const SizedBox.shrink();
        return _LyricsLoader(
          key: ValueKey(item.id),
          item: item,
          fontSize: fontSize,
          padding: padding,
        );
      },
    );
  }
}

class _LyricsLoader extends StatefulWidget {
  const _LyricsLoader({
    super.key,
    required this.item,
    required this.fontSize,
    required this.padding,
  });

  final MediaItem item;
  final double fontSize;
  final EdgeInsets padding;

  @override
  State<_LyricsLoader> createState() => _LyricsLoaderState();
}

class _LyricsLoaderState extends State<_LyricsLoader> {
  late final Future<TimedLyrics?> _future = fetchTimedLyrics(widget.item);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<TimedLyrics?>(
      future: _future,
      builder: (context, snapshot) {
        final Widget child;
        if (snapshot.connectionState != ConnectionState.done) {
          child = const Center(key: ValueKey('wait'), child: Spinner());
        } else if (snapshot.data == null || snapshot.data!.lines.isEmpty) {
          child = Center(
            key: const ValueKey('none'),
            child: Text(
              context.l10n?.lyricsNotAvailable ?? 'Lyrics not available',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          );
        } else {
          child = _LyricsLines(
            key: const ValueKey('lines'),
            lyrics: snapshot.data!,
            fontSize: widget.fontSize,
            padding: widget.padding,
          );
        }
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          child: child,
        );
      },
    );
  }
}

class _LyricsLines extends StatefulWidget {
  const _LyricsLines({
    super.key,
    required this.lyrics,
    required this.fontSize,
    required this.padding,
  });

  final TimedLyrics lyrics;
  final double fontSize;
  final EdgeInsets padding;

  @override
  State<_LyricsLines> createState() => _LyricsLinesState();
}

class _LyricsLinesState extends State<_LyricsLines> {
  final _scroll = ScrollController();
  late final List<GlobalKey> _keys = List.generate(
    widget.lyrics.lines.length,
    (_) => GlobalKey(),
  );
  StreamSubscription<PositionData>? _position;
  int _current = -1;
  DateTime _userScrolledAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _position = audioHandler.positionDataStream.listen(
      (data) => _onPosition(data.position),
    );
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _onPosition(audioHandler.currentPositionData.position),
    );
  }

  void _onPosition(Duration position) {
    // A small lead makes the highlight land with the voice, not after it.
    final index = widget.lyrics.indexAt(
      position + const Duration(milliseconds: 250),
    );
    if (index == _current || !mounted) return;
    setState(() => _current = index);
    _follow(index);
  }

  void _follow(int index, {bool force = false}) {
    if (index < 0) return;
    final idle = DateTime.now().difference(_userScrolledAt);
    if (!force && idle < const Duration(seconds: 4)) return;
    final context = _keys[index].currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      alignment: 0.32,
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _position?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lyrics = widget.lyrics;
    final strings = OngakuStrings.of(context);

    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n is UserScrollNotification) _userScrolledAt = DateTime.now();
        return false;
      },
      child: ShaderMask(
        // Lines fade out at the top and bottom edges, like Apple Music.
        shaderCallback: (rect) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.white,
            Colors.white,
            Colors.transparent,
          ],
          stops: [0, 0.08, 0.86, 1],
        ).createShader(rect),
        blendMode: BlendMode.dstIn,
        child: SingleChildScrollView(
          controller: _scroll,
          padding: widget.padding.copyWith(
            top: widget.padding.top + 120,
            bottom: widget.padding.bottom + 260,
          ),
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < lyrics.lines.length; i++)
                _LyricLineTile(
                  key: _keys[i],
                  text: lyrics.lines[i].text,
                  active: i == _current,
                  distance: _current < 0 ? 3 : (i - _current).abs(),
                  fontSize: widget.fontSize,
                  onTap: lyrics.synced
                      ? () {
                          audioHandler.seek(lyrics.lines[i].time);
                          _userScrolledAt = DateTime.fromMillisecondsSinceEpoch(
                            0,
                          );
                        }
                      : null,
                ),
              if (!lyrics.synced)
                Padding(
                  padding: const EdgeInsets.only(top: 28),
                  child: Text(
                    strings.lyricsApproximate,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LyricLineTile extends StatelessWidget {
  const _LyricLineTile({
    super.key,
    required this.text,
    required this.active,
    required this.distance,
    required this.fontSize,
    this.onTap,
  });

  final String text;
  final bool active;
  final int distance;
  final double fontSize;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isPause = text.isEmpty;
    final opacity = active ? 1.0 : (distance == 1 ? 0.42 : 0.3);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: fontSize * 0.32),
        child: AnimatedScale(
          scale: active ? 1 : 0.96,
          alignment: Alignment.centerLeft,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOutCubic,
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOutCubic,
            style: TextStyle(
              fontFamily: 'Inter',
              color: Colors.white.withValues(alpha: opacity),
              fontSize: fontSize,
              height: 1.18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
            ),
            child: Text(isPause ? '• • •' : text),
          ),
        ),
      ),
    );
  }
}
