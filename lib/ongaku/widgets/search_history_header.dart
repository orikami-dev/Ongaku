/*
 *     Ongaku — an Apple Music style edition of Musify.
 *     Based on Musify, Copyright (C) 2026 Valeri Gokadze.
 *
 *     This program is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version. See <https://www.gnu.org/licenses/>.
 */

import 'package:material_ui/material_ui.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/ongaku/l10n/ongaku_strings.dart';
import 'package:musify/screens/search_page.dart' show searchHistoryNotifier;
import 'package:musify/services/data_manager.dart';
import 'package:musify/utilities/flutter_toast.dart';
import 'package:musify/widgets/confirmation_dialog.dart';

/// Asks, then forgets every past search (moved here from the settings).
Future<void> ongakuClearSearchHistory(BuildContext context) async {
  final l10n = context.l10n!;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => ConfirmationDialog(
      confirmationMessage: l10n.clearSearchHistoryQuestion,
      submitMessage: OngakuStrings.of(context).clear,
      onCancel: () => Navigator.of(dialogContext).pop(),
      onSubmit: () {
        Navigator.of(dialogContext).pop();
        searchHistoryNotifier.value = [];
        deleteData('user', 'searchHistory');
        showToast(context, '${l10n.searchHistoryMsg}!');
      },
    ),
  );
}

/// "Recent searches" above the search history, with "Clear" on the right.
class OngakuSearchHistoryHeader extends StatelessWidget {
  const OngakuSearchHistoryHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = OngakuStrings.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 0, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              strings.recentSearches,
              style: TextStyle(
                fontFamily: 'Inter',
                color: colorScheme.onSurface,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
          ),
          TextButton(
            onPressed: () => ongakuClearSearchHistory(context),
            child: Text(
              strings.clear,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
