# Space 项目开发指导书

状态：强制开发入口；与代码、协议、测试及模块文档同步维护。  
适用：GDScript、C#、Godot 场景/Resource、Space ↔ Jar Core 集成。

## 1. 项目目标与唯一入口

Space 是 Godot 游戏客户端；Jar Core 是同级独立仓库。当前目标流程：

`Main Menu → Hangar → Frozen Owned Loadout → Game Scene → WorldV2ShipHost → Jar Core World`

不得绕过 Hangar 冻结生产配置进入正式战斗。Sandbox 初始化只允许显式开发探针使用。

## 2. 权威所有权

| 领域 | 唯一权威 | Space 可以做什么 | Space 不得做什么 |
|---|---|---|---|
| Jar、液体、工作台、订单、求解、执行、结算、逻辑时钟 | Jar Core | 传入配置/命令，读取快照和领域结果 | 复制规则、可行性、资源扣减、订单求解或结算 |
| Board、槽位、玩家安装关系 | Space Hangar | 定义位置、安装 Owned Instance、冻结版本化快照 | 把槽位角色写成组件个体永久属性 |
| 飞船、Parser、生产设备、技能定义、成长 | Space Domain | 管理内容、实例、进度和效果语义 | 直接修改 Core 内部状态 |
| 战斗、敌人、掉落、关卡、奖励政策 | Space Game | 决定何时提交外部输入、如何响应 Core 事件 | 伪造 Core 已接收/结算的资源 |
| UI、HUD、预览 | Presentation | 展示权威状态、转发玩家意图 | 成为第二份可写领域状态 |
| 根场景导航、暂停与生命周期 | GameFlow / PauseController / ShipHost | 通过指定入口转换 | 让 UI 节点直接管理 Core 时钟或跨场景所有权 |

依赖方向：

`Scene/UI → Application Flow → Space Domain → WorldV2 Host Adapter → Jar Core`

## 3. 模块文档地图

- [总体架构与模块地图](architecture/00-system-architecture-and-module-map.md)
- [应用全生命周期与 UI 状态机](architecture/18-application-flow-and-ui-state-machine.md)
- [Hangar、Board Assignment 与冻结装配协议](architecture/13-hangar-board-assignment-and-loadout-pipeline.md)
- [World V2 Host、GameFlow 与战斗生命周期](architecture/14-world-v2-host-runtime-and-failure-boundary.md)
- [生产、原石 Parser 与资源供给](architecture/15-production-parser-and-resource-supply.md)
- [订单、Rule Profile 与 Space 效果](architecture/16-order-rule-profile-and-effect-dispatch.md)
- [玩家成长、关卡与持久化](architecture/17-progression-stage-and-persistence.md)
- [编码与架构规范](architecture/12-space-engineering-standard.md)
- [World V2 集成契约索引](industrial/README.md)
- [World V2 源码入口](../scripts/industrial/world_v2/README.md)
- [工作记录索引](work-records/README.md)

## 4. 每个模块文档必须包含

1. 目标与非目标。
2. 权威数据所有者。
3. 输入、输出、稳定身份与版本。
4. 依赖方向及禁止依赖。
5. 生命周期/状态转换。
6. 失败语义、回滚与资源释放。
7. 对应源码路径和公共入口。
8. 自动化测试、探针、人工 GUI 验收边界。
9. 未完成事项和当前证据。

## 5. 强制开发闭环

### 修改前
- 确认 Core 与 Space 的分支、HEAD SHA、PR 状态。
- 找到真实调用链和字段生产者/消费者；不要只根据错误文案猜根因。
- 对跨仓库 JSON/DTO/fingerprint，先逐字段对照两端序列化顺序、默认值、版本和规范化规则。
- 明确修复属于生产逻辑、协议、测试夹具还是文档，禁止用测试夹具修复代替运行时修复。

### 修改时
- 先修根因，再补回归测试；不可降低校验强度来让流程通过。
- 每个跨模块输入必须有显式 schema、身份、版本和可定位错误。
- GDScript 对 Dictionary/Variant 读取必须做类型/字段检查；C# Bridge 只做适配。
- 注释解释所有权、前置条件、失败语义和不直观的协议决策，不复述代码。
- 不允许在 UI 中复制领域规则；不允许把临时诊断变成永久高频日志。

### 修改后
- Core 单测/完整验证。
- 精确 Core SHA 的 Bridge 构建。
- Space .NET 构建、Godot Editor import/parse。
- 领域探针、跨仓库集成探针、生命周期/故障探针。
- 实际桌面 GUI：默认配置、进入战斗、暂停/恢复、返回菜单、再次进入战斗。
- 每个结果记录仓库、分支、SHA、命令、精确输出、环境和未覆盖范围。

## 6. 跨仓库版本同步规则

- Space 集成必须固定一个完整 Core commit SHA，不允许只写分支名或“最新”。
- Core 协议改动必须同步更新 Core DTO、Core 测试向量、Space 生产端、Space 消费端、协议文档和跨仓库探针。
- schema 向前兼容必须逐版本定义；不允许因为一个消费者不支持新字段就静默丢弃层级信息。
- 同一个 fingerprint 的两端必须使用同一字段集合、字段顺序、数组排序、字符串编码和数值表达。
- PR Draft、CI 绿色、Headless 通过和桌面 GUI 通过是四种不同状态，不能互相替代。

## 7. 故障分级与完成定义

P0：无法启动、配置身份不一致、资源丢失/重复、时钟双推进、存档破坏。  
P1：玩法流程不可达、状态机无法恢复、关键 UI 操作无效。  
P2：表现、可读性、性能或非关键便利性。

P0 未关闭时不得扩展玩法或把版本标记为可试玩。修复只有在回归测试、精确跨仓库验证和目标平台 GUI 验收均通过后才可标记为“已解决”。

## 8. 文档同步

代码改动涉及模块职责、接口、字段、状态、错误语义、版本或验证流程时，必须同一批提交更新对应模块文档和工作记录。历史结论若被推翻，必须明确写出“更正”，不能让错误结论继续作为现行事实。

## 9. 当前 P0：跨模块 World 配置与运行时语义

### 9.1 Board Assignment schema 2

Space 的 `SpaceHangarBoardAssignment.build_snapshot()` 发送外层 Assignment Snapshot schema 2，并在每条 assignment 中携带 `areaId`、`subAreaId`。Core 曾只接受外层 schema 1，导致 Hangar 点击建造后在 World 初始化前失败。Core schema 2 支持和 golden vector 已通过 Core run `45856292385`；当前 Space PR #2 的精确 Core pin 跨仓库验证已于 Run `45875481227` 成功。桌面 GUI 复验仍待完成，详见对应工作记录。

### 9.2 World liquid polarity 必须完整传播

World 的液体词汇不是只有 `liquids` 名称数组，而是不可拆分的三元组：`shapes + liquids + liquidPolarities`。Core 的 `WorldV2Context` 是映射的唯一权威；任何创建 `Vocabulary`、Jar、Requirement 或订单规格的应用服务必须传递 `context.LiquidPolarities`。不得从液体名称、列表顺序、资源账户字典或旧默认值推断自定义 World 的极性。此次 `AddJarDemandFromTemplate` 丢失映射导致运行时已初始化、订单物化失败；Core 三个应用服务入口已修复并添加非默认映射回归测试，验证状态见 [订单实例化液体极性传播故障记录](work-records/2026-11-27-order-materialization-liquid-polarity-fault.md)。

### 9.3 导航探针必须区分负向与正向结果

导航探针可包含预期失败路径，但必须分别输出“失败回滚验证通过”和“真实 MainMenu 转场通过”标记。集成脚本必须要求两个标记；不得仅凭 GameFlow 的逻辑状态或单一泛化成功字符串宣告场景切换通过。

## 10. 战斗暂停、退出与检查点一致性

战斗中必须同时提供可见的屏幕暂停按钮和 Escape 快捷键；快捷键不能是唯一入口。暂停面板必须同时提供继续和返回主菜单。返回主菜单必须由 `Game.gd` 结束战斗生命周期并释放 World V2 Host，再由 `GameFlow.return_to_menu` 执行转场，禁止 UI 直接切场景。

订单效果提交必须原子持久化效果状态和 Dispatcher EventId；只有完整运行时检查点可安全捕获时，才将其与效果状态一起提交。有限关卡活动波次期间不能伪造可恢复检查点：效果可在内存中幂等应用，但 Jar 事件必须保持 pending，直到无敌人阶段间隔成功持久化；死亡/终局关闭不得尝试生成可恢复检查点。检查点身份必须与冻结 Loadout 的 `shipWorldId/loadoutId/loadoutVersion/loadoutFingerprint` 一致。设计见 [Battle Pause UI and Runtime Checkpoint Contract](architecture/17-battle-pause-ui-and-checkpoint-contract.md)。


## 11. 当前跨仓库集成检查点（2026-11-27）

- Core：PR #63，分支 `architecture/core-liquid-identity-consolidation`，集成固定 SHA `116c0bb7e3589a2850bf1b85f6da4c48de8c0a28`。
- Space：PR #2，分支 `world-v2/phase-4.10b-hangar-ui`，当前工作提交 `72782e95d3c36b0485d6d8c3ea616b5cf16b35c3`。
- 精确跨仓库 Run `45875481227`：completed / success。它证明当前 SHA 组合的 Bridge、Space、Godot Headless 和脚本化领域/生命周期探针通过，不替代桌面 GUI。
- 主场景 `main.tscn` → `Main.gd` → Main Menu → Hangar。演示目录资源位于 `data/hangar/demo_catalog_bundle.tres` 与 `demo_board.tres`；首次启动通过显式 DEMO bootstrap 建立原型 Owned Inventory，并由 Hangar draft 生成默认 owned-instance 配置。
- 桌面验收仍需人工完成：主菜单启动、机库默认装配、进入战斗、订单/资源变化、暂停/继续、返回主菜单、再次进入战斗、GameOver 返回机库/主菜单、窗口关闭。
- Reward Coordinator 已接入 Hangar 可选恢复入口；demo 资源包尚未配置正式 Reward Profile / Curve Catalog，因此不会在未定义 XP 平衡的情况下自动发放成长奖励。


## 12. Sandbox entry is opt-in

The production Game scene must not enter a Sandbox World when no frozen Owned Loadout was injected. `Game.allow_sandbox_world_for_development` therefore defaults to `false`. A developer-only fixture may explicitly opt in when it is intentionally testing Sandbox behavior; Hangar production launch must always supply the immutable Owned Loadout snapshot. Do not turn this flag on to work around a failed Core initialization or missing Hangar configuration.
