## Parent

[[SPEC-10] Release：签名公证、版本 tag 与正式安装验收](https://github.com/wynnok/fsearch-desktop/issues/13)。

Ticket ID：T29。切片粒度与阻塞边已由用户确认；本票不编辑或关闭父 Spec。

## What to build

维护者明确发出版本 tag 后，完整检查自动发布签名公证 DMG、哈希、许可和说明，用户能从 Releases 下载并安装。

## Acceptance criteria

- [ ] 复用 alpha 验收和真实签名链路，任一检查失败阻止正式发行。
- [ ] 一次已批准 tag 的完整运行及可下载资产、版本/引擎记录、哈希与安装证据可追溯。
- [ ] 普通 push 不覆盖 stable，不自动重写公开 tag 或替换历史包。
- [ ] 缺签名/设备证据不以 workflow 分支存在宣称公众发行完成。

