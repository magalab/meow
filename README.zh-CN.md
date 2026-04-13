# Meow

[English](README.md) | [简体中文](README.zh-CN.md)

轻量级 macOS 启动器（SwiftUI + AppKit）。

## 功能

- 全局快捷键呼出启动器
- 应用搜索（带启动历史权重）
- 内置命令（偏好设置 / 退出）
- 菜单栏控制与可选 Dock 图标
- 登录启动（受 macOS 签名策略限制）
- 运行时语言切换（英文 / 简体中文）
- 多主题配色（默认：调皮猫猫）

## 环境要求

- macOS 14+
- Swift 5.9+

## 快速开始

```bash
# 构建
swift build

# 运行
.build/debug/Meow

# 生成 DMG
bash scripts/build-dmg.sh
```

如需自定义 Bundle ID：

```bash
APP_BUNDLE_ID=tech.lury.meow bash scripts/build-dmg.sh
```

## 使用方式

1. 启动 Meow 后，通过快捷键呼出面板（默认：`Cmd+Space`）。
2. 输入关键词搜索应用或命令。
3. 使用 `上/下` 选择结果，回车启动。
4. 在偏好设置中调整语言、主题、快捷键、Dock 与菜单栏选项。

## 代码结构

- `Sources/MeowApp.swift`: 应用生命周期与窗口管理
- `Sources/LauncherViewModel.swift`: 搜索与排序逻辑
- `Sources/Views.swift`: 启动器与偏好设置 UI
- `Sources/Theme.swift`: 主题配色系统
- `Sources/Services.swift`: 快捷键、状态栏、自动启动、持久化
- `Sources/Resources/`: 本地化资源

## 说明

- 当前项目没有自动化测试目标，主要依赖手工验证。
- 详细开发说明见 [DEVELOPMENT.md](DEVELOPMENT.md)。
