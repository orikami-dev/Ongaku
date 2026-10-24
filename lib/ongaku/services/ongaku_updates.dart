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

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:musify/main.dart' show logger;
import 'package:musify/ongaku/brand.dart';
import 'package:musify/ongaku/l10n/ongaku_strings.dart';
import 'package:musify/services/update_manager.dart';
import 'package:musify/utilities/flutter_toast.dart';

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
