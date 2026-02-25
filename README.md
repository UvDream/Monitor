# 屏幕卫士 (Monitor)

> 一个 macOS 菜单栏应用，利用摄像头实时监测是否有人从你身后查看屏幕。一旦检测到偷窥者，自动将前台切换到指定的"安全应用"，并可对偷窥者拍照留证。

---

## ✨ 功能特性

| 功能 | 说明 |
|------|------|
| 🎥 实时人脸检测 | 基于 Apple Vision 框架，每 200ms 分析一次摄像头画面 |
| 🧠 持久化人脸校准 | 首次校准（约 6 秒）后自动保存，后续启动直接跳过校准 |
| 🚨 偷窥检测 | 发现有人朝向屏幕时触发警报并自动切换应用 |
| 📸 偷窥者截图 | 触发时自动截取摄像头画面，保存到指定目录 |
| 🛡️ 白名单保护 | 指定"安全应用"，在前台时不触发切换 |
| 🎯 自定义目标应用 | 触发时切换到任意已安装的 App（默认 VS Code） |
| ⚙️ 参数可调 | 检测灵敏度和冷却时间均可滑动调节并持久保存 |
| 📊 菜单栏角标 | 实时显示画面中人脸数量及监控状态 |

---

## 🔍 检测原理

### 三阶段流程

```
第一阶段：校准（仅首次，约 6 秒）
    ↓  确保画面中只有你，Vision 框架采集 30 帧
    ↓  计算你的人脸面积均值 → 保存为"主人脸参考值"

第二阶段：实时监控
    ↓  每 200ms 抓取一帧摄像头画面
    ↓  Vision 检测所有人脸的位置 + yaw（左右偏转角）
    ↓  找出面积与参考值最接近的脸 = 你
    ↓  其余人脸 且 |yaw| < 0.5 rad（约 28°，正对屏幕）→ 视为威胁
    ↓  威胁持续超过"检测灵敏度"设定的秒数 → 触发

第三阶段：触发与冷却
    ↓  切换到目标应用（如 VS Code）
    ↓  截图保存偷窥者照片（如已开启）
    ↓  进入冷却期，等待设定秒数后恢复监控
```

### 主人脸识别方式

> 不是取"最大的脸"，而是取**面积最接近校准参考值**的脸作为主人。
> 这样即使偷窥者凑近摄像头变成画面中最大的脸，也不会被误判为主人。

---

## 🖥️ 系统要求

- **macOS 13.0 (Ventura)** 或更高版本
- 内置或外接摄像头
- Xcode Command Line Tools（仅命令行构建时需要）

---

## 🔨 构建与运行

### 方式一：命令行构建（推荐）

```bash
cd /path/to/Monitor
chmod +x build.sh
./build.sh

# 运行
open build/Monitor.app
```

构建脚本会自动检测你的 Mac 架构：
- **Apple Silicon (arm64)**：生成同时包含 arm64 + x86_64 的 **Universal Binary**
- **Intel (x86_64)**：生成 x86_64 单架构二进制

### 方式二：Xcode 构建

1. 打开 Xcode → **File → New → Project → macOS → App**
2. Product Name: `Monitor`，Language: `Swift`，Interface: `SwiftUI`
3. 删除 Xcode 自动生成的源文件
4. 将 `Monitor/` 目录下的所有 `.swift` 文件拖入项目
5. 在 Target 的 **Signing & Capabilities** 中添加摄像头权限：
   - Info.plist 添加 `NSCameraUsageDescription`
6. Build & Run

---

## 📖 使用方法

### 首次启动

1. 双击 `build/Monitor.app` 运行
2. 系统弹出摄像头权限请求 → 点击 **允许**
3. 主窗口和菜单栏图标同时出现

### 开始监控

1. 主窗口点击 **「开始监控」**（或菜单栏图标 → 开始监控）
2. **首次运行**：进入约 6 秒的校准阶段
   - 确保摄像头画面中**只有你一个人**，画面稳定面对摄像头
   - 校准完成后数据自动保存，**下次启动直接跳过此步骤**
3. 状态指示灯变绿 → 监控正式开始

### 状态指示说明

| 菜单栏图标点 | 主窗口颜色 | 含义 |
|:-----------:|:----------:|------|
| ⚫ 灰色 | 灰色 | 未启动 |
| 🟡 黄色 | 黄色 | 校准中 |
| 🟢 绿色 | 绿色 | 正常监控 |
| 🔴 红色 | 红色 | 检测到偷窥者，已触发切换 |

菜单栏图标旁的数字 = 当前摄像头画面中检测到的人脸数量。

---

## ⚙️ 功能设置

### 人脸校准

| 操作 | 说明 |
|------|------|
| 自动校准 | 首次开始监控时约 6 秒完成，无需手动操作 |
| 查看状态 | 主窗口"人脸校准"区显示校准状态和当前参考值 |
| 重新校准 | 点击"重新校准"按钮 → 确认 → 下次启动时重新采集 |

### 切换目标

- 点击**「更换」**按钮，从已安装的应用中搜索并选择
- 默认为 **Visual Studio Code**
- 支持搜索"全部已安装应用"或"当前运行中的应用"

### 白名单

- 添加的应用在**当前处于前台**时，不会触发切换（适合设置为"你自己的隐私 App"）
- 点击 **「添加应用」** 从列表选择，点击 ✕ 移除

### 检测设置

| 参数 | 范围 | 默认值 | 说明 |
|------|------|--------|------|
| 检测灵敏度 | 0.3 – 3.0 秒 | 1.0 秒 | 偷窥者需持续注视屏幕多久才触发 |
| 切换冷却时间 | 3 – 30 秒 | 10 秒 | 触发切换后暂停检测的时长 |

两项参数均**自动持久化**，重启后保留。

### 截图保护

1. 开启 **「触发时自动截图偷窥者」** 开关
2. 点击 **「选择」** 指定截图保存目录
3. 点击 ⬆️ 按钮可直接在 Finder 中打开保存目录

**截图文件命名规则：**
```
intruder_2026-02-25_15-30-00.123.jpg
```
精确到毫秒，同一次入侵多次触发不会相互覆盖。

---

## 📁 项目结构

```
Monitor/                              ← 项目根目录
├── Sources/                          ← Swift 源文件
│   ├── MonitorApp.swift              # 应用入口 (AppDelegate)
│   ├── ContentView.swift             # 主界面 (SwiftUI)
│   │   ├── CalibrationStatusView     # 人脸校准状态面板
│   │   ├── SnapshotSettingsView      # 截图保护设置面板
│   │   └── AppPickerView             # 应用选择 Sheet
│   ├── CameraPreviewView.swift       # 摄像头预览视图 (NSViewRepresentable)
│   ├── ScreenGuardController.swift   # 核心控制器
│   │   ├── 摄像头采集 & Vision 检测
│   │   ├── 人脸校准 & 持久化
│   │   ├── 威胁检测逻辑
│   │   ├── 应用切换
│   │   └── 截图保存
│   ├── StatusBarController.swift     # 菜单栏图标 & 菜单
│   └── AppInfo.swift                 # 应用信息模型（扫描/枚举已安装 App）
├── Resources/                        ← 非代码资源
│   ├── AppIcon.icns                  # 应用图标
│   ├── Info.plist                    # 应用配置 & 摄像头权限描述
│   └── Monitor.entitlements          # 应用权限
├── build/                            ← 构建产物（建议 .gitignore）
├── build.sh                          # 命令行构建脚本（支持 Universal Binary）
└── README.md                         # 本文件
```

---

## 💾 持久化数据说明

所有设置保存在 macOS 用户 `UserDefaults` 中，键名如下：

| 键名 | 类型 | 说明 |
|------|------|------|
| `monitor.ownerFaceArea` | Double | 校准的人脸面积参考值 |
| `monitor.detectionDelay` | Double | 检测灵敏度 |
| `monitor.cooldownDuration` | Double | 冷却时间 |
| `monitor.snapshotEnabled` | Bool | 截图功能开关 |
| `monitor.snapshotDirectory` | String | 截图保存目录路径 |
| `monitor.targetApp` | Data (JSON) | 切换目标应用 |
| `monitor.whitelistedApps` | Data (JSON) | 白名单列表 |

如需完全重置所有设置，可在终端执行：
```bash
defaults delete com.monitor
```

---

## ⚠️ 注意事项

- 首次运行需授权摄像头权限，可在 **系统设置 → 隐私与安全性 → 摄像头** 中管理
- 校准时请确保画面中**只有你一个人**，且光线充足
- 光线较暗时人脸检测准确率可能下降
- 偷窥者从摄像头视角盲区靠近时无法检测
- 截图功能保存的是摄像头画面（你身后的场景），而非屏幕截图

---

## 🛠️ 技术栈

| 组件 | 技术 |
|------|------|
| UI 框架 | SwiftUI + AppKit |
| 人脸检测 | Apple Vision (`VNDetectFaceRectanglesRequest` Revision 3) |
| 摄像头采集 | AVFoundation (`AVCaptureSession`) |
| 图像处理 | Core Image (`CIContext`) |
| 状态管理 | Combine (`@Published` + `ObservableObject`) |
| 数据持久化 | UserDefaults |
