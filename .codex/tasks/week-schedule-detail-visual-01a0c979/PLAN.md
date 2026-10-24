# Week Schedule Detail Visual

- Task-ID: week-schedule-detail-visual-01a0c979
- Owner-Session: 01a0c979-f247-7c13-a361-86b1f796bf06
- Scope: 在现有 visual worktree 中核对并完成完整周表详情页的真实上下课时间网格与单课点击详情；保留既有用户改动，不扩大到其他功能。

## Milestones

1. 核对源码、真实作息数据、当前 diff 与已有构建状态。
2. 必要时修正详情页：每一行对应真实上课到下课区间，休息区间独立分隔；移除底部纯文字课程列表；单课点击打开课程详情。
3. 运行针对性静态检查/测试并完成 iOS Simulator Debug 构建。
4. 在指定“南哪课表 iPhone 16”（EF43A038-4E4B-417D-A813-E2404D1220FD）真实打开详情页，核对网格、课程卡片和点击详情；记录已验证与未验证边界。

## Constraints

- 工作目录固定为 /Users/zhuanzmima0000/Desktop/NJU-Class-Shedule-Flutter-visual。
- 不新建/复制/切换/reset worktree，不提交、推送或发布。
- 仅操作指定 iPhone 16 Simulator，不使用其他模拟器。
