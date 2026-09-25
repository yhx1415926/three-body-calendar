# REBOUND source provenance

- Upstream: https://github.com/hannorein/rebound
- Release: 4.4.11
- Commit: `1509463f3e5802807e69dfd7db23ff4309c56909`
- Archive: https://codeload.github.com/hannorein/rebound/tar.gz/1509463f3e5802807e69dfd7db23ff4309c56909
- License: GNU GPL version 3 or, at your option, any later version.

`src/` and `LICENSE` are copied verbatim from this upstream commit. The app adds
`include/CRebound.h` and `bridge.c` to expose the native C API to SwiftPM and to
install the upstream halt-on-collision callback.

SwiftPM compiles the double-precision C99 core and archive support. MPI, OpenMP,
OpenGL, AVX512, and the network server are not enabled. The display/server source
files retain their upstream non-OpenGL and non-server stubs. No fast-math is used;
floating-point contraction is explicitly disabled.
