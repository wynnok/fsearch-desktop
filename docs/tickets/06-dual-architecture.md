## Parent

[[SPEC-04] M1：双架构构建、链接与最低系统验证](https://github.com/wynnok/fsearch-desktop/issues/4)。

Ticket ID：T06。切片粒度与阻塞边已由用户确认；本票不编辑或关闭父 Spec。

## What to build

同一最小原生查询应用可以在 arm64、x86_64 和 macOS 13 目标环境构建、链接并完成样本查询。

## Acceptance criteria

- [ ] Swift 与内置 Rust 的架构一致，核验最终可执行产物和依赖切片。
- [ ] 使用兼容基线 CPU 参数及最低系统目标，不沿用构建机器特有指令。
- [ ] 构建、样本查询和启动证据覆盖两架构；跨编译、Rosetta、Intel 实机与最低系统实测分开记录。
- [ ] 目标准备与缓存在项目/隔离环境中完成，不改变工作站全局工具链。
- [ ] 缺少真实设备时保留未验证门禁，不把构建成功当运行成功。

