/*
 *     Ongaku — an Apple Music style edition of Musify.
 *     Based on Musify, Copyright (C) 2026 Valeri Gokadze.
 *
 *     This program is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version. See <https://www.gnu.org/licenses/>.
 */

import 'dart:ui' show ImageFilter;

import 'package:audio_service/audio_service.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/main.dart';
import 'package:musify/ongaku/layout/adaptive.dart';
import 'package:musify/services/common_services.dart' show getSongLyrics;
import 'package:musify/utilities/artwork_provider.dart';
import 'package:musify/widgets/flip_card.dart';
import 'package:musify/widgets/now_playing/bottom_actions_row.dart';
import 'package:musify/widgets/now_playing/now_playing_artwork.dart';
import 'package:musify/widgets/now_playing/now_playing_controls.dart';
import 'package:musify/widgets/position_slider.dart';
import 'package:musify/widgets/queue_list_view.dart';
import 'package:musify/widgets/song_artwork.dart';

/// Opens the full screen player as an Apple Music style card sliding up.
Future<void> openOngakuNowPlaying(BuildContext context) {
  final isPanel = _usesSidePanel(MediaQuery.sizeOf(context));
  return Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 460),
      reverseTransitionDuration: const Duration(milliseconds: 340),
      pageBuilder: (context, animation, _) => const OngakuNowPlayingPage(),
      transitionsBuilder: (context, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutQuart,
          reverseCurve: Curves.easeInCubic,
        );
        return SlideTransition(
          position: Tween(
            begin: isPanel ? const Offset(1, 0) : const Offset(0, 1),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    ),
  );
}

/// Wide and tall enough (tablets, unfolded foldables, desktops): the player
/// is a panel on the right and the app stays visible on the left, where the
/// lyrics open full height. Phones keep the full screen player.
bool _usesSidePanel(Size size) => size.width >= 600 && size.height >= 520;

/// Full screen player. Reuses upstream's player widgets (artwork + lyrics,
/// title, seek bar, controls, actions, queue) so their behaviour follows
/// Musify updates, and only restyles them through a "glass" theme on top of
/// a blurred artwork background.
class OngakuNowPlayingPage extends StatefulWidget {
  const OngakuNowPlayingPage({super.key});

  @override
  State<OngakuNowPlayingPage> createState() => _OngakuNowPlayingPageState();
}

class _OngakuNowPlayingPageState extends State<OngakuNowPlayingPage>
    with SingleTickerProviderStateMixin {
  final _lyricsController = FlipCardController();
  late final _lyricsToggle = _LyricsToggle(
    () => setState(() => _showLyrics = !_showLyrics),
  );
  bool _showLyrics = false;
  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  double _dragOffset = 0;

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset = (_dragOffset + details.delta.dy).clamp(0.0, 10000.0);
    });
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (_dragOffset > 140 || velocity > 900) {
      Navigator.of(context).pop();
      return;
    }
    final start = _dragOffset;
    final animation = Tween<double>(
      begin: start,
      end: 0,
    ).animate(CurvedAnimation(parent: _settle, curve: Curves.easeOutCubic));
    void tick() => setState(() => _dragOffset = animation.value);
    animation.addListener(tick);
    _settle.forward(from: 0).whenComplete(() => animation.removeListener(tick));
  }

  @override
  Widget build(BuildContext context) {
    final appTheme = Theme.of(context);
    final screenHeight = MediaQuery.sizeOf(context).height;
    final progress = (_dragOffset / screenHeight).clamp(0.0, 1.0);
    final radius = _dragOffset > 0 ? 28.0 : 0.0;

    if (_usesSidePanel(MediaQuery.sizeOf(context))) {
      return Theme(
        data: _glassTheme(appTheme),
        child: StreamBuilder<MediaItem?>(
          stream: audioHandler.mediaItem,
          initialData: audioHandler.mediaItem.valueOrNull,
          builder: (context, snapshot) {
            final metadata = snapshot.data;
            return Scaffold(
              backgroundColor: Colors.transparent,
              body: metadata == null
                  ? const Center(child: CircularProgressIndicator())
                  : _PanelLayout(
                      metadata: metadata,
                      showLyrics: _showLyrics,
                      lyricsToggle: _lyricsToggle,
                      onClose: () => Navigator.of(context).pop(),
                    ),
            );
          },
        ),
      );
    }

    return Theme(
      data: _glassTheme(appTheme),
      child: Transform.translate(
        offset: Offset(0, _dragOffset),
        child: Transform.scale(
          scale: 1 - progress * 0.08,
          child: ClipRSuperellipse(
            borderRadius: BorderRadius.circular(radius),
            child: StreamBuilder<MediaItem?>(
              stream: audioHandler.mediaItem,
              initialData: audioHandler.mediaItem.valueOrNull,
              builder: (context, snapshot) {
                final metadata = snapshot.data;
                return Scaffold(
                  backgroundColor: Colors.black,
                  body: Stack(
                    fit: StackFit.expand,
                    children: [
                      _ArtworkBackdrop(metadata: metadata),
                      SafeArea(
                        child: Column(
                          children: [
                            _Grabber(
                              onDragUpdate: _onDragUpdate,
                              onDragEnd: _onDragEnd,
                            ),
                            Expanded(
                              child: metadata == null
                                  ? const Center(
                                      child: CircularProgressIndicator(),
                                    )
                                  : GestureDetector(
                                      onVerticalDragUpdate: _onDragUpdate,
                                      onVerticalDragEnd: _onDragEnd,
                                      child: _PlayerLayout(
                                        metadata: metadata,
                                        lyricsController: _lyricsController,
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// White-on-color styling for upstream player widgets.
  ThemeData _glassTheme(ThemeData app) {
    const white = Colors.white;
    final scheme = app.colorScheme.copyWith(
      brightness: Brightness.dark,
      // Play button and active shuffle/repeat: white "pill" with dark glyph.
      primary: white,
      onPrimary: Colors.black,
      primaryContainer: white.withValues(alpha: 0.18),
      onPrimaryContainer: white,
      secondary: white,
      onSecondary: Colors.black,
      // Back of the artwork card (lyrics).
      secondaryContainer: Colors.black.withValues(alpha: 0.38),
      onSecondaryContainer: white,
      tertiaryContainer: white.withValues(alpha: 0.18),
      onTertiaryContainer: white,
      surface: const Color(0xFF1C1C1E),
      onSurface: white,
      onSurfaceVariant: white.withValues(alpha: 0.66),
      surfaceContainerLow: const Color(0xFF1C1C1E),
      surfaceContainer: const Color(0xFF1C1C1E),
      // Containers drawn behind controls disappear: glyphs float on the art.
      surfaceContainerHigh: Colors.transparent,
      surfaceContainerHighest: Colors.transparent,
      outlineVariant: white.withValues(alpha: 0.2),
      shadow: Colors.black,
    );

    return app.copyWith(
      brightness: Brightness.dark,
      colorScheme: scheme,
      iconTheme: const IconThemeData(color: white),
      textTheme: app.textTheme.apply(bodyColor: white, displayColor: white),
      dialogTheme: app.dialogTheme.copyWith(
        backgroundColor: const Color(0xFF2C2C2E),
      ),
      bottomSheetTheme: app.bottomSheetTheme.copyWith(
        backgroundColor: const Color(0xFF1C1C1E),
        dragHandleColor: white.withValues(alpha: 0.3),
      ),
      popupMenuTheme: app.popupMenuTheme.copyWith(
        color: const Color(0xFF2C2C2E),
      ),
      progressIndicatorTheme: app.progressIndicatorTheme.copyWith(color: white),
      sliderTheme: app.sliderTheme.copyWith(
        year2023: true,
        trackHeight: 6,
        activeTrackColor: white.withValues(alpha: 0.9),
        inactiveTrackColor: white.withValues(alpha: 0.25),
        thumbColor: white,
        thumbShape: const RoundSliderThumbShape(
          enabledThumbRadius: 0,
          elevation: 0,
          pressedElevation: 0,
        ),
        overlayShape: SliderComponentShape.noOverlay,
      ),
    );
  }
}

/// Blurred, enlarged artwork filling the screen (Apple Music ambient look).
class _ArtworkBackdrop extends StatelessWidget {
  const _ArtworkBackdrop({required this.metadata});

  final MediaItem? metadata;

  ImageProvider? _provider() {
    final item = metadata;
    if (item == null) return null;
    final artUri = item.artUri;
    String? source;
    if (artUri?.scheme == 'file') {
      final extrasPath = item.extras?['artWorkPath']?.toString();
      source = (extrasPath == null || extrasPath.isEmpty)
          ? artUri!.toFilePath()
          : extrasPath;
    } else {
      source = artUri?.toString();
    }
    if (source == null ||
        !(source.startsWith('http') || source.startsWith('/'))) {
      return null;
    }
    return ArtworkProvider.get(source);
  }

  @override
  Widget build(BuildContext context) {
    final provider = _provider();
    const fallback = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF4A4A52), Color(0xFF151518)],
        ),
      ),
    );

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 600),
      child: KeyedSubtree(
        key: ValueKey(metadata?.id),
        child: Stack(
          fit: StackFit.expand,
          children: [
            fallback,
            if (provider != null)
              ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
                child: Transform.scale(
                  scale: 1.6,
                  child: Image(
                    image: provider,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ),
            // Keeps white text readable on bright covers.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x40000000), Color(0x8C000000)],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Grabber extends StatelessWidget {
  const _Grabber({required this.onDragUpdate, required this.onDragEnd});

  final GestureDragUpdateCallback onDragUpdate;
  final GestureDragEndCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: MaterialLocalizations.of(context).closeButtonTooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).pop(),
        onVerticalDragUpdate: onDragUpdate,
        onVerticalDragEnd: onDragEnd,
        child: SizedBox(
          height: 30,
          width: double.infinity,
          child: Center(
            child: Container(
              width: 38,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Picks the arrangement for the current window and posture.
class _PlayerLayout extends StatelessWidget {
  const _PlayerLayout({required this.metadata, required this.lyricsController});

  final MediaItem metadata;
  final FlipCardController lyricsController;

  bool get _isLive => metadata.extras?['isLive'] ?? false;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final windowSize = windowSizeForWidth(size.width);
    final isWide = windowSize != WindowSize.compact;
    final standard = size.width > size.height * 1.05
        ? _sideBySide(context, size, isLargeScreen: false)
        : _portrait(context, size, isLargeScreen: false);

    // On foldables, keep the artwork and the controls on separate halves.
    return FoldAwareTwoPane(
      origin: Offset(padding.left, padding.top + 30),
      fallback: standard,
      first: _artworkPane(size, maxFraction: 0.9),
      second: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: _controlsPane(context, size, isLargeScreen: isWide),
      ),
    );
  }

  Widget _portrait(
    BuildContext context,
    Size size, {
    required bool isLargeScreen,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Expanded(flex: 5, child: _artworkPane(size)),
          if (!_isLive)
            Expanded(
              flex: 4,
              child: NowPlayingControls(
                size: size,
                audioId: metadata.extras?['ytid'],
                adjustedIconSize: _iconSize(size),
                adjustedMiniIconSize: _miniIconSize(size),
                metadata: metadata,
              ),
            ),
          _actions(size, isLargeScreen: isLargeScreen),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _sideBySide(
    BuildContext context,
    Size size, {
    required bool isLargeScreen,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        children: [
          Expanded(flex: 5, child: _artworkPane(size)),
          const SizedBox(width: 24),
          Expanded(
            flex: 5,
            child: _controlsPane(context, size, isLargeScreen: isLargeScreen),
          ),
        ],
      ),
    );
  }

  Widget _controlsPane(
    BuildContext context,
    Size size, {
    required bool isLargeScreen,
  }) {
    return Column(
      children: [
        if (!_isLive)
          Expanded(
            child: NowPlayingControls(
              size: size,
              audioId: metadata.extras?['ytid'],
              adjustedIconSize: _iconSize(size),
              adjustedMiniIconSize: _miniIconSize(size),
              metadata: metadata,
            ),
          )
        else
          const Spacer(),
        _actions(size, isLargeScreen: isLargeScreen),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _artworkPane(Size size, {double maxFraction = 1}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: constraints.maxWidth * maxFraction,
              maxHeight: constraints.maxHeight * maxFraction,
            ),
            child: FittedBox(
              child: _PausedShrink(
                child: NowPlayingArtwork(
                  size: size,
                  metadata: metadata,
                  lyricsController: lyricsController,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _actions(Size size, {required bool isLargeScreen}) {
    return BottomActionsRow(
      metadata: metadata,
      iconSize: _miniIconSize(size),
      isLargeScreen: isLargeScreen,
      lyricsController: lyricsController,
    );
  }

  double _iconSize(Size size) => size.width < 360
      ? 36
      : size.width < 400
      ? 40
      : 44;

  double _miniIconSize(Size size) => size.width < 360 ? 18 : 22;
}

/// Apple Music shrinks the artwork while paused.
class _PausedShrink extends StatelessWidget {
  const _PausedShrink({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: audioHandler.playbackState.map((s) => s.playing).distinct(),
      initialData: audioHandler.playbackState.valueOrNull?.playing ?? false,
      builder: (context, snapshot) {
        final playing = snapshot.data ?? false;
        return AnimatedScale(
          scale: playing ? 1 : 0.86,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOutBack,
          child: child,
        );
      },
    );
  }
}

/// Stands in for upstream's FlipCardController: the bottom row's lyrics
/// button calls `flipcard()`, which here toggles the lyrics pane instead.
class _LyricsToggle {
  _LyricsToggle(this.onToggle);

  final VoidCallback onToggle;

  Future<void> flipcard() async => onToggle();
}

/// Player as a panel on the right; the left side shows the app behind a
/// scrim, or the lyrics when they are open.
class _PanelLayout extends StatelessWidget {
  const _PanelLayout({
    required this.metadata,
    required this.showLyrics,
    required this.lyricsToggle,
    required this.onClose,
  });

  final MediaItem metadata;
  final bool showLyrics;
  final _LyricsToggle lyricsToggle;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final panelWidth = (size.width * 0.42).clamp(380.0, 560.0);

    final left = Stack(
      fit: StackFit.expand,
      children: [
        // Tapping the dimmed app closes the player, like tapping outside a sheet.
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onClose,
          child: const SizedBox.expand(),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 360),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween(
                begin: const Offset(-0.06, 0),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: showLyrics
              ? SizedBox.expand(
                  key: const ValueKey('lyrics'),
                  child: _LyricsPane(metadata: metadata),
                )
              : const SizedBox.shrink(key: ValueKey('none')),
        ),
      ],
    );

    Widget panel(double width) => SizedBox(
      width: width,
      child: _Panel(
        metadata: metadata,
        showLyrics: showLyrics,
        lyricsToggle: lyricsToggle,
        padding: padding,
      ),
    );

    return FoldAwareTwoPane(
      first: left,
      second: panel(panelWidth),
      fallback: Row(
        children: [
          Expanded(child: left),
          panel(panelWidth),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.metadata,
    required this.showLyrics,
    required this.lyricsToggle,
    required this.padding,
  });

  final MediaItem metadata;
  final bool showLyrics;
  final _LyricsToggle lyricsToggle;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final isLive = metadata.extras?['isLive'] ?? false;
    final scheme = Theme.of(context).colorScheme;

    return ClipRSuperellipse(
      borderRadius: const BorderRadius.only(topLeft: Radius.circular(24)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _ArtworkBackdrop(metadata: metadata),
          Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              padding.top + 16,
              20,
              padding.bottom + 12,
            ),
            child: Column(
              children: [
                _PanelHeader(metadata: metadata),
                const SizedBox(height: 8),
                const Expanded(child: QueueWidget()),
                if (!isLive) ...[
                  const SizedBox(height: 4),
                  const PositionSlider(),
                  PlayerControlButtons(
                    metadata: metadata,
                    iconSize: 44,
                    miniIconSize: 22,
                  ),
                ],
                const SizedBox(height: 8),
                BottomActionsRow(
                  metadata: metadata,
                  iconSize: 22,
                  isLargeScreen: true,
                  lyricsController: lyricsToggle,
                ),
              ],
            ),
          ),
          if (showLyrics)
            // Marks the lyrics button as active.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                child: Container(height: 2, color: scheme.primary),
              ),
            ),
        ],
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.metadata});

  final MediaItem metadata;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final artist = metadata.artist;

    return Row(
      children: [
        SongArtworkWidget(
          metadata: metadata,
          size: 60,
          borderRadius: 8,
          errorWidgetIconSize: 24,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                metadata.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              if (artist != null && artist.isNotEmpty)
                Text(
                  artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Lyrics filling the whole left side, like Apple Music on iPad.
class _LyricsPane extends StatefulWidget {
  const _LyricsPane({required this.metadata});

  final MediaItem metadata;

  @override
  State<_LyricsPane> createState() => _LyricsPaneState();
}

class _LyricsPaneState extends State<_LyricsPane> {
  String? _key;
  late Future<String?> _lyrics;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_LyricsPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    _load();
  }

  void _load() {
    final key = '${widget.metadata.artist} - ${widget.metadata.title}';
    if (key == _key) return;
    _key = key;
    _lyrics = getSongLyrics(widget.metadata.artist, widget.metadata.title);
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final unavailable = context.l10n!.lyricsNotAvailable;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.6),
          child: FutureBuilder<String?>(
            future: _lyrics,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final text = snapshot.data;
              final has = text != null && text.trim().isNotEmpty;
              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  40,
                  padding.top + 40,
                  40,
                  padding.bottom + 40,
                ),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Text(
                    has ? text : unavailable,
                    style: TextStyle(
                      fontSize: has ? 30 : 22,
                      height: 1.35,
                      fontWeight: FontWeight.w800,
                      color: Colors.white.withValues(alpha: has ? 0.92 : 0.6),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
