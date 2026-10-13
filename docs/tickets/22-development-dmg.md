## Parent

[[SPEC-09] DevOps：可安装开发 DMG 与持续集成](https://github.com/wynnok/fsearch-desktop/issues/10)。

交叉验收还覆盖 [[SPEC-04] M1：双架构构建、链接与最低系统验证](https://github.com/wynnok/fsearch-desktop/issues/4)；只设置一个原生父 Spec，父 Spec 的完成仍需按原正文验收。

Ticket ID：T22。切片粒度与阻塞边已由用户确认；本票不编辑或关闭父 Spec。

## What to build

普通 push/PR 自动产出可安装开发 DMG；测试者下载、安装并完成当时已实现的查询切片。

## Acceptance criteria

- [ ] 复用项目构建入口，核对主程序/内置引擎架构、版本、许可证和最终 SHA-256。
- [ ] 真实 CI 和安装→启动→查询→退出路径有证据，失败不产出成功标记。
- [ ] 早期包明确标注开发/验证状态，完整 alpha 尚未具备时不得冒充成品验收通过。
- [ ] 工作流以后自动携带已合并能力；不需要等所有 UI 功能完成才建立下载链路。
- [ ] 不运行 CLI install 或修改系统设置，缺签名条件可标明未公证，不发布 stable。

