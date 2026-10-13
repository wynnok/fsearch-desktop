## Parent

[[SPEC-13] v0.2：受支持文本内容搜索与匹配片段](https://github.com/wynnok/fsearch-desktop/issues/14)。

Ticket ID：T32。切片粒度与阻塞边已由用户确认；本票不编辑或关闭父 Spec。

## What to build

内容搜索预算耗尽时用户可继续，匹配高亮对中文/emoji 正确，部分结果不会被显示为全部匹配。

## Acceptance criteria

- [ ] 按上游内容 cursor 续查，不与名称 offset 混用，文件/匹配计数不混淆。
- [ ] 结合 complete、next、来源和预算判断未完成，停止/继续状态可理解。
- [ ] UTF-8 字节范围安全转为原生文本范围，覆盖组合字符、emoji 和截断片段。
- [ ] 查询改变或晚返回续查不会覆盖新查询，真实受控数据验证无错页与错误高亮。

