# [SPEC-12] v0.1：端到端验收、用户文档与已知限制

## Problem Statement

分散完成模块不能证明普通用户能安装并完成一次搜索流程。没有清楚文档和限制说明，会让覆盖、大小精度或内容索引被误解。

## Solution

按真实开发安装包跑 v0.1 的用户流程与回归矩阵，整理入门、权限、搜索、诊断、更新和已知限制，明确 alpha 与公众发行的不同状态。

## User Stories

1. As a new user, I want installation instructions, so that I can start without developer tools.
2. As a new user, I want permission instructions, so that I can understand restricted coverage.
3. As a user, I want examples of name modes and filters, so that I can find files effectively.
4. As a user, I want global sorting explained, so that I understand ongoing and final result states.
5. As a user, I want indexed and actual size differences explained, so that large-file precision is clear.
6. As a user, I want path and file-action guidance, so that found files can be used immediately.
7. As a user, I want window-close and quit behavior explained, so that background activity is predictable.
8. As a user, I want default text-index activity documented, so that alpha scope is not confused with indexing internals.
9. As a user, I want unsupported volumes and document content identified, so that I do not rely on absent features.
10. As a user, I want local-data and diagnostic-export instructions, so that support actions remain controlled.
11. As a user, I want manual-update instructions, so that I can install a newer client.
12. As a tester, I want a complete behavior matrix, so that module success is checked as an end-to-end experience.
13. As an Intel user, I want my validation status recorded, so that missing hardware evidence is visible.
14. As a maintainer, I want performance measurements and version records, so that release claims have evidence.
15. As a maintainer, I want open defects and blocked gates listed, so that alpha completion cannot hide known failures.
16. As a public user, I want unsigned alpha and verified public release distinguished, so that I know which package I downloaded.

## Implementation Decisions

- 汇总现有客户端、安装包和上游升级能力，不添加新功能；以用户旅程为验收单位。
- 文档覆盖安装、授权、模式/筛选、排序/分页、检查器、路径/动作、窗口、诊断、更新、默认索引资源及卸载/数据说明。
- 支持矩阵记录 macOS 13+、两芯片、权限状态、冷/热和数据规模，区分未验证与失败。
- 已知限制包含外接/网络卷、文本准入、索引大小精度、iCloud 本地缺失、完整排序成本和引擎版本。
- alpha 可为明确标记的开发包；公众签名公证验收由独立发行规格负责，alpha 报告不能代替公众发行证据。
- 更新 PR、依赖版本、许可、资源报告与临时补丁记录可追溯，用户文档跟随真实实现修订。

## Testing Decisions

- 以真实安装产物完成安装→授权/跳过→搜索/筛选→排序/分页→选择/预览→Finder 导航→关闭/重开→退出→手动更新入口的原生端到端冒烟。
- 功能回归复用主服务接缝，避免对内部模块重复造镜像测试；系统交互以真实动作证据补充。
- 覆盖特殊名称、长路径、同名、隐藏项、应用包、链接、删除、无结果、错误和过期响应。
- 核对每个公开功能与说明一致，诊断无默认泄露，性能数字来自报告而非上游宣传；目前无客户端端到端先例。
- 验收输出逐项结果、问题列表、用户指南和已知限制；任何缺失 P0 或未通过 M1 核心门禁都不能标 alpha 全部完成。

## Out of Scope

- 新增保存查询、全文文档解析、P2 特性、替公众发行准备或修改凭据、承诺未经测量的性能。

## Further Notes

- 总规格：Part of #1。
- 阻塞依赖：Blocked by: #6、#7、#8、#9、#10、#11。
- Spec ID：SPEC-12。
- 阶段：M2 / alpha 完整验收。
- 依据已确认选择：Q1、Q2、Q3、Q4、Q5、Q6、Q7、Q8、Q9、Q10、Q11、Q12、Q13、Q14、Q15、Q16、Q17、Q18、Q19、Q20、Q21、Q22、Q23。
- 前置规格：SPEC-05、SPEC-06、SPEC-07、SPEC-08、SPEC-09、SPEC-11。
- 公众正式发行依赖此 alpha 验收，再执行独立签名公证门禁。

