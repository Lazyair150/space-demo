# JarSystem.Core API 地图（阶段 2 产物）

口径：只读 `D:\codex\jar-system-dotnet\src\JarSystem.Core`。所有签名与行号来自当前源码；未运行测试、未编译本工程（引用已由阶段 0 验证过一次），因此"这些 API 能调通"仍属**构造期推断**，只有阶段 4/5 的 Bridge 实际调用才算验证。

本文件只回答：**Godot 的 JarCoreBridge 应该调哪些方法、拿什么返回、踩哪些语义坑**。凡签名未在本文件展开的，标〔待核对〕，不猜。

---

## 1. 门面与构造

```csharp
// JarSystem.cs:400-402
public JarSystem(ISystemLog? log = null, int? randomSeed = null, Vocabulary? vocabulary = null,
    WorldOptions? world = null, ISolver? solver = null,
    IIdGenerator? jarIds = null, IIdGenerator? orderIds = null)
```

构造参数决定了宿主必须准备好的东西：

| 参数 | Godot 侧怎么给 | 为什么重要 |
| --- | --- | --- |
| `log` | 传 `null` 用 `ConsoleSystemLog`，或自己实现 `ISystemLog` 转到 Godot 控制台 | 核心用它在异常/告警处出声，接错地方就"静默失败" |
| `randomSeed` | **存进存档**（`int?`，null = 每次不同，那样无法回放） | 读档必须用同一个种子（`JarSystem.cs:390`） |
| `vocabulary` | `null` → 由 `world.BuildVocabulary()` 构造（`:412`） | 词表顺序决定液体键序 |
| `world` | `WorldOptions`（`Config/WorldOptionsJson.FromJson` 从 `config/world.json` 或关卡文件来，`:411`） | 关卡只给世界，核心不认识"关卡" |
| `solver` | `null` → `StateSpaceSolver` + `ModifierAwareSolver` 装饰（`:442`） | **GDScript 不写求解算法**的依据就在这里：求解已封在 Core |
| `jarIds` / `orderIds` | 正常运行可 `null`；**读档必须注入全新 `SequentialIdGenerator`** | 否则重建出的 ID 与原次不同（`:418-419`、`:83-90`） |

构造期就会做的装配（写 Bridge 时不要重复做）：`OrderTemplates` 从世界配置解析并**立即校验**（`:413-416`）、`FlowSettings` 取世界流入参数（`:420`）、`ResourceLedger` 在任何产出之前建立（`:427-428`）、`PresentationFeed` 只订阅总线不回写（`:429-432`）、`ProcessSystem` + `WorldTime` 建立（`:449-452`），最后 `InitializeDefault()` + `RecordInitialStock()`（`:465-466`）。

---

## 2. 只读视图（读状态、读日志）

| 成员 | 签名 / 位置 | 说明 |
| --- | --- | --- |
| 工作台 | `IReadOnlyList<Workshop> Workshops`（`JarSystem.cs:94`） | 真只读包装，向下转型也改不动（`:47-51`） |
| 订单 | `IReadOnlyList<Order> Orders`（`:95`） | 同上 |
| 订单模板库 | `OrderTemplateLibrary OrderTemplates`（`:102`） | 空库 = 世界不提供模板 |
| 事件历史 | `IReadOnlyList<Dictionary<string,object?>> EventHistory`（`:103`） | 内存只留 10 条（`:128`） |
| 液体速率 | `IReadOnlyDictionary<string,double> LiquidProductionRate`（`:110`） | 修改必须走意图方法 |
| 液体产能体 | `Production.LiquidProduction LiquidProduction`（`:113`） | 带累加器（能表达 0.5 份/tick） |
| 命令日志 | `IReadOnlyList<WorldCommand> CommandLog`（`:69`） | 存档原料 |
| 随机种子 | `int? RandomSeed`（`:72`） | 存档原料 |
| ID 源 | `IIdGenerator JarIds` / `OrderIds`（`:87`/`:90`） | 存档原料（读档要新的） |
| 过程日志 | `ProcessJournal Journal`（`:251`）；`IReadOnlyList<JournalEntry> StepsFor(string subject, int subjectId)`（`:278`） | 记录栏数据源 |
| 世界时间 | `WorldTime Time`（`Runtime.cs:14`）；`bool IsTimePaused`（`:17`） | 唯一时间门面 |

---

## 3. 写世界的意图方法（Bridge 唯一允许的入口）

### 3.1 工作台

```csharp
public void AddWorkshop(Workshop workshop);                                   // :543
public void ClearWorkshops();                                                 // :559
public void CreateWorkshop(string name, List<string> baseMarks,
    List<string>? additionalMarks = null, List<string>? ban = null);          // :666
public void CreateRandomWorkshop();                                           // :672
public void SetWorkshopCapability(int index, List<string>? baseMarks = null, …); // :696  〔参数后半段待核对〕
public void UpdateWorkshopCapacity(…);                                        //  〔待核对：未展开签名〕
public Dictionary<string, object?> SetMaster(int index);                      // :647
public Dictionary<string, object?> SetSlave(int index);                       // :658
public void SetMasterIndex(int? index);                                       // :603  null = 不设主台
public void SetSlaveIndex(int? index);                                        // :622
```

`SetMasterIndex/SetSlaveIndex` 是"装配期摆台"用的（关卡开局用它们，`JarSystemService.cs:140-141`）；`SetMaster/SetSlave` 返回字典，是旧调试页的形状，新 Bridge 用前者即可。

### 3.2 订单

```csharp
public (bool Success, string? Error) CreateOrder(List<Requirement> requirements,
    string orderType = Constants.OrderType.A);                                // :708
public (bool Success, string? Error) CreateOrderFromTemplate(string templateName); // :721
public (bool Success, string? Error) CreateRandomOrder();                     // :730
public (bool Success, string? Error) DeleteOrder(int index);                  // :751
public bool MoveOrder(int orderId, int dir);                                  // :744
public void AddOrder(Order order);                                            // :574
public void ClearOrders();                                                    // :581
```

注意 `DeleteOrder` 与 `MoveOrder` 的参数口径不同：前者吃**下标**，后者吃**订单 id**。Web 侧靠 `ResolveOrderIndex` 把 `orderId` 翻成下标（`CommandDispatcher.cs:388-406`），Bridge 也要做同一件事——这是最容易把"删错单"写出来的地方。

### 3.3 可行性

```csharp
public FeasibilityResultData? CheckFeasibility(int orderIndex);               // :760
public List<AutoCheckResultDto> CheckAllFeasibility();                        // :772
```

两者都是**只读分析 + 把结果写回订单缓存**（会进 `state.orders[].feasibilityResult`），不改世界资源。

### 3.4 执行（双轨，务必分清）

```csharp
public ??? ExecuteOrder(int orderIndex);                                      // :789 〔返回签名待核对，含操作明细〕—— 同步轨：一次跑完
public (bool Started, string? Error, int? ProcessId) StartOrder(int orderIndex, int? deadlineTicks = null); // :835 异步轨：起过程
public (bool Cancelled, string? Error) CancelProcess(int processId, string? reason = null);                 // :1035
```

- 异步轨是本项目的正式玩法：`StartOrder` 只登记过程，之后**由世界 tick 驱动**（每 2 刻一个单位）。进程内的进度经 `state.processes` 与过程消息暴露。
- `CancelProcess` **不回滚已完成部分**，订单按失败收尾。
- 同步轨只服务旧调试页；Godot 第一版**不应**提供它（否则同一单有两条执行路径，验收无法收敛）。

### 3.5 生产、时间、重置

```csharp
public int Tick(int count = 1);                                  // Runtime.cs:43
public bool PauseTime();                                         // :20
public bool ResumeTime();                                        // :30
public void UpdateProducerRate(string name, string shape, double rate);      // :73
public void UpdateLiquidProductionRate(string liquid, double rate);          // :86
public void SetLiquidProductionRate(string liquid, double rate);             // :117
public void SetFlowSettings(int jarCount, int liquidAmount);                 // :127
public void SetAutoCheck(bool enabled);                                      // :97
public void ResetProducerModule();                                           // :104
public void Reset();                                                         // :141
```

---

## 4. `Tick` 的真实语义（阶段 5/8 的实现依据）

```csharp
// JarSystem.Runtime.cs:43-71
if (count < 0) throw new ArgumentOutOfRangeException(...);
if (count == 0) return 0;
if (Time.State == WorldTimeState.Paused) return 0;               // 暂停：不推进、不产出、不写日志
if (!turns.Allows(count)) throw new DomainValidationException(turns.ReasonIfBlocked(count));
if (Outcome.IsOver) throw new DomainValidationException("本关已经结束，无法继续推进；需要继续游玩请重开本关");
for (int i = 0; i < count; i++) { Processes.Pipeline.AdvanceOneTick(); Time.OnAdvanced(); if (Outcome.IsOver) break; }
Processes.Pipeline.RunCallBoundary();                            // 调用边界才把仓库搬向主台
Record(WorldOps.Tick, intA: applied, preserveTime: true);
```

对 Godot 的四个直接结论：

1. **`Tick` 会抛异常**，不是返回错误码。回合耗尽与结局已定都会抛 `DomainValidationException`，Bridge 必须捕获并转成 `success=false`，不能让它冒到 C# 之外。
2. `Tick` **返回值恒为 0**（`Runtime.cs:70`），推进了几刻要看 `state.turns.used` 的差值，别信返回值。
3. **暂停是核心态**（`PauseTime/ResumeTime`），不是 UI 局部状态；暂停期间 `Tick` 静默返回 0，不会报错。
4. **流入只在调用边界发生一次**（`RunCallBoundary`），所以 `Tick(1)` 与 `Tick(5)` 的流入次数不同 —— 时间累积器若要补算多刻，必须明确"一次调用补 N 刻"还是"N 次调用"，否则玩家看到的主台资源会不一样。这是阶段 8 必须先定下来的策略。

tick 管线已登记的阶段（`JarSystem.cs:461-464`）：`TickPhase.Production`（产出，每 tick 一次）、`TickPhase.Flow`（流入，每次调用一次）。过程执行由 `ProcessSystem.Pipeline` 在 `AdvanceOneTick` 内推进。

---

## 5. 对外 DTO 契约（Bridge 的映射对象）

`GetState()` → `StateDto`（`Services/StateDtos.cs`）；`WorldMeta()` → `WorldMetaDto`（词表：`shapes` 8 个、`liquids` 2 个）。**所有键名由 `[JsonPropertyName]` 固定，camelCase 命名策略对它们不生效**（`StateDtos.cs:11-13`）—— 也就是说 JSON 出去的键名就是这些字面量，改它 = 破坏契约。

| DTO | 键 | 位置 |
| --- | --- | --- |
| `StateDto` | `workshops` / `orders` / `warehouse` / `producerStatus` / `globalState` / `eventHistory` / `worldRevision` / `processes` / `turns` / `phase` / `level` | `:15-59` |
| `WorkshopStateDto` | 12 键：`index` `name` `baseMarks` `additionalMarks` `ban` `maxJars` `maxLiquids` `jars` `liquids` `canPourShapes` `isMaster` `isSlave` | `:128-143` |
| `JarStateDto` | 5 键：`id` `shape` `liquid` `isMarked` `description` | `:145-153` |
| `OrderStateDto` | 7 键：`index` `id` `type` `requirements` `status` `feasibilityResult` `description`；**`status` 是中文常量** `待执行/执行中/成功/失败`（`Config/Constants.cs:38-44`），不是 `pending/success/failed` | `:155-171` |
| `WarehouseStateDto` | 5 键：`jars` `jarList` `liquids` `discardedJars` `discardedLiquids`（注释写"4 个键"，实际 5 个 → 注释滞后，按属性走） | `:176-190` |
| `GlobalStateDto` | 5 键：`autoCheckEnabled` `currentMaster` `currentSlave` `masterName` `slaveName` | `:192-200` |
| `ProducerStatusDto` | 7 键：`producers` `generators` `slots` `flow` `liquidRates` `liquidAccumulated` `warehouse`（注释写"5 个键"，实为 7） | `:212-237` |
| `TurnStateDto` | 3 键：`used` `limit`（0=不限） `exhausted` | `:72-80` |
| `LevelStateDto` | 4 键：`goalOrders` `completedOrders` `outcome`(inProgress/won/lost) `reason` | `:61-70` |
| `ProcessStateDto` | 13 键：`id` `kind` `subject` `subjectId` `state` `outcome` `currentStep` `totalSteps` `startedAtTick` `deadlineTick` `remainingTicks` `ticksUntilNextUnit` `blockedReason` `lastJournalSeq`（实为 14 属性，注释写 13） | `:82-126` |
| `FeasibilityResultData` | 12 键：`feasible` `undetermined` `blockage` `reason` `timestamp` `directCount` `operationCount` `solverPath` `masterPath` `checkMethod` `transferJarIds` `transferLiquids` | `Orders/Order.cs:181-218` |
| `AutoCheckResultDto` | 载荷 = `orderId` 等 3 键 + 上面 12 键 | `Orders/AutoCheckResultDto.cs` |

三处注释计数与实际属性数不一致（warehouse / producerStatus / processState）。这是**注释滞后**，不影响序列化结果；移植时以属性表为准，不要按注释数数。

---

## 6. 异常与失败语义

| 情形 | 表现 | Bridge 必须做什么 |
| --- | --- | --- |
| 世界配置非法 | 构造期抛；Web 宿主选择"拒绝启动"（`JarSystemService.cs:212-229`） | 启动时校验一次，失败给玩家一句人话并停用工业界面，不要静默降级 |
| 参数越界（负速率、未知液体、罐数上限…） | `DomainValidationException` | 捕获 → `error_code` + 人话，UI 保持原状 |
| 回合耗尽 / 结局已定 | `Tick` 抛 `DomainValidationException` | 同上；UI 侧按钮本应已禁用，属于"双保险" |
| 分析不可行 | **不抛**，返回 `feasible=false` + `blockage`/`reason` | 原样显示，不要自己编理由 |
| 订单不存在 | 门面返回 `false` 或 null | 转 `error`，并重拉 state（列表可能已被别处改动） |

`error_code` 的统一建议：Bridge 只给三类 —— `invalid_arg`（参数/校验）、`illegal_state`（回合/结局/阶段）、`internal`（未预期异常 + 日志）。**不要**把 Core 的异常类名透给 GDScript。

---

## 7. 存档原语（阶段 11 直接可用）

```csharp
IReadOnlyList<WorldCommand> CommandLog;   // JarSystem.cs:69
int? RandomSeed;                          // :72
SessionReplay.Into(JarSystem target, IEnumerable<WorldCommand> commands);  // Sessions/SessionReplay.cs:26
```

读档流程（`SessionReplay.cs:14-19` 明示的前置条件）：

1. 用**同一份** `WorldOptions`（即同一份 world/关卡配置——存档里要记"是哪一份"）、
2. 用**同一个** `randomSeed`、
3. 用**全新的** `new JarSystem(world: world, randomSeed: seed, jarIds: new SequentialIdGenerator(), orderIds: new SequentialIdGenerator())`、
4. `SessionReplay.Into(replay, commands)`。

两个已知坑（都是 Core 注释里写明的实测结论，不是推测）：
- `WorldCommand.time` **必须**一起存，否则 `eventHistory[].timestamp` 与原次不同（`WorldCommand.cs:31-36`）。
- 回放走的是与宿主相同的意图方法，因此回放本身也会记录日志；"回放出的系统日志与原日志逐条相同"可以当作读档自检（`SessionReplay.cs:20-21`）。

Web 宿主**没有**用这套东西（没有存档端点，见 `01-web-feature-map.md` §8），所以读档逻辑要在 Bridge 侧新写，且没有现成调用范例。

---

## 8. Godot Bridge 的最小 API 面（第一版）

第一版只接通"一条链路"，Bridge 只需暴露下面这些（其余等阶段 7 之后按需加）：

- 读：`GetState()`、`WorldMeta()`、`StepsFor(subject, subjectId)`、`OrderTemplates`（**阶段 7 补：模板清单**，界面据此列"可派的单"）、`Presentation`（帧流，见 §9）、`CommandLog` + `RandomSeed`（存档）。
- 写：`SetMasterIndex`、`SetSlaveIndex`、`CreateRandomOrder`、`CreateOrderFromTemplate(name)`（**阶段 7 补**，`JarSystem.cs:721`，返回 `(bool,string?)`）、`DeleteOrder`、`MoveOrder`、`CheckFeasibility`、`CheckAllFeasibility`、`StartOrder`、`CancelProcess`、`UpdateProducerRate`、`UpdateLiquidProductionRate`、`Tick`、`PauseTime`、`ResumeTime`、`Reset`。
- 不暴露：`CreateOrder` / `CreateWorkshop` / `UpdateWorkshopCapacity` / `SetWorkshopCapability` / `ExecuteOrder`（创建型与同步轨，第一版不需要）。

按指导书硬规则：Bridge 只做适配与 DTO 转换，**不得**在里面重新实现可行性、搬运、产出、判胜的任何一条规则；GDScript 侧不得出现求解/校验算法。

---

## 9. 过程日志与表现层帧流（阶段 4 实测补齐）

**结论：`StepsFor` 不能当"事后查询"用，过程可见必须走帧流。**

1. `StepsFor(subject, subjectId)`（`JarSystem.cs:278`）先做 `Processes.TryGetProcessId(subject, subjectId, out processId)`，再按 `entry.ProcessId == processId` 过滤日志。
2. `subject` 是**展示语言字符串**：`JarSystem.cs:1024` 用 `new ProcessDefinition(ProcessKinds.OrderExecution, "委托 #" + order.Id, order.Id, …)` 起过程 ⇒ `subject == "委托 #1"`、`subjectId == 订单 id`（与 `ProcessStateDto` 的 `subject`/`subjectId` 同值）。
3. **过程结算后主体映射被淘汰**，之后调用返回空数组。Core 注释（`:271-273`）明确要求把空读成"没有**保留的**步骤"，不是"没发生过"。
4. 实测：`start_order` 后立刻查 → 0 条；推进一刻后再查 → 仍 0 条。原因是**一次 `Tick` 里过程通常整个跑完**（本例各模板 `directCount` 已覆盖全部需求，MATCH 不计时），过程在 tick 内部就结算了。

因此"记录栏"的数据源只能是 **`PresentationFeed` 帧流**：

```csharp
public PresentationFeed Presentation { get; }   // JarSystem.cs:384，构造期 new PresentationFeed()（:431）
Presentation.Subscribe(IPresentationSink sink);  // 同步派发；纪律：不得抛异常/不得改世界/不得阻塞
Presentation.Since(int afterSeq);                 // 游标式读取；IsTruncated 表示历史被裁剪
```
`PresentationFrame`（`Presentation/PresentationFrame.cs`）= `Seq` / `Kind`（`WorldChanged|ProcessChanged|TimePaused|TimeResumed`）/ `Op` / `Subject` / `SubjectId` / `Tick` / `Revision` —— **只有引用，没有状态**，细节要回查世界。

Bridge 的做法（已实装）：实现 `IPresentationSink`，在 `OnFrame` 里把帧记进缓冲，并**当场**用 `StepsFor(subject, subjectId)` 附一份过程日志快照（此刻过程还在册才取得到）；GDScript 用 `poll_events()` 一次取走 `{frames, dropped}`。实测：一次 `tick(1)` 后取到 16 帧、帧内日志最多 5 条 —— 这就是"过程可见"的落地方式。

---

## 10. 本阶段未覆盖与风险

- **未运行**：没有编译或调用过上述任何方法；`ExecuteOrder` / `UpdateWorkshopCapacity` / `SetWorkshopCapability` 的完整签名未展开〔待核对〕。
- 未核对 `Turns`（`World/TurnBudget.cs`）、`Outcome`（`World/LevelOutcome.cs`）、`Phase`（`World/WorldPhase.cs`）的**公开成员签名**，只确认它们被 `Tick` 使用。
- 未核对 `WorldOptionsJson.FromJson` 的容错口径（错误报在哪里、是否给行号），阶段 4 实现"读关卡配置"时要补。
- 未核对 `ISystemLog` 的接口成员；接 Godot 控制台前需读一次。

> 阶段 4 已实装并跑通 `scripts/industrial/bridge/JarCoreBridge.cs` + `tests/industrial/bridge_smoke.gd`（33 项断言全过），上述"未核对"项中 `WorldOptionsJson`（`UnmappedMemberHandling=Disallow`、拼错键名抛 `JsonException`、容忍缺字段）与 `ISystemLog`（`Error(string, Exception?)` / `Info(string)`）已补核对；`TurnBudget`/`LevelOutcome` 只从使用处确认行为（`turns.limit`、`tick` 超限抛异常、`outcome` 字段），公开成员仍未逐个展开。
