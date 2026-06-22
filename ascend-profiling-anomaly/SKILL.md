---
name: ascend-profiling-anomaly
description: Ascend profiling 时间线异常发现与模型结构反推辅助 Skill。用于在已校验的 Ascend Profiler 数据中分析 kernel_details.csv、trace_view.json、op_summary 或 rank 级 profiling 产物，发现 device bubble、underfeed、prelaunch/internal/tail gap、wait-anchor false hotspot、AICPU 暴露、未解释 Host gap，并在用户需要时从 profiling 反推 step/pass/layer/model architecture。作为横向证据层辅助 ascend-schedule-analysis、ascend-computation-analysis、ascend-communication-analysis 和 cluster-fast-slow-rank-detector，不直接替代根因专项分析。
---

# Ascend Profiling Anomaly

本 Skill 是 Ascend 性能调优套件中的“异常事实层”。它负责从 profiling 时间线中找出不自然的空洞、等待污染和结构模式，再把证据交给调度、计算、通信或集群专项做根因下钻。

不要把本 Skill 当成 `ascend-schedule-analysis` 的替代品。这里输出的是“发生了什么”和“可能指向哪里”，不是最终 Host/通信/计算根因裁决。

## 适用场景

使用本 Skill 当用户提出：

- device bubble、underfeed、kernel gap、空洞、NPU 没活干。
- step time 看似正常但怀疑隐藏异常。
- Free time、prelaunch gap、tail gap、internal bubble 需要精确定位。
- `kernel_details.csv`、`trace_view.json`、`op_summary.csv`、`op_statistic.csv` 中的时间线异常。
- Top op 被 wait time 污染，怀疑高 wait 低 duration 的假热点。
- AICPU 暴露、AI CPU fallback、辅助流异常。
- 需要从 profiling 反推模型结构、layer structure、forward pass、prefill/decode、通信 pipeline。

## 和现有 Skill 的关系

先使用 `mindstudio_profiler_data_check` 确认数据 valid。之后按下列方式接入：

| 本 Skill 发现 | 后续主 Skill |
|---|---|
| prelaunch / internal / tail bubble 与 Host event 或 launch gap 对齐 | `ascend-schedule-analysis` |
| AICPU 暴露、短小算子串、结构内计算序列异常、shape 变化嫌疑 | `ascend-computation-analysis` |
| bubble 周围出现 HCCL/hcom/Notify Wait/StreamWaitEvent/c10d | `ascend-communication-analysis` |
| 多 rank 中只有部分 rank 出现 bubble 或 underfeed | `cluster-fast-slow-rank-detector` |
| 需要 DB 表级查询补证据 | `ascend-profiler-db-explorer` |
| CPU/NUMA/cgroup/绑核可能导致 Host gap | `mindstudio-cpu-binding` |

在集群场景中，不要默认逐 rank 全量运行 anomaly。先用 `cluster-fast-slow-rank-detector` 或 `msprof-analyze-cli` 找候选慢 rank / 长 Free rank / 长 step rank，再对候选 rank 做本 Skill 分析。

## 输入优先级

优先使用：

1. `kernel_details.csv`：构建 device kernel intervals、op/task/core/stream 证据。
2. `trace_view.json`：识别 step markers、host events、sync/copy/communication markers。
3. `op_summary.csv` / `op_statistic.csv`：无 kernel 明细时的降级 op 级证据。
4. `step_trace_time.csv` / `analysis.db` / `cluster_analysis_output/cluster_analysis.db`：step 边界或候选 rank/step 辅助证据。
5. `profiler_info.json`：判断 `record_shapes`、`with_stack`、profiler level 等置信度条件。

如果只有 DB 而没有 CSV/JSON，可先通过 `ascend-profiler-db-explorer` 或 `msprof-analyze-cli` 获取等价 step/kernel/op 视图，再回到本 Skill 做事实层分析。

## 核心原则

- 把异常事实和根因归因分开。`bubble exists` 是事实，`host launch lag` 只是可能归因。
- 不因为整体 step device-bound 就忽略局部 bubble。
- 不把高 wait、低 duration 的 op 当真实热点，必须做 wait-anchor 扫描。
- 不只看 `kernel_sum`。同时维护 `wall_ms`、`busy_union_ms`、`kernel_sum_ms`、`total_cost_ms`。
- 没有 host evidence 时输出 `possible_untraced_host_blocking` 或 `insufficient_evidence`，不要沉默。
- 每个重要 bubble 必须列出 gap 前后的 kernel 名称、task type、duration、stream id。

## 工作流

### Step 1. 数据盘点

确认：

- profiling 是单卡、选定 rank，还是集群根目录。
- 是否有 `kernel_details.csv`、`trace_view.json`、`op_summary.csv`。
- 是否存在 step marker，例如 `ProfilerStep#N` 或 `Iteration#N`。
- `profiler_info.json` 中 `record_shapes`、`with_stack`、`profiler_level` 是否足够。

输出数据覆盖范围和降级限制。

### Step 2. Step 边界识别

优先从 `trace_view.json` 的用户标注识别 step window。

若没有 step marker：

- 使用 `step_trace_time.csv` / `analysis.db` 中的 step 信息。
- 仍无 step 信息时，将全局采集窗口作为 single pseudo-step，并明确降低置信度。

### Step 3. 构建 device busy union

从 `kernel_details.csv` 或降级 op 明细中提取 device intervals：

- interval start = kernel start time
- interval end = start + duration
- 包含 AI Core、AI Vector、AI CPU、HCCL/hcom、Memcpy 等 device-side 任务
- 按 step window 裁剪 interval
- 多 stream interval 合并统计，避免重复计算重叠

计算：

- `service_ms`
- `device_busy_union_ms`
- `underfeed_ms = service_ms - device_busy_union_ms`
- `underfeed_ratio`
- `prelaunch_gap_ms`
- `tail_gap_ms`
- `internal_bubble_total_ms`
- `largest_internal_bubble_ms`
- `bubble_count`

### Step 4. Bubble 分类

按 step 输出 bubble 类型：

- `PRELAUNCH_GAP_HEAVY`：step 开始到首个 device task 之间存在明显空洞。
- `INTERNAL_BUBBLE_HEAVY`：两个 device busy segment 之间存在明显空洞。
- `TAIL_GAP_HEAVY`：最后一个 device task 到 step 结束之间存在明显空洞。
- `DEVICE_IDLE_GAP_HEAVY`：整体 underfeed ratio 明显高。

阈值应结合任务粒度。默认经验：

- 单个 gap 大于 1 ms 且超过 step time 1%：值得报告。
- underfeed ratio 大于 10%：高优先级。
- 重复出现在 60% 以上 step：认为是 recurring pattern。

若用户提供业务阈值或已有 baseline，以用户阈值为准。

### Step 5. Host / Sync / Comm 软归因

对每个重要 bubble window，在 `trace_view.json` 中扫描同时间范围 host events。

收集覆盖率：

- `host_visible_coverage_ratio`
- `sync_marker_overlap_ratio`：`aclrtSynchronize*`、`HostToDevice`、`torch_to_npu`、`aclrtMemcpy*`
- `comm_marker_overlap_ratio`：`HCCL`、`hcom`、`c10d`、`StreamWaitEvent`、`Notify_Wait`
- `launch_or_dispatch_overlap_ratio`：`AscendCL@*`、`launch`、CANN/PyTorch API

软归因标签：

| 条件 | 标签 |
|---|---|
| sync/copy 覆盖明显 | `possible_sync_or_h2d` |
| communication marker 覆盖明显 | `possible_comm_wait` |
| host event 很少 | `possible_untraced_host_blocking` |
| launch/dispatch 事件与 bubble 接近 | `possible_host_launch_lag` |
| 有 host 事件但缺少明确 sync/comm/launch | `possible_python_serialization_or_lock` |
| 证据不足 | `insufficient_evidence` |

这些标签可以并存，不要把它们写成唯一根因。

### Step 6. Wait-anchor false hotspot 扫描

扫描 Top total cost op：

```text
total_cost = duration + wait
wait_ratio = wait / total_cost
```

若 `wait_ratio > 0.95` 且 `duration < 10 us`，同时该 op 位于 total cost TopK，则标记：

- `WAIT_ANCHOR_FALSE_HOTSPOT`

这类 op 应降级为等待锚点，不作为计算优化第一目标。后续通常交给 `ascend-communication-analysis` 或 `ascend-schedule-analysis` 补证据。

### Step 7. AICPU 暴露与结构内异常

标记：

- AICPU / AI CPU 占比异常。
- AI Core 前后夹杂大量短小 vector/cast/transdata/transpose。
- 同一结构内存在重复小 op 串或多 stream wait。
- 动态 shape 或 shape group 变化导致同模板耗时差异。

只输出“计算侧风险”，再交给 `ascend-computation-analysis` 做 operator/shape/fusion 下钻。

### Step 8. 模型结构反推（按需）

仅在用户要求模型结构、layer structure、architecture、forward pass，或性能异常必须依赖结构解释时执行。

可用线索：

- `ProfilerStep#N` / `Iteration#N` 定位 pass。
- 重复 kernel name pattern 定位 layer/structure。
- `FusedInferAttentionScore`、MatMul、GroupedMatmul、MoeGatingTopK、DispatchFFNCombine、AllReduce/AllGather/alltoall 等标志性 op 分类 attention、MLP、MoE、communication。
- stream id 和时间重叠关系定位 main compute stream、communication stream、AI CPU side stream。

输出一个独立 Markdown 报告文件时，命名为：

```text
model_architecture_report_<profiling_dir_name>.md
```

报告至少包含：

1. 输入数据与置信度。
2. Step/pass 边界证据。
3. 结构/layer 分类表。
4. 每类结构的 kernel sequence 和 timing breakdown。
5. 通信 pipeline 和 overlap 概述。
6. 结构相关的性能异常线索。

若信息不足，只在最终报告中输出结构摘要，不强制生成文件。

## 输出格式

默认输出以下结构：

```text
## 异常事实摘要

- 是否存在显著 device bubble / underfeed：
- 主要集中 step/rank/structure：
- 主要 bubble 类型：
- 置信度：

## 关键 Bubble 窗口

| 位置 | gap 类型 | 开始/结束 | gap 时长 | 前一个 kernel | 后一个 kernel | stream | 软归因 |
|---|---|---|---|---|---|---|---|

## Wait-anchor / AICPU / 结构风险

- wait-anchor false hotspot：
- AICPU 暴露：
- 结构内异常：

## 后续路由

- 调度侧：
- 计算侧：
- 通信侧：
- 集群侧：

## 限制与缺失证据

- ...
```

若生成模型结构报告，额外列出报告路径。

## 禁止事项

- 不要在本 Skill 中直接断言最终 Host Bound，除非已经满足 `ascend-schedule-analysis` 的证据标准。
- 不要把 `possible_comm_wait` 写成通信链路慢；通信链路慢必须由 `ascend-communication-analysis` 的 wait gate 和 transfer evidence 判定。
- 不要把 wait-anchor op 作为计算优化 P0。
- 不要为了满足结构报告而编造 layer 名称、模型类型或 pass 数。
- 不要依赖源 Trae Skill 中不存在于当前目录的 reference/scripts；本 Skill 必须自包含。
