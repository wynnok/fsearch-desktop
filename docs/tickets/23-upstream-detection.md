## Parent

[[SPEC-11] Maintenance：每日上游检测与升级 PR 兼容性门禁](https://github.com/wynnok/fsearch-desktop/issues/11)。

Ticket ID：T23。切片粒度与阻塞边已由用户确认；本票不编辑或关闭父 Spec。

## What to build

维护者能看到每日检测的无更新、新候选或失败结果，确认客户端跟进的是正式版本而非滚动主线。

## Acceptance criteria

- [ ] 正式 Release/tag 选择和候选 commit 明确，不选预发布或滚动 main 作为正式依赖。
- [ ] 无更新无改动；网络失败保留现有版本并可重试，不伪造发行。
- [ ] 真实仓库作业和受控发行列表核对选择逻辑，结果包含现用/候选版本。
- [ ] 实现于仓库 CI，不建立无关 Codex 定时任务，本票尚不自动合并/发行。

