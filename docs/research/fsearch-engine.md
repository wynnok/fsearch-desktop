# Fsearch 引擎源码研究

研究日期：2026-10-13。基线：`noahdunnagan/fsearch` **v0.2.1**，固定提交 `88e63fdf850cf7749deae8198b187accd21f8ba5`。本报告以该提交的实际代码为准，链接均固定到该提交；后续升级必须重新核查接口和边界。

## 结论

Fsearch 能提供本应用需要的核心能力：macOS 文件名索引、模糊与字面查询、路径和元数据过滤、FSEvents 增量更新，以及有限范围的文本内容检索。它同时提供 Rust crate、CLI、JSON Lines 守护进程接口和 MCP，但没有 Swift/C ABI。SwiftUI + AppKit 客户端需要一个薄桥接层，搜索与索引算法继续调用上游。公开库与二进制模块的边界见 [lib.rs L1–17](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/lib.rs#L1-L17)、[main.rs L1–25](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/main.rs#L1-L25)。

**不能从“whole-disk”宣传直接推导出 Everything 的完整功能对等。** 本版本不跨越挂载点，内容索引仅覆盖符合规则的用户目录文本，JSON 名称分页路径有 20,000 条抓取上限，接口没有匹配总数或按名称/大小/时间进行全局排序的参数。这些差异决定客户端产品文案、排序语义和版本范围。相关证据见下文。

## 1. 模块与算法

| 模块 | 源码实际职责及主要算法 | 固定来源 |
| --- | --- | --- |
| `walk.rs` | 从 `/` 枚举；使用 `getattrlistbulk` 批量取得名称、类型、逻辑大小和修改时间，以目录 fd + `openat` 递归；Rayon 并行扫描，跳过符号链接递归及挂载点 | [遍历与并行 L113–190](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/walk.rs#L113-L190)、[下降 L200–260](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/walk.rs#L200-L260)、[属性读取 L313–408](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/walk.rs#L313-L408) |
| `index.rs` | 按目录块深度优先排列，使子树成为连续范围；重复文件名驻留一次，先按唯一名称评分；字符类位图一次筛 64 个名称；整数位压缩、父目录映射、十六进制/UUID 名称压缩；整个二进制索引可 mmap | [结构说明 L1–16](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/index.rs#L1-L16)、[构建 L657–745](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/index.rs#L657-L745) |
| `query.rs` | 解析搜索语言；字节级模糊子序列、前缀、后缀、字面包含、排除和 glob；边界/驼峰/连续匹配奖励与 gap 惩罚，整名和词干奖励；拼写错误容忍和必要时的深层纠错；路径词继承、位置先验、近期修改及 app/隐藏标志参与相关度；最终取 top-k | [评分 L1111–1210](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/query.rs#L1111-L1210)、[路径匹配 L652–716](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/query.rs#L652-L716)、[微调 L4033–4055](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/query.rs#L4033-L4055) |
| `query.rs` 查询规划 | 依查询选择 ranked、driven、spread、选择性扫描或完整顺序扫描；先评分唯一名称，再映射到条目；缓存输入逐渐收窄时的名称匹配；合并基底与 overlay 后按相关度截断 | [策略入口 L2064–2175](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/query.rs#L2064-L2175)、[名称缓存 L3632–3726](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/query.rs#L3632-L3726) |
| `live.rs` | 已保存基底索引 + 删除标记 + 路径有序 overlay 与 flat mask；事件触发目录重新列举、比较新旧条目，删除子树、补扫新目录；读盘 `fetch` 与写内存 `apply` 分开，减小搜索受锁影响的时间 | [结构 L14–111](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/live.rs#L14-L111)、[fetch/apply L209–368](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/live.rs#L209-L368) |
| `fsevents.rs`、`engine.rs` | 动态加载 CoreServices/CoreFoundation，监听 `/` 的目录级 FSEvents；保存事件 ID，重启回放；丢事件时重新列举上次同步时间之后变化的目录，加入 120 秒余量；对高频目录事件做节流 | [流 L139–166](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/fsevents.rs#L139-L166)、[恢复 L941–977](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/engine.rs#L941-L977)、[节流与循环 L979–1145](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/engine.rs#L979-L1145) |
| `content.rs` | 不可变 mmap 内容 segment；对内容去重，trigram 倒排用 bitset 或插值编码；路径前缀压缩，5 字节 gram Bloom filter 排除假候选；查询先组合 trigram AND/OR，再读取当前磁盘内容精确核验；segment diff、墓碑和合并维护更新 | [设计 L1–19](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/content.rs#L1-L19)、[结构 L182–217](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/content.rs#L182-L217)、[维护 L2262–2432](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/content.rs#L2262-L2432)、[搜索 L2731–2800](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/content.rs#L2731-L2800) |
| `server.rs` | Unix socket JSON Lines 请求分发、名称分页、glob/Git 过滤、相关度再排序、内容查询参数与响应 | [建立服务 L17–57](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/server.rs#L17-L57)、[请求分发 L197–287](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/server.rs#L197-L287) |
| `frecency.rs`、`git.rs` | 用户主动上报的打开次数按 14 天半衰期衰减，最多保留 4,096 条；读取 Git 状态和用户近期提交做过滤/标注/排序，Git 是附加能力，不是索引必需条件 | [frecency L13–88](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/frecency.rs#L13-L88)、[Git L1–107](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/git.rs#L1-L107) |
| `alloc.rs`、`main.rs` | 二进制安装自定义全局分配器，大块使用 mmap，小块按搜索线程有限缓存；daemon 启动使用进程级 malloc 空间优化；CLI、stdio 和 daemon 生命周期管理 | [allocator L1–31](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/alloc.rs#L1-L31)、[二进制 L12–84](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/main.rs#L12-L84) |
| `mcp.rs` | JSON-RPC MCP，提供 `find_files`、`grep`、`multi_grep`，转发到共享 daemon，回答文本偏开发者用途 | [协议 L1–31](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/mcp.rs#L1-L31)、[工具分发 L113–147](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/mcp.rs#L113-L147) |

## 2. Rust crate 真实接口

`Engine::start(Options { dir, home, skip }) -> Result<Engine, String>` 在后台建立/加载索引。`Options` 只有索引目录、用户 home、排除目录；**没有指定索引 root、禁用内容索引、暂停、取消、重建或关闭引擎的公开选项**。搜索范围 `in:` 是查询约束，不能解释为“只对用户选择的文件夹建立索引”。owner 首次启动调用从 `/` 枚举的 `full_build`。[Options L36–44](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/engine.rs#L36-L44)、[启动 L226–335](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/engine.rs#L226-L335)、[全量构建 L890–905](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/engine.rs#L890-L905)。

| 接口 | 返回/语义 | 产品用途 |
| --- | --- | --- |
| `Query::parse(text, home)` | `Result<Query, String>`；默认 `limit = 50` | 基础和高级查询的唯一语义入口 |
| `Engine::search(&Query)` | `Result<Vec<Found>, String>`，每条含 `path/kind/size/mtime/score` | 文件名结果；没有总数或分页状态 |
| `Grep::with_case(pattern, mode, case)`、`Grep::any_of(...)` | literal/regex/symbol，smart/sensitive/insensitive；多字面模式按 OR 匹配 | 文本内容查询 |
| `Engine::grep(&Query, &Grep)` | `Result<(GrepResult, bool), String>`；bool 说明来自内容索引还是直接读取 | 内容结果及覆盖状态 |
| `Engine::status()` | `Status`：ready、entries、dirs、overlay、removed、event_id、index_bytes、content_docs/segments/bytes/pending、full_disk_access、owner | 展示索引状态；entries 是基底条目数，不是当前查询匹配总数 |
| `Engine::indexing()` | 进度描述字符串 | 初次索引提示；其中 `~25s` 是上游估计，不应原样作为本产品承诺 |
| `Engine::save()` | 请求后台压缩保存，立即返回 | 保存请求；返回不等于已落盘 |
| `Engine::on_change(callback)` | 在 apply 线程回调变化目录及 recursive 标志 | 触发 UI 结果刷新，回调必须快速返回 |
| `Engine::keep_warm(Duration)` | 短时自旋保持 CPU 时钟 | 可选性能优化，必须先评估耗电 |

接口定义来源：[查询结构和解析 L376–452](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/query.rs#L376-L452)、[Engine API L358–465](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/engine.rs#L358-L465)、[Found/Status L46–73](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/engine.rs#L46-L73)、[Grep L3348–3428](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/content.rs#L3348-L3428)。

**桥接建议（工程判断，尚待 POC 验证）：** 以嵌入 Engine 的 Rust staticlib + C ABI 薄封装连接 Swift，封装句柄、请求/响应序列化、错误与结果内存释放；在后台队列执行搜索。它避免依赖上游 CLI 的安装流程，并可使用 `Options.dir` 给本应用独立数据目录。daemon 的 Git/frecency/MCP 属于二进制模块，没有通过 `lib.rs` 全部导出；不能把 daemon extras 直接写成 crate 自带 API。若选择子进程/JSON 桥接，需显式接受下面的分页边界，并另行验证 helper 的 TCC 归属。[公开导出](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/lib.rs#L6-L17)、[binary 模块](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/main.rs#L1-L4)。

## 3. 名称搜索语言、排序与结果完整性

### 可映射到配置区的能力

- 名称：普通词为 fuzzy；`'词` 表示字面包含，`^词` 为前缀，`词$` 为后缀，`!词` 为排除。`'exact` **不是整个名称相等**，UI 应叫“包含（字面）”；全名相等可经转义构造锚定 `re:`。[token L508–536](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/query.rs#L508-L536)、[token_score L1631–1663](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/query.rs#L1631-L1663)。
- `ext:` 扩展名列表，`type:` image/video/audio/doc/code/archive/font/app，`kind:` 文件/目录/链接，`in:` 单一目录范围，`size:` 范围，`mtime:`/`modified:` 修改时间年龄，`re:` 名称正则、`path:` 路径正则。`type:doc` 按扩展名分类不表示可以搜其文档正文。[类型 L420–428](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/query.rs#L420-L428)、[过滤 L573–618](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/query.rs#L573-L618)。
- 支持 glob、目录词和否定 glob，多个词可由文件名及祖先目录共同满足，但至少一个正向词须命中文件自身名称；正向词超过 8 个会移除最早的词。[glob/词解析 L451–536](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/query.rs#L451-L536)、[路径匹配 L675–711](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/query.rs#L675-L711)。
- fuzzy token 按 UTF-8 **字节长度**达到 5/8 时允许一/两次编辑；不是按中文字符个数计算。实际搜索可能在 top-8 无足够好匹配时进行更深纠错。[阈值 L361–374](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/query.rs#L361-L374)、[深层查询 L2079–2115](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/query.rs#L2079-L2115)。

### JSON 接口的分页边界

传输为每行一个 JSON，默认 socket 在 `~/Library/Application Support/FSearch/fsearch.sock`；`fsearch stdio` 也是转发到 daemon。响应回显 `id`。名称响应字段为 `ok/id/hits/took_us`，分页时可有 `next`；命中只有 `path/kind/size/mtime/score` 和可选 Git 状态，没有 `total` 或 `complete`。[socket L17–18](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/server.rs#L17-L18)、[stdio L114–132](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/main.rs#L114-L132)、[响应 L131–195](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/server.rs#L131-L195)。

名称请求使用 `offset`，`cursor` 在非 grep 时也解释为 offset。分页重复取得相关度排序的前 `offset + limit + 1` 条后裁剪，**不是固定快照游标**；索引变化时跨页可能漂移。`MAX_FETCH = 20_000`，offset 也被 clamp 到该值。到上限后没有 `next`，不能据此证明不存在更多真实匹配。[参数 L329–349](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/server.rs#L329-L349)、[查询 L251–284](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/server.rs#L251-L284)、[裁剪 L436–444](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/server.rs#L436-L444)、[抓取 L548–575](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/server.rs#L548-L575)。

**20,000 并不是所有查询共有的引擎硬上限。** 普通无 extras 的 JSON search 直接调用 `Engine::search`，不走 MAX_FETCH；crate 的 `Query.limit` 为 `usize`，上游有 `usize::MAX` 的小索引测试。故经 crate 把 limit 调到很大，再在客户端排序，理论上可获得更完整的名称匹配集；但上游接口仍一次性返回 `Vec`，没有流式输出、全局排序键、计数或快照语义。它可能构造大量结果、完整路径、top-k 缓冲并做全量排序；百万条宽查询的内存、首次延迟、纠错语义必须通过 POC 核验。小索引 huge_limit 测试不等于生产规模保证。[plain 分支 L251–257](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/server.rs#L251-L257)、[limit 设置 L872–891](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/server.rs#L872-L891)、[TopK L1665–1707](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/query.rs#L1665-L1707)、[合并排序 L2117–2123](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/query.rs#L2117-L2123)、[huge_limit 测试 L4070–4075](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/query.rs#L4070-L4075)。

**产品要求：** 若采用 CLI 快速原型，列排序必须标明仅作用于“当前已加载结果”；正式 P0 必须验证完整匹配集合的全局排序，原型不能替代用户的正式需求，也不能把某页排序伪装成所有匹配排序。原型结果数量宜显示“已加载 N 个结果”或“显示前 N 个结果”，不以返回条数声称总匹配数；正式版本只有经过完整性核验后才可显示匹配总数。这是由上述接口边界得出的产品判断。

## 4. 内容搜索覆盖、预算和 Unicode

内容索引最初同步 `$HOME`；只覆盖符合规则的文件，不是整盘所有内容。非 Git 仓库一般上限 **1 MiB**，按文本扩展名准入，无扩展名限制 **256 KiB**；Git 仓库多数文本可至 **10 MiB**，JSON/JSONL/NDJSON 仍采用 1 MiB cap。PDF、Word、Excel、PowerPoint、压缩包、图片等在二进制扩展名列表，不提供正文解码/OCR。[限制 L36–40](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/content.rs#L36-L40)、[扩展名 L93–122](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/content.rs#L93-L122)、[准入 L1338–1365](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/content.rs#L1338-L1365)、[Git 准入 L1615–1628](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/content.rs#L1615-L1628)。

依赖、缓存、app/library bundle 和部分 home 子目录会排除；仓库读取 `.ignore`、`.gitignore`、`.git/info/exclude` 与全局 ignore；linked Git worktree 的内容也跳过。lockfile、≥100 KiB 的 JSON/JSONC/JSON5、minified/bundle/chunk 资产以及平均行长过大的文本会省略；任何 NUL 字节使索引文本测试失败。名称是否可搜与内容是否索引是不同问题。[目录规则 L64–91](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/content.rs#L64-L91)、[生成文件与文本 L1368–1401](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/content.rs#L1368-L1401)、[worktree L1565–1591](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/content.rs#L1565-L1591)、[ignore 次序 L1718–1742](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/content.rs#L1718-L1742)。

`content-skip.txt` 允许用户额外排除目录，支持 `~` 和注释；它不会让名称消失，主动指定某文件的 grep 仍可读取。[排除列表 L1451–1475](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/content.rs#L1451-L1475)。

范围不由内容索引覆盖时，引擎退回名称索引选候选再读文件。此扫描路径本身截断在 **200,000 条、≤1 MiB** 后按修改时间排序；所以不能承诺“未索引位置可穷尽所有文本”。主动指定单文件 grep 可读至 10 MiB，放宽生成文本判断但仍检查前 8 KiB 的 NUL，也不构成文档格式解析。[Engine 回退 L390–425](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/engine.rs#L390-L425)、[候选扫描 L4668–4688](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/content.rs#L4668-L4688)、[单文件 L3584–3593](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/content.rs#L3584-L3593)、[读取 L3722–3765](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/content.rs#L3722-L3765)。

默认 `Grep` 预算 **250 ms**、每文件最多 5 个匹配行；JSON `file` 查询默认每文件 200 行，可设 `budget_ms/per_file/before/after/context/defs/cursor`。内容响应有 `source`（index/scan/file）、`candidates/read/complete/indexing/files` 和可选 `next`。`cursor` 是候选排名的继续位置，不能当名称 offset；额外过滤路径又可采用 offset，必须区分。`complete` 为 true 也可能只是本页达到 limit，**不表示所有匹配已展示**；要结合 `next` 与预算理解，而且 candidates 是候选数。[Grep 默认 L3348–3411](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/content.rs#L3348-L3411)、[响应/参数 L750–866](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/server.rs#L750-L866)、[完成计算 L3697–3702](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/content.rs#L3697-L3702)。

文本结果来自现读磁盘，避免展示索引内的旧正文；候选选择仍可能落后更新，dirty 文件先读机制和每目录 2 秒 debounce / 最长 5 分钟等待用于改善新鲜度。不能将源码说明中的“无 stale 内容”扩大为“无漏检”。[内容设计 L9–19](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/content.rs#L9-L19)、[内容同步 L757–808](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/engine.rs#L757-L808)、[fresh 先读 L2731–2756](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/content.rs#L2731-L2756)。

Unicode 边界：名称保留 UTF-8 字节，查询通过 CoreFoundation 添加另一 NFC/NFD 形式；这有助于组合/分解重音字符，但模糊匹配与大小写折叠主要基于字节和 ASCII，**没有中文分词、拼音、简繁互转或按字形计算的纠错接口**。内容非 ASCII 字面可走 regex 路径，索引只折叠 ASCII，非 ASCII 大小写查询会放宽候选筛选。中文、emoji、组合字符、大小写扩展必须专项核验，不能从 ASCII 基准推算。[名称归一化 L984–1035](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/query.rs#L984-L1035)、[字节折叠 L1111–1154](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/query.rs#L1111-L1154)、[内容 Unicode 路径 L3390–3415](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/content.rs#L3390-L3415)、[候选计划 L3465–3469](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/content.rs#L3465-L3469)。内容命中 `col/ranges` 按字节偏移，Swift 字符串高亮必须按 UTF-8 安全转换；显示行还裁为最多 400 原始字节。[行与范围 L3770–3797](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/content.rs#L3770-L3797)。

## 5. 持久化、owner/follower 与权限

名称索引 `index.bin` 按 temp + sync_data + rename 原子保存，header 记录事件 ID 与上次完整同步时间，重启 mmap 加载并回放。超过 **50,000** overlay+删除条目或有变化且距离上次保存超过 **12 小时**会压缩；`save()` 也可触发。压缩通过 live 重建索引、保存后重映射。[保存 L918–941](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/index.rs#L918-L941)、[阈值 L19–34](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/engine.rs#L19-L34)、[压缩 L918–937](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/engine.rs#L918-L937)、[触发 L1182–1191](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/engine.rs#L1182-L1191)。

同一数据目录的 `daemon.lock` flock 决定唯一 writer；其余 Engine 当 follower，读取名称/内容索引并在内存跟踪事件，每 10 秒检查更新或尝试接管。owner 退出后 follower 可获得锁接管；daemon 另有 `socket.lock` 限制同 socket 服务实例。这提供并存机制，**不是客户端可以任意结束其他进程的授权**。[启动锁 L236–257](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/engine.rs#L236-L257)、[follow/接管 L557–599](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/engine.rs#L557-L599)、[检查 L1173–1177](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/engine.rs#L1173-L1177)、[socket 锁 L21–29](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/server.rs#L21-L29)。

未检测到 Full Disk Access 且 `skip=None` 时，上游默认跳过 Desktop/Documents/Downloads、iCloud/CloudStorage、部分系统保护目录和 `/Volumes`，避免隐私提示阻塞。FDA 检测实现是尝试打开系统 TCC 数据库；应用不可把检测成功当成对所有路径可读的保证。macOS 允许用户按应用控制文件夹访问，最终应以签名后的实际 `.app` 权限实测。[gated 与探测 L706–722](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/engine.rs#L706-L722)、[Apple 文件夹访问说明](https://support.apple.com/guide/mac-help/control-access-to-files-and-folders-on-mac-mchld5a35146/mac)。

`walk::SKIP` 为进程级 `OnceLock`，设置后本进程不能随每个 Engine 动态改变；`status.full_disk_access` 只是检查 SKIP 是否不存在，**不是每次再次探测 TCC**。授权变化、排除项变化及多 Engine 实例应设计重启/重载方案；API 暂未提供动态 skip 管理。上游保存 `skipped` 文件并在 owner 启动或接管时重新列举此前缺失而现在可访问的目录。[skip 初始化 L240–250](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/engine.rs#L240-L250)、[status L428–445](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/engine.rs#L428-L445)、[缺失恢复 L602–655](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/engine.rs#L602-L655)。

iCloud 占位文件：CLI 设置进程级 no-materialize，Engine 工作线程设置线程级策略，不主动下载无数据文件，读取可能失败。因此“名称可见”不等于“云端正文可搜或预览已可用”。客户端预览若触发下载，需要单独的用户交互设计，不能让后台索引默默物化。[Engine 策略 L140–148](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/engine.rs#L140-L148)、[线程 L216–223](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/engine.rs#L216-L223)、[CLI 策略 L43–47](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/main.rs#L43-L47)。

## 6. 外接卷与文件详情边界

遍历将 mount/trigger 标记为 `FLAG_MOUNT`，并明确不下降；增量更新对子目录挂载也不递归，初期 scoped 目录构建遇挂载点同样停止。所以外接盘、网络卷及其他挂载卷的内容不能列为 v0.2.1 已支持搜索；即使 FDA 授权也不解除此算法限制。若客户需求后来包含外接卷，需要上游增加能力或贡献上游修复，不应在 Swift 另造扫描索引来绕开“底层全部基于 Fsearch”的约束。[扫描 L224–240](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/walk.rs#L224-L240)、[mount 标志 L394–397](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/walk.rs#L394-L397)、[增量 L225–245](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/live.rs#L225-L245)、[early scope L665–689](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/engine.rs#L665-L689)。

`Found` 提供名称路径、类型、大小、修改时间和分数，不提供创建时间、上次打开时间、UTType、本机图标、owner/group、权限或 inode。信息区需按选中项目惰性调用 macOS 元数据与预览 API；Finder 跳转/打开、面包屑、Quick Look 属于客户端能力，不改变上游索引算法。[结果 L46–54](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/engine.rs#L46-L54)。

**大小精度特别注意：** 基底索引小于 2 GiB 时精确，≥2 GiB 以 2 MiB 粒度向下编码；overlay 保留原大小。基底查询也对解码后的压缩大小作范围比较，因此大小列、筛选边界及相近大文件排序可能不同于实时元数据；详情显示精确字节应读取文件元数据。索引只记录文件逻辑长度，不能当作磁盘占用或目录递归汇总大小。[size 编码 L1221–1228](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/index.rs#L1221-L1228)、[筛选比较 L3484–3488](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/query.rs#L3484-L3488)、[结果转换 L367–379](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/engine.rs#L367-L379)、[属性 L313–319](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/walk.rs#L313-L319)。

## 7. Intel、发行与许可证

源码对 `aarch64` 使用 NEON/位掩码快路，其他架构有 scalar `Folded` 和一般 fuzzy 路径；`O_NOFOLLOW_ANY` 在 arm64，其他架构用 `O_NOFOLLOW`。这说明存在 Intel 编译意图和替代路径，**不等于 Intel 已构建、运行或性能等同验证**。[fuzzy cfg L1191–1205](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/query.rs#L1191-L1205)、[scalar L1269–1289](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/query.rs#L1269-L1289)、[nofollow L183–188](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/src/walk.rs#L183-L188)。

上游 release workflow 在 `macos-15` 构建，以 `target-cpu=apple-m1` 覆盖本机 CPU 配置，仅打包 `fsearch-aarch64-apple-darwin.tar.gz` 及 SHA256。它不是双架构 `.app`/DMG 工作流，也没有客户端签名、公证或安装包。项目 CI 需分别编译/测试 Rust 与 Swift 的 arm64、x86_64 slice，选择 universal 合并或分别出安装包，再完成签名、公证、Gatekeeper、干净系统安装和升级验证。普通提交可做 CI 构建，公开发布与 tag 的触发策略由本项目另行定义。[上游发行 L1–36](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/.github/workflows/release.yml#L1-L36)、[本机 CPU 配置 L1–2](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/.cargo/config.toml#L1-L2)。

上游 crate MIT 许可，发行成品应保留其版权与许可声明；版本和源码 pin 应在第三方依赖清单中可追溯。[Cargo 元信息 L1–6](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/Cargo.toml#L1-L6)、[MIT 声明 L1–13](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/LICENSE#L1-L13)。

## 8. 已验证事实与后续闸门

本次主会话在本机 Apple Silicon 环境执行上游 `cargo test --locked`，报告 **13 个 library + 9 个 binary 单元测试，共 22 个通过**。这是本次执行记录，不是上游 CI 或 Intel 证明；本研究任务没有运行全盘扫描。源码固定提交已通过 `git rev-parse HEAD` 核对。

尚未验证：Intel 编译/原生运行、Swift/C ABI、生产 `.app` 的 TCC/FDA、全盘首次索引和事件回放、大结果集完整性与内存、中文/emoji 质量、GUI/Quick Look/iCloud、签名公证和实际双架构安装包。

上游 README 的性能表为作者在 **M4 Mac mini、Linux/Chromium 源码语料**上的中位数数据，包括名称查询、内容首屏、索引体积和峰值内存。它们只能作为研究背景，不能承诺本应用端到端响应、首次索引耗时或内存；GUI、桥接、大小排序、中文和 Intel 都改变测量条件。[上游基准 L19–42](https://github.com/noahdunnagan/fsearch/blob/88e63fdf850cf7749deae8198b187accd21f8ba5/README.md#L19-L42)。

建议在正式实现前依次通过以下验证，结果写入项目测试记录：

1. **可控语料桥接 POC**：在项目内生成临时目录索引，不触发全盘 Engine；核验字面/前后缀/fuzzy/排除/大小/时间、中文和 NFC/NFD，以及当前结果集排序。百万级压力测试单独衡量完整抓取成本，禁止把小样本测试外推。
2. **双架构闸门**：arm64 与 x86_64 release 构建、链接和原生测试；核查 Intel 符号链接策略差异、时间/size 边界和同一数据文件兼容性。
3. **权限闸门**：签名 `.app` 在 FDA 关闭、允许、撤销、重新启动后的覆盖提示；允许访问不等于没有排除项，区分加载中、范围不覆盖和真实无结果。
4. **索引生命周期闸门**：经授权后在专用测试环境核验第一次构建、保存、重启、文件变更、目录删除、event loss 恢复、owner/follower 接管、内容预算续查和 iCloud 不下载。
5. **发行闸门**：可复现依赖 pin、arm64/x86_64 安装包、签名、公证、Gatekeeper、干净机器安装/升级与恢复。

以上为本项目的工程验证建议，不是声称上游已经实现的客户端功能。
