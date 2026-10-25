/*
 *     Ongaku — an Apple Music style edition of Musify.
 *     Based on Musify, Copyright (C) 2026 Valeri Gokadze.
 *
 *     This program is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version. See <https://www.gnu.org/licenses/>.
 */

import 'dart:ui' show DisplayFeatureState;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/main.dart' show audioHandler;
import 'package:musify/ongaku/brand.dart';
import 'package:musify/ongaku/l10n/ongaku_strings.dart';
import 'package:musify/ongaku/local/local_library.dart';
import 'package:musify/ongaku/services/ongaku_logs.dart';
import 'package:musify/ongaku/sound/sound_engine.dart';
import 'package:musify/ongaku/sound/sound_settings.dart';
import 'package:musify/ongaku/theme/ongaku_palettes.dart';
import 'package:musify/ongaku/widgets/ongaku_page_parts.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/services/playlists_manager.dart';
import 'package:musify/utilities/flutter_toast.dart';
import 'package:ongaku_sound/ongaku_sound.dart';

/// Path of the logs export, under the Settings tab.
const logsPath = '/settings/logs';

/// "Exporter les journaux": the filtered report, to read before sending it
/// by e-mail (through the phone's mail app) or copying it.
class OngakuLogsPage extends StatefulWidget {
  const OngakuLogsPage({super.key});

  @override
  State<OngakuLogsPage> createState() => _OngakuLogsPageState();
}

class _OngakuLogsPageState extends State<OngakuLogsPage> {
  final _description = TextEditingController();
  String? _report;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_report == null) _build();
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _build() async {
    final media = MediaQuery.of(context);
    var device = const <String, Object?>{};
    try {
      device = await OngakuSound.deviceInfo();
    } catch (_) {}

    // The user's own songs, to be removed from the report.
    final songs = <Map>[
      ...userLikedSongsList.value.whereType<Map>(),
      ...userOfflineSongs.value.whereType<Map>(),
      ...userRecentlyPlayed.value.whereType<Map>(),
      ...localSongs.value,
      for (final p in userCustomPlaylists.value)
        ...((p['list'] as List?) ?? const []).whereType<Map>(),
    ];
    final queue = audioHandler.queue.valueOrNull ?? const <MediaItem>[];
    final scrubber = OngakuScrubber(
      titles: [
        for (final s in songs) s['title']?.toString() ?? '',
        for (final q in queue) q.title,
        for (final p in userCustomPlaylists.value) p['title']?.toString() ?? '',
        for (final p in userLikedPlaylists.value) p['title']?.toString() ?? '',
      ],
      artists: [
        for (final s in songs) s['artist']?.toString() ?? '',
        for (final q in queue) q.artist ?? '',
      ],
      albums: [
        for (final s in songs) s['album']?.toString() ?? '',
        for (final q in queue) q.album ?? '',
      ],
      deviceNames: [
        ...((device['names'] as List?) ?? const []).map((n) => '$n'),
        OngakuSoundEngine.route.value.name,
      ],
    );

    final size = media.size;
    final halfOpen = media.displayFeatures.any(
      (f) => f.state == DisplayFeatureState.postureHalfOpened,
    );
    final screen =
        '${size.width.round()} x ${size.height.round()} dp, '
        'x${media.devicePixelRatio.toStringAsFixed(2)}, '
        '${halfOpen
            ? 'mi-plié'
            : size.shortestSide >= 600
            ? 'déplié ou grand écran'
            : 'plié ou téléphone'}';
    final uptime = DateTime.now().difference(OngakuJournal.started);
    final route = OngakuSoundEngine.route.value;
    final report = buildOngakuReport(
      header: {
        'App': 'Ongaku $ongakuVersion ($ongakuVersionCode)',
        'Thème': ongakuPalette.value.label,
        'Android': '${device['android'] ?? '?'} (API ${device['sdk'] ?? '?'})',
        'Modèle': '${device['maker'] ?? ''} ${device['model'] ?? ''}'.trim(),
        'Écran': screen,
        'Export': DateTime.now().toString(),
        'Ouvert depuis': '${uptime.inMinutes} min',
      },
      sound: {
        'Sortie': route.type.name,
        'Son calibré': soundEnabled.value ? 'oui' : 'non',
        'Profil pour cette sortie': soundProfiles.value.containsKey(route.id)
            ? 'oui'
            : 'non',
        'Couche': soundLayer.value.name,
        'Couche Auto entendue': OngakuSoundEngine.autoLayer.value?.name ?? '-',
        'Mode doux': crossfadeMode.value.name,
      },
      journal: OngakuJournal.text,
      crash: OngakuJournal.lastCrash,
      error: OngakuJournal.lastError,
      scrubber: scrubber,
    );
    if (mounted) setState(() => _report = report);
  }

  String _full() {
    final note = _description.text.trim();
    return note.isEmpty ? _report! : 'Problème décrit :\n$note\n\n$_report';
  }

  Future<void> _send(OngakuStrings strings) async {
    final note = _description.text.trim();
    final opened = await OngakuSound.sendLogs(
      to: ongakuLogsAddress,
      subject: '[Ongaku $ongakuVersion] Journaux',
      text: note.isEmpty ? strings.logsMailBody : note,
      fileName: 'ongaku-journaux.txt',
      content: _full(),
    );
    if (!mounted) return;
    if (!opened) showToast(context, strings.logsNoMailApp);
  }

  Future<void> _copy(OngakuStrings strings) async {
    await Clipboard.setData(ClipboardData(text: _full()));
    if (mounted) showToast(context, strings.logsCopied);
  }

  @override
  Widget build(BuildContext context) {
    final strings = OngakuStrings.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final margin = ongakuPageMargin(context);
    final report = _report;

    return Scaffold(
      body: Column(
        children: [
          OngakuLargeTitle(title: strings.logsTitle, showBack: true),
          Padding(
            padding: EdgeInsets.fromLTRB(margin, 12, margin, 8),
            child: Text(
              strings.logsInfo,
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: margin),
            child: TextField(
              controller: _description,
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: strings.logsDescribe,
                filled: true,
                fillColor: colorScheme.onSurface.withValues(alpha: 0.06),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: Container(
              margin: EdgeInsets.fromLTRB(margin, 12, margin, 12),
              decoration: BoxDecoration(
                color: colorScheme.onSurface.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: report == null
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: SelectableText(
                        report,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11.5,
                          height: 1.35,
                          color: colorScheme.onSurface.withValues(alpha: 0.85),
                        ),
                      ),
                    ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              margin,
              0,
              margin,
              MediaQuery.paddingOf(context).bottom + 12,
            ),
            child: Row(
              children: [
                TextButton(
                  onPressed: () => context.pop(),
                  child: Text(strings.logsCancel),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: OutlinedButton(
                    onPressed: report == null ? null : () => _copy(strings),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(strings.logsCopy),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: report == null ? null : () => _send(strings),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(strings.logsSend),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// After a crash that closed the app: offers to export the logs once.
Future<void> ongakuOfferLogsAfterCrash(BuildContext context) async {
  String? trace;
  try {
    trace = await OngakuSound.lastCrash();
  } catch (_) {}
  if (trace == null || trace.isEmpty || !context.mounted) return;
  OngakuJournal.keepCrash(trace);
  final strings = OngakuStrings.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.showSnackBar(
    SnackBar(
      content: Text(strings.logsAfterCrash),
      duration: const Duration(seconds: 10),
      action: SnackBarAction(
        label: strings.logsExport,
        onPressed: () => context.push(logsPath),
      ),
    ),
  );
}
