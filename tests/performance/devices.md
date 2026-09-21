# Physical-device performance gate — pending

No physical reference device or iOS/macOS runner was available during local implementation. Host SQLite timings and Android emulator journeys do not pass this gate.

Use a dedicated test account and device with the synthetic dataset. Record app commit, Flutter/OS versions, device model/RAM/storage, battery/thermal state, connection, test data size and build mode. Android reference: a physical 4 GB device, 60 Hz display. Repeat the core flows on physical iOS. Use profile/release builds and the actual camera/video plugins.

## Capture procedure

1. Build/run the pinned application with `flutter run --profile -d DEVICE --dart-define=API_BASE_URL=https://STAGING_API`. Configure the test account, load a store, then enable airplane mode to measure cached paths. Initial login is not an offline operation.
2. Startup: run 30 independent cold process launches with the warm persisted cache. On Android force-stop the package between runs (never clear application data). Capture Flutter startup timeline (`flutter run --profile --trace-startup`) and screen recording. Time the usable screen, not merely the OS activity launch; retain traces and recordings. p95 ≤ 2.5 seconds.
3. Local sale: capture 100 saves using a product/lot with known inventory, including runs with 120 queued operations. In DevTools profile the tap-to-durable-feedback interval and SQLite work; verify outbox IDs after process restart. p95 ≤ 250 ms. Search at least 100 partial name/reference/barcode queries against the cached 200-product catalog: p95 ≤ 150 ms.
4. Scrolling: record at least 1,000 frames each for stock, sales, training and store selection. Export DevTools frame/timeline data; count frames exceeding the device's 16.67 ms budget, including raster frames. Require <1% missed frames for each flow, retaining frame distributions rather than screenshots of a single smooth run.
5. Switch repeatedly among four cached stores, then a store not yet cached, with a saved draft and queued sale in the original store. Verify scoped data and attribution after connection returns.
6. Open/scan/close camera 30 times, switch torch, deny/regrant permission, background/resume, rotate, and scan the same barcode held in frame. Confirm one capture per scan. Record camera resource release and Android `adb shell dumpsys meminfo tn.biobalance.app` (or Xcode Memory Graph on iOS) before/after stabilized cycles.
7. Open/play/close streamed and downloaded videos 30 times; pause/background/rotate and interrupt transfers. Compare stabilized memory, active native players and thermal behavior. Run manual TalkBack/VoiceOver checks, 200% text, keyboard and landscape.
8. Keep the original pending operations while testing session expiry and revoked access. Reauthenticate the original account and reconcile actual database effects.

Publish a dated result table with sample count, p50/p95/max, missed frame count, memory trend, raw evidence locations, issues and disposition. Failures remain release blockers; tests are not marked passed by this procedure's existence. Camera/push functionality is separate from frame-rate measurements.
