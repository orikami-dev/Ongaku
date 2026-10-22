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
import 'package:musify/main.dart';
import 'package:musify/ongaku/layout/adaptive.dart';
import 'package:musify/utilities/artwork_provider.dart';
import 'package:musify/widgets/flip_card.dart';
import 'package:musify/widgets/now_playing/bottom_actions_row.dart';
import 'package:musify/widgets/now_playing/now_playing_artwork.dart';
import 'package:musify/widgets/now_playing/now_playing_controls.dart';
import 'package:musify/widgets/queue_list_view.dart';

/// Opens the full screen player as an Apple Music style card sliding up.
Future<void> openOngakuNowPlaying(BuildContext context) {
  return Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 380),
      reverseTransitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (context, animation, _) => const OngakuNowPlayingPage(),
      transitionsBuilder: (context, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return SlideTransition(
          position: Tween(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    ),
  );
}

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
    final showQueue =
        (windowSize == WindowSize.expanded || windowSize == WindowSize.large) &&
        size.height >= 520;

    final standard = showQueue
        ? Row(
            children: [
              Expanded(child: _portrait(context, size, isLargeScreen: true)),
              const SizedBox(width: 12),
              Expanded(child: _queuePane(context)),
            ],
          )
        : (size.width > size.height * 1.05
              ? _sideBySide(context, size, isLargeScreen: false)
              : _portrait(context, size, isLargeScreen: false));

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

  Widget _queuePane(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 16, 16),
      child: ClipRSuperellipse(
        borderRadius: BorderRadius.circular(20),
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.22),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [Expanded(child: QueueWidget())],
          ),
        ),
      ),
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
