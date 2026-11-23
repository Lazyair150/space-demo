# space-demo World v2 Runtime（4.10a）

这是新 World v2 在 space-demo 中的独立运行时适配层。它不依赖旧 IndustrialRuntime 的回合、奖励、钱包、存档或伤害语义，也不定义 Jar 系统与太空战玩法之间的关系。

## 依赖

当前依赖 jar-system-dotnet 的 World v2 Bridge：PR #59 提供离散原石解析产出导入，基于 PR #57；PR #57 基于 PR #55，PR #55 又依赖 PR #54。PR #54/#55/#57/#59 均保持 Draft，尚未合并。

本阶段使用两个并列仓库的本地工作副本：

    D:/godot/programs/
    ├── space-demo/
    └── jar-system-dotnet/
        └── hosts/godot/WorldV2Bridge/

jar-system-dotnet 工作副本需要包含 PR #59 的 world-v2/phase-4.11b-space-produced-jar-import-v2 分支内容（该分支已包含 PR #57 的通用时间型生产率入口及其上游依赖）。space-demo 的 space-demo.csproj 通过相对路径引用 Bridge，不引用旧 Core 项目路径。

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

逐项验证七个当前公开的控制/命令入口：

- `PauseWorld`
- `ResumeWorld`
- `SetWorldSpeedRatio`
- `UpdateProducerRates`
- `AddSingleRequirementDemand`
- `MoveDemand`
- `StartActiveDemand`

每项必须抛出包含“已故障”的 `InvalidOperationException`。探针还检查故障 signal 仍只发出一次、故障快照可读且原因稳定、拒绝操作没有推进世界时间，最后确认故障会话随 Runtime 节点退出 SceneTree 而释放。

预期关键输出：

```text
[WorldV2FaultedCommandsProbe] all seven operations rejected fault_signal_count=1 snapshot_readable=true fault_reason_stable=true
[WorldV2FaultedCommandsProbe] passed operations=7 disposed=true
```

本地验收已通过：六个入口均抛出预期的故障态 `InvalidOperationException`；单次故障信号、稳定诊断快照、世界时间不变和会话释放均得到验证。


## 4.11c Runtime 终止生命周期操作边界

新增独立 C# 探针场景：`scenes/industrial/WorldV2DisposedCommandsProbe.tscn`。

该探针先创建并初始化健康 Runtime，再将节点移出 SceneTree。此时 Runtime 已释放 Bridge session，且 `IsDisposed=true`、`IsInitialized=false`。随后逐项调用所有现有控制/命令入口及快照查询，确认它们统一因“尚未初始化/会话不存在”而抛出 `InvalidOperationException`，不能在节点终止后继续操作已释放的世界。

覆盖：

- `PauseWorld`
- `ResumeWorld`
- `SetWorldSpeedRatio`
- `AddSingleRequirementDemand`
- `MoveDemand`
- `StartActiveDemand`
- `GetWorldSnapshot`
- `InitializeWorld` 必须返回 false，不能复活已终止节点。

该场景还检查正常 Dispose 不应产生 RuntimeFaulted signal，也不应把“已释放”错误地标记为运行期故障。本地验收已通过：8 个退出后入口均被拒绝，重新初始化被拒绝，`fault_signal_count=0`。


## 4.12a Runtime 对外 API 边界审查

本阶段先完成审查和分类，不因“接口看起来不够通用”而提前扩大 API，也不定义 Jar World 与太空战之间尚未确定的玩法关系。

### Host 生命周期入口

- `_Ready()`：Godot 节点进入场景树时自动初始化。
- `_Process(delta)`：接收墙钟增量并驱动世界推进。
- `_ExitTree()`：终止 Runtime 节点并释放其拥有的 Bridge session。

这些是 Godot 生命周期实现，不是供 UI 或普通场景脚本主动调用的业务命令。会话创建、替换和 Dispose 的所有权继续留在 Runtime 内部。

### 宿主控制接口

- `PauseWorld()`
- `ResumeWorld()`
- `SetWorldSpeedRatio(ratio)`

它们是合理的 World Runtime 控制入口。Godot 只表达暂停/恢复/倍率意图；秒到世界毫秒的转换仍由 Runtime 负责，倍率和逻辑时间换算仍由 Core 负责。

### 观察与诊断接口

- `GetWorldSnapshot()`：返回脱离 Core 对象的 Godot Dictionary 快照。
- `IsInitialized`、`IsFaulted`、`IsDisposed`、`CanAcceptCommands`：只读状态。
- `RuntimeReady`、`SnapshotChanged`、`RuntimeFaulted`：状态通知。

故障态保留快照用于诊断；正常 Dispose 后 Session 已释放，快照查询会被拒绝。4.11b/4.11c 探针已分别验证这两个边界。

### 当前需求命令适配器（暂定）

- `AddSingleRequirementDemand(...)`
- `MoveDemand(...)`
- `StartActiveDemand(...)`

这些接口目前服务于最小化探针和 Bridge 连通性验证。特别是 `AddSingleRequirementDemand` 明确只支持单个 requirement，是测试阶段的窄接口，不应视为最终需求编辑 API。当前没有真实游戏调用者，也没有已定义的 Jar World 玩法职责，因此暂不扩展为多需求命令体系，不引入猜测性的游戏业务 DTO。

### 初始化入口的后续判断

`InitializeWorld()` 由 `_Ready()` 自动调用；它目前保持 public，是因为初始化失败后需要允许调用方修正配置并重试。对已创建 Session 的重复初始化会被拒绝，节点退出 SceneTree 后则永久拒绝再次初始化。若未来出现正式的外部初始化调用者，再考虑把“首次初始化”和“初始化失败后的重试”拆成更明确的宿主 API；当前不做无实际调用需求的重构。

### 本次审查结论

当前边界足以支持独立 Runtime 的运行、控制、观察和故障诊断。下一阶段应由真实场景需求驱动命令契约，而不是先把探针适配器包装成完整游戏 API。旧 Jar 模块清理、伤害/奖励联动以及 Jar World 的玩法定位均不属于本次审查范围。


## 4.12b Godot 快照隔离探针

新增独立 C# 探针场景：`scenes/industrial/WorldV2SnapshotIsolationProbe.tscn`。

运行方式：Godot 4.7.1 .NET 打开该场景，运行当前场景（F6）。

探针在 Runtime 中创建一个最小需求，然后获取快照并主动修改返回给 Godot 的数据：

- 根 Dictionary 的世界时间和故障标志；
- `resourceLiquids` 嵌套 Dictionary；
- `master` 嵌套 Dictionary 及其 `baseMarks` Array；
- `demands` Array、需求 Dictionary、嵌套 `requirements` Array 和 requirement Dictionary。

随后重新获取快照，验证所有值仍来自未被污染的 Core 状态。接着再次修改第二份快照，并获取第三份快照，验证不同调用之间的嵌套 Dictionary/Array 也互相独立。

该探针只验证数据所有权和隔离，不引入新的游戏命令或玩法规则。预期关键输出：

```text
[WorldV2SnapshotIsolationProbe] detached snapshot mutation passed root=true dictionary=true array=true nested=true cross_snapshot=true
[WorldV2SnapshotIsolationProbe] passed
```

注意：当前探针覆盖了资源字典、工作台数组和需求的深层嵌套结构；如未来快照新增可变容器字段，应将其加入隔离测试。


## 4.12c 快照字段契约审查

本阶段对照 space-demo 的 Godot Dictionary 适配器与 jar-system-dotnet 当前 `WorldV2SnapshotDto`，明确快照边界。当前不新增 `schemaVersion`，也不把 Core DTO 类型直接暴露给 GDScript；在尚无正式 UI 消费者时，先固定字段语义并记录兼容规则。

### 根快照字段

| Godot key | 类型/语义 | 契约分类 |
|---|---|---|
| `worldTimeMilli` | 整数；世界时间毫秒 | 稳定时钟字段 |
| `logicalTimeMilli` | 整数；倍率/暂停换算后的逻辑时间毫秒 | 稳定时钟字段 |
| `speedRatioMilli` | 整数；1000 表示 1x | 稳定时钟字段 |
| `isPaused` | 布尔值 | 稳定时钟字段 |
| `runtimeFaulted` | 布尔值；合并 Host/Core 故障状态 | 稳定运行状态 |
| `faultReason` | 字符串；无故障时为空字符串 | 稳定诊断字段 |
| `resourceJars` | Jar 字典数组 | 当前资源展示数据 |
| `resourceLiquids` | 液体名称到数量的字典 | 当前资源展示数据 |
| `master` / `slave` | 工作台字典 | 当前工作台展示数据 |
| `demands` | 需求字典数组 | 当前需求展示数据 |
| `activeSessions` | 执行会话字典数组 | 当前执行展示数据 |
| `reservationCount` | 整数；预约数量 | 当前运行展示数据 |
| `replacement` | 工作台替换状态字典 | 当前运行展示数据 |

### 嵌套对象字段

- Jar：`id`、`shape`、`liquid`、`isMarked`。
- Workshop：`name`、`maxJars`、`maxLiquids`、`baseMarks`、`additionalMarks`、`ban`、`jars`、`liquids`。
- Demand：`id`、`area`、`type`、`requirements`、`cooldownDurationLogicalMilli`、`cooldownRemainingLogicalMilli`、`isCoolingDown`。
- Requirement：`shape`、`liquid`。
- Active session：`demandId`、`stage`、`unitDurationLogicalMilli`、`unitElapsedLogicalMilli`、`completedMasterSteps`、`completedSlaveSteps`、`isTerminal`、`succeeded`、`reason`。
- Replacement：`role`、`oldWorkshopName`、`targetWorkshopName`、`phaseDurationLogicalMilli`、`phaseElapsedLogicalMilli`、`isFinished`、`succeeded`、`interruptionCommitted`、`interruptionOutcomeUncertain`、`completedPhases`、`failureReason`、`commitWarning`。

### 当前语义约束与注意事项

1. Godot 字段名是 Runtime 适配器定义的外部键；Core DTO 的 C# 属性重命名不应自动改变 Godot 键。
2. 时间字段均为整数毫秒；`speedRatioMilli=1000` 表示 1x。不要在 GDScript/UI 再乘倍率。
3. `area`、`stage`、`role` 当前以枚举/阶段的字符串形式输出。其字符串值属于契约的一部分；未来重命名必须同步评估兼容性。
4. 当前空工作台与空替换状态都映射为空 Dictionary，而不是 null。调用方应先检查关键字段或 Dictionary 是否为空，不能把空 Dictionary 当作有效对象。
5. `liquid`、`reason`、`faultReason` 等可选文本当前统一映射为空字符串；调用方不要依赖 null 区分“无值”。
6. 集合字段以 Godot Array 输出，字典字段以 Godot Dictionary 输出；每次快照都创建独立容器。4.12b 已通过对根及多层嵌套容器进行破坏性修改的隔离验证。
7. 本快照是展示/观察模型，不是存档格式、网络协议或 Core 内部 Solver 的 `WorldSnapshot`。当前没有承诺跨版本持久化兼容。

### 变更规则

- 新增展示字段：优先新增可选键，不改变现有键含义。
- 修改字段类型、单位、枚举字符串或空值表示：视为破坏性契约变更，必须同步更新 Godot 消费者与探针。
- 删除字段或重命名键：先搜索所有场景/脚本消费者，再做迁移；不能只改 Core DTO。
- 若未来出现多个独立消费者、存档/网络需求或需要并行兼容多个 Runtime 版本，再引入明确的快照 schema version 和迁移策略；当前不为版本号而版本化。

### 审查结论

当前快照契约可作为 space-demo 内部 Godot Runtime 的初始展示接口。字段语义已记录，但在没有正式 UI 消费者前，不承诺跨项目或跨版本稳定。4.12b 的深层容器隔离已由用户本地 Godot 4.7.1 .NET 探针通过。


## 4.13a 快照消费者审计

审计范围：PR #1 当前 head 的仓库文件树、World v2 Runtime/Probe 文件、`IndustrialMain.tscn` 与其脚本，以及项目 Autoload 配置。此审计只统计当前分支中可见的引用，不把未来 UI 计划当作现存消费者。

### 结论先行

**当前没有正式游戏 UI 消费 World v2 快照。** 当前快照消费者全部属于 World v2 验证探针。项目主工业场景 `scenes/industrial/IndustrialMain.tscn` 仍挂载旧 `scripts/industrial/ui/IndustrialMain.gd`；Autoload `IndustrialRuntime` 仍指向旧 `scripts/industrial/runtime/IndustrialRuntime.gd`。这两个旧入口不读取 `WorldV2RuntimeNode` 或其快照。

因此，当前字段契约是“Runtime 与探针之间的内部集成契约”，尚不是已被正式 UI 使用的产品界面契约。

### 已观察到的消费者

| 消费者 | 实际读取字段/行为 | 用途 |
|---|---|---|
| `WorldV2RuntimeProbe.gd` | `worldTimeMilli`、`logicalTimeMilli`、`isPaused`、`master.name`、`slave.name`、`speedRatioMilli`、`demands[].id/area/type`、`runtimeFaulted` | 基本快照、命令结果和时钟行为验证 |
| `WorldV2LifecycleProbe.gd` | `worldTimeMilli`、`logicalTimeMilli` | 重复初始化不得改变世界时间 |
| `WorldV2FaultProbe.gd` | `runtimeFaulted`、`faultReason`、`worldTimeMilli` | 故障诊断与故障后快照可读性 |
| `WorldV2SnapshotIsolationProbe.cs` | `worldTimeMilli`、`runtimeFaulted`、`resourceLiquids`、`master.name/baseMarks`、`demands[].area/requirements[].shape` | 根与深层容器隔离 |
| `WorldV2FaultedCommandsProbe.cs`、`WorldV2DisposedCommandsProbe.cs` | 主要检查 Runtime 方法、属性和生命周期；不构成展示字段消费者 | 故障/释放后的操作边界 |

### 当前尚无实际消费者的快照字段

在当前正式场景/UI 与上述探针中，以下数据没有被读取用于业务或显示：

- `resourceJars`；
- 工作台容量、标记规则、禁用规则、罐子与液体库存等完整字段；
- 需求冷却字段；
- `activeSessions`；
- `reservationCount`；
- `replacement` 及其阶段细节。

其中部分字段由 Runtime 正常输出，但“已输出”不代表“已被 UI 需要”。本阶段不删除这些字段：它们仍可用于后续观察和诊断；是否保留应等真实消费者与 World v2 玩法职责明确后再决定。

### 时间与数据转换审计

- Godot Runtime 的 `_Process(delta)` 将墙钟秒换算成世界毫秒；它不读取 `speedRatioMilli` 参与二次倍率计算。
- Core WorldClock 负责把世界时间换算为逻辑时间。
- 探针通过 2x 与 0x 断言验证倍率只转换一次。
- GDScript 探针从快照读取整数时间字段，没有把逻辑时间再次乘以倍率。
- `GetWorldSnapshot()` 在 C# 中逐层创建 Godot Dictionary/Array；4.12b 已验证修改返回容器不会污染 Core 或其他快照。

### 发现与后续约束

1. 不要把旧 `IndustrialMain.gd` / `IndustrialRuntime.gd` 当作 World v2 快照消费者；它们属于旧集成路径。
2. 不应仅因快照字段当前没有消费者就立即删除；先等新的场景/UI 设计明确。
3. 新 UI 接入时，应通过一个明确的 View/Presenter 适配层读取稳定字段，不应让多个控件各自猜测字典结构。
4. 需要新增字段时，先指出具体消费者和展示/诊断目的；不要把 Core 的全部 DTO 字段无差别透传到 UI。
5. 任何时间字段都必须保留单位后缀；UI 仅格式化显示，不自行换算世界倍率。

### 审计限制

GitHub 仓库文件树和本次逐文件检查覆盖了当前可见的 World v2 Runtime、探针、工业主场景、旧工业 UI/Runtime 与项目 Autoload 配置。该结果不代表未来本地未提交文件或分支外部消费者。当前仓库没有正式 World v2 UI 消费者这一结论，以本次审计的 PR head 为准。


## 4.14a Space 生产率接入边界

jar-system-dotnet PR #57 增加了通用 UpdateProducerRates 命令；本分支的 WorldV2RuntimeNode 与 WorldV2ShipHost 已提供对应的 Godot 适配入口。Godot Runtime 探针验证有效完整速率表可提交；故障态和 Dispose 后探针也覆盖该命令的拒绝边界。

`UpdateProducerRates` 只服务于真正的时间型 Jar Producer，不是能量石解析器入口。能量石是 Space 持有的有限、typed 输入；Space 解析器消费原石并独立累计各形状进度，满 1 后产生完整空 Jar，再通过 Jar Core 的 `ImportProducedJars(operationId, shapeCounts)` 离散批次入口进入中央仓库。该入口具备操作 ID 去重、检查点持久化和仓库容量/丢弃账目。Jar 继续负责中央仓库到主台流入和后续订单规则。

时间型 Producer 接口不决定能量石大小单位、解析器属性、原石处理进度或战机液体生产率/容量。能量石与解析器配置由 Space 侧版本化构筑配置提供；不得从 sandbox 值推导生产平衡。


## 4.14b 战前原石解析器与离散 Jar 产出链

- `SpaceOreParserDefinition.gd` 是战前选定解析器的版本化定义，包含 `productionPercentage`、每形状处理速率、每形状产出一只 Jar 所需进度。
- `productionPercentage` 属于解析器本身，按百分比缩放该解析器自己的各形状处理吞吐；它不把产出比例分配给不同形状，也不属于能量石类型。
- `SpaceBattleLoadoutSnapshot` 要求构筑中恰好选择一个通用 `ore_parser`，并把完整解析器属性纳入冻结快照与指纹。
- `SpaceOreParserRuntime.gd` 无条件接受当前世界词表中的所有原石类型；类型决定目标 Jar 形状，体积是有限可解析资源量。各形状队列、进度和速率余数独立；未解析完的原石体积不会丢失。
- 达到每形状的完整 Jar 进度阈值后，解析器创建稳定 operationId 的待交付批次。批次在确认前留在解析器状态中。
- `SpaceOreParserJarIngress.gd` 通过 `WorldV2ShipHost.ImportProducedJars` 提交批次；Jar 的资源账本持久去重，中央仓库容量溢出按 Jar Core 规则丢弃。解析器先在本地 staged state 中完成整步计算，只有所有算术和单批 Int32 数量限制通过后才提交消费/进度，失败不会吞掉原石。
- `WorldV2ShipHost.AccumulateSpaceSimulationDelta` 是唯一的毫秒余数持有者，并记录唯一待提交的 prepared step。Game 先取出本步精确整数毫秒，让 Space 解析器处理并提交 Jar，再且仅一次把同一整数毫秒交给 Jar Core 推进；Host 拒绝重复累计、错值推进或重复消费 prepared step。
- `Game.gd` 暴露 `ingest_energy_stone`、`capture_ore_parser_state`，并在战斗步进前推进解析器、提交待产 Jar。解析器检查点包括拾取身份、待解析体积、独立进度、速率余数和未确认输出批次。
- `SpaceEnergyStonePickup.gd` / `SpaceEnergyStonePickup.tscn` 提供玩家碰撞拾取适配器；生成方必须在入树前提供稳定 ID、类型和体积，只有解析器接受（含重复 ID 幂等确认）后拾取物才消失。旧 `Asteroid.gd` 的 `GameState.add_ore(ore_value)` 是旧钱包资源，不被当成 typed energy stone。
- `SpaceOreParserRuntimeProbe.gd` 覆盖百分比吞吐、并行独立进度、重复拾取去重、身份冲突、固定点分步一致性、输出批次检查点和单次确认。
- `SpaceSkillBuildContextEvaluatorProbe.gd` 验证 50% / 100% 是解析器自身吞吐修正，不会把一个形状的产量份额分给另一个形状。
- `SpaceOreParserJarIngressProbe.gd` 与 `scenes/industrial/SpaceOreParserJarIngressProbe.tscn` 验证 Host 毫秒余数和 prepared-step 单次消费、Space 原石解析、Jar 离散导入、模拟丢失回执后的幂等重试，以及不会直接注入主台。

当前仍缺少实际 Hangar/敌机掉落资产对解析器配置与拾取入口的连接；没有填写任何正式生产百分比、速率、体积或进度阈值。Godot 4.7.1 .NET 对本轮最新 C#/GDScript 的实际编译和运行尚未完成，不能把静态提交视为已通过本机验收。


### 4.14c Space 原石解析器到 Jar 仓库端到端探针

新增场景：`scenes/industrial/SpaceOreParserJarIngressProbe.tscn`。

运行方式：Godot 4.7.1 .NET 打开该场景，运行当前场景（F6）。

该探针使用纯合成数据，不代表正式掉落或平衡数值。它会：

1. 从 sandbox WorldV2Options 初始化独立 `WorldV2ShipHost`。
2. 初始化一个版本化通用解析器，接收一颗圆罐类型原石。
3. 推进 1000 个逻辑毫秒，生成一只完整空圆罐的待交付批次。
4. 首次调用 Jar `ImportProducedJars`，模拟“Jar 已提交，但 Space 未收到/未保存回执”的不确定响应。
5. 保留解析器 outbox 中的同一 operationId，再次 flush；Jar 应返回持久化重复回执，Space 随后确认并清除待交付批次。
6. 验证中央仓库只增加一只 Jar，主台库存没有被直接注入。

预期输出：
```text
[SpaceOreParserJarIngressProbe] passed parsed=1 stored=1 retry_duplicate=1 workshop_bypass=0
```

该探针覆盖跨域的“有限原石输入 → Space 进度 → 整 Jar 批次 → Jar 中央仓库”链路及不确定响应重试。它不替代实际 Godot 4.7.1 .NET 编译/运行，也不构成正式 Hangar、敌机掉落资产或战斗存档接线验收。
