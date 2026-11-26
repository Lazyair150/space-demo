# 2026-11-26 Parser/Core 供给对账观察契约

## 基线与工作方式

- 仓库：`Lazyair150/space-demo`
- 分支：`world-v2/phase-4.10b-hangar-ui`
- Core 仓库：`Lazyair150/jar-system-dotnet`
- Core 分支：`architecture/core-liquid-identity-consolidation`
- 本轮开始时 Space head：`7b2227c7d7e90a7f3a2d8759326412200916cd0c`
- 本轮使用的 Core 精确 head：`391f318a24fde724a66054e771d0590f0e20c231`
- Core 精确提交验证：Run `45822480114`，`verify` success。
- 旧 Space 集成失败：Run `45796547789`，Job `139828547247`。根因是工作流仍 checkout 旧 Core `e1e89cad5e0f11f369c8ade814140a7b4cc8df74`，导致 Space 读取的精确回执 DTO 成员缺失。
- 采用成组改动、过程记录先行/同步、最后集中验证；不逐小改动等待 CI。

## 一、集成版本错位修正

失败日志显示：

1. Core Bridge 在旧 SHA 上成功构建。
2. Space 编译失败，`WorldV2ProducedJarImportResultDto` 缺少：
   - `HasExactReceipt`
   - `StoredJarCountsByShape`
   - `DiscardedJarCountsByShape`
3. 失败发生在 Space C# Build，尚未进入 Godot import、GDScript parse 或 SceneTree probes。
4. Space 当前源码已经依赖 Core schema-11 精确导入回执，而 workflow 和 README 仍使用旧 Core SHA。

已将 Space workflow 的 checkout ref 和 `CORE_EXPECTED_SHA`、README 克隆/构建指令统一到 Core PR #63 当前精确 head `391f318a24fde724a66054e771d0590f0e20c231`。同步更新跨仓库集成检查点的权威状态区。此修正不代表新联合验证已经通过。

## 二、供给事实的来源与所有权

### Space Parser 事实

`SpaceOreParserRuntime.build_supply_observation_snapshot()` 提供：

- 每形状已完成 Jar 数；
- 每形状 pending Core import 数；
- 每形状已确认请求数；
- 每形状未归属完成量；
- Core 精确 stored/discarded 历史回执（逐形状）；
- 回执历史完整性标记；
- 接受/排队/处理原石体积与分数进度。

Parser 是有限原石输入的权威事实来源。预测供给模型不能覆盖这些运行事实。

### Core 当前账户事实

`WorldV2ShipHost.GetWorldSnapshot()` 返回 Core World V2 当前快照：

- `resourceJars`：中央 Warehouse 当前 Jar 库存；
- `master.jars`：主工作台 Jar Storage 当前库存；
- `slave.jars`：从工作台 Jar Storage 当前库存；
- 其他时间、订单、活动会话和液体账户快照。

这些余额属于 Core 账户，不由 Space 重算或写回。中央 Warehouse、主台和从台是不同账户，不能合并成一个可随意支取的总库存。

## 三、对账视图的正式边界

新增 `SpaceBattleSupplyReconciliation` 只读服务，将 Parser observation 与 Core 当前快照并排组合。逐形状输出：

- Parser 累计完成量、pending、acknowledged、unattributed；
- Parser 导入回执中的精确 stored/discarded；
- Core 当前 Warehouse、Master、Slave 各自的 Jar 数量。

必须成立的 Parser 过程守恒式：

`completed = pending + acknowledged + unattributed`

精确回执约束：

- `exactStored + exactDiscarded <= acknowledged`；
- 当 `perShapeCoreOutcomeHistoryComplete=true` 时，逐形状必须满足 `exactStored + exactDiscarded = acknowledged`；
- 非法类型、负数量、缺失账户数组或不守恒输入必须 fail closed，不得静默变成零。

### 不允许的推断

Core 导入回执目前按 operation 与 shape 汇总，不将每个导入 Jar 的来源 OperationId 绑定到当前 Jar 实体身份。当前 World snapshot 虽然暴露 Jar ID 和 shape，但没有持久的“此 Jar 来自哪个 Parser 批次”关系。

因此：

- Parser 历史 stored 数量不等于当前 Warehouse 中仍然存在的 Parser 来源 Jar 数；
- 当前 Warehouse 数量还可能包含 Core 时间型 Producer 的产物；
- 已导入 Jar 可能已经流入工作台或被订单执行消耗；
- 不得用 `parserStored - warehouseCurrent` 推导已消耗量；
- 不得把 Warehouse 当前余额归因给 Parser；
- 不得声称当前可见账户合计就是完整世界 Jar 总量（活动执行/预留语义仍由 Core 管理）。

服务显式返回 `sourceAttributionAvailable=false`，并分别展示历史导入结果与当前账户余额。这是“可审计的事实并列”，不是虚假的来源追踪或完整库存守恒证明。

## 四、本轮代码与探针

新增：

- `scripts/industrial/world_v2/SpaceBattleSupplyReconciliation.gd`
- `scripts/industrial/world_v2/SpaceBattleSupplyReconciliationProbe.gd`

调整：

- `SpaceOreParserJarIngressProbe.gd`：运行合成契约检查，并在真实 Parser→Core 导入/检查点恢复探针末尾组合 Parser observation 与 Core 当前快照。
- `SpaceOreParserRuntime.gd`：修正 duplicate 回执注释，区分 schema-11 exact duplicate 与旧 tombstone unknown。
- `docs/industrial/15-production-parser-and-individual-progression-gameplay.md`：修正旧文档中“当前 Core duplicate 永远只返回 0/0/0”的过时表述。
- `docs/work-records/README.md`：加入本记录索引。
- 跨仓库 workflow、README 和 integration checkpoint 已在本轮前段统一 Core SHA。

探针覆盖：

1. 精确回执逐形状 stored/discarded 保留；
2. Parser completed/pending/acknowledged 分项保留；
3. Core Warehouse 与 Master/Slave 库存独立展示；
4. 当前库存不被错误归因给 Parser；
5. 旧回执历史不完整时保留 unknown/incomplete；
6. Parser 数量不守恒时拒绝；
7. Core Jar 缺少合法 shape 时拒绝；
8. 在真实 Parser→Core ingress 检查点恢复场景中验证并列观察。

## 五、验证状态

- 用户本地 Core xUnit：1038 / 1038 通过（用户提供的实际运行结果）。
- Core 当前精确 HEAD 的 GitHub verify：Run `45822480114` success。
- Space 旧精确集成 Run `45796547789` failure，根因是 workflow Core pin 落后；不作为新 pin 的验证证据。
- 本轮新增 GDScript 服务、Probe 与 HUD 接入已提交源码；最新 Space 精确集成 Run `45826120969` 正在执行，尚未取得 Build/Probe 结果。
- 该 Run 的 verify Job `139930613248` 已完成 Space/Core checkout 与 .NET SDK setup，当前仍在安装 Headless runtime dependencies；不能提前标记 Godot import/compile/Headless 通过。
- 桌面 GUI、主菜单/机库/战斗/暂停/返回主菜单交互仍未验收。

## 六、下一步

1. 对当前最新 Space HEAD 执行一次完整跨仓库验证，Core 固定为 `391f318a24fde724a66054e771d0590f0e20c231`。
2. 按失败的第一个步骤修复，不跳过后续探针，也不把旧 Run 的结果移植到新 HEAD。
3. 已将只读对账数据接入战斗 UI 的详情区域；UI 只展示快照，不执行资源规则计算。需要通过当前 Run 验证 GDScript、C#、Godot import 和 Parser/Core probes。
4. 若玩法确实需要知道“哪一批 Parser Jar 现在位于哪个账户”，下一项 Core 设计应是持久的 Jar 来源/转移谱系，而不是在 Space 按数量猜测。先评估事件身份、JarId 生命周期、工作台转移与检查点恢复，再决定是否引入该能力。
5. 对账事实稳定后，再将实际 Parser 消耗、Core 已提交转换事件接入 Owned Individual XP Reward Profile。正式 XP 系数和成长曲线仍由版本化内容数据提供，不写入服务或探针。


## 七、只读对账已接入战斗 HUD（实现已提交，待当前 Run 验证）

在原有持续资源条下方的详情面板新增“原石解析 / Core 导入 / 当前库存”区域：

- `Game.get_supply_reconciliation_snapshot()` 从 Space Parser 获取 observation，并读取 `WorldV2ShipHost.GetWorldSnapshot()`；只调用只读接口。
- `SpaceJarHudObserver` 展示每形状 Parser 完成量、待导入、已确认、精确入库/丢弃，以及当前 Core Warehouse、Master、Slave 各自库存。
- 旧检查点若回执历史不完整，会显示历史不完整提示；不会用 0 填充未知事实。
- UI 明确提示当前账户库存与历史 Parser 入库量分别展示，尚无逐罐来源关联。
- Parser observation 被纳入 HUD 刷新签名，因此即使 Core Jar 数量暂时没有变化，Parser 的排队/进度/导入事实变化也会触发详情刷新。
- Parser/Core 对账契约 Probe 已加入 Parser ingress 主探针；同时检查战斗场景具有供给观察 UI 入口。

最新 Space HEAD：`b322040708c5adccf9ef3b48f3b0ac4bb9d43384`。
最新跨仓库验证：Run `45826120969`，verify Job `139930613248`，运行中。
