z# RemoteDeck

RemoteDeck is an unofficial native SwiftUI client for streaming a console you own to an iPhone. It targets iOS 16.0 and uses Microsoft's Xbox sign-in and home-streaming services to discover and wake your Xbox, negotiate a WebRTC stream, and send controller input from a paired Bluetooth controller or the touch overlay.

The project is configured for iOS 16.0 and is intended for devices such as an iPhone running iOS 16.7.16. This Windows-only development workflow cannot verify behavior on a physical iPhone.

RemoteDeck is an independent community project. It is not affiliated with, endorsed by, or supported by Microsoft or Apple. Use it only with your own console and games you own. Xbox service protocols can change without notice; a build can stop working when Microsoft changes them.

## What it includes

- Microsoft public-client device-code sign-in, Xbox user/XSTS token exchange, and Keychain token storage.
- Xbox account console listing and Wake-on-LAN command through Microsoft's Xbox services.
- Home-stream session provisioning, SDP and ICE signaling, WebRTC video/audio receive, and input/control/message/chat data channels.
- H.264-first SDP, 720p/1080p selection, configurable video bitrate, connection state, latency/FPS overlay, and reconnect attempts.
- GameController input sampling for Xbox controllers paired in iOS Bluetooth settings, plus a touch controller overlay.
- iOS 16-compatible SwiftUI UI, with no paid service, private backend, ads, analytics, telemetry, user-provided API key/secret, or Apple provisioning capability.

The project is protocol-driven and has not been built on the author's Windows machine. The GitHub Actions workflow is the supported build and simulator-test path. A passing CI build verifies compilation and unit tests, not access to a physical Xbox or Microsoft's live streaming service.

## Build and test on GitHub Actions

The workflow in `.github/workflows/ios.yml` runs for pushes to `main`, pull requests to `main`, tags matching `v*`, and manual `workflow_dispatch` runs. GitHub-hosted standard runners are free for public repositories under GitHub Actions' public-repository usage policy. The workflow uses a macOS runner to:

1. Install XcodeGen, generate `RemoteDeck.xcodeproj`, and resolve the pinned Swift package.
2. Run the iOS simulator unit tests using `xcodebuild`.
3. Archive the app without code signing and create `RemoteDeck.ipa` with the expected `Payload/RemoteDeck.app` layout.
4. Upload the IPA as a 14-day Actions artifact and attach it to a GitHub release when a `v*` tag is pushed.

No Apple Developer account, signing certificate, provisioning profile, or GitHub secret is required for CI. The resulting IPA is unsigned and must be signed by Sideloadly before installation.

### Create the GitHub repository and push from PowerShell

Install Git for Windows, open PowerShell, and create a **public** empty repository on GitHub named `RemoteDeck` (do not initialize it with a README or license). Then run:

```powershell
Set-Location "$HOME\Documents\RemoteDeck"
git init --initial-branch=main
git add .
git commit -m "Initial RemoteDeck project"
git remote add origin https://github.com/<YOUR-GITHUB-USERNAME>/RemoteDeck.git
git push -u origin main
```

Replace `<YOUR-GITHUB-USERNAME>` with your GitHub username. The first push starts the workflow. From the repository's **Actions** tab, open the latest successful run and download `RemoteDeck-unsigned-ipa`. To start a build manually, choose **iOS build and test**, select **Run workflow**, and confirm.

### Create a tagged release

After the `main` workflow succeeds, run:

```powershell
Set-Location "$HOME\Documents\RemoteDeck"
git tag -a v1.0.0 -m "RemoteDeck 1.0.0"
git push origin v1.0.0
```

The tag starts the same build and creates or updates the GitHub release with `RemoteDeck.ipa`. You can also download the IPA from the release's **Assets** list.

## Install on Windows with Sideloadly

An unsigned CI IPA cannot be opened directly on an iPhone. Use Sideloadly with your own Apple ID to sign and sideload it:

1. Install Sideloadly from its official site: [sideloadly.io](https://sideloadly.io/).
2. Install the standalone Windows versions of [iTunes](https://support.apple.com/downloads/itunes) and [iCloud for Windows](https://support.apple.com/en-us/HT204283) from Apple's website. Do not use the Microsoft Store editions; Sideloadly may not detect their Apple device components.
3. Connect the iPhone by USB, unlock it, and tap **Trust This Computer** if prompted. If it does not appear, see the troubleshooting section.
4. Download `RemoteDeck.ipa` from the successful Actions run or a GitHub release, then drag it into Sideloadly.
5. Enter your Apple ID in Sideloadly and click **Start**. Your credentials are used by Sideloadly to sign the app; they are not entered into RemoteDeck. Never give your Apple ID password to RemoteDeck.
6. After installation, enable Developer Mode on the iPhone at **Settings > Privacy & Security > Developer Mode**. This option appears after a developer-signed app is installed and enabling it requires a restart.
7. After restarting, confirm Developer Mode. If iOS asks you to trust the signing profile, go to **Settings > General > VPN & Device Management**, select the developer app/profile, and trust it.
8. Enable Sideloadly's **Auto Refresh** while the iPhone and PC can connect periodically. Free Apple IDs require re-signing about every 7 days.

Apple's free signing account has limits, including a maximum of **3 active sideloaded apps** and weekly app expiry. Sideloadly may also consume an app ID allowance. Paid developer membership is not required by this project, but is subject to different Apple limits and terms.

## Prepare your Xbox

On the console:

1. Open **Settings > Devices & connections > Remote features** and enable **Remote features**.
2. Run the remote-play test shown on that page. It checks the console and network configuration; resolve any warnings before streaming.
3. In **Settings > General > Power options**, choose the **Sleep** power mode (called **Instant-On** on some older Xbox system versions) so the console can wake remotely.
4. Confirm the Xbox is signed in to the same Microsoft account used in RemoteDeck and appears in the app's console list.
5. Pair an Xbox controller with the iPhone in **Settings > Bluetooth**. Controller button and trigger support depends on what iOS exposes for that controller model.

Streaming away from home depends on your console, home router, and internet connection supporting Xbox remote play. RemoteDeck does not operate a relay or backend; the app communicates with Microsoft Xbox sign-in/streaming services and the console's negotiated WebRTC path.

## Troubleshooting

### RemoteDeck sign-in or console list

- The device code expires; restart sign-in and enter the new code at the Microsoft URL displayed by the app.
- Confirm the account owns/has registered the console and that Remote Features are enabled.
- If Xbox returns an XSTS or home-streaming error, sign out in RemoteDeck and sign in again. Microsoft may change token requirements or device authorization.
- A console that is offline or set to energy-saving shutdown may not wake remotely. Use Sleep/Instant-On and check the Xbox Remote Features network test.

### Stream or controller

- A provisioning timeout commonly means the console is offline, Remote Features are disabled, or the home network blocks the stream path. Verify the console's remote-play test.
- Poor or unstable Wi-Fi/cellular connections can cause high latency, dropped video, or reconnects. Try a stable network and reduce resolution or bitrate in **Settings**.
- If a paired controller is not detected, reconnect it in iOS Bluetooth settings and relaunch the stream. The touch overlay is available in the player.
- Some Microsoft protocol or service changes may require an app update; consult the GitHub issue tracker before assuming a local network problem.

### Sideloadly on Windows

- **iTunes/iCloud not detected:** uninstall Microsoft Store copies, install Apple's standalone iTunes and iCloud packages, then restart Sideloadly.
- **Device missing / USB driver error:** unlock the phone, accept **Trust This Computer**, try an Apple-certified data cable and another USB port, and confirm the Apple Mobile Device USB driver is installed with the Apple software.
- **Apple ID login or app-specific password error:** confirm the Apple ID and two-factor authentication prompts in Sideloadly. Follow Sideloadly's current guidance for app-specific passwords/account security; do not put Apple ID credentials in the app or GitHub repository.
- **App no longer opens:** its free signature may have expired. Reconnect the phone and use Sideloadly Auto Refresh or sideload the IPA again.
- **Developer Mode or trust prompt missing:** install the signed app first, restart after enabling Developer Mode, then check **Settings > General > VPN & Device Management**.

## Public identifiers and protocol sources

RemoteDeck uses the public OAuth client ID `1f907974-e22b-4810-a9de-d9647380c97e` with Microsoft's consumer device-code/token endpoints and scope `xboxlive.signin openid profile offline_access`. This ID is present in the open-source Greenlight `xal-node` flow and its player transfer-token code; it is a public-client identifier, not a client secret. The streaming requests also use the service labels `XboxComBrowser`, `www.xbox.com`, and offering ID `xhome`. Microsoft may disable or restrict public identifiers at any time.

The control/message protocol constants ported from the cited public clients are the control-channel authorization value `4BDB3609-C1F1-4195-9B37-FEFF45DA8B8E`, client install ID `c97d7ee0-73b2-4239-bf1d-9d805a338429`, and the message handshake ID `be0bfc6d-1e83-4c8a-90ed-fa8601c5a179`. These are published protocol values, not account tokens. RemoteDeck does **not** use XStreaming's AppId `000000004c20a908`, TitleId `328178078`, or `ms-xal-000000004c20a908://auth` callback; it uses device-code flow and does not register a new OAuth client.

The exact sign-in endpoints are `https://login.microsoftonline.com/consumers/oauth2/v2.0/devicecode` and `/token`; the transfer-token exchange is `https://login.live.com/oauth20_token.srf` with scope `service::http://Passport.NET/purpose::PURPOSE_XBOX_CLOUD_CONSOLE_TRANSFER_TOKEN`. Xbox Live user authentication posts to `https://user.auth.xboxlive.com/user/authenticate`, followed by XSTS at `https://xsts.auth.xboxlive.com/xsts/authorize` for the `http://xboxlive.com` and `http://gssv.xboxlive.com/` relying parties. Home streaming exchanges the GSSV token at `https://xhome.gssv-play-prod.xboxlive.com/v2/login/user` with offering ID `xhome`; console wake posts to `https://xccs.xboxlive.com/commands`.

Console discovery uses `GET {regionBaseUri}/v6/servers/home`. Session signaling posts to `{regionBaseUri}/v5/sessions/home/play`, polls `/state`, posts the transfer token to `/connect`, and fetches `/configuration`. WebRTC negotiation posts an SDP offer to `/sdp` and polls `/sdp` for the exchange response; it posts `{"candidates":[...]}` to `/ice` and polls `/ice`. Keepalive posts to `/keepalive`, and stop deletes the session path. The app starts the console session, polls its state, connects it with Microsoft's console-transfer token, and exchanges SDP and ICE candidates before WebRTC media and data channels start.

The current Greenlight/player ICE request shape is `{"candidates":[...]}`. Older XStreaming documentation and source use inconsistent ICE message formats; this app follows the current Greenlight player library. Input uses the Greenlight 14-byte little-endian report header and 23-byte gamepad sample (button mask, axes, triggers, and physicality values), sent at approximately 60 Hz. The control-channel authorization value is a protocol constant also present in the cited public clients; it is not an account token or user credential. Protocol details are reverse-engineered and may become outdated.

## Dependencies and credits

| Component | Purpose | License |
|---|---|---|
| Apple iOS SDK: Swift, SwiftUI, GameController, Security, AVFoundation, Combine, Foundation | App UI, controller input, Keychain, networking and media | Apple SDK terms; included with Xcode/iOS |
| [stasel/WebRTC 158.0.0](https://github.com/stasel/WebRTC) (Google WebRTC iOS framework) | H.264-capable WebRTC media and data channels; uses the framework's VideoToolbox hardware decoder where available; package declares iOS 15+ support | BSD 3-Clause |
| [XcodeGen](https://github.com/yonaskolb/XcodeGen) | Generate the Xcode project in CI | MIT |
| GitHub Actions `checkout`, `cache`, `upload-artifact` | Public-repository CI workflow | MIT |

Protocol research and ported implementation ideas are credited to [XStreaming](https://github.com/Geocld/XStreaming) (MIT, Geocld) and [Greenlight](https://github.com/unknownskl/greenlight) / [xbox-xcloud-player](https://github.com/unknownskl/xbox-xcloud-player) (MIT, UnknownSKL). Their source checkouts are kept only in the ignored local `reference/` directory and are not included in this project. The upstream MIT notices are reproduced in [LICENSE](./LICENSE).

## Privacy and limitations

Tokens are stored in the iOS Keychain with device-only accessibility. RemoteDeck does not send telemetry or contact a third-party backend. Microsoft sign-in and Xbox streaming endpoints receive the requests needed to authenticate and connect your account and console. Do not share a build with anyone unless you trust the source.

RemoteDeck is an independent project, is not affiliated with Microsoft or Apple, and is intended only for streaming your own console and games that you own. Xbox, Xbox Live, and related marks are trademarks of Microsoft.
