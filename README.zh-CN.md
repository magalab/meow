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
- 按键可视化叠层，支持拖拽、显示模式、显示时长、透明度与历史数量
- 菜单栏日历，含农历日期、节气、节假日及 Calendar.app 事件
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
5. 在偏好设置中调整语言、主题、快捷键、Dock、菜单栏、剪贴板、按键叠层与 AI 设置。

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
- `Sources/Views/`: 启动器、AI 聊天、偏好设置、翻译面板与 UI 组件
- `Sources/Theme.swift`: 主题配色系统
- `Sources/Services/`: 快捷键、状态栏、自动启动、剪贴板、翻译、AI 聊天与持久化
- `Sources/Models/`: 应用、剪贴板与设置模型
- `Sources/Resources/`: 本地化资源

## 说明

- 当前项目没有自动化测试目标，主要依赖手工验证。
- AI 相关变更需要手动检查：已配置/未配置状态、模型获取/手动输入、Enter 发送、Shift+Enter 换行、聊天历史，以及打开历史文件夹。
- 按键叠层相关变更需要手动检查：辅助功能权限拒绝/已授权状态、快捷键冲突处理、拖拽/重置叠层，以及非美式键盘布局。
- 详细开发说明见 [DEVELOPMENT.md](DEVELOPMENT.md)。
