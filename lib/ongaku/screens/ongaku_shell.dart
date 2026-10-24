/*
 *     Ongaku — an Apple Music style edition of Musify.
 *     Based on Musify, Copyright (C) 2026 Valeri Gokadze.
 *
 *     This program is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version. See <https://www.gnu.org/licenses/>.
 */

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/main.dart';
import 'package:musify/ongaku/theme/ongaku_motion.dart';
import 'package:musify/ongaku/widgets/ongaku_mini_player.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/utilities/flutter_bottom_sheet.dart'
    show closeCurrentBottomSheet;

/// App shell replacing upstream's BottomNavigationPage, laid out like Apple
/// Music on Android:
///
/// * Phone / folded cover screen: the mini player is docked above a full
///   width bar of four tabs. The app stays in portrait there.
/// * Open foldable / tablet: one bar, the tabs on the left and the mini
///   player docked on the right.
///
/// Branch indexes are upstream's: 0 home, 1 search, 2 library, 3 settings.
/// The bar shows them as Home, Library, Search, Settings.
class OngakuShell extends StatefulWidget {
  const OngakuShell({required this.child, super.key});

  final StatefulNavigationShell child;

  /// Bar colour shared with the player panel edges.
  static Color barColor(ColorScheme colorScheme) =>
      colorScheme.brightness == Brightness.dark
      ? const Color(0xFF1F1F1F)
      : const Color(0xFFF7F7F7);

  @override
  State<OngakuShell> createState() => _OngakuShellState();
}

class _OngakuShellState extends State<OngakuShell> {
  late final _miniPlayerVisibility = audioHandler.mediaItem
      .map((mediaItem) => mediaItem != null)
      .distinct();

  bool? _previousOfflineMode;
  int? _previousShellIndex;
  bool? _portraitOnly;

  static const _homeIndex = 0;
  static const _searchIndex = 1;
  static const _libraryIndex = 2;
  static const _settingsIndex = 3;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The folded cover screen is too small for landscape; open, anything goes.
    final portraitOnly = MediaQuery.sizeOf(context).shortestSide < 600;
    if (portraitOnly != _portraitOnly) {
      _portraitOnly = portraitOnly;
      SystemChrome.setPreferredOrientations(
        portraitOnly
            ? const [DeviceOrientation.portraitUp]
            : const <DeviceOrientation>[],
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: widget.child.currentIndex == _homeIndex,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (widget.child.currentIndex != _homeIndex) {
          widget.child.goBranch(_homeIndex);
        } else {
          SystemNavigator.pop();
        }
      },
      child: ValueListenableBuilder<bool>(
        valueListenable: offlineMode,
        builder: (context, isOfflineMode, _) {
          if (_previousOfflineMode != null &&
              _previousOfflineMode != isOfflineMode) {
            SchedulerBinding.instance.addPostFrameCallback((_) {
              _handleOfflineModeChange(isOfflineMode);
            });
          }
          _previousOfflineMode = isOfflineMode;

          return StreamBuilder<bool>(
            stream: _miniPlayerVisibility,
            initialData: audioHandler.mediaItem.valueOrNull != null,
            builder: (context, snapshot) {
              final hasMiniPlayer = snapshot.data ?? false;
              final wide = MediaQuery.sizeOf(context).width >= 600;
              final tabs = _tabs(context, isOfflineMode);
              return Scaffold(
                body: widget.child,
                bottomNavigationBar: wide
                    ? _WideBar(
                        tabs: tabs,
                        selected: widget.child.currentIndex,
                        onSelected: _goToBranch,
                        hasMiniPlayer: hasMiniPlayer,
                      )
                    : _PhoneBar(
                        tabs: tabs,
                        selected: widget.child.currentIndex,
                        onSelected: _goToBranch,
                        hasMiniPlayer: hasMiniPlayer,
                      ),
              );
            },
          );
        },
      ),
    );
  }

  List<_Tab> _tabs(BuildContext context, bool isOfflineMode) {
    final l10n = context.l10n;
    return [
      _Tab(
        icon: Icons.home_rounded,
        label: l10n?.home ?? 'Home',
        shellIndex: _homeIndex,
      ),
      _Tab(
        icon: Icons.library_music_rounded,
        label: l10n?.library ?? 'Library',
        shellIndex: _libraryIndex,
      ),
      if (!isOfflineMode)
        _Tab(
          icon: Icons.search_rounded,
          label: l10n?.search ?? 'Search',
          shellIndex: _searchIndex,
        ),
      _Tab(
        icon: Icons.settings_rounded,
        label: l10n?.settings ?? 'Settings',
        shellIndex: _settingsIndex,
      ),
    ];
  }

  void _handleOfflineModeChange(bool isOfflineMode) {
    if (!mounted) return;
    final currentRoute = GoRouterState.of(context).matchedLocation;
    if (isOfflineMode && currentRoute.startsWith('/search')) {
      widget.child.goBranch(_homeIndex);
    }
  }

  void _goToBranch(int shellIndex) {
    final isReselect =
        _previousShellIndex == shellIndex &&
        widget.child.currentIndex == shellIndex;

    closeCurrentBottomSheet();
    HapticFeedback.selectionClick();

    // Tapping the current tab again goes back to its first page.
    widget.child.goBranch(shellIndex, initialLocation: isReselect);
    _previousShellIndex = shellIndex;
  }
}

class _Tab {
  const _Tab({
    required this.icon,
    required this.label,
    required this.shellIndex,
  });

  final IconData icon;
  final String label;
  final int shellIndex;
}

class _BarSurface extends StatelessWidget {
  const _BarSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: OngakuShell.barColor(colorScheme),
        border: Border(
          top: BorderSide(
            color: colorScheme.onSurface.withValues(alpha: 0.1),
            width: 0.5,
          ),
        ),
      ),
      child: child,
    );
  }
}

/// Phone: mini player docked on top of a five-tab bar.
class _PhoneBar extends StatelessWidget {
  const _PhoneBar({
    required this.tabs,
    required this.selected,
    required this.onSelected,
    required this.hasMiniPlayer,
  });

  final List<_Tab> tabs;
  final int selected;
  final ValueChanged<int> onSelected;
  final bool hasMiniPlayer;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return _BarSurface(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSize(
            duration: OngakuMotion.medium,
            curve: Curves.easeOutCubic,
            alignment: Alignment.bottomCenter,
            child: hasMiniPlayer
                ? Column(
                    children: [
                      const OngakuMiniPlayer(),
                      Divider(
                        height: 0.5,
                        thickness: 0.5,
                        color: colorScheme.onSurface.withValues(alpha: 0.1),
                      ),
                    ],
                  )
                : const SizedBox(width: double.infinity),
          ),
          SizedBox(
            height: 58,
            child: _TabRow(
              tabs: tabs,
              selected: selected,
              onSelected: onSelected,
            ),
          ),
          SizedBox(height: bottomInset),
        ],
      ),
    );
  }
}

/// Open foldable / tablet: tabs on the left, mini player on the right.
class _WideBar extends StatelessWidget {
  const _WideBar({
    required this.tabs,
    required this.selected,
    required this.onSelected,
    required this.hasMiniPlayer,
  });

  final List<_Tab> tabs;
  final int selected;
  final ValueChanged<int> onSelected;
  final bool hasMiniPlayer;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final padding = MediaQuery.paddingOf(context);

    return _BarSurface(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: padding.bottom,
          left: padding.left,
          right: padding.right,
        ),
        child: SizedBox(
          height: 66,
          child: LayoutBuilder(
            builder: (context, constraints) {
              // About 60 % for the tabs, like Apple Music on a tablet.
              final tabsWidth = hasMiniPlayer
                  ? constraints.maxWidth * 0.6
                  : constraints.maxWidth;
              return Row(
                children: [
                  AnimatedContainer(
                    duration: OngakuMotion.medium,
                    curve: Curves.easeOutCubic,
                    width: tabsWidth,
                    child: _TabRow(
                      tabs: tabs,
                      selected: selected,
                      onSelected: onSelected,
                    ),
                  ),
                  if (hasMiniPlayer) ...[
                    VerticalDivider(
                      width: 0.5,
                      thickness: 0.5,
                      color: colorScheme.onSurface.withValues(alpha: 0.12),
                    ),
                    const Expanded(child: OngakuMiniPlayer()),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _TabRow extends StatelessWidget {
  const _TabRow({
    required this.tabs,
    required this.selected,
    required this.onSelected,
  });

  final List<_Tab> tabs;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final tab in tabs)
          Expanded(
            child: _TabButton(
              tab: tab,
              selected: tab.shellIndex == selected,
              onTap: () => onSelected(tab.shellIndex),
            ),
          ),
      ],
    );
  }
}

class _TabButton extends StatefulWidget {
  const _TabButton({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final _Tab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_TabButton> createState() => _TabButtonState();
}

class _TabButtonState extends State<_TabButton>
    with SingleTickerProviderStateMixin {
  late final _bounce = AnimationController(
    vsync: this,
    duration: OngakuMotion.slow,
    value: 1,
  );
  bool _pressed = false;

  @override
  void didUpdateWidget(_TabButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected && !oldWidget.selected) _bounce.forward(from: 0);
  }

  @override
  void dispose() {
    _bounce.dispose();
    super.dispose();
  }

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tab = widget.tab;
    final selected = widget.selected;
    final color = selected
        ? colorScheme.primary
        : colorScheme.onSurface.withValues(alpha: 0.5);

    return Semantics(
      selected: selected,
      button: true,
      label: tab.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        child: AnimatedOpacity(
          opacity: _pressed ? 0.55 : 1,
          duration: OngakuMotion.fast,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ScaleTransition(
                scale: TweenSequence<double>([
                  TweenSequenceItem(
                    tween: Tween<double>(begin: 1, end: 0.82),
                    weight: 30,
                  ),
                  TweenSequenceItem(
                    tween: Tween<double>(
                      begin: 0.82,
                      end: 1,
                    ).chain(CurveTween(curve: Curves.elasticOut)),
                    weight: 70,
                  ),
                ]).animate(_bounce),
                child: TweenAnimationBuilder<Color?>(
                  tween: ColorTween(end: color),
                  duration: OngakuMotion.quick,
                  builder: (context, value, _) =>
                      Icon(tab.icon, color: value, size: 27),
                ),
              ),
              const SizedBox(height: 3),
              AnimatedDefaultTextStyle(
                duration: OngakuMotion.quick,
                style: TextStyle(
                  fontFamily: 'Inter',
                  color: color,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.1,
                ),
                child: Text(
                  tab.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
