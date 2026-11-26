# 玩家成长、关卡与持久化模块

## 1. Player Progression

Catalog Definition 是可复用内容模板；Owned Instance 是玩家持有的独立副本。实例拥有稳定 ID、精确 Definition ID/Version、等级、经验、revision 和成长属性。两个同 Definition 的实例也必须独立成长。

成长服务根据版本化 Progression Curve 计算完整成长快照，再通过 revision-checked 更新写回 Progression Aggregate。战斗 Loadout 冻结使用的实例快照，不受之后 Catalog/成长修改影响。

## 2. Roguelike Individual

局内 Offer/Reward 产生的个体与永久玩家库存不是同一生命周期。Offer、选择、战斗内状态和结算身份必须独立；不得把临时局内对象误写入永久 progression。

## 3. Stage

Stage Definition 是版本化内容；Encounter Director 管遭遇节奏；Objective Runtime 管目标进度；Game 管组合；GameState/settlement owner 负责持久化通关事实。

遭遇清空不等于目标完成，也不等于奖励已持久化。只有遭遇和目标都完成，且 durable settlement callback 成功，才允许发出 Stage Complete。

## 4. Checkpoint

Checkpoint 必须冻结 exact stage identity、loadout identity/fingerprint、Encounter Director、Objective Runtime、Jar checkpoint、Parser state、Space effect state、dispatcher ledger 和临时 GameState。只允许恢复被 schema 明确支持的场景窗口；不支持的 live actor 状态不能声称可恢复。

## 5. 源码入口

Progression：`SpacePlayerProgressionState.gd`、`SpaceOwnedProgressionInstance.gd`、`SpaceProgressionGrowthService.gd`、`SpaceProgressionRewardService.gd`。  
Stage：`SpaceStageCatalog.gd`、`SpaceStageEncounterDirector.gd`、`SpaceStageObjectiveRuntime.gd`、`Game.gd`。  
更详细内容见 [15 — Production, Parser and Individual Progression Gameplay](../industrial/15-production-parser-and-individual-progression-gameplay.md)。
