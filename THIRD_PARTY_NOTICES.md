# 第三方软件声明

## REBOUND 4.4.11

本项目使用 REBOUND 引力 N 体积分器，其源码位于 `Vendor/REBOUND/src`。

- 项目：https://github.com/hannorein/rebound
- 固定提交：`1509463f3e5802807e69dfd7db23ff4309c56909`
- 版本：4.4.11
- 作者与版权：Hanno Rein、Shangfei Liu 及 REBOUND contributors；各源文件保留原始声明。
- 许可：GNU General Public License version 3，或自行选择任何后续版本。
- 完整许可：`Vendor/REBOUND/LICENSE`，亦见项目根目录 `LICENSE`。
- 本地改动：上游 `src/` 未改动；增加了供 SwiftPM 使用的公开头文件及碰撞停止回调安装函数。

SwiftPM 构建保留 IAS15、自适应步长、完整双精度运算以及 Simulationarchive
存档功能。MPI、OpenMP、OpenGL、AVX512 和网络服务器均未启用。禁用 fast-math
和浮点运算收缩。

算法引用：

- Rein, H. & Spiegel, D. S. (2015). IAS15: a fast, adaptive, high-order integrator
  for gravitational dynamics, accurate to machine precision over a billion orbits.
  MNRAS 446, 1424–1437. https://doi.org/10.1093/mnras/stu2164
- Rein, H. & Liu, S.-F. (2012). REBOUND: an open-source multi-purpose N-body code
  for collisional dynamics. A&A 537, A128. https://doi.org/10.1051/0004-6361/201118085

## 本应用

Copyright © 2026 三体人的万年历 contributors.

应用原创源码和资源采用 GPL-3.0-or-later。您可以依许可运行、修改及再分发；
软件按原样提供，不含适销性或特定用途适用性保证。分发构建产物时，应同时提供
相应源码及许可文件。Apple 系统框架由操作系统提供，不包含在本源码分发中。


## 半人马座 α 公开观测资料

本应用离线收录 CDS/VizieR 的公开数值表，原始列说明、作者引文与来源记录保存在
`Sources/SimulationCore/Resources/ObservedSystems/`，并随应用资源包分发。

- Akeson et al. (2021), AJ 162, 14，表 6、7，CDS J/AJ/162/14；https://doi.org/10.3847/1538-3881/abfaff
- Suárez Mascareño et al. (2020), A&A 639, A77，表 A.1，CDS J/A+A/639/A77；https://doi.org/10.1051/0004-6361/202037745
- 模型根数、状态及辐射参数采用 Kervella et al. (2016/2017) 和 Ribas et al. (2016)，完整引文及具体表号见 `alpha-centauri-provenance.md`。

资料及原文说明归原作者和 CDS；应用代码的 GPL 声明不改写第三方资料的归属。
使用这些数值开展研究应引用原论文和 CDS/VizieR。原数值表未替换为推算或插值。
