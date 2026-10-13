## Parent

[[SPEC-01] M1：可升级 Fsearch 集成与 Swift 引擎服务契约](https://github.com/wynnok/fsearch-desktop/issues/2)。

Ticket ID：T01。切片粒度与阻塞边已由用户确认；本票不编辑或关闭父 Spec。

## What to build

打开原生验证窗口，输入文件名，经 Swift 引擎服务与薄桥接调用 Fsearch 的受控样本，显示可核对的真实匹配结果。

## Acceptance criteria

- [ ] 项目范围构建可复现，上游版本固定且与适配代码分开，许可证可追溯。
- [ ] 输入→公开服务→Fsearch→原生结果的完整路径可演示，不能以硬编码列表代替。
- [ ] 受控样本、缓存和产物留在项目内；未启动真实 Engine 时明确标注样本验证模式，不宣称 Engine 已验证。
- [ ] 窗口能显示成功、无匹配及查询失败，测试从 Swift 侧公开契约核对外部结果。
- [ ] 定义用于后续切片的最小请求、结果、状态和内存归属契约，不复制上游匹配算法。

## Blocked by

None (can start immediately).

