# Monitor - 屏幕卫士

一个 macOS 应用，利用摄像头实时监测是否有人从你身后查看屏幕。一旦检测到有人注视屏幕，自动将前台应用切换到 VS Code。

## 工作原理

1. **校准阶段** — 启动监控后，应用会在 ~6 秒内学习你（主人）的人脸特征（大小/位置）
2. **监控阶段** — 持续检测摄像头画面中的人脸数量
   - 只有 1 张脸（你自己） → 安全
   - 检测到额外的人脸且朝向屏幕 → 触发警报
3. **触发切换** — 如果额外人脸持续注视屏幕超过设定时间（默认 1 秒），自动将 VS Code 切换到前台
4. **冷却期** — 切换后等待一段冷却时间（默认 10 秒）才恢复监控

### 检测逻辑

- 使用 **Vision** 框架的 `VNDetectFaceRectanglesRequest` 进行人脸检测
- 最大的人脸 = 你（离摄像头最近的人）
- 其他人脸如果 yaw 朝向摄像头（|yaw| < 0.5 rad）= 正在看屏幕
- 每 200ms 处理一帧，不会占用过多 CPU

## 系统要求

- macOS 13.0 (Ventura) 或更高版本
- 内置或外接摄像头
- VS Code 已安装（用于自动切换目标）

## 构建与运行

### 方式一：命令行构建

```bash
cd /path/to/Monitor
chmod +x build.sh
./build.sh

# 运行
open build/Monitor.app
```

### 方式二：Xcode 构建

1. 打开 Xcode → File → New → Project → macOS → App
2. Product Name: `Monitor`，Language: Swift，Interface: SwiftUI
3. 删除 Xcode 自动生成的源文件
4. 将 `Monitor/` 目录下的所有 `.swift` 文件拖入项目
5. 在 target 的 Info 中添加 `NSCameraUsageDescription`
6. Build & Run

## 使用方法

1. 启动应用后，会请求摄像头权限 → 允许
2. 点击 **「开始监控」** 按钮
3. **校准**：确保只有你在摄像头画面中，等待校准完成（~6 秒）
4. 校准完成后进入监控状态（绿色指示灯）
5. 如果有人从你身后注视屏幕，应用会自动切换到 VS Code

### 状态指示

| 颜色 | 含义 |
|------|------|
| 🔘 灰色 | 未启动 |
| 🟡 黄色 | 校准中 |
| 🟢 绿色 | 正常监控 |
| 🔴 红色 | 检测到入侵 |

### 可调设置

- **检测灵敏度** (0.3 – 3.0s)：有人注视屏幕多久后触发切换
- **切换冷却时间** (3 – 30s)：触发切换后暂停检测的时间

## 项目结构

```
Monitor/
├── Monitor/
│   ├── MonitorApp.swift              # 应用入口
│   ├── ContentView.swift             # 主界面 (SwiftUI)
│   ├── CameraPreviewView.swift       # 摄像头预览视图
│   ├── ScreenGuardController.swift   # 核心控制器 (摄像头 + 检测 + 切换)
│   ├── Info.plist                    # 应用配置 & 摄像头权限描述
│   └── Monitor.entitlements          # 应用权限
├── build.sh                          # 命令行构建脚本
└── README.md                         # 本文件
```

## 注意事项

- 首次运行需要授权摄像头权限
- 确保 VS Code 已安装，否则切换功能无法生效
- 校准时请确保画面中只有你一个人
- 光线较暗时人脸检测准确度可能下降
