# [SPEC-04] M1：双架构构建、链接与最低系统验证

## Problem Statement

上游现成 CLI 发行只覆盖 Apple Silicon，客户端必须证明 Swift 和 Rust 在两种架构及最低支持目标上能正确链接运行。

## Solution

建立项目范围的可复现构建入口，构建 arm64/x86_64 的真实桥接和最小原生应用，核对依赖切片并分别记录编译、运行与最低系统验证。

## User Stories

1. As an Intel Mac user, I want a native client, so that I do not depend on an unsupported engine slice.
2. As an Apple Silicon user, I want a native baseline-compatible build, so that newer build-machine instructions do not exclude my Mac.
3. As a developer, I want reproducible build commands, so that local and isolated CI checks use the same procedure.
4. As a developer, I want architecture-matched Swift and Rust outputs, so that linking failures are found early.
5. As a tester, I want all embedded components inspected, so that a universal main executable does not hide a single-architecture dependency.
6. As a macOS 13 user, I want actual compatibility verification, so that an SDK build is not mistaken for runtime support.
7. As a maintainer, I want architecture-specific fixture results, so that scalar and optimized engine paths are both checked.
8. As a developer, I want project-local caches, so that my host toolchain remains unchanged.
9. As a tester, I want a minimal installable app bundle, so that launch behavior can be checked before full UI work.
10. As a tester, I want cross-compilation and native execution distinguished, so that test reports are accurate.
11. As a maintainer, I want compiler and upstream-version records, so that failed upgrades can be reproduced.
12. As a tester, I want missing Intel hardware recorded, so that unavailable evidence cannot silently pass a gate.

## Implementation Decisions

- 构建 Swift 与 Rust 的 arm64/x86_64 目标，分别链接对应库并验证；最终安装包可合并 Universal 产物。
- 覆盖上游 target-cpu=native 配置，使用各架构基线兼容参数和一致 deployment target。
- 新增项目范围构建入口、依赖/工具链记录和最小应用打包能力；不更换用户全局 runtime 或 rustup 默认值。
- 额外编译目标仅在隔离构建环境准备；验证环境资源不足不通过全局安装绕开约定。
- macOS 13+ 与两芯片同一功能范围为目标；跨编译、Rosetta、Intel 实机和最低系统实测分开记载。

## Testing Decisions

- 通过统一服务跑相同真实 fixture，比较两架构公开查询与状态行为，不断言 SIMD 或内部结构。
- 对主程序和内置组件执行架构、链接依赖与启动冒烟核验。
- 用最低目标系统与 Intel 实机验证可用行为；不具备环境时列为未验证。
- 参考上游非 aarch64 的替代路径和发行 CPU 基线选择，不能把其 Apple Silicon 工作流当双架构证据。
- 交付可复现构建入口、最小原生应用及明确的编译/运行/最低系统报告。

## Out of Scope

- 完整 alpha UI、公众签名公证发行、全局目标安装或系统配置修改。

## Further Notes

- 总规格：Part of #1。
- 阻塞依赖：Blocked by: #2。
- Spec ID：SPEC-04。
- 阶段：M1。
- 依据已确认选择：Q6、Q19、Q23。
- 前置规格：SPEC-01。
- 本规格产物供生命周期与权限验证使用；正式 DMG 和 CI 发行另有规格。

