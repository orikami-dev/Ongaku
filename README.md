<p align="center">
  <img src="docs/images/ongaku-icone.png" width="128" alt="Ongaku">
</p>

<h1 align="center">Ongaku</h1>
<p align="center"><b>Listen. Breathe.</b><br>by ORIKAMI</p>

<p align="center">
  <a href="https://github.com/orikami-dev/ongaku/releases/latest">⬇️ <b>Download the latest version</b></a>
  ·
  <a href="https://github.com/orikami-dev/ongaku/releases">📦 All versions</a>
  ·
  <a href="CHANGELOG.md">📝 Changelog</a>
</p>

---

## 🎵 The project

Ongaku is a free, ad-free Android music player in the style of Apple Music. It does everything [Musify](https://github.com/gokadzev/Musify) does (search, streaming, playlists, lyrics, radios, downloads) and gives it an interface made for phones and foldables.

<p align="center">
  <img src="docs/images/captures-1.0.png" width="92%" alt="Home, player, lyrics and All songs">
</p>

| | |
|---|---|
| 🏠 **For you** | An Apple Music style home, with your playlists, your recent listening and picks. |
| 🎧 **Player** | Animated full screen, background in the colors of the artwork, synced lyrics in their own area. |
| 📁 **Local files** | The music already on your phone, next to streaming. |
| 🔊 **Calibrated sound** | One setting per output (speaker, earphones, car), with an acoustic test or a hearing test. |
| 🌙 **Soft mode** | Crossfade between songs. |
| 🚗 **Android Auto** | Your tabs and your music in the car. |
| 🔄 **Automatic updates** | New versions download by themselves and are verified before installation. |

## 🎨 Four themes

Each theme has its own colors and a matching app icon.

| Theme | In one sentence |
|---|---|
| 🖋️ **Sumi** | Indian ink, dark, with a touch of violet. |
| 📜 **Washi** | Japanese paper, light and warm. |
| 🌸 **Sakura** | The pink night of cherry blossoms. |
| 🍵 **Matcha** | The soft green of tea, in light mode. |

<p align="center">
  <img src="docs/images/themes-1.0.png" width="92%" alt="Sumi, Washi, Sakura and Matcha">
</p>

## ✨ Highlights

- 📐 Interface sized for every screen: phones, foldables, tablets.
- 📖 On a half-open foldable, the player splits: artwork or lyrics on top, controls and queue below.
- 🔤 "All songs" with an alphabetical index.
- 📥 Import of Spotify, Deezer and Apple Music playlists, with name, cover and every song.
- 📊 Listening statistics: summary and history.
- 👆 Gestures: swipe the artwork to change songs, swipe a song to like it.
- 📚 Apple Music style library, with pins and categories to your taste.
- 🚫 No ads, no subscription, SponsorBlock built in.

<p align="center">
  <img src="docs/images/pliants-1.0.png" width="92%" alt="Player on a half-open foldable and on a large screen">
</p>

## ⭐ Major updates

| Version | What it brought |
|---|---|
| [1.3.0 ⭐](https://github.com/orikami-dev/ongaku/releases/tag/v1.3.0) | Apple Music style library, gestures in the player, redesigned statistics, automatic updates. |
| [1.0 ⭐](https://github.com/orikami-dev/ongaku/releases/tag/v1.0) | First public version: split player on foldables, interface sized to the screen, Android Auto, built-in updates. |

## 🛠️ The repository

| Folder | Content |
|---|---|
| `lib/ongaku/` | All of Ongaku's own code (interface, player, sound, themes, local files) |
| `lib/` (the rest) | Musify's code, kept as is to follow its updates |
| `packages/` | Bundled packages (audio playback, extraction) |
| `docs/` | Notes of each version (`docs/releases`), images |
| `scripts/` | Sync with Musify, checks |

Build: `flutter build apk --flavor github --release --target-platform android-arm64`. The points where Ongaku touches Musify are listed in [ONGAKU.md](ONGAKU.md).

## ⚖️ Licenses

Ongaku is a modified version of [Musify](https://github.com/gokadzev/Musify) by Valeri Gokadze and its contributors, distributed like it under the GNU GPL v3.0 license (see [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md)). To support Musify: [ko-fi.com/gokadzev](https://ko-fi.com/gokadzev). Ongaku is not affiliated with Apple, YouTube, Google, Spotify or Deezer.
