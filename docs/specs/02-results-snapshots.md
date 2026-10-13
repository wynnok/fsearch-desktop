# [SPEC-02] M1：完整结果快照、全局排序与分页

## Problem Statement

原有 JSON 分页没有全局排序与精确总数契约。只对一页排序会误导用户；大量结果和索引变化也会造成遗漏、重复或顺序漂移。

## Solution

通过已确认的引擎服务取得本次查询的完整匹配集合，建立明确快照，以自然名称、索引大小和修改时间全局排序，再按同一快照分页。

## User Stories

1. As a user, I want all matching results sorted, so that a file on a later page is not placed incorrectly.
2. As a user, I want natural name ordering, so that file2 appears before file10.
3. As a user, I want size ordering, so that I can identify relatively large or small files.
4. As a user, I want modification-time ordering, so that I can find recent or old files.
5. As a user, I want both sorting directions, so that I can inspect either end of the result set.
6. As a user, I want stable ties, so that equal values do not reorder randomly.
7. As a user, I want an honest total, so that a truncated response is not treated as exhaustive.
8. As a user, I want explicit partial-result status, so that an operational limit is visible.
9. As a user, I want paged results from one snapshot, so that indexing changes do not duplicate or omit entries between pages.
10. As a user, I want sorting to run asynchronously, so that I can change my query while it completes.
11. As a user, I want stale requests discarded, so that an old sort cannot replace my current results.
12. As a user, I want my chosen sort retained, so that changing search mode does not override an explicit preference.
13. As a user, I want indexed-size precision explained, so that near-equal large files are not presented as byte-exact comparisons.
14. As a tester, I want large controlled result sets, so that behavior beyond the old pagination cap is verified.
15. As a maintainer, I want measured memory and latency, so that full-result behavior is assessed rather than inferred from top-k speed.

## Implementation Decisions

- 通过统一引擎服务提供查询快照标识、完整性/截断状态、计数、排序条件和分页位置，不建设第二套搜索引擎。
- 关联性保留上游排序；名称采用原生自然顺序，索引大小/修改时间采用对应值，同值以路径形成稳定次序。
- 用户显式选择排序优先于模式默认；无显式选择时包含模式名称升序，模糊模式关联性。
- 页必须属于同一快照；查询、排序或刷新得到新快照，禁止混合旧页与新结果；UI 只接收所需页。
- 完整性不能由返回数量或旧分页 next 缺失猜测；限制导致部分结果时明确标注，不能据此宣称 P0 全局排序已满足。
- 首版大小沿用索引精度；名称全量获取的内存/延迟需要实测，不把 usize 最大值的小样本测试外推。

## Testing Decisions

- 在 Swift 侧服务主接缝比较至少 25,001 个匹配的独立预期集合，无缺漏/重复；覆盖跨页升降序、同值和自然排序。
- 覆盖中文、emoji、NFC/NFD、数字、重音、大小写、相同名称和 2 GiB 大小编码边界。
- 注入晚返回和索引变化，验证快照隔离、过期请求丢弃及完整性字段外部行为。
- 从 25,001、100,000、1M 逐级测量，再评估 8M；记录冷/热状态、p50/p95 和峰值 RSS，不要求无证据的毫秒承诺。
- 参考上游大 limit 溢出回归与名称排序稳定性实现的外部结果；本规格不测试其私有 top-k 数据结构。

## Out of Scope

- 读取完整匹配集所有文件的实际字节大小来替代上游筛选、自研匹配、当前页排序冒充全局排序。

## Further Notes

- 总规格：Part of #1。
- 阻塞依赖：Blocked by: #2。
- Spec ID：SPEC-02。
- 阶段：M1。
- 依据已确认选择：Q12、Q13、Q14、Q17、Q23。
- 前置规格：SPEC-01。
- 全局排序允许异步完成；候选首屏 150ms 不是已经证明的客户端指标。

