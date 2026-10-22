/*
 *     Ongaku — an Apple Music style edition of Musify.
 *     Based on Musify, Copyright (C) 2026 Valeri Gokadze.
 *
 *     This program is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version. See <https://www.gnu.org/licenses/>.
 */

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/main.dart';
import 'package:musify/ongaku/brand.dart';
import 'package:musify/ongaku/layout/adaptive.dart';
import 'package:musify/ongaku/widgets/glass.dart';
import 'package:musify/ongaku/widgets/ongaku_mini_player.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/utilities/flutter_bottom_sheet.dart'
    show closeCurrentBottomSheet;

/// App shell replacing upstream's BottomNavigationPage.
///
/// * Phones: floating glass tab bar + separate search button (iOS 26 style),
///   with the mini player floating above it.
/// * Unfolded foldables / small tablets: compact side rail.
/// * Tablets / desktops: Apple Music style sidebar.
///
/// Branch indexes are the ones declared by upstream's router:
/// 0 home, 1 search, 2 library, 3 settings.
class OngakuShell extends StatefulWidget {
  const OngakuShell({required this.child, super.key});

  final StatefulNavigationShell child;

  @override
  State<OngakuShell> createState() => _OngakuShellState();
}

class _OngakuShellState extends State<OngakuShell> {
  late final _miniPlayerVisibility = audioHandler.mediaItem
      .map((mediaItem) => mediaItem != null)
      .distinct();

  bool? _previousOfflineMode;
  int? _previousShellIndex;

  static const _homeIndex = 0;
  static const _searchIndex = 1;
  static const _libraryIndex = 2;
  static const _settingsIndex = 3;

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
              final size = windowSizeOf(context);
              return size == WindowSize.compact
                  ? _buildPhoneLayout(context, isOfflineMode, hasMiniPlayer)
                  : _buildSidebarLayout(
                      context,
                      isOfflineMode,
                      hasMiniPlayer,
                      extended:
                          size == WindowSize.expanded ||
                          size == WindowSize.large,
                    );
            },
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------- phone

  Widget _buildPhoneLayout(
    BuildContext context,
    bool isOfflineMode,
    bool hasMiniPlayer,
  ) {
    final tabs = _tabs(context, includeSearch: false);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      extendBody: true,
      body: SafeArea(bottom: false, child: widget.child),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.fromLTRB(
          12,
          0,
          12,
          bottomInset > 0 ? bottomInset : 10,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween(
                      begin: const Offset(0, 0.4),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: hasMiniPlayer
                    ? const Padding(
                        key: ValueKey('mini'),
                        padding: EdgeInsets.only(bottom: 8),
                        child: OngakuMiniPlayer(),
                      )
                    : const SizedBox(
                        key: ValueKey('none'),
                        width: double.infinity,
                      ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: _GlassTabBar(
                    tabs: tabs,
                    selectedShellIndex: widget.child.currentIndex,
                    onSelected: _goToBranch,
                  ),
                ),
                if (!isOfflineMode) ...[
                  const SizedBox(width: 10),
                  _GlassSearchButton(
                    selected: widget.child.currentIndex == _searchIndex,
                    onPressed: () => _goToBranch(_searchIndex),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------- foldables / tablets

  Widget _buildSidebarLayout(
    BuildContext context,
    bool isOfflineMode,
    bool hasMiniPlayer, {
    required bool extended,
  }) {
    final tabs = _tabs(context, includeSearch: !isOfflineMode);
    final mediaQuery = MediaQuery.of(context);
    final miniPlayerSpace = hasMiniPlayer
        ? OngakuMiniPlayer.totalHeight + 12
        : 0.0;

    final content = Stack(
      children: [
        MediaQuery(
          data: mediaQuery.copyWith(
            padding: mediaQuery.padding.copyWith(
              bottom: mediaQuery.padding.bottom + miniPlayerSpace,
            ),
          ),
          child: widget.child,
        ),
        if (hasMiniPlayer)
          Positioned(
            left: 16,
            right: 16,
            bottom: mediaQuery.padding.bottom + 12,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: const OngakuMiniPlayer(),
              ),
            ),
          ),
      ],
    );

    return Scaffold(
      body: Row(
        children: [
          _Sidebar(
            tabs: tabs,
            extended: extended,
            selectedShellIndex: widget.child.currentIndex,
            onSelected: _goToBranch,
          ),
          Expanded(child: SafeArea(left: false, bottom: false, child: content)),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- logic

  List<_Tab> _tabs(BuildContext context, {required bool includeSearch}) {
    final l10n = context.l10n;
    return [
      _Tab(
        icon: FluentIcons.home_24_regular,
        selectedIcon: FluentIcons.home_24_filled,
        label: l10n?.home ?? 'Home',
        shellIndex: _homeIndex,
      ),
      if (includeSearch)
        _Tab(
          icon: FluentIcons.search_24_regular,
          selectedIcon: FluentIcons.search_24_filled,
          label: l10n?.search ?? 'Search',
          shellIndex: _searchIndex,
        ),
      _Tab(
        icon: FluentIcons.music_note_2_24_regular,
        selectedIcon: FluentIcons.music_note_2_24_filled,
        label: l10n?.library ?? 'Library',
        shellIndex: _libraryIndex,
      ),
      _Tab(
        icon: FluentIcons.settings_24_regular,
        selectedIcon: FluentIcons.settings_24_filled,
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

    // Tapping the current tab again resets it, like on iOS.
    widget.child.goBranch(shellIndex, initialLocation: isReselect);
    _previousShellIndex = shellIndex;
  }
}

class _Tab {
  const _Tab({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.shellIndex,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final int shellIndex;
}

class _GlassTabBar extends StatelessWidget {
  const _GlassTabBar({
    required this.tabs,
    required this.selectedShellIndex,
    required this.onSelected,
  });

  final List<_Tab> tabs;
  final int selectedShellIndex;
  final ValueChanged<int> onSelected;

  static const double height = 62;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected = tabs.indexWhere((t) => t.shellIndex == selectedShellIndex);
    // The pill glides between tabs instead of fading in and out.
    final alignX = tabs.length < 2
        ? 0.0
        : -1 + 2 * (selected < 0 ? 0 : selected) / (tabs.length - 1);

    return GlassSurface(
      height: height,
      borderRadius: height / 2,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Stack(
          children: [
            AnimatedAlign(
              duration: const Duration(milliseconds: 380),
              curve: Curves.easeOutBack,
              alignment: Alignment(alignX, 0),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: selected < 0 ? 0 : 1,
                child: FractionallySizedBox(
                  widthFactor: 1 / tabs.length,
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      color: colorScheme.onSurface.withValues(alpha: 0.08),
                      shape: const StadiumBorder(),
                    ),
                  ),
                ),
              ),
            ),
            Row(
              children: [
                for (final tab in tabs)
                  Expanded(
                    child: _TabButton(
                      tab: tab,
                      selected: tab.shellIndex == selectedShellIndex,
                      onTap: () => onSelected(tab.shellIndex),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
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

class _TabButtonState extends State<_TabButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tab = widget.tab;
    final selected = widget.selected;
    final color = selected ? colorScheme.primary : colorScheme.onSurface;

    return Semantics(
      selected: selected,
      button: true,
      label: tab.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.9 : 1,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOutBack,
                transitionBuilder: (child, animation) =>
                    ScaleTransition(scale: animation, child: child),
                child: Icon(
                  selected ? tab.selectedIcon : tab.icon,
                  key: ValueKey(selected),
                  color: color,
                  size: 24,
                ),
              ),
              const SizedBox(height: 2),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 220),
                style: TextStyle(
                  color: color,
                  fontSize: 10.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
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

class _GlassSearchButton extends StatelessWidget {
  const _GlassSearchButton({required this.selected, required this.onPressed});

  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final label = context.l10n?.search ?? 'Search';

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onPressed,
        child: SizedBox.square(
          dimension: _GlassTabBar.height,
          child: GlassSurface(
            borderRadius: _GlassTabBar.height / 2,
            child: Icon(
              selected
                  ? FluentIcons.search_24_filled
                  : FluentIcons.search_24_regular,
              color: selected ? colorScheme.primary : colorScheme.onSurface,
              size: 26,
            ),
          ),
        ),
      ),
    );
  }
}

/// Side navigation for wide screens. [extended] shows labels and the app
/// name (iPad / Mac Apple Music sidebar), otherwise a compact icon rail.
class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.tabs,
    required this.extended,
    required this.selectedShellIndex,
    required this.onSelected,
  });

  final List<_Tab> tabs;
  final bool extended;
  final int selectedShellIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final padding = MediaQuery.paddingOf(context);
    final width = extended ? 250.0 : 88.0;

    return Container(
      width: width + padding.left,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(
          right: BorderSide(color: colorScheme.outlineVariant, width: 0.5),
        ),
      ),
      padding: EdgeInsets.only(
        left: padding.left + (extended ? 12 : 8),
        right: extended ? 12 : 8,
        top: padding.top + 12,
        bottom: padding.bottom + 12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (extended)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 18),
              child: Text(
                appName,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.8,
                  color: colorScheme.onSurface,
                ),
              ),
            )
          else
            const SizedBox(height: 8),
          for (final tab in tabs)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _SidebarItem(
                tab: tab,
                extended: extended,
                selected: tab.shellIndex == selectedShellIndex,
                onTap: () => onSelected(tab.shellIndex),
              ),
            ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.tab,
    required this.extended,
    required this.selected,
    required this.onTap,
  });

  final _Tab tab;
  final bool extended;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final icon = Icon(
      selected ? tab.selectedIcon : tab.icon,
      color: colorScheme.primary,
      size: 24,
    );

    return Semantics(
      button: true,
      selected: selected,
      label: tab.label,
      excludeSemantics: true,
      child: Material(
        color: selected ? colorScheme.surfaceContainerHigh : Colors.transparent,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 10,
              vertical: extended ? 10 : 8,
            ),
            child: extended
                ? Row(
                    children: [
                      icon,
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          tab.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      icon,
                      const SizedBox(height: 4),
                      Text(
                        tab.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
