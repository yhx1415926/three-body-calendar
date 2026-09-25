# 三体人的万年历

原生 macOS 三星引力模拟与行星纪元历法。应用使用 SwiftUI、AppKit、MetalKit 和
REBOUND IAS15，计算在后台运行。全部计算与项目文件均在本机，不需要联网账户。

## 构建与启动

需要 macOS 14 或更新版本，以及支持 Swift 6 的 Xcode Command Line Tools。
首次运行前可在终端通过 `xcode-select --install` 安装 Apple 开发工具。
REBOUND 源码已固定版本并包含在仓库中，构建不下载第三方依赖。

在项目根目录执行：

```sh
./script/build_and_run.sh
```

```sh
./script/build_and_run.sh --verify     # 构建、启动并确认进程
./script/build_and_run.sh --build-only # 只生成应用包
./script/build_and_run.sh --debug      # 使用 LLDB 启动调试
./script/build_and_run.sh --logs       # 启动并查看应用日志
./script/build_and_run.sh --telemetry  # 启动并筛选应用日志子系统
```

`build_and_run.sh` 默认生成适合调试的构建。性能测试可使用：

```sh
TRISOLARIS_BUILD_CONFIGURATION=release ./script/build_and_run.sh
```

### 在本机 Xcode 中编译

1. 安装完整 Xcode，在终端用 `xcodebuild -version` 确认当前开发工具可用。
2. 在 Xcode 中选择“文件 → 打开”，选中本目录的 `Package.swift`。这是 Swift Package，
   不需要另外生成 `.xcodeproj`。
3. 在工具栏选择 `TrisolarisApp` scheme 和“我的 Mac”，用“产品 → 构建”（`⌘B`）
   编译，或用“产品 → 运行”（`⌘R`）启动；用“产品 → 测试”（`⌘U`）运行单元测试。

Xcode 直接构建的是 Swift Package 可执行目标。若需要包含图标、许可和 `Info.plist`
的完整 `.app`，请使用上面的打包脚本。Apple 的
[Swift Package 与 Xcode 文档](https://developer.apple.com/documentation/xcode/creating-a-standalone-swift-package-with-xcode)
介绍了 Xcode 对独立软件包的支持。
也可以在终端使用当前 Xcode 工具链编译同一目标：

```sh
xcrun swift build -c release --product TrisolarisApp
```

### 生成本地 Release 附件

```sh
./script/release.sh
(cd dist && shasum -a 256 -c TrisolarisCalendar-v1.0.0-SHA256SUMS.txt)
```

独立的 `release.sh` 先运行单元测试和 100 年数值检查，再调用原有打包脚本进行
Release 构建，检查 App 的版本、arm64 架构和代码签名，最后生成两个附件：
`dist/TrisolarisCalendar-v1.0.0-macos-arm64.dmg`（含高清安装背景、App 与“应用程序”快捷入口）及
`dist/TrisolarisCalendar-v1.0.0-source.zip`（含源码、资源、测试、脚本与许可）。
校验值写入同目录的 `TrisolarisCalendar-v1.0.0-SHA256SUMS.txt`。
脚本会请 Finder 设置 DMG 的窗口布局；若 macOS 提示自动化授权，允许终端控制
Finder 后再运行。打开 DMG 后，把左侧 App 拖到右侧“应用程序”文件夹即可安装。


## 使用

1. 在工具栏选择层级三星、等质量八字或随机初始轨道。随机轨道保留参数并使用
   可记录的随机种子；它不保证系统长期束缚或行星存活。
2. 在右侧检查器编辑恒星和行星。支持质量、半径、光度、三维位置与速度，也可将
   二体轨道要素转换成初始状态。开始模拟后，每个天体受到全系统引力作用。
3. 选择参考恒星与适宜参考距离，设置历法年数、气候阈值、积分容差和环境采样数。
   默认计算一万个标准年。没有行星时可以观测三星，添加行星后可生成历法。
4. 使用观测页播放、暂停、单步、选择和跟随天体，或切换俯视。天体增强显示只影响
   画面，物理半径和碰撞判断使用真实配置值。
5. 生成万年历后，在历法页按年份或纪元筛选，并回放指定年份；分析页显示温度、
   辐照、守恒误差和事件。可以运行严格精度复算比较年度标签。
6. 使用“文件”菜单保存 `.trisolaris` 项目、另存为、重新打开，或导出 CSV/JSON。
   计算可以暂停再继续；保存文件包含可用的计算检查点。取消或碰撞发生后，已经
   完成的年份仍可查看。场景也可导出 PNG。

主要快捷键：`⌘O` 打开，`⌘S` 保存，`⇧⌘S` 另存为，`⌘G` 生成万年历，
`⌘R` 重置初始状态，`⌘.` 单步。每个项目窗口持有独立配置和计算实例。

## 科学模型与精度

### 引力

三颗恒星与一颗有质量行星构成完整牛顿四体模型；行星对恒星产生反作用。
内部单位为 AU、太阳质量和日，位置、速度及积分均使用双精度。
内核固定为 REBOUND 4.4.11，提交
`1509463f3e5802807e69dfd7db23ff4309c56909`。IAS15 自适应调整引力积分步长，
默认 `epsilon = 1e-9`，严格复算为 `1e-11`，编译禁用 fast-math 和浮点运算收缩。

有限半径天体发生碰撞时停止该模型，不自动合并。碰撞检测使用积分步内线性轨迹
检测；它比只检查画面帧更可靠，但仍是对一步内路径的数值近似。
能量、角动量及质心诊断用于发现数值异常。混沌系统的长期轨迹会放大初值和舍入
差异，良好的守恒量不等于任意长时间的轨迹都可作确定性预测。

层级三星是长期稳定候选，稳定结论以实际积分为准。八字轨道使用公开舍入初值；
已知周期性质针对理想等质量三星，改变质量、加入有质量行星或发生扰动后应重新
检验。八字初值来源见 [Richard Montgomery 的 N-body 页面](https://people.ucsc.edu/~rmont/NbdyB.html)。

### 标准年

一次计算开始时，按参考恒星与参考距离冻结标准年长度：

```text
T = 2π × sqrt(a_reference³ / [G × (M_reference + M_planet)])
```

“按地球参考辐照计算距离”将距离设为 `sqrt(L_star / L_sun)` AU。
这是该恒星单独供光时的参考尺度，实际环境同时合并三颗恒星的辐照。
第 n 年覆盖 `[(n−1)T, nT)`，不使用地球公历的月份或闰年；行星换星或逃逸后仍
使用同一个标准年连续计时。

### 温度与纪元

总辐照为 `Σ L_i / (4πr_i²)`。辐射平衡温度考虑反照率和球面平均受光，再加上
固定温室增温，并通过一阶热响应体现热惯性。显示的是全球平均“模型温度”，
不代表完整气候预测。

默认规则均可在检查器修改：

| 设置 | 默认值 |
|---|---|
| 适宜模型温度 | 0～50 ℃ |
| 适宜总辐照 | 地球参考辐照的 0.7～1.5 倍 |
| 辐照波动上限 | 时间加权变异系数 20% |
| 辐照统计窗口 | 0.1 标准年 |
| 最短稳定持续时间 | 0.1 标准年 |
| 反照率 / 温室增温 | 0.3 / 33 K |
| 热响应时间 | 30 日 |
| 每标准年环境采样 | 512 次，严格复算 1024 次 |

温度、辐照及波动同时合格、且持续达到最短时长的区间才确认为恒纪元。
整个标准年被已确认的恒纪元覆盖才标记为“恒纪元年”；包含乱纪元区间的年份
标为“乱纪元年”，同时保留稳定时长占比。未完整计算的年度应视作待确认。
跨年不重置气候历史或稳定区间，末尾会继续计算必要的确认区间。

引力积分和环境采样是两种不同精度控制：降低 IAS15 容差不能代替加密气候采样。
临界阈值附近的纪元标签应结合更严格复算和采样收敛结果判断。
首版模型不包含完整大气、昼夜、季节、食与遮掩、潮汐、恒星演化或相对论效应。

## 验证与复现

```sh
swift test
swift run -c release ScienceCheck 100
```

单元测试检查场景约束和历法检查点恢复；`ScienceCheck` 运行层级三星基准并输出
完成年度数和守恒误差。年数可通过命令行参数调整，不带参数时默认为 100。
项目记录初值、规则、随机种子、内核版本及可恢复的积分状态。完整检查点在相同
内核版本和架构下用于继续积分；不同版本或机器架构不承诺逐位一致。
显示轨迹是有界抽样，历法统计使用更密的环境采样；显示抽样不等同于全部积分步。

## 工程与许可

- `SimulationCore`：物理、气候、历法和检查点。
- `CRebound`：固定上游源码与薄 C 桥接。
- `TrisolarisApp`：原生界面、Metal 场景、项目管理与后台任务。
- `ScienceCheck`：可独立运行的数值验证入口。

原创源代码和资源为 GPL-3.0-or-later，REBOUND 同样采用 GPL-3.0-or-later。
完整条款见 [LICENSE](LICENSE)，第三方版本、来源和算法引用见
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
