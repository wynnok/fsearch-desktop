## Parent

[[SPEC-06] v0.1：检查器、Quick Look 与 Finder 路径导航](https://github.com/wynnok/fsearch-desktop/issues/7)。

Ticket ID：T15。切片粒度与阻塞边已由用户确认；本票不编辑或关闭父 Spec。

## What to build

选择结果后立即显示已知信息，并按需加载图标、类型、实际大小和创建/修改时间。

## Acceptance criteria

- [ ] 异步信息返回必须对应当前选择，快速切换不会显示上一文件详情。
- [ ] 未知/不可读显示明确状态，目录大小不冒充递归占用。
- [ ] 索引大小与实际大小差异可解释；应用包、链接、多选诚实呈现。
- [ ] 受控真实文件和选择晚返回测试通过，图标/属性读取并发有界。

