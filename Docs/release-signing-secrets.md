# Release Signing Secrets

Date: 2026-07-08
Status: Policy for optional GitHub Actions release packaging.

## Decision

Use a protected GitHub Actions environment named `release-signing` for Developer ID and notarization secrets. Do not store signing material in repository files, repo-wide plaintext variables, logs, issues, docs, or release artifacts.

The release packaging workflow is manual-only through `workflow_dispatch`. Pull requests, pushes, schedules, and forks must not receive signing secrets.

## Required GitHub Environment

Environment: `release-signing`

Recommended protection:

- Required reviewer before jobs can access environment secrets.
- Deployment branch/tag restriction to release branches or tags before public release.
- No self-review if more than one maintainer is available.
- Periodic secret audit and rotation.

Environment variable:

- `CODESIGN_IDENTITY`: Developer ID Application identity string, for example `Developer ID Application: Team Name (TEAMID)`.

Environment secrets:

- `DEVELOPER_ID_APPLICATION_CERTIFICATE_BASE64`: base64-encoded `.p12` Developer ID Application certificate.
- `DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD`: password for the `.p12` certificate.
- `KEYCHAIN_PASSWORD`: random password for the temporary CI keychain.
- `NOTARY_APPLE_ID`: Apple ID used for notarization.
- `NOTARY_TEAM_ID`: Apple Developer Team ID.
- `NOTARY_APP_SPECIFIC_PASSWORD`: app-specific password for `notarytool`.

## Workflow Rules

- Use `permissions: contents: read`.
- Use `workflow_dispatch`; do not run signed release jobs automatically.
- Reference `release-signing` only in the signed job.
- Create a temporary keychain on the runner and delete it after the job.
- Store the notary profile in the temporary keychain.
- Pass `NOTARY_KEYCHAIN` to scripts so `notarytool` reads the temporary keychain.
- Upload only `.dist/release/cerberus.zip` and `.dist/release/cerberus.zip.sha256`.
- Do not upload keychains, certificates, notarization credentials, logs containing secret-derived command output, or `.p12` files.

## Local Setup

Create the certificate secret from a local `.p12` file:

```sh
base64 -i DeveloperIDApplication.p12 | pbcopy
```

Create the notary password through Apple ID app-specific passwords, then store it only as `NOTARY_APP_SPECIFIC_PASSWORD` in the protected GitHub environment.

## Sources Checked

- GitHub Actions secrets: https://docs.github.com/en/actions/concepts/security/secrets
- GitHub Actions environments: https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments
- GitHub Actions secure use: https://docs.github.com/en/actions/reference/security/secure-use
- GitHub manually running workflows: https://docs.github.com/actions/managing-workflow-runs/manually-running-a-workflow
- Apple notarization workflow: https://developer.apple.com/documentation/security/customizing-the-notarization-workflow
