# 工业界面 UI 设计（阶段 3 产物）

本文是**设计方案**，不是实现记录：`scenes/industrial/IndustrialMain.tscn` 与 `scripts/industrial/ui/*` 尚未创建。设计依据是阶段 1 的 Web 页面结构（`01-web-feature-map.md`）与阶段 2 的 Core 契约（`02-core-api-map.md`）。

前置硬约束（来自指导书，任一条不满足即方案作废）：

- UI **不拥有**世界状态：所有显示值来自 Bridge 返回的 DTO，按钮只发意图。
- UI **不决定** Runtime 生命周期：界面开关不影响工业 tick 是否推进。
- GDScript 不写求解/校验/搬运算法，可行性结论与进度一律原样呈现。
- 不改 `main.tscn`（游戏主场景），工业界面是独立场景/独立入口。

---

## 0. 原客户端的设计目的（移植红线）

用户 2026-11-17 明确：原 jar 客户端的设计**有其目的**，依赖的 Core 不变；要变的是包装（融入太空战），不是设计目的。下面逐条钉住"可改的包装"与"不可改的目的"，阶段 6/7 评审时按这张表逐条对照。

| # | 设计目的 | Web 上的体现 | 太空战可以怎么包装 | 不许变的东西 |
| --- | --- | --- | --- | --- |
| 1 | **回合是硬预算** | 每关 `turns` 固定（第一关 9），`goal` 达标判胜，超限硬停判负 | 一次跃迁/一个补给周期 = 一回合 | 回合由 Core 判定（`WorldOptions.TurnLimit` + `TurnBudget`）；超限**整个推进请求不生效**；界面不能"先预支再结算" |
| 2 | **先看见做法再决定做** | `checkFeasibility` 返回 `solverPath` / `masterPath` / `directCount`，玩家按"做法"决定要不要投入 | 蓝图预演 / 施工路线预排 | 路径与阻断原因必须来自 Core 并原样显示；GDScript 不得自己算可行性 |
| 3 | **主从台是空间约束** | 主台直接做；从台要先迁移罐子和液体，迁移有代价 | 主装配台 + 副装配台（母舱 / 子舱） | 迁移的代价与容量限制不删；主从切换是玩家决策，不是自动优化 |
| 4 | **标记与禁令制造张力** | `baseMarks` / `additionalMarks` / `ban` 让"这单在主台做不成，得换台或先改形" | 舱段可加工规格 + 禁用工质 | 可行性由标记/禁令推导，UI 只呈现；不要给"一键找到能做的台"这种消除解谜的便利 |
| 5 | **生产 ≠ 流入** | 产线速率决定每回合产出；`flow` 决定每次推进从仓库搬多少到主台 | 产线产坯料，传送带每回合限量往主台搬 | 两者不能合并成一个"每回合产出"数字（合并后玩家无法理解"为什么台上有货但不够用"） |
| 6 | **过程可见** | 过程日志逐条记"谁·第几步·做了什么"，进度 `currentStep/totalSteps` | 施工日志 / 工单步骤 | 不删过程反馈；否则失败时玩家只看到"失败了"而不知道为什么 |
| 7 | **同一次投入只产出一次** | 一个订单执行一次；产出由执行结果给出 | 同上 | 奖励发放按订单/过程 id 去重，重开面板/重连不得重复发（指导书硬规则） |

### 术语重命名（只改配置字符串，不改 Core）

| 原词汇 | 太空战候选 | 说明 |
| --- | --- | --- |
| 工作台 | 装配舱 | `world.json` 的 `workshops[].name` |
| 主台 / 从台 | 主装配台 / 副装配台 | `state.globalState.masterName/slaveName` 只是显示值 |
| 形状（圆罐/方罐…） | 舱段规格（圆/方/三角…） | 词表来自 `shapes`，**可以任意重命名**；形状之间的"可改形"关系由 `baseMarks`/`additionalMarks` 决定。改形状名要同时改 `producers[].rates`、`baseMarks`/`additionalMarks`、`orderTemplates[].requirements` |
| 液体（酒/蜜） | 工质（冷却剂/等离子） | **不能改名**：`liquids` 必须恰好两种且与 Core 内置词表逐字一致（`WorldOptions.cs:182-183`：「liquids 目前不支持改名/改序…请保持与内置一致: 酒, 蜜」）。换说法只能在 UI 文案层做**显示别名**（配置里仍是 酒/蜜） |
| 订单 | 工单 | 同上 |
| 回合 | 回合（保留） | 玩家对这一词的理解成本最低，不建议换 |

包装的第一版建议：先把上面这张词的替换做完（纯配置 + UI 文案），再决定要不要更强的叙事包装（舱室剖面图、建造动画）。**不要**在做法上偷懒——把"解谜"简化成"点一下自动完成"会直接丢掉 #2 和 #4 两条设计目的。

---

## 1. 信息层级：玩家一屏要看到什么

按"这一回合我能做什么"排出优先级（越靠上越高频）：

| 层 | 内容 | 为什么在这个位置 |
| --- | --- | --- |
| L0 状态条 | 回合 `used/limit`、目标 `completedOrders/goalOrders`、结局、连接/忙碌 | 每次操作前都要确认"还能不能玩" |
| L1 动作区 | 「推进一回合」+ 自动推进开关 | 最高频，固定右下/底部 |
| L2 工作台 | 主台 / 从台：形状标记、液体存量、罐子、禁令 | 决定"这单做不做得成" |
| L3 订单 | 每单的类型、需求、可行性、做法、开始/取消 | 主循环目标 |
| L4 产线与仓库 | 形状线速率、液体自产、仓库库存、溢出丢弃 | 供给侧，决定中后期节奏 |
| L5 记录 | 过程日志（谁·第几步·做了什么） | 出事时才看，可折叠但默认展开一条摘要 |

结论：**两列布局**（左生产、右订单）+ 顶部状态条 + 底部推进按钮，与 `play.html` 同构。理由：Web 版这个结构已经被 6 个关卡验证过（每关都能在 1280×720 一屏内完成操作），照搬能省掉一轮布局试错；代价是手机上会挤，而本项目当前目标平台是桌面。

〔提案·待决定〕如果后续要在太空游戏 HUD 里以"半屏面板"打开工业界面，两列会挤成一条；那时改为"标签页（生产/订单/记录）"，记录栏默认收起。

---

## 2. 场景结构与节点树

根场景 `scenes/industrial/IndustrialMain.tscn`（`Control`，锚点全屏，最小 1280×720，靠 `canvas_items` 拉伸适配）。

```
IndustrialMain (Control)                      ← scripts/industrial/ui/IndustrialMain.gd
└─ Root (MarginContainer)                     边距 12
   └─ VBox (VBoxContainer)  separation 8
      ├─ TopBar (PanelContainer)              ← ui/TopBar.gd
      │  └─ HBox: TurnsLabel | GoalLabel | PhaseBadge | OutcomeBadge | Spacer | BusyLabel | CloseButton
      ├─ Body (HBoxContainer)  size_flags_vertical = EXPAND_FILL
      │  ├─ LeftColumn (VBoxContainer)  size_flags_horizontal = EXPAND_FILL, stretch 1.1
      │  │  ├─ BenchCard_Master  (PanelContainer)      ← ui/BenchCard.gd（role = master）
      │  │  ├─ BenchCard_Slave   (PanelContainer)      ← ui/BenchCard.gd（role = slave）
      │  │  ├─ LinesPanel        (PanelContainer)      ← ui/LinesPanel.gd
      │  │  └─ WarehousePanel    (PanelContainer)      ← ui/WarehousePanel.gd
      │  └─ RightColumn (VBoxContainer)  stretch 1.0
      │     ├─ OrdersPanel (PanelContainer) size_flags_vertical = EXPAND_FILL
      │     │  └─ VBox: Header(HBox: Title | RandomOrderButton) + ScrollContainer(OrderCards VBox)
      │     └─ LogPanel (PanelContainer) custom_minimum_size.y = 180   ← ui/LogPanel.gd
      │        └─ VBox: Header(HBox: Title | FilterOption | CollapseButton) + LogList(ScrollContainer > VBox)
      └─ FooterBar (PanelContainer)            ← ui/FooterBar.gd
         └─ HBox: HintLabel | Spacer | AutoTickToggle | AdvanceButton
```

弹出层（与主场景同文件，`CanvasLayer` + `PanelContainer`，默认 `visible=false`）：

- `Picker_Workshop`：换主台/换从台（列表项 = 工作台名 + 标记摘要 + 禁令）；用 `ItemList` 而非下拉，因为要同时显示摘要。
- `Picker_Level`（若第一版保留关卡）：这属于**宿主职责**，由 Runtime 提供关卡列表，UI 只显示与选择。
- `Toast`：`{kind: info|error}` 浮条，3 秒淡出；错误文本直接来自 Bridge 的 `message`。

节点命名约定：容器用 `XxxPanel`/`XxxCard`，叶子用 `XxxLabel`/`XxxButton`。**不把 DTO 字段塞进节点名**，字段绑定写在脚本的 `bind_*` 函数里。

---

## 3. 数据绑定：DTO → 控件

Bridge 每次返回新 `state` 后，`IndustrialMain.gd` 调 `model.apply_state(dto)` 生成只读模型，再逐个 `bind_xxx(model)`。UI **不在本地缓存"世界"**，只缓存"上一帧用于 diff 的显示值"（避免重复重建节点）。

| 面板 | 取值字段 | 控件与呈现 |
| --- | --- | --- |
| TopBar | `turns.used` / `turns.limit`（0 显示"不限"）/ `turns.exhausted`；`level.goalOrders` / `level.completedOrders`；`phase`（setup/running/settled）；`level.outcome`（inProgress/won/lost）；`processes[]` 中 `kind=="order_execution"` 且 `state=="running"` 的条数 | `TurnsLabel` 中文化为"回合 3 / 9"；`exhausted` 时标签转警示色；`phase` 显示"准备 / 执行中 / 已结算"；`OutcomeBadge` 仅 `outcome != inProgress` 时出现（"达成 / 失败 · reason"） |
| BenchCard | `index` `name` `isMaster` `isSlave` `baseMarks` `additionalMarks` `ban` `maxJars` `maxLiquids` `jars[]` `liquids{}` | 标题 = 名称；副标题 = "基础：圆罐、方罐 · 附加：三角罐"；`ban` 行 = "禁：酒（能存不能用）"；罐位行 = "罐 4 / 6"；液体行逐液体 "酒 3 / 5"（**每种各自比 maxLiquids**）；罐子区按形状分组显示只数与是否带液；按钮"换主台/换从台""撤掉从台" |
| LinesPanel | `producerStatus.producers[]` `generators[]` `slots` `flow` `liquidRates` `liquidAccumulated` `warehouse.liquids` | 每个形状一张小卡（合计速率 + 累加 + 生产源数）；每个生产源一行 `名称 0.4 / 回合` + 4 个档位按钮 `0 / 0.2 / 0.4 / 0.6`（非档位显示"当前 x.xx"）；`producers==0` 的形状线折叠成一行"另有 N 条形状线没有生产源"；液体区每液体一张卡（自产 / 累加 / 仓库库存）；底部固定说明"生产 ≠ 流入：生产进中央仓库，流入才是每次推进搬向主台（最多 3 只罐、每种液体最多 2 份）" |
| WarehousePanel | `warehouse.jars` `jarList[]` `liquids{}` `discardedJars` `discardedLiquids{}` | "罐子 12 只"+"按形状明细"（圆罐×4、方罐×3…）；液体行；`discarded*` 非 0 时出现一行"已丢弃 3 只（容量溢出）" |
| OrdersPanel | `orders[]`：`index` `id` `type` `requirements[]` `status` `feasibilityResult` `description` | 每单一张卡：标题 `A · 空双罐`；需求行（形状 + 液体，`null` 显示"空罐"）；`ProgressBar`（分子 = 可行时需求条数，否则 `directCount`）；"做法"可折叠列表（A：solverPath；B：masterPath → "迁移到从台" → solverPath）；阻断原因原样显示；按钮：`开始`（仅 `status==pending` 且 `phase==setup` 且 `feasible`）、`取消`（有 running 过程时）、`删除` |
| LogPanel | **`poll_events()` 的帧流**（每帧附该刻 `StepsFor` 快照）：`frames[].steps[]{seq,tick,kind,stepIndex,operation,summary}`，以及 `frames[].kind/op/subject/tick` | 按 `seq` 去重、按 seq 升序追加；第 N 行 = "第 3 步 · 倒液 圆罐 ← 蜜"（`summary` 优先，缺失时才按 `operation` 查中文措辞表）；只做措辞，不做判断。**不要**在 tick 之后单独调 `getSteps`：过程通常在一个 tick 内结算完，主体映射已淘汰，只会拿到空数组（见 `02-core-api-map.md` §9） |
| FooterBar | `turns.exhausted` / `outcome` / `phase` | 「推进一回合」在 `exhausted` 或 `outcome != inProgress` 时禁用，并显示原因文案；「自动推进」开关反映 `startTick/stopTick` 的宿主态 |

---

## 4. 交互 → Bridge 调用 → 反馈

一次点击的固定顺序：**禁用按钮 → 调 Bridge（异步）→ 收结果 → 重拉 state → 恢复按钮**。中间失败不做乐观更新，避免"界面说成功了但世界没变"。

| 控件 | Bridge 方法 | 成功 | 失败 |
| --- | --- | --- | --- |
| 换主台（选中项） | `SetMasterIndex(index)` | 重拉 state，`BenchCard_Master` 重绑 | Toast `message`，不重拉 |
| 换从台 / 撤掉从台 | `SetSlaveIndex(index)` / `SetSlaveIndex(-1)` | 同上 | 同上 |
| 随机派一单 | `CreateRandomOrder()` | 重拉 state + `CheckAllFeasibility()` | Toast |
| 删除订单 | `DeleteOrder(index)` | 重拉 state | Toast（可能"订单不存在"→ 仍重拉，列表已变） |
| 上移 / 下移 | `MoveOrder(orderId, ±1)` | 重拉 state | Toast |
| 检查可行性（单） | `CheckFeasibility(orderId)` | 只更新该卡的 `feasibilityResult`（不整表重绘） | Toast |
| 检查全部 | `CheckAllFeasibility()` | 逐卡更新 | Toast |
| 开始 | `StartOrder(orderId)` | 重拉 state；该卡转为"执行中"（显示过程进度） | Toast（回合/阶段不满足时是预期失败） |
| 取消 | `CancelProcess(processId)` | 重拉 state；该单状态转 failed | Toast（"已完成部分不回滚"写进确认框） |
| 速率档位 | `UpdateProducerRate(producerName, shape, rate)` | 该卡重绑 + 重拉 state | Toast（越界时不得把按钮点亮） |
| 液体速率 | `UpdateLiquidProductionRate(liquid, rate)` | 同上 | 同上 |
| 推进一回合 | `Tick(1)` | 重拉 state + `CheckAllFeasibility` | `illegal_state` 时 Toast"本关已结束/回合已用完"，不重拉 |
| 自动推进 | 开：宿主 Runtime 的时间累积器；关：停 | 只影响节奏，不影响判定 | — |

需要二次确认的只有两项：**取消过程**（已投入的罐子/液体不回滚）与**重开本关**（世界回开局，进度清空）。

---

## 5. 界面状态机

```
loading ──► ready(setup) ──Tick/StartOrder──► running ──进程结束──► ready
   │             │                                  │
   │             └──回合耗尽/达成/失败──► ended       └──全部结束/回合耗尽──► ended
   └─ 初始化失败 ──► faulted（显示原因 + 重试按钮，不显示任何数字）
```

- `faulted` 只在**世界装配失败 / Bridge 抛未预期异常**时进入；此时隐藏所有面板，只留一段人话 + "重试"。绝不用 0 值面板冒充"世界是空的"。
- `ended` 时保留全部只读显示（玩家要能回看这局做了什么），只禁用动作类按钮；「重开本关」是唯一可用的写操作。
- 忙碌态（`Tick`/`StartOrder` 在途）用按钮 disabled + `BusyLabel`，不用全屏遮罩——玩家需要边等边看进度。

---

## 6. 工业 time 的界面呈现（与 Runtime 的分工）

- UI 只发"推进一回合"或"开关自动推进"，**不自己数时间**。时间累积器、暂停/失焦/长卡顿补算策略住在 `IndustrialRuntime.gd`（阶段 5），界面不参与。
- `remainingTicks` / `ticksUntilNextUnit` 来自 `processes[]`，直接显示为"还需 12 刻 · 下一单位 2 刻"。**不用 Godot 帧数换算秒数**当进度条——那会把"看起来快到了"变成"判定还没到"。
- 工业界面关闭（隐藏/隐藏面板）**不代表**工业暂停：是否暂停必须显式走 `PauseTime/ResumeTime`，由 Runtime 的策略决定，UI 无权自行冻结世界。

〔待决定〕第一版是否给玩家"暂停工业"按钮？推荐**给**（叙事上对应"离港修整"），但要明确暂停期间 `Tick` 静默返回 0，且 UI 上的回合数不变——否则玩家会以为暂停在"偷跑"。

---

## 7. 空态与文案（统一口径，避免"界面在撒谎"）

| 情形 | 文案 | 禁止 |
| --- | --- | --- |
| 无订单 | 还没有订单。派一张随机单，或重开本关。 | 不要显示"0/0 已完成"当成数据 |
| 无可分析单 | 先派一张订单再看可行性。 | 不要显示"不可行" |
| 不可行 | 原样显示 `blockage`/`reason` | 不要自己编原因、不要用红色当"错误"（这是正常状态） |
| 无主台 | 还没有主台。先选一台当主台。 | 不要显示"从台可执行" |
| 回合耗尽 | 本关回合已用完（9/9）。 | 不要把「推进」按钮留在可点状态 |
| 执行中阻断 | `blockedReason` 原文 + "等资源/等液体" | 不要自己判断等待要多久 |
| 溢出丢弃 | 已丢弃 N 只罐子（台上的容量装不下）。 | 不要说"仓库满了"（丢弃发生在搬运/流入，口径不同） |

术语表（UI 与文档统一，不改 Core 的词）：工作台 / 主台 / 从台 / 形状 / 液体 / 罐子 / 基础标记 / 附加标记 / 禁令 / 订单 / 需求 / 可行性 / 做法 / 步骤 / 回合 / 过程 / 流入 / 产出 / 仓库 / 丢弃。

---

## 8. 美术与声音

- 现状：`space-demo` 是太空射击（`scenes/actors`、`scenes/ui`），没有工业题材素材。第一版**用占位**：深色 `PanelContainer` + 1px 描边 + 系统字体（`Label` 默认），形状用文字 + 简单色块（圆/方/三角/高/长/扁/鼓/尖），不引入外部美术。
- 视觉方向〔待决定〕：① 冷淡工业风（青灰 + 琥珀强调，与原太空 HUD 同族）；② 陶器暖色风（陶土色 + 米白，和"陶罐"主题一致但和太空场景脱节）。推荐 ①，理由是它要么被放进 HUD，要么独立界面，和现有 `Hud.gd` 的配色更容易统一。
- 声音：第一版**不做**。反馈靠文字 Toast + 进度变化。若后期加，只加三类：推进一回合、订单完成、过程阻断。

---

## 9. 与太空游戏的接入口（第一版只留接口，不实现联动）

工业界面本身不知道"矿石"。它需要两个由外部注入的值：

1. **可用矿石**（战斗产出）→ 显示在 TopBar 右侧的"工业库存"小标签，来源由桥接层给，UI 只显示。
2. **可兑换的强化材料**（订单产出）→ 订单完成时显示"获得强化材料 ×N"，实际发放由桥接层决定。

**同一订单/同一产品不得重复发奖**——显示层必须按 `process.id` 或订单 `id` 去重，重连/重开面板不能让玩家重复领（这条是硬规则，UI 也要守）。

---

## 10. 可观察的验收条件（阶段 6 结束时逐条实测）

1. 打开工业界面：在**没有任何订单**的世界里，看到空态文案而不是崩溃或 0 值面板。
2. 派一张随机单 → 订单卡出现，需求行显示形状文本，可行性在 1 次刷新内出现。
3. 点「开始」→ 订单卡出现"第 x / y 步"与"下一单位 N 刻"，且这个数字**随推进减少**（不是 Godot 帧数）。
4. 点「推进一回合」→ 回合数 +1、主台/仓库数值变化、记录栏新增步骤行（按 seq 升序无重复）。
5. 把回合耗到上限 → 「推进」禁用且文案说明原因；再点不会出现 Toast 之外的任何变化。
6. 换主台 / 撤从台 → 主从卡与订单可行性同时刷新（不是只刷新一边）。
7. 速率档位切换 → 形状线合计速率变化，且推进后仓库产出随之变化（用两次推动的产出差对照）。
8. 取消一个执行中的过程 → 该单转失败、已投入资源不回滚（对照取消前后的台面罐数）。
9. 关闭并重新打开面板 → 显示值与世界一致（证明 UI 不持有世界状态）。

第 1–9 条中"数值变化"必须用真实的 `state` diff 说明，不能只看界面文字；"界面好不好看/顺不顺手"需人工试玩，工具与脚本都不能代替这一条。

---

## 11. 待决定（影响实现顺序，不影响本文件结构）

1. ~~**首版界面范围**~~ **已定（2026-11-17）：只保留 `play.html` 那套，不做创建型命令、不做同步轨。** 订单来源 = 关卡预置模板 + 随机派一单。
2. **关卡是否进第一版**：若第一版只要"一条链路"，可先做"无限回合沙盒 + 目标单数"；关卡目录（6 关）留到内容期。代价是第一版少一条现成的内容供给线。
3. **记录栏位置**：右列底部（推荐，同 Web）vs 独立抽屉（省空间，但要多一次点击才能看见过程）。
4. **自动推进的默认值**：开局是否直接走自动推进？推荐**默认关**，让玩家先按一次手动推进理解"一回合"。
5. **词表重命名时机**：先按 §0 的术语表只改配置与文案（推荐，成本低、可回退），还是等叙事包装定稿再一起改？

---

## 12. 阶段 6 实现记录（2026-11-17）

### 12.1 已落地

| 文件 | 职责 |
| --- | --- |
| `scenes/industrial/IndustrialMain.tscn` | 工业界面场景：只有根 `Control` + 脚本，全部节点在 `_build()` 里用代码建（避免手写 .tscn 与代码两处漂移）。 |
| `scripts/industrial/ui/IndustrialMain.gd` | 主控：装配世界、连运行时信号、整块重画、动作转发、Toast、换台选择器、故障态与重试。 |
| `scripts/industrial/ui/UiKit.gd` | 配色与控件工厂（面板/标题/按钮/滚动区/速率文本）。 |
| `scripts/industrial/ui/BenchCard.gd` | 主/副装配台卡：基础/附加舱段、禁装工质、舱段与工质用量、构成。 |
| `scripts/industrial/ui/LinesPanel.gd` | 产线：每形状合计算、累加、生产源与速率档位；无生产源折叠；工质自产/累加/仓库；「生产 ≠ 流入」常驻说明。 |
| `scripts/industrial/ui/WarehousePanel.gd` | 中央仓库：舱段数、构成、工质、丢弃计数。 |
| `scripts/industrial/ui/OrdersPanel.gd` | 工单：状态（中文常量）、需求、直接可用量、不可行原因、**做法（solverPath 原文）**、过程进度、开始/删除/取消。 |
| `scripts/industrial/ui/LogPanel.gd` | 记录栏：只吃帧流（`poll_events`），按 seq 去重，保留 300 行。 |

### 12.2 自动验证（`tests/industrial/ui_smoke.gd`，headless，27 项断言全过）

覆盖 §10 的第 1、2、4、6、9 条：空态、派单后出现工单卡与可行性、点「推进一回合」回合 +1、换主/副台后卡片就位、开始一单后执行中过程出现且步骤写进记录栏、改窗口尺寸后结构仍在。
**不覆盖**：3（进度倒数）、5（回合耗尽后禁用与文案）、7（档位切换前后产出差）、8（取消后不回滚）。这几条已在 `bridge_smoke.gd` / `runtime_smoke.gd` 层面验过内核行为，但"界面上的表现"尚未断言。

### 12.3 截图（人工看图依据，非自动视觉验收）

`tests/industrial/ui_capture.gd` 用带窗口的方式跑，把游戏自己的视口存成 PNG：`tmp/ui_capture/01_empty.png`（空态）、`02_picker.png`（换台选择器）、`03_benches.png`（主副台就位 + 推进 3 回合）、`04_orders.png`（工单卡与做法）、`05_running.png`（一单跑完：状态「成功」、记录栏步骤）。
必须带窗口：headless 是 dummy 渲染器，抓出来是全黑。

### 12.4 已知未做/待打磨

1. **观感未打磨**：字体用默认字体、没有配色层次之外的视觉设计；产线卡在 720p 下需要滚动才能看全 4 个形状。
2. **目标进度只在顶栏**：没有"还差几单"的进度条。
3. **记录栏没有筛选**：Web 版有按步骤类型过滤，这里没做（首版优先级低，见 §11 第 3 项）。
4. **Toast 与底栏贴得近**，长文案时会压住底栏提示。
5. **主场景里的探针节点仍在**（`main.tscn` 的 `Test`，挂 `scripts/industrial/JarIntegrationProbe.cs`），违反指导书"不改主场景"，待用户决定是否删除。

---

## 13. 阶段 7 实现记录：接通业务（2026-11-17）

指导书阶段 7 的八步里，六步在阶段 6 已通；本轮补的是**第 4 步「创建订单」的模板入口**，并把"页面刷新不丢状态"变成可断言的一条。

| 项 | 之前 | 现在 |
| --- | --- | --- |
| 派单 | 只有「随机派一单」 | 新增「选模板」：弹层列出世界配置里的 `orderTemplates`（名称、A/B 型、需求），选一张就派一张 |
| Bridge | 有 `create_order_from_template`，但界面拿不到模板清单 | 新增 `get_order_templates()`（只转手 `JarSystem.OrderTemplates`，不推断可行性） |
| Runtime | 无 | 新增 `get_order_templates()`、`create_order_from_template(name)` |
| 界面刷新 | 只靠肉眼 | `ui_smoke` 新增：关掉场景再开一个新场景，回合数与工单数与关掉前一致 |

**自动验证**（`tests/industrial/ui_smoke.gd`，32 项全过；`bridge_smoke.gd` 35 项、`runtime_smoke.gd` 23 项全过）
- 「选模板」列出 5 张模板；选第一张确认后工单 +1（1 → 2）。
- 关掉 `IndustrialMain` 再实例化一次：`runtime.running` 仍为真、回合数不变、工单数不变 ⇒ 世界在 Runtime（autoload）里，不随界面消失。
- `bridge_smoke` 断言模板清单按配置顺序给出（首张 `双圆工单`）。

**顺手修的测试缺陷（不是产品 bug）**：原来断言"开始后必有执行中的过程"。真实语义是——若订单开局就满足（A 类需求已被主台上的舱段覆盖，`MATCH` 不计时），`startOrder` 会在一次调用里整段跑完，状态直接变「成功」、过程列表里也就没有它。现在按两种合法结局分别断言，并优先挑"还需要动手"的单来验分步过程。

**仍未做**：`moveOrder`（上移/下移）没进界面——首版用不到；`cancelProcess` 已有按钮但界面级断言还没补。

---

## 14. 阶段 8 实现记录：后台生产（2026-11-17）

阶段 8 要证的三件事，现在都有断言（不是"看起来还在跑"）：

| 验收点 | 怎么验的 | 结果 |
| --- | --- | --- |
| 工业生产不依赖 UI 是否打开 | `ui_smoke`：打开“自动推进”，把工业界面 `free()` 掉，等 2.4 秒再来读 | 回合 0 → 1（界面不在也推进了） |
| 场景切换不重置工业世界 | 同上：重新实例化界面后读到的回合就是关界面期间的值 | 读到 1，与关掉前一致 |
| Tick 不因帧率不同而直接倍增 | `runtime_smoke`：同样时长分别用 130 个 1/60 秒碎片与一次 2.17 秒推进 | 两种喂法都只推 1 刻 |

**为什么"关掉界面还能生产"成立**：世界在 `IndustrialRuntime`（autoload）手里，界面只是订阅者；`_process` 只在 `auto_advance` 打开时把墙钟 delta 交给累积器，`auto_advance` 默认关——玩家不开自动推进，切场景就真的不生产（这是刻意的，别默认替玩家花回合）。

**一个浮点边界（记录，不修改）**：正好 120 个 1/60 秒累加得到 `1.9999999999999998`，比 2.0 少一个 ulp，因此那一刻不推进、下一帧才推进。这是正确行为，不给它加 epsilon 凑整——否则"看起来更顺手"的代价是判定层多一个魔法容差。

**仍未做**：离开工业界面去战斗场景这一整段"真实场景切换"还没串起来（主场景仍是原太空游戏，没有入口按钮）；阶段 8 的验收是在 headless 里用 `free()`/重实例化模拟同一件事。

---

## 15. 阶段 9 实现记录：战斗资源投入工业（2026-11-17）

### 15.1 走的是一条不碰 Core 的桥
Core 不会把玩家库存交给外部改（`WorldOptions` 里没有"加液体/加舱段"的入口），所以"投入"落在 Core **已有的**意图方法上：花矿石 → `updateProducerRate(生产者, 形状, 新速率)`。矿石本身存在 `GameState`（autoload），跨战斗、跨场景累积。

| 环节 | 落点 | 说明 |
| --- | --- | --- |
| 战斗获得 | `scripts/Asteroid.gd` → `GameState.add_ore(ore_value)` | 打碎残骸掉 1 矿石（`@export` 可调） |
| 显示 | `Hud.gd` 分数行追加"矿石：N" | 一个标签带两个数，不新增节点 |
| 投入 | `LinesPanel` 每条产线一个「投矿 +0.2」按钮 → `upgrade_requested` → `IndustrialMain._on_upgrade_requested` | 花 2 矿石，速率 +0.2，上限 0.6 |
| 记账 | `GameState.spend_ore / add_ore` | 先扣、Core 调用失败就原额退回；不存在"界面扣了矿但世界没变" |

### 15.2 为什么选"提速"而不是"注液体"
注液体需要给 Core 加新入口（等于改核心语义），提速用的是 Core 已经提供、已经有结算的意图方法；而且"花资源提高产能"和本作的回合预算咬合——**花矿石换的是每回合产出，不是白给舱段**。

### 15.3 自动验证
`ui_smoke` 第 10 段（6 项）：开局速率 0.4 → 投矿后 0.6 → 矿石 5→3 → 矿石只有 1 时速率不变、矿也不扣 → 界面上确实画出了「投矿」按钮。
`scene_switch` 第 12 项：实例化残骸、打碎，`GameState.ore` 0→1。

### 15.4 一处显示缺陷（已修）
不可行原因用 `str(null)` 会得到字面串 `<null>`，界面上就出现"不可行：<null>"。`OrdersPanel` 统一改走 `_text()`（null → 空串），现在显示内核给出的真实原因（如"资源冲突或液体不足"）。

---

## 16. 阶段 8 的补全：真实场景切换（2026-11-17）

之前阶段 8 是用 `free()` + 重新实例化模拟"离开界面"。现在有了真入口，改由 `tests/industrial/scene_switch.gd` 走真实 `change_scene_to_file`：

| 断言 | 实测 |
| --- | --- |
| 主菜单有「进入工业舱」按钮 | 有 |
| 按下后切到 `IndustrialMain`，世界已装配 | 通过 |
| 在工业舱推进一回合 | 0 → 1 |
| 「返回主菜单」回到菜单，世界仍存活 | 通过 |
| 回合数不因切场景回退 | 仍是 1 |
| 再次进入工业舱，读到同一局 | 1 |

入口位置：`scenes/menus/MainMenu.tscn` 的 `ColorRect/VBoxContainer/IndustrialButton`（不动机器人主场景 `main.tscn`，仍是"主场景只负责切菜单"的既有分工）。

---

## 17. 阶段 10 实现记录：奖励系统（产品 → 强化材料 → 舰船攻击力）

### 17.1 链路
工单结算成「成功」→ 运行时发 1 张强化材料 → 玩家在工业舱顶栏花 3 张升 1 级攻击力 → 战斗里子弹伤害 = 1 + 等级（上限 5 级，即最多 6 点）。

| 环节 | 落点 | 关键点 |
| --- | --- | --- |
| 发奖 | `IndustrialRuntime._collect_rewards()` | 每次刷新快照时扫 `orders[]`，只给**本局第一次**变成「成功」的工单发 |
| 幂等 | `_awarded_orders`（工单 id 账本） | 账本在运行时、不在钱包；`start()` 与 `reset_world()` 清空，重开一局还能拿奖 |
| 钱包 | `GameState.materials` / `attack_level` | `add_material` / `upgrade_attack`（不够或到顶返回 false 且不改数值） |
| 显示 | 工业舱顶栏「材料 N　攻击 LvN」+「强化攻击（材料 3）」 | 灰掉条件 = 材料不够或已到顶 |
| 战斗生效 | `Player._shoot()` → `b.damage = GameState.attack_damage()` | 取不到钱包就用子弹默认伤害，战斗不因工业侧缺席而崩 |
| 战斗可见 | `Hud.gd` 分数行追加「攻击:N」 | 玩家能看见强化真的生效 |

### 17.2 为什么账本放在运行时
"同一产品不得重复发奖"（指导书硬规则）要求一个**只对本局世界有效**的去重面。放进 `GameState` 会跟存档纠缠（阶段 11 要处理），放进 Core 又等于改核心。放运行时：随 `start`/`reset_world` 清空，语义正好是"这一局工业世界的发奖记录"。

### 17.3 自动验证
- 新增 `tests/industrial/reward_smoke.gd`（17 项）：结算一张工单得 1 张材料 → 连刷两次仍是 1（幂等）→ 材料不足时升级失败且数值不变 → 3 张升 1 级、伤害 1→2、材料归 0 → 升到 5 级后第 6 次失败、满级伤害 6 → `reset_world()` 后同一张工单还能再拿一张。
- `ui_smoke` 第 11 段（7 项）：顶栏材料/攻击文本同步、「强化攻击」的灰/亮状态、点一次等级与材料变化、伤害跟随等级。
- `scene_switch` 已有残骸掉矿断言；子弹伤害与 HUD 的联动靠 `reward_smoke` 的数值断言 + HUD 直接读 `GameState.attack_damage()` 保证。

### 17.4 已知边界
材料与攻击等级都还在内存里，退出游戏就归零——这是阶段 11（存档）要解决的；本次没有做"打一场战斗验证伤害真的变高"的人肉验收。

---

## 18. 阶段 11 实现记录：存档 / 读档（2026-11-18）

### 18.1 存什么、存在哪
| 内容 | 形式 | 位置 |
| --- | --- | --- |
| 工业世界 | Core 的 **意图日志**：世界配置 + 随机种子 + 全部命令（Event Sourcing） | `user://industrial_save.json` |
| 玩家钱包 | 矿石 / 强化材料 / 攻击力等级 | 同一份存档的 `wallet` 段，并且 `user://player.cfg` 自存一份（战斗里就能变） |

读档走 Core 给的原语：`new JarSystem(world, seed, jarId源, orderId源)` + `SessionReplay.Into(...)`。**独立 ID 源是硬前置条件**，否则重建出的罐子/订单 id 与原来不同。

### 18.2 三个踩过的坑（都记在这里，避免后人重踩）
1. **存档不能经 Godot 的 Variant 中转**：Godot 的 JSON 把所有数字读成 float，再写回时命令里的 `intA` 变成 `5.0`，C# 反序列化到 `int?` 直接失败（`The JSON value could not be converted to System.Nullable\`1[System.Int32]`）。改成 Bridge 直接吐**原始 JSON 文本**（`save_state_json()`），运行时只把它当字符串搬。
2. **`_bridge == null` 才是"不能存"的唯一判据**：一开始额外要求 `running == true`，结果"这一局已结算"（`running=false`）时无法保存——玩家的进度恰恰就在那时候最需要留住。
3. **测试之间会互相污染**：钱包落盘后，前一个测试留下的 `user://player.cfg` 会让后一个测试的"开局材料为 0"失败。现在每个测试开头都清 `player.cfg` 与 `industrial_save.json`。

### 18.3 自动验证
- `tests/industrial/save_smoke.gd`（19 项）：存档 → 释放运行时 → 新建运行时读档；回合数/工单逐条状态/仓库内容/主从台位置全部一致；钱包（矿石 7 / 材料 2 / 攻击 1）读回；**读档不会凭空补算**（喂 0.5 秒不推进）；存档写坏时退回新开一局并把原因带回来。
- 真实启动流程（带 autoload）：先造一份"回合 2、3 条命令"的存档，再启动 `scenes/industrial/IndustrialMain.tscn`，日志实测
  `[industrial] 已读取存档 user://industrial_save.json（回合 2）`；退出时又写回同一份（命令 3 条）。这条是把"退出前保存、重启恢复"真的从头跑到尾，不只是单元断言。

### 18.4 语义边界（诚实说明）
- **关闭期间不生产**：存档里带 `accumulator`，读回来原样恢复；没有"离线模拟"这条路，所以关机多久都不会多出舱段。
- 存档是**明文 JSON**，出问题可以直接打开看；也因此它可被玩家手改——这是单机原型的取舍，不是发行级的防篡改。
- 存档没有版本迁移（`version` 不匹配就拒绝并开新局），后面加字段要写迁移。

---

## 19. 阶段 12 实现记录：全链路验收（2026-11-18）

### 19.1 这条链是怎么跑通的
`tests/industrial/full_loop.gd`（15 项）一次跑完，全部走真实场景与真实节点：

1. `change_scene_to_file` 进主菜单 → 点「进入工业舱」（按钮自己的信号）→ 断言落到 `IndustrialMain`；
2. 工业舱：选主/副台 → 推 4 回合预热 → 按模板派单 → 可行性 → 开单 → 推进到结算 → `_collect_rewards()` 拿到材料；
3. 界面按钮「强化攻击」→ 材料扣 3、等级 1、`attack_damage()` = 2；
4. 「保存进度」→ 存档文件生成 → 「返回主菜单」；
5. 战斗侧：实例化 `Player.tscn` 调 `_shoot()`，抓到子弹断言 `damage == 2`；实例化 `Asteroid.tscn` 打碎断言矿石 0→1；
6. 释放整个运行时再新建 → `ensure_started()` 读档 → 回合数回到 5、攻击等级仍是 1。

### 19.2 只在测试里做的两处简化（诚实标注）
- 进工业舱用的是「按钮的 `pressed` 信号」，等于点了一下，但没有经过鼠标命中测试（headless 无窗口）。
- 战斗只实例化玩家与残骸，没有开整局刷怪；这条链验的是"伤害与掉矿接得上"，不是整场战斗体验。

### 19.3 顺带修掉的测试噪音
阶段 12 首轮退出时报 `2 ObjectDB instances were leaked` + `res://assets/audio/explosion.wav still in use`：残骸自毁时爆炸音效还在播，测试立刻退出。改成等 1.2 秒并释放残留 `Explosion` 节点后，连跑 3 次都干净。**这不是产品缺陷，是测试退出时机问题**——记在这里避免以后误判。
