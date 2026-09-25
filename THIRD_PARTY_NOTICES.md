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
