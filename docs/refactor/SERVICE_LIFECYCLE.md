# Service lifecycle inventory

This inventory records the current lifecycle owners and boundaries from
`AppServiceRegistry`, `AppSettingsCoordinator`, `AppLifecycleCoordinator`, and
the service implementations. It is a review aid for Phase 2, not a new runtime
contract. Permission recovery and manual checks remain platform-dependent.

| Service / resource | Owner and start condition | Stop condition | Re-entry and outstanding coverage |
| --- | --- | --- | --- |
| System monitor sampler | `SystemMonitorService`, configured by `AppSettingsCoordinator`; starts when enabled or when its panel is shown | Disabled setting or app termination | `SystemMonitorEngine` now serializes lifecycle operations, ignores stale callbacks, and `SystemMetricsActor.stop()` awaits its canceled loop. Repeated start/stop has a unit test. Manual setting toggle and app termination checks remain. |
| Screen recording | `AppRecordingCoordinator` owns the user operation task and visual overlays; `RecordingService` owns ScreenCaptureKit, writer, microphone capture, and timers | User stop, failed start, cancellation, or app termination | `canStartRecording` checks the coordinator task and service state. Service stop is async and tears down stream/audio before finalizing. A Meow/Miao test cancels a mobile-source countdown, confirms the inactive state can prepare another recording, and stops it. Screen permission and real capture teardown still need manual coverage. |
| Clipboard monitor | `AppSettingsCoordinator` starts/stops `ClipboardStore` when clipboard history changes; app termination stops it | Setting disabled or app termination | `startMonitoring` first calls `stopMonitoring`, preventing duplicate timer/observer installation. It owns a 0.5-second timer and workspace app observer. Meow and Miao tests now restart monitoring and verify changes after stop are ignored using an isolated pasteboard and notification center. |
| Keystroke visualizer | `AppSettingsCoordinator` applies settings; the service starts its event tap when enabled | Setting disabled, app termination, or deinit | `start()` guards an existing event tap; `stop()` removes the run-loop source and disables the tap. Meow/Miao tests verify repeated enable/stop owns one tap and permission recovery starts after a grant. Permission revoke behavior and actual macOS event tap recovery still need manual verification. |
| Health reminder | `AppSettingsCoordinator` applies settings; enabled state starts the timer and work interval | Setting disabled or app termination | `startTimerIfNeeded` owns a single timer; `stop` invalidates it and hides the break panel. Meow/Miao tests verify repeated apply reuses one timer, disable invalidates it, and pause/resume invalidates/recreates the timer while preserving the phase. Termination with a visible break panel remains a manual check. |
| Keep Awake | `AppSettingsCoordinator` applies settings; user action starts an IOKit assertion, while settings disable, sleep, expiration, or app termination release it | Explicit stop, disabled setting, sleep transition, expiration, or app termination | Async start/stop use operation tokens, settle pending release tasks, and retry failed releases. Wake reconciliation is implemented. Tests cover driver failures and sleep/wake; retain those checks when changing lifecycle ownership. |
| Dock icon calendar observer | `AppDelegate` starts `DockIconService` during initial setup; settings update its style | App termination | `start()` now keeps a single day-change observer, and `stop()` removes it. A repeated start/stop test verifies one callback and no callback after stopping. |
| Status item date refresh | `StatusItemService.setup` creates the item and schedules a midnight timer; wake refresh reschedules it | App termination via `StatusItemService.stop()` | Scheduling invalidates the prior timer before replacing it. `stop()` now invalidates the timer, removes the status item, and releases menu/drop references. The termination test verifies shutdown invokes this owner. |
| App event monitors | `AppWindowCoordinator` installs launcher, translation, AI, and global/local input monitors | App termination or coordinator removal | Repeated install/remove and post-removal handler behavior are unit tested. Permission-dependent global monitor behavior still needs manual verification. |
| Hotkeys | `AppHotkeyCoordinator` applies registrations when settings change | Registration replacement, unregister, or app termination | Registration conflicts are surfaced and restored on settings changes. Manual conflict and restoration checks remain. |
| File upload | `FileUploadService` owns one active upload task and runtime uploader; an upload action creates the task | Completion, cancellation, credential/config change, or app termination | `executeUpload` rejects a second concurrent upload. `shutdown()` cancels and awaits active work, then shuts down and clears runtime uploader credentials. Test cancel during network I/O and shutdown during multipart upload. |
| Voice speech recognition (Miao only) | `AppSettingsCoordinator` applies model/settings; hotkey hold starts audio capture and recognition | Key release, cancellation, setting/model change, or app termination | Audio engine and duration timer are stopped by capture cleanup; recognition/model tasks can be canceled and unloaded asynchronously. App activation refreshes microphone permission. Test rapid key press/release, permission revoke, and unload while inference is active. |

## Lifecycle ownership notes

- `AppServiceRegistry` owns long-lived service instances; `AppDelegate` composes
  their coordinators and supplies lifecycle actions.
- `AppSettingsCoordinator` is the settings-driven start/stop dispatcher. A
  setting change should not instantiate an optional service unless the feature
  is enabled or the service was already loaded.
- `AppLifecycleCoordinator` owns app startup, sleep/wake notifications,
  permission retry, and shutdown sequencing. Async shutdown currently explicitly
  awaits Keep Awake and upload shutdown before replying to termination; other
  teardown callbacks are dispatched synchronously or in unawaited tasks.
- Permission restoration is event-specific: accessibility and speech
  microphone permissions are retried when the app becomes active. Screen
  recording requests screen capture access at start. There is no shared generic
  permission lifecycle abstraction.

## Follow-up checks

1. Exercise system monitor start/stop and setting changes in the packaged app.
2. Exercise recording cancellation during source selection, countdown, and
   capture shutdown with screen and microphone permissions granted and denied.
3. Manually exercise clipboard and event monitor repeated enable/disable and
   verify no callbacks arrive after stop.
4. Exercise app sleep/wake with Keep Awake active and system monitor enabled.
5. Manually verify app termination removes the status item and Dock calendar
   refresh observer in both editions.
