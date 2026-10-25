/*
 *     Ongaku — an Apple Music style edition of Musify.
 *     Based on Musify, Copyright (C) 2026 Valeri Gokadze.
 *
 *     This program is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version. See <https://www.gnu.org/licenses/>.
 */

import 'dart:ui' show PlatformDispatcher;

import 'package:musify/localization/app_localizations.dart';

/// Everything that names the app lives here, so upstream Musify files only
/// need a one-line reference instead of a hard-coded name.
const appName = 'Ongaku';

/// Android application id (must match android/app/build.gradle.kts).
const androidApplicationId = 'com.orikami.ongaku';

/// GitHub repository that publishes Ongaku releases (used by update checks).
/// Change these two values once the fork is pushed to GitHub.
const releaseRepoOwner = 'orikami-dev';
const releaseRepoName = 'ongaku';

const updateCheckUrl =
    'https://raw.githubusercontent.com/$releaseRepoOwner/$releaseRepoName/update/check.json';
const latestReleaseApiUrl =
    'https://api.github.com/repos/$releaseRepoOwner/$releaseRepoName/releases/latest';
const apkDownloadFilename = '$appName.apk';

/// Ongaku's own version, not Musify's, from 1.0 on: 1.0.x for upstream
/// fixes only, 1.x.0 for a visible feature, x.0 for a redesign. Keep it in
/// step with `version:` in pubspec.yaml, whose version code only goes up
/// (1.0.0+1300 follows the test builds v1 to v12, codes 100 to 1200).
const ongakuVersion = '1.2';

/// Ongaku's author, credited first on the About and sponsor sections.
const ongakuAuthor = 'Orikami';

/// Ongaku's public repository and donation page. Shown dimmed ("bientôt
/// disponible") until they exist: set them once they are online.
const String? ongakuRepoUrl = null;
const String? ongakuSponsorUrl = null;

/// Upstream project this app is based on (credited in the About page).
const upstreamName = 'Musify';
const upstreamUrl = 'https://github.com/gokadzev/Musify';
const upstreamSponsorUrl = 'https://ko-fi.com/gokadzev';

/// Language used until the user picks one: the phone's, when the app has
/// it, otherwise English (Musify always starts in English).
String ongakuDefaultLanguageCode() {
  final code = PlatformDispatcher.instance.locale.languageCode;
  return AppLocalizations.supportedLocales.any((l) => l.languageCode == code)
      ? code
      : 'en';
}
