# Status: splash timing

- Task-ID: ios-android-splash-under-1s-01a0db8f
- Owner-Session: 01a0db8f-8c62-7171-9879-b4b12016b164
- State: in progress

## Verified

- Checkout is local `main` at `ad3f7a4ca6155128fd1c43c4e63781d1ebfc5614`; no changes are being made in the other timetable checkout.
- Current Android APK: 0.4s is Android's white system icon splash; 0.8s shows the app's centered poster and skip control during fade-in; 1.2s stable poster; 2.0s/3.5s centered uncropped video; 8.0s timetable. Skip and background-return-no-replay were verified. Evidence: `/tmp/nju-android-final-timeline-20260926/`.
- iOS current build was reinstalled without clearing app data. A correctly monotonic launch-anchored sequence was captured in `/tmp/nju-ios-precise-20260926-run2/`: 0.4s, 0.8s, 1.2s and 2.0s are black; 3.5s is the centered video action frame with `跳过`; 8.0s is the timetable. Capture starts were 0.410, 0.811, 1.211, 2.010, 3.503 and 8.006 seconds after `simctl launch` returned. This directly fails the iOS <=1s visual target.
- A reversible light-appearance control was also captured in `/tmp/nju-ios-light-appearance-20260926/`: 0.8s and 1.2s remain black; the square poster and `跳过` appear by 2.0s; an action frame appears at 3.5s and the timetable at 8.0s. The simulator appearance was restored to dark. So the >1s handoff is not explained by dark appearance.
- Current source logs from the earlier recheck show the native splash window created at +0.282s, `didBecomeActive` at +0.406s and video reveal at +1.334s; nevertheless the black transition remains visible at the user-required screenshots through 1.2s. Existing documented attempts to force iOS's launch-card handoff are explicitly ruled out for repetition in the task instructions.
- Android video source and APK asset SHA-256: `6d4d8305401731524d6849224306fb7959df76b3f6eac470d80e28a532c21a90`. iOS `ChaoxiWidgetsEnabled=false`; `git diff --check` passed at last check.

## Next

- Correctly capture all six iOS launch-anchored checkpoints with real monotonic waits, then inspect each screenshot and the 8s completion state.
- Finish final source/build/diff and media checks; preserve the measured iOS evidence and state honestly that iOS remains over the 1s target if no safe, untried fix emerges.
- Recheck diff and constraints without reading or changing repository `.codex/`.
