# release.md — OptionTab Release Workflow

`release.sh` automates the full release pipeline: version bump, archive, Developer ID signing, notarization, DMG packaging, git tag, and GitHub Release creation.

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

1. Make sure you are on the correct branch (`main` for a full release, or a `release/X.Y.Z` branch).
2. Working tree must be **clean** — commit or stash any changes.
3. Update the `VERSION` file with the new semver version:
   ```bash
   echo "1.2.0" > VERSION
   git add VERSION
   git commit -m "chore: prepare release 1.2.0"
   git push
   ```
4. Confirm `VERSION` is higher than the current `MARKETING_VERSION` in `optiontab.xcodeproj/project.pbxproj` — the script will fail with a clear error if nothing changed.

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
| 2 | Checks all prerequisites (Xcode, create-dmg, gh, notary profile, signing identity, clean working tree, tag not already existing) |
| 3 | **Bumps** `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` (auto-incremented) in `project.pbxproj`, commits as `chore: bump version to X.Y.Z (N)`, and pushes the commit to the current branch |
| 4 | Archives the app with `xcodebuild` (scheme `release`, configuration `Release`) |
| 5 | Exports a Developer ID-signed `.app` with hardened runtime; verifies signature |
| 6 | Creates a `.dmg` with `create-dmg` (540×380 window, Applications drop-link) |
| 7 | Submits the DMG to Apple's notary service and waits for approval (typically 2–5 min) |
| 8 | Staples the notarization ticket to the DMG and validates it |
| 9 | Creates an annotated git tag `vX.Y.Z` on the bump commit and pushes it |
| 10 | Creates a GitHub Release with `--generate-notes` and attaches the DMG |

---

## Troubleshooting

**"VERSION file not found"**  
Run from the repo root, where the `VERSION` file lives.

**"VERSION must be semver X.Y.Z"**  
The `VERSION` file must contain exactly `X.Y.Z` (e.g. `1.2.0`), nothing else.

**"VERSION file matches current .pbxproj — nothing to bump"**  
The version in `VERSION` is the same as the one already in `project.pbxproj`. Update `VERSION` to a higher version before running the script.

**"Git working tree not clean"**  
Commit or stash all changes before running the script. The only change the script makes is the version bump — it cannot start from a dirty tree.

**"Tag vX.Y.Z already exists"**  
The tag has already been created (possibly from a failed run). Delete it if appropriate: `git tag -d vX.Y.Z && git push origin :refs/tags/vX.Y.Z`.

**"notary profile 'optiontab-notary' not found"**  
Run the `xcrun notarytool store-credentials` command from the [One-time setup](#one-time-setup) section above.

**"No Developer ID Application signing identity found in keychain"**  
Your certificate is missing or expired. Check in Xcode → Settings → Accounts, or verify `Local.xcconfig` has the correct `DEVELOPMENT_TEAM`.

**"Push rejected"** (e.g. branch protection on `main`)  
Move to the correct branch or open the push permissions, then re-run. The bump commit must be pushed before the archive step to ensure the tag lands on a pushed commit.

**Notarization rejected**  
Run `xcrun notarytool log <submission-id> --keychain-profile optiontab-notary` to retrieve the full rejection log.

---

## Post-release

After `release.sh` completes:

1. If you released from a `release/X.Y.Z` branch, merge it to `main` and then to `develop`:
   ```bash
   git checkout main && git merge release/X.Y.Z --no-ff
   git checkout develop && git merge main --no-ff
   git push origin main develop
   ```
2. Verify the release is live: `gh release view vX.Y.Z`
3. Update `VERSION` on `develop` to the next development version if desired (e.g. `0.2.0-dev`). Not required — the script will reject a non-semver value at runtime.
