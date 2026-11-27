# 2026-11-26 Space 供给场景敏感性区间

## 基线与来源

- 仓库：`Lazyair150/space-demo`
- 分支：`world-v2/phase-4.10b-hangar-ui`
- 本轮源 HEAD：`93d3b89d98b8a7e81ef79e4226f220fecd2c1f96`
- Core 精确集成源：`e1e89cad5e0f11f369c8ade814140a7b4cc8df74`
- PR #2：Open / Draft / Mergeable；没有合并。
- 基线 Space 验证：记录中的 Run `45781580539` 对应源 HEAD `93d3b89d` 成功。该结果只属于基线，不覆盖本轮新增代码。

## 源码审计结论

1. `SpaceBattleJarSupplyForecast.evaluate()` 已分别计算初始 Warehouse Jar、Core 时间 Producer、有限原石输入和 Space Parser 输出，采用 Core/Parser 固定点余数；本轮不重写或重复验证这三路来源。
2. 当前输入 `expectedEnemyDefeatsPerSecond` 是单一标量，只能生成一个概率加权期望场景。
3. `SpaceStageDefinition.wave_plans` 提供敌人数量和休息配置，但不提供玩家实际击败速率。不能把刷怪数量/休息秒数直接伪装成掉落输入率。
4. `SpaceBattleEconomyEvaluator` 仍是技能共享资源预算模型；它不负责 Core 的逐 Tick 资源事实。
5. 当前五个 Demo Stage 的 `completion_rewards` 均为空。正式击败速率、奖励系数、成长曲线和战斗奖励表均不能在本轮凭空填入。

## 本轮架构决策

- 新增版本化 `SpaceBattleSupplyScenarioProfile`，通过明确的 profile ID/version 保存 Low、Baseline、High 三个预期敌人击败率。
- 三个速率必须有限、非负且满足 Low ≤ Baseline ≤ High；缺失、额外或逆序字段均拒绝。
- 新增 `SpaceBattleJarSupplyForecast.evaluate_scenario_band()`。它对相同 World Options、Parser Profile、Drop Profile、战斗时长和初始状态调用既有单场景 evaluator，唯一变化为显式击败速率。
- 输出保留每个场景完整报告，并按形状汇总预期原石、Parser 处理/未处理体积、整 Jar 产出和 Warehouse 毛供给；同时单独展示 Core Producer 与初始 Warehouse 库存。
- 场景区间仅用于预算敏感性，不是置信区间、随机事件回放或 Core 实际库存承诺。
- 不从 Stage wave 数量自动推导击败率；需由真实游玩样本或内容作者配置精确版本的 Scenario Profile。

## 实际变更

- 新增 `scripts/industrial/world_v2/SpaceBattleSupplyScenarioProfile.gd`。
- 扩展 `SpaceBattleJarSupplyForecast.gd`，加入三场景批量求值、逐形状比较、单调性检查和 Core 来源不变量检查。
- 扩展 `SpaceBattleJarSupplyForecastProbe.gd`，加入场景档案往返、低/基线/高输入、Parser 上限瓶颈、Core 产量不变及逆序拒绝用例。
- 更新 `docs/industrial/15-production-parser-and-individual-progression-gameplay.md` 第 9 节，明确预测范围和不推导规则。
- 更新工作记录索引。

## 未完成边界

- 尚无正式 Low / Baseline / High Scenario Profile 资源；本轮 Probe 使用合成数值，只证明契约形状，不是平衡结论。
- 尚未接入实际 Pickup ID、Parser checkpoint、Core Import receipt 的运行时观测校正。
- 尚未把预测区间自动传入 Skill Economy，也未做逐 Tick 资源调度。
- 液体账户、Master/Slave 实际收货和 Core 容量/Mark 仍以 Core 快照与 Manifest 为准。
- Stage `completion_rewards` 到多 Owned Instance XP 奖励的跨存档原子结算仍是独立未完成项。

## 验证边界

- 本轮没有重复运行基线已通过的 CI，也没有为了验证提交而创建额外 CL。
- 新增 GDScript 与 Probe 目前是已提交源码、尚未执行的验证项；不能宣称 Godot 4.7.1 导入、C# 构建或 Probe 运行成功。
- 下一次有信息增量的验证应在接入真实场景配置时，和跨仓库/Headless 运行一并执行，而不是单独反复跑相同探针。

