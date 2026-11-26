# 2026-11-27 Hangar 启动故障根因更正：外层 Assignment schema 2 未被 Core 接受

## 更正说明

2026-11-26 的初步记录曾误判“Assignment Snapshot schema 1、仅内嵌 Board Definition schema 2”。这是错误的，原因是只检查了 Board Definition producer，没有沿真实调用链核对 Assignment producer。

当前源码 `SpaceHangarBoardAssignment.build_snapshot()` 明确输出外层 `schemaVersion: 2`。每个 assignment entry 同时包含 `areaId` 和 `subAreaId`。Core 在本次故障前的 `WorldV2BoardAssignmentSnapshotOptions.Validate()` 却要求外层 `SchemaVersion == 1`。此前 Core 只接受了嵌套 Board Definition schema 2，没有支持外层 Assignment schema 2。

因此此前要求用户反复重建本地 Bridge 的建议不足以解决问题：即使使用最新 Core，Core 仍然拒绝 Space 实际发送的协议版本。

## 真实运行证据

用户在 Windows / Godot 4.7.1 .NET 桌面环境中点击 Hangar Build 后，日志显示：

- Hangar selector connected，item_count=1；
- 调用进入 `SpaceHangarBattleLauncher.launch_new_battle`；
- `Game._begin_ship_world` 调用 `WorldV2ShipHost.BeginShipWorldFromJson`；
- `WorldV2RuntimeNode.InitializeWorldFromJson` 将冻结配置交给 Core；
- Core 配置校验失败，Game 阻止战斗启动。

这证明选择器信号和建造入口已触发。故障发生于 Core World Options ingress，不是 OptionButton 单选问题。

## Core 修复内容

Core 分支 `architecture/core-liquid-identity-consolidation`：
- 接受 Assignment Snapshot schema 1 和 2；
- Assignment Entry DTO 增加 JSON 字段 `areaId`、`subAreaId`；
- schema 2 严格校验两字段与冻结 Board Slot 一致；
- schema 2 canonical fingerprint 纳入 Area/SubArea；schema 1 fingerprint 形状保持不变；
- 保留 stable SlotId 顺序、Owned Instance、Definition Version、Source Revision 和 fingerprint 校验；
- 把原先综合 identity mismatch 错误拆成可定位的独立诊断。

关键 Core 提交：
- `7b3c7cb91250b6da9d34b60bb04ceada8454fd9f`：schema 2 DTO/校验/fingerprint 支持。
- `ec7b4da5d746347d1c9597476c65c4e3d7744691`：schema 2 正向与层级错配测试。
- `84645bab724a9e71cdcafe54733e67d59a5740a9`：精确身份诊断。
- `15e533691010a24cd8b6a4adcdf6dd1b6d8292ee`：不支持 schema 诊断测试。
- `49b8de4e2e0c5385808e6f9977f337a006f9ef84`：测试 fixture 同时使用外层 Assignment schema 2 和内嵌 Board schema 2。
- `ba84182eba7555b3456d66ffceb58845d97a1bea`：加入跨语言 schema 2 assignment fingerprint golden vector。

## 跨仓库同步修正

此前 Space workflow `.github/workflows/world-v2-cross-repo.yml` 仍固定 checkout Core `391f318a24fde724a66054e771d0590f0e20c231`，这是过期 pin，无法验证本次 schema 2 修复。本轮已将 workflow 与 README pin 更新到 Core 测试代码提交 `ba84182eba7555b3456d66ffceb58845d97a1bea`。

该 pin 必须与 Core 精确头 CI 结果绑定。后续若 Core 新增代码提交，必须再次同步更新 Space workflow、`CORE_EXPECTED_SHA` 和 README。

## 文档治理

新增：
- `docs/PROJECT_DEVELOPMENT_GUIDE.md`
- `docs/architecture/00-system-architecture-and-module-map.md`
- `docs/architecture/13-hangar-board-assignment-and-loadout-pipeline.md`
- `docs/architecture/14-world-v2-host-runtime-and-failure-boundary.md`
- `docs/architecture/15-production-parser-and-resource-supply.md`
- `docs/architecture/16-order-rule-profile-and-effect-dispatch.md`
- `docs/architecture/17-progression-stage-and-persistence.md`

同步了根 README、工业模块文档索引、跨仓库工作流 Core pin。开发指导书要求任何跨仓库协议字段/schema/fingerprint 修改必须同步两端 DTO、producer、consumer、测试向量、集成探针和文档。

## 验证状态（写记录时）

- Core schema 2 实现与测试：已提交。
- Core PR #63 精确头 CI：运行中，尚未宣告通过。
- Space workflow 对 Core pin 的更新：已提交，待对应 Space CI。
- 实际桌面 Hangar → Battle：待用户本地复验。
- 在 Core CI、Space cross-repo CI 和桌面 GUI 均通过前，本故障状态仍为 OPEN。
