# 玩家成长、关卡与持久化模块

## 1. Player Progression

Catalog Definition 是可复用内容模板；Owned Instance 是玩家持有的独立副本。实例拥有稳定 ID、精确 Definition ID/Version、等级、经验、revision 和成长属性。两个同 Definition 的实例也必须独立成长。

成长服务根据版本化 Progression Curve 计算完整成长快照，再通过 revision-checked 更新写回 Progression Aggregate。战斗 Loadout 冻结使用的实例快照，不受之后 Catalog/成长修改影响。

## 1.1 Reward Policy and Committed Facts

`SpaceProgressionRewardProfile` is the versioned content-policy boundary between committed source facts and final XP awards. A profile has an exact identity/version and an explicit rule for each enabled source kind. Each rule selects the compatible Owned Instance kind, final positive integer XP, and exact progression Curve ID / Version. Missing rules, incompatible source/item mappings, duplicate source Event IDs, or mixed policy versions fail closed. There are no default XP values.

The profile accepts only committed fact envelopes (`eventId`, `instanceId`, `sourceKind`, `sourceRef`). It does not create facts, infer provenance from forecasts, or query live UI state. Its output stamps `rewardProfileId` and `rewardProfileVersion` into every award; the settlement fingerprint therefore binds the final awards to the exact policy revision.

`SpaceBattleRewardFactProjection` currently projects only accepted Parser Pickup identities and the exact Stage-clear candidate into stable facts attributed to the frozen Ship Owned Instance. The stage-clear callback persists this envelope inside the campaign clear record, making that record the durable source-fact outbox. Parser processed volume, production work, Workshop rule transitions and Skill cycle facts remain explicitly uncovered until their authoritative subsystems expose stable committed event identities.

The generic reward service remains a settlement mechanism: it validates ownership, exact curves, revisions, duplicate source receipts, and detached candidate state. It does not calculate game balance. The production Reward Profile and Curve Catalog are not yet authored or connected to the battle lifecycle; the current probe values are synthetic contract fixtures only.

## 2. Roguelike Individual

局内 Offer/Reward 产生的个体与永久玩家库存不是同一生命周期。Offer、选择、战斗内状态和结算身份必须独立；不得把临时局内对象误写入永久 progression。

## 3. Stage

Stage Definition 是版本化内容；Encounter Director 管遭遇节奏；Objective Runtime 管目标进度；Game 管组合；GameState/settlement owner 负责持久化通关事实。

遭遇清空不等于目标完成，也不等于成长奖励已持久化。Stage-clear result carries a versioned progression reward settlement identity and committed-fact envelope; the campaign clear callback persists both with the clear record. Campaign clear receipt 与 XP progression receipt 仍属于两个不同的持久化聚合；不得因为 stage-clear callback 成功就声称 XP 已结算。只有遭遇和目标都完成，且 campaign clear 的 durable settlement callback 成功，才允许发出 Stage Complete。成长奖励必须另有 exact-version Reward Profile、已提交事实和可恢复的持久化协调边界。

## 4. Checkpoint

Checkpoint 必须冻结 exact stage identity、loadout identity/fingerprint、Encounter Director、Objective Runtime、Jar checkpoint、Parser state、Space effect state、dispatcher ledger 和临时 GameState。只允许恢复被 schema 明确支持的场景窗口；不支持的 live actor 状态不能声称可恢复。

## 5. 源码入口

Progression：`SpacePlayerProgressionState.gd`、`SpaceOwnedProgressionInstance.gd`、`SpaceProgressionGrowthService.gd`、`SpaceProgressionRewardProfile.gd`、`SpaceProgressionRewardService.gd`。  
Stage：`SpaceStageCatalog.gd`、`SpaceStageEncounterDirector.gd`、`SpaceStageObjectiveRuntime.gd`、`Game.gd`。  
更详细内容见 [15 — Production, Parser and Individual Progression Gameplay](../industrial/15-production-parser-and-individual-progression-gameplay.md)。
