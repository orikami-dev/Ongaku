/*
 *     Ongaku — an Apple Music style edition of Musify.
 *     Based on Musify, Copyright (C) 2026 Valeri Gokadze.
 *
 *     This program is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version. See <https://www.gnu.org/licenses/>.
 */

import 'dart:convert';
import 'dart:io';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:musify/main.dart' show logger;
import 'package:musify/ongaku/brand.dart';
import 'package:musify/ongaku/l10n/ongaku_strings.dart';
import 'package:musify/services/router_service.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/services/update_manager.dart';
import 'package:musify/utilities/flutter_toast.dart';
import 'package:musify/widgets/auto_format_text.dart';
import 'package:ongaku_sound/ongaku_sound.dart';
import 'package:path_provider/path_provider.dart';

/// Settings > Rechercher une mise à jour: always says what it found, where
/// Musify's check stays silent when there is nothing new.
Future<void> ongakuCheckUpdatesNow(BuildContext context) async {
  final strings = OngakuStrings.of(context);
  showToast(
    context,
    strings.updateChecking,
    icon: FluentIcons.arrow_sync_24_regular,
  );
  String? latest;
  try {
    final response = await http
        .get(Uri.parse(updateCheckUrl))
        .timeout(const Duration(seconds: 12));
    if (response.statusCode == 200) {
      final map = json.decode(response.body) as Map<String, dynamic>;
      latest = map['version']?.toString();
    }
  } catch (e) {
    logger.log('Ongaku update check failed', error: e);
  }
  if (!context.mounted) return;
  if (latest == null) {
    showToast(
      context,
      strings.updateFailed,
      icon: FluentIcons.cloud_off_24_regular,
    );
  } else if (isLatestVersionHigher(ongakuVersion, latest)) {
    ScaffoldMessenger.of(context).clearSnackBars();
    // Musify's dialog: release notes, download and install.
    await checkAppUpdates();
  } else {
    showToast(context, strings.upToDate(ongakuVersion));
  }
}

/// Automatic updates are on from 1.3 (Orikami's choice), once: whoever
/// turns them off afterwards keeps them off.
void ongakuEnableAutoUpdatesOnce() {
  try {
    final settings = Hive.box('settings');
    if (settings.get('ongakuAutoUpdatesOn') == true) return;
    settings
      ..put('ongakuAutoUpdatesOn', true)
      ..put('shouldWeCheckUpdates', true);
    shouldWeCheckUpdates.value = true;
  } catch (e) {
    logger.log('Ongaku auto updates', error: e);
  }
}

/// Name of the downloaded update, in the cache folder Android's installer
/// can read (the one the share sheet uses).
const _updateFile = 'ongaku-update.apk';

/// Why a downloaded APK must not be installed, or null when it can be: it
/// must be Ongaku, newer than this version, signed with the same key as
/// the installed app and, when check.json gives one, have that SHA-256.
@visibleForTesting
String? ongakuUpdateProblem(
  Map<String, Object?> info, {
  required int currentCode,
  String? expectedSha256,
}) {
  final signers = (info['signers'] as List?)?.map((e) => '$e').toSet() ?? {};
  final installed =
      (info['installedSigners'] as List?)?.map((e) => '$e').toSet() ?? {};
  if (info['package'] == null || info['package'] != info['installedPackage']) {
    return 'not Ongaku';
  }
  if (signers.isEmpty ||
      signers.length != installed.length ||
      !signers.containsAll(installed)) {
    return 'not signed with the same key';
  }
  final code = (info['versionCode'] as num?)?.toInt() ?? 0;
  if (code <= currentCode) return 'not newer';
  final expected = expectedSha256?.trim().toLowerCase() ?? '';
  if (expected.isNotEmpty && info['sha256'] != expected) {
    return 'sha256 does not match';
  }
  return null;
}

/// Ongaku's update: downloads the new version, checks it (same signing
/// key, newer, the SHA-256 from check.json), then offers to install it.
/// Android still asks the user before installing. Returns false when the
/// download failed, so Musify's dialog (download in the browser) shows.
Future<bool> ongakuOfferUpdate(
  Map<String, dynamic> check,
  String version,
  String notes,
) async {
  if (kIsWeb || !Platform.isAndroid) return false;
  final File file;
  try {
    final dir = Directory('${(await getTemporaryDirectory()).path}/share_plus')
      ..createSync(recursive: true);
    file = File('${dir.path}/$_updateFile');
    final url = await getDownloadUrl(check);
    final request = await http.Client().send(
      http.Request('GET', Uri.parse(url)),
    );
    if (request.statusCode != 200) {
      logger.log('Ongaku update download: ${request.statusCode}');
      return false;
    }
    final sink = file.openWrite();
    await request.stream.pipe(sink);
  } catch (e, stackTrace) {
    logger.log('Ongaku update download', error: e, stackTrace: stackTrace);
    return false;
  }

  final context = NavigationManager().context;
  final strings = OngakuStrings.of(context);
  final arm64 = (await getCPUArchitecture()).contains('aarch64');
  final expected = (arm64 ? check['arm64sha256'] : null) ?? check['sha256'];
  String? problem;
  try {
    problem = ongakuUpdateProblem(
      await OngakuSound.apkInfo(file.path),
      currentCode: ongakuVersionCode,
      expectedSha256: expected?.toString(),
    );
  } catch (e) {
    problem = 'unreadable ($e)';
  }
  if (problem != null) {
    logger.log('Ongaku update refused: $problem');
    try {
      file.deleteSync();
    } catch (_) {}
    if (context.mounted) showToast(context, strings.updateRefused);
    return true;
  }
  if (!context.mounted) return true;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => _UpdateReady(version: version, notes: notes),
  );
  return true;
}

class _UpdateReady extends StatelessWidget {
  const _UpdateReady({required this.version, required this.notes});

  final String version;
  final String notes;

  Future<void> _install(BuildContext context) async {
    final strings = OngakuStrings.of(context);
    if (!await OngakuSound.canInstallApks()) {
      if (context.mounted) showToast(context, strings.updateAllow);
      await OngakuSound.allowInstallApks();
      return;
    }
    final opened = await OngakuSound.installApk(_updateFile);
    if (!context.mounted) return;
    if (opened) {
      Navigator.of(context).pop();
    } else {
      showToast(context, strings.updateInstallFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = OngakuStrings.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return AlertDialog(
      icon: Icon(
        FluentIcons.arrow_download_24_regular,
        color: colorScheme.primary,
        size: 32,
      ),
      title: Text(strings.updateReady(version)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.updateChecked,
            style: TextStyle(
              fontSize: 14,
              color: colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          if (notes.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height / 3,
              ),
              child: SingleChildScrollView(child: AutoFormatText(text: notes)),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.updateLater),
        ),
        FilledButton(
          onPressed: () => _install(context),
          child: Text(strings.updateInstall),
        ),
      ],
    );
  }
}
