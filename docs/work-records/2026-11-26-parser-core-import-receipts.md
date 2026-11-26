# 2026-11-26 Parser Core 导入回执留存

## 基线

- 仓库：`Lazyair150/space-demo`
- 分支：`world-v2/phase-4.10b-hangar-ui`
- 源 HEAD：`0b800dad7c572b508aee10901bc06f81fcdd9acb`
- Core 精确源：`da57eeecece87b6e2af7548f86b748cc24f2a559`
- 基线自动化：Space PR #2 run `45787796492` 对应 `0b800dad7c572b508aee10901bc06f81fcdd9acb`，SUCCESS。
- 本轮不重复执行该基线上的供给/Parser 测试。

## 审计发现

1. Space Parser 已经为每批输出产生稳定 `operationId`，并在 Core 确认前保留 pending outbox。
2. `WorldV2ShipHost.ImportProducedJars` 的首次成功响应包含 `wasDuplicate`、`submittedJarCount`、`storedJarCount`、`discardedJarCount`。
3. Core `WorldV2ApplicationService.ImportProducedJars` 在相同 operation ID + 相同规范化载荷的重放时返回 `WasDuplicate=true` 和计数 `0/0/0`；它确认此前已有提交，但不重新返回首次仓库容量分配结果。
4. 因此不能把 duplicate response 的零计数写成原始提交“存储零只、丢弃零只”。真实原始 outcome 在该 DTO 路径上不可知。
5. Game 的外层 Space Parser envelope schema 仍为 2；本次仅升级其内层 Parser Runtime checkpoint schema，不改变协调战斗 checkpoint envelope 版本。

## 本轮实现

- Parser Runtime checkpoint schema 从 4 升至 5（兼容读取 schema 2/3/4），加入 `coreImportReceipts` 和 `coreImportReceiptHistoryComplete`。
- `acknowledge_output_batch()` 必须接收完整 Core 响应；先校验请求数量、Core 返回字段及计数关系，再将 receipt 写入 ledger 并移除 pending outbox。校验失败不会修改任何状态。
- 首次提交记录为 `outcomeStatus=exact`，要求 `submitted=requested` 且 `stored+discarded=submitted`。
- 旧 Core 回执格式仍可保存为 `duplicate_confirmation_only`；新 Core 返回 `hasExactReceipt=true` 时，重复确认记录为 `outcomeStatus=duplicate_exact`，保留原始逐 shape 申请量及 stored/discarded 数量。
- Restore 验证 receipt operation ID namespace、batch sequence 唯一性、请求 shape/count、Core response 和每形状生产数量守恒。
- 新建 Parser 的 receipt history 完整；schema 2/3 迁移后 history completeness 明确为 false。完整历史状态要求 pending + acknowledged requested 数量逐形状等于累计产出。
- 新增只读 `build_supply_observation_snapshot()`，汇总接受/排队/处理体积、累计 Jar、pending、回执、精确 stored/discarded、重复确认未知 outcome 和历史完整性。
- 更新 Parser Runtime Probe 与跨 Core Ingress Probe：覆盖坏回执原子拒绝、精确回执往返、schema-3 迁移、Core duplicate 返回不完整容量信息时的显式未知标记。

## 不在本轮宣称完成

- Core 已增加持久化 produced-Jar import receipt，并在重复调用时返回首次精确逐形状 requested/stored/discarded maps；旧 schema 10 检查点仍没有该回执，必须继续显示 unknown。
- 观察快照仍是 Space Parser 侧事实，不等于 Core 当前实时 Warehouse/资源账本完整快照。
- 外层完整玩家存档的跨文件原子提交协调仍是独立问题。
- 新增 GDScript、C# bridge 和 Probe 源码已同步；仍需在成组完成后执行 Godot 4.7.1 .NET 编译与 Headless Probe。本工作不把源码写入等同于运行通过。

## 下一步

1. 将 Parser observation 与 Core 实时 Warehouse / 资源账本快照合并为只读战斗供给对账视图，明确区分累计产出、仓库存量、已丢弃与仍未导入数量。
2. 用对账视图驱动生产可见性 HUD 和战后结算事实采集，不把预估供给当成实际结算。
3. 在事实对账稳定后，再接入基于已确认事件的 XP Reward Profile；不提前制造生产奖励数值。

## 本轮 Space 分支最终落点

- 行为实现最后一组提交（后续仅做过程记录同步）：`3aba7b180c3f597d82578aef504cd5b10760fe5c`。
- 最新 Core 依赖：`da57eeecece87b6e2af7548f86b748cc24f2a559`。
- PR #2 维持 Open/Draft；本轮不等待 CI，测试状态以未运行明确记录。


## 2026-11-26 Core 精确回执接入（过程追加）

### 实施依据

Core 分支新增提交 `0faffd14e2660b94d2c08ef0c9cbb06c0cbdcb2e`、`3cd18335134e736740f11d4c0d9e3c5187e94d70`、`7e9f2cc8cf7feb492f1aa656bf7ac19cd8737f2d`、`55ff24bed2fb19e93f3e93b6a4690a8c07573c5d` 与 `da57eeecece87b6e2af7548f86b748cc24f2a559`，在 ResourceLedger 持久保存每个外部导入批次的请求/入库/丢弃逐形状数量、payload 指纹，并纳入 schema 11 检查点；导入 DTO 同时返回首次逐形状入库/丢弃 maps。Space 不读取事件日志推断历史结果。

### Space 侧成组修改

- `WorldV2RuntimeNode.ImportProducedJars` 将 Core 的 `HasExactReceipt`、`StoredJarCountsByShape`、`DiscardedJarCountsByShape` 映射为 Godot 字段 `hasExactReceipt`、`storedJarCountsByShape`、`discardedJarCountsByShape`。
- `WorldV2ShipHost` 将该字段加入完整回执契约检查；缺字段时拒绝确认，不会删除 Parser pending outbox。
- Parser Runtime checkpoint schema 升至 5，导入回执 schema 升至 2；仍兼容 schema 4 / receipt schema 1 的历史存档。
- 新 duplicate 回执若带 `hasExactReceipt=true`，以 `duplicate_exact` 记录并计入逐形状 stored/discarded 汇总；旧 duplicate 0/0/0 仍标记未知。
- Runtime Probe 新增精确重复回执与 schema4 旧回执迁移断言；Ingress Probe 改为验证 Core 重放返回首次 exact outcome。
- 没有改动正式掉落率、生产平衡或经验奖励数据。

### 验证状态

- Core 分支最终提交：`da57eeecece87b6e2af7548f86b748cc24f2a559`。
- Space 分支本轮成组提交：`ab0a813b17f77f8464bee4ac5ea1cd65c7f3ee07`、`8c56c6efbd56d16ae19249fdeced34a958d3ce10`、`3aba7b180c3f597d82578aef504cd5b10760fe5c`。
- 当前开发工作站没有挂载两个仓库的本地工作树，也未检测到 `dotnet` / Godot 可执行文件；因此没有实际运行 xUnit、Godot .NET 编译、Headless Probe 或 GUI 试玩。
- 已对两仓关键 DTO、字段映射、schema、restore 分支、回执 map conservation、旧 schema 兼容和测试用例做源码静态核对。此核对不等同于运行通过。
- 本轮不等待 GitHub Actions / CL，也不以它们作为开发节奏的阻塞条件。
