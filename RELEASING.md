# Releasing Canis97

GitHub Releases is the canonical binary channel. A project-owned Homebrew tap
mirrors each release as the `canis97` cask. Released disk images are arm64-only,
signed with Developer ID, hardened, notarized, stapled, and accompanied by a
SHA-256 checksum and SPDX software bill of materials.

## Versioning contract

Canis97 uses stable Semantic Versioning: `MAJOR.MINOR.PATCH`.

- Increment `MAJOR` for incompatible user-facing or persisted-data changes.
- Increment `MINOR` for backward-compatible features.
- Increment `PATCH` for backward-compatible fixes, including repairs for an
  upstream SiriusXM compatibility change.
- Public tags are exactly `vMAJOR.MINOR.PATCH`. Prerelease and build-metadata
  tags are intentionally unsupported until the release process defines a
  separate prerelease channel.
- `MARKETING_VERSION` in `Config/Version.xcconfig` is the single source of
  truth for the release version.
- `CURRENT_PROJECT_VERSION` is a positive, monotonically increasing build
  number. GitHub Actions uses `GITHUB_RUN_NUMBER`, so rerunning a release from
  a new workflow run never reuses a build number.
- Never move or replace a published tag. Ship a new patch release instead.

The reusable `SiriusXMClient` package shares the repository version until it
has an independent release cadence. Its public API still follows SemVer.

## One-time repository setup

1. Create a GitHub `release` environment and restrict it to protected
   `v*.*.*` tags.
2. Add these environment secrets:

   - `MACOS_CERTIFICATE_P12`: base64-encoded Developer ID Application `.p12`.
   - `MACOS_CERTIFICATE_PASSWORD`: password for the `.p12`.
   - `APPLE_ID`: Apple ID used by the notary service.
   - `APPLE_TEAM_ID`: Developer Program team identifier.
   - `APPLE_APP_SPECIFIC_PASSWORD`: app-specific password for notarization.

3. Protect the default branch and require the `CI / validate` check.
4. Protect tags matching `v*.*.*` so only release maintainers can create them.
5. Create a separate `OWNER/homebrew-tap` repository containing a `Casks/`
   directory. Set repository variable `HOMEBREW_TAP_REPOSITORY` to that
   `owner/repository` value. Add a dedicated write-enabled SSH deploy key to
   that tap and store only its private half as the source repository secret
   `HOMEBREW_TAP_DEPLOY_KEY`. If either setting is absent, the GitHub Release
   succeeds and the workflow reports that Homebrew publishing was skipped.

The workflows pin third-party actions to full commit SHAs. Dependabot or a
reviewed maintenance change should update those pins.

After initially configuring or rotating any Apple release secret, run the
manual `Release Preflight` workflow from a ref permitted by the `release`
environment. It imports the Developer ID identity into an ephemeral keychain
and authenticates with Apple's notarization service. It does not build,
upload, tag, or publish Canis97.

## Prepare a release

1. Ensure the intended commit is on the protected default branch and CI is
   green. Do not run live SiriusXM probes as part of release CI.
2. Update `MARKETING_VERSION` in `Config/Version.xcconfig` and increment the
   local `CURRENT_PROJECT_VERSION` baseline.
3. Move the relevant entries from `[Unreleased]` in `CHANGELOG.md` into a new
   `## [MAJOR.MINOR.PATCH] - YYYY-MM-DD` section.
4. Run the safe local checks:

   ```sh
   script/validate_release_version.sh v0.1.0
   swift test --package-path Packages/SiriusXMClient
   xcodebuild build-for-testing \
     -project SiriusMac.xcodeproj \
     -scheme Canis97 \
     -destination 'platform=macOS' \
     -only-testing:Canis97Tests \
     -parallel-testing-enabled NO \
     CODE_SIGNING_ALLOWED=NO
   ```

   `build-for-testing` compiles without launching the app or tests. App-hosted
   and UI tests remain prohibited until the repository safety review is
   separately authorized.

5. Commit the version and changelog together. Have another maintainer review
   the release diff.

## Publish

Create and push an annotated tag from the reviewed commit:

```sh
git tag -a v0.1.0 -m 'Canis97 0.1.0'
git push origin v0.1.0
```

The `Release` workflow then:

1. Rejects malformed tags or a tag that differs from `MARKETING_VERSION`.
2. Builds the exact tagged commit with Xcode 26.6 and a CI build number.
3. Verifies the Developer ID signature and hardened runtime.
4. Submits the app with `notarytool`, staples the accepted ticket, and validates
   it with `stapler`, `codesign`, and Gatekeeper.
5. Builds the branded drag-to-Applications disk image, signs it with Developer
   ID Application, notarizes and staples the outermost DMG, and validates it
   with `stapler`, `codesign`, Gatekeeper, and `syspolicy_check`.
6. Creates `Canis97-VERSION-arm64.dmg`, `SHA256SUMS`, and an SPDX SBOM from the
   final stapled disk-image bytes.
7. Publishes an immutable GitHub Release from the tag.
8. Renders and pushes `Casks/canis97.rb` to the configured Homebrew tap.

The app embeds the triggering `owner/repository` in its Info.plist. Its update
checker calls only GitHub's public latest-release API and opens the canonical
release page; it never downloads or installs an update.

## Verify after publishing

1. On a clean current-macOS machine, download the GitHub DMG and compare
   it with `SHA256SUMS`.
2. Open the DMG, drag Canis97 into Applications, and launch it through Finder so
   Gatekeeper evaluates the downloaded path.
3. Confirm About shows the intended version and CI build number.
4. Choose **Canis97 > Check for Updates…** and confirm the current version is
   reported as up to date.
5. Test the tap:

   ```sh
   brew tap OWNER/tap
   brew install --cask canis97
   brew uninstall --cask canis97
   ```

## Recovery and rollback

- If notarization, signing, or validation fails, do not publish an unsigned
  substitute. Fix the workflow or certificate and create a new build/tag only
  when the source commit or version changes.
- If a release is unsafe, mark the GitHub Release as withdrawn, remove its cask
  version from the tap, and publish a fixed patch version. Do not reuse the old
  tag or asset URL.
- If Homebrew publication alone fails, the GitHub Release remains canonical.
  Correct the tap deploy key or branch policy, regenerate the cask with
  `script/render_homebrew_cask.sh`, and submit that isolated tap change.
