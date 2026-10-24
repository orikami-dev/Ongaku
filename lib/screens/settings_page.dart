/*
 *     Copyright (C) 2026 Valeri Gokadze
 *
 *     Musify is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version.
 *
 *     Musify is distributed in the hope that it will be useful,
 *     but WITHOUT ANY WARRANTY; without even the implied warranty of
 *     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *     GNU General Public License for more details.
 *
 *     You should have received a copy of the GNU General Public License
 *     along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 *
 *     For more information about Musify, including how to contribute,
 *     please visit: https://github.com/gokadzev/Musify
 */

import 'package:audio_service/audio_service.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/constants/app_constants.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/main.dart';
import 'package:musify/ongaku/l10n/ongaku_strings.dart';
import 'package:musify/ongaku/widgets/ongaku_credits.dart';
import 'package:musify/ongaku/widgets/ongaku_page_parts.dart';
import 'package:musify/ongaku/widgets/ongaku_settings_ui.dart';
import 'package:musify/screens/search_page.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/services/data_manager.dart';
import 'package:musify/services/listening_stats_service.dart';
import 'package:musify/services/playlist_download_service.dart';
import 'package:musify/services/playlists_manager.dart';
import 'package:musify/services/router_service.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/services/update_manager.dart';
import 'package:musify/theme/app_colors.dart';
import 'package:musify/theme/app_themes.dart';
import 'package:musify/utilities/flutter_bottom_sheet.dart';
import 'package:musify/utilities/flutter_toast.dart';
import 'package:musify/utilities/language_utils.dart';
import 'package:musify/utilities/platform_utils.dart';
import 'package:musify/utilities/url_launcher.dart';
import 'package:musify/widgets/bottom_sheet_bar.dart';
import 'package:musify/widgets/confirmation_dialog.dart';
import 'package:musify/widgets/custom_bar.dart';
import 'package:musify/widgets/mini_player_bottom_space.dart';
import 'package:musify/widgets/section_header.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final content = Column(
      children: <Widget>[
        _buildCategories(context),
        const SizedBox(height: 20),
        const MiniPlayerBottomSpace(),
      ],
    );

    return Scaffold(
      body: Column(
        children: [
          OngakuLargeTitle(title: context.l10n!.settings),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: ongakuPageMargin(context),
                vertical: 20,
              ),
              child: isDesktopPlatform
                  ? Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 880),
                        child: content,
                      ),
                    )
                  : content,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategories(BuildContext context) {
    final strings = OngakuStrings.of(context);
    final online = !offlineMode.value;
    final isOffline = offlineMode.value;

    return Column(
      children: [
        _group(strings.catAppearance, const Color(0xFFAF52DE), [
          CustomBar(
            context.l10n!.accentColor,
            FluentIcons.color_24_regular,
            borderRadius: commonCustomBarRadiusFirst,
            // Ongaku: the current colour shows on every platform, the
            // system's when the dynamic colour is on.
            trailing: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: isAndroidPlatform && useSystemColor.value
                    ? Theme.of(context).colorScheme.primary
                    : primaryColorSetting,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
            onTap: () => _showAccentColorPicker(context),
          ),
          CustomBar(
            context.l10n!.themeMode,
            FluentIcons.weather_sunny_28_regular,
            onTap: () => _showThemeModePicker(context),
          ),
          if (themeMode == ThemeMode.dark)
            CustomBar(
              context.l10n!.pureBlackTheme,
              FluentIcons.color_background_24_regular,
              description: context.l10n!.pureBlackThemeDescription,
              trailing: Switch(
                value: usePureBlackColor.value,
                onChanged: (value) => _togglePureBlack(context, value),
              ),
            ),
          // Ongaku: the dynamic colour switch is in the Couleur picker.
          CustomBar(
            context.l10n!.language,
            FluentIcons.translate_24_regular,
            onTap: () => _showLanguagePicker(context),
          ),
        ]),
        _group(strings.catPlayback, const Color(0xFFFF2D55), [
          CustomBar(
            context.l10n!.audioQuality,
            FluentIcons.music_note_1_24_regular,
            onTap: () => _showAudioQualityPicker(context),
          ),
          // Ongaku: no audio quality badge row.
          if (isAndroidPlatform)
            CustomBar(
              context.l10n!.equalizer,
              FluentIcons.data_histogram_24_regular,
              onTap: () => context.push('/settings/equalizer'),
            ),
          // Ongaku: calibrated sound (profiles per output, layers, mode doux).
          if (isAndroidPlatform)
            CustomBar(
              strings.soundTitle,
              FluentIcons.headphones_sound_wave_24_regular,
              description: strings.soundRowDesc,
              onTap: () => context.push('/settings/sound'),
            ),
          if (online)
            ValueListenableBuilder<bool>(
              valueListenable: playNextSongAutomatically,
              builder: (_, value, __) {
                return CustomBar(
                  context.l10n!.automaticSongPicker,
                  FluentIcons.music_note_2_play_20_regular,
                  description: context.l10n!.automaticSongPickerDescription,
                  trailing: Switch(
                    value: value,
                    onChanged: (value) {
                      _toggleAutoPlayNext(context, value);
                      showToast(context, context.l10n!.settingChangedMsg);
                    },
                  ),
                );
              },
            ),
          if (online)
            ValueListenableBuilder<bool>(
              valueListenable: sponsorBlockSupport,
              builder: (_, value, __) {
                return CustomBar(
                  'SponsorBlock',
                  FluentIcons.cut_24_regular,
                  description: context.l10n!.sponsorBlockDescription,
                  trailing: Switch(
                    value: value,
                    onChanged: (value) => _toggleSponsorBlock(context, value),
                  ),
                );
              },
            ),
        ]),
        _group(strings.catLibrary, const Color(0xFF007AFF), [
          ValueListenableBuilder<bool>(
            valueListenable: wrappedEnabled,
            builder: (_, value, __) {
              return CustomBar(
                context.l10n!.listeningStats,
                FluentIcons.clock_24_regular,
                description: context.l10n!.listeningStatsDescription,
                trailing: Switch(
                  value: value,
                  onChanged: (value) => _toggleWrapped(context, value),
                ),
              );
            },
          ),
          if (online)
            CustomBar(
              context.l10n!.clearRecentlyPlayed,
              FluentIcons.receipt_play_24_regular,
              onTap: () => _showConfirmationDialog(
                context: context,
                confirmationMessage: context.l10n!.clearRecentlyPlayedQuestion,
                onSubmit: () {
                  userRecentlyPlayed.value = [];
                  deleteData('user', 'recentlyPlayedSongs');
                  showToast(context, '${context.l10n!.recentlyPlayedMsg}!');
                },
              ),
            ),
          if (online)
            CustomBar(
              context.l10n!.clearSearchHistory,
              FluentIcons.history_24_regular,
              onTap: () => _showConfirmationDialog(
                context: context,
                confirmationMessage: context.l10n!.clearSearchHistoryQuestion,
                onSubmit: () {
                  searchHistoryNotifier.value = [];
                  deleteData('user', 'searchHistory');
                  showToast(context, '${context.l10n!.searchHistoryMsg}!');
                },
              ),
            ),
          if (online)
            CustomBar(
              context.l10n!.clearListeningStats,
              FluentIcons.clock_24_regular,
              onTap: () => _showConfirmationDialog(
                context: context,
                confirmationMessage: context.l10n!.clearListeningStatsQuestion,
                submitMessage: context.l10n!.delete,
                isDangerous: true,
                onSubmit: () async {
                  audioHandler.resetListeningStatsSession(flushStats: false);
                  await listeningStatsService.clearStats();
                  audioHandler.startListeningStatsSessionIfNeeded();
                  if (context.mounted) {
                    showToast(
                      context,
                      '${context.l10n!.listeningStatsCleared}!',
                    );
                  }
                },
              ),
            ),
          if (online)
            CustomBar(
              context.l10n!.importSpotifyPlaylist,
              FluentIcons.arrow_upload_24_regular,
              // Ongaku: link import with name and cover (CSV still offered).
              onTap: () => context.push('/settings/import-spotify'),
            ),
          // Ongaku: Deezer and Apple Music imports.
          if (online)
            CustomBar(
              strings.importDeezer,
              FluentIcons.arrow_upload_24_regular,
              onTap: () => context.push('/settings/import-deezer-playlist'),
            ),
          if (online)
            CustomBar(
              strings.importApple,
              FluentIcons.arrow_upload_24_regular,
              onTap: () =>
                  context.push('/settings/import-apple-music-playlist'),
            ),
          if (online)
            CustomBar(
              context.l10n!.backupUserData,
              FluentIcons.cloud_sync_24_regular,
              onTap: () => _backupUserData(context),
            ),
          if (online)
            CustomBar(
              context.l10n!.restoreUserData,
              FluentIcons.cloud_add_24_regular,
              onTap: () async {
                try {
                  final result = await restoreData(context);
                  if (result.success) {
                    reloadSettingsFromStorage();
                    reloadSongLibraryStateFromStorage();
                    reloadPlaylistLibraryStateFromStorage();
                    reloadSearchHistoryFromStorage();
                    listeningStatsService.reload();
                    await audioHandler.setShuffleMode(
                      shuffleNotifier.value
                          ? AudioServiceShuffleMode.all
                          : AudioServiceShuffleMode.none,
                    );
                    await audioHandler.setRepeatMode(repeatNotifier.value);
                    themeMode = getThemeMode(themeModeSetting);
                    brightness = getBrightnessFromThemeMode(themeMode);
                    if (context.mounted) {
                      await Musify.updateAppState(
                        context,
                        newThemeMode: themeMode,
                        newLocale: languageSetting,
                        newAccentColor: primaryColorSetting,
                        useSystemColor: useSystemColor.value,
                      );
                      NavigationManager.refreshRouter();
                    }
                  }
                  if (context.mounted) {
                    showToast(
                      context,
                      result.message,
                      icon: result.success
                          ? null
                          : FluentIcons.error_circle_24_regular,
                    );
                  }
                } catch (e, str) {
                  logger.log('Error restoring data', error: e, stackTrace: str);
                  if (context.mounted) {
                    showToast(
                      context,
                      context.l10n!.error,
                      icon: FluentIcons.error_circle_24_regular,
                    );
                  }
                }
              },
            ),
        ]),
        _group(strings.catStorage, const Color(0xFFFF9500), [
          if (online)
            CustomBar(
              context.l10n!.clearCache,
              FluentIcons.broom_24_regular,
              borderRadius: commonCustomBarRadiusFirst,
              onTap: () async {
                final cleared = await clearCache();
                showToast(
                  context,
                  cleared ? '${context.l10n!.cacheMsg}!' : context.l10n!.error,
                );
              },
            ),
          if (online)
            CustomBar(
              context.l10n!.deleteDownloads,
              FluentIcons.delete_24_regular,
              onTap: () => _showConfirmationDialog(
                context: context,
                confirmationMessage: context.l10n!.deleteDownloadsQuestion,
                submitMessage: context.l10n!.delete,
                isDangerous: true,
                onSubmit: () async {
                  try {
                    await offlinePlaylistService.deleteAllDownloads();
                    if (context.mounted) {
                      showToast(context, context.l10n!.downloadsDeleted);
                    }
                  } catch (e) {
                    if (context.mounted) {
                      showToast(context, context.l10n!.error);
                    }
                  }
                },
              ),
            ),
        ]),
        _group(strings.catNetwork, const Color(0xFF34C759), [
          ValueListenableBuilder<bool>(
            valueListenable: offlineMode,
            builder: (_, value, __) {
              return CustomBar(
                context.l10n!.offlineMode,
                FluentIcons.cloud_off_24_regular,
                description: context.l10n!.offlineModeDescription,
                borderRadius: isOffline && isFdroidBuild
                    ? commonCustomBarRadiusLast
                    : BorderRadius.zero,
                trailing: Switch(
                  value: value,
                  onChanged: (value) => _toggleOfflineMode(context, value),
                ),
              );
            },
          ),
          ValueListenableBuilder<bool>(
            valueListenable: useProxy,
            builder: (_, value, __) {
              return CustomBar(
                context.l10n!.useProxy,
                FluentIcons.shield_24_regular,
                description: context.l10n!.useProxyDescription,
                trailing: Switch(
                  value: value,
                  onChanged: (value) {
                    useProxy.value = value;
                    addOrUpdateData<bool>('settings', 'useProxy', value);
                    showToast(context, context.l10n!.settingChangedMsg);
                  },
                ),
              );
            },
          ),
          if (online)
            ValueListenableBuilder<bool>(
              valueListenable: externalRecommendations,
              builder: (_, value, __) {
                return CustomBar(
                  context.l10n!.externalRecommendations,
                  FluentIcons.channel_share_24_regular,
                  description: context.l10n!.externalRecommendationsDescription,
                  borderRadius: commonCustomBarRadiusLast,
                  trailing: Switch(
                    value: value,
                    onChanged: (value) =>
                        _toggleExternalRecommendations(context, value),
                  ),
                );
              },
            ),
          if (!isFdroidBuild && isMobilePlatform)
            ValueListenableBuilder<bool?>(
              valueListenable: shouldWeCheckUpdates,
              builder: (_, value, __) {
                return CustomBar(
                  context.l10n!.automaticUpdateChecks,
                  FluentIcons.arrow_sync_24_regular,
                  description: context.l10n!.automaticUpdateChecksDescription,
                  borderRadius: offlineMode.value
                      ? commonCustomBarRadiusLast
                      : BorderRadius.zero,
                  trailing: Switch(
                    value: value ?? false,
                    onChanged: (value) =>
                        _toggleAutomaticUpdateChecks(context, value),
                  ),
                );
              },
            ),
          if (online && !isFdroidBuild && isMobilePlatform)
            CustomBar(
              context.l10n!.downloadAppUpdate,
              FluentIcons.arrow_download_24_regular,
              borderRadius: commonCustomBarRadiusLast,
              onTap: checkAppUpdates,
            ),
        ]),
        _group(strings.catAbout, const Color(0xFF8E8E93), [
          CustomBar(
            context.l10n!.licenses,
            FluentIcons.document_24_regular,
            borderRadius: commonCustomBarRadiusFirst,
            onTap: () => NavigationManager.router.go('/settings/license'),
          ),
          CustomBar(
            context.l10n!.translate,
            FluentIcons.translate_24_regular,
            description: context.l10n!.translateDescription,
            onTap: () =>
                launchURL(Uri.parse('https://crowdin.com/project/musify')),
          ),
          ValueListenableBuilder<int>(
            valueListenable: logger.logCount,
            builder: (context, logCount, _) => CustomBar(
              '${context.l10n!.copyLogs} ($logCount)',
              FluentIcons.error_circle_24_regular,
              onTap: () async =>
                  showToast(context, await logger.copyLogs(context)),
            ),
          ),
          CustomBar(
            context.l10n!.about,
            FluentIcons.book_information_24_regular,
            borderRadius: commonCustomBarRadiusLast,
            onTap: () => NavigationManager.router.go('/settings/about'),
          ),
        ]),
        if (online) _buildSponsorSection(context),
      ],
    );
  }

  Widget _group(String title, Color tint, List<Widget> rows) => rows.isEmpty
      ? const SizedBox.shrink()
      : OngakuSettingsGroup(title: title, tint: tint, children: rows);

  Widget _buildSponsorSection(BuildContext context) {
    return Column(
      children: [
        SectionHeader(
          title: context.l10n!.sponsorProject,
          icon: FluentIcons.star_24_filled,
        ),
        // Ongaku: Orikami first, then Musify's creator.
        const OngakuSponsorCards(),
      ],
    );
  }

  void _showAccentColorPicker(BuildContext context) {
    if (isDesktopPlatform) {
      _showPickerDialog(
        context,
        title: context.l10n!.accentColor,
        content: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 10,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
          ),
          itemCount: availableColors.length,
          itemBuilder: (context, index) {
            final color = availableColors[index];
            final isSelected = color == primaryColorSetting;

            return InkWell(
              customBorder: const CircleBorder(),
              onTap: () => _selectAccentColor(context, color),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: isSelected
                      ? Border.all(
                          color: Theme.of(context).colorScheme.onSurface,
                          width: 3,
                        )
                      : null,
                ),
                child: isSelected
                    ? Icon(
                        FluentIcons.checkmark_20_filled,
                        color: color.computeLuminance() > 0.5
                            ? Colors.black
                            : Colors.white,
                        size: 20,
                      )
                    : null,
              ),
            );
          },
        ),
      );
      return;
    }

    final colorScheme = Theme.of(context).colorScheme;
    final dynamicOn = isAndroidPlatform && useSystemColor.value;

    showCustomBottomSheet(
      context,
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        // Ongaku: the dynamic colour switch sits above the colours.
        child: ongakuAccentSheet(
          context,
          dynamicColor: isAndroidPlatform
              ? CustomBar(
                  context.l10n!.dynamicColor,
                  FluentIcons.toggle_left_24_regular,
                  description: context.l10n!.dynamicColorDescription,
                  trailing: Switch(
                    value: useSystemColor.value,
                    onChanged: (value) {
                      _toggleSystemColor(context, value);
                      ongakuClosePicker(context);
                    },
                  ),
                )
              : null,
          colors: GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 5,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
          ),
          shrinkWrap: true,
          physics: const BouncingScrollPhysics(),
          itemCount: availableColors.length,
          itemBuilder: (context, index) {
            final color = availableColors[index];
            final isSelected = !dynamicOn && color == primaryColorSetting;

            return GestureDetector(
              onTap: () => _selectAccentColor(context, color),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: isSelected
                      ? Border.all(color: colorScheme.onSurface, width: 3)
                      : null,
                ),
                child: isSelected
                    ? Icon(
                        FluentIcons.checkmark_20_filled,
                        color: color.computeLuminance() > 0.5
                            ? Colors.black
                            : Colors.white,
                        size: 24,
                      )
                    : null,
              ),
            );
          },
          ),
        ),
      ),
    );
  }

  void _selectAccentColor(BuildContext context, Color color) {
    addOrUpdateData<int>('settings', 'accentColor', color.toARGB32());
    Musify.updateAppState(
      context,
      newAccentColor: color,
      useSystemColor: false,
    );
    showToast(context, context.l10n!.accentChangeMsg);
    ongakuClosePicker(context);
  }

  void _showThemeModePicker(BuildContext context) {
    final availableModes = [ThemeMode.system, ThemeMode.light, ThemeMode.dark];
    final modeIcons = [
      if (isDesktopPlatform)
        FluentIcons.desktop_24_regular
      else
        FluentIcons.phone_24_regular,
      FluentIcons.weather_sunny_24_regular,
      FluentIcons.weather_moon_24_regular,
    ];
    final modeNames = [
      context.l10n!.themeModeSystem,
      context.l10n!.themeModeLight,
      context.l10n!.themeModeDark,
    ];

    Widget buildModeBar(int index) {
      final mode = availableModes[index];

      return BottomSheetBar(
        modeNames[index],
        () {
          addOrUpdateData<int>('settings', 'themeIndex', mode.index);
          Musify.updateAppState(context, newThemeMode: mode);
          ongakuClosePicker(context);
        },
        themeMode == mode,
        icon: modeIcons[index],
      );
    }

    if (isDesktopPlatform) {
      _showPickerDialog(
        context,
        title: context.l10n!.themeMode,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < availableModes.length; index++)
              buildModeBar(index),
          ],
        ),
      );
      return;
    }

    showCustomBottomSheet(
      context,
      ListView.builder(
        shrinkWrap: true,
        physics: const BouncingScrollPhysics(),
        padding: commonListViewBottomPadding,
        itemCount: availableModes.length,
        itemBuilder: (context, index) => buildModeBar(index),
      ),
    );
  }

  void _showLanguagePicker(BuildContext context) {
    final availableLanguages = appLanguages.toList();
    final activeLanguageCode = Localizations.localeOf(context).languageCode;
    final activeScriptCode = Localizations.localeOf(context).scriptCode;
    final activeLanguageFullCode = activeScriptCode != null
        ? '$activeLanguageCode-$activeScriptCode'
        : activeLanguageCode;

    Widget buildLanguageBar(int index) {
      final language = availableLanguages[index];
      final newLocale = getLocaleFromLanguageCode(language);
      final newLocaleFullCode = newLocale.scriptCode != null
          ? '${newLocale.languageCode}-${newLocale.scriptCode}'
          : newLocale.languageCode;

      return BottomSheetBar(getLanguageDisplayName(context, language), () {
        addOrUpdateData<String>('settings', 'languageCode', newLocaleFullCode);
        Musify.updateAppState(context, newLocale: newLocale);
        showToast(context, context.l10n!.languageMsg);
        ongakuClosePicker(context);
      }, activeLanguageFullCode == newLocaleFullCode);
    }

    if (isDesktopPlatform) {
      _showPickerDialog(
        context,
        title: context.l10n!.language,
        height: 460,
        content: ListView.builder(
          padding: commonListViewBottomPadding,
          itemCount: availableLanguages.length,
          itemBuilder: (context, index) => buildLanguageBar(index),
        ),
      );
      return;
    }

    showCustomBottomSheet(
      context,
      ListView.builder(
        shrinkWrap: true,
        physics: const BouncingScrollPhysics(),
        padding: commonListViewBottomPadding,
        itemCount: availableLanguages.length,
        itemBuilder: (context, index) => buildLanguageBar(index),
      ),
    );
  }

  void _showAudioQualityPicker(BuildContext context) {
    final availableQualities = ['low', 'medium', 'high'];
    final qualityNames = [
      context.l10n!.audioQualityLow,
      context.l10n!.audioQualityMedium,
      context.l10n!.audioQualityHigh,
    ];
    const qualityIcons = [
      FluentIcons.speaker_1_24_regular,
      FluentIcons.speaker_2_24_regular,
      FluentIcons.speaker_2_24_filled,
    ];

    Widget buildQualityBar(int index) {
      final quality = availableQualities[index];

      return BottomSheetBar(
        qualityNames[index],
        () {
          addOrUpdateData<String>('settings', 'audioQuality', quality);
          audioQualitySetting.value = quality;
          showToast(context, context.l10n!.audioQualityMsg);
          ongakuClosePicker(context);
        },
        audioQualitySetting.value == quality,
        icon: qualityIcons[index],
      );
    }

    if (isDesktopPlatform) {
      _showPickerDialog(
        context,
        title: context.l10n!.audioQuality,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < availableQualities.length; index++)
              buildQualityBar(index),
          ],
        ),
      );
      return;
    }

    showCustomBottomSheet(
      context,
      ListView.builder(
        shrinkWrap: true,
        physics: const BouncingScrollPhysics(),
        padding: commonListViewBottomPadding,
        itemCount: availableQualities.length,
        itemBuilder: (context, index) => buildQualityBar(index),
      ),
    );
  }

  void _showPickerDialog(
    BuildContext context, {
    required String title,
    required Widget content,
    double? height,
  }) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          content: SizedBox(width: 420, height: height, child: content),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                MaterialLocalizations.of(dialogContext).cancelButtonLabel,
              ),
            ),
          ],
        );
      },
    );
  }

  void _toggleSystemColor(BuildContext context, bool value) {
    addOrUpdateData<bool>('settings', 'useSystemColor', value);
    useSystemColor.value = value;
    Musify.updateAppState(
      context,
      newAccentColor: primaryColorSetting,
      useSystemColor: value,
    );
    showToast(context, context.l10n!.settingChangedMsg);
  }

  void _togglePureBlack(BuildContext context, bool value) {
    addOrUpdateData<bool>('settings', 'usePureBlackColor', value);
    usePureBlackColor.value = value;
    Musify.updateAppState(context);
    showToast(context, context.l10n!.settingChangedMsg);
  }

  Future<void> _toggleWrapped(BuildContext context, bool value) async {
    if (!value) {
      audioHandler.resetListeningStatsSession(
        countCurrentTick: true,
        flushStats: false,
      );
      await listeningStatsService.flush();
    }

    await addOrUpdateData<bool>('settings', 'wrappedEnabled', value);
    wrappedEnabled.value = value;
    listeningStatsService.reload();
    if (value) {
      audioHandler.startListeningStatsSessionIfNeeded();
    }
    if (context.mounted) {
      showToast(context, context.l10n!.settingChangedMsg);
    }
  }

  void _toggleOfflineMode(BuildContext context, bool value) {
    addOrUpdateData<bool>('settings', 'offlineMode', value);
    offlineMode.value = value;

    // Trigger router refresh and notify about the change
    NavigationManager.refreshRouter();

    showToast(context, context.l10n!.settingChangedMsg);
  }

  void _toggleSponsorBlock(BuildContext context, bool value) {
    addOrUpdateData<bool>('settings', 'sponsorBlockSupport', value);
    sponsorBlockSupport.value = value;
    showToast(context, context.l10n!.settingChangedMsg);
  }

  void _toggleAutoPlayNext(BuildContext context, bool value) {
    addOrUpdateData<bool>('settings', 'playNextSongAutomatically', value);
    playNextSongAutomatically.value = value;
    showToast(context, context.l10n!.settingChangedMsg);
  }

  void _toggleAutomaticUpdateChecks(BuildContext context, bool value) {
    addOrUpdateData<bool>('settings', 'shouldWeCheckUpdates', value);
    shouldWeCheckUpdates.value = value;
    showToast(context, context.l10n!.settingChangedMsg);
  }

  void _toggleExternalRecommendations(BuildContext context, bool value) {
    addOrUpdateData<bool>('settings', 'externalRecommendations', value);
    externalRecommendations.value = value;
    showToast(context, context.l10n!.settingChangedMsg);
  }

  void _showConfirmationDialog({
    required BuildContext context,
    required String confirmationMessage,
    required VoidCallback onSubmit,
    String? submitMessage,
    bool isDangerous = false,
  }) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return ConfirmationDialog(
          submitMessage: submitMessage ?? context.l10n!.clear,
          confirmationMessage: confirmationMessage,
          isDangerous: isDangerous,
          onCancel: () => Navigator.of(context).pop(),
          onSubmit: () {
            Navigator.of(context).pop();
            onSubmit();
          },
        );
      },
    );
  }

  Future<void> _backupUserData(BuildContext context) async {
    try {
      final result = await backupData(context);
      if (context.mounted) {
        showToast(
          context,
          result.message,
          icon: result.success ? null : FluentIcons.error_circle_24_regular,
        );
      }
    } catch (e, stackTrace) {
      logger.log('Error backing up data', error: e, stackTrace: stackTrace);
      if (context.mounted) {
        showToast(
          context,
          context.l10n!.error,
          icon: FluentIcons.error_circle_24_regular,
        );
      }
    }
  }
}
