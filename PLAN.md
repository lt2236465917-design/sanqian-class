# iOS and Android splash timing

- Task-ID: ios-android-splash-under-1s-01a0db8f
- Owner-Session: 01a0db8f-8c62-7171-9879-b4b12016b164

## Objective

Verify and improve the system-launch-to-app-splash transition on the iPhone 16 and existing Android emulator. Keep the poster for about 0.5s, play the complete centered original video, then show the timetable. Preserve skip/background behavior.

## Constraints

- Only work in `/Users/zhuanzmima0000/Desktop/NJU-Class-Shedule-Flutter-visual`; stay on local `main` at `ad3f7a4ca6155128fd1c43c4e63781d1ebfc5614`.
- Do not touch the other timetable checkout or repository `.codex/`; do not push or commit. Keep `ChaoxiWidgetsEnabled=false`.
- Judge timing from launch-anchored simulator screenshots, not build success.
- Do not repeat the disproven iOS approaches listed in the active task instructions.

## Milestones

1. Revalidate current checkout and Android launch behavior.
2. Capture/review iOS launch-anchored screenshots at 0.4, 0.8, 1.2, 2.0, 3.5 and 8 seconds.
3. Apply only evidence-led iOS changes; rebuild and repeat the same screenshot check.
4. Audit final diffs, original video bytes, and widget flag; record any unmet platform requirement honestly.
