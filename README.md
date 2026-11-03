# ChatGPT / Codex Windows 启动修复

非官方 Windows 工具，用于检查并按需修复 `OpenAI.Codex` 桌面安装包的 `cua_node` 运行时复制问题。

下载：[最新正式版本](https://github.com/Jie-account/codex-fix/releases/latest) · [更新记录](CHANGELOG.md)

## 安装和使用

1. 下载 Release 中的 `codex-fix-v1.0.1-windows.zip`，完整解压。
2. 双击 `安装自动修复.cmd`，创建桌面和开始菜单快捷方式。
3. 打开“ChatGPT（自动修复）”，点击“开始”。

也可以直接双击解压目录中的 `修复并启动.cmd` 临时使用。使用发布包无需安装 Git。

窗口显示应用版本、当前阶段、实际文件进度、耗时和结果；支持查看日志和失败后重试。“完成后打开 ChatGPT”默认勾选，可以取消。执行期间窗口保持响应，任务完成后可关闭。

“已发送启动请求”表示系统启动调用已发出，尚未确认应用成功打开。启动请求失败时，已经完成的修复结果仍会保留。

## 适用范围

- 常规 Windows 10/11 桌面环境，具备系统自带的 Windows PowerShell 5.1 和 WinForms 组件。
- 当前用户已安装 `OpenAI.Codex` 桌面安装包。
- 应用沿用目前的运行时结构和目录命名方式；未来结构变化可能需要适配。

已在 Windows x64 环境验证；ARM64 和其他机器尚未实际验证。工具针对运行时复制问题，其他启动故障需要按实际错误定位。

## 工作原理

WindowsApps 中的加密资源在普通复制时可能返回 Win32 错误 6000，在 Node 中表现为 UNKNOWN/-4094。工具直接使用流式读写复制，避免传播源文件的加密属性。

工具查询当前安装包位置，根据三个核心文件的内容计算运行时 ID。已有目录先快速检查，必要时完整校验；需要修复时复制到独立暂存目录，逐文件验证 SHA256，应用退出后再部署。损坏目录保留为备份。

安装包仅包含本项目脚本和文档，不包含第三方应用、运行时或图标资源。安装时从已安装应用读取图标，修复时使用该应用自身的资源。

## 文件与本机日志

安装目录：`%LOCALAPPDATA%\OpenAI\CodexRepair`。

- `Start-RepairGui.ps1`、`RepairWindow.psm1`：图形界面。
- `RepairSession.psm1`：共用编排、阶段通知和结果记录。
- `RuntimeRepair.psm1`：校验、流式复制与部署。
- `Repair-And-Launch.ps1`：命令行入口。
- `Uninstall.ps1`：移除快捷方式，保留运行时、安装文件和日志。

`state/` 保存本机校验记录和最近十次 JSON 执行日志。日志可能包含本机文件路径和错误详情，默认只保存在本机；分享日志前应检查相关内容。程序的修复流程不联网，也不上传日志。

## 命令行

```powershell
# 只检查；健康退出码为 0，需要修复为 2，执行失败为 1。
& "$env:LOCALAPPDATA\OpenAI\CodexRepair\Repair-And-Launch.ps1" -CheckOnly -VerifyAll

# 完整检查、按需修复，然后请求打开应用。
& "$env:LOCALAPPDATA\OpenAI\CodexRepair\Repair-And-Launch.ps1" -VerifyAll -Launch

# JSON 输出。
& "$env:LOCALAPPDATA\OpenAI\CodexRepair\Repair-And-Launch.ps1" -CheckOnly -Json
```

## 开发、测试与发布

```powershell
git clone git@github.com:Jie-account/codex-fix.git
cd codex-fix
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-RuntimeRepair.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-RepairSession.ps1
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-RepairWindow.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-PublicationPrivacy.ps1
```

测试数据和界面截图写入被 Git 忽略的 `work/`；不会替换已安装应用的运行时。功能测试覆盖缺失目录、内容损坏、备份恢复、版本变化、后台响应、进度通知和失败后重试。

更新 `VERSION`、`CHANGELOG.md` 和 `RELEASE_NOTES.md` 并提交后，执行 `tools/Build-Release.ps1`。构建前检查源码与可达 Git 历史，随后按明确清单打包。安装 ZIP、SHA256 校验文件生成于 `dist/`；包内 `release-info.json` 记录来源提交和逐文件哈希。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Build-Release.ps1
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Release.ps1 -Archive .\dist\codex-fix-v1.0.1-windows.zip
```

校验发布包内容和来源后再分发；本机状态、日志、环境配置及私人工作记录均不纳入发布包。
