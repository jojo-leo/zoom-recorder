# ZoomRecorder

到点自动加入 Zoom 会议、全屏、打开字幕，并用 EV 录屏录下来；会议结束后自动停止。适合跨时区听讲座、开会，不用熬夜守着。

**测试环境：** Windows 11、Windows PowerShell 5.1、Zoom Workplace、EV 录屏 5.2。本机时区为珀斯（UTC+8）。其他环境下没有测试过，从头到尾的完整演练也还没做。

**路径是写死的：** 项目目录 `D:\ClaudeCodeProjects\ZoomRecorder`，EV 安装在 `C:\Program Files (x86)\EVCapture`，录像保存到 `D:\EV录屏文件`。路径不同时，请修改 `lib\EV.ps1` 顶部的常量，以及下文命令里的路径。

## 安装

在 PowerShell 里运行一次：

```powershell
powershell -File D:\ClaudeCodeProjects\ZoomRecorder\ZoomRecorder.ps1 -Action Install
```

安装会设置开机自启（托盘图标），并为已登记的会议重新注册定时任务。之后右下角会出现一个蓝色圆点。

本工具要求当前用户的脚本执行策略为 `RemoteSigned`（已设置）。如果以后改回默认值，定时任务会无法启动。

## 使用前一次性设置

**Zoom**（设置 → 对应页面）。这些必须设置：Zoom 不允许程序点击它的按钮，入会弹窗、声音和字幕都只能靠这里的设置。
- 视频：**取消**「加入视频会议时始终显示视频预览对话框」（否则半夜会卡在入会弹窗）
- 视频：勾选「加入会议时关闭我的视频」
- 音频：勾选「加入会议时自动使用电脑音频」（否则录像没有声音）
- 音频：勾选「加入会议时将我的麦克风静音」
- 辅助功能：开启「始终显示字幕（如有）」（主持人开启字幕后才会出现）

**EV 录屏**
- 录制区域：全屏；音频：仅系统声音
- 快捷键保持默认：Ctrl+F1 开始、Ctrl+F2 停止
- EV 默认有 3 秒开始倒计时，录像会从按下快捷键约 3 秒后开始

## 登记会议

双击托盘图标（或右键 →「打开管理界面」）→「添加」，填写：
- 会议号、密码
- 日期和时间：填**会议原时区**的时间
- 会议原时区：例如 `America/New_York`
- 最长时长：超过这个时间会自动停止（默认 120 分钟）

窗口会实时显示换算后的珀斯时间。夏令时切换会自动处理；如果填的时间在当地不存在（夏令时跳过的那一小时），会提示错误。

## 录制当天发生什么

| 时间 | 动作 |
|------|------|
| 会议前 12 小时 | 右下角通知，显示原时间和珀斯时间 |
| 会议前 15 分钟 | 弹出确认窗，开始阻止睡眠和熄屏（托盘变黄） |
| 会议前 3 分钟 | 若电脑在睡眠，自动唤醒（**仅在接电源时有效**） |
| 会议前 10 秒 | 启动 EV |
| 会议开始 | 入会 → 电脑音频 → 全屏 → 字幕 → 开始录制（托盘红色闪烁） |
| 会议结束 / 达到最长时长 | 停止录制，关闭 Zoom 和 EV（托盘变蓝） |

确认窗无需点击，到时间会自动继续；点「取消录制」则放弃这一场。

**睡前请确认：不要按 Win+L 锁屏、不要合上笔记本盖、接上电源。** 锁屏后程序无法操作桌面，这一场会记为失败，你下次解锁时会弹窗告诉你。

## 结果在哪里

- 录像：`D:\EV录屏文件`
- 日志：`D:\ClaudeCodeProjects\ZoomRecorder\Logs\`（每场一个 `.log`；入会失败时有同名截图 `.png`）
- 托盘右键 →「立即停止当前录制」可以提前结束

## 卸载

```powershell
powershell -File D:\ClaudeCodeProjects\ZoomRecorder\ZoomRecorder.ps1 -Action Uninstall
```

删除开机自启和所有定时任务；会议数据和日志保留。

## 开发

```powershell
powershell -NoProfile -File D:\ClaudeCodeProjects\ZoomRecorder\tools\Run-Tests.ps1
```

所有 `.ps1` 必须保存为 UTF-8 with BOM（`Run-Tests.ps1` 会自动处理），否则 Windows PowerShell 5.1 会把中文读成乱码。
