# TouchBarScreen 架构文档

## 1. 项目目标

TouchBarScreen 将 macOS 中一个真实或虚拟显示器的画面实时绘制到实体 Touch Bar。
它不创建显示器，也不修改系统显示拓扑。虚拟桌面由 BetterDisplay 等外部工具
提供，本项目只负责显示器枚举、画面采集、鼠标跟踪和 Touch Bar 呈现。

## 2. 技术栈

- AppKit：应用生命周期、菜单栏、Touch Bar 和绘图
- ScreenCaptureKit：显示器枚举和实时屏幕采集
- Core Image：将采集像素缓冲转换为 `CGImage`
- Core Graphics：显示器坐标和鼠标位置
- Carbon HIToolbox：系统级全局快捷键
- Objective-C Runtime：动态调用私有 Touch Bar API
- Swift Package Manager：构建和测试

## 3. 模块职责

### AppDelegate

`AppDelegate` 是应用的协调层，负责：

- 初始化菜单栏应用
- 加载和保存用户设置
- 选择显示器并控制采集生命周期
- 把采集帧和鼠标位置转交给 Touch Bar
- 响应菜单操作和全局快捷键
- 监听应用切换、Space 切换和显示器配置变化
- 在显示器断开后执行恢复

它维护两个不同的采集状态：

- `isCapturing`：当前是否存在正在工作的采集流程
- `wantsCapture`：用户是否仍然希望保持采集

两者分离后，采集流因断屏意外停止时，应用仍可以判断是否应该自动恢复。

### ScreenCaptureEngine

`ScreenCaptureEngine` 封装 ScreenCaptureKit。

显示器枚举流程：

1. 调用 `SCShareableContent` 获取可共享内容。
2. 将 `SCDisplay` 与 `NSScreen` 按 display ID 对应。
3. 生成包含名称、分辨率和主屏状态的 `CapturableDisplay`。
4. 将非主屏排在主屏前面，便于默认选择虚拟显示器。

采集流程：

1. 根据 display ID 查找 `SCDisplay`。
2. 创建不排除任何窗口的 `SCContentFilter`。
3. 配置最大 2560 像素宽的 BGRA 视频流。
4. 设置目标 FPS、队列深度 2，并关闭音频。
5. 在独立的高优先级串行队列中接收视频帧。
6. 将 `CVPixelBuffer` 转换为 `CIImage` 和 `CGImage`。
7. 回到主线程分发 `CapturedFrame`。

限制最大采集宽度可以降低像素转换和 Touch Bar 绘制成本。Touch Bar 高度很小，
继续处理显示器原始的 4K 或更高分辨率通常没有可见收益。

### TouchBarController

`TouchBarController` 创建只包含一个 `NSCustomTouchBarItem` 的 `NSTouchBar`，并把
`TouchBarFrameView` 作为该项目的视图。

它支持两种安装方式：

1. 常驻模式：通过 Objective-C 桥接呈现系统模态 Touch Bar。
2. 公开模式：设置 `NSApp.touchBar`，内容只按正常应用规则出现。

请求常驻模式但私有 API 不可用时，会自动使用公开模式。

### TouchBarFrameView

`TouchBarFrameView` 是实际绘图层，逻辑高度固定为 30 pt。

画面分区：

- 左侧预览区：以 `aspectFit` 显示完整桌面。
- 中间分隔线：区分预览与细节。
- 右侧细节区：裁剪鼠标附近区域并拉伸到剩余空间。

局部视图的源区域大小为：

```text
sourceWidth  = detailWidth  / magnification
sourceHeight = detailHeight / magnification
```

倍率越大，采样的源图区域越小，最终视觉放大程度越高。裁剪区域在屏幕边缘会被
限制在图像范围内。

### GlobalHotKeyManager

全局快捷键使用 Carbon `RegisterEventHotKey` 注册，不依赖应用处于前台。

每项动作分配固定 ID，Carbon 事件处理器收到按键后把 ID 转换为 `Action`，再通过
闭包通知 `AppDelegate`。自定义快捷键以 JSON 编码后保存到 `UserDefaults`。

录制新快捷键期间，管理器会暂时注销已有快捷键，防止录制动作触发真实命令。

### TouchBarPrivateBridge

Swift 目标通过 Objective-C 桥接访问私有 API。桥接层不会直接静态引用私有符号，
而是按名称检查类方法是否存在，再使用 `objc_msgSend` 调用。

代码同时尝试 Touch Bar 和 Function Bar 两组历史命名，以兼容不同系统实现。

## 4. 运行时调用链

启动流程：

```text
main.swift
  -> NSApplication.run()
  -> AppDelegate.applicationDidFinishLaunching()
  -> 加载偏好和注册全局快捷键
  -> 枚举显示器
  -> 恢复上次选择或选择第一个非主屏
  -> ScreenCaptureEngine.start()
  -> TouchBarController.install()
```

单帧流程：

```text
SCStreamOutput
  -> CVPixelBuffer
  -> CIContext.createCGImage()
  -> CapturedFrame
  -> AppDelegate.onFrame
  -> TouchBarController.setFrame()
  -> TouchBarFrameView.needsDisplay
  -> TouchBarFrameView.draw()
```

鼠标跟踪流程：

```text
30 Hz DispatchSourceTimer
  -> CGEvent.location
  -> 转换为显示器内 0...1 坐标
  -> AppDelegate.onCursorPosition
  -> TouchBarFrameView.updateCursorPosition()
```

## 5. 坐标转换

全局鼠标坐标减去目标显示器原点后，再除以显示器宽高，得到归一化坐标：

```text
x = (mouseX - displayMinX) / displayWidth
y = (mouseY - displayMinY) / displayHeight
```

结果被限制在 `0...1`，鼠标位于其他显示器时，局部画面会停留在目标显示器最近的
边缘。

AppKit 图像裁剪使用的垂直坐标方向与全局屏幕坐标不同，因此绘制局部区域时使用：

```text
imageY = (1 - normalizedY) * imageHeight
```

## 6. 恢复策略

显示器配置变化或 `SCStream` 异常停止后，只要 `wantsCapture` 仍为真，应用就会在
约 0.4、1.2、3.0 和 6.0 秒后重新枚举显示器。

目标显示器按以下优先级恢复：

1. 原 display ID 仍然存在
2. 名称和分辨率与原显示器相同
3. 第一个非主显示器
4. 第一个可用显示器

名称和分辨率匹配用于处理虚拟显示器重连后 display ID 改变的情况。

切换前台应用或 Space 时，系统可能覆盖系统模态 Touch Bar。常驻模式会在通知后
延迟 0.2 秒和 0.9 秒重新呈现，兼顾快速恢复和系统切换动画完成后的二次确认。

## 7. 持久化设置

以下设置存储在 `UserDefaults`：

| Key | 含义 |
| --- | --- |
| `selectedDisplayID` | 上次选择的显示器 ID |
| `detailMagnification` | 局部画面缩放倍率 |
| `framesPerSecond` | 采集帧率 |
| `persistentTouchBar` | 是否请求常驻模式 |
| `hotKey.<actionID>` | 对应动作的快捷键 JSON |

## 8. 构建产物

`scripts/build-app.sh` 执行以下步骤：

1. 使用 SwiftPM 构建 Release 可执行文件。
2. 创建标准 `.app/Contents/MacOS` 目录。
3. 复制可执行文件和 `Info.plist`。
4. 使用 `codesign --sign -` 执行临时签名。

生成结果位于 `dist/TouchBarScreen.app`。`dist` 和 `.build` 均不进入版本控制。

## 9. 测试

当前单元测试覆盖图像布局算法：

- Stretch 使用完整目标区域
- Aspect Fit 保持比例并居中
- Center Crop 保持比例并允许居中溢出

后续适合补充的测试包括显示器恢复选择、缩放边界、坐标转换，以及将采集和
Touch Bar 呈现抽象为可替换依赖后的状态机测试。

## 10. 风险与约束

- 私有 API 可能随 macOS 更新发生变化。
- 私有 API 应用不能提交到 Mac App Store。
- ScreenCaptureKit 权限必须由用户在系统设置中授予。
- Carbon 全局快捷键 API 较旧，但适合当前无第三方依赖的轻量实现。
- 实体 Touch Bar 的显示空间有限，本项目定位是监看和定位，不是完整桌面交互。
