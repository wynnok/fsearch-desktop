## Parent

[[SPEC-13] v0.2：受支持文本内容搜索与匹配片段](https://github.com/wynnok/fsearch-desktop/issues/14)。

Ticket ID：T33。切片粒度与阻塞边已由用户确认；本票不编辑或关闭父 Spec。

## What to build

测试者走完文本查询、模式/范围、匹配片段、预算续查和文件动作，用户获得准确的文本搜索说明。

## Acceptance criteria

- [ ] 真实应用覆盖普通/正则/大小写、Unicode、CRLF、文件更新、非法模式与续查。
- [ ] 文件数量、内容匹配、complete/next 和扫描来源的语义与上游一致且可理解。
- [ ] 指南公开文本类型、大小/忽略规则、直接扫描限制与云端缺失；预览能力不算正文检索能力。
- [ ] 诊断无默认片段泄露，名称搜索回归正常，不加入未确认的 beta 扩展。

