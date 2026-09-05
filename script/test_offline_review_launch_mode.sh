#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
scratch="$(mktemp -d /private/tmp/canis97-offline-launch-check.XXXXXX)"
trap 'rm -rf "$scratch"' EXIT
python3 - "$repo_root" "$scratch" <<'PY'
from pathlib import Path
import sys
root, scratch = map(Path, sys.argv[1:])
source = (root / 'SiriusMac/SiriusMacApp.swift').read_text()
mode = source[source.index('enum OfflineReviewLaunchMode {'):]
(scratch / 'Mode.swift').write_text('import Foundation\nenum ProductIdentity { static let environmentPrefix = "CANIS97" }\n' + mode)
(scratch / 'Check.swift').write_text('''import Foundation
@main struct Check {
    static func main() {
        let requested = ["CANIS97_OFFLINE_REVIEW_MODE": "1"]
        precondition(OfflineReviewLaunchMode.isOfflineReviewRequested(environment: requested))
        precondition(!OfflineReviewLaunchMode.isUnitTestHost(environment: [:]))
#if CANIS97_ANIMATION_ACCEPTANCE
        precondition(OfflineReviewLaunchMode.isOfflineReviewRequested(environment: [:]))
        precondition(OfflineReviewLaunchMode.isOfflineReviewMode(environment: [:]))
        precondition(OfflineReviewLaunchMode.isOfflineReviewMode(environment: ["CANIS97_OFFLINE_REVIEW_MODE": "0"]))
#elseif DEBUG
        precondition(!OfflineReviewLaunchMode.isOfflineReviewRequested(environment: [:]))
        precondition(OfflineReviewLaunchMode.isOfflineReviewMode(environment: requested))
#else
        precondition(!OfflineReviewLaunchMode.isOfflineReviewRequested(environment: [:]))
        precondition(!OfflineReviewLaunchMode.isOfflineReviewMode(environment: requested))
#endif
        print("PASS: production launch-mode policy; no app/test host instantiated")
    }
}
''')
PY
for mode in CANIS97_ANIMATION_ACCEPTANCE DEBUG RELEASE_CHECK; do
  swiftc -swift-version 6 -warnings-as-errors -D "$mode" -module-cache-path "$scratch/cache" \
    "$scratch/Mode.swift" "$scratch/Check.swift" -o "$scratch/check"
  "$scratch/check"
done
