# Build and release

## Development

Run the app bundle locally:

```sh
./script/build_and_run.sh
```

Run unit tests:

```sh
swift test
```

## Developer ID release

The release script requires a `Developer ID Application` identity and a version:

```sh
export WRITEIT_VERSION=0.1.0
export WRITEIT_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)'
./script/package_release.sh
```

To notarize and staple the generated app, create a `notarytool` keychain profile, then run:

```sh
export WRITEIT_NOTARY_PROFILE=writeit-notary
./script/package_release.sh --notarize
```

Validate the local toolchain without credentials:

```sh
./script/package_release.sh --dry-run
```

The generated ZIP is written to `release/`. No signing identity or notarization credential is stored in this repository.
