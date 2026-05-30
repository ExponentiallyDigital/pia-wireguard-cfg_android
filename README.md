# pia-wireguard-cfga

A native Android GUI app built with Flutter and Dart that generates a ready-to-use WireGuard configuration file for the Private Internet Access (PIA) VPN service. It authenticates with PIA's official provisioning API, selects the lowest-latency server in your chosen region, generates a fresh WireGuard keypair, and allows you to save the complete `.conf` to the clipboard or share/save to a user specified app/location.

This app is a GUI Android APK equivalent of my [Windows 11/Linux command line app](https://github.com/ExponentiallyDigital/pia-wireguard-cfg).

## Why use this?

Manually creating a PIA WireGuard configuration requires authenticating against multiple APIs, parsing server lists, performing key exchange, and assembling the config by hand. **pia-wireguard-cfga** automates the entire process.

## Features

- **Automated lowest-latency server selection:** measures live TCP latency against port 1337 across all available servers in your selected target region, ensuring you always provision against the fastest node.
- **Cryptographically secure keypair generation:** dynamically generates an ephemeral WireGuard keypair using `x25519` with proper RFC 7748 scalar clamping directly inside the runtime environment.
- **Dynamic certificate pinning:** fetches PIA's trusted root CA certificate dynamically at runtime from the `pia-foss/manual-connections` repository. No hardcoded certificates ensure operations continue smoothly even if PIA rotates authority roots.
- **Zero-persistence local footprint:** sensitive keys, usernames, and passwords reside exclusively as short-lived volatile variables inside system RAM (`AppState`). Config payloads are written to a named temporary file solely to preserve the correct filename through the OS share pipeline, then deleted immediately in a `finally` block once `share()` returns -- whether the share completes, is cancelled, or throws. No unencrypted files are permanently cached or retained in local storage.
- **Credential safety:** your PIA password is entered interactively at execution and used strictly to request a short-lived HTTP Basic Auth provisioning token. Credentials are never written to disk, stored, or logged.
- **Automatic session self-destruct:** includes an automatic 3-minute safety countdown timer. If the app is left idle for 3 continuous minutes while displaying a configuration, the screen UI, form states, and memory addresses are completely wiped. Active screen interactions automatically reset the clock back to a full 3 minutes.
- **Native Task-Switcher Protection (`FLAG_SECURE`):** Enforces native OS-level window flags to block third-party screenshot capturing and automatically obfuscates/blanks the app layout view inside the Android Recent Apps / Task Switcher interface.
- **Input field hardening:** user credential entry textboxes disable predictive dictionary caching, auto-correction tracking assistance, and keyboard learning behaviors, alongside native selection overrides to block background clipboard scraping.
- **Modern adaptive styling:** fully supports Android 8.0+ Adaptive Icons using a native multi-layered presentation conforming to a dark-mode theme aesthetic (`#12141A`).
- **Android permissions:** none are requested/required.

## Pre-built releases

If you don't want to compile the app from scratch, pre-packaged release archives are available under the **Releases** section of this GitHub repository.

Each release contains a compiled, production-ready `.zip` archive containing:

- The optimised Android application (`pia-wireguard-cfga.apk`) and SHA1 (`pia-wireguard-cfga.sha1`)
- Offline documentation (`README.html`, `README.md` and `LICENSE`)

## Interface

App screen:

![Screenshot: pia-wireguard-cfga UI](./images/interface.png)

Filterable region selection:

![Screenshot: region selection](./images/region-selection.png)

Generated config file:

![Screenshot: generated config](./images/generated-config.png)

## Build setup

If you prefer to compile and test the application locally, follow the configuration steps below.

### Prerequisites

- **Flutter SDK:** version 3.10 or later ([Flutter installation guide](https://flutter.dev/docs/get-started/install))
- **Android SDK / Studio:** [download Android Studio](https://developer.android.com/studio) and configure with Java Development Kit (JDK 17), also install Android SDK Command-line Tools and check your config with `flutter doctor`
- A connected physical Android device (with USB Debugging enabled) or an active Android Virtual Device (AVD) Emulator.

### 1. Install dependencies

Pull the tracking package constraints defined within the project manifests:

```bash
flutter pub get
```

### 2. Generate assets (launcher icons)

The app leverages the `flutter_launcher_icons` framework to generate adaptive foreground and background configurations for Android launchers. Before your initial compilation, generate the native resource files:

```bash
dart run flutter_launcher_icons
```

### 3. Run locally for testing

To run a hot-reloaded debug instance directly onto your attached mobile workspace:

```bash
flutter run
```

### 4. Build release APK

To create a standalone production compilation targeted for distribution:

```bash
flutter build apk --release
```

#### Local output destinations

- Standard Flutter pipeline archive: build/app/outputs/flutter-apk/app-release.apk
- Gradle pipeline build output: build/app/outputs/apk/release/pia-wireguard-cfga-release.apk

### 5. Sideload

To push the compiled binaries directly onto your phone via Android Debug Bridge (ADB):

```bash
adb install build/app/outputs/flutter-apk/app-release.apk
```

or sideload via your favorite app (I prefer X-plore).

## How it works

The provisioning logic in `lib/pia_service.dart` is a direct Dart translation of the command line version's [Go code](https://github.com/ExponentiallyDigital/pia-wireguard-cfg/blob/main/main.go), implementing the same steps in the same order:

1. **Server discovery**: pulls the complete endpoints mapping directly from serverlist.piaservers.net/vpninfo/servers/v6. The payload splits at the first newline boundary to discard the payload block signature.
2. **Latency probes**: dispatches immediate TCP probes to port 1337 across regional candidate blocks to calculate routing latency.
3. **Session tokens**: challenges the central API through a standard POST request over TLS, securing an execution token from basic user parameters.
4. **Keypair issuance**: generate WireGuard keypair using X25519 with RFC 7748 scalar clamping  
   (k[0] &= 248, k[31] &= 127, k[31] |= 64)
5. **Secure registration**: submits the dynamic public key configuration to the chosen low-latency endpoint via an HTTPS API (port 1337). The step utilises the dynamically resolved PIA root certificate, matching the specific Common Name (CN) mapping fields rather than raw IP routing addresses. The certificate is not hardcoded, so that it stays current when PIA rotates it.
6. **Config assembly**: transforms payload metadata returns into localised .conf specifications utilising Unix line endings (\n) for cross-compatibility.

### Sample output

```
[Interface]
PrivateKey = <freshly generated private key>
Address    = <client IP assigned by PIA>
DNS        = 9.9.9.9, 149.112.112.112
MTU        = 1420

[Peer]
PublicKey           = <server public key from PIA>
Endpoint            = <server IP:port from PIA>
PersistentKeepalive = 25
AllowedIPs          = 0.0.0.0/0
```

## Output & session destruction

The generated configuration data lifecycle is managed under a high-security paradigm:

- **Ephemeral verification:** displayed on-screen inside an obscured text viewport for instant validation.
- **Transient streaming:** shareable seamlessly using Android's system share sheet (e.g., via "Save to Files" or encrypted side-channels) via localized memory stream descriptors.
- **Manual clear:** the "Clear" action button scrubs the username, password, and displayed config on screen data.
- **Safety timeout clock:** adjacent to the "Clear" action button, a real-time countdown widget tracks session idle state, executing a complete memory and view scrub if the application interface goes completely untouched for 3 consecutive minutes.

## Notes

- **Time-to-live constraints**: PIA Wireguard configs expire every few weeks per PIA's token handling, requiring you to regenerate a config file periodically (which is why this app exists!).
- **Key safety**: the generated config contains private encryption keys. Treat them like a password and manage them securely.
- **Network requirements**: an active internet connection is required to resolve remote lookup tables and register credentials with API endpoints.

## Package dependencies

| Package             | Purpose                                                                                  |
| ------------------- | ---------------------------------------------------------------------------------------- |
| `http`              | HTTP REST connection pipelines to PIA APIs                                               |
| `x25519`            | Ephemeral WireGuard keypair generation                                                   |
| `share_plus`        | Share/save config file via Android share sheet                                           |
| `package_info_plus` | Querying app package metadata dynamically from `pubspec.yaml` to unify version reporting |

## Development "to do" list

1. Release to Play Store
2. Full external app security audit
3. ADD to docs: onscreen logging added
4. ADD to docs: replace screenshots
5. FIX: still can't install over an existing copy of the app, have to manually uninstall first
6. CHG: review all log messaages

## Contributing

Contributions are welcome. To contribute:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Ensure code formatting is clean (`flutter format .` and `flutter analyze`)
5. Push to the branch (`git push origin feature/AmazingFeature`)
6. Open a Pull Request

## Bugs and feature requests

Found a bug or want to request a feature? [Open an issue here](https://github.com/ExponentiallyDigital/pia-wireguard-cfga/issues).

## Support

This tool is unsupported and may cause objects in mirrors to be closer than they appear. Batteries not included.

## License

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program. If not, see <https://www.gnu.org/licenses/>.

Copyright (C) 2026 Andrew Newbury.
