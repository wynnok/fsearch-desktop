## Parent

[[SPEC-03] M1：真实 Engine 生命周期、权限与资源验证](https://github.com/wynnok/fsearch-desktop/issues/5)。

Ticket ID：T08。切片粒度与阻塞边已由用户确认；本票不编辑或关闭父 Spec。

## What to build

在专用环境中验证跳过、授予、撤销完全磁盘访问权限后的真实搜索结果，用户不会把受限覆盖当无匹配。

## Acceptance criteria

- [ ] 测试主体为实际签名应用，签名身份和测试环境作为明确外部前置。
- [ ] 受保护位置授权前后、撤销、重启/重新检查的结果及状态可解释。
- [ ] 不只依据 full_disk_access 字段宣称全部可读，测试不程序化修改系统权限。
- [ ] 索引不自动下载 iCloud 占位文件；本地缺失与不可读说明准确。
- [ ] 缺少签名条件时其他独立工作可继续，但本票权限门禁不得关闭。

