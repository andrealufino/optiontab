# release.md — OptionTab Release Workflow

`release.sh` automates the full release pipeline: version bump, merge to main, archive, Developer ID signing, notarization, DMG packaging, git tag, GitHub Release creation, and develop sync.

> **Tag convention**: tags are always the plain semver `X.Y.Z` — never prefix with `v`.

---

## One-time setup

Install required tools:

```bash
brew install create-dmg gh
gh auth login
```

Make sure your **Developer ID Application** certificate is installed in your keychain. The script resolves the signing identity and Team ID automatically from the keychain at runtime.

Store your notarization credentials:

```bash
xcrun notarytool store-credentials "optiontab-notary" \
    --apple-id "you@example.com" \
    --team-id "<your-team-id>" \
    --password "<app-specific-password>"
```

Use an [app-specific password](https://support.apple.com/en-us/102654), not your Apple ID password.

Set up your local signing config (one-time, per machine):

```bash
cp Local.xcconfig.template Local.xcconfig
# edit Local.xcconfig and set DEVELOPMENT_TEAM = <your-10-char-team-id>
```

`Local.xcconfig` is gitignored and must never be committed.

---

## Pre-release checklist

1. Must be on the **`develop` branch** — the script aborts with a clear error on any other branch.
2. Working tree must be **clean** — commit or stash any changes.
3. `develop` must be **in sync with `origin/develop`** — push or pull as needed.
4. Update the `VERSION` file with the new semver version:
   ```bash
   echo "1.2.0" > VERSION
   git add VERSION
   git commit -m "chore: prepare release 1.2.0"
   git push
   ```
5. Confirm `VERSION` is higher than the current `MARKETING_VERSION` in `optiontab.xcodeproj/project.pbxproj` — the script will fail with a clear error if nothing changed.

---

## Running the release

```bash
./release.sh
```

No arguments — the script reads the version from `VERSION`.

### What the script does

| Step | What happens |
|------|--------------|
| 1 | Reads `VERSION` file, validates semver format |
| 2 | Checks all prerequisites: must be on `develop`, in sync with remote, tools present, notary profile valid, signing identity found, clean tree, tag not existing |
| 3 | **Bumps** `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` (auto-incremented) in `project.pbxproj`, commits as `chore: bump version to X.Y.Z (N)`, pushes to `develop` |
| 4 | Merges `develop` → `main` (`--no-ff`, message `release: X.Y.Z`), pushes `main` |
| 5 | Archives the app with `xcodebuild` (scheme `release`, configuration `Release`) |
| 6 | Exports a Developer ID-signed `.app` with hardened runtime; verifies signature |
| 7 | Creates a `.dmg` with `create-dmg` (540×380 window, Applications drop-link) |
| 8 | Submits the DMG to Apple's notary service and waits for approval (typically 2–5 min) |
| 9 | Staples the notarization ticket to the DMG and validates it |
| 10 | Creates an annotated git tag `X.Y.Z` on the **`main` merge commit** and pushes it |
| 11 | Creates a GitHub Release with `--generate-notes` and attaches the DMG |
| 12 | Fast-forward merges `main` → `develop`, pushes `develop` to keep branches in sync |

---

## Troubleshooting

**"must be run from develop"**
You are on the wrong branch. Checkout `develop` and rerun.

**"develop is not in sync with origin/develop"**
Run `git status` to see what is ahead or behind. Push uncommitted local commits or pull remote ones before releasing.

**"origin/main has N commit(s) not in local main"**
Run `git checkout main && git pull`, then switch back to `develop` and rerun.

**"VERSION file not found"**
Run from the repo root, where the `VERSION` file lives.

**"VERSION must be semver X.Y.Z"**
The `VERSION` file must contain exactly `X.Y.Z` (e.g. `1.2.0`), nothing else.

**"VERSION file matches current .pbxproj — nothing to bump"**
The version in `VERSION` is the same as the one already in `project.pbxproj`. Update `VERSION` to a higher version before running the script.

**"Git working tree not clean"**
Commit or stash all changes before running the script.

**"Tag X.Y.Z already exists"**
The tag has already been created (possibly from a failed run). Delete it if appropriate: `git tag -d X.Y.Z && git push origin :refs/tags/X.Y.Z`.

**"notary profile 'optiontab-notary' not found"**
Run the `xcrun notarytool store-credentials` command from the [One-time setup](#one-time-setup) section above.

**"No Developer ID Application signing identity found in keychain"**
Your certificate is missing or expired. Check in Xcode → Settings → Accounts, or verify `Local.xcconfig` has the correct `DEVELOPMENT_TEAM`.

**Script failed after merge to main was already pushed**
The script prints a recovery message with the merge commit SHA. Investigate the failure, bump `VERSION` to a new number, and rerun `release.sh`. No automatic rollback is performed — `main` and `develop` remain at the already-pushed state.

---

## Post-release

After `release.sh` completes, both `main` and `develop` are already pushed and in sync. Verify the release is live:

```bash
gh release view X.Y.Z
```
