# Meow

[English](README.md) | [简体中文](README.zh-CN.md)

轻量级 macOS 启动器 + 挂件工具集（SwiftUI + AppKit）。

## 功能

- 全局快捷键（`Opt+Space`）呼出启动器
- 应用搜索（带启动历史权重）
- 剪贴板历史，支持粘贴、复制、删除与清空
- 内置命令（偏好设置 / 询问 AI / 退出）
- 兼容 OpenAI Chat Completions 的 AI 聊天助手，并支持本地聊天历史
- 可从剪贴板条目直接询问 AI
- 选中文本翻译面板（需要辅助功能权限）
- 离线语音识别，支持按住说话、自动粘贴和本地 WAV 历史
- 按键可视化叠层，支持拖拽、显示模式、显示时长、透明度与历史数量
- 健康提醒，支持工作/休息计时、休息叠层、每日目标与轻量键鼠活跃检测
- 菜单栏日历，含农历日期、节气、节假日及 Calendar.app 事件
- TOTP 身份验证器，支持钥匙串存储、`otpauth://` 与 JSON 导入、JSON 备份、搜索和一键复制
- 使用正确签名构建时，可选择通过 iCloud 钥匙串同步身份验证器账户
- 7 种菜单栏日期图标样式（爪印、轮廓日期、圆角轮廓、仅日期、月+日、星期+日、农历）
- 3 种 Dock 图标样式（默认、日历、扁平）
- 条目操作菜单（打开、在 Finder 中显示、复制、粘贴、询问 AI、删除）
- 4 套主题配色：调皮猫猫、雾霾蓝、琥珀石墨、苔墨
- 运行时语言切换（英文 / 简体中文）
- 登录启动（受 macOS 签名策略限制）

## 环境要求

- macOS 15+
- Swift 6.0+

## 快速开始

```bash
# Debug 构建
swift build

# Release 构建
swift build -c release

# 运行
.build/debug/Meow

# 打包 DMG
bash scripts/build-dmg.sh
```

当 `logo.png` 比当前生成的 `AppIcon.icns` 更新时，DMG 构建脚本会自动重新生成应用图标。

如需自定义 Bundle ID：

```bash
APP_BUNDLE_ID=tech.lury.meow bash scripts/build-dmg.sh
```

## 使用方式

1. 启动 Meow 后，通过快捷键呼出面板（默认：`Opt+Space`）。
2. 输入关键词搜索应用或命令。
3. 使用 `上/下` 选择结果，回车启动应用或执行命令。
4. 在剪贴板条目上使用操作菜单，可粘贴、复制、删除、在 Finder 中显示，或询问 AI。
5. 在偏好设置中调整语言、主题、快捷键、Dock、菜单栏、剪贴板、身份验证器、健康提醒、按键叠层与 AI 设置。

## 身份验证器

可在「偏好设置 -> 身份验证器」中配置 TOTP 身份验证器。

- 账户密钥保存在 macOS 钥匙串中，不写入 Meow 设置
- 支持手动输入 Base32 密钥和标准 `otpauth://` 链接
- 支持导入 Meow 备份、令牌数组和 Keyden Vault JSON
- 在明确提示明文密钥风险后，可导出带版本信息的 JSON 备份
- 复制的验证码和导入的密钥不会进入 Meow 剪贴板历史
- 可通过 iCloud 钥匙串同步独立账户

iCloud 钥匙串同步需要稳定的 Apple 签名及相应 entitlement。未签名或临时签名构建会保持本地存储，并显示缺少能力的原因。导出的 JSON 含明文 TOTP 密钥，必须安全保管。

## 离线语音识别

可在「偏好设置 -> 语音」中配置。

- 启用功能后，按住 `Option+R` 录音（最长 30 秒），松开后识别并粘贴到当前应用
- 使用 sherpa-onnx 与本地语音模型，全程本地运行，支持多语言 SenseVoice Small int8 和英文 Parakeet int8
- 仅在偏好设置中确认后下载约 230 MB 模型
- 支持中文、英语、日语、韩语和粤语
- 成功识别的文本与 WAV 录音默认在本机保留 30 天
- 需要麦克风权限；自动粘贴还需要辅助功能权限

语音历史和模型保存在：

```text
~/Library/Application Support/Meow/ASRHistory/
~/Library/Application Support/Meow/Models/ASR/
```

## 健康提醒

Meow 可以在专注工作和短暂休息之间循环提醒。可在「偏好设置 -> 健康」中配置。

- 开始工作计时，并在该休息时提醒你
- 在菜单栏日历面板中显示控制项，并提供浮动休息叠层
- 在本地记录今日已完成和已跳过的休息次数
- 休息期间检测到键盘或鼠标操作时，可暂停休息倒计时
- 支持温和和严格两种休息窗口模式

## 按键可视化

Meow 可以在可拖拽叠层中显示全局按键。可在「偏好设置 -> 键盘」中配置。

- 全局按键监听需要辅助功能权限
- 支持仅快捷键、快捷键 + 特殊键、全部按键三种显示模式
- 支持紧凑/醒目样式、预设或自定义位置、透明度、显示时长，以及 1-3 条历史记录
- 按键标签会尽量跟随当前 macOS 键盘布局

## AI 助手

Meow 内置兼容 OpenAI 的聊天助手。可在「偏好设置 -> AI」中配置：

- 接口地址，例如 `https://api.openai.com/v1/chat/completions`
- API Key
- 模型名称，可手动输入，也可从服务商的 `/models` 接口获取

聊天历史保存在本机：

```text
~/Library/Application Support/Meow/AIChats/
```

API Key 仍保存在 Meow 的本地设置中。聊天历史可在 AI 设置页关闭、清空，或直接打开所在文件夹。

## 代码结构

- `Sources/App/MeowApp.swift`: 应用生命周期与窗口管理
- `Sources/ViewModels/LauncherViewModel.swift`: 搜索与排序逻辑
- `Sources/Views/`: 启动器、AI 聊天、身份验证器、偏好设置、翻译面板与 UI 组件
- `Sources/Theme.swift`: 主题配色系统
- `Sources/Services/`: 快捷键、状态栏、自动启动、剪贴板、翻译、语音识别、身份验证器、AI 聊天与持久化
- `Sources/Models/`: 应用、剪贴板、身份验证器与设置模型
- `Sources/Resources/`: 本地化资源
- `Tests/`: Swift Testing 自动化测试

## 说明

- 提交变更前运行 `swift test`、`swift build` 和 `swift build -c release`。
- 身份验证器相关变更需要手动检查：钥匙串存储、剪贴板历史排除、JSON 风险提示，以及同步不可用时的本地回退。
- AI 相关变更需要手动检查：已配置/未配置状态、模型获取/手动输入、Enter 发送、Shift+Enter 换行、聊天历史，以及打开历史文件夹。
- 健康提醒相关变更需要手动检查：计时开始/暂停/继续、休息开始/跳过/完成、每日目标进度、活跃检测暂停倒计时，以及菜单栏日历面板控制。
- 按键叠层相关变更需要手动检查：辅助功能权限拒绝/已授权状态、快捷键冲突处理、拖拽/重置叠层，以及非美式键盘布局。
- 详细开发说明见 [DEVELOPMENT.md](DEVELOPMENT.md)。
