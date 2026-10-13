## Parent

[[SPEC-01] M1：可升级 Fsearch 集成与 Swift 引擎服务契约](https://github.com/wynnok/fsearch-desktop/issues/2)。

Ticket ID：T02。切片粒度与阻塞边已由用户确认；本票不编辑或关闭父 Spec。

## What to build

用户输入中文、emoji、空格和冒号时得到正确结果；非法查询给出可恢复错误，重复搜索不会因跨语言边界泄漏或崩溃。

## Acceptance criteria

- [ ] 普通输入保留标点数据含义，与明确启用的高级语义分开。
- [ ] 通过同一公开服务与原生窗口验证 Unicode、组合字符、空/非法请求及错误恢复。
- [ ] 重复查询及释放观测资源，结果归属和释放责任明确；Rust panic 不跨越 FFI 边界。
- [ ] 错误后继续正常查询可成功，诊断不原样泄露真实路径或正文。

