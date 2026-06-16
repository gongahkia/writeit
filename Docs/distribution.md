# Distribution

## Local App Bundle

Build and ad-hoc sign:

```sh
Scripts/build_app.sh
```

Developer ID sign:

```sh
CODESIGN_IDENTITY="Developer ID Application: Team Name (TEAMID)" Scripts/build_app.sh
```

The script writes `.dist/cerberus.app`, embeds `ShellExecService.xpc` at `Contents/XPCServices`, signs nested code first, then verifies the bundle.

## Notarization

Create a notarytool profile once:

```sh
xcrun notarytool store-credentials cerberus-notary
```

Submit and staple:

```sh
NOTARY_PROFILE=cerberus-notary Scripts/notarize_app.sh
```

Notarization requires a Developer ID signature. Ad-hoc signed bundles are only for local bundle validation.
