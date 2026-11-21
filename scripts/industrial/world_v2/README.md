# space-demo World v2 Runtime（4.10a）

这是新 World v2 在 space-demo 中的独立运行时适配层。它不依赖旧 IndustrialRuntime 的回合、奖励、钱包、存档或伤害语义，也不定义 Jar 系统与太空战玩法之间的关系。

## 依赖

当前 jar-system-dotnet 的 World v2 Bridge 位于 PR #26（Draft，尚未合并）。本阶段使用两个并列仓库的本地工作副本：

    D:/godot/programs/
    ├── space-demo/
    └── jar-system-dotnet/
        └── hosts/godot/WorldV2Bridge/

先在 jar-system-dotnet 工作副本切换到 world-v2/phase-4-godot-host-project。space-demo 的 space-demo.csproj 通过相对路径引用 Bridge，不引用旧 Core 项目路径。

## 4.10a 职责

- 创建并拥有一个 WorldV2BridgeSession。
- 从独立的 world_v2_sandbox.json 读取和校验世界配置。
- 把 Godot 墙钟秒转换为世界毫秒，保留不足 1ms 的余数。
- 不乘流速倍率；暂停和倍率由 Core WorldClock 处理。
- 向 GDScript 提供脱离式 Godot Dictionary 快照。
- 节点退出时释放会话。

本阶段不实现订单 UI、太空战伤害、奖励、钱包、旧存档迁移或旧模块删除。

## 本地验证

1. 确保两个仓库位于上述并列目录。
2. 在 Godot 4.7.1 .NET 打开 space-demo。
3. 通过「运行当前场景」打开 scenes/industrial/WorldV2RuntimeProbe.tscn。
4. 输出应出现 [WorldV2Runtime] initialized 和 [WorldV2Probe] runtime ready。
5. 每秒观察 world 与 logical 数值增长；主台/从台应分别显示“主台”“从台”。
6. 关闭场景/项目，不应出现 Dispose 异常。

这是 Runtime 冒烟测试场景，不替换项目主场景，也不修改旧 IndustrialMain。

## 4.10d 生命周期探针

新增独立场景：`scenes/industrial/WorldV2LifecycleProbe.tscn`。

运行方式：在 Godot 4.7.1 .NET 中打开该场景并运行当前场景（F6）。

探针覆盖：

- D1：对已初始化 Runtime 重复调用 `InitializeWorld()`，应返回 false，保留原会话和时钟，不把健康 Runtime 标记为故障。
- D2：使用 `world_v2_invalid.json` 初始化，应触发 `RuntimeFaulted`，且不保留 World session。
- D4：修正配置路径后，在同一个节点再次初始化，应成功并清除故障状态。
- D3/D5：将节点从 SceneTree 移除，应执行 `_ExitTree()`、释放 Bridge session、清空会话所有权，并将 `IsDisposed` 置为 true。
- D6：退出后的节点不可复活；再次初始化必须被拒绝。

该探针使用独立 Runtime 节点和 `AutoAdvance=false`，不干扰时间/命令探针，也不替换项目主场景。测试通过时应输出：

```text
[WorldV2LifecycleProbe] lifecycle probe passed initialization_faults=1 recovery=true duplicate_rejected=true disposed=true post_exit_rejected=true
```

D6：退出 SceneTree 后再次调用 `InitializeWorld()` 必须返回 false；`IsDisposed` 保持 true，且不得重新创建会话。

注意：探针场景内移除节点用于验证退出树时的释放路径；仍建议在完成探针后关闭运行窗口，确认整个项目退出时没有额外 Dispose 异常。

## 4.11a Runtime 故障边界

Runtime 将故障分为两类：

- 初始化故障：尚未持有 Bridge session。修正配置后允许在同一节点重新初始化；成功后清除初始化故障。
- 运行期故障：来自 Core 的 `AdvanceWorld` 结果、Core 快照，或推进过程中的异常。该故障在当前 Runtime 节点生命周期内保持粘滞，不提供自动恢复入口。

运行期故障处理：

- 消费 `WorldV2AdvanceResultDto.RuntimeFaulted/FaultReason`，并将故障转为 Godot 的 `RuntimeFaulted` signal。
- 推进异常时先检查 Core 快照；若 Core 尚未报告故障，则以 Host 推进异常作为宿主故障锁定。
- 故障后停止自动推进。
- 暂停、恢复、倍速、添加需求、移动需求、启动需求均要求 Runtime 处于正常运行状态；故障后拒绝这些操作。
- `GetWorldSnapshot()` 仍可用于诊断。返回的 `runtimeFaulted` / `faultReason` 合并 Host 与 Core 故障信息。
- 普通领域拒绝（例如当前求解结果不是该订单的有效可行计划）不是 Runtime 故障，命令仍返回正常的失败结果。

当前探针新增一项区分验证：订单启动得到普通领域拒绝后，`IsFaulted` 和快照的 `runtimeFaulted` 仍必须为 false。

本阶段没有加入人为制造 Core 运行期粘滞故障的生产 API。真实 Core fault fixture 已通过本地 Godot 验证；不得为测试向正式 Runtime 增加任意故障注入接口。

### 4.11a 真实 Core 故障探针

新增场景：`scenes/industrial/WorldV2FaultProbe.tscn`。

运行方式：Godot 4.7.1 .NET 打开该场景，运行当前场景（F6）。

该探针不使用 Runtime 故障注入 API，而是利用真实 Core 时间运算路径：

1. 创建正常 World v2 session，先关闭 Godot 自动推进。
2. 设置有限且可表示的极大流速倍率 `9.0e15`。
3. 恢复自动推进，让普通 Godot 帧增量进入 Core `WorldClock.Advance()`。
4. `deltaWorldTimeMilli * SpeedRatioMilli` 触发 checked Int64 溢出；Core 锁定故障并抛出异常。
5. 验证 Godot 收到一次 `RuntimeFaulted`，Runtime 保留会话用于诊断、`CanAcceptCommands=false)，快照仍可读取并包含故障原因，且溢出的时钟推进没有部分提交世界时间。

预期输出包含：

```text
[WorldV2FaultProbe] fault boundary passed core_fault=true signal_count=1 command_gate=false snapshot_readable=true
[WorldV2FaultProbe] faulted session disposal passed disposed=true session_released=true
```

故障快照读取完成后，探针会将 Runtime 节点移出 SceneTree，验证 sticky-fault 会话仍可正常释放，且节点进入终止状态。

注意：该探针使用极端倍率，仅用于独立测试场景；不要将其放入正常游戏配置或正常玩法 UI。

## 4.11b 故障后操作拒绝探针

新增独立 C# 探针场景：`scenes/industrial/WorldV2FaultedCommandsProbe.tscn`。

运行方式：Godot 4.7.1 .NET 打开该场景，运行当前场景（F6）。

该探针使用真实 Core WorldClock 溢出制造 sticky fault，并在 C# 中直接调用 Runtime API、捕获并检查异常。选择 C# 捕获是为了避免把 GDScript 对托管异常的日志行为误当成断言结果。

逐项验证六个当前公开的控制/命令入口：

- `PauseWorld`
- `ResumeWorld`
- `SetWorldSpeedRatio`
- `AddSingleRequirementDemand`
- `MoveDemand`
- `StartActiveDemand`

每项必须抛出包含“已故障”的 `InvalidOperationException`。探针还检查故障 signal 仍只发出一次、故障快照可读且原因稳定、拒绝操作没有推进世界时间，最后确认故障会话随 Runtime 节点退出 SceneTree 而释放。

预期关键输出：

```text
[WorldV2FaultedCommandsProbe] all six operations rejected fault_signal_count=1 snapshot_readable=true fault_reason_stable=true
[WorldV2FaultedCommandsProbe] passed operations=6 disposed=true
```

此探针目前是新增待本地运行验证项；不能仅凭代码已加入就视为 4.11b 通过。
