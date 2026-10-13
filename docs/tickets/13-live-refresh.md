## Parent

[[SPEC-05] v0.1：原生搜索配置与结果列表交互](https://github.com/wynnok/fsearch-desktop/issues/6)。

交叉验收还覆盖 [[SPEC-02] M1：完整结果快照、全局排序与分页](https://github.com/wynnok/fsearch-desktop/issues/3)；只设置一个原生父 Spec，父 Spec 的完成仍需按原正文验收。

Ticket ID：T13。切片粒度与阻塞边已由用户确认；本票不编辑或关闭父 Spec。

## What to build

当前查询中的新增、改名、删除和属性变化自动合并刷新，用户选中文件和可视位置尽量保持稳定。

## Acceptance criteria

- [ ] 复用上游服务变更通知，不增建另一套文件系统监视/索引。
- [ ] 新快照按当前查询和排序生成，不混用旧页；刷新期间输入与选择可用。
- [ ] 按路径恢复选择并尽量保留滚动位置，所选文件消失时给出原因。
- [ ] 原生交互与真实受控变化验证连续变更、排序字段变化和晚返回刷新。

