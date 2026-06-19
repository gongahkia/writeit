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
See `SECURITY.md` for vulnerability reporting and local-data handling expectations.

## Manual Decisions

Choose the license before publishing. GitHub license docs were re-checked on 2026-06-19 and still document that a public repository is not automatically open source without a license that grants reuse, modification, and distribution rights. They also recommend putting the license text in a root `LICENSE` file and noting license terms in the README.

Review GitHub's private-to-public visibility effects before changing visibility. GitHub visibility docs were re-checked on 2026-06-19 and still document that code becomes visible, anyone can fork the repository, activity and Actions logs become public, and all push rulesets are disabled by the transition.

Verify security and analysis settings. GitHub security/analysis docs were re-checked on 2026-06-19 and recommend Dependabot alerts, secret scanning, push protection, and code scanning for public repositories; dependency graph remains permanently enabled for public repositories.

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
