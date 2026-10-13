# 双架构构建与 GitHub Releases 方案

状态：发布设计，当前尚无 workflow 或安装包。目标仓库为 [wynnok/fsearch-desktop](https://github.com/wynnok/fsearch-desktop)，下载入口为其 [Releases](https://github.com/wynnok/fsearch-desktop/releases)。

## 目标产物

推荐一个 Universal 2 应用，主应用及 Rust 引擎都包含 arm64 和 x86_64，两类 Mac 下载同一个 DMG。可另提供架构独立包作为诊断产物，但不让普通用户必须分辨 CPU。

版本产物建议：`Fsearch-Desktop-<version>-universal.dmg`、`SHA256SUMS`、发布说明及内置第三方许可证。DMG 包含应用、Applications 快捷入口和简短安装指引；不修改系统设置或执行 CLI install。

用户已确认最低支持目标为 macOS 13，两种芯片保持同一功能范围；正式承诺须通过 M1 的 SwiftUI/AppKit 和 Rust API 兼容性验证，它不是当前已经测试的支持版本。

Universal 构建的必要性与验证方法参考 [Apple：Building a universal macOS binary](https://developer.apple.com/documentation/apple-silicon/building-a-universal-macos-binary)。应用包含两个切片不表示内置依赖也自动包含两个切片。

## 自动化触发

| 触发 | 应做什么 | 产物位置 |
| --- | --- | --- |
| push 到工作分支 / PR | 测试、双架构编译、开发包打包 | Actions artifacts，用于评审 |
| 版本 tag `v*` | 同样检查，打包、签名、公证、安装冒烟通过后发布 | GitHub Releases |
| workflow_dispatch | 构建指定 commit/tag，用于排障/重发明确版本 | artifacts 或指定 release |

用户已确认普通 push 自动生成 Actions 可安装开发包，版本 tag 自动构建并发布到 Releases；上游升级 PR 检查通过后由维护者合并。普通提交不覆盖 stable Release，首版不建设 nightly 发布通道。

工作流触发规则以 [GitHub Actions workflow 文档](https://docs.github.com/en/actions/concepts/workflows-and-actions/workflows) 为依据；实现时按当前受支持版本核查具体 action 与 runner，固定可审计版本，不照搬上游 workflow 的 Apple Silicon 单架构方案。

## 构建步骤

1. checkout 精确 commit，校验当前已批准的上游依赖 pin 和 Cargo lockfile；初始研究基线为 `88e63fdf850cf7749deae8198b187accd21f8ba5`，后续按兼容性门禁升级。版本号和引擎版本写入应用 About 及 build manifest。
2. 项目内配置 `CARGO_HOME`、`CARGO_TARGET_DIR`、Swift module cache 和 DerivedData；开发与 CI 使用同一脚本，不要求本机全局安装额外目标或变更 rustup 默认值。CI 缺少 target 时只在临时 runner 环境准备，隔离本机环境。
3. 分别构建 Rust `aarch64-apple-darwin` 和 `x86_64-apple-darwin`。覆盖上游 aarch64 `target-cpu=native`，使用面向 Apple Silicon 基线的参数；Intel 也不得使用构建机器特有指令。锁定最低 deployment target。
4. 分别构建 Swift arm64/x86_64，并将各自链接到对应架构引擎；最后合并应用可执行文件。如果使用 staticlib 在两次 Swift 链接中分别提供对应库；如果最终改用 helper，则 helper 同样必须合并双切片。
5. 原生架构运行自动化 fixture，核验 `file`、`lipo -archs` 和依赖。不把编译产物经过 Rosetta 能启动当成 Intel 实机兼容结论。
6. 组装完整 `.app`，内置 Fsearch MIT 及第三方许可证。先签名嵌套可执行组件，再签主应用；签名完成后不再改变内容。
7. 打包 DMG，上传 Apple 公证、等待 Accepted、staple，再执行 `codesign --verify --strict`、`spctl` 和安装冒烟。留存公证日志的状态，不记录密钥。
8. 为最终安装包生成 SHA-256；成功后上传对应 tag 的 Releases。任何架构/测试/公证失败都阻止正式发行。

本机当前只有 aarch64 Rust target；没有为研究安装 x86_64 target。M1 会在隔离构建环境和 Intel 验证环境补齐证据。

## 签名和凭据

用户已确认公开正式版以 Developer ID Application 签名、Hardened Runtime、Apple 公证及安装验证作为门禁；参考 [Apple 公证要求](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)。alpha 开发测试可产生明确标注的未公证包，不能把它标成已公证稳定版，也不教普通用户关闭 Gatekeeper 来代替发布工作。缺少签名条件时先完成开发验证，保留公众发行门禁。

正式发行需要 Apple Developer 身份和对应签名/公证凭据。实现时用 GitHub Secrets 保存证书、证书密码和公证 API 认证信息，仅通过变量名引用；临时 keychain 在 CI 作业结束清理，不向仓库提交证书、私钥或连接凭据。

如果签名凭据缺失，CI 可以完成测试和开发包生成，但不能声称已交付正式公证安装包。无需在当前文档阶段收集秘密值。

## 发布验收矩阵

| 场景 | 证据 |
| --- | --- |
| Intel / Apple Silicon | 两个 native slice、对应真实运行、设备和 OS 记录 |
| 支持的最低 OS / 当前 OS | 在支持矩阵中记录安装与核心搜索，不仅 SDK 编译 |
| 干净系统安装 | DMG 打开、拖入 Applications、Gatekeeper、首次启动和卸载 |
| 授权前/后 |受保护位置搜索、权限说明、重新检查及实际引擎进程行为 |
| 已有 CLI / 索引 | 客户端独立目录，不破坏 CLI 数据和进程；客户端重复实例及其索引升级恢复 |
| 索引初建/更新/历史回放 | 不漏改名删除，初建状态可解释；不伪造精确进度 |
| 大量匹配/全局排序 | 大于 JSON 分页上限的数据，跨页顺序/总数/峰值 RSS |
| 内容搜索 | 文本范围、cursor、complete 和预算中断正确，不宣称 PDF 全文 |

## 升级、回退和维护

持续跟进 Fsearch 上游是已确认要求；每天检查正式版本，发现更新后自动生成升级 PR，验证 API、查询、索引格式、资源使用、最低 OS 和两种架构。检查通过后由维护者合并，以版本 tag 触发发行，每次客户端发行固定引擎版本。上游跟进与用户安装客户端新版本是两个步骤，前者不能自动等同于后者。必要的临时补丁必须有测试、来源和移除条件；每次升级评估删除。当前没有配置监控或自动升级工作流。

2026-10-13 只读核查：上游已有 `v0.2.0`、`v0.2.1` 两个正式 tag/Release，`main` 当时与研究基线 `88e63fdf850cf7749deae8198b187accd21f8ba5` 相同（[上游 Releases](https://github.com/noahdunnagan/fsearch/releases)、[基线提交](https://github.com/noahdunnagan/fsearch/commit/88e63fdf850cf7749deae8198b187accd21f8ba5)）。因此用户确认以正式发行版作为升级候选来源；这不构成上游 API 或索引格式兼容承诺。

首版提供检查更新入口与下载链接，用户从 Releases 手动下载安装包。自动更新框架在后续版本单独评估，不提前加入额外第三方依赖。引擎升级随客户端版本交付，不在运行时热替换引擎。

每次发布记录客户端版本、上游 commit、工具链、支持 OS/架构、已知限制和哈希。错误版本标明问题并发修复，不重写公开 tag 或悄悄替换既有安装包。回退前检查引擎索引格式兼容；不兼容时说明需要按上游机制重建，保留用户文件。

真实 workflow、DMG 和线上 Releases 只有在实现并运行验证后才能标记完成。本文件不能作为其已经存在的证明。

