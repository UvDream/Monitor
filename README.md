# 屏幕卫士 (Monitor)

> 一个 macOS 菜单栏应用，利用摄像头实时监测是否有人从你身后查看屏幕。  
> 一旦检测到偷窥者，自动将前台切换到指定的「安全应用」，并可对偷窥者自动拍照留证。

---

## ✨ 功能特性

| 功能 | 说明 |
|------|------|
| 🎥 实时人脸检测 | 基于 Apple Vision 框架，每 200ms 分析一次摄像头画面 |
| 🧠 持久化人脸校准 | 首次校准（约 6 秒）后自动保存，后续启动直接跳过校准 |
| 🚨 偷窥检测与切换 | 发现有人朝向屏幕时触发警报，自动切换到指定安全应用 |
| 📸 偷窥者截图 | 触发时自动截取摄像头画面，保存为 JPEG 到指定目录 |
| 🛡️ 白名单保护 | 指定「安全应用」，在前台时不触发切换 |
| 🎯 自定义切换目标 | 可切换到任意已安装的 App（默认 VS Code） |
| ⚙️ 参数可调且持久化 | 检测灵敏度和冷却时间均可滑动调节，重启后保留 |
| 📊 菜单栏实时状态 | 图标颜色反映当前状态，角标数字显示检测到的人脸数 |

---

## 🔍 检测原理

### 三阶段流程

```
第一阶段：校准（仅首次，约 6 秒）
    ↓  确保画面中只有你一个人，Vision 框架采集 30 帧
    ↓  计算你的人脸面积均值，保存为「主人脸参考值」到 UserDefaults

第二阶段：实时监控
    ↓  每 200ms 从摄像头抓取一帧
    ↓  Vision 检测所有人脸的位置 + yaw（左右偏转角）
    ↓  面积最接近参考值的脸 = 你（主人）
    ↓  其余人脸：|yaw| < 0.5 rad（约 28°，正对屏幕）→ 视为威胁
    ↓  威胁持续时间超过「检测灵敏度」→ 触发

第三阶段：触发与冷却
    ↓  切换到目标应用（如 VS Code）
    ↓  自动截图保存偷窥者照片（如已开启）
    ↓  进入冷却期，等待设定秒数后恢复监控
```

### 主人脸识别方式

> 不是简单取「画面中最大的脸」，而是找**面积最接近校准参考值**的脸作为主人。  
> 即使偷窥者凑近摄像头变成画面中最大的脸，也不会被误判为主人。

### yaw 角判断「是否在看屏幕」

```
正对屏幕时，脸朝向摄像头 → yaw ≈ 0      → 威胁 ⚠️
侧身不看时，脸朝向侧面   → |yaw| 增大   → 安全 ✅
阈值：|yaw| < 0.5 rad（约 28°）视为朝向屏幕
```

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
- **Apple Silicon (arm64)**：先分别编译 arm64 和 x86_64，再用 `lipo` 合并为 **Universal Binary**
- **Intel (x86_64)**：直接生成 x86_64 单架构二进制

### 方式二：Xcode 构建

1. 打开 Xcode → **File → New → Project → macOS → App**
2. Product Name: `Monitor`，Language: `Swift`，Interface: `SwiftUI`
3. 删除 Xcode 自动生成的源文件
4. 将 `Sources/` 目录下的所有 `.swift` 文件拖入项目
5. 在 Target 的 **Signing & Capabilities** 中：
   - 添加 `Resources/Info.plist` 中的 `NSCameraUsageDescription` 描述
   - 导入 `Resources/Monitor.entitlements`
6. Build & Run

---

## 📖 使用方法

### 首次启动

1. 双击 `build/Monitor.app` 运行（或 `open build/Monitor.app`）
2. 系统弹出摄像头权限请求 → 点击 **允许**
3. 主窗口和菜单栏图标同时出现

### 开始监控

1. 在主窗口点击 **「开始监控」**，或从菜单栏图标菜单中点击
2. **首次运行**：进入约 6 秒的自动校准阶段
   - 确保摄像头画面中**只有你一个人**，保持画面稳定
   - 校准完成后数据**自动保存**，下次启动直接跳过此步骤
3. 状态指示灯变绿 → 正式进入监控

### 状态指示

| 菜单栏图标点 | 主窗口状态灯 | 含义 |
|:-----------:|:-----------:|------|
| ⚫ 灰色 | 灰色 | 未启动 |
| 🟡 黄色 | 黄色 | 校准中（请保持画面中只有你） |
| 🟢 绿色 | 绿色 | 正常监控中 |
| 🔴 红色 | 红色 | 检测到偷窥者，已触发切换 |

菜单栏图标旁的数字 = 当前摄像头画面中检测到的**人脸总数**。

---

## ⚙️ 功能设置

### 🧠 人脸校准

| 操作 | 说明 |
|------|------|
| 自动校准 | 首次「开始监控」时自动进行，约 6 秒完成 |
| 状态查看 | 主窗口「人脸校准」面板显示校准状态（已保存 / 未校准） |
| 重新校准 | 点击「重新校准」→ 确认弹窗 → 下次启动时重新采集 |

### 🎯 切换目标应用

- 点击**「更换」**按钮，搜索并选择任意已安装的 App
- 默认目标：**Visual Studio Code**
- 支持按名称/Bundle ID 搜索，可筛选「全部已安装」或「当前运行中」

### 🛡️ 白名单

- 白名单应用**正处于前台**时，即使检测到偷窥者也**不会触发切换**
- 适合添加你自己正在使用的隐私应用（如密码管理器）
- 点击「添加应用」从列表选择，点击 ✕ 移除

### ⚙️ 检测设置

| 参数 | 范围 | 默认 | 说明 |
|------|------|------|------|
| 检测灵敏度 | 0.3 – 3.0 秒 | 1.0 秒 | 偷窥者需持续注视屏幕多久才触发 |
| 切换冷却时间 | 3 – 30 秒 | 10 秒 | 触发切换后暂停检测的时长 |

两项参数滑动后**自动写入 UserDefaults**，重启后保留。

### 📸 截图保护

1. 开启**「触发时自动截图偷窥者」**开关
2. 点击**「选择」**指定截图保存目录
3. 点击 ⬆️ 按钮可直接在 Finder 中打开保存目录

**截图文件命名规则：**
```
intruder_2026-02-25_15-30-00.123.jpg
```
- 精确到毫秒，同一次入侵多次触发不会相互覆盖
- 截图内容为**摄像头画面**（你身后的场景），不是屏幕截图

---

## 📁 项目结构

```
Monitor/                              ← 项目根目录
├── Sources/                          ← Swift 源文件
│   ├── MonitorApp.swift              # 应用入口 (AppDelegate + NSApplication)
│   ├── ContentView.swift             # 主界面 (SwiftUI)
│   │   ├── CalibrationStatusView     # 人脸校准状态面板
│   │   ├── SnapshotSettingsView      # 截图保护设置面板
│   │   └── AppPickerView             # 应用选择 Sheet（异步加载）
│   ├── CameraPreviewView.swift       # 摄像头预览视图 (NSViewRepresentable)
│   ├── ScreenGuardController.swift   # 核心控制器 (ObservableObject)
│   │   ├── 摄像头采集 & Vision 检测
│   │   ├── 人脸校准 & UserDefaults 持久化
│   │   ├── 威胁检测（yaw 角分析）
│   │   ├── 应用切换（白名单检查）
│   │   └── 截图保存（CIContext → JPEG）
│   ├── StatusBarController.swift     # 菜单栏图标 & 菜单（图标缓存）
│   └── AppInfo.swift                 # 应用信息模型（扫描/枚举已安装 App）
├── Resources/                        ← 非代码资源
│   ├── AppIcon.icns                  # 应用图标
│   ├── Info.plist                    # Bundle ID、摄像头权限描述等
│   └── Monitor.entitlements          # 摄像头权限声明
├── build/                            ← 构建产物（建议加入 .gitignore）
├── build.sh                          # 构建脚本（Universal Binary）
└── README.md                         # 本文件
```

---

## 💾 持久化数据说明

所有设置保存在 macOS `UserDefaults` 中（Bundle ID: `com.local.Monitor`）：

| 键名 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `monitor.ownerFaceArea` | Double | — | 校准的人脸面积参考值 |
| `monitor.detectionDelay` | Double | 1.0 | 检测灵敏度（秒） |
| `monitor.cooldownDuration` | Double | 10.0 | 冷却时间（秒） |
| `monitor.snapshotEnabled` | Bool | false | 截图功能开关 |
| `monitor.snapshotDirectory` | String | — | 截图保存目录路径 |
| `monitor.targetApp` | Data (JSON) | VS Code | 切换目标应用 |
| `monitor.whitelistedApps` | Data (JSON) | [] | 白名单列表 |

**重置单项设置（示例）：**
```bash
# 只重置人脸校准数据
defaults delete com.local.Monitor monitor.ownerFaceArea

# 重置所有设置
defaults delete com.local.Monitor
```

---

## ⚠️ 注意事项

- 首次运行需授权摄像头权限，可在 **系统设置 → 隐私与安全性 → 摄像头** 中管理
- 校准时确保画面中**只有你一个人**，且光线充足、面部朝向摄像头
- 光线较暗时，Vision 框架的人脸检测准确率会明显下降
- 偷窥者若从摄像头视角的盲区靠近，则无法检测
- 截图保存的是**摄像头画面**（你身后的物理场景），而非屏幕截图

---

## 🛠️ 技术栈

| 组件 | 技术 |
|------|------|
| UI 框架 | SwiftUI + AppKit |
| 人脸检测 | Apple Vision（`VNDetectFaceRectanglesRequest` Revision 3，支持 yaw 角） |
| 摄像头采集 | AVFoundation（`AVCaptureSession` + `AVCaptureVideoDataOutput`） |
| 图像渲染 | Core Image（`CIContext`，GPU 加速） |
| 状态管理 | Combine（`@Published` + `ObservableObject`） |
| 应用列表 | NSWorkspace + FileManager |
| 数据持久化 | UserDefaults |
| 构建 | swiftc + lipo（Universal Binary） |
