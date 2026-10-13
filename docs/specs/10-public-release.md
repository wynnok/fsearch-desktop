# [SPEC-10] Release：签名公证、版本 tag 与正式安装验收

## Problem Statement

面向普通用户的发行需要经过签名公证和真实安装检查。开发包不能被标成可信正式版，失败的公证也不能被忽略后直接上传 Releases。

## Solution

在已有构建与 alpha 验收基础上建立正式发行流程，以版本 tag 触发签名、公证、最终包验证和 GitHub Releases 发布。

## User Stories

1. As a public user, I want a Developer ID signed app, so that I can identify the distributor.
2. As a public user, I want notarization completed, so that I receive a verified distribution.
3. As a public user, I want a familiar DMG installation flow, so that I can install without command-line steps.
4. As a public user, I want both architectures supported, so that the release fits my Mac.
5. As a public user, I want release notes and known limitations, so that I understand what the version provides.
6. As a user, I want a trustworthy download entry, so that manual updating leads to the intended package.
7. As a maintainer, I want tag-based publishing, so that the public release has an explicit version boundary.
8. As a maintainer, I want signing credentials kept out of source and logs, so that release secrets are not exposed.
9. As a maintainer, I want public release blocked on failed verification, so that an invalid package is not distributed as stable.
10. As a maintainer, I want final hashes and version metadata, so that an installed package can be traced.
11. As a tester, I want clean-system launch checks, so that build-machine permissions do not hide installer problems.
12. As a user, I want previous releases left identifiable, so that regressions can be diagnosed and updates considered safely.
13. As a maintainer, I want missing signing conditions reported, so that development progress does not create a false public-release claim.

## Implementation Decisions

- 公开正式版以 Developer ID、Hardened Runtime、公证和安装验证作为门禁；签名嵌套组件后签主应用，完成后不更改应用内容。
- 版本 tag 触发构建、测试、签名、公证、staple、最终校验和 Releases 上传；任一失败阻止正式发行。
- 签名/公证凭据仅从安全的 CI 凭据配置取用，以变量名引用，临时签名环境结束清理；不提交证书或私钥。
- 发布最终 DMG、哈希、版本/引擎记录、许可、已知限制与发布说明。
- 用户手动下载更新；不热替换引擎，不重写公开 tag 或悄悄替换旧包。
- 缺少签名身份或专用环境时开发工作可继续，但本规格的公众发行门禁保持未通过。

## Testing Decisions

- 对实际签名、公证并 staple 的产物做 codesign/spctl 与安装冒烟，不以模拟成功返回替代真实公证证据。
- 验证干净系统的首次启动、授权前后、核心搜索、Finder 动作和退出，核对两架构与最低系统报告。
- 用受控缺凭据/构建失败/公证拒绝场景验证不发布正式版，不记录秘密值。
- 参考项目已通过的开发包安装与 alpha 验收；此前无正式客户端发行先例。
- 验收要求真实版本 tag、完整 CI 运行、可下载 Releases 资产、哈希和安装证据；代码有分支不等于签名门禁通过。

## Out of Scope

- 购买或代管开发者身份、关闭 Gatekeeper、自动修改系统信任设置、强推/重写历史、自动下载安装框架。

## Further Notes

- 总规格：Part of #1。
- 阻塞依赖：Blocked by: #10、#12。
- Spec ID：SPEC-10。
- 阶段：M4 / 公众发行门禁。
- 依据已确认选择：Q6、Q18、Q19、Q20。
- 前置规格：SPEC-09、SPEC-12。
- 签名身份与测试设备为外部前置条件，不能用 ready-for-agent 标签绕过。

