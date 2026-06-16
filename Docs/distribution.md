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

## Demo Recording

Record a local demo video:

```sh
Scripts/record_demo.sh
```

The script builds `.dist/cerberus.app` if needed, opens it, and writes `.dist/demo/cerberus-demo.mov`.

Preflight without starting screen recording:

```sh
Scripts/record_demo.sh --check
```

For a timed full-display capture:

```sh
DEMO_CAPTURE_MODE=display DEMO_SECONDS=30 Scripts/record_demo.sh
```

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

## Release Readiness

Run the full pre-release gate:

```sh
CODESIGN_IDENTITY="Developer ID Application: Team Name (TEAMID)" \
NOTARY_PROFILE=cerberus-notary \
Scripts/release_check.sh
```

The script fails fast unless all release requirements are true:

- `.dist/cerberus.app` is signed with an installed Developer ID Application identity and passes Gatekeeper assessment
- `NOTARY_PROFILE` points to a usable `notarytool` keychain profile and the bundle has a stapled ticket
- `.dist/demo/cerberus-demo.mov` exists and is a video file
- the repository passes `Scripts/open_source_check.sh`, including license, visibility, worktree, artifact, and local secret checks

Target one gate while preparing release:

```sh
Scripts/release_check.sh dev-id
Scripts/release_check.sh notary
Scripts/release_check.sh demo
Scripts/release_check.sh oss
```

See `Docs/open-source.md` for the public repository handoff.
