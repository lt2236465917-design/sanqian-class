# Status

- Task-ID: ios-android-system-splash-under-1s-01a0db8f
- Owner-Session: 01a0db8f-8c62-7171-9879-b4b12016b164
- State: active
- Verified milestones: none
- Current: repository identity and clean tracked state confirmed (`main`, `ad3f7a4`); existing untracked `.codex/` preserved. Applicable `AGENTS.md` search found no file in the target repo or its ancestors; task-provided rules apply.
- Next: inspect splash implementation and simulator/device status, then collect baseline startup screenshots.

## Milestone 1: baseline launch capture
- Verified: cold process relaunch on the specified iPhone 16 simulator; measured capture start offsets from `simctl launch` return were 0.405, 0.805, 1.205, 2.001, 3.505, and 8.000 seconds.
- Evidence: `evidence/ios-baseline/ios-{0.4,0.8,1.2,2.0,3.5,8.0}s.png`.
- Result: all six frames show a blank white screen with status/navigation chrome, no close-up poster or `跳过`; even 8.0s does not show timetable. This contradicts a clean splash transition and needs runtime diagnosis before changing source.
- Android AVD `sanqian_visual_api35` was started without wiping data; boot state is pending.
