---
name: ascend-performance-orchestrator
description: Ascend 性能调优套件入口。用于接收 Ascend NPU 训练、推理、集群、Profiler、慢卡慢链路、计算、通信、调度、Host Bound、CPU 绑核、NUMA、Profiling DB 查询、device bubble、underfeed、kernel gap、profiling anomaly、模型结构反推、算子 MFU、msprof op 和 AscendC 算子端到端优化等性能问题，并路由到本工作区的专项 Skill 形成完整证据链。
---

# Ascend Performance Orchestrator

本 Skill 是当前工作区 Ascend 性能调优套件的统一入口。先按用户问题识别场景，再读取对应专项目录的 `SKILL.md` 下钻分析。完整入口说明保留在 `Ascend Performance Orchestrator.md`；通过安装脚本部署到 TRAE IDE 后，该文件会同时出现在 `.trae/skills/` 根目录和本 Skill 目录内。当需要更详细的路由表、输出模板和安全边界时先读取该文件。

## 本地专项 Skill

| 目录 | 角色 |
|---|---|
| `mindstudio_profiler_data_check/` | Profiler 数据完整性、Stop 状态、解析状态和关键交付件校验 |
| `msprof-analyze-cli/` | `msprof-analyze` 集群分析与 advisor 命令选择、执行和结果解释 |
| `ascend-profiler-db-explorer/` | Profiling DB SQL 查询、schema 查询、TopK 算子/通信/下发证据抽取 |
| `ascend-profiling-anomaly/` | 时间线异常事实层：device bubble、underfeed、kernel gap、wait-anchor、AICPU 暴露、模型结构反推 |
| `cluster-fast-slow-rank-detector/` | 集群慢卡、慢 rank、慢链路、负载不均衡诊断 |
| `ascend-computation-analysis/` | 计算侧瓶颈、算子耗时、AI Core/AI Vector/AICPU、动态 shape、融合机会 |
| `ascend-communication-analysis/` | HCCL/hcom 通信、wait-caused 判定、带宽、慢链路、通信矩阵 |
| `ascend-schedule-analysis/` | Host Bound、Free time、下发/launch/API gap、同步卡顿、调度瓶颈 |
| `mindstudio-cpu-binding/` | Host CPU affinity、NUMA locality、cgroup/cpuset、线程与 LLM Serving CPU 竞争 |
| `op-mfu-calculator/` | 算子 MFU 计算、公式推导和峰值算力利用率解释 |
| `msot-msopprof-operator-profiler/` | `msprof op` / `msprof op simulator` 上板或仿真算子性能分析 |
| `ascendc-operator-performance-optim/` | AscendC 算子端到端优化闭环：采集、诊断、改代码、验证和对比 |

## 路由流程

1. 对任何 profiler 路径，先使用 `mindstudio_profiler_data_check`。若结果为 `invalid` 或 `unparsed`，终止确定性性能分析，先修复采集或解析。
2. 对 device bubble、underfeed、kernel gap、wait-anchor、AICPU 暴露、隐藏时间线异常或模型结构反推，使用 `ascend-profiling-anomaly` 建立异常事实层，再路由到根因专项。
3. 对多卡/集群问题，先使用 `msprof-analyze-cli` 建立全局视图，再使用 `cluster-fast-slow-rank-detector` 判定慢卡、慢 rank、慢链路或负载不均；需要对候选 rank 做时间线定位时，再使用 `ascend-profiling-anomaly`。
4. 根据全局证据或 anomaly 事实选择一个主下钻方向：
   - 计算慢、算子慢、AI Core 利用率低：`ascend-computation-analysis`
   - HCCL/hcom、wait、带宽、通信矩阵：`ascend-communication-analysis`
   - Free time、Host Bound、launch/API gap：`ascend-schedule-analysis`
5. 需要 DB 表、SQL、TopK 明细或自定义证据时，辅助使用 `ascend-profiler-db-explorer`，并遵守其 CTE 宏和 schema 规则。
6. 调度或服务侧问题涉及 CPU 资源、NUMA、cgroup/cpuset 或绑核时，辅助使用 `mindstudio-cpu-binding`。任何改变运行状态的动作必须先给出命令、影响范围、风险、回滚和验证指标，并等待用户确认。
7. 单算子问题按目标选择：
   - 只计算 MFU：`op-mfu-calculator`
   - 解释 msprof op / simulator 产物或生成算子分析报告：`msot-msopprof-operator-profiler`
   - 对 AscendC 源码做端到端性能优化闭环：`ascendc-operator-performance-optim`

## 证据要求

不要在缺少 profiling、日志、benchmark 或明确背景时给确定性调优结论。最终结论至少引用以下一类证据：

- step time / iteration time
- compute / communication / free time 占比
- operator duration / count / average / max
- HCCL/hcom elapsed / wait / transit / bandwidth
- Host API / CANN API / launch gap / dispatch gap
- device bubble / underfeed / prelaunch/internal/tail gap
- CPU affinity / NUMA / cgroup / cpuset / thread contention
- Profiling DB 查询结果或 `msprof-analyze` 输出

## 输出要求

最终报告按以下结构输出：

1. 结论摘要和置信度。
2. 分析路径：入口路由、数据校验、全局初筛、专项下钻、辅助 Skill。
3. 关键证据：列出指标、数值/现象和来源。
4. 根因分类：主因、次要因素、暂不能确认的因素。
5. 优化实验：动作、期望改善、验证方式、风险、回滚方式。
6. 限制与缺失证据。

## 安全边界

默认只读分析。不要自动修改线上服务配置、重启服务、kill 进程、修改 cgroup/cpuset、执行 `taskset`/`numactl` 等改变运行状态的命令，或在证据不足时给确定性结论。
