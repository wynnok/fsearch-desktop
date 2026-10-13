## Parent

[[SPEC-08] v0.1：本地设置、主动诊断导出与手动更新入口](https://github.com/wynnok/fsearch-desktop/issues/9)。

Ticket ID：T21。切片粒度与阻塞边已由用户确认；本票不编辑或关闭父 Spec。

## What to build

用户从 About 或菜单了解版本，检查更新后可打开可信下载入口并自行更新。

## Acceptance criteria

- [ ] 当前客户端和上游固定版本可追溯，更新入口与 Releases 下载链接可用。
- [ ] 没有新版本或网络失败时诚实反馈，不伪造更新、不阻塞搜索。
- [ ] 检查动作不自动替换应用或已加载引擎。
- [ ] 原生冒烟与受控更新响应验证结果及错误行为。

