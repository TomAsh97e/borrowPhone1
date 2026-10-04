# Third-party code

## llama.cpp

- Source: https://github.com/ggml-org/llama.cpp, commit `836d57176dc699a726c55418e4f96b8ca628e1bf` (2026-10-03, tag `b11381`).
- License: MIT (`llama.cpp/LICENSE`).
- Kept: `CMakeLists.txt`, `cmake/`, `include/`, `src/`, `ggml/` with only the CPU backend.
- Removed: all GPU/NPU backends under `ggml/src/` (CUDA, Vulkan, Metal, SYCL, OpenCL, …), `vendor/`, tools, examples, tests, docs.

Local changes:

1. `ggml/src/ggml-cpu/ggml-cpu.c`: the Linux thread-affinity branch is `#elif defined(__linux__) && !defined(__OHOS__)`, because that branch does not compile against the OpenHarmony musl sysroot.
2. `CMakeLists.txt`: `add_subdirectory(vendor)` only runs when `vendor/` exists (it is used only by tools that are not built).
