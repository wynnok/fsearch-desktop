## Parent

[[SPEC-06] v0.1：检查器、Quick Look 与 Finder 路径导航](https://github.com/wynnok/fsearch-desktop/issues/7)。

Ticket ID：T17。切片粒度与阻塞边已由用户确认；本票不编辑或关闭父 Spec。

## What to build

用户按空格预览当前选择，切换选择或关闭预览时目标一致，系统不支持或文件消失时能理解失败。

## Acceptance criteria

- [ ] Quick Look、Escape、选择切换与焦点行为通过原生冒烟。
- [ ] 快速切换不预览旧对象；不可访问/已删除文件给出清楚说明。
- [ ] 预览支持格式不作为内容搜索能力宣称；后台索引不借预览自动批量下载云文件。
- [ ] 保留已有搜索与系统打开操作，必要回归在同一用户流程验证。

