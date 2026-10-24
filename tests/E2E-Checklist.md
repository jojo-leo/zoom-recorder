# 端到端验证清单

需要一个真实的 Zoom 会议：自己用另一个账号或手机开会当主持人，会议里开启字幕（CC / 自动字幕）。

## 0. 校准 Zoom 窗口识别（先做）

在会议的不同状态下运行，记录 Title 和 ClassName：

```powershell
Import-Module D:\ClaudeCodeProjects\ZoomRecorder\RecorderCore.psm1
Get-TopWindows -ProcessName Zoom | Where-Object Visible | Format-Table Title, ClassName, Width, Height
Get-ZoomState
```

- [ ] 会议中 → `Get-ZoomState` 显示 `Meeting`
- [ ] 等候主持人 / 等候室 → `Waiting`
- [ ] 密码错误 → `PasswordError`
- [ ] 只有 Zoom 主界面 → `Other`

不一致时修改 `lib\Zoom.ps1` 顶部的 `$script:ZoomClasses` / `$script:ZoomTitles`，并在 `tests\Zoom.Tests.ps1` 里加上真实值的用例。

会议中再手动验证：
- [ ] `Set-ZoomFullScreen` 返回 True 且窗口变为全屏
- [ ] `Enable-ZoomCaptions` 返回 True 且字幕出现
- [ ] 新入会时 `Confirm-ZoomComputerAudio` 能点中「使用电脑音频加入」（若 Zoom 已设为自动加入音频，返回 False 也正常）

## 1. 完整流程

1. [ ] `-Action Install` 后托盘出现蓝点；注销重登后仍自动出现
2. [ ] 登记一场 20 分钟后的会议 → 任务计划程序中只有 `ZoomRecorder_Session_*` 和 `ZoomRecorder_Record_*`（不足 12 小时，没有 Notify12h）
3. [ ] 会议前 15 分钟弹确认窗，内容含原时间和珀斯时间；托盘变黄
4. [ ] 此时运行 `powercfg /requests`，DISPLAY 和 SYSTEM 下有 powershell.exe
5. [ ] 到点：EV 启动 → Zoom 入会 → 全屏 → 字幕出现 → EV 开始录制；托盘红色闪烁
6. [ ] 主持人结束会议 → 约 15–20 秒内 EV 停止，Zoom 和 EV 关闭，托盘变蓝
7. [ ] `powercfg /requests` 不再有 powershell.exe
8. [ ] `D:\EV录屏文件` 有新 mp4：全屏、带字幕、有会议声音、无麦克风声音
9. [ ] 日志状态为「成功」，入会 URL 中密码显示为 `pwd=***`
10. [ ] 管理界面中这场会议状态为「已完成」

## 2. 异常

11. [ ] 错误密码 → 日志「入会失败：密码错误」，有截图，EV 没有生成录像
12. [ ] 录制中托盘「立即停止当前录制」→ 正常停止，状态「已完成」
13. [ ] 确认窗点「取消录制」→ 两个任务被删除，状态「已取消」
14. [ ] 录制中按 Win+L，再解锁 → 弹出「录制中断：用户手动锁屏」
15. [ ] 登记 12 小时以上之后的会议 → 到 T-12h 右下角出现提醒，显示两种时间
16. [ ] 睡眠唤醒（接电源）：确认窗出现前手动让电脑睡眠 → T-3 分钟被唤醒并开始无人值守录制；若唤醒后停在锁屏，日志应为「录制失败：系统已锁屏」

发现问题：先在对应的 `tests\*.Tests.ps1` 中写一个能复现的失败用例，再修复。
