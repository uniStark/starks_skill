# Obsidian 跨项目记忆协议

本协议把 `$STARKS_MEMORY_DIR` 视为 Claude 与 Codex 共用的长期事实库。它不是默认上下文：没有当前任务的明确授权，就不接触记忆库；获得授权后，也只按候选路由和预算逐层加载。

## 稳定协议键

下列键供 Claude、Codex、prompt 与契约测试共同引用；自然语言可改写，键名和值不得静默改变：

```text
MEMORY_ZERO_ACCESS=true
MEMORY_READ_AUTH=MEMORY_READ_OPT_IN
MEMORY_DEEP_READ_AUTH=MEMORY_DEEP_READ_OPT_IN
MEMORY_WRITE_AUTH=MEMORY_WRITE_OPT_IN
MEMORY_SOURCE_OF_TRUTH=OBSIDIAN_MARKDOWN
MEMORY_NATIVE_MEMORY_POLICY=POINTERS_ONLY
MEMORY_INDEX_POLICY=HUMAN_ONLY
MEMORY_ROUTE_MAX_ITEMS=60
MEMORY_ROUTE_MAX_CHARS=1500
MEMORY_SUMMARY_MAX_FILES=3
MEMORY_SUMMARY_MAX_CHARS=4000
MEMORY_SUMMARY_MAX_EST_TOKENS=2500
MEMORY_DEEP_MAX_MEMORY_FILES=1
MEMORY_DEEP_MAX_MEMORY_CHARS=3000
MEMORY_HISTORY_MAX_FILES=2
MEMORY_TASK_MAX_FILES=5
MEMORY_TASK_MAX_CHARS=8000
MEMORY_TASK_MAX_EST_TOKENS=5000
MEMORY_FACT_SCHEMA=key,fact,status,verified_at,source,expires?
MEMORY_CURRENT_OBSERVATION_WINS=true
MEMORY_NEW_FILE_BASE_STATE=ABSENT
MEMORY_MISSING_TARGET_VALIDATION=PARENT_REALPATH
MEMORY_LEGACY_UNMATCHED_ORDER=LAST
```

## 零访问与任务级授权

- 默认不读、不写。未获得本任务的读取授权前，不得对记忆根目录执行 `Read`、`rg`、`ls`、`find`、`stat`，不得查看 frontmatter，也不得为了判断是否值得询问而预扫描。
- 询问读取授权时，必须提前说明：检索范围、只做元数据路由、普通读取预算，以及授权只在当前任务内有效。不能用环境变量已配置、历史授权或写入授权代替本次读取授权。
- 用户拒绝或没有明确同意时立即跳过；同一任务不得再次请求普通读取授权。
- 普通读取预算不足时，深度读取必须再次询问，并单独说明新增范围和预算。普通读取授权不自动包含深度读取。
- 读取授权与写入授权相互独立，任何读取结果都不能推定用户同意回写。

## 目录与事实源

```text
STARKS_MEMORY_DIR/
├── _index.md              # 仅供人类导航，机器永不读取，可过期
├── _shared/               # 真正跨项目、且不属于单一项目的事实
├── <project>/
│   ├── summary.md         # 短入口；项目元数据和项目关系的唯一事实源
│   ├── memory.md          # 稳定事实索引
│   └── history/           # 详细历史，默认不读取
└── private/               # 永不读取、列举或写入
```

`_index.md` 不参与机器召回，也不用于修正项目名。项目目录 basename 是定位旧项目的回退标识；canonical 项目标识和关系只来自 `summary.md` frontmatter。`_shared/` 不参与项目扫描，只保存真正共享的事实，不复制项目关系。

`STARKS_MEMORY_DIR` 下的 Markdown 是 Claude 与 Codex 唯一共享的长期事实源。Claude/Codex 平台原生 memory 最多保存 OB 条目指针，不复制、覆盖或独立裁决跨项目事实。

canonical frontmatter 只解释以下白名单字段：

```yaml
---
project: fly-oa
tags: [auth, invoice, admin]
related: [tuding-old, fly-dashboard]
depends_on: [feilianyun-infra]
status: active
updated: 2026-07-15
---
```

- `project` 是稳定项目名；`updated` 使用 `YYYY-MM-DD`。
- `tags`、`related`、`depends_on` 必须是单行内联数组。多行数组、错误类型或无法可靠解析的 frontmatter 必须标为“schema 不兼容”，不得静默漏召回或猜测关系。
- 白名单外字段不参与路由，也不得出现在路由输出中。
- `related` 按无向关系去重，但保留声明来源；`depends_on` 始终有向。
- frontmatter 是关系的唯一事实源，不通过正文 wikilink、`_index.md` 或目录邻近关系推导项目关系。

## 授权后的安全路由

获得普通读取授权后，按以下顺序执行；任一边界不明确都 fail-closed，停止相关访问并向用户说明。

1. 解析记忆根目录的物理路径。只访问其直接项目子目录；不跟随软链接。每个候选文件在访问前解析 realpath，结果必须仍位于物理根目录内。
2. 永远排除 `private/`、`_shared/`、`.obsidian/`、模板目录及其子路径，也不读取 `_index.md`。
3. 当前项目名取 repo 根目录 basename。先检查同名安全项目入口，再以稳定顺序检查其他直接子目录；最多处理 60 个项目元数据条目。达到上限必须报告还有多少条目未检查，不能把“未检查”表述成“无结果”。
4. canonical 项目只扫描 `*/summary.md` 的 frontmatter，不读取正文。没有 frontmatter 的直接项目目录只记录目录名并标为“未迁移”；存在但 schema 不兼容的 frontmatter 只报告不兼容，不使用其中的标签或关系。
5. 形成候选：当前项目；当前项目主动声明的 `related` / `depends_on`；其他项目指向当前项目的派生反向边；标签重叠项目；以及未迁移项目名。
6. 当前项目声明产生“直连”；其他项目声明当前项目产生“反向”。派生反向边必须携带 `edge_source=<声明项目>`，不能伪装成当前项目自己的声明。标签候选记录重叠数量。
7. 候选按“当前项目 > 直连 > 反向 > 标签重叠数量 > `updated` 较新”排序，再以项目名稳定排序。无日期候选排在同级有有效日期的候选之后；没有当前、关系或标签匹配的未迁移候选排在所有 canonical 匹配候选之后。

元数据路由输出最多 60 个项目条目、1500 个 Unicode 字符，只包含项目名、匹配原因、关系方向/声明来源、更新时间和迁移状态。扫描时看到的正文、未知 frontmatter 字段和文件系统细节不得带入上下文。

普通正文选择遵循以下限制：

- 最多加载 3 个 `summary.md`；优先当前项目，再按候选排序加载。
- summary 正文合计不超过 4000 个 Unicode 字符。
- 元数据路由输出与 summary 注入合计估算不超过 2500 token；估算公式为 `CJK 字符数 × 1.0 + 其他字符数 ÷ 4`，任一上限先到即停止。
- 元数据输出不计入“正文 4000 字符”，但计入普通 token 预算和全任务累计预算。
- 未迁移或 schema 不兼容的项目，只有它是当前项目或被 canonical 当前项目直接点名为 `related` / `depends_on` 时，才允许加载 `summary.md` 正文；不得自动迁移或修补。
- 发生候选、字符、token 或文件数截断时，明确报告采用的上限、已加载项，以及未读取候选数量。

`_shared/` 不参与自动扫描。只有用户在授权范围中明确点名共享主题，或已加载 summary 明确指向一个安全共享文件且原授权覆盖 `_shared/` 时，才可读取对应文件；它计入正文、文件数、字符和 token 预算。否则先请求深度读取授权。

## 深度读取

summary 不足以完成任务时，说明缺少什么并再次询问。获得深度读取授权后：

- 最多展开 1 个候选项目的 `memory.md`，正文不超过 3000 个 Unicode 字符。
- `history/` 默认永不读取；只有用户明确要求回顾历史时，最多读取 2 个明确相关的历史文件。
- 从普通路由开始计算，整个任务最多注入 5 个正文文件、8000 个 Unicode 字符、约 5000 估算 token，任一上限先到即停止。frontmatter 元数据扫描本身不计正文文件数，但实际输出的路由文本计入字符与 token 累计。
- 深度授权仍受原始作用域约束；需要新项目或新目录时再次说明，不得自行扩大范围。

## 事实解释与输出

- 事实冲突优先级固定为：当前任务直接观察 > 未过期的 `verified` > `assumption` > `deprecated`。同级冲突以 `verified_at` 较新者优先，但易变化的配置、路径、版本和运行状态仍须现场验证。
- 读取事实表时保留事实自身的 `source`、`verified_at`、`status`、`expires`；它们与候选关系的 `edge_source` 是不同概念，不得混淆。
- 过期的 `verified` 按 `assumption` 使用；`assumption` 只能作为待验证线索，`deprecated` 不作为正向证据。记忆与现场冲突时，以现场为准；没有单独写入授权，只报告冲突，不回写。
- 结果必须列出实际读取的文件、预算使用、截断情况和记忆影响；不得把未读取候选概括成已检查事实。
