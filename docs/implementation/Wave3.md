# Wave 3：T11–T18 / T21 搜索、文件与本地数据切片

对应 [T11/#25](https://github.com/wynnok/fsearch-desktop/issues/25)、[T12/#26](https://github.com/wynnok/fsearch-desktop/issues/26)、[T13/#27](https://github.com/wynnok/fsearch-desktop/issues/27)、[T14/#28](https://github.com/wynnok/fsearch-desktop/issues/28)、[T15/#29](https://github.com/wynnok/fsearch-desktop/issues/29)、[T16/#30](https://github.com/wynnok/fsearch-desktop/issues/30)、[T17/#31](https://github.com/wynnok/fsearch-desktop/issues/31)、[T18/#32](https://github.com/wynnok/fsearch-desktop/issues/32)、[T21/#35](https://github.com/wynnok/fsearch-desktop/issues/35)。代码落在 `93f37fb`，随后由 T19/T20、Wave 4 与内容搜索工作续接。

这些票此前已实现但缺少实施报告；本文补齐复核记录，不修改或关闭父 Spec，也不以本文解除签名、Intel、macOS 13、真实 TCC 等外部门禁。

环境：Apple Silicon arm64、macOS 27.0.1、Swift 6.4、Rust 1.99.0。客户端 0.1.0，上游 `0.2.1 / 88e63fdf850cf7749deae8198b187accd21f8ba5`。

## 逐票证据

| Ticket | 结果与证据 |
| --- | --- |
| T11 搜索范围与隐藏项 | `SearchConfiguration` / `SearchState` 承载内置位置、个人目录与选定文件夹范围及隐藏项开关；`SearchConfigurationTests.testEmptyDefaultScopeAndHiddenSwitchDoNotEnumerateIndex`、`testInvalidConditionsRemainAvailableForCorrection` 覆盖空默认范围与隐藏项不触发全量查询。范围只过滤现有覆盖，不新建索引或取权限。真实外接/网络卷说明与真实覆盖仍未验证。 |
| T12 属性筛选 | `Sources/FsearchService/SearchFilters.swift` 把文件/目录、扩展名、索引大小与修改时间映射到上游语义；`SearchFiltersView` 提供逐项与全部清除。`SearchFilterTests` 覆盖组合、边界、无匹配与大小精度，服务层不冒充 UI 单页过滤。 |
| T13 自动刷新 | `SnapshotQueryController` 复用上游变更通知按当前查询与排序生成新快照，不混用旧页。`LiveRefreshTests` 覆盖连续变更、排序字段变化与晚返回刷新；`QueryResponsivenessTests` 覆盖旧结果不覆盖新查询。真实受控变更的原生连续交互仍以开发 DMG smoke 辅助核对。 |
| T14 权限引导 | `PermissionStatus` 区分名称就绪、内容后台工作、受限覆盖、无结果与失败，提供跳过与重新检查入口，不自动改系统权限。`PermissionStatusTests`、`PermissionCoverageTests` 覆盖跳过持久化与“受限但就绪”区别于内容工作与失败。真实 TCC/FDA 授权前后旅程仍未验证。 |
| T15 检查器 | `FileInspector` 用有界串行队列异步加载图标、类型、实际大小与创建/修改时间，选择路径与详情一致。`FileInspectorTests` 覆盖快速切换时旧详情不覆盖新选择；目录大小不冒充递归占用。 |
| T16 Finder 与打开 | `FileActions` 用系统 `NSWorkspace` 完成打开、Finder 显示与复制路径，`MainSearchWindow` 提供逐级路径导航。`NativeFileActionsSmoke` 核对实际目标与区分“打开文件夹/显示文件本身”；不新增移动、删除、重命名功能。 |
| T17 Quick Look | `FileActions` 驱动 `QLPreviewPanel` 数据源/委托，空格与 Escape、选择切换保持一致，不可访问/已删除给出说明。`NativeFileActionsSmoke` 核对空格预览目标与切换；预览格式不作为内容搜索能力宣称。 |
| T18 窗口生命周期 | `WindowLifecycle` 让红色按钮只关主窗口、`⌘Q` 才结束客户端，默认不安装登录任务。`WindowLifecycleTests.testCloseAndReopenRetainsWindowContentAndSelection` 覆盖关窗重开保留进程内输入与选择。与 M1 生命周期报告一致的实机再启动仍未验证。 |
| T21 手动更新 | `ManualUpdate` 展示客户端与固定上游版本，检查更新后打开可信 Releases 入口，无新版/网络失败诚实反馈且不阻塞搜索。`ManualUpdateTests` 覆盖新版、无新版、无 Release 与网络失败响应。 |

## 执行与验证

2026-10-13 复核执行：

```bash
bash scripts/dev.sh check
bash scripts/dev.sh test
```

结果：Rust check、Swift 编译与链接通过；完整 XCTest 在沙箱外为服务 56 项 + 应用 20 项 = 76 项、0 失败。`ContentSearchTests.testRealEngineLiteralContentJourneyInIndependentProcess` 内部调用 macOS `sandbox_init` 隔离引擎扫描，在嵌套沙箱内被拒绝（Operation not permitted），属执行环境限制而非代码缺陷；沙箱外单测与完整套件均通过。

原生 smoke 入口 `App.swift` 输出 `Native search and file acceptance journeys: passed` 与 `Native file actions and Quick Look: passed (...)`，覆盖搜索、排序、刷新、范围、筛选、检查器、文件动作与 Quick Look 的同一模型动作；真实 Finder 可见选中状态、人工 VoiceOver 与真实权限旅程仍未单独观察。

## 未验证门禁与残余风险

- Intel 实机、macOS 13 实机、真实 TCC/FDA 授权与撤销、受保护位置真实覆盖仍未验证（T06/T08/T10 门禁）。
- 真实用户磁盘规模下的性能、资源占用与大索引延迟仍以受控样本测量为限，不代表个人磁盘 p50/p95。
- 本组票完成受控应用行为、公开服务接缝与既有回归；不能据此宣称 alpha 或公众发行门禁解除。
