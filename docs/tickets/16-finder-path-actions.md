## Parent

[[SPEC-06] v0.1：检查器、Quick Look 与 Finder 路径导航](https://github.com/wynnok/fsearch-desktop/issues/7)。

Ticket ID：T16。切片粒度与阻塞边已由用户确认；本票不编辑或关闭父 Spec。

## What to build

用户能双击/回车打开结果、在 Finder 显示、复制路径，并点击底部任一级祖先文件夹打开对应位置。

## Acceptance criteria

- [ ] 选中路径→原生系统动作→实际目标完整可演示，文件夹打开与显示文件本身明确区分。
- [ ] 长路径可折叠但所有祖先仍可访问，完整路径可复制。
- [ ] 根目录、同名、链接、应用包、移动删除和权限失败均有可理解行为。
- [ ] 使用系统文件操作，不新增移动、删除、重命名等文件管理功能。

