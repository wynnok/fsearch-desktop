# Wave 4：T25 / T26 / T28 验收与门禁

对应 [T25/#39](https://github.com/wynnok/fsearch-desktop/issues/39)、[T26/#40](https://github.com/wynnok/fsearch-desktop/issues/40)、[T28/#42](https://github.com/wynnok/fsearch-desktop/issues/42)。起点 `5763dcaee4651a5bb370b89ba7edc62c3de43d90`，2026-10-13 执行。未修改或关闭父 Spec，不以本文解除外部门禁。

## 本次结果

T25/T26 补齐受控应用旅程、实际开发 DMG 安装验证和[用户指南](../product/user-guide.md)；T28 完成[签名、公证与最终验证入口](T28.md)及失败门禁测试，真实签名条件缺失。三票不能据此宣称完整 alpha、真实用户磁盘覆盖或公众发行完成。

环境：Apple Silicon arm64、macOS 27.0.1、Swift 6.4、Rust 1.99.0。客户端 0.1.0，上游 `0.2.1 / 88e63fdf850cf7749deae8198b187accd21f8ba5`。两架构编译/链接通过，本次运行是原生 arm64；Intel 和 macOS 13 实机未验证。

本次包从上述起点的 dirty 工作区构建，包含 Wave 4 修改；包名的提交号仅是基点，不能表述为该 clean commit 的可复现产物。实际产物由 manifest、构建记录和最终哈希追溯：

- DMG：`.build/dev-dmg/output/Fsearch-Desktop-0.1.0-dev-5763dcaee465-universal.dmg`
- SHA-256：`fcd03477a43580f232c4b2aeecd21513b7bfe1a8f29d28525283be692b1ce955`
- 状态：development-unnotarized，ad-hoc 签名，没有 Developer ID、公证或 stable 发布。
- 安装报告：`.build/dev-dmg/verification/verification-report.txt`；本轮总日志 `.build/wave4-installed-smoke.log`。
- 旅程成品：`.build/dev-dmg/verification/journeys/` 中的 search-journey.json、file-journey.json、file-actions.json、diagnostics.json 和对应截图。它们是安装后实际进程生成并复读验证的成品。

## T25：搜索旅程

| 场景 | 结果与证据 |
| --- | --- |
| 空输入、标点、空格、引号、换行、中文/emoji、NFC/NFD、无匹配、模式 | 实际安装应用既有原生样本套件通过；sample 模式，不代表真实磁盘覆盖 |
| 限定范围、隐藏项、仅筛选、清除范围/筛选、无效条件修正 | 新增 5 项 search-journey.json 全 true；实际应用模型发起查询，真实服务与原生结果视图一起运行 |
| 名称/索引大小/修改时间升降序、跨页、部分结果、变化刷新 | 安装后原生套件通过；大小与时间实际结果按已知 fixture 核对；部分结果不冒充全局完整排序 |
| 长查询响应与晚返回 | 既有 25,001 个受控文件旅程通过，确认输入可变化、新查询不被旧结果覆盖；不把该单次样本当个人磁盘 p50/p95 承诺 |
| 错误与受限覆盖说明 | 实际样本应用显示失败及覆盖未验证说明；权限模型/公开服务回归通过。真实 TCC 拒绝/授权前后旅程仍未验证 |
| 用户操作说明 | 指南覆盖模式、空态、范围只筛现有覆盖、索引大小精度、分页快照、默认真实 Engine 文本索引与资源报告 |

## T26：文件与本地数据旅程

| 场景 | 结果与证据 |
| --- | --- |
| 回车/双击、复制路径、Finder 请求、空格 Quick Look、切换预览、Escape、多选与焦点/滚动 | 安装应用既有 file-actions.json 12 项全 true；Finder 接收到指定目标请求，Finder 窗口的可见选中状态未单独观察 |
| 同名文件与长路径 | 新 fixture 出现在同一真实查询结果，原生表格选择长路径目标；外部检查器接口核对独立大小与路径 |
| 链接/应用包/多选/删除/不可读 | 新 file-journey.json 13 项全 true；核对链接本身属性、断链失败、应用包不递归算大小、多选不虚构属性、删除后刷新移除结果；不可读通过项目样本 chmod 000 验证，不代替真实 TCC |
| 晚返回检查器 | FileInspectorTests 受控异步 Reader 回归通过，旧详情不覆盖新选择；未在人为放慢的实际磁盘上另做原生晚详情旅程 |
| 关窗重开与偏好 | 安装应用保留进程内输入/选择；LocalPreferencesTests 验证新模型恢复偏好并排除查询/路径/范围/筛选。真正退出重启的偏好人工旅程仍未验证 |
| 诊断与更新 | 安装进程产出并检查脱敏 diagnostics.json；真实更新 sheet 打开/关闭和版本入口通过；ManualUpdateTests 的新版/无新版/无 Release/网络失败响应通过 |
| 导出保存面板/下载 | NSSavePanel 完整确认/取消/权限失败交互及实际 Releases 下载更新未在本轮人工操作，保持未验证。没有自动上传或替换程序 |
| 数据说明与清理 | 指南区分用户偏好、项目缓存/验证索引、客户端与 CLI 数据；任务只清理自己创建的样本/安装工作区，不清除用户索引 |

属性/范围筛选通过同一应用模型驱动验证，未声称逐个点击 NSOpenPanel 和日期控件的完整人工表单旅程。

## T28：签名外部门禁

用户明确暂时没有 Developer ID 身份和 notarytool profile。本次没有收集或创建凭据，也没有向 Apple 上传。入口与 7 个受控缺失/失败场景通过，详情见 [T28](T28.md)。真实 Accepted、staple、签名/Gatekeeper 成功链路及干净系统安装仍未验证；模拟工具输出不算 Apple 或设备证据。

## 执行与修复记录

```sh
bash scripts/dev.sh test --filter 'SigningValidationTests|FileInspectorTests|ManualUpdateTests|SearchFilterTests'
bash scripts/dev.sh check
bash scripts/dev.sh test
FSEARCH_DEV_RUST_VERSION=1.99.0 bash scripts/package-dev-dmg.sh
bash scripts/verify-dev-dmg.sh --dmg .build/dev-dmg/output/Fsearch-Desktop-0.1.0-dev-5763dcaee465-universal.dmg
```

最终 Rust check、Swift 构建、完整 XCTest（服务 49 + 应用 19 = 68 项，0 失败）和实际 DMG 验证均通过。shell 语法与 diff whitespace 检查通过。没有为静态指南创建镜像测试。

首次补充文件冒烟因目录 URL 尾斜杠差异造成断言误判，改为实际路径比较后通过。首次 Release 安装冒烟在更新 sheet 尚未关闭时请求退出而卡住；结束本次临时进程后，补实际 sheet 打开/关闭等待、捕获 sheet 本身及共用 180 秒超时/进程清理，再构建和安装验证通过。失败运行没有成功报告，本表使用后一次通过的哈希/报告。

Standards 审查发现 TERM 后无界 wait 可能绕过冒烟超时；补拒绝 TERM 的真实受控进程回归，先失败，再改为等待最多 3 秒后 KILL 本次 PID，回归通过。测试的空数组清理兼容性也修正，失败测试遗留的本次临时目录已移除。

完整 alpha 仍受默认样本模式、真实 TCC/覆盖、Intel/macOS 13、真实 GitHub Actions、升级 PR 链路和签名条件等门禁限制；缺少的实机/权限/发行证据保持未验证，不把代码或本机样本通过改写成全部 Ticket 验收完成。
