# Phase 6 measurements

Measurement date: 2026-10-20 (Asia/Shanghai)

Code revision: `e16bf56afe70e4725df95946cc8fc019bfff1c8b`

Host: MacBook Air (`MacBookAir10,1`), Apple M1, 16 GB RAM, arm64

OS: macOS 15.8.1 (`24H32`)  
Swift: Apple Swift 6.1.2 (`swift-driver` 1.120.5)

## App and DMG size

The baseline values come from the Phase 0 measurements for `4f7cfc9` (`v0.1.3`), recorded on the same host and OS. Current Release products were built from the revision above. To preserve existing files under `dist/`, each temporary `.app` began as a copy of the existing 0.1.3 bundle; its executable and SwiftPM resource bundles were replaced with the current Release outputs, then stripped with `strip -x` and ad-hoc signed with `scripts/Meow.entitlements`. Temporary DMGs used the same `hdiutil` UDZO format and app-plus-Applications layout as `scripts/build-dmg.sh`.

`.app` values use `du -sk` allocated KiB. DMG values include both allocated KiB and exact file bytes.

| Edition | Baseline app (KiB) | Current app (KiB) | Change | Baseline DMG (KiB) | Current DMG (KiB) | Current DMG (bytes) | Change |
|---|---:|---:|---:|---:|---:|---:|---:|
| Meow | 11,188 | 11,560 | +372 (+3.3%) | 5,936 | 6,060 | 6,204,104 | +124 (+2.1%) |
| Miao | 11,540 | 11,900 | +360 (+3.1%) | 6,088 | 6,216 | 6,361,098 | +128 (+2.1%) |

The measured outputs were created in `/private/tmp/meow-phase6-refresh`; both app signatures passed `codesign --verify --deep --strict`, and both disk images passed `hdiutil verify`. Release builds for Meow and Miao passed on this revision. The existing `dist/` artifacts were not changed. These numbers describe package size only and do not establish runtime performance parity.

## Runtime performance and regression status

| Requirement | Current evidence | Status |
|---|---|---|
| Cold-start time | No repeatable launch measurement collected | Not measured |
| Idle CPU and memory | No current-build process sample collected | Not measured |
| Wake frequency and long-running resource use | No current-build sampling session collected | Not measured |
| Screenshot latency and recording start/stop | No packaged-app timing run collected | Not measured |
| Sleep/wake, permission revocation, network/storage failures, rapid start/stop | Automated tests cover selected lifecycle cases; full packaged-app matrix has not been run | Manual verification remains |
| Meow/Miao upload and other end-to-end user paths | Earlier manual upload validation was reported by the user; the broader Phase 6 matrix has not been repeated for this revision | Partial |

The Phase 0 reference process sample was an already-running installed Miao 0.1.2, not the measured 0.1.3 release bundle: it reported 0.0% CPU, about 66 MiB resident/physical footprint in the sampled tools, and 98.5 MiB peak in `vmmap`. It is useful context only; it is not an exact before/after comparison. Phase 0 did not record cold-start time. The package size comparison above is the only current quantitative before/after measurement completed so far.

Do not mark Phase 6 complete until cold start and runtime resource sampling have been repeated on this host, the packaged-app regression matrix has been exercised, and remaining gaps have been recorded here.
