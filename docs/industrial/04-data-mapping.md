# 04 · 数据映射（Core 契约 → Godot 客户端）

> 目的：把"内核给的数据"与"界面上看到的东西"之间的对应关系一次说清。改字段先改这里，再改代码。
> 所有键名取自 `src/JarSystem.Core/Services/StateDtos.cs` 的 `[JsonPropertyName]` —— **它们是对外契约，不是内部实现**。

## 1. 状态快照 → 界面

| 快照键 | 子键 | 界面落点 | 备注 |
| --- | --- | --- | --- |
| `turns` | `used` / `limit` / `exhausted` | 顶栏「回合 used / limit」 | `limit=0` 显示「不限」 |
| `level` | `goalOrders` / `completedOrders` / `outcome` / `reason` | 顶栏「工单 done / goal」+ 结算文案 | `outcome` ∈ `inProgress`/`won`/`lost` |
| `phase` | — | 顶栏「准备阶段 / 执行中 / 已结算」 | `setup`/`running`/`settled` |
| `workshops[]` | `index`/`name`/`baseMarks`/`additionalMarks`/`ban`/`maxJars`/`maxLiquids`/`jars`/`liquids`/`canPourShapes` | 主/副装配台卡片 | **`liquids` 的上限是"每种液体各自"**，不能相加 |
| `orders[]` | `index`/`id`/`type`/`requirements`/`status`/`feasibilityResult`/`description` | 工单卡 | `status` 是**中文常量**：待执行/执行中/成功/失败 |
| `orders[].requirements[]` | `shape` / `liquid` | 需求行 | `liquid=null` 显示「空舱」 |
| `orders[].feasibilityResult` | `feasible`/`directCount`/`reason`/`blockage`/`solverPath`/`masterPath` | 进度条、「现在就能直接用上的 x / N 件」、不可行原因、做法清单 | `solverPath[].operation` 直接展示原文 |
| `processes[]` | `id`/`kind`/`subject`/`subjectId`/`state`/`currentStep`/`totalSteps`/`ticksUntilNextUnit`/`remainingTicks`/`blockedReason` | 执行中的工单卡内进度 | 判「执行中 N」只看 `kind == "order_execution"` |
| `warehouse` | `jars`/`jarList`/`liquids`/`discardedJars`/`discardedLiquids` | 中央仓库卡 | `jarList[].shape` 用于构成统计 |
| `producerStatus` | `producers`/`generators`/`slots`/`flow`/`liquidRates`/`liquidAccumulated`/`warehouse` | 产线卡 | `flow.jars` / `flow.liquidPerLiquid` 是"每次推进最多流入" |
| `globalState` | `currentMaster`/`currentSlave`/`masterName`/`slaveName`/`autoCheckEnabled` | 主/副台高亮 | 索引可能为 `null`（未选定）——**必须防 `int(null)`** |

## 2. 词表（`WorldMeta`）

`{ shapes: string[], liquids: string[] }`。**`liquids` 不可改名**：Core 校验强制它恰好是「酒、蜜」，界面上换说法只能做显示别名（本原型直接沿用原名，避免"显示一套、配置一套"）。

## 3. 世界配置 → 玩法

| 配置键 | 含义 | 界面/玩法影响 |
| --- | --- | --- |
| `turnLimit` | 回合硬预算（0=不限） | 超限时 Core 拒绝整次推进 |
| `goalOrders` | 目标工单数（0=无目标） | 0 时顶栏显示「沙盒模式」 |
| `flow.jarCount` / `flow.liquidAmount` | 每次推进从仓库搬进主台的上限 | 产线卡的「生产 ≠ 流入」说明 |
| `flow.liquidRate` | 液体自产速率 | 工质卡的「自产 x.xx / 回合」 |
| `producerSlots` | 产能槽上限（0=不限） | 「产线占用 used / limit」 |
| `orderTemplates[]` | 可派模板（`name`/`type`/`requirements`） | 「选模板」弹层的条目 |

## 4. 存档格式（`user://industrial_save.json`，明文）

```json
{
  "version": 1,
  "world_path": "res://data/industrial/world_sandbox.json",
  "accumulator": 0.0,
  "industrial_json": "{\"world\":\"...\",\"seed\":null,\"commands\":[...] }",
  "wallet": { "ore": 0, "materials": 0, "attack_level": 0 }
}
```

- `industrial_json` 是 **Core 原样吐出的文本**（世界配置 + 种子 + 命令日志），刻意不经过 Godot 的 Variant：Godot 会把所有数字读成 float，命令里的 `intA` 变成 `5.0` 后 C# 反序列化失败。
- `accumulator` 是"这一帧之前已经攒了多久"的秒数；读档后原样恢复，**不做离线补算**。
- 钱包另有一份 `user://player.cfg`（战斗中也会变，不能等进工业舱才存）。

## 5. 玩家钱包（`GameState`）

| 字段/方法 | 含义 | 约束 |
| --- | --- | --- |
| `ore` / `add_ore` / `spend_ore` | 战斗打碎残骸得到，工业里投矿提速用 | 不足时 `spend_ore` 返回 false 且不扣 |
| `materials` / `add_material` | 工单结算产出 | 每张工单只发一次（运行时账本去重） |
| `attack_level` / `attack_damage()` | 花 3 张材料升 1 级，上限 5 级 | 伤害 = `1 + attack_level` |

## 6. 错误码（Bridge 信封）

| `error_code` | 触发 | 界面表现 |
| --- | --- | --- |
| `invalid_arg` | 参数不合法（如空液体名） | Toast 原文 |
| `invalid_config` | 世界配置/存档校验失败 | 顶部故障条 + 原因 |
| `illegal_state` | Core 拒绝（回合上限、本关已结束等） | Toast 原文 |
| `internal` | 未预期异常（含存档回放不完整） | Toast「内部错误」+ 日志 |
| `not_initialized` | 还没装配世界就调写方法 | 顶部故障条 + 重试 |
