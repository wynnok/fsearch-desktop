## Parent

[[SPEC-13] v0.2：受支持文本内容搜索与匹配片段](https://github.com/wynnok/fsearch-desktop/issues/14)。

Ticket ID：T31。切片粒度与阻塞边已由用户确认；本票不编辑或关闭父 Spec。

## What to build

用户在内容查询中复用范围/筛选，并明确选择正则和大小写方式，错误保留输入便于修正。

## Acceptance criteria

- [ ] 请求条件经同一公开契约映射上游，范围/属性与正文模式不会误用名称 offset。
- [ ] 真实样本验证 literal/regex、大小写、过滤组合与无匹配，非法正则可恢复。
- [ ] 受支持文本准入/忽略/大小规则说明与实际结果一致，不新增文档解析。
- [ ] 用户交互可发现且不破坏既有名称搜索和文件动作。

