# 订单、Board Rule Profile 与 Space 效果分发

## 1. 两个不同语义域

Jar Core 的 Order 是资源需求、可行性、准入、执行、冷却和完成事实。Space 的 Skill 是玩家能力及其战斗/世界效果定义。两者通过精确绑定连接，不互相替代。

## 2. Board Rule Profile

Space 从 Board Assignment 中的精确 Owned Instance、Definition Version、Progression Revision 解析 Rule Contributions。Core 负责验证来源确实安装在指定 Slot，并构建 EffectiveRuleProfile。

- Assignment Snapshot 是安装关系事实。
- Rule Profile 是从该 revision 派生的规则贡献集合。
- Profile 必须携带完全相同的 Board ID、Definition Version 和 Assignment Fingerprint。
- contribution provenance 必须指回同一 Slot 和 Owned Instance。
- 不支持的 scope 必须显式拒绝，不允许静默忽略。

## 3. Order binding

Hangar 对技能选择冻结 exact skill definition/version、Owned Instance 和 orderDefinitionKey。Jar Order Template 提供实际需求；Space 不应把技能效果参数伪装成 Jar 规则。Core 仍是需求可行性和执行的权威。

## 4. 事件到效果

```text
Jar Core Order completion fact
  -> WorldV2ShipHost snapshot/event boundary
  -> SpaceOrderEffectDispatcher
  -> Space effect catalog / target resolver
  -> Space effect state
  -> atomic persistence callback
```

效果应用必须幂等。若效果状态与 dispatcher event ledger 不一致，不能继续结算或假定效果已经生效。

## 5. Active / Passive

- Active：玩家明确发起 Start 请求；Core 决定是否可行和是否准入。
- Passive：Core scheduler 决定何时执行；Space 不提供伪造的手动启动。
- HUD 只转发 demand ID 并显示 Core 的结果。
- Cooldown 和订单生命周期归 Core；技能效果语义归 Space。

## 6. 源码入口

`SpaceRuleContributionResolver.gd`、`SpaceBoardRuntimeProfileSet.gd`、`SpaceCoreOrderTemplateDefinition.gd`、`SpaceOrderEffectDispatcher.gd`、`SpaceOrderEffectCommitter.gd`、`SpaceBattleEffectStateStore.gd`。详细规则范围见 [14 — Ability and Workshop Rule Scopes](../industrial/14-space-ability-and-workshop-rule-scopes.md)。
