# [SPEC-09] DevOps：可安装开发 DMG 与持续集成

## Problem Statement

客户端功能需要通过真实安装包验收，普通提交若没有可复现的双架构开发产物，测试者无法验证安装、原生启动和更新行为。

## Solution

使用项目构建入口在 push/PR 上执行测试、双架构构建和应用打包，生成明确标注的可安装开发 DMG、版本信息和哈希供 Actions 下载。

## User Stories

1. As a developer, I want push builds, so that ordinary changes produce testable application packages.
2. As a reviewer, I want PR checks, so that build regressions are caught before merge.
3. As a tester, I want an installable DMG, so that I can exercise the real distribution rather than a build directory.
4. As an Intel user, I want an installer containing my native slice, so that I can test the same client.
5. As an Apple Silicon user, I want a native package, so that I can verify the optimized engine path.
6. As a tester, I want a simple Applications installation entry, so that the package follows familiar macOS setup.
7. As a tester, I want development status clearly marked, so that an unnotarized package is not confused with a public release.
8. As a maintainer, I want package hashes, so that downloaded artifacts can be identified.
9. As a maintainer, I want client and engine versions recorded, so that each package is traceable.
10. As a maintainer, I want upstream licenses included, so that redistributed engine code is properly credited.
11. As a reviewer, I want failed checks to stop successful packaging claims, so that a broken build is not presented as ready.
12. As a developer, I want one build procedure across local and CI environments, so that failures are reproducible.
13. As a user, I want installation to leave system settings alone, so that the app does not install unrelated tools.

## Implementation Decisions

- 基于已验证的构建入口组装完整原生应用，Swift 与内置引擎均含所需架构；推荐一个 Universal 开发安装包。
- 普通 push/PR 测试并输出 Actions 开发产物，不覆盖 stable Release；开发包可未公证但须明确标注。
- DMG 包含应用、熟悉的安装入口、简短指引和第三方许可；不得执行 CLI install 或改变系统隐私设置。
- 版本、上游 commit、工具链和 SHA-256 随最终产物可追溯；哈希基于实际打包输出。
- CI 使用项目范围缓存与受支持的隔离构建环境，固定可审计工具版本；不在工作站全局准备目标。
- 失败阻止成功产物标记，开发与公众发行流程分开但复用构建能力。

## Testing Decisions

- 复用主接缝功能回归，额外对最终应用及 DMG 做架构、依赖、许可、版本与哈希检查。
- 在专用环境从 DMG 安装、启动、名称搜索、路径动作、退出和更新测试，而非只验证编译目录。
- 使用受控失败验证构建/测试失败不会发布成功开发包；不测试工作流 YAML 细节的实现镜像。
- 参考上游 tag 构建思路，但其单架构 CLI 包不作为客户端安装验收先例。
- 验收：可复现的一次真实 CI 运行、可下载安装产物和各架构检查证据；未有 Intel 实机证据仍明确未验证。

## Out of Scope

- 公众正式签名公证 Release、每次 push 发 stable、nightly 通道、自动下载安装。

## Further Notes

- 总规格：Part of #1。
- 阻塞依赖：Blocked by: #4、#6、#7、#8、#9。
- Spec ID：SPEC-09。
- 阶段：M2 / v0.1。
- 依据已确认选择：Q6、Q18、Q19。
- 前置规格：SPEC-04、SPEC-05、SPEC-06、SPEC-07、SPEC-08。
- 可以交付未公证 alpha 开发包；公众发行另有严格门禁。

