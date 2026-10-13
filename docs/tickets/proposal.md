# Fsearch Desktop Tickets 拆分草案

状态：**用户已确认粒度与 55 条阻塞边，33 张执行 Tickets 已发布**。本文件保留批准的拆分记录；实际 Issue 编号与执行入口见 [Tickets 索引](README.md)。提案基于全部 14 个 Spec 的正文和评论（读取时评论为空）。

每张 Ticket 已单独发布为对应 Spec 的原生子 Issue，使用 ready-for-agent 和原生阻塞关系；本次不编辑或关闭现有 Spec 正文、状态和标签。这里是审批记录，不是把所有 Tickets 合成一个实施任务。

## 拆分原则与前置

- 仓库尚无应用代码，不需要 prefactoring；T01 直接建立最小可验证用户路径。
- 每票从用户/维护者输入走到实际结果、可见界面或 CI 产物，并自带公开行为测试和必要原生冒烟；不单列 Rust、C ABI 或 Swift UI 水平层任务。
- 主测试接缝沿用已确认的 Swift 侧引擎服务；权限、系统动作、实际安装和发行补必要原生/成品证据。
- M1 验证窗口可以先逐步推进；完整 alpha 主界面由 T10 明确等待 M1 门禁。
- Spec 级依赖是整体能力验收顺序；Ticket 边只指向真正需要的前置能力，不把自身父 Spec 的关闭状态设为前置，避免父子循环。完成某个切片不等于父 Spec 已全部满足，跨规格覆盖在此索引中记录。
- 签名身份、Intel 实机、macOS 13 与专用权限环境为外部验收条件，缺失时对应 Ticket 保持未验证，其他无真实依赖的任务可继续。
- T22 可先交付标记明确的开发/验证包，T28 可先验证签名链路；完整 alpha 和正式发行分别由 T27、T29 守门。

## 编号列表

### 1. T01：最小原生窗口完成一次真实 Fsearch 样本查询

**Parent Spec：** [#2](https://github.com/wynnok/fsearch-desktop/issues/2) [SPEC-01] M1：可升级 Fsearch 集成与 Swift 引擎服务契约。

**Blocked by：** 无，可立即开始。

**What to build：** 打开原生验证窗口，输入文件名，经 Swift 引擎服务与薄桥接调用 Fsearch 的受控样本，显示可核对的真实匹配结果。

**Acceptance criteria：**

- [ ] 项目范围构建可复现，上游版本固定且与适配代码分开，许可证可追溯。
- [ ] 输入→公开服务→Fsearch→原生结果的完整路径可演示，不能以硬编码列表代替。
- [ ] 受控样本、缓存和产物留在项目内；未启动真实 Engine 时明确标注样本验证模式，不宣称 Engine 已验证。
- [ ] 窗口能显示成功、无匹配及查询失败，测试从 Swift 侧公开契约核对外部结果。
- [ ] 定义用于后续切片的最小请求、结果、状态和内存归属契约，不复制上游匹配算法。

### 2. T02：普通名称、Unicode 与错误查询可安全往返

**Parent Spec：** [#2](https://github.com/wynnok/fsearch-desktop/issues/2) [SPEC-01] M1：可升级 Fsearch 集成与 Swift 引擎服务契约。

**Blocked by：** T01。

**What to build：** 用户输入中文、emoji、空格和冒号时得到正确结果；非法查询给出可恢复错误，重复搜索不会因跨语言边界泄漏或崩溃。

**Acceptance criteria：**

- [ ] 普通输入保留标点数据含义，与明确启用的高级语义分开。
- [ ] 通过同一公开服务与原生窗口验证 Unicode、组合字符、空/非法请求及错误恢复。
- [ ] 重复查询及释放观测资源，结果归属和释放责任明确；Rust panic 不跨越 FFI 边界。
- [ ] 错误后继续正常查询可成功，诊断不原样泄露真实路径或正文。

### 3. T03：完整名称快照支持自然排序和跨页浏览

**Parent Spec：** [#3](https://github.com/wynnok/fsearch-desktop/issues/3) [SPEC-02] M1：完整结果快照、全局排序与分页。

**Blocked by：** T01。

**What to build：** 用户按名称自然顺序浏览完整匹配集合，下一页仍属于同一结果快照，数量与完整性准确。

**Acceptance criteria：**

- [ ] 至少 25,001 个匹配按独立预期集合核对，无遗漏、重复，不依赖旧 JSON 分页上限。
- [ ] 名称升降序、数字自然顺序、同名路径稳定次序、中文和重音案例通过。
- [ ] 滚动或继续加载使用同一快照；刷新/查询改变不能混用旧页。
- [ ] 完整总数仅在完整集合有证据时展示；限制导致部分结果必须显式标识，不能冒充满足全局排序。
- [ ] 服务测试及原生验证窗口共同展示分页和最终排序；记录较大样本的时间与峰值内存。

### 4. T04：按索引大小与修改时间全局排序

**Parent Spec：** [#3](https://github.com/wynnok/fsearch-desktop/issues/3) [SPEC-02] M1：完整结果快照、全局排序与分页。

**Blocked by：** T03。

**What to build：** 点击大小或修改时间列，可对完整结果升降序排列，并理解大文件的索引精度。

**Acceptance criteria：**

- [ ] 完整快照中按索引大小、修改时间升降序和同值路径稳定性通过跨页验证。
- [ ] 大小字段说明采用索引大小，不表示目录递归占用。
- [ ] 覆盖 2 GiB 编码边界，不以实际大小偷偷替换上游筛选语义。
- [ ] 排序结果由统一服务交付，原生窗口显示对应列头方向及完成状态。

### 5. T05：长查询和排序期间输入仍可用

**Parent Spec：** [#3](https://github.com/wynnok/fsearch-desktop/issues/3) [SPEC-02] M1：完整结果快照、全局排序与分页。

**Blocked by：** T03。

**What to build：** 排序较慢时用户可以继续改关键词；新查询结果不会被晚返回的旧请求覆盖。

**Acceptance criteria：**

- [ ] 显示查询/排序中状态，期间输入、选择及窗口交互保持可用。
- [ ] 人为安排快慢请求，旧结果、旧计数和旧分页不能覆盖新请求。
- [ ] 临时顺序和数量不标成最终结果；失败或取消后仍可发起正常查询。
- [ ] 通过公开服务与原生窗口测量响应、主线程行为和大集合资源，而非只验证防抖代码。

### 6. T06：最小查询应用在两芯片和最低系统运行

**Parent Spec：** [#4](https://github.com/wynnok/fsearch-desktop/issues/4) [SPEC-04] M1：双架构构建、链接与最低系统验证。

**Blocked by：** T01。

**What to build：** 同一最小原生查询应用可以在 arm64、x86_64 和 macOS 13 目标环境构建、链接并完成样本查询。

**Acceptance criteria：**

- [ ] Swift 与内置 Rust 的架构一致，核验最终可执行产物和依赖切片。
- [ ] 使用兼容基线 CPU 参数及最低系统目标，不沿用构建机器特有指令。
- [ ] 构建、样本查询和启动证据覆盖两架构；跨编译、Rosetta、Intel 实机与最低系统实测分开记录。
- [ ] 目标准备与缓存在项目/隔离环境中完成，不改变工作站全局工具链。
- [ ] 缺少真实设备时保留未验证门禁，不把构建成功当运行成功。

### 7. T07：真实 Engine 完成独立索引、通知与退出恢复

**Parent Spec：** [#2](https://github.com/wynnok/fsearch-desktop/issues/2) [SPEC-01] M1：可升级 Fsearch 集成与 Swift 引擎服务契约；同时覆盖 [#5](https://github.com/wynnok/fsearch-desktop/issues/5) 的相关验收。

**Blocked by：** T01。

**What to build：** 验证窗口切换到真实 Engine，使用客户端独立索引回答查询；文件变化可收到通知，关闭重开及退出恢复有真实证据。

**Acceptance criteria：**

- [ ] 启动前证明扫描限制策略或使用专用环境，不能把 home、数据目录或查询范围当成索引 root。
- [ ] 独立索引与已有 CLI 数据/进程分离；真实 Engine 查询不能仅用 Searcher 通过来替代。
- [ ] 目录增删改经过同一服务的变更通知可验证，索引保存及再启动查询恢复有证据。
- [ ] 关闭验证窗口仍维护索引，重开可查；退出结束自身应用，重复实例行为与索引锁正确。
- [ ] 保留上游默认名称/内容索引机制，不擅自拆复制或切换 helper。

### 8. T08：实际签名应用验证授权前后的索引覆盖

**Parent Spec：** [#5](https://github.com/wynnok/fsearch-desktop/issues/5) [SPEC-03] M1：真实 Engine 生命周期、权限与资源验证。

**Blocked by：** T07。

**What to build：** 在专用环境中验证跳过、授予、撤销完全磁盘访问权限后的真实搜索结果，用户不会把受限覆盖当无匹配。

**Acceptance criteria：**

- [ ] 测试主体为实际签名应用，签名身份和测试环境作为明确外部前置。
- [ ] 受保护位置授权前后、撤销、重启/重新检查的结果及状态可解释。
- [ ] 不只依据 full_disk_access 字段宣称全部可读，测试不程序化修改系统权限。
- [ ] 索引不自动下载 iCloud 占位文件；本地缺失与不可读说明准确。
- [ ] 缺少签名条件时其他独立工作可继续，但本票权限门禁不得关闭。

### 9. T09：默认索引的初建与空闲资源可测量

**Parent Spec：** [#5](https://github.com/wynnok/fsearch-desktop/issues/5) [SPEC-03] M1：真实 Engine 生命周期、权限与资源验证。

**Blocked by：** T07。

**What to build：** 维护者获得真实默认名称/内容索引的初建、查询、常驻和空闲成本报告，能决定是否需要推动上游控制选项。

**Acceptance criteria：**

- [ ] 报告设备、OS、版本、数据规模、命令、初建耗时、索引体积、峰值 RSS 和空闲 CPU/后台资源。
- [ ] 合成查询、真实首次扫描和空闲状态分开，不把上游 top-k 数字当客户端保证。
- [ ] 说明 v0.1 名称入口仍可能后台读取合规文本，明确实际覆盖和成本。
- [ ] 资源不合格时给出证据与上游方案，不以复制内核或隐藏结果限制假装通过。

### 10. T10：原生主窗口提供名称模式和真实结果交互

**Parent Spec：** [#6](https://github.com/wynnok/fsearch-desktop/issues/6) [SPEC-05] v0.1：原生搜索配置与结果列表交互。

**Blocked by：** T02、T04、T05、T06、T08、T09。

**What to build：** M1 门禁后，用户通过完整原生主窗口按包含、模糊、前缀、后缀或完整名称搜索，切换排序并操作结果。

**Acceptance criteria：**

- [ ] SwiftUI + AppKit 呈现搜索配置、结果和检查器区域，原生菜单/焦点/选择可用，视觉不照抄参考。
- [ ] 包含默认不区分大小写并按名称自然升序，模糊默认关联性；保留用户主动选择的排序。
- [ ] 空输入无有效筛选时显示提示，不查询排序全部文件。
- [ ] 真实服务结果、分页、查询/排序中、错误和无匹配状态可见；禁止把 mock 窗口当 alpha。
- [ ] M1 实际门禁证据具备；键盘、深浅模式和基本 VoiceOver 行为通过原生冒烟。

### 11. T11：搜索范围与隐藏项可直观切换

**Parent Spec：** [#6](https://github.com/wynnok/fsearch-desktop/issues/6) [SPEC-05] v0.1：原生搜索配置与结果列表交互。

**Blocked by：** T10。

**What to build：** 用户在所有已覆盖内置位置、个人目录或选定文件夹之间切换，并能显式显示/隐藏隐藏项。

**Acceptance criteria：**

- [ ] 默认所有已覆盖内置磁盘位置且隐藏项可见，系统目录不额外静默排除。
- [ ] 原生文件夹选择、个人目录及当前范围状态可用，切换后查询和计数同步。
- [ ] 隐藏项可见性不删除索引条目，切换不能混入旧快照。
- [ ] 不能覆盖的外接/网络卷明确解释；选文件夹不等于新建索引或取得权限。
- [ ] 真实样本核对范围、隐藏项与跨页结果。

### 12. T12：类型、扩展名、大小和时间筛选可组合

**Parent Spec：** [#6](https://github.com/wynnok/fsearch-desktop/issues/6) [SPEC-05] v0.1：原生搜索配置与结果列表交互。

**Blocked by：** T10。

**What to build：** 用户用普通语言组合属性筛选，也可不输入名字直接按条件查找并清除条件。

**Acceptance criteria：**

- [ ] 文件/目录、扩展名、索引大小与修改时间范围通过同一服务映射上游语义。
- [ ] 用户设置的有效筛选可单独发起查询；默认范围/隐藏项不单独触发全量查询。
- [ ] 支持逐项和全部清除，错误保留条件并解释原因。
- [ ] 覆盖组合、边界、无匹配、大小精度与分页，不能在 UI 单页后过滤冒充完整结果。

### 13. T13：文件变化自动刷新并保持选择

**Parent Spec：** [#6](https://github.com/wynnok/fsearch-desktop/issues/6) [SPEC-05] v0.1：原生搜索配置与结果列表交互；同时覆盖 [#3](https://github.com/wynnok/fsearch-desktop/issues/3) 的相关验收。

**Blocked by：** T10。

**What to build：** 当前查询中的新增、改名、删除和属性变化自动合并刷新，用户选中文件和可视位置尽量保持稳定。

**Acceptance criteria：**

- [ ] 复用上游服务变更通知，不增建另一套文件系统监视/索引。
- [ ] 新快照按当前查询和排序生成，不混用旧页；刷新期间输入与选择可用。
- [ ] 按路径恢复选择并尽量保留滚动位置，所选文件消失时给出原因。
- [ ] 原生交互与真实受控变化验证连续变更、排序字段变化和晚返回刷新。

### 14. T14：可跳过权限引导与清楚的索引状态

**Parent Spec：** [#8](https://github.com/wynnok/fsearch-desktop/issues/8) [SPEC-07] v0.1：权限引导、索引状态与窗口生命周期。

**Blocked by：** T10。

**What to build：** 首次用户可以跳过授权先搜索已有覆盖，以后通过指引和重新检查改善覆盖，并分清索引中、受限、无结果与失败。

**Acceptance criteria：**

- [ ] 权限解释、跳过、后续授权指引和重新检查入口均可操作，不自动改系统权限。
- [ ] 名称就绪与内容后台工作分开显示，不伪造百分比或完成时间。
- [ ] 基于 M1 权限证据验证受限覆盖与无结果/错误不同，错误后可重试。
- [ ] 默认内容索引行为和云端缺失可理解，状态更新不打断输入。

### 15. T15：检查器联动当前选择显示真实文件信息

**Parent Spec：** [#7](https://github.com/wynnok/fsearch-desktop/issues/7) [SPEC-06] v0.1：检查器、Quick Look 与 Finder 路径导航。

**Blocked by：** T10。

**What to build：** 选择结果后立即显示已知信息，并按需加载图标、类型、实际大小和创建/修改时间。

**Acceptance criteria：**

- [ ] 异步信息返回必须对应当前选择，快速切换不会显示上一文件详情。
- [ ] 未知/不可读显示明确状态，目录大小不冒充递归占用。
- [ ] 索引大小与实际大小差异可解释；应用包、链接、多选诚实呈现。
- [ ] 受控真实文件和选择晚返回测试通过，图标/属性读取并发有界。

### 16. T16：打开文件、Finder 显示与逐级路径导航

**Parent Spec：** [#7](https://github.com/wynnok/fsearch-desktop/issues/7) [SPEC-06] v0.1：检查器、Quick Look 与 Finder 路径导航。

**Blocked by：** T10。

**What to build：** 用户能双击/回车打开结果、在 Finder 显示、复制路径，并点击底部任一级祖先文件夹打开对应位置。

**Acceptance criteria：**

- [ ] 选中路径→原生系统动作→实际目标完整可演示，文件夹打开与显示文件本身明确区分。
- [ ] 长路径可折叠但所有祖先仍可访问，完整路径可复制。
- [ ] 根目录、同名、链接、应用包、移动删除和权限失败均有可理解行为。
- [ ] 使用系统文件操作，不新增移动、删除、重命名等文件管理功能。

### 17. T17：空格 Quick Look 可预览所选文件

**Parent Spec：** [#7](https://github.com/wynnok/fsearch-desktop/issues/7) [SPEC-06] v0.1：检查器、Quick Look 与 Finder 路径导航。

**Blocked by：** T10。

**What to build：** 用户按空格预览当前选择，切换选择或关闭预览时目标一致，系统不支持或文件消失时能理解失败。

**Acceptance criteria：**

- [ ] Quick Look、Escape、选择切换与焦点行为通过原生冒烟。
- [ ] 快速切换不预览旧对象；不可访问/已删除文件给出清楚说明。
- [ ] 预览支持格式不作为内容搜索能力宣称；后台索引不借预览自动批量下载云文件。
- [ ] 保留已有搜索与系统打开操作，必要回归在同一用户流程验证。

### 18. T18：主窗口关闭、重开与退出符合约定

**Parent Spec：** [#8](https://github.com/wynnok/fsearch-desktop/issues/8) [SPEC-07] v0.1：权限引导、索引状态与窗口生命周期。

**Blocked by：** T10。

**What to build：** 红色按钮只关闭主窗口，重开恢复运行中的查询和选择；⌘Q 才结束客户端，开机启动默认关闭。

**Acceptance criteria：**

- [ ] 主窗口关闭后真实引擎持续运行，重开可恢复当前进程的输入与选择。
- [ ] 退出结束自身应用及其引擎，不结束外部 CLI；再启动独立索引正常。
- [ ] 默认不安装登录任务，菜单行为可发现。
- [ ] 用户流程验证与 M1 生命周期报告一致，不只断言某个回调返回值。

### 19. T19：本地设置保留且查询历史默认不落盘

**Parent Spec：** [#9](https://github.com/wynnok/fsearch-desktop/issues/9) [SPEC-08] v0.1：本地设置、主动诊断导出与手动更新入口。

**Blocked by：** T18。

**What to build：** 应用重启后恢复必要偏好，但不默认持久保存查询历史；关窗重开中的当前输入只保留在进程内。

**Acceptance criteria：**

- [ ] 设置与查询历史明确分开，无账号或远程同步。
- [ ] 重启与关窗重开分别验证偏好持久化和运行中输入保留。
- [ ] 默认查询历史不会因日志、设置或导出旁路落盘。
- [ ] 测试外部行为，不固定内部存储格式或增加未确认的保存查询功能。

### 20. T20：主动诊断导出默认剔除路径和正文

**Parent Spec：** [#9](https://github.com/wynnok/fsearch-desktop/issues/9) [SPEC-08] v0.1：本地设置、主动诊断导出与手动更新入口。

**Blocked by：** T14。

**What to build：** 用户主动导出诊断前知道包含什么，生成可排障但默认不含完整文件路径或内容的报告。

**Acceptance criteria：**

- [ ] 导出为用户显式动作，保留可用版本、架构、系统和错误类别。
- [ ] 上游 stderr、Unicode、多行和标点路径样本经过脱敏，不原样打包。
- [ ] 检查最终导出文件而非仅检查脱敏函数，完整路径/正文不会泄露。
- [ ] 失败说明不被脱敏掩盖，无自动上传或默认查询历史记录。

### 21. T21：显示客户端/引擎版本并提供手动更新入口

**Parent Spec：** [#9](https://github.com/wynnok/fsearch-desktop/issues/9) [SPEC-08] v0.1：本地设置、主动诊断导出与手动更新入口。

**Blocked by：** T10。

**What to build：** 用户从 About 或菜单了解版本，检查更新后可打开可信下载入口并自行更新。

**Acceptance criteria：**

- [ ] 当前客户端和上游固定版本可追溯，更新入口与 Releases 下载链接可用。
- [ ] 没有新版本或网络失败时诚实反馈，不伪造更新、不阻塞搜索。
- [ ] 检查动作不自动替换应用或已加载引擎。
- [ ] 原生冒烟与受控更新响应验证结果及错误行为。

### 22. T22：两架构开发 DMG 可经 push/PR 下载验证

**Parent Spec：** [#10](https://github.com/wynnok/fsearch-desktop/issues/10) [SPEC-09] DevOps：可安装开发 DMG 与持续集成；同时覆盖 [#4](https://github.com/wynnok/fsearch-desktop/issues/4) 的相关验收。

**Blocked by：** T06。

**What to build：** 普通 push/PR 自动产出可安装开发 DMG；测试者下载、安装并完成当时已实现的查询切片。

**Acceptance criteria：**

- [ ] 复用项目构建入口，核对主程序/内置引擎架构、版本、许可证和最终 SHA-256。
- [ ] 真实 CI 和安装→启动→查询→退出路径有证据，失败不产出成功标记。
- [ ] 早期包明确标注开发/验证状态，完整 alpha 尚未具备时不得冒充成品验收通过。
- [ ] 工作流以后自动携带已合并能力；不需要等所有 UI 功能完成才建立下载链路。
- [ ] 不运行 CLI install 或修改系统设置，缺签名条件可标明未公证，不发布 stable。

### 23. T23：每日检测上游正式版并给出可追溯结果

**Parent Spec：** [#11](https://github.com/wynnok/fsearch-desktop/issues/11) [SPEC-11] Maintenance：每日上游检测与升级 PR 兼容性门禁。

**Blocked by：** T01。

**What to build：** 维护者能看到每日检测的无更新、新候选或失败结果，确认客户端跟进的是正式版本而非滚动主线。

**Acceptance criteria：**

- [ ] 正式 Release/tag 选择和候选 commit 明确，不选预发布或滚动 main 作为正式依赖。
- [ ] 无更新无改动；网络失败保留现有版本并可重试，不伪造发行。
- [ ] 真实仓库作业和受控发行列表核对选择逻辑，结果包含现用/候选版本。
- [ ] 实现于仓库 CI，不建立无关 Codex 定时任务，本票尚不自动合并/发行。

### 24. T24：新正式版生成去重的升级 PR 并跑兼容检查

**Parent Spec：** [#11](https://github.com/wynnok/fsearch-desktop/issues/11) [SPEC-11] Maintenance：每日上游检测与升级 PR 兼容性门禁。

**Blocked by：** T02、T04、T05、T08、T09、T22、T23。

**What to build：** 发现新版本后维护者获得一个可审核的升级 PR，附查询、架构、索引恢复和资源检查结果及临时补丁评估。

**Acceptance criteria：**

- [ ] 依赖和锁定记录固定候选 commit；重复检测复用既有 PR，不重复开单。
- [ ] 复用已验证服务和构建入口运行兼容检查，相关权限/资源/格式变化有证据或明确未验证项。
- [ ] 临时补丁记录来源、测试与移除条件，升级时逐项评估；没有补丁时不人为制造。
- [ ] 失败保留候选与诊断但不自动合并或发 stable，维护者合并后由版本 tag 发版。
- [ ] 用受控无更新、候选、重复、网络和兼容失败验证完整检测→变更→PR→检查路径。

### 25. T25：验收搜索到排序刷新的完整旅程并产出指南

**Parent Spec：** [#12](https://github.com/wynnok/fsearch-desktop/issues/12) [SPEC-12] v0.1：端到端验收、用户文档与已知限制。

**Blocked by：** T11、T12、T13、T14。

**What to build：** 测试者走完输入、模式、范围、属性筛选、全局排序、分页和变化刷新，用户获得对应搜索与权限说明。

**Acceptance criteria：**

- [ ] 真实应用验证空态、标点、Unicode、隐藏项、仅筛选、跨页、晚返回、错误及权限受限。
- [ ] 复用公开服务回归，补必要原生旅程，不能以模块通过代替流程通过。
- [ ] 指南与实际行为一致，说明索引大小、覆盖限制和默认后台内容索引。
- [ ] 结果、问题和未验证项可追溯，不重复跑无理由的宽泛测试或声称未测性能。

### 26. T26：验收文件操作和本地数据旅程并产出指南

**Parent Spec：** [#12](https://github.com/wynnok/fsearch-desktop/issues/12) [SPEC-12] v0.1：端到端验收、用户文档与已知限制。

**Blocked by：** T15、T16、T17、T19、T20、T21。

**What to build：** 测试者从结果选择完成详情、预览、Finder 导航、关窗恢复、诊断和更新入口，用户获得实际操作与数据说明。

**Acceptance criteria：**

- [ ] 真实文件旅程覆盖同名、长路径、链接、应用包、多选、删除、不可读和晚返回。
- [ ] 设置/历史默认策略、诊断成品脱敏和手动更新行为与文档一致。
- [ ] 用户指南说明窗口关闭/退出、数据位置含义与清理边界；不擅自清除用户索引。
- [ ] 原生动作证据和问题清单齐全，不新增文件管理、保存查询或自动更新功能。

### 27. T27：从开发 DMG 完成两芯片 alpha 安装验收

**Parent Spec：** [#12](https://github.com/wynnok/fsearch-desktop/issues/12) [SPEC-12] v0.1：端到端验收、用户文档与已知限制；同时覆盖 [#10](https://github.com/wynnok/fsearch-desktop/issues/10) 的相关验收。

**Blocked by：** T24、T25、T26。

**What to build：** 在真实开发安装包上完成完整 v0.1 用户旅程，给出支持矩阵、已知限制、版本与资源报告，明确 alpha 是否可交付。

**Acceptance criteria：**

- [ ] 下载→安装→授权/跳过→搜索/筛选/排序→详情/预览/Finder→关闭/重开/退出→更新入口全部按真实产物核对。
- [ ] 核对 macOS 13+ 与两架构证据、M1 门禁、上游升级通路、许可/哈希和诊断策略。
- [ ] 缺失 P0 或未通过技术门禁不得标 alpha 全部完成，未验证/失败分别记录。
- [ ] 公开支持指南、已知限制与报告，未公证 alpha 明确标识，不代替公众发行证明。

### 28. T28：开发安装包可完成签名、公证和最终校验

**Parent Spec：** [#13](https://github.com/wynnok/fsearch-desktop/issues/13) [SPEC-10] Release：签名公证、版本 tag 与正式安装验收。

**Blocked by：** T22。

**What to build：** 在签名条件具备时，将实际开发包走完签名、公证、staple 和干净环境启动验证，失败时可排障且不泄露凭据。

**Acceptance criteria：**

- [ ] Developer ID 和公证条件作为明确外部前置；签嵌套组件后签主应用，完成后不改内容。
- [ ] 真实公证 Accepted、staple 与最终 codesign/spctl 和安装启动证据齐全，模拟成功不算通过。
- [ ] 凭据仅安全配置使用，临时签名环境清理，缺凭据/拒绝不会泄露秘密或报告成功。
- [ ] 本票只建立验证链路，不未经批准发布公众版本；缺外部条件保留门禁。

### 29. T29：已批准版本 tag 发布可下载正式 Release

**Parent Spec：** [#13](https://github.com/wynnok/fsearch-desktop/issues/13) [SPEC-10] Release：签名公证、版本 tag 与正式安装验收。

**Blocked by：** T27、T28。

**What to build：** 维护者明确发出版本 tag 后，完整检查自动发布签名公证 DMG、哈希、许可和说明，用户能从 Releases 下载并安装。

**Acceptance criteria：**

- [ ] 复用 alpha 验收和真实签名链路，任一检查失败阻止正式发行。
- [ ] 一次已批准 tag 的完整运行及可下载资产、版本/引擎记录、哈希与安装证据可追溯。
- [ ] 普通 push 不覆盖 stable，不自动重写公开 tag 或替换历史包。
- [ ] 缺签名/设备证据不以 workflow 分支存在宣称公众发行完成。

### 30. T30：普通文本查询显示按文件分组的匹配行

**Parent Spec：** [#14](https://github.com/wynnok/fsearch-desktop/issues/14) [SPEC-13] v0.2：受支持文本内容搜索与匹配片段。

**Blocked by：** T27。

**What to build：** v0.2 用户从明确的文本内容入口输入普通文字，通过 Fsearch 找到受支持文件及其匹配行，并沿用已有文件动作。

**Acceptance criteria：**

- [ ] 同一引擎服务调用公开 Grep，不复制内容索引或匹配算法。
- [ ] 一文件一结果，文件数量与内容匹配分开，来源/限制准确，基础片段可见。
- [ ] 真实文本、Unicode、CRLF、无匹配、修改正文与现有打开/预览动作验证通过。
- [ ] 说明只支持上游合规文本，PDF/Office/OCR、压缩包和云端缺失不冒充可搜；片段不默认进诊断。

### 31. T31：内容范围、属性、正则与大小写选项可用

**Parent Spec：** [#14](https://github.com/wynnok/fsearch-desktop/issues/14) [SPEC-13] v0.2：受支持文本内容搜索与匹配片段。

**Blocked by：** T30。

**What to build：** 用户在内容查询中复用范围/筛选，并明确选择正则和大小写方式，错误保留输入便于修正。

**Acceptance criteria：**

- [ ] 请求条件经同一公开契约映射上游，范围/属性与正文模式不会误用名称 offset。
- [ ] 真实样本验证 literal/regex、大小写、过滤组合与无匹配，非法正则可恢复。
- [ ] 受支持文本准入/忽略/大小规则说明与实际结果一致，不新增文档解析。
- [ ] 用户交互可发现且不破坏既有名称搜索和文件动作。

### 32. T32：内容预算续查和 Unicode 高亮保持正确

**Parent Spec：** [#14](https://github.com/wynnok/fsearch-desktop/issues/14) [SPEC-13] v0.2：受支持文本内容搜索与匹配片段。

**Blocked by：** T30。

**What to build：** 内容搜索预算耗尽时用户可继续，匹配高亮对中文/emoji 正确，部分结果不会被显示为全部匹配。

**Acceptance criteria：**

- [ ] 按上游内容 cursor 续查，不与名称 offset 混用，文件/匹配计数不混淆。
- [ ] 结合 complete、next、来源和预算判断未完成，停止/继续状态可理解。
- [ ] UTF-8 字节范围安全转为原生文本范围，覆盖组合字符、emoji 和截断片段。
- [ ] 查询改变或晚返回续查不会覆盖新查询，真实受控数据验证无错页与错误高亮。

### 33. T33：验收 v0.2 文本旅程与边界说明

**Parent Spec：** [#14](https://github.com/wynnok/fsearch-desktop/issues/14) [SPEC-13] v0.2：受支持文本内容搜索与匹配片段。

**Blocked by：** T31、T32。

**What to build：** 测试者走完文本查询、模式/范围、匹配片段、预算续查和文件动作，用户获得准确的文本搜索说明。

**Acceptance criteria：**

- [ ] 真实应用覆盖普通/正则/大小写、Unicode、CRLF、文件更新、非法模式与续查。
- [ ] 文件数量、内容匹配、complete/next 和扫描来源的语义与上游一致且可理解。
- [ ] 指南公开文本类型、大小/忽略规则、直接扫描限制与云端缺失；预览能力不算正文检索能力。
- [ ] 诊断无默认片段泄露，名称搜索回归正常，不加入未确认的 beta 扩展。

## Spec 覆盖索引

| Spec | 拆出的 Tickets（含交叉验收） |
| --- | --- |
| [#2](https://github.com/wynnok/fsearch-desktop/issues/2) | T01、T02、T07 |
| [#3](https://github.com/wynnok/fsearch-desktop/issues/3) | T03、T04、T05、T13 |
| [#4](https://github.com/wynnok/fsearch-desktop/issues/4) | T06、T22 |
| [#5](https://github.com/wynnok/fsearch-desktop/issues/5) | T07、T08、T09 |
| [#6](https://github.com/wynnok/fsearch-desktop/issues/6) | T10、T11、T12、T13 |
| [#7](https://github.com/wynnok/fsearch-desktop/issues/7) | T15、T16、T17 |
| [#8](https://github.com/wynnok/fsearch-desktop/issues/8) | T14、T18 |
| [#9](https://github.com/wynnok/fsearch-desktop/issues/9) | T19、T20、T21 |
| [#10](https://github.com/wynnok/fsearch-desktop/issues/10) | T22、T27 |
| [#11](https://github.com/wynnok/fsearch-desktop/issues/11) | T23、T24 |
| [#12](https://github.com/wynnok/fsearch-desktop/issues/12) | T25、T26、T27 |
| [#13](https://github.com/wynnok/fsearch-desktop/issues/13) | T28、T29 |
| [#14](https://github.com/wynnok/fsearch-desktop/issues/14) | T30、T31、T32、T33 |

## 审批与发布记录

用户已确认粒度、依赖并批准逐票发布，33 张执行 Tickets 已创建；没有开始实现或 Git 提交。原 Spec 正文和状态保持不变，执行时以 Tickets 索引及 GitHub 原生阻塞关系为准。

