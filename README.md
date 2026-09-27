# TouchBarScreen

TouchBarScreen 是一个 macOS 菜单栏应用，用于把指定显示器实时镜像到
2016-2020 Intel MacBook Pro 的 Touch Bar。它也可以配合 BetterDisplay 创建的
虚拟显示器，把 Touch Bar 作为虚拟桌面的监看窗口使用。

Touch Bar 左侧显示完整桌面缩略图，右侧显示以鼠标位置为中心的局部画面。

## 功能

- 枚举并选择 macOS 当前可采集的显示器
- 支持 BetterDisplay 等工具创建的虚拟显示器
- Touch Bar 左侧显示完整桌面，右侧显示鼠标附近细节
- 支持 `0.1x-20x` 局部缩放
- 支持 `5/10/15/30 FPS` 采集帧率
- 支持自定义全局快捷键
- 保存显示器、帧率、缩放和常驻模式等设置
- 显示器断开或重连后自动尝试恢复采集
- 可使用私有 API 让画面在切换应用后继续常驻 Touch Bar

## 系统要求

- 带 Touch Bar 的 Intel MacBook Pro
- macOS 13 或更高版本
- Xcode 15 或更高版本
- Swift 6 工具链

> 项目的主要目标设备是 2016-2020 款带实体 Touch Bar 的 Intel MacBook Pro。
> 没有 Touch Bar 的 Mac 可以构建和启动应用，但无法使用核心显示功能。

## 快速开始

```bash
chmod +x scripts/build-app.sh
./scripts/build-app.sh
open dist/TouchBarScreen.app
```

构建脚本会执行 Release 构建，将可执行文件和 `Info.plist` 组装到
`dist/TouchBarScreen.app`，然后使用本机临时签名完成签署。

第一次启动时，请在“系统设置 > 隐私与安全性 > 屏幕与系统音频录制”中允许
TouchBarScreen 录制屏幕。授权后可能需要退出并重新打开应用。

## 使用方法

1. 启动 TouchBarScreen。
2. 在菜单栏找到矩形叠加图标。
3. 选择需要镜像的显示器。
4. 根据需要设置鼠标局部缩放和采集帧率。
5. 使用“启动镜像”或全局快捷键控制采集。

配合 BetterDisplay 时，可以先创建并连接虚拟显示器，再从 TouchBarScreen
菜单中选择该显示器。

默认全局快捷键：

| 操作 | 快捷键 |
| --- | --- |
| 启动或停止镜像 | `Control + Option + Command + T` |
| 缩放减小 0.1x | `Control + Option + Command + -` |
| 缩放增大 0.1x | `Control + Option + Command + =` |
| 输入自定义缩放倍率 | `Control + Option + Command + M` |

快捷键可以在菜单栏的“全局快捷键”子菜单中逐项修改。

## 工作原理

应用通过 ScreenCaptureKit 获取显示器视频帧，将 `CVPixelBuffer` 转换为
`CGImage`，再交给自定义 `NSView` 绘制到 `NSTouchBar`。

```text
显示器或虚拟显示器
        |
        v
ScreenCaptureKit / SCStream
        |
        v
CVPixelBuffer -> CIImage -> CGImage
        |
        v
TouchBarFrameView
        |
        +-- 左侧：完整画面缩略图
        |
        +-- 右侧：以鼠标为中心的局部裁剪画面
```

采集帧率和鼠标跟踪相互独立。视频帧按照菜单中选择的 FPS 更新，鼠标位置约以
30 Hz 采样，因此在较低采集帧率下，局部视图仍能及时跟随鼠标。

更完整的模块说明、调用链和恢复策略见
[架构文档](docs/ARCHITECTURE.md)。

## 常驻模式

公开的 `NSTouchBar` API 通常只在应用处于活动状态时显示内容。为了在切换到其他
应用后继续显示画面，本项目可以动态调用 macOS 未公开的系统模态 Touch Bar API。

常驻模式使用 `placement: 0`，保留右侧系统 Control Strip。macOS 不允许一个
常驻系统模态栏与当前应用自己的 App Controls 同时占用左侧区域。

如果运行环境不支持对应私有方法，程序会自动回退到公开的 `NSApp.touchBar`
行为。

> 私有 API 只适合个人签名和本机使用，不能提交到 Mac App Store，并且可能在
> 后续 macOS 版本中失效。

## 开发

运行测试：

```bash
swift test
```

直接运行 Debug 版本：

```bash
swift run TouchBarScreen
```

项目使用 Swift Package Manager 管理代码，没有第三方运行时依赖。

主要目录：

```text
Resources/                    应用 Info.plist
Sources/TouchBarScreen/       Swift 应用代码
Sources/TouchBarPrivateBridge Objective-C 私有 API 桥接
Tests/                        单元测试
scripts/build-app.sh          App Bundle 构建脚本
```

## 已知限制

- 依赖带实体 Touch Bar 的 MacBook Pro 才能使用核心功能。
- 屏幕录制需要用户手动授予系统权限。
- 常驻模式依赖私有 API，无法保证跨 macOS 版本稳定。
- Touch Bar 是画面的监看视图，不会被 macOS 识别为独立显示器。
- 当前只显示画面，不转发 Touch Bar 触控事件到被镜像显示器。

## 版本

当前首个版本为 `0.1.0`。
