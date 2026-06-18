# Release Checklist

## Inputs

- [ ] `CODESIGN_IDENTITY` is a Developer ID Application identity installed in the login keychain
- [ ] `NOTARY_PROFILE` is a usable `notarytool` keychain profile
- [ ] `.dist/demo/cerberus-demo.mov` exists and is final
- [ ] license, visibility, worktree, artifact, and secret checks are ready for public release

## Build and Package

- [ ] run `Scripts/build_app.sh`
- [ ] run `Scripts/package_release.sh`
- [ ] confirm `.dist/release/cerberus.zip` exists
- [ ] confirm `.dist/release/cerberus.zip.sha256` exists
- [ ] run `shasum -a 256 -c .dist/release/cerberus.zip.sha256`

## Release Gates

- [ ] run `Scripts/release_check.sh dev-id`
- [ ] run `Scripts/release_check.sh notary`
- [ ] run `Scripts/release_check.sh demo`
- [ ] run `Scripts/release_check.sh oss`
- [ ] run `spctl --assess --type execute --verbose=2 .dist/cerberus.app`
- [ ] run `codesign --verify --deep --strict --verbose=2 .dist/cerberus.app`

## Final Smoke

- [ ] run `Scripts/release_smoke.sh`
- [ ] launch the signed `.app`, not `swift run`
- [ ] confirm `ShellExecService.xpc` is embedded at `Contents/XPCServices/ShellExecService.xpc`
- [ ] confirm the downloaded/quarantined app launches
- [ ] confirm release notes and rollback notes match the shipped build
