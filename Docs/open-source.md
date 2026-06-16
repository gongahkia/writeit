# Open Source Release

The repository-public step is intentionally manual. Do not change visibility until the license choice, local audit, and GitHub security settings are verified.

## Preflight

Run:

```sh
Scripts/open_source_check.sh
```

For prep work before the repository is public:

```sh
REQUIRE_PUBLIC=0 Scripts/open_source_check.sh
```

The script checks:

- `LICENSE` or `COPYING` exists
- GitHub CLI can read repository visibility
- repository visibility is public unless `REQUIRE_PUBLIC=0`
- working tree is clean unless `ALLOW_DIRTY=1`
- no tracked build/release artifacts are present
- no tracked private-key block or obvious quoted token assignment is present

The secret check is only a local heuristic. Keep GitHub push protection enabled and review any secret-scanning alerts before release.

## Manual Decisions

Choose the license before publishing. GitHub documents that a public repository is not automatically open source without a license that grants reuse, modification, and distribution rights.

Review GitHub's private-to-public visibility effects before changing visibility. GitHub documents that code, activity, Actions logs, and forks become publicly visible, and push rulesets can be disabled by the transition.

Verify push protection. GitHub documents account-level push protection for users as enabled by default and blocking supported secrets from public repositories, but repository-level settings can add stronger bypass controls and alerts.

Official references:

- https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository
- https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/managing-repository-settings/setting-repository-visibility
- https://docs.github.com/en/code-security/concepts/secret-security/push-protection

## Publishing

After the checks pass and the manual decisions are complete, make the repository public from GitHub Settings, or with GitHub CLI after explicit approval:

```sh
gh repo edit --visibility public
```

Then run:

```sh
Scripts/release_check.sh oss
```
