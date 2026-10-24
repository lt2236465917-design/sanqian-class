# iOS and Android system splash under 1 second

- Task-ID: ios-android-system-splash-under-1s-01a0db8f
- Owner-Session: 01a0db8f-8c62-7171-9879-b4b12016b164

## Objective
Reduce the native system splash before the app-owned splash to under one second on iOS and Android, and verify with timestamped screenshots after launch. Preserve the centered close-up logo for about 0.5 seconds, then play the complete original 4.06-second `res/mascot/cold-start-splash.mp4` centered with aspect fit; verify skip, foreground/background behavior, and return to timetable.

## Constraints
- Only edit `/Users/zhuanzmima0000/Desktop/NJU-Class-Shedule-Flutter-visual`, local branch `main`, starting commit `ad3f7a4`.
- Do not modify `/Users/zhuanzmima0000/Desktop/课表/NJU-Class-Shedule-Flutter`; do not push; do not commit secrets, signing files, or `.codex/`.
- Keep `ChaoxiWidgetsEnabled` false. Do not change widgets or App Group.
- Do not retry the already falsified iOS approaches listed in the user objective.
- Do not clear simulator data or uninstall apps.

## Milestones
1. Inspect current source, repository state, and available simulator/device state; record the baseline without disturbing user data.
2. Make only evidence-supported changes to native splash timing/presentation where they can meet the required alignment.
3. Build/launch on iPhone 16 simulator `EF43A038-4E4B-417D-A813-E2404D1220FD` and existing Android emulator; capture screenshots at required time offsets and verify the app-owned splash lifecycle.
4. If native system splash cannot meet the under-one-second aligned close-up requirement, document attempted changes, timestamped screenshots, and why the OS retains control; keep the app-owned white-background aligned close-up before full animation.

## Current state
- Active work is limited to inspection until baseline source and simulator evidence are collected.
