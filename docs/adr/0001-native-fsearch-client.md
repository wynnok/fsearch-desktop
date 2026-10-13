---
status: accepted
---

# 原生独立搜索客户端，以 Fsearch 为唯一搜索引擎

本产品定位为类似 Everything 的独立 macOS 文件搜索应用，使用 SwiftUI + AppKit；索引、名称匹配、文本内容检索和变更追踪使用 Fsearch，不另建 Spotlight、SQLite 或自研扫描器作为搜索引擎。相比 Finder 插件和跨平台网页界面，这一选择保留原生文件操作、预览及可访问性，也意味着能力边界要跟随 Fsearch；上游没有的全局排序等能力必须通过最薄的适配验证，而不能静默换用另一套底层实现。

