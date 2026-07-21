# macOS Release

AvestaCode is distributed directly with Developer ID signing and Apple notarization. It is intentionally not App Sandbox-enabled because workspaces and Ghostty terminals need user-directed access to repositories, Git, shells, and developer tools.

## Permissions

The release signature enables Hardened Runtime and only the Apple Events automation exception. The app's `Info.plist` explains access to Desktop, Documents, Downloads, network volumes, removable volumes, and user-directed automation.

macOS does not provide entitlements that silently grant privacy access. If a workflow needs any of the following, the user must enable AvestaCode in System Settings > Privacy & Security:

- Full Disk Access, for protected locations outside chosen workspaces.
- Accessibility, if a future feature controls other applications' user interfaces.
- Screen & System Audio Recording, if a future feature captures the screen.
- Automation, when the user explicitly triggers an Apple Events integration.

Do not add hardened-runtime bypasses such as unsigned executable memory, disabled executable-page protection, DYLD environment variables, or disabled library validation unless a tested production feature requires that exact exception.

## One-time local setup

The Developer ID Application certificate and its private key must be installed in the login Keychain. Store notarization credentials in Keychain, never in this repository:

```sh
xcrun notarytool store-credentials AvestaCodeNotary \
  --apple-id "YOUR_APPLE_ID" \
  --team-id "7H66Q22DJD"
```

Enter an Apple app-specific password at the prompt.

## Build, sign, and notarize

From a clean `main` checkout:

```sh
sh Scripts/release-macos.sh 0.1.0 1
```

The script performs a clean SwiftPM release build, creates the app bundle, signs it with Hardened Runtime and a secure timestamp, submits it to Apple's notary service, staples the ticket, verifies it with Gatekeeper, and writes the final ZIP plus SHA-256 checksum under `dist/`.

The current release is ARM64. The artifact name reflects the actual Mach-O architectures and will change to `universal` when an Intel slice is added and tested.

## Publish

Publish only the notarized final archive and checksum:

```sh
gh release create v0.1.0 \
  dist/AvestaCode-0.1.0-macos-arm64.zip \
  dist/AvestaCode-0.1.0-macos-arm64.zip.sha256 \
  --title "AvestaCode 0.1.0" \
  --generate-notes
```

Never commit `.p8`, `.p12`, `.cer`, provisioning profiles, app-specific passwords, or notarization response credentials. The repository ignores the common credential file formats and the complete `dist/` directory.
