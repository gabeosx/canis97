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
   - `MACOS_APP_PROVISIONING_PROFILE`: base64-encoded Developer ID
     distribution profile for `com.canis97.player`, authorizing
     `group.com.canis97.player`.
   - `MACOS_WIDGET_PROVISIONING_PROFILE`: base64-encoded Developer ID
     distribution profile for `com.canis97.player.widget`, authorizing the same
     App Group.
   - `APPLE_ID`: Apple ID used by the notary service.
   - `APPLE_TEAM_ID`: Developer Program team identifier.
   - `APPLE_APP_SPECIFIC_PASSWORD`: app-specific password for notarization.

3. Protect the default branch and require the `CI / validate` check.
4. Protect tags matching `v*.*.*` so only release maintainers can create them.
5. Enable GitHub **immutable releases** before the first public publication.
   Set the protected repository variable `IMMUTABLE_RELEASES_CONFIRMED` to the
   exact value `true` only after a release maintainer has confirmed that setting.
   The workflow refuses to publish without it; this is an operator gate, not a
   claim that a workflow can enable the repository setting itself.
6. Create a separate `OWNER/homebrew-tap` repository containing a `Casks/`
   directory. Set repository variable `HOMEBREW_TAP_REPOSITORY` to that
   `owner/repository` value. Add a dedicated write-enabled SSH deploy key to
   that tap and store only its private half as the source repository secret
   `HOMEBREW_TAP_DEPLOY_KEY`. If either setting is absent, the GitHub Release
   succeeds and the workflow reports that Homebrew publishing was skipped.

The workflows pin third-party actions to full commit SHAs. Dependabot or a
reviewed maintenance change should update those pins.

Create the two distribution profiles after assigning the App Group to both
explicit App IDs in Certificates, Identifiers & Profiles. They must be Developer
ID profiles associated with the same certificate supplied in
`MACOS_CERTIFICATE_P12`; development profiles from a local Xcode build are not
release assets.

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
   package_scratch="$(mktemp -d /private/tmp/canis97-swiftpm.XXXXXX)"
   derived_data="$(mktemp -d /private/tmp/canis97-build-for-testing.XXXXXX)"
   script/validate_release_version.sh v0.3.0
   swift test --package-path Packages/SiriusXMClient --scratch-path "$package_scratch"
   xcodebuild build-for-testing \
     -project SiriusMac.xcodeproj \
     -scheme Canis97 \
     -destination 'platform=macOS' \
     -derivedDataPath "$derived_data" \
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

Create and push an annotated tag from the reviewed commit only after the
repository immutable-release setting and protected `IMMUTABLE_RELEASES_CONFIRMED`
variable have both been checked:

```sh
git tag -a v0.3.0 -m 'Canis97 0.3.0'
git push origin v0.3.0
```

The `Release` workflow then:

1. Rejects malformed tags or a tag that differs from `MARKETING_VERSION`.
2. Creates (or, on a retry, reuses) only the matching draft release. A published
   matching release is terminal: do not replace its tag or assets.
3. Builds the exact tagged commit with Xcode 26.6 and a CI build number.
4. Validates and embeds distinct Developer ID provisioning profiles for the app
   and widget, then signs `Canis97MotionConverter.xpc` and
   `Canis97Widget.appex` before `Canis97.app`. It verifies all three Developer
   ID identifiers, team, hardened runtime, secure timestamp, exact expected
   entitlements, and both embedded profiles.
5. Submits a notary ZIP, waits for acceptance, staples the app, and validates the
   stapled app with `stapler`, strict `codesign`, `spctl`, and
   `syspolicy_check distribution`.
6. Builds the branded drag-to-Applications DMG around the stapled app, signs the
   disk image with Developer ID Application, notarizes and staples the outermost
   DMG, and validates it with `codesign`, `stapler`, `spctl`, and
   `syspolicy_check distribution`.
7. Derives `SHA256SUMS`, the SPDX SBOM, and the verification manifest from the
   final stapled DMG bytes.
8. Attaches the final DMG, checksum, SBOM, and verification manifest to the draft,
   downloads all four again, and verifies their hashes before publishing the draft.
9. Renders and pushes `Casks/canis97.rb` to the configured Homebrew tap only after
   the verified draft is published.

Never publish an unsigned, unstapled, unnotarized, or policy-rejected substitute.
Do not instruct users to bypass Gatekeeper.

## Homebrew lifecycle verification

GitHub Releases remains the canonical channel; Homebrew is an optional mirror of
the same final disk image. The cask URL is always the immutable
`vVERSION/Canis97-VERSION-arm64.dmg` asset and its lower-case SHA-256 is the
digest of that final stapled DMG, never a pre-notary or `latest` asset.

Before public publication, an owner may run the separately authorized local
integration verifier with two immutable local archives. The verifier uses
a new explicit work directory, temporary app/cache/tap paths, performs clean
install → upgrade → repeated upgrade → uninstall, and writes a residue report.
It never launches Canis97, uses credentials or Keychain, contacts SiriusXM,
modifies `/Applications`, or pushes a tap.

```sh
CANIS97_RUN_HOMEBREW_INTEGRATION=true \
  script/verify_homebrew_release.sh \
  --cask-fqn gabeosx/homebrew-tap/canis97 \
  --prior-archive /absolute/path/Canis97-0.2.1-arm64.dmg \
  --current-archive /absolute/path/Canis97-0.3.0-arm64.dmg \
  --work-dir /absolute/path/new-canis97-homebrew-check
```

The command is gated intentionally: do not run it in ordinary CI or without an
owner-authorized release verification environment.

The app embeds the triggering `owner/repository` in its Info.plist. Its update
checker calls only GitHub's public latest-release API and opens the canonical
release page; it never downloads or installs an update.

## Verify after publishing

1. Confirm the published release has exactly the final DMG, `SHA256SUMS`, SPDX
   SBOM, and verification manifest attached; download the DMG and compare it
   with `SHA256SUMS`.
2. Open the DMG, drag Canis97 into Applications, and launch it through Finder so
   Gatekeeper evaluates the downloaded path.
3. Confirm About shows the intended version and CI build number.
4. Choose **Canis97 > Check for Updates…** and confirm the current version is
   reported as up to date.
5. Test the cask with the one fully-qualified item form; do not pre-trust the
   whole third-party tap:

   ```sh
   brew install --cask gabeosx/homebrew-tap/canis97
   brew upgrade --cask gabeosx/homebrew-tap/canis97
   brew uninstall --cask gabeosx/homebrew-tap/canis97
   ```

## Recovery and rollback

- If draft creation, notarization, signing, attachment verification, or policy
  validation fails, do not publish an unsigned substitute. Preserve the failed
  tag/draft for diagnosis and fix forward with a new patch version; do not
  replace a tag or release asset.
- If a release is unsafe, mark the GitHub Release as withdrawn, remove its cask
  version from the tap, and publish a fixed patch version. Do not reuse the old
  tag or asset URL.
- If Homebrew publication alone fails, the GitHub Release remains canonical.
  Correct the tap deploy key or branch policy, regenerate the cask with
  `script/render_homebrew_cask.sh`, and submit that isolated tap change.
