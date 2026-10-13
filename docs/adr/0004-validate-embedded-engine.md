---
status: accepted
---

# 优先验证公开 Fsearch Engine 的嵌入路线

用户确认先用 Rust staticlib + 薄 C ABI 直接调用公开 Engine，保留 Fsearch 为可升级依赖，验证完整结果排序、生命周期、权限及双架构链接。相比直接包装 CLI，这条路线能绕开现有 JSON 分页契约的限制，并让扫描与主应用的集成边界更清楚；代价是必须验证 FFI 内存、线程和进程内资源行为。此决定批准的是优先验证路线，不表示它已经可行；若验证不成立，再提出 bundle 内 helper 方案及其代价。
