# mindstudio-skills

Ascend 性能调优 Skill 套件。它把 Profiler 数据校验、集群全局初筛、时间线异常发现、计算/通信/调度专项下钻、Host CPU 绑核、Profiler DB 查询和单算子调优组织成一条证据优先的分析链。

入口 Skill：

- `ascend-performance-orchestrator/SKILL.md`
- `Ascend Performance Orchestrator.md`

推荐从 `ascend-performance-orchestrator` 入口使用，除非你已经明确知道要调用某个专项 Skill。

## 一键安装到 TRAE IDE 项目

TRAE IDE 的项目级 Skill 目录约定为：

```text
<项目根目录>/
└── .trae/
    └── skills/
        ├── ascend-performance-orchestrator/
        │   └── SKILL.md
        ├── ascend-computation-analysis/
        │   └── SKILL.md
        └── ...
```

本仓库提供一键安装脚本，会把当前套件中所有包含 `SKILL.md` 的 Skill 目录复制到目标项目根目录的 `.trae/skills/` 下，并同步复制：

- `README.md` 到 `.trae/skills/README.md`
- `Ascend Performance Orchestrator.md` 到 `.trae/skills/Ascend Performance Orchestrator.md`
- `Ascend Performance Orchestrator.md` 到 `.trae/skills/ascend-performance-orchestrator/Ascend Performance Orchestrator.md`
- 安装清单到 `.trae/skills/mindstudio-skills-install.json`

### 推荐安装方式

在 macOS 的 TRAE 目标项目根目录打开终端，执行：

```bash
/path/to/mindstudio-skills/install-trae-skills.sh
```

第一次使用前如果脚本没有执行权限，先运行：

```bash
chmod +x /path/to/mindstudio-skills/install-trae-skills.sh
```

也可以显式指定项目根目录：

```bash
/path/to/mindstudio-skills/install-trae-skills.sh /path/to/your-trae-project
```

### 安装参数

| 参数 | 作用 |
|---|---|
| `<PROJECT_ROOT>` | 指定目标项目根目录；不传时使用当前终端目录 |
| `--no-backup` | 若目标已有同名 Skill，直接覆盖，不创建备份 |
| `--list-only` | 只列出将安装的 Skill，不写入目标项目 |
| `-h` / `--help` | 查看脚本帮助 |

默认会备份目标项目中已有的同名 Skill：

```text
.trae/skills/<skill-name>.backup-YYYYMMDD-HHMMSS
```

### 安装后使用

安装完成后，重启 TRAE IDE 或重新加载项目。建议优先使用入口提示词：

```text
使用 ascend-performance-orchestrator 分析这个 Ascend 性能问题：
<你的问题或 profiling 路径>

请先校验数据，再按证据判断应该进入计算、通信、调度、集群慢卡、时间线异常、CPU 绑核或单算子调优路径。
```

## 设计目标

本套 Skill 解决三个问题：

1. **先路由，再下钻**：用户只需要描述性能问题或给出 profiling 路径，入口 Skill 负责选择合适的专项。
2. **先证据，再结论**：任何性能结论都必须绑定 profiling、日志、benchmark、DB 查询、`msprof-analyze` 输出或系统采样证据。
3. **避免误判**：把慢卡、通信 wait、Host Bound、device bubble、wait-anchor 假热点、CPU/NUMA 绑核等容易混淆的问题拆开处理。

## 整体架构

```text
用户问题 / profiling 路径 / 算子源码 / msprof op 产物
  |
  v
ascend-performance-orchestrator
  |
  +-- mindstudio_profiler_data_check        # 数据是否 valid / parsed
  |
  +-- msprof-analyze-cli                    # 集群/多卡全局初筛、advisor
  |     |
  |     +-- cluster-fast-slow-rank-detector # 慢卡、慢 rank、慢链路
  |
  +-- ascend-profiling-anomaly              # bubble / underfeed / kernel gap / wait-anchor / 模型结构反推
  |
  +-- ascend-computation-analysis           # 计算侧下钻
  |     +-- op-mfu-calculator               # 算子 MFU 计算
  |
  +-- ascend-communication-analysis         # HCCL/hcom/wait/bandwidth/通信矩阵
  |
  +-- ascend-schedule-analysis              # Free time / Host Bound / launch gap / API gap
  |     +-- mindstudio-cpu-binding          # CPU affinity / NUMA / cgroup / cpuset
  |
  +-- ascend-profiler-db-explorer           # DB SQL 与 schema 证据补充
  |
  +-- msot-msopprof-operator-profiler       # msprof op / simulator 产物分析
        |
        +-- ascendc-operator-performance-optim # AscendC 端到端优化闭环
```

核心原则：`ascend-profiling-anomaly` 是异常事实层，不直接裁决根因；`ascend-schedule-analysis`、`ascend-computation-analysis`、`ascend-communication-analysis` 才做根因专项下钻。

## Skill 清单

| Skill | 角色 | 典型触发 |
|---|---|---|
| `ascend-performance-orchestrator` | 统一入口和路由 | 不确定用哪个 Skill、需要完整调优方案 |
| `mindstudio_profiler_data_check` | Profiler 数据完整性校验 | `*_ascend_pt`、`*_ascend_ms`、`PROF_*`、未解析数据 |
| `msprof-analyze-cli` | `msprof-analyze` 命令编排和结果解释 | 集群分析、advisor、slow rank、free_analysis |
| `ascend-profiler-db-explorer` | Profiling DB 查询和 SQL 设计 | `ascend_pytorch_profiler*.db`、`msprof_*.db`、表结构、TopK 查询 |
| `ascend-profiling-anomaly` | 时间线异常事实层 | device bubble、underfeed、kernel gap、wait-anchor、模型结构反推 |
| `cluster-fast-slow-rank-detector` | 集群快慢卡诊断 | 慢卡、慢 rank、慢链路、负载不均衡 |
| `ascend-computation-analysis` | 计算侧瓶颈分析 | 算子慢、AICPU、动态 shape、block dim、fusion |
| `ascend-communication-analysis` | 通信侧瓶颈分析 | HCCL/hcom、Notify Wait、带宽低、通信矩阵、慢链路 |
| `ascend-schedule-analysis` | 调度与 Host Bound 分析 | Free time、Host 下发慢、launch/API gap、同步卡顿 |
| `mindstudio-cpu-binding` | Host CPU/NUMA/绑核分析 | CPU range 重叠、NUMA 不匹配、cgroup/cpuset、LLM Serving CPU 竞争 |
| `op-mfu-calculator` | 算子 MFU 计算 | MatMul/GEMM/FlashAttention FLOPs 与 MFU |
| `msot-msopprof-operator-profiler` | msprof op 算子产物分析 | `msprof op`、`msprof op simulator`、OPPROF、Roofline、PipeUtilization |
| `ascendc-operator-performance-optim` | AscendC 端到端优化闭环 | 算子源码、编译、采集、诊断、改代码、前后对比 |

## 推荐工作流

### 1. 普通 Profiler 数据分析

```text
mindstudio_profiler_data_check
  -> msprof-analyze-cli 或 ascend-profiling-anomaly
  -> computation / communication / schedule 三选一主下钻
  -> db-explorer 补证据
  -> 输出优化实验和验证计划
```

适合提示词：

```text
使用 ascend-performance-orchestrator 分析这个 Ascend profiler 数据：
<profiling_path>

目标是定位主要性能瓶颈。请先校验数据，再判断是计算、通信、调度/Host Bound、慢卡还是证据不足。
最终输出证据链、根因分类、优化实验和验证计划。
```

### 2. 集群慢卡 / 慢 rank / 慢链路

```text
mindstudio_profiler_data_check
  -> msprof-analyze-cli
  -> cluster-fast-slow-rank-detector
  -> 候选 rank 上按需调用 anomaly / computation / communication / schedule
```

适合提示词：

```text
使用 ascend-performance-orchestrator 分析集群慢卡问题：
<cluster_profiling_root>

请先做数据校验和集群全局初筛，识别慢 rank / 慢链路 / 负载不均衡。
如果某个 rank Free time 或 bubble 异常，请对候选 rank 做时间线异常定位，再路由到对应专项下钻。
```

### 3. Device bubble / underfeed / kernel gap

```text
mindstudio_profiler_data_check
  -> ascend-profiling-anomaly
  -> schedule / communication / computation 根因专项
```

适合提示词：

```text
使用 ascend-profiling-anomaly 看这个 profiling 是否有 device bubble / underfeed / kernel gap：
<profiling_path>

请只先输出异常事实和软归因，不要直接断言 Host Bound。
如果发现 possible_host_launch_lag、possible_comm_wait 或 AICPU 暴露，请说明下一步应该交给哪个专项 Skill。
```

### 4. 计算侧瓶颈

```text
mindstudio_profiler_data_check
  -> ascend-computation-analysis
  -> ascend-profiler-db-explorer / op-mfu-calculator
```

适合提示词：

```text
使用 ascend-computation-analysis 分析这个 rank 的计算瓶颈：
<rank_profiler_path>

请优先看 DB，其次 kernel_details.csv / op_statistic.csv。
输出 Top op/type、AI Core/AI Vector/AICPU 占比、动态 shape / block dim / fusion 风险，并给出按收益排序的优化实验。
```

### 5. 通信侧瓶颈

```text
mindstudio_profiler_data_check
  -> msprof-analyze-cli
  -> ascend-communication-analysis
  -> cluster-fast-slow-rank-detector
```

适合提示词：

```text
使用 ascend-communication-analysis 分析通信瓶颈：
<cluster_or_rank_profiler_path>

请先区分 wait-caused high duration 和真实通信传输慢。
不要仅凭通信 op duration 高就判断链路慢；需要给出 wait、bandwidth、transit、rank 对齐或通信矩阵证据。
```

### 6. 调度 / Host Bound / Free time

```text
mindstudio_profiler_data_check
  -> ascend-profiling-anomaly
  -> ascend-schedule-analysis
  -> mindstudio-cpu-binding
```

适合提示词：

```text
使用 ascend-schedule-analysis 分析 Host Bound / Free time 问题：
<profiling_path>

如果需要，请先用 ascend-profiling-anomaly 定位 prelaunch/internal/tail gap。
Host Bound 结论必须同时证明 Free 区间无 device work，且 Host dispatch/launch gap 与 Free 区间对齐。
```

### 7. CPU 绑核 / NUMA / cgroup

```text
mindstudio-cpu-binding
  -> ascend-schedule-analysis 交叉验证 profiling 证据
```

适合提示词：

```text
使用 mindstudio-cpu-binding 分析这个 NPU 任务的 CPU/NUMA/绑核问题。
我会提供 Snapshot 或目标 PID。

请默认只读分析，不要自动执行 taskset/numactl。
输出当前绑定状态、NUMA locality、cgroup/cpuset 限制、保守方案、进阶方案、风险、回滚和 before/after 验证计划。
```

### 8. msprof op / 单算子调优

```text
msot-msopprof-operator-profiler
  -> op-mfu-calculator
  -> ascendc-operator-performance-optim
```

适合提示词：

```text
使用 msot-msopprof-operator-profiler 分析这个 msprof op 产物：
<OPPROF_path>

请先判断 device/simulator 模式和输入形态，再按固定报告模板输出算子基本信息、关键数据 TOP5、核心瓶颈 TOP5、优化建议 TOP5。
```

端到端代码优化提示词：

```text
使用 ascendc-operator-performance-optim 对这个 AscendC 算子做端到端性能优化：
<operator_project_path>

要求先备份工程，只在备份目录修改代码。
流程包括源码审查、基线 msprof op 采集、瓶颈分析、代码优化、精度验证、性能复测和优化前后对比。
```

## 路由决策速查

| 用户问题 | 推荐入口 | 说明 |
|---|---|---|
| “帮我看这个 profiler 数据” | `ascend-performance-orchestrator` | 先校验，再自动路由 |
| “数据是不是采完整了 / 为什么没法分析” | `mindstudio_profiler_data_check` | 检查 stop、parse、关键交付件 |
| “集群有慢卡 / 慢 rank” | `cluster-fast-slow-rank-detector` | 先全局后候选 rank 下钻 |
| “有 device bubble / NPU 空洞” | `ascend-profiling-anomaly` | 先做异常事实层 |
| “Free time 高 / Host Bound” | `ascend-schedule-analysis` | 必须证明 dispatch/launch gap 对齐 |
| “算子慢 / AI Core 利用低” | `ascend-computation-analysis` | DB 优先，CSV 降级 |
| “HCCL 慢 / Notify Wait 高” | `ascend-communication-analysis` | 先 wait gate，再判断链路 |
| “查 DB 表 / 写 SQL” | `ascend-profiler-db-explorer` | 使用内置 CTE 宏和 schema 规则 |
| “CPU 绑核 / NUMA” | `mindstudio-cpu-binding` | 默认只读，执行前确认 |
| “算 MFU” | `op-mfu-calculator` | 需要 shape、耗时、峰值算力 |
| “msprof op 产物怎么看” | `msot-msopprof-operator-profiler` | 区分 device/simulator |
| “AscendC 算子自动优化” | `ascendc-operator-performance-optim` | 必须备份后修改 |

## 输出要求

最终性能诊断建议统一包含：

1. 结论摘要和置信度。
2. 分析路径：用了哪些 Skill，为什么这么路由。
3. 关键证据：指标、数值/现象、来源文件或命令。
4. 根因分类：主因、次要因素、暂不能确认因素。
5. 优化实验：动作、预期改善、验证指标、风险。
6. 验证计划：before/after 指标、对比方式、成功标准。
7. 限制与缺失证据。

推荐结论格式：

```text
## 结论
<一句话说明主要瓶颈和置信度>

## 分析路径
- 数据校验：
- 全局初筛 / 异常事实层：
- 专项下钻：
- 使用的 Skill：

## 关键证据
| 证据项 | 数值/现象 | 来源 | 说明 |
|---|---|---|---|

## 根因判断
- 主因：
- 次要因素：
- 暂不能确认：

## 优化实验
| 优先级 | 实验 | 期望改善 | 验证指标 | 风险 / 回滚 |
|---|---|---|---|---|
```

## 安全边界

默认只读分析。以下动作不能自动执行：

- 修改线上服务配置。
- 重启服务或 kill 进程。
- 修改 cgroup / cpuset / K8s / Slurm / Docker 配置。
- 执行 `taskset`、`numactl` 等改变运行状态的命令。
- 直接修改用户原始算子工程代码。
- 在证据不足时给确定性结论。

如果确实需要执行状态变更，必须先输出：

1. 要执行的命令。
2. 影响范围。
3. 风险。
4. 回滚方式。
5. 验证指标。

并等待用户明确确认。

## 维护与扩展

新增 Skill 时建议遵守：

- 每个 Skill 一个目录，必须包含 `SKILL.md`。
- `SKILL.md` frontmatter 只保留 `name` 和 `description`。
- 大型说明放入 `references/`，确定性工具放入 `scripts/`。
- 在 `ascend-performance-orchestrator/SKILL.md` 和根目录 `Ascend Performance Orchestrator.md` 中补充路由。
- 在本 README 的 Skill 清单和路由速查表中补充说明。
- 不要把一个专项写成万能入口；入口只放在 `ascend-performance-orchestrator`。

当前套件中，`ascend-profiling-anomaly` 是从 Trae 版本融合来的瘦身版。它不引用缺失的外部 reference/scripts，职责被限制为异常事实层和按需模型结构反推。

## 当前状态

已集成 13 个 Skill：

- `ascend-performance-orchestrator`
- `mindstudio_profiler_data_check`
- `msprof-analyze-cli`
- `ascend-profiler-db-explorer`
- `ascend-profiling-anomaly`
- `cluster-fast-slow-rank-detector`
- `ascend-computation-analysis`
- `ascend-communication-analysis`
- `ascend-schedule-analysis`
- `mindstudio-cpu-binding`
- `op-mfu-calculator`
- `msot-msopprof-operator-profiler`
- `ascendc-operator-performance-optim`
