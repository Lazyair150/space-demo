# 成长奖励协调器与机库恢复

日期：2026-11-27  
仓库：`Lazyair150/space-demo`  
分支：`world-v2/phase-4.10b-hangar-ui`  
Core 固定版本：`116c0bb7e3589a2850bf1b85f6da4c48de8c0a28`

## 目标

把已经持久化在 Campaign Clear 记录中的成长奖励事实信封，接入版本化 Reward Profile、Progression Curve Catalog 和现有幂等结算服务；在重新进入 Hangar 时恢复未完成的奖励结算。

## 实现

- 新增 `SpaceProgressionRewardCoordinator`，从持久化 Campaign Clear record 读取奖励 outbox。
- 校验精确 Stage ID/version、objective-complete 状态、稳定 settlement ID，以及对应的 Stage-clear fact。
- 由 Reward Profile 将整个事实数组转换为最终 XP awards；缺失任一来源策略时整笔拒绝，不静默跳过。
- 使用现有 `SpaceProgressionRewardService.prepare_settlement` 和 `GameState.commit_space_progression_reward_settlement`，保留 Detached Candidate、保存成功后发布、收据指纹及重复提交语义。
- Hangar Catalog Bundle 可选接收 Reward Profile 与 Curve Catalog，但必须成对配置；没有生产资产时不创建虚构 XP 数值，也不启用恢复。
- Hangar 每次进入时尝试恢复。若上次在 Campaign Clear 保存后、Progression 保存前崩溃，重试会继续结算；若 Progression 已保存，重复收据返回 no-op 成功。
- 扩展统一 Domain Contract Probe，加入协调器的 Stage 身份、Stage-clear 事实和 Reward Profile 版本检查。

## 事务边界

Campaign Clear 与 Player Progression 是两个独立持久化聚合，不宣称跨文件原子提交。Campaign Clear 中的事实信封充当 durable outbox；Progression receipt 是消费证明。相同 settlement ID 携带不同 award payload 会被 fingerprint 冲突拒绝。

## 尚未完成

- 生产 Reward Profile / Curve Catalog 仍需真实内容数据；未配置时 outbox 保持 pending。
- Parser 实际处理体积、Production committed work、Workshop rule transition、Skill effect cycle 等来源仍需各自权威模块提供稳定提交事件；不得用预测、UI 激活或库存差额替代。
- 本次代码变更尚未执行最终 Core/Space/Godot 集中验证；验证结果以精确提交对应的工作流为准。
- 桌面 GUI 的完整流程验收仍待执行。

## 代码入口

- `scripts/industrial/world_v2/SpaceProgressionRewardCoordinator.gd`
- `scripts/industrial/world_v2/SpaceProgressionRewardCoordinatorProbe.gd`
- `scripts/industrial/world_v2/SpaceHangarCatalogBundleResource.gd`
- `scripts/industrial/world_v2/SpaceHangarScreen.gd`
- `globals/GameState.gd`（复用既有持久化结算入口，无修改）
