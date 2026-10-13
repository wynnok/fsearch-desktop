## Parent

[[SPEC-10] Release：签名公证、版本 tag 与正式安装验收](https://github.com/wynnok/fsearch-desktop/issues/13)。

Ticket ID：T28。切片粒度与阻塞边已由用户确认；本票不编辑或关闭父 Spec。

## What to build

在签名条件具备时，将实际开发包走完签名、公证、staple 和干净环境启动验证，失败时可排障且不泄露凭据。

## Acceptance criteria

- [ ] Developer ID 和公证条件作为明确外部前置；签嵌套组件后签主应用，完成后不改内容。
- [ ] 真实公证 Accepted、staple 与最终 codesign/spctl 和安装启动证据齐全，模拟成功不算通过。
- [ ] 凭据仅安全配置使用，临时签名环境清理，缺凭据/拒绝不会泄露秘密或报告成功。
- [ ] 本票只建立验证链路，不未经批准发布公众版本；缺外部条件保留门禁。

