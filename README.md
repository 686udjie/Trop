# Trop

A free and open source YouTube Music client for iOS.

| | | |
|:---:|:---:|:---:|
| ![](.github/assets/1.jpg) | ![](.github/assets/2.jpg) | ![](.github/assets/3.jpg) |

## Features

- No ads
- Stream songs and videos from YouTube Music
- Synced lyrics (Musixmatch, Netease, Kugou, LRCLIB, Genius)
- Library sync (playlists, albums, artists, podcasts)
- Downloads
- Equalizer
- Custom app icons and themes
- Queue management and listening history

## Installation

Requires iOS 26 or later and a YouTube Music account (sign in through the in-app web view).

### Feather / AltStore / SideStore

Add the Trop source, then install the nightly IPA (unsigned — your client re-signs it with your Apple ID):

```
https://raw.githubusercontent.com/686udjie/Trop/main/altstore.json
```

One-tap add links:

- [Add to Feather](feather://source/add?url=https://raw.githubusercontent.com/686udjie/Trop/main/altstore.json)
- [Add to AltStore](altstore://source?url=https://raw.githubusercontent.com/686udjie/Trop/main/altstore.json)
- [Add to SideStore](sidestore://source?url=https://raw.githubusercontent.com/686udjie/Trop/main/altstore.json)

Nightlies are published from each successful push to `main` as the floating [`nightly`](../../releases/tag/nightly) release.

### Manual Installation

The latest stable IPA is on the [releases page](../../releases). Nightly IPAs are also built on each commit via [Actions](../../actions). You can also build an unsigned IPA yourself with `./build_ipa.sh` (output at `build/Trop.ipa`).

## Notable mentions

- [InnerTubeX](https://github.com/MetrolistGroup/innertubex) — eXtended InnerTube API library for Kotlin
- [zemer-cipher](https://github.com/ZemerTeam/zemer-cipher) — YouTube cipher deobfuscation and PoToken generation
- [Metrolist](https://github.com/MetrolistGroup/Metrolist) — YouTube Music client for Android

## Community

Join the [Discord server](https://discord.gg/QrMwZAfU97) for support and discussion.

## License

This repo is licensed under [GPLv3](LICENSE.txt). Trop is not affiliated with, endorsed, or sponsored by Google or YouTube.
