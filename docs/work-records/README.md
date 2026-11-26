# Space 工作记录专区

本目录记录 Space 与 Jar Core 的跨仓库集成、游戏流程、战斗生命周期、机库、资源契约和 GUI 验收。

约定：
- 使用 `YYYY-MM-DD-主题.md` 命名。
- 记录仓库、分支、commit SHA、Core 精确版本、实际改动、CI run 与人工验收边界。
- 明确区分 Godot import/parse、Headless SceneTree、.NET build/test、桌面 GUI 试玩。
- 不把 Core 规则复制到 Space；Space 文档只记录 Space 的语义映射、内容和集成契约。
- 历史记录不覆盖；新结果追加记录并更新索引。
- 本目录为版本化文档区；仅 `_local/` 导出临时产物被忽略。

当前重点：
- [2026-11-27 订单实例化液体极性传播故障](2026-11-27-order-materialization-liquid-polarity-fault.md)
- [2026-11-27 Hangar Assignment schema 2 根因更正](2026-11-27-hangar-assignment-schema-v2-root-cause-correction.md)
- [2026-11-26 真实 Hangar Board Schema 运行时故障与 Core 兼容修复](2026-11-26-live-hangar-board-schema-runtime-fault.md)
- [2026-11-26 跨仓库探针生命周期与诊断修正](2026-11-26-cross-repo-probe-lifecycle.md)
- [2026-11-26 供给对账观察契约](2026-11-26-supply-reconciliation-contract.md)
- [2026-11-26 Parser Core 导入回执留存](2026-11-26-parser-core-import-receipts.md)
- [2026-11-26 供给场景敏感性区间](2026-11-26-supply-scenario-band.md)
- [2026-11-25 Core 收敛协作记录](2026-11-25-core-consolidation.md)
- Core 架构审查源文档位于 Jar Core 仓库 `docs/architecture/2026-11-core-multi-angle-audit.md`。

- [2026-11-27 战斗暂停入口与检查点拒绝诊断](2026-11-27-battle-pause-and-checkpoint-rejection.md)
