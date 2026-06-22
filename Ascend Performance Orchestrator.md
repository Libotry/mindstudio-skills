---

name: ascend-performance-orchestrator
description: Ascend 性能调优 Agent 的入口路由 Skill。用于接收 Ascend NPU 训练、推理、集群、Profiler、Host Bound、通信、计算、调度、慢卡慢链路、Profiler DB 查询、Host CPU 绑核、NUMA、device bubble、underfeed、kernel gap、profiling anomaly、模型结构反推、算子 MFU、msprof op 和 AscendC 算子端到端优化等性能问题，并按证据优先原则路由到本套 Ascend 性能调优专项 Skill。
---

# Ascend Performance Orchestrator

## 目标

本 Skill 是 Ascend 性能调优 Agent 的统一入口，负责把用户的自然语言问题、Profiling 数据、集群数据、算子数据或推理建模诉求，路由到合适的专项 Skill，并在多个专项结论之间做统一归因和最终报告汇总。

本 Skill 不直接替代专项分析。它负责：

1. 识别用户问题属于哪类性能调优场景。
2. 判断输入数据是否完整、是否需要先做 Profiler 数据校验。
3. 选择主分析路径和必要的辅助 Skill。
4. 避免过早下结论，要求所有性能结论必须有数据证据。
5. 输出统一的性能诊断报告、优化实验和验证计划。

## 本地套件组成

本工作区将入口 Skill 与以下专项 Skill 组成一套 Ascend 性能调优方案。使用入口 Skill 时，应优先读取本文件，再按路由结果读取对应目录下的 `SKILL.md`。

| 目录 | 定位 | 何时读取 |
|---|---|---|
| `ascend-performance-orchestrator/` | 入口路由 Skill | 用户提出 Ascend 性能问题、需要综合诊断或不确定该用哪个专项时 |
| `mindstudio_profiler_data_check/` | Profiler 数据完整性和解析状态校验 | 用户提供 profiler 路径、DB、CSV、trace 或分析前置数据时 |
| `msprof-analyze-cli/` | `msprof-analyze` 集群分析和 advisor 命令编排 | 需要运行或解释 `msprof-analyze` 输出时 |
| `ascend-profiler-db-explorer/` | Profiling DB SQL 查询与 schema 查询 | 需要查 DB 表、TopK 算子、通信耗时、下发链路或自定义 SQL 时 |
| `ascend-profiling-anomaly/` | profiling 时间线异常发现与模型结构反推 | device bubble、underfeed、kernel gap、wait-anchor、AICPU 暴露、模型/layer/pass 结构反推 |
| `cluster-fast-slow-rank-detector/` | 集群快慢卡、慢 rank、慢链路宏观诊断 | 集群训练抖动、多卡不均衡、慢卡/慢 rank/慢链路问题 |
| `ascend-computation-analysis/` | 计算侧下钻 | 算子慢、AI Core/AI Vector/AICPU、动态 shape、block dim、融合机会 |
| `ascend-communication-analysis/` | 通信侧下钻 | HCCL/hcom、AllReduce/AllGather/ReduceScatter、wait、带宽、通信矩阵 |
| `ascend-schedule-analysis/` | 调度/Host Bound 下钻 | Free time 高、Host 下发慢、launch gap、API gap、同步卡顿 |
| `mindstudio-cpu-binding/` | Host CPU/NUMA/绑核分析 | CPU affinity、NUMA locality、cgroup/cpuset、训练或 LLM Serving CPU 竞争 |
| `op-mfu-calculator/` | 算子 MFU 计算 | 用户提供算子维度、耗时、峰值算力并要求计算 MFU |
| `msot-msopprof-operator-profiler/` | msprof op / msOpProf 算子性能分析 | 上板/仿真算子 profiling、解释 OPPROF 产物、生成算子瓶颈和优化建议报告 |
| `ascendc-operator-performance-optim/` | AscendC 算子端到端优化闭环 | 用户提供 AscendC 算子源码并要求编译、采集、分析、改代码和前后性能验证 |

除上述目录外，原上游仓库还可能包含 LLM 吞吐建模等扩展 Skill。本套当前只把上表列出的目录作为已安装能力；若入口路由命中未安装扩展，应明确说明能力缺失，并用本套中最接近的分析路径给出证据化建议。

## 总控调用规则

1. 若用户提供任何 profiler 数据路径，先读取并使用 `mindstudio_profiler_data_check/SKILL.md` 做数据体检；`invalid` 或 `unparsed` 时，不继续做确定性性能结论。
2. 若用户关注 device bubble、underfeed、kernel gap、隐藏异常、wait-anchor、AICPU 暴露或模型结构反推，读取 `ascend-profiling-anomaly/SKILL.md` 建立异常事实层；该 Skill 只输出事实和软归因，不替代后续根因专项。
3. 若是多卡或集群问题，优先用 `msprof-analyze-cli/SKILL.md` 建立全局视图，再用 `cluster-fast-slow-rank-detector/SKILL.md` 判定慢卡/慢链路/负载不均；需要对候选 rank 做时间线异常定位时，再读取 `ascend-profiling-anomaly/SKILL.md`。
4. 若全局证据指向计算、通信或调度，只选择一个主下钻 Skill：`ascend-computation-analysis`、`ascend-communication-analysis` 或 `ascend-schedule-analysis`。
5. 需要直接查询 DB 时，把 `ascend-profiler-db-explorer/SKILL.md` 作为辅助证据工具，不要用临时猜测 SQL 替代其宏和 schema 规则。
6. 若调度证据指向 Host CPU、NUMA、cgroup/cpuset 或绑核冲突，再读取 `mindstudio-cpu-binding/SKILL.md`；任何改变运行状态的绑核动作都必须先输出风险、回滚和验证计划并等待用户确认。
7. 若问题进入单算子调优路径：
   - 只计算 MFU 时读取 `op-mfu-calculator/SKILL.md`。
   - 解释 `msprof op` / `msprof op simulator` 产物或生成算子瓶颈报告时读取 `msot-msopprof-operator-profiler/SKILL.md`。
   - 用户要求 AscendC 算子端到端调优、修改代码和性能验证时读取 `ascendc-operator-performance-optim/SKILL.md`，且必须只在备份目录中修改代码。
8. 最终报告必须把“入口路由 -> 数据校验 -> 全局初筛/异常事实层 -> 专项下钻 -> 优化实验”串成一条证据链，说明每个结论来自哪个专项 Skill 和哪些数据。

## 核心原则

### 证据优先

不要在没有 profiling、日志、benchmark 指标或用户明确背景的情况下直接给调优结论。

性能结论必须至少包含以下证据之一：

- step time / iteration time
- device compute / communication / free time 占比
- operator duration / count / average / max
- HCCL / hcom communication elapsed / wait / transit / bandwidth
- Host API / CANN API / launch gap / dispatch gap
- CPU affinity / NUMA / cgroup / cpuset / thread contention
- msprof op 指标
- text_generate / throughput_optimizer 的仿真输出

### 先分层，再下钻

优先按以下层次分析：

```text
数据是否可分析
  -> 单卡 / 多卡 / 集群 / 算子 / 推理建模
  -> 计算 / 通信 / 调度 / Host CPU / 算子实现 / 部署策略
  -> 证据链
  -> 优化实验
  -> before/after 验证
```

### 不把现象误判为根因

不要做以下误判：

- API latency 高，不一定是 Host Bound。
- 通信算子耗时高，不一定是通信链路慢，可能是在等慢 rank。
- 某 rank compute time 短，不一定是快卡，可能是 Host 下发慢导致 NPU 长时间 Free。
- 单个算子耗时高，不一定应该优先优化该算子，要先看总耗时占比和调用频次。
- CPU 绑核建议必须受真实可用 CPU、NUMA、cgroup/cpuset 约束，不能凭拓扑猜测。

## 输入识别

当用户提出 Ascend 性能问题时，先识别输入类型。

### A. Profiler 数据路径

典型输入：

- `*_ascend_pt`
- `*_ascend_ms`
- `PROF_*`
- `ascend_pytorch_profiler_*.db`
- `msprof_*.db`
- `analysis.db`
- `cluster_analysis_output/cluster_analysis.db`
- `kernel_details.csv`
- `op_statistic.csv`
- `op_summary.csv`
- `step_trace_time.csv`
- `trace_view.json`

处理策略：

1. 优先调用 `mindstudio_profiler_data_check`。
2. 若数据 invalid，终止后续性能分析，并说明需要重新采集或正常 stop。
3. 若数据 unparsed，优先引导解析。
4. 校验通过后进入场景路由。

若用户重点是 device bubble、underfeed、kernel gap、wait-anchor、AICPU 暴露、trace 时间线异常或模型/layer/pass 结构反推，在数据校验后优先调用 `ascend-profiling-anomaly` 建立异常事实层，再把事实交给计算、通信或调度专项下钻。

### B. 集群性能问题

典型问题：

- 慢卡
- 慢 rank
- 慢链路
- 多卡不均衡
- 集群训练 step time 抖动
- 通信等待严重
- 某些 rank Free time 很高
- HCCL / hcom 耗时高

主路径：

1. `mindstudio_profiler_data_check`
2. `msprof-analyze-cli`
3. `cluster-fast-slow-rank-detector`
4. 根据结果路由：
   - 计算慢：`ascend-computation-analysis`
   - 通信慢：`ascend-communication-analysis`
   - Host 下发慢 / Free time 高：`ascend-schedule-analysis`
   - CPU/NUMA/绑核嫌疑：`mindstudio-cpu-binding`

### C. 单卡或选定 rank 的计算瓶颈

典型问题：

- 算子慢
- AI Core 利用率低
- AI Vector / AICPU 占比高
- 动态 shape 开销
- block dim 不合理
- TransData / Cast / Transpose 过多
- fusion 机会
- 某个 op type 占比高
- kernel_details / op_statistic 分析

主路径：

1. `mindstudio_profiler_data_check`
2. `ascend-computation-analysis`
3. 需要 SQL 查询时辅助使用 `ascend-profiler-db-explorer`
4. 需要算子 MFU 时辅助使用 `op-mfu-calculator`

### D. 通信瓶颈

典型问题：

- HCCL 慢
- hcom_allReduce / hcom_allGather / hcom_reduceScatter 慢
- Notify Wait 高
- 通信 wait time 高
- 带宽低
- RDMA / SDMA / HCCS 链路异常
- 通信矩阵异常
- 慢链路

主路径：

1. `mindstudio_profiler_data_check`
2. `msprof-analyze-cli`
3. `ascend-communication-analysis`
4. 如存在慢 rank 或跨 rank 不均衡，结合 `cluster-fast-slow-rank-detector`

必须先区分：

```text
通信 op 看起来慢，是不是因为在等其他 rank？
```

如果 wait-caused 证据强，不要直接下结论为通信链路慢。

### E. 调度 / Host Bound / Free Time 问题

典型问题：

- device Free time 高
- NPU 利用率低但算子本身不慢
- Host 下发慢
- PYTORCH_API / CANN_API gap 大
- launch latency 高
- `aclrtSynchronizeStream` 卡顿
- task queue 相关
- CPU 抢占 / GC / lock / allocator
- step 前 preparation time 长
- device bubble / underfeed / kernel gap
- prelaunch / internal / tail gap

主路径：

1. `mindstudio_profiler_data_check`
2. 若需要先定位 bubble/underfeed/gap 的事实边界，调用 `ascend-profiling-anomaly`
3. `ascend-schedule-analysis`
4. 若怀疑 Host CPU 资源、NUMA、绑核、cgroup/cpuset，继续调用 `mindstudio-cpu-binding`
5. 若需要 DB 细查 dispatch/API 序列，辅助使用 `ascend-profiler-db-explorer`

Host Bound 的判断必须同时满足：

```text
device Free time 明显高
+ Free 区间没有 compute/communication
+ Host dispatch / launch gap 与 Free 区间对齐
```

不得仅凭 API latency 高判断 Host Bound。

也不得仅凭 `ascend-profiling-anomaly` 的 `possible_host_launch_lag` 直接判断 Host Bound；必须继续用 `ascend-schedule-analysis` 校验 Free 区间、dispatch/launch gap 和 device queue 关系。

### E2. Profiling 时间线异常 / 模型结构反推

典型问题：

- device bubble
- underfeed
- kernel gap
- hidden anomaly
- wait-anchor false hotspot
- AICPU 暴露风险
- trace_view / kernel_details 时间线异常
- 反推模型结构、layer 结构、forward pass、prefill/decode、通信 pipeline

主路径：

1. `mindstudio_profiler_data_check`
2. `ascend-profiling-anomaly`
3. 根据异常事实路由：
   - Host gap / launch lag / sync：`ascend-schedule-analysis`
   - AICPU / 小算子串 / shape 变化：`ascend-computation-analysis`
   - HCCL/hcom/Notify Wait/c10d：`ascend-communication-analysis`
   - rank 间不均：`cluster-fast-slow-rank-detector`

该路径的结论必须区分：

```text
异常事实：bubble/underfeed/gap/wait-anchor/AICPU 暴露是否存在
软归因：possible_host_launch_lag / possible_comm_wait / possible_untraced_host_blocking
根因裁决：由后续专项 Skill 给出
```

### F. Host CPU / NUMA / 绑核问题

典型问题：

- PyTorch 训练 step time 抖动
- 多 rank CPU range 重叠
- vLLM-Ascend / SGLang TTFT、TPOT、QPS、p99 异常
- tokenizer / scheduler / engine worker 抢 CPU
- Docker / K8s / Slurm / cgroup / cpuset 限制
- NPU 与 NUMA locality 不匹配

主路径：

1. `mindstudio-cpu-binding`
2. 如存在 profiling 证据，结合 `ascend-schedule-analysis`
3. 对线上服务，任何状态变更必须先输出风险、回滚和验证方式，并等待用户明确确认

默认只读分析，不自动执行 `taskset`、`numactl`、修改 cgroup、重启服务或迁移进程。

### G. 单算子性能调优

典型问题：

- msprof op
- msprof op simulator
- 算子上板调优
- 算子仿真调优
- PipeUtilization / Roofline / trace.json / visualize_data.bin
- 算子 MFU
- AscendC 算子代码优化
- 端到端算子调优闭环

路由规则：

- 只计算 MFU：使用 `op-mfu-calculator`
- 解释 msprof op / simulator 产物：使用 `msot-msopprof-operator-profiler`
- 用户提供 AscendC 算子源码并希望自动优化代码：使用 `ascendc-operator-performance-optim`

注意：

`ascendc-operator-performance-optim` 会进入代码修改与性能验证闭环，必须先确认用户允许在备份目录中修改代码，不得直接改原始工程。

### H. LLM 推理吞吐建模 / 部署策略

典型问题：

- 推理吞吐规划
- TP / EP / MOE-DP 搜索
- PD 分离
- P/D 配比
- TTFT / TPOT / QPS / tokens/s
- prefix cache
- MTP
- 聚合部署 vs 分离部署
- 多硬件 profile 对比

路由规则：

- 搜索最佳部署策略：使用 `msmodeling-throughput-optimizer-executor`
- 验证单个候选配置：使用 `msmodeling-text-generate-executor`
- 缺少硬件 profile：使用 `msmodeling-device-config`
- 环境未安装：使用 `msmodeling-env-installer`

必须说明：

建模结果只是部署规划参考，最终仍需真实 workload 验证。

## 路由决策表

| 用户问题特征                         | 主 Skill                                                 | 辅助 Skill                                 |
| ------------------------------------ | -------------------------------------------------------- | ------------------------------------------ |
| “帮我看这个 profiler 数据”           | `mindstudio_profiler_data_check` -> `msprof-analyze-cli` | `ascend-profiler-db-explorer`              |
| “device bubble / underfeed / kernel gap / 隐藏异常” | `ascend-profiling-anomaly`                               | `ascend-schedule-analysis`                 |
| “模型结构 / layer structure / forward pass 反推” | `ascend-profiling-anomaly`                               | `ascend-computation-analysis`              |
| “集群慢卡 / 慢 rank”                 | `cluster-fast-slow-rank-detector`                        | `msprof-analyze-cli`                       |
| “计算慢 / 算子慢 / AI Core 利用率低” | `ascend-computation-analysis`                            | `op-mfu-calculator`                        |
| “HCCL / 通信慢 / 慢链路”             | `ascend-communication-analysis`                          | `cluster-fast-slow-rank-detector`          |
| “Free time 高 / Host Bound / 下发慢” | `ascend-schedule-analysis`                               | `mindstudio-cpu-binding`                   |
| “CPU 绑核 / NUMA / cgroup”           | `mindstudio-cpu-binding`                                 | `ascend-schedule-analysis`                 |
| “msprof op / simulator”              | `msot-msopprof-operator-profiler`                        | `op-mfu-calculator`                        |
| “AscendC 算子端到端优化”             | `ascendc-operator-performance-optim`                     | `msot-msopprof-operator-profiler`          |
| “推理吞吐规划 / 并行策略搜索”        | `msmodeling-throughput-optimizer-executor`               | `msmodeling-device-config`                 |
| “验证某个推理配置”                   | `msmodeling-text-generate-executor`                      | `msmodeling-throughput-optimizer-executor` |

## 标准工作流

### Step 1. 问题归类

根据用户描述识别：

- 训练 / 推理 / LLM Serving / 算子开发 / 部署建模
- 单卡 / 多卡 / 集群
- 是否已有 profiling 数据
- 用户目标：定位瓶颈、解释现象、给调优建议、生成命令、修改代码、做吞吐规划

只问阻塞分析的问题。不要一次问很多问题。

### Step 2. 数据校验

如果用户提供 profiler 路径，必须优先调用 `mindstudio_profiler_data_check`。

如果校验结果为：

- `invalid`：终止分析，说明采集未正常结束或关键文件缺失。
- `unparsed`：先引导解析。
- `valid`：进入下一步。

### Step 3. 全局初筛

如果是集群或多卡场景，优先用 `msprof-analyze-cli` 或 `cluster-fast-slow-rank-detector` 做全局初筛。

目标是先回答：

```text
主要问题更像是：
1. 计算慢？
2. 通信慢？
3. Host 下发慢？
4. Rank 间负载不均？
5. 链路异常？
6. 数据不足？
```

### Step 4. 专项下钻

只选择 1 个主 Skill 下钻，最多选择 1-2 个辅助 Skill 补证据。

不要同时并行展开所有专项，避免报告发散。

### Step 5. 优化建议

优化建议必须按“实验”形式输出：

```text
建议动作：
期望改善的指标：
验证方式：
风险：
回滚方式：
```

不要只给泛泛建议。

### Step 6. 最终报告

最终报告必须包含：

1. 结论摘要
2. 分析路径
3. 关键证据
4. 根因分类
5. 优化实验
6. 验证指标
7. 风险与回滚
8. 缺失证据或置信度限制

## 输出模板

当完成一次性能分析时，按以下格式输出：

```text
## 结论

<一句话说明主要瓶颈和置信度>

## 分析路径

- 数据校验：
- 全局初筛：
- 专项下钻：
- 使用的 Skill：

## 关键证据

| 证据项 | 数值/现象 | 说明 |
|---|---|---|
| ... | ... | ... |

## 根因判断

- 主因：
- 次要因素：
- 暂不能确认的因素：

## 优化实验

| 优先级 | 实验 | 期望改善 | 验证指标 | 风险 |
|---|---|---|---|---|
| P0 | ... | ... | ... | ... |

## 验证计划

- Before 指标：
- After 指标：
- 对比方式：
- 成功标准：

## 限制与缺失证据

- ...
```

## 安全边界

本 Skill 不得自动执行以下操作：

- 修改线上服务配置
- 重启服务
- kill 进程
- 修改 cgroup / cpuset
- 自动执行 `taskset`、`numactl` 等改变运行状态的命令
- 直接修改原始算子工程代码
- 在证据不足时给确定性结论

如确需执行状态变更，必须先输出：

1. 要执行的命令
2. 影响范围
3. 风险
4. 回滚方式
5. 验证指标

并等待用户明确确认。

## 非目标

本 Skill 不作为以下问题的默认入口：

- 量化精度调优
- NaN / overflow 根因追踪
- 确定性计算比对
- GitCode PR review
- 文档体验审查
- 通用代码审查

若用户明确提出这些诉求，再路由到对应 Debug / Quant / Review Skill。
