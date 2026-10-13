## Parent

[[SPEC-01] M1：可升级 Fsearch 集成与 Swift 引擎服务契约](https://github.com/wynnok/fsearch-desktop/issues/2)。

交叉验收还覆盖 [[SPEC-03] M1：真实 Engine 生命周期、权限与资源验证](https://github.com/wynnok/fsearch-desktop/issues/5)；只设置一个原生父 Spec，父 Spec 的完成仍需按原正文验收。

Ticket ID：T07。切片粒度与阻塞边已由用户确认；本票不编辑或关闭父 Spec。

## What to build

验证窗口切换到真实 Engine，使用客户端独立索引回答查询；文件变化可收到通知，关闭重开及退出恢复有真实证据。

## Acceptance criteria

- [ ] 启动前证明扫描限制策略或使用专用环境，不能把 home、数据目录或查询范围当成索引 root。
- [ ] 独立索引与已有 CLI 数据/进程分离；真实 Engine 查询不能仅用 Searcher 通过来替代。
- [ ] 目录增删改经过同一服务的变更通知可验证，索引保存及再启动查询恢复有证据。
- [ ] 关闭验证窗口仍维护索引，重开可查；退出结束自身应用，重复实例行为与索引锁正确。
- [ ] 保留上游默认名称/内容索引机制，不擅自拆复制或切换 helper。

