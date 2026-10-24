/*
 *     Ongaku — an Apple Music style edition of Musify.
 *     Based on Musify, Copyright (C) 2026 Valeri Gokadze.
 *
 *     This program is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version. See <https://www.gnu.org/licenses/>.
 */

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/main.dart' show logger;
import 'package:musify/ongaku/import/playlist_sources.dart';
import 'package:musify/ongaku/import/track_matcher.dart';
import 'package:musify/ongaku/l10n/ongaku_strings.dart';
import 'package:musify/services/playlists_manager.dart';
import 'package:musify/utilities/flutter_toast.dart';
import 'package:musify/widgets/mini_player.dart';

/// Services a playlist can be imported from.
enum ImportSource { spotify, deezer, appleMusic, soundCloud }

/// Imports a Spotify, Deezer or Apple Music playlist with its name and
/// cover: reads its songs from a link (or an exported file), then finds each
/// one on YouTube.
class OngakuImportPlaylistPage extends StatefulWidget {
  const OngakuImportPlaylistPage({super.key, required this.source});

  final ImportSource source;

  @override
  State<OngakuImportPlaylistPage> createState() =>
      _OngakuImportPlaylistPageState();
}

class _OngakuImportPlaylistPageState extends State<OngakuImportPlaylistPage> {
  // Shared by every page instance: only one import at a time.
  static bool _importRunning = false;

  final _linkController = TextEditingController();
  final _nameController = TextEditingController();
  ImportedPlaylist? _playlist;
  bool _reading = false;
  bool _importing = false;
  int _done = 0;
  int _total = 0;

  bool get _busy => _reading || _importing;

  @override
  void dispose() {
    _linkController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  String _errorText(OngakuStrings s, ImportError error) => switch (error) {
    ImportError.invalidLink => s.importErrLink,
    ImportError.notFound => s.importErrNotFound,
    ImportError.privateOrEmpty => s.importErrPrivate,
    ImportError.network => s.importErrNetwork,
    ImportError.badFile => s.importErrFile,
  };

  Future<void> _read(Future<ImportedPlaylist> Function() reader) async {
    final strings = OngakuStrings.of(context);
    setState(() => _reading = true);
    try {
      final playlist = await reader();
      if (!mounted) return;
      // A file read after a link keeps the link's name and cover.
      final previous = _playlist;
      final merged = previous != null && playlist.image == null
          ? ImportedPlaylist(
              previous.name ?? playlist.name,
              playlist.tracks,
              image: previous.image,
            )
          : playlist;
      setState(() => _playlist = merged);
      if (_nameController.text.trim().isEmpty && merged.name != null) {
        _nameController.text = merged.name!;
      }
    } on PlaylistImportException catch (e) {
      logger.log('Ongaku import: ${e.error}', error: e.detail);
      if (mounted) showToast(context, _errorText(strings, e.error));
    } catch (e, stackTrace) {
      logger.log('Ongaku import failed', error: e, stackTrace: stackTrace);
      if (mounted) showToast(context, strings.importErrNetwork);
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  Future<void> _readLink() async {
    final link = _linkController.text.trim();
    if (link.isEmpty) {
      showToast(context, OngakuStrings.of(context).importErrLink);
      return;
    }
    FocusScope.of(context).unfocus();
    await _read(
      () => switch (widget.source) {
        ImportSource.spotify => fetchSpotifyPlaylist(link),
        ImportSource.deezer => fetchDeezerPlaylist(link),
        ImportSource.appleMusic => fetchAppleMusicPlaylist(link),
        ImportSource.soundCloud => fetchSoundCloudPlaylist(link),
      },
    );
  }

  Future<void> _chooseFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'csv', 'tsv'],
    );
    if (result.isEmpty || !mounted) return;
    final file = result.single;
    final path = file.path;
    if (path == null) return;
    await _read(
      () async => parsePlaylistFile(
        await File(path).readAsBytes(),
        fileName: file.name,
      ),
    );
  }

  Future<void> _import() async {
    final l10n = context.l10n!;
    final playlist = _playlist;
    if (playlist == null || _importing) return;
    if (_importRunning) {
      showToast(context, l10n.spotifyPlaylistAlreadyImporting);
      return;
    }
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      showToast(context, l10n.enterPlaylistName);
      return;
    }

    _importRunning = true;
    setState(() {
      _importing = true;
      _done = 0;
      _total = playlist.tracks.length;
    });
    final MatchResult result;
    try {
      result = await matchTracks(
        playlist.tracks,
        onProgress: (done, total) {
          if (mounted) {
            setState(() {
              _done = done;
              _total = total;
            });
          }
        },
      );
    } finally {
      _importRunning = false;
    }
    if (!mounted) return;

    final (_, playlistId) = createCustomPlaylist(name, playlist.image, context);
    addSongsInCustomPlaylist(context, playlistId, result.found);
    setState(() {
      _importing = false;
      _playlist = null;
    });

    final count = l10n.spotifyPlaylistImportResult(
      result.found.length,
      playlist.tracks.length,
    );
    final resultText = result.rateLimited
        ? '${l10n.spotifyPlaylistImportFailed}\n$count'
        : count;
    if (result.missing.isEmpty) {
      showToast(context, resultText);
      return;
    }
    final missingText = result.missing.join('\n');
    await Clipboard.setData(ClipboardData(text: missingText));
    if (!mounted) return;
    showToastWithButton(
      context,
      '$resultText\n${l10n.spotifyPlaylistMissingSongs}',
      l10n.copy,
      () => Clipboard.setData(ClipboardData(text: missingText)),
      duration: const Duration(seconds: 8),
      icon: FluentIcons.warning_24_regular,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n!;
    final strings = OngakuStrings.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final source = widget.source;
    final (title, help, hint) = switch (source) {
      ImportSource.spotify => (
        'Spotify',
        strings.importSpotifyHelp,
        'https://open.spotify.com/playlist/…',
      ),
      ImportSource.deezer => (
        'Deezer',
        strings.importDeezerHelp,
        'https://www.deezer.com/playlist/…',
      ),
      ImportSource.appleMusic => (
        'Apple Music',
        strings.importAppleHelp,
        'https://music.apple.com/…/playlist/…',
      ),
      ImportSource.soundCloud => (
        'SoundCloud',
        strings.importSoundCloudHelp,
        'https://soundcloud.com/…/sets/…',
      ),
    };
    final playlist = _playlist;

    InputDecoration field(String label, {String? hint}) => InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: colorScheme.surfaceContainerHigh,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );

    return Scaffold(
      appBar: AppBar(
        // The service name: the full "Import playlist from..." is cut off.
        title: Text(title),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(help),
                const SizedBox(height: 16),
                TextField(
                  controller: _linkController,
                  enabled: !_busy,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  textInputAction: TextInputAction.go,
                  onSubmitted: (_) => _readLink(),
                  decoration: field(strings.importLink, hint: hint),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : _readLink,
                  icon: _reading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(FluentIcons.link_24_regular),
                  label: Text(strings.importRead),
                ),
                if (source != ImportSource.deezer &&
                    source != ImportSource.soundCloud) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _chooseFile,
                    icon: const Icon(FluentIcons.document_add_24_regular),
                    label: Text(strings.importFile),
                  ),
                ],
                if (playlist != null) ...[
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      _Cover(url: playlist.image),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              strings.importTracksRead(playlist.tracks.length),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              playlist.tracks.take(3).join(' · ') +
                                  (playlist.tracks.length > 3 ? ' …' : ''),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _nameController,
                    enabled: !_busy,
                    decoration: field('${l10n.playlistName} *'),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _busy ? null : _import,
                    icon: _importing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(FluentIcons.arrow_download_24_regular),
                    label: Text(
                      _importing
                          ? l10n.spotifyPlaylistImporting
                          : l10n.importPlaylist,
                    ),
                  ),
                ],
                if (_importing && _total > 0) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(value: _done / _total),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.spotifyPlaylistProgress(_done, _total),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: MiniPlayer.playerHeight + 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The imported playlist's cover, or a placeholder when it has none.
class _Cover extends StatelessWidget {
  const _Cover({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final placeholder = ColoredBox(
      color: colorScheme.surfaceContainerHigh,
      child: Icon(
        FluentIcons.music_note_2_24_regular,
        color: colorScheme.onSurfaceVariant,
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox.square(
        dimension: 72,
        child: url == null
            ? placeholder
            : Image.network(
                url!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => placeholder,
              ),
      ),
    );
  }
}
