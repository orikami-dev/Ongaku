/*
 *     Ongaku — an Apple Music style edition of Musify.
 *     Based on Musify, Copyright (C) 2026 Valeri Gokadze.
 *
 *     This program is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version. See <https://www.gnu.org/licenses/>.
 */

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

/// Upstream project this app is based on (credited in the About page).
const upstreamName = 'Musify';
const upstreamUrl = 'https://github.com/gokadzev/Musify';
