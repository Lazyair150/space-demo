# 最新 JarSystem Web 功能调查（阶段 1 产物）

调查口径：只读 `D:\codex\jar-system-dotnet\src\JarSystem.Web` 与 Core 的契约文件（未启动 `run.bat`、未在 jar 项目内产生 bin/obj，未改其任何文件）。每条结论都标注可回溯的文件与行号。

未做的事（不得据此宣称已验证）：没有打开过页面、没有点击、没有录制手感 —— 因此"布局是否好看、点击是否顺手"一律〔未验证〕。本文件只回答"Web 端有哪些功能、谁在什么时候调 Core 的哪个方法"。

---

## 1. 页面结构

### 主要页面

| 页面 | 定位 | 谁打开它 | 数据源 |
| --- | --- | --- | --- |
| `wwwroot/play.html`「陶罐解谜」 | 唯一面向玩家的游戏页 | `run.bat`（`http://localhost:5289/play.html`） | WS `/ws` 的 `state` / `frame` / `steps` 消息 |
| `wwwroot/index.html`「陶罐生产与订单系统 v3.1」 | 开发调试控制台（全命令面板） | 开发者手输 URL | 同上 + 4 个 modal（订单/工作台/执行/场景） |
| `wwwroot/world.html`「世界视图」 | 诊断页（世界状态、帧时间线、不变量、资源账本） | 开发者手输 URL | `/api/state`、`/api/invariants`、`/api/provenance` + WS `frame` |

### 入口

- `run.bat` 起 `src\JarSystem.Web`，绑 `http://localhost:5289`，打开游戏页。
- 无 `ASPNETCORE_URLS` 时默认 `http://127.0.0.1:3457`（`Program.cs:32`）。
- 非本机连接一律 403，仅 `JAR_ALLOW_REMOTE=1` 放开（`Program.cs` 中间件）。
- 管理操作（`reset` / `restartLevel` / `loadLevel` / 写场景）在配置了 `JAR_ADMIN_TOKEN` 时要求 `X-JarSystem-Admin` 头逐一相同（`JarSystemService.cs:33-41`）。

### 主要区域（play.html）

顶栏：关卡名 `lvname`、回合 `turns`、目标 `goal`、阶段 `phase`、执行中计数 `busy`、连接状态 `conn`，右侧「重开本关」「关卡选择」「世界视图」。
提示条：`lvhint` = 当前关卡的 `hint`。
左列：主台面板（`masterName` + `masterBody` + 「换主台」）、从台面板（`subName` + `subBody` + 「换从台」「撤掉从台」）、产线面板（`linesBody` + `linesHint`，由 `production-view.js` 渲染）、中央仓库（`stageBody` + `stageHint`）。
右列：订单面板（`ordersBody` + 「随机派一单」）、记录面板（`logbar` 筛选条 + `logBody`）。
底部：「推进一回合」（`advanceBtn`，被结局/回合耗尽禁用）。

### 三个页面的边界（很重要，决定移植范围）

- `play.html` 只做两件事：把 `getState` 画出来、把点击翻译成内核命令（`play.js:1-13` 的自我声明）。
- `index.html` 额外拥有**创建型**命令（`createOrder` / `createWorkshop` / `updateWorkshopCapacity` / `setWorkshopCapability` / `executeOrder` / `setTickInterval` / `setAutoCheck` / 场景编辑）。
- `world.html` 是**只读诊断**，不派发任何改变世界的命令（除「推进一回合」外）。
- 三者共用同一份 WS 契约；`CommandDispatcher.cs:7-12` 明文规定：命令名、消息名、payload 键集合不得改动。

---

## 2. 工作台

- 显示数据：`state.workshops[]`，12 个键（`Services/StateDtos.cs:128-143`）—— `index`、`name`、`baseMarks`、`additionalMarks`、`ban`、`maxJars`、`maxLiquids`、`jars[]`（`id`/`shape`/`liquid`/`isMarked`/`description`）、`liquids{名:数量}`、`canPourShapes`、`isMaster`、`isSlave`。
- 用户操作：换主台 → `setMaster{index}`；换从台 → `setSlave{index}`；撤从台 → `setSlave{index:-1}`（`play.js:839-841`）。这些不是本页自算，全部转发。
- 后端接口：WS 命令 `setMaster` / `setSlave`；Core 侧是 `SetMasterIndex(int?)`（`JarSystem.cs:603`）、`SetSlaveIndex(int?)`（`JarSystem.cs:622`），带返回值的版本 `SetMaster(int)` / `SetSlave(int)`（`JarSystem.cs:647`/`658`）供旧调试页使用。
- Core 调用链：命令分派器 → `JarSystem` 门面 → 工作台服务；核心改写世界后由宿主广播 `state`。
- 操作结果：页面**不做本地乐观更新**，一律等内核的 `state` 回来重画（`play.js:70-79`）。
- 液位语义（易错点）：`maxLiquids` 是**每种液体各自**的上限，不是合计（`play.js:208-215` 有专门注释）。把"酒2 + 蜜4"跟 5 比是错的。
- 禁令语义：`ban` 里的液体可以存在台面上，但不能用（`play.js:198-204` 的 title 文案："这台禁它：能存不能用"）。

---

## 3. 订单

- 显示数据：`state.orders[]`，7 个键（`StateDtos.cs:155-171`）—— `index`、`id`、`type`（A/B）、`requirements[{shape,liquid}]`、`status`、`feasibilityResult`（与消息同类型，12 键）、`description`。
  - **`status` 是中文常量，不是 `pending/success/failed`**：`Config/Constants.cs:38-44` 定义 `待执行 / 执行中 / 成功 / 失败`（`StateSerializer.cs:177` 原样下发）。
  - 因此原客户端 `play.js:256/260/261/568/572` 的 `o.status === 'success' / 'failed'` **永远不成立**——它的"已完成/已失败"徽章与结算 toast 是坏的（这是原客户端的缺陷，不是设计意图）。Godot 客户端必须按中文常量比较。
- 创建操作：游戏页只有「随机派一单」→ `createRandomOrder`（无参）。完整创建（A 类主台 / B 类从台 + 需求行）只在 `index.html` 的 modal 里 → `createOrder`。Core：`CreateOrder(List<Requirement>, string orderType = "A")`（`JarSystem.cs:708`）、`CreateRandomOrder()`（`:730`）、模板派单 `CreateOrderFromTemplate(string)`（`:721`）。
- 删除操作：`deleteOrder{orderId}` → `DeleteOrder(int index)`（`:751`），返回 `(bool Success, string? Error)`；页面用 toast 显示 `Error`。
- 执行操作 —— **有两条轨，这是本系统最关键的语义**：
  - 同步轨 `executeOrder{orderId}` → `ExecuteOrder(int)`（`JarSystem.cs:789`）：一次调用内跑完所有步骤，回 `orderExecuted{success,reason,operations,transferOccurred}`。只有旧调试页用。
  - 异步轨 `startOrder{orderId}` → `StartOrder(int, int? deadlineTicks)`（`JarSystem.cs:835`）：只"开始"，随后**由世界 tick 驱动**（每 2 刻一个单位，`CommandDispatcher.cs:222-236` 注释），进度经过程消息与 `state.processes` 投影；可被 `cancelProcess{processId}` 取消，**已完成部分不回滚、订单按失败收尾**（`:238-250`）。
  - 游戏页只用异步轨（`play.js:856-862`），且要求 `state.phase === 'setup'` 才允许点「开始」（`play.js:293`）。
- 排序：`moveOrder{orderId, dir:±1}` → `MoveOrder(int orderId, int dir)`（`:744`）。
- 后端接口：以上全部为 WS 命令；`ResolveOrderIndex` 优先按 `orderId` 定位，兼容旧 `orderIndex`，找不到回 `error{message:"订单不存在"}`（`CommandDispatcher.cs:387-406`）。
- 空态：无订单时显示"还没有订单（点右上角「随机派一单」，或重开本关）"（`play.js:246-249`）。

---

## 4. 可行性分析

- 输入：`checkFeasibility{orderId}`（单条）或 `checkAllFeasibility{}`（全部）。Core：`CheckFeasibility(int orderIndex)`（`JarSystem.cs:760`，返回可空 `FeasibilityResultData`）、`CheckAllFeasibility()`（`:772`，返回 `List<AutoCheckResultDto>`）。
- 执行过程：核心求解器给出路径与阻断原因；宿主在 `createOrder` 后若 `sys.AutoCheckEnabled` 为真会自动跑一次全量并广播 `autoCheckResults`；`AutoCheckBackgroundService`（`PeriodicTimer`）也会定时跑。
- 返回数据：`FeasibilityResultData` **12 键**（`Orders/Order.cs:172-218`）—— `feasible`、`undetermined`、`blockage`、`reason`、`timestamp`、`directCount`、`operationCount`、`solverPath[]`、`masterPath[]`、`checkMethod`、`transferJarIds[]`、`transferLiquids{}`。
- 页面反馈：
  - 进度分子 = `feasible ? 需求条数 : directCount`，分母 = 需求条数（`play.js:254-255`）。
  - 可行时展示"做法"：A 类 = `solverPath`；B 类 = `masterPath`（主台）→ 「把选定罐子与液体迁移到从台」→ `solverPath`（从台）（`play.js:347-366`）。步骤 `type === 'MATCH'` 不计时（`play.js:343-345`）。
  - 不可行时**原样显示** `blockage || reason`，页面不编理由（`play.js:267-270`）。
  - 每步描述优先用内核给的 `description`（`play.js:397`），页面只在缺字段时按 op 兜底措辞。
- 可用性与一致性：`allFeasibilityResults` / `autoCheckResults` 的 `data` **是数组本身**（页面兼容了 `{results:[...]}` 的旧形状，`play.js:113-118`）。

---

## 5. 生产

- 生产数据：`state.producerStatus`（`StateDtos.cs:212-237`）—— `producers[{name, rates{形状:速率}}]`、`generators[{shape, rate, accumulated, producers}]`、`slots{used, limit}`、`flow{jars, liquidPerLiquid}`、`liquidRates{}`、`liquidAccumulated{}`、`warehouse{jars, liquids}`。
  - （注释写"5 个键"，实际声明 7 个属性；`WarehouseStateDto` 注释写"4 个键"，实际 5 个。属注释统计口径滞后，不是契约缺陷，但移植时按属性表走，别按注释数数。）
- 推进方式：
  - 手动：`manualTick{count}`（游戏页固定 `count:1`，`play.js:816-821`），Core `Tick(int count = 1)`（`JarSystem.Runtime.cs:43`）。
  - 自动：`startTick` / `stopTick` 只翻 `svc.IsRunning` 开关，真正的循环由 `TickBackgroundService`（`PeriodicTimer`，`JarSystemService.cs:207-210` 注释）按 `TickIntervalMs` 驱动，默认 2000ms。
- 时间规则（移植时必须照抄的判定）：
  - 判定只认**逻辑 tick**；`setTickInterval` 只改节奏（100~60000ms），不改结论（`CommandDispatcher.cs:252-264`）。
  - `count < 0` 抛参数异常；`count == 0` 直接返回；`Time.State == Paused` 时返回 0 不推进（`Runtime.cs:45-50`）。
  - 回合预算：`Turns.Allows(count)` 不通过抛 `DomainValidationException(turns.ReasonIfBlocked(count))`；`Outcome.IsOver` 时抛"本关已经结束，无法继续推进；需要继续游玩请重开本关"（`Runtime.cs:52-57`）。
  - 批量 `count>1` 时逐刻走管线，一旦达成结局立即停在那一 tick（`Runtime.cs:61-67`）。
  - 每步先走 tick 管线，再在调用边界把仓库资源搬向主台（`Runtime.cs:39-41`）。
- 页面反馈：产线卡显示每个形状的"合计 x.xx / 回合"与每个生产源的快捷档位 `0 / 0.2 / 0.4 / 0.6`（非档位显示"当前 x.xx"）；液体卡单独一格"自产 / 累加 / 仓库库存 / 每次推进最多流入 N 份"；还有一条常驻说明"生产 ≠ 流入"（`production-view.js:7`、`:58-79`、`:109-115`）。
- 速率设置：`updateProducerRate{producerName, shape, rate}` → `UpdateProducerRate`（`Runtime.cs:73`，上下界由 Core 校验）；`updateLiquidRate{liquid, rate}` → `UpdateLiquidProductionRate`（`Runtime.cs:86`）。

---

## 6. 仓库

- 资源类型：罐子（每只独立，带形状与液体）、液体（`酒` / `蜜` 两种，词表在 `world.json` 的 `liquids`）、溢出丢弃计数。
- 数量：`state.warehouse`（`StateDtos.cs:176-190`）—— `jars`、`jarList[]`（**逐只**，顺序 = 流入时主台取用顺序：先主台基础形状、再先进先出）、`liquids{}`、`discardedJars`、`discardedLiquids{}`。
- 操作：玩家不能直接操作仓库（没有"从仓库拿一只"的命令）。仓库→主台的搬运由流动参数决定：`flow.jarCount`、`flow.liquidAmount`，每种液体的自产速率在 `flow.liquidRate`。
- 数据来源：`ResourceLedger` 记录每一次增减，`/api/provenance?since=N` 读出，`cause` 六种（产线产出 `production`、开局库存 `stock`、仓库流入主台 `flow`、主台→从台 `transfer`、从台→主台 `return`、容量溢出丢弃 `discard`）。
- 语义提醒（移植时最容易写错的两条）：
  - 液体自产为 0 时，仓库**已有库存**仍会流进主台 —— 搬的是库存，不是新产出（`production-view.js:111-114`）。
  - `flow.liquidPerLiquid` 是**每种液体各自**的每次流入上限。

---

## 7. 日志

- 日志类型（两套，不能混）：
  1. **命令日志** `WorldCommand`（Event Sourcing，`Sessions/WorldCommand.cs`）：记"宿主对世界下了一次什么意图"，取 `sys.CommandLog`（`JarSystem.cs:69`），配 `sys.RandomSeed`（`:72`）可完整重建世界。
  2. **过程日志** `ProcessJournal` / `JournalEntry`：记"某一单执行到第几步、做了什么"，取 `sys.StepsFor(subject, subjectId)`（`JarSystem.cs:278`），WS 侧投影为 `StepEntryDto{Seq, Tick, Kind, StepIndex, Operation, Summary}`（`CommandDispatcher.cs:414-427`）。
- 记录时机：每次命名意图方法（`Record(WorldOps.XXX)`）；过程侧在 `started` / `step_begin` / `step_applied` / `blocked` / `failed` / `succeeded` 等节点写入。
- 数据来源：`getSteps{subject, subjectId}` 拉取；页面按 `seq` 去重（`play.js:535-550`），350ms 节流但保留尾随请求（`:519-533`），避免丢掉最终那条 `succeeded`。
- 事件历史：`state.eventHistory` 最近 **10 条**（`StateDtos.cs:26-27`，内存保留上限见 `JarSystem.cs:120-125`）。
- 页面职责：`OP_ZH` 把 `operation`（`pourIn` / `reshape` / `transfer` / `match` …）译成中文**措辞**，不做任何判断（`play.js:462-503`）。

---

## 8. 存档

- **Web 端没有任何存档功能**（这是调查的硬结论，不是推论）：
  - 没有 save / load 端点，`Program.cs` 的 HTTP 端点只有 state / levels / provenance / invariants / scenario 五组。
  - 世界只活在 `JarSystemService.System` 这个内存引用里；刷新页面 = 重新连接同一个内存世界；重启进程 = 全新世界。
  - 唯一写盘的是场景编辑器（`POST /api/scenario` → `config/scenario.json`，重启生效），那是配置，不是进度。
- Core 已备好的存档原语（**Godot 阶段 11 可以直接用，不需要自己在 Core 里加序列化**）：
  - `sys.CommandLog`：`IReadOnlyList<WorldCommand>`，每条带 `seq` / `op` / `time` / 参数。
  - `sys.RandomSeed`：重建随机性必须用它。
  - `SessionReplay.Into(target, commands)`（`Sessions/SessionReplay.cs:26`）：把命令重放进一个**全新**系统。
  - 前置条件（`SessionReplay.cs:14-19` 明文）：同样的世界配置 + 同样的种子 + **全新的 ID 源**：
    `new JarSystem(world: world, randomSeed: seed, jarIds: new SequentialIdGenerator(), orderIds: new SequentialIdGenerator())`。
  - 已知坑（Core 注释里记着实测踩过）：读档必须把 `WorldCommand.time` 一起存，否则 `eventHistory[].timestamp` 与原来不一致，"读档后状态逐字节一致"立刻失败。
- 三种重置语义（别混用）：
  - `reset`：世界回默认装配（`JarSystem.Runtime.cs:141-160`，含清账本、清过程、`_completedOrders=0`）。
  - `restartLevel`：宿主把世界推回本关开局 + 按关卡模板重新派单（`JarSystemService.cs:129-134`）。
  - `loadLevel{index}`：**换关** = 起一局新世界，旧世界连同过程/订单/日志一起消失（`JarSystemService.cs:98-115`）。

---

## 9. 其他功能

| 功能 | 数据/入口 | 说明 |
| --- | --- | --- |
| 关卡 | `config/levels/01_学会改形.json` … `06_抢资源.json`（6 个），`LevelCatalog.cs` | 一关 = 打包好的 `world` + `hint` + `turns` + `goal` + `master`/`slave` + `orderTemplates`。**核心不认识"关卡"**，装配与派单都在宿主 |
| 世界装配 | `config/world.json`（2982 B） | 8 形状 / 2 液体 / 4 生产者 / 4 工作台 / 流入 3 罐·每液 2 份；文件存在但校验失败 ⇒ **拒绝启动** |
| 场景（世界事件） | `config/scenario.json` + `/api/scenario*` | 初始修饰器 + 定时事件；保存后**重启生效** |
| 不变量 | `/api/invariants` | `WorldInvariants.Check()` → `{ok, count, violations[{code,message,severity}]}`，诊断用 |
| 资源账本 | `/api/provenance?since=N` | 逐条 `seq/tick/cause/kind/name/amount/from/to/reason`，诊断用 |
| 帧流 | WS `frame` | `kind: worldChanged / processChanged`，带 `subject`/`subjectId` 时页面去拉 `getSteps` |
| 协议守卫 | — | 命令名/消息名/`data` 键集合被快照比对，改键名 = 破坏契约 |

---

## 10. 对 Godot 移植的取舍（本阶段结论）

**必须搬（玩家可玩闭环的最小集合）**
1. `state` 七块渲染：顶栏（回合/目标/阶段）、主从台卡、产线卡、仓库、订单卡、记录栏。
2. 12 条玩家命令：`getState`、`checkAllFeasibility`、`checkFeasibility`、`startOrder`、`cancelProcess`、`deleteOrder`、`createRandomOrder`、`setMaster`、`setSlave`、`updateProducerRate`、`updateLiquidRate`、`manualTick`（+ **表现层帧流**取过程日志：过程通常在一个 tick 内结算完，tick 之后再 `getSteps` 只会拿到空数组，详见 `02-core-api-map.md` §9）。
3. 可行性 → 进度条/做法/阻断原因的直呈；`MATCH` 不计时。
4. 异步轨的进度三层数据：`currentStep/totalSteps`、`ticksUntilNextUnit`、`remainingTicks`、`blockedReason`。
5. 关卡装配（world + 派单 + 回合上限）—— 但这属于**宿主职责**，在 Godot 里由 Bridge/Runtime 承担。

**不必搬**
- `index.html` 的创建型命令面板（`createOrder` / `createWorkshop` / `updateWorkshopCapacity` / `setWorkshopCapability` / `executeOrder` 同步轨）、`canvas.js` 画布与 `ghost` 飞行动画。
- `world.html` 的不变量页与资源账本页（保留为诊断手段，不做成玩家界面）。
- `scenario` 场景编辑器（配置期工具）。

**必须在 Godot 侧新做（Web 没有现成实现）**
- 存档/读档（用上节的原语：`CommandLog` + `RandomSeed` + `SessionReplay`）。
- Tick 时间累积器（禁止用 Godot 帧当工业 tick，见指导书硬规则）。
- 与太空游戏的资源桥接（矿石 → 工业投入 → 订单产出 → 强化材料），这部分在 jar 项目里**完全不存在**。

**范围决定（2026-11-17 用户确认）**
1. **首版只保留 `play.html` 那一套界面，不做创建型命令。** 即：不做 `createOrder` / `createWorkshop` / `updateWorkshopCapacity` / `setWorkshopCapability`，也不做同步轨 `executeOrder`。订单来源只有"关卡预置模板 + 随机派一单"。
   - 影响：Bridge 只暴露 14 个方法（阶段 7 补了 `get_order_templates`，见 `02-core-api-map.md` §8）；UI 少两个表单弹层。
   - 代价（明确接受）：玩家不能自建工作台、不能手写需求行，内容多样性完全依赖世界配置里的 `orderTemplates`。
2. 关卡机制是否进第一版 —— **仍待决定**（见 `03-ui-design.md` §11）。
3. 过程日志记录栏是否第一版必需 —— **仍待决定**。

**原客户端的设计目的（用户 2026-11-17 强调，移植时不得丢失）**
原 `play.html` 不是"陶罐作坊模拟器"，它是一套**回合制资源解谜**：核心规则一行不改，客户端负责把它包装成可玩的谜题。改包装（太空题材）可以，改设计目的不行。逐条清单见 `03-ui-design.md` §0，要点是：①回合是硬预算；②先看得见做法再决定做；③主从台是空间约束；④标记/禁令制造"必须换台/必须先改形"的张力；⑤过程可见，玩家能看懂每步在干什么；⑥同一次投入只产出一次（不可重复发奖）。
