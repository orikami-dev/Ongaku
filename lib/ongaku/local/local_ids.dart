/*
 *     Ongaku — an Apple Music style edition of Musify.
 *     Based on Musify, Copyright (C) 2026 Valeri Gokadze.
 *
 *     This program is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version. See <https://www.gnu.org/licenses/>.
 */

/// Prefix of the `ytid` given to songs imported from the device.
///
/// Kept in a dependency-free file so upstream services can check it with a
/// one-line guard before calling YouTube.
const localSongIdPrefix = 'local_';

bool isLocalSongId(Object? id) =>
    id is String && id.startsWith(localSongIdPrefix);
