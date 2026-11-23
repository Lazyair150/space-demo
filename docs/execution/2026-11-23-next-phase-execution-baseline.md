# 临时执行基线：Space / Jar World V2 下一阶段

> 状态：执行中（临时工作文档，不替代领域设计文档）
> 建立日期：2026-11-23
> 仓库：`Lazyair150/space-demo`
> 工作分支：`world-v2/phase-4.10b-hangar-ui`
> PR：[#2](https://github.com/Lazyair150/space-demo/pull/2)（Draft / Open；禁止擅自合并）
> 本文用途：固定当前事实、执行边界、工作顺序和验收条件。每轮完成后更新“执行记录”，不得把计划写成已实现，也不得把未运行的 Probe 写成通过。

## 0. 执行原则

1. 以当前分支源文件为事实依据；旧对话中的计划、PR 描述和本文件都不能覆盖实际代码。
2. 每次开工先核对目标文件和依赖接口，再修改；不凭类名猜 API，不重复创建已有模块。
3. 先建立正确的领域契约和数据流，再接 UI、存档和战斗运行时；不要用占位数字伪装正式平衡。
4. 所有可成长的解析器、工作台、技能等均为独立 Owned Instance；Definition 是模板，Instance 才属于玩家。
5. 每个个体必须由其所属子系统的指标模型计算强度；强度必须落在该模型、该稀有度对应的有效预算区间内。禁止超模、低模；不同 item kind / power model 的 raw score 不可直接横向比较。
6. 不允许用通用成长乘数、虚构权重或临时数值填充尚未定义的正式经济模型。无法确定时显式标为 `unconfigured`，阻止进入正式池。
7. Jar Core 是订单可行性、资源、冷却和 Passive scheduler 的唯一权威；Space 只提供请求、冻结战斗语义和执行成功后的效果。
8. 文件写入必须逐项核对 GitHub 当前 SHA；同一路径的写入不能并行。不要合并 PR #2。
9. 区分 authored、静态审阅、CI 验证、Godot 运行时验证。未执行的验证必须标记为未执行。

## 1. 不可变领域规则

### Jar / Workshop
- Ban 只约束对应工作台暂存区的液体入口；Jar 内液体自耗不是工作台暂存区液体，不得错误交给工作台 Ban 检查。
- Jar 是独立实体；但主台不得把主台 Ban 的液体传给从台。装入 Jar 不能成为绕过主台 Ban 的路径。
- B 类订单会产生从台使用事件；从台使用期间只接收主台提供的液体。主从资源流单向。
- B 类订单可以需要液体资源，不能把 B 类限制成只转移 Jar。
- 订单过程产生的游离液体必须先进入当前工作台暂存空间；拒收或超限则丢弃。液体回收唯一入口是工作台暂存区。
- 不保留专门储存 Ban 液体的暂存区。
- `maxLiquids` 与可选聚合 `liquidStagingCapacity` 是不同概念；`-1` 仅代表遵循 Core documented fallback，不能作为负容量或擅自转成显式值。

### Space / Skills / Effects
- Skill Definition、Jar Order contract、Space Effect Definition/Execution 分层；订单周期可启动持续激光、导弹、无人机、护盾等，不等于单发子弹。
- Core 成功执行订单是正式触发 Space Effect 的唯一来源；不能在 Space 重做可行性、冷却或 Passive 调度。
- Active 请求由玩家触发并交 Core admission；Passive scheduling 由 Core 管理。
- 非 Buff 效果不得伪装为 BuffDefinition；后续必须使用类型化 Effect Definition 与 Executor。

### Progression / Roguelike
- Definition 与 Owned Instance 分离；同一 Definition 可有多个独立成长的 Instance。
- 战斗 Loadout 必须冻结 exact definition ID/version、instance ID、level、experience、growth attributes、progression revision 和成长曲线 provenance。
- 解析器、工作台、技能的指标模型分别由所属子系统定义；模型版本必须精确绑定到个体池。
- 肉鸽抽取只产生 Offer，不直接改变玩家所有权；玩家选择后才领取。领取必须幂等、持久化成功后才发布内存状态。
- 每个 pool entry 的 power score 必须由其绑定的 power model 从完整指标计算得出，并落入对应 rarity band。禁止用跨模型分数做统一稀有度预算。

### Stages / Persistence
- 有限关卡与 endless loop 分开；stage exact ID/version 与冻结 loadout identity 绑定。
- Stage clear 必须先完成持久化再发布成功事件；重复 settlement ID 不得重复发奖。
- Checkpoint 只恢复已序列化的状态；不能声称恢复未序列化的敌人或目标 Actor。
- 任何失败恢复都必须保持旧存档可用；跨 aggregate 事务未实现前不得宣称 Campaign clear 与奖励已原子结算。

## 2. 已有实现（需继续以代码核对）

- World V2 Host/Runtime 集成边界、Active request adapter、Jar HUD observer 与形状视觉映射。
- Workshop local definition / Master-Slave pair / combination 资源模型。
- Skill 五类能力分类与类别—Jar shape profile 校验；当前 sandbox vocab 不能证明五类 shape 已全部正式配置。
- Owned progression aggregate、exact-version unlock/acquire、独立实例成长、revision 检查、存档序列化。
- Versioned progression curves 与成长属性快照；不同 item kind 有不同曲线类型。
- Hangar owned inventory / owned loadout assembler / frozen instance snapshots 已存在；但生产目录资源和生产启动路由仍需检查，不能仅凭这些类存在就认定流程已接通。
- 五关 Rift Frontier、finite encounter director、stage objective、inter-beat checkpoint、campaign clear ledger。
- Rift Warden typed boss actor 和有限关卡 Boss spawn 路径。
- Roguelike individual library / pool / power model / offer / reward service 的基础框架。
- GameState progression 与 campaign 独立持久化、persist-before-publish 与恢复机制。
- 概念 SVG 素材已创建；不是正式动画、碰撞或最终美术资源。

## 3. 当前已确认的缺口

1. **正式生产目录为空缺**：当前 `data/` 下可见 `effects`、`industrial`、`stages`；`data/industrial` 仅有 World V2 sandbox/invalid JSON。需要核对各 Resource catalog 与 Hangar bundle 的生产资源绑定；不得凭空创建平衡值。
2. **个体强度模型尚未生产化**：现有通用 evaluator / power model 框架不能代替解析器、工作台、技能各自真实指标的定义、归一化、权重与有效预算。
3. **Hangar 正式路径未闭环**：`SpaceHangar.tscn` 目前绑定 stage catalog 与 Preparation；MainMenu Start 仍需核对是否绕过 Hangar；选择、冻结、Launch、恢复和战斗结算要形成一条真实路径。
4. **订单资源需求来源重复（架构入口已打通，生产配置仍待作者录入）**：Core PR #60 已将 `orderTemplates` 纳入 World V2 options，并提供 `AddJarDemandFromTemplate`。Space Runtime / Host / ShipHost 已能按模板键物化；`SpaceSkillDefinition` 已支持 exact `template_id + version`，生产 Hangar bundle 强制技能引用模板，并从冻结 World options 解析实际需求用于平衡评估。仍缺真实 workshop combination 里的模板数据与实际技能 Definition 的迁移；legacy inline requirements 仅供隔离开发 Probe 使用。
5. **Stage reward transaction 未完成**：Campaign clear 与 progression reward 尚无跨 aggregate 原子提交；Offer UI / 玩家选取 / durable receipt 仍需接通。
6. **Protected Target 未完成**：有 objective contract，但真实可受攻击 Actor、敌人目标选择、被摧毁事件与 checkpoint identity 仍需实现。
7. **Typed Effect 系统未完成**：当前 Buff-first；Beam / Projectile / Missile / Shield / SupportUnit / Recon 等需要真实类型化定义和执行器。
8. **生产初始拥有库存/解锁引导未完成**：需确定新玩家初始可用船、解析器、工作台、技能实例的来源和版本；不得把 Definition 列表直接当成 Owned Inventory。
9. **验证边界**：Space demo 的 Godot 4.7.1 .NET 编译、GDScript parse、SceneTree Probe 和集成验证当前未执行；Core PR #59 的成功 CI 只覆盖该 Core head，不等于 Space demo 已验证。

## 4. 执行顺序与完成定义

### Phase A — 事实审计与契约收敛（当前）
- [x] 已审计 Game / Spawner / Boss / Hangar / GameState / Reward / Power Evaluator 的主要实际接口；仍需后续做完整调用链闭环审计。
- [x] Hangar Screen 的选择控件确实使用 owned inventory，回调传递各槽位 instance ID；不存在“Controller 已写但 UI 未接线”的断层。MainMenu/Launch 仍未闭环。
- [x] 新/resumed stage 的 durable settlement callback 与 exact stage/loadout identity 已确认；protected target 仍缺持久化实例身份，需在 Protected Target 阶段补齐。
- [x] OwnedLoadoutAssembler 已将 Ship、Parser、Master/Slave Workshop、Device、Skill 的独立 Owned Instance 快照及成长合成结果写入冻结快照。
- 完成定义：调用链和所有权边界有源码证据；发现的问题形成修复提交，不以文档审计代替修复。

### Phase B — 子系统真实指标与强度模型
- [x] 通用 scoring contract 已支持显式 higher/lower/target_value 语义；Workshop 容量、逐 shape Mark、逐 liquid Ban 和 Core fallback 的生产模型被强制使用 target_value；unconfigured 模型不能进入生产 Pool。此项只完成模型机制，不代表真实维度/权重已配置。
- [ ] Parser：从实际运行效果确定解析效率、能量石维持时间、稳定性、吞吐量等指标及方向；区分原始定义属性与成长后有效属性。
- [ ] Workshop：从实际规则确定 Jar 容量、液体容量、暂存容量、Mark/Ban、操作成本和副作用；不能简单假定容量越大越强。
- [ ] Skill：把 Space 效果收益与真实 Jar Order 成本、冷却、资源量、执行难度关联；收益越高通常应有更高资源代价，但必须由实际模型计算。
- [ ] 每类模型有独立 ID/version、指标定义、范围、方向、权重、归一化规则、有效强度区间和解释报告。
- [ ] 成长后的 instance 必须重新计算 effective metrics / power；越界时拒绝成长结果或拒绝进入可用池，不能静默 clamp。
- [ ] 未确定的维度/权重标为 unconfigured，模型不得被生产 pool 引用。
- 完成定义：每个合法个体有可解释分数；边界值、缺失维度、超范围、成长越界均有 Probe 覆盖；无假数字。

### Phase C — 生产 Catalog 与初始 Owned Inventory
- [ ] 建立 exact-version catalog resources / bundle；只收录已通过所属模型验证的定义。
- [ ] 建立明确的 prototype 与 production 标记；prototype 不进入正式肉鸽池。
- [ ] 确定新玩家初始解锁、获得实例和版本迁移规则。
- [ ] 每个 item kind 的 Pool 绑定自己的 power model exact version 与 rarity bands。
- 完成定义：Hangar inventory 来自玩家 progression + 已验证 catalogs，不是直接展示所有 Definition。

### Phase D — Hangar Owned Instance 装配闭环
- [ ] Hangar UI 的 Parser / Master Workshop / Slave Workshop / Skills / Devices / Ship 均选择 Owned Instance ID。
- [ ] Master 与 Slave 必须是两个不同 instance；两者可同 Definition 但各自成长独立。
- [x] 兼容性校验已接入 exact skill template ID/version、选中 Core world template、形状/液体词表、主形状严格多数；workshop capacity / role 继续由 owned composer 和 Core options 校验。
- [ ] 为生产 WorkshopCombination 资源录入正式 orderTemplates，并把生产技能定义迁移到 template ID/version；未录入真实配置前不创建虚构模板配方。
- [ ] 冻结 snapshot 包含所有选中 instance 的完整成长与 provenance；Battle runtime 只读取冻结快照。
- 完成定义：UI 选择、Assembler、Snapshot、战斗 Host 之间无 Definition-only 漏洞。

### Phase E — MainMenu / Launch / Restore
- [ ] MainMenu Start 进入 Hangar；开发直入战斗仅保留显式 dev route。
- [ ] Hangar 选择 stage + owned loadout 后调用 launcher；effect commit callback 必须存在。
- [ ] Resume 必须恢复 exact loadout/stage 与 target identity，且重新注入 durable settlement callback。
- [ ] 启动失败不能残留半配置战斗 Scene 或错误 GameFlow 状态。
- 完成定义：新开、恢复、拒绝启动三条路径的生命周期与存档边界明确。

### Phase F — Stage Reward 事务与 Offer UI
- [ ] Completion reward schema 包含 item kind、pool ID/version、roll count、rarity/tag filters。
- [ ] 先生成 Offer，不改变 progression；选择后 acquire。
- [ ] Stage settlement identity、reward receipt、progression revision 必须幂等。
- [ ] 设计跨 Campaign + Progression aggregate 的持久化事务/恢复协议；未实现前保持未结算状态。
- 完成定义：断电/写盘失败/重复回调不会重复领奖或出现内存幽灵实例。

### Phase G — Protected Target 与 Typed Effects
- [ ] Protected Target Actor 具备生命、伤害、死亡、identity、snapshot/restore；Enemy AI 能按 stage 配置攻击目标。
- [ ] Typed Effect Definition / Executor Registry：至少按 Beam、Projectile、Missile、Shield、SupportUnit、Recon 等独立类型扩展。
- [ ] Effect 仅由 Core order execution success event 驱动；状态持久化与 dispatcher ledger 原子一致。
- 完成定义：每类效果有输入契约、执行器、失败语义、生命周期和状态恢复 Probe。

### Phase H — 集成验证与发布准备
- [ ] Space demo Godot 4.7.1 .NET build、GDScript parse、各 Probe、场景加载和新开/恢复运行时验证。
- [ ] 与 Jar Core PR 的确切 head 对齐；记录 Core head SHA 和 CI run。
- [ ] 更新 PR #2 body、设计文档、剩余风险和人工验收清单。
- 完成定义：明确区分通过的自动验证、未运行验证和人工验收；不提前合并 PR。

## 5. 本轮代码审计观察（2026-11-23）

- `SpaceHangarPreparation` 的生产分支在 `require_owned_instances` 或 progression state 存在时走 `build_owned_loadout_from_selection`；Definition-only path 有显式阻断，方向正确。
- `SpaceHangarOwnedLoadoutAssembler` 以 Owned Instance ID 解析船、解析器、两台工作台、设备和技能，并检查重复 instance；随后调用 definition assembler 生成基础 snapshot，再叠加成长 profile。必须继续检查其余文件段，确认 Master/Slave 和 Skill 的成长后数据确实被写回冻结结果。
- `SpaceHangarBattleLauncher` 的新开与恢复路径都注入 stage settlement callback；`Game.restore_battle_stage_from_checkpoint` 检查 exact stage ID/version 与 frozen loadout identity/fingerprint，`SpaceStageEncounterDirector.restore_state` 也校验 stage version 和 difficulty profile。Protected Target 的 checkpoint 仍未保存 target instance identity，目前仅要求调用方重新提供一个带 Health 的 Node，不能证明它就是原目标。
- `Spawner` 的 boss beat 将 boss 数量固定为 1，不随 encounter scale 复制；普通敌人数才缩放。
- `SpaceStageBossActor.configure_stage_boss` 在入树前缩放 max_hp；`EnemyChaser._ready` 在入树后用该 max_hp 初始化 Health。Boss 重写接触处理，避免普通追击敌机接触即死亡。Probe 已覆盖 1.4 倍 HP 计算，但未运行。
- `SpaceHangarScreen` 的 `_render_view_model` 从 owned inventory 填充选项，飞船/解析器/工作台/设备/技能的选择回调会把对应 `instanceId`（工作台为 Master/Slave 两个 instance ID）传给 SelectionController；因此 UI 已接入 Owned Instance draft，并非单纯 Definition picker。控件文案仍有“定义”旧称，后续可统一。
- Core 模板入口审计：`WorldV2Options` 原先无 `orderTemplates`；`WorldV2ApplicationService.AddJarDemand` 直接从请求需求数组构造 `JarOrderSpecification`；Space `WorldV2ShipHost.MaterializeSelectedOrders` 将 `jarOrder.requirements` 原样转发。现已在 Jar Core PR #60 添加 Core-owned 模板库入口。
- 当前分支没有可见的正式 `data/industrial` catalog 资源目录；只有 sandbox/invalid World V2 JSON。Stage catalog 已单独存在。

## 6. 当前阶段的禁止事项

- 不创建没有真实子系统依据的 parser/workshop/skill power metrics、rarity bands 或生产池。
- 不把五类技能图标/概念 SVG 当作 Jar Core shape vocabulary 已配置。
- 不把 Definition picker 或 catalog entry 当成玩家 Owned Instance。
- 不让 Space 自行检查 Jar Order feasibility/cooldown。
- 不让 B 类工作台流向变成双向，也不扩大 Ban 的作用域。
- 不把 Boss / Protected Target / Typed Effect 的原型或 Probe 源码写成已运行。
- 不合并 PR #2。

## 7. 执行记录

### 2026-11-23 — 基线建立
- 已核对 PR #2 仍为 Draft / Open / 未合并。
- 已核对当前分支目录：`data/industrial` 仅有 sandbox/invalid JSON；`data/stages/campaign_01` 存在关卡资源。
- 已开始审计 Hangar Preparation、Owned Loadout Assembler、Selection Controller、Hangar Screen、Game、Spawner、Boss Actor 与 Launcher。
- 额外确认：Hangar 的“检查并冻结装配快照”按钮目前只构建并显示 fingerprint，不负责启动战斗；MainMenu/Launch 路由仍未闭环。
- 发现并修复：奖励服务曾将 `roguelike` 来源数据塞入 `growth_attributes`，与各子系统 composer 的严格属性白名单冲突。现新增独立 `acquisition_provenance`，RewardService 写入该字段；ProgressionState 导入时会把旧 `growthAttributes.roguelike` 迁移到新字段。
- 已扩展 `SpaceRoguelikeIndividualLibraryProbe`：验证奖励实例的成长属性为空、来源信息单独保存、Skill composer 可以接受该实例、存档 round-trip 保留来源，以及旧格式迁移。Probe 仅已编写，未执行。
- 新增 `SpaceOwnedProgressionInstance.acquisition_provenance`，将奖励来源/池版本/模型版本/稀有度/基础强度/奖励 ID 与子系统 `growth_attributes` 分离；该字段进入持久化和非空 Owned Instance frozen snapshot。
- `SpacePlayerProgressionState.from_data` 兼容旧 `growthAttributes.roguelike`，自动迁移到 `acquisitionProvenance`；若新旧字段冲突则拒绝加载，避免来源歧义。
- `replace_instance_progression` 禁止通过成长更新篡改 acquisition provenance；普通无 provenance 个体不输出空字段，保持既有 frozen snapshot fingerprint 形状。
- `SpaceRoguelikeIndividualLibraryProbe` 新增：奖励实例增长属性隔离、Skill composer 可用性、provenance round-trip、旧存档迁移和 provenance 篡改拒绝。Probe authored，未运行。
- 相关实现提交：`481088c`、`eeae256`、`ae49248`、`693126b`、`500e21d`、`d76e315`、`70229b0`。
- Jar Core Draft PR #60：`world-v2/phase-4.11c-order-template-demand-ingress`。`WorldV2Options` 可选模板配置（null 时不序列化以保持旧配置指纹）、Core `OrderTemplateLibrary` vocabulary validation、`WorldV2Context` 持有不可变模板库、ApplicationService/Bridge 的 `AddJarDemandFromTemplate`，以及模板深拷贝、未知模板拒绝、词表错误和 null entry 测试。PR #60 的 CI run `45197432477` 已对当前 PR head `063e2b7151ea43e92cf6ba1d627b9c7d50819b5b` 完成并成功；PR 仍为 Draft，不合并。
- Core 模板入口的职责：Core 校验并实例化模板；Space 只提供模板键、控制区域、冷却和不透明 orderDefinitionKey，不再传递需求数组。Space skill exact template identity 使用 `template_id@version` 作为 Core template name，另在冻结 binding 中保存 templateId/version/name 三元组。模板要求和实际需求只从所选 WorkshopCombination 的 `jar_world_options.orderTemplates` 解析。
- `SpaceSkillCatalog.resolve_order_template()` 校验模板 exact name、A/B 类型、非空需求、shape/liquid vocabulary、技能主形状严格多数；返回的展开需求只用于 Space 侧生产/难度/强度评估，不写进 runtime `jarOrder`。
- `SpaceBattleLoadoutSnapshot` 拒绝模板订单附带重复 `type` 或 `requirements`，并验证冻结模板身份与 runtime `templateName` 一致；同时仍在冻结 `jarWorldOptions` 中保存 Core 模板原文。
- `SpaceProgressionRuntimeProfileComposer` 在成长后重新计算技能收益曲线时，从冻结 Core world options 按 exact templateName 解析实际需求，避免将仅含 templateName 的 runtime contract 误当成完整需求。
- 新增 `SpaceSkillTemplateContractProbe`，覆盖 exact version、主形状严格多数、词表液体校验、运行时订单不复制需求、legacy inline 与 template 混用拒绝；已接入 `SpaceSkillCatalogProbe`。Probe authored，未在 Godot 执行。
- 本轮 Space 模板接线提交：`161e2f5`、`781d056`、`c8c9e9a`、`bf07be1`、`f189541`、`17bd404`、`00f2d31`、`3bf71e9`、`84dfb10`、`f80e8ac`、`a83a6a2`、`c39da11`、`b4e4c65`、`87bf42a`、`1815aa6`、`f4b19f3`、`04d93cc`、`1e2dfa7`、`c008590`、`00872a4`、`de58577`。
- 本轮补充修正：生产 Hangar bundle 默认拒绝 legacy inline skill requirements；仅当 `allow_legacy_inline_skill_orders_for_probes=true` 时，隔离 Probe 可继续使用旧格式。`SpaceHangarCatalogOwnershipProbe` 已显式开启该标记，生产资源默认关闭。
- `SpaceProgressionRuntimeProfileComposer` 成长后从冻结 `jarWorldOptions.orderTemplates` 重新解析真实 Core 模板，再计算有效技能收益/成本；冻结快照和成长重算都验证 `templateId@version == templateName`，避免身份字段与实际模板错配。
- `SpaceSkillTemplateContractProbe` 已接入 `SpaceSkillCatalogProbe`，覆盖 exact version、主形状多数、液体词表、模板最小 runtime payload、禁止 legacy/template 混搭。
- Core PR #60 verify workflow run `45197432477` 已成功，且 run head 与 PR head 完全一致：`063e2b7151ea43e92cf6ba1d627b9c7d50819b5b`。
- 较早记录的 Space Demo head `d23d1cb...` 已被后续提交更新；当前最新 head 与 ahead/behind 数以本执行记录末尾的最新核对为准。Space Demo Godot/.NET/GDScript 验证仍未执行。
- 本轮 Space 模板接线后续提交：`f4b19f3`、`04d93cc`、`1e2dfa7`、`c008590`、`00872a4`、`de58577`、`baf41ef`、`8274f9c`、`685442e`、`d23d1cb`。
- 本次续接后发现：Skill template resolver 原本从 `combination.jar_world_options` 读取模板，但真正的 Core options 是 `build_jar_world_options()` 生成；这会使 typed catalog 与技能 resolver 脱节。已修复 `SpaceHangarCatalogBundleResource`：每个可选世界先通过组合定义完整校验，再物化 World V2 options，之后才解析技能 exact template。
- 新增 `SpaceCoreOrderTemplateDefinition.gd`：用独立 Resource 表达 `template_id + version + A/B type + requirements`；模板名固定为 `id@version`。需求列表逐项映射 Core 的 shape/liquid，不允许自造 count 语义。
- `SpaceWorkshopCombinationDefinition` 新增 typed `core_order_templates`，由 `build_jar_world_options()` 生成 Core `orderTemplates`；原始 `jar_world_options` 禁止再塞入非类型化的 `orderTemplates`，避免双重来源。
- `SpaceWorkshopCombinationCatalog` 对模板资源做深拷贝；变更原始模板或解析副本不会污染已注册的 catalog。
- Space authoring 校验与 Core 保持一致：模板 exact name 唯一、A/B 类型、shape/liquid 属于当前 World vocab、需求不超过 Core 上限 10、空罐需求必须排在满罐需求之前，且只允许 shape/liquid 字段。
- 扩展 `SpaceHangarCatalogOwnershipProbe`：模板深拷贝、World options 物化、skill exact template resolve、运行时 `jarOrder` 只携带 templateName、不重复携带 type/requirements、无效 shape、空罐/满罐顺序错误和超 10 条需求均有断言；另验证生产 Hangar bundle 使用物化后的 Core template catalog。
- 上述 Probe 仅已编写，未在 Godot 执行；Space Demo 没有对应 CI run，不能标为通过。
- 本次新增提交：`d8829bb`、`325be82`、`0fdcd38`、`0bea5f3`、`804ac33`、`270972d`、`66756fc`、`a348227`、`455e418`、`6eb3741`、`671b94b`。
- 当前 Space PR #2 head：`671b94b18c440e3f6b24c23a95ebdccf17bf3126`；compare main...branch ahead 581 / behind 0。PR 仍 Draft/Open/未合并。
- 仍未录入真实生产 workshop combination / skill resources；本轮建立的是可验证的类型化 authoring contract，不创建虚构技能配方或平衡数值。
- Phase B 开始执行：检查发现通用模型只有 `higherIsBetter` 方向，无法表达工作台容量/规则的“有目标值而非越大越好”；而且任何结构有效模型都能进入生产 Pool，`unconfigured` 没有硬门禁。
- `SpaceIndividualPowerModelDefinition` 新增 `configuration_status`（默认 `unconfigured`）和生产校验入口 `get_production_validation_errors()`。普通 evaluator 可用于隔离调试/调参；Production Pool 必须引用显式标记 `configured` 且每个维度显式声明 scoringMode 的模型。
- 新增 `target_value` scoringMode 与 `targetValue`：目标值记满分，目标值两侧分别线性衰减至各自边界的 0 分；因此上下界不对称时也不会把“容量过大”误当成仍然接近最优。
- 生产 Workshop power model 的 `max_jars`、`max_liquids`、`liquid_staging_capacity` 必须使用 `target_value`；每种 shape 的 base/additional mark、每种 liquid 的 Ban 和 Core staging fallback 也必须使用 workload-target 语义，避免把更多 Mark/Ban/容量机械当成更强。
- `SpaceIndividualPowerEvaluator.evaluate_workshop()` 不再只输出 mark/ban 数量，而是输出 `base_mark.<shape>`、`additional_mark.<shape>`、`ban.<liquid>` 的逐项原始指标，保留不同规则作用对象的身份。-1 staging fallback 仍按 0 显式容量 + 独立 fallback flag 处理。
- `SpaceRoguelikeIndividualPool.get_validation_errors()` 改为调用模型的生产校验门禁；未配置模型不能被生产 Pool 引用，即使 metrics/score 在结构上可计算也不行。
- 扩展 `SpaceIndividualPowerEvaluatorProbe` 与 `SpaceRoguelikeIndividualLibraryProbe`：合成模型显式配置 scoringMode；覆盖目标值评分、非对称边界两侧归零、未配置模型被 Pool 拒绝、Workshop 容量禁止单调高分、逐 shape/逐 liquid 指标和成长后重新评估。Probe 仅已编写，未运行。
- 注意：这还不是生产 power model。没有擅自确定 Parser / Workshop / Skill 的正式指标权重、边界、目标工作负载或稀有度区间；所有真实模型仍需在有真实设计数据后从 `unconfigured` 变为 `configured`。
- 本轮 power contract 新增提交：`0b07db6`、`c14562b`、`aa69080`、`96e3110`、`4623252`、`e1da0bd`、`611f930`、`d223cfa`、`d9f087c`、`8f84725`、`ca112f8`、`bf80d28`。
- 新增 `SpaceIndividualPowerEvaluator.evaluate_effective_skill()`：按精确 Owned Instance 合成技能成长，重新解析冻结 World options 中的 Core 模板，再由 `SpaceProgressionRuntimeProfileComposer.compose_skill_binding()` 重新计算收益/Jar 成本；若成长导致技能 undercosted，则拒绝生成 effective power score。该路径与 Parser/Workshop 的 effective evaluator 一起覆盖三类实例成长后的重评估入口。
- Parser 指标边界审计：`SpaceOreParserRuntime` 的输入是有限体积 energy stone，按 parser 的 per-shape processing rate / production percentage 消耗体积，再按 progress-per-Jar 产出；`SpaceEnergyStoneDropProfile` 单独拥有 drop chance 与各 stone volume 分布。当前 parser power evaluator 已能算有效处理速率、每形状吞吐量和每 Jar 进度成本，但没有绑定参考掉落供给分布，因此不能把“每颗石头可维持多久”伪装成 Parser 固有属性。后续必须明确是用 exact drop profile 作为评估上下文，还是将其作为 encounter economy 指标；未确定前 Parser 生产模型保持 unconfigured。

- `SpaceIndividualPowerEvaluatorProbe` 增加 template-backed Skill 的 neutral instance 成功与过度成长被 cost curve 拒绝检查；Probe authored，未运行。
- effective-skill evaluator 提交：`b34980d`、`cefe838`。

- 当前剩余：在真实 WorkshopCombination 配置中录入 versioned Core orderTemplates，并迁移生产 skill definitions；继续核对 MainMenu / Hangar launch route、Protected Target identity 和真实子系统 power metric 契约。

- 最新续接核对（文档提交前）：Space Demo PR #2 head `235e3a88e5ef778dc55d5959d058363e0003de4f`，ahead 597 / behind 0，Draft/Open/未合并；文档本次提交将继续更新 head。Jar Core PR #60 head `063e2b7151ea43e92cf6ba1d627b9c7d50819b5b`，verify run `45197432477` completed/success。Space Demo 仍无 Godot/.NET/GDScript 运行验证。


## 8. 本轮续接 — Parser encounter supply context 与 Owned Hangar 冻结审计

- 新增 SpaceParserSupplyEvaluationContext：明确把 exact SpaceEnergyStoneDropProfile（掉落概率、各形状石头体积分布）与 encounter expected enemy defeats/sec（遭遇侧击杀节奏）作为显式评估上下文；二者均不是 Parser Definition 固有属性。
- 新增 SpaceIndividualPowerEvaluator.evaluate_parser_in_encounter()：在原有 Parser intrinsic metrics 上，按 shape 计算 conditional mean stone volume、每敌人期望供给体积、每秒期望供给体积，以及每颗对应石头按该 Parser 有效处理速率可维持的秒数。报告同时冻结 drop profile exact ID/version 与 encounter defeat rate。
- 供给量按 drop chance × 该 shape 的加权平均体积 × encounter defeat rate 计算；每颗石头维持时间使用条件平均体积 / Parser effective processing rate。不存在供给的 shape 返回零值；若供给配置包含某 shape 但 Parser 有效处理速率为零，则拒绝评分，不把无限维持时间伪装成强度。
- 新增 synthetic Probe 覆盖多 shape 权重、drop chance、每秒击杀率、石头维持时间、exact profile provenance 与非法 encounter rate 拒绝。Probe authored，未执行。
- 该 API 仍不配置任何生产 Parser power model：模型必须显式包含 encounter metrics 的确切维度，真实范围、方向、权重和 encounter forecast 必须由正式关卡/敌人掉落数据决定；未确定前 Parser production pool 继续保持 unconfigured。
- Owned assembler 审计确认：Ship、Parser、Master/Slave 两个不同 Workshop、Device、Skill 均按 Owned Instance ID 解析；各子系统成长 profile 被写回 snapshot；技能成长后重新基于冻结 jarWorldOptions.orderTemplates 计算收益与 Core 成本；快照的 ownedInstanceSnapshots 与槽位引用做集合一致性校验。Workshop pair 角色来自 exact combination pair definition，不从实例成长数据推断。
- 下一项审计点：Workshop power evaluator 目前只接收单个 Workshop Definition + local rules，没有 role/真实工作负载结果输入；因此不能仅凭容量/Mark/Ban 给 Master 或 Slave 实例打生产强度分。后续需建立角色/工作负载评估上下文，或将组合协同强度独立归属 pair model，不能混入 Workshop 个体固有属性。
- 本轮未创建正式 Parser/Workshop/Skill power model、权重、范围、rarity band、production pool 或虚构 drop profile。Space Demo Godot/.NET/GDScript 验证仍未执行。

- 计算修正：Encounter evaluator 先在临时 intrinsic-only model 上验证基础 Parser 指标，再将 supply-context 维度并入完整模型评分，避免模型包含供给维度时被提前的精确维度数量检查拒绝。
- 边界修正：drop chance 为 0 且无 weighted stone entries 是合法的“无掉落遭遇”，所有供给量/维持时间输出 0；若 drop chance 大于 0 却无正权重供给则拒绝。Probe 已加入零掉落和无效击杀速率覆盖，仍未运行。
- 本轮最新 GitHub 核对（执行文档更新前）：PR #2 head `197d6ec3ee7d35dce1592841a909cb5eba529abb`；执行文档更新后 head 为 `5df294dc9001ab82f9eef69a21da93255eb4b859`，compare main...branch ahead 613 / behind 0。PR 仍 Draft/Open/未合并。Space Demo Godot 4.7.1 .NET、GDScript parse 与 runtime Probe 均未执行。


## 9. 修正工作区装配语义 — 独立元件与可配置位置（2026-11-23）

- 纠正旧的固定配对设计：SpaceWorkshopCombinationDefinition 现在是 World V2 规则配置 + 可用工作台 Definition roster；workshop_pair 降为仅供旧 definition-only 开发 fixture 兼容的可选提示，不再是生产 Owned Instance 选择约束。
- World roster 不再要求恰好两个 Definition；允许一个或多个工作台元件定义。每次生产装配必须从玩家拥有的工作台实例中选出两个不同 instance ID，分别放入 Master / Slave 位置。两个实例可以来自同一个 Definition（例如同一元件的两份独立个体），成长数据仍各自独立。
- Core World V2 options 只物化当前选中的两个位置，并用角色后缀生成唯一工作台名；角色属于位置，不写回 Definition，不修改 Owned Instance 身份。Master / Slave 的实际资源方向与执行规则仍完全由 Jar Core 执行。
- Owned inventory 不再只暴露预先配好的 Master/Slave 组合：分别输出 World profile choices 和独立 workshop instance choices。Hangar UI 改为独立选择 World 规则配置、主台位置元件、从台位置元件；重复选择同一 instance 被拒绝。
- SpaceHangarOwnedLoadoutAssembler 依据两个精确 Owned Instance 的 definition ID/version 查找各自规则，分别合成其成长属性，再按所处位置写入 Core World options，并冻结两个独立 instance snapshots。不会把角色绑定到 Definition。
- SpaceWorkshopSlotSelectionProbe 覆盖角色交换、同一 Definition 的两个不同 Owned copies 可分别占据两个位置、无固定 pair 的 roster，以及 Core role name uniqueness。SpaceHangarCatalogOwnershipProbe 已改为检查独立 World / instance inventory 与角色交换。
- 为模板和目录验证场景，只有一个 workshop Definition 的 World 也可使用该 Definition 临时物化两个空白验证位置；生产 Owned assembler 仍必须显式提供两个真实且不同的 Owned Instance IDs。
- 本轮不再建立 Workshop role power model；角色是工作区位置，不是个体属性。订单区和分解区将按相同的 Definition / Owned Instance / Board Slot 分离原则继续统一。
- Space Demo Godot/GDScript/.NET 验证仍未执行；本轮所有 Probe 均为 authored-only。


## 10. 工作区装配语义复审与 Board/runtime 边界纠正（2026-11-24）

### 已确认的正确领域模型
- 工作台、分解器、订单/技能、生产设备都是独立元件 Definition；玩家持有的是各自独立的 Owned Instance，成长数据只属于具体实例。
- Board Slot 表示工作区上的位置/插槽。槽位决定元件当前所在区域及其角色；元件 Definition 不固化主台/从台身份。
- 玩家可以把同类别的不同元件实例安装到不同槽位；同 Definition 的不同 Owned Instance 也可分别安装，不能因为 Definition 相同而合并成长状态。
- 主台/从台是当前 World V2 工作台区的两个角色位置，不是固定 WorkshopPair 资产。Core 继续拥有实际单向资源流和执行语义。
- 订单区与分解区必须沿用同样的 Definition / Owned Instance / Slot Assignment 分离，不可保留“技能绑定数组”和“单 Parser 字段”作为永久领域模型。

### 当前代码审计结论
- `SpaceHangarBoardDefinition` / `SpaceHangarBoardSlotDefinition` 已表达槽位位置，但此前 Board validation 把恰好一个主台、一个从台、一个 Parser 写成 Board 本身的结构规则；这是把当前 runtime 限制错误地提升为 Board 领域规则。
- `SpaceHangarScreen` 仍然维护专用 Parser、Master、Slave picker；`SpaceHangarSelectionDraft` 仍以 parser/master/slave 专用字段和 deviceSelections/skillSelections 两个平行数组表达选择。Board Slot 还没有成为统一 assignment 数据源。
- `SpaceHangarOwnedLoadoutAssembler` 仍接收专用 `parserInstanceId`、`masterWorkshopInstanceId`、`slaveWorkshopInstanceId` 字段；它会正确冻结当前两个工作台 Owned Instance 的独立成长，但尚未遍历统一 Board assignment。
- `SpaceBattleLoadoutSnapshot` 当前仍要求单个 Parser slot，并将 Parser 物化为生产设备数组中的一个设备；多个 Parser 的资源输入、处理调度、产出归属尚未定义。因此不能把多个 Parser 槽位展示成已支持的可运行功能。
- 生产设备和技能可有多个槽位；当前 adapter 已将它们投影为设备槽位数组和订单 binding 数组。该实现可作为迁移适配层，不应继续成为 Board 的主数据模型。
- MainMenu Start 已转入 Hangar；Hangar 的“装配并进入战斗”按钮会冻结 Owned loadout、附加 Board snapshot，并调用 `SpaceHangarBattleLauncher.launch_new_battle`。所以“启动路由完全未接通”的旧描述已经过时。真实生产 catalog/owned inventory 和端到端实测仍是阻塞项。
- `SpaceHangarLoadoutAssembler` 的 Definition-only 路径仍存在；Preparation 默认 `require_owned_instances=true`，生产入口会拒绝 definition-only，但旧路径仍被隔离开发/Probe 使用。删除前必须查明所有调用方并迁移 Probe，不能按文件名直接清理。
- 目前 Board frozen snapshot 只冻结槽位定义，不包含一个统一的 `slotId -> ownedInstanceId` assignment map；实例身份分散保存在旧 selection / subsystem snapshot 字段中。

### 本轮已提交的纠正
- `SpaceHangarBoardDefinition.get_validation_errors()` 现在只验证 Board 本身：版本身份、非空槽位、槽位结构、唯一 slot ID；不再把 Core 当前只能执行两个工作台角色和单 Parser 的限制当作 Board 的定义约束。
- 新增 `get_runtime_projection_errors()`，单独表达当前 World V2 adapter 的执行边界：必须恰好一个 Master、一个 Slave、一个 Parser。多 Parser 会明确拒绝投影，不会再被旧字段静默覆盖。
- `build_hangar_configuration()` 在结构无效或 runtime projection 不支持时返回空配置，避免错误装配。
- 新增 `get_slots_for_area()` 和 `build_slot_index()`，让 UI/控制器能按区域遍历槽位，而不必复制固定字段。
- 扩展 `SpaceHangarBoardDefinitionProbe`：验证多个订单槽和生产槽可共存；多个 Parser 虽是结构合法 Board，但当前 runtime projection 明确拒绝；重复 slot ID 仍然被结构校验拒绝。
- 提醒：Probe 仅写入，未在 Godot 执行；这是领域/适配层纠正，不代表已完成通用 Owned Slot Assignment 或多 Parser runtime。

### 下一步执行顺序（不得倒退）
1. 引入统一的 Board Assignment 数据模型：`slotId + exact itemKind + ownedInstanceId + exact definitionId/version`。assignment 必须检查 Board Slot 的 componentKind、Owned Instance 类型、重复 instance、必填槽位和空槽规则。
2. 将 Hangar Draft / Controller / Screen 的选择行为迁移到统一的 slot assignment API。UI 按 Board area 分区渲染；主从位置只影响工作台 role projection，不写回实例 Definition/成长。
3. Owned assembler 从 assignment map 解析实例，并将 assignment map 与所有 Owned Instance frozen snapshots 一起写入 loadout fingerprint。旧 subsystem fields 仅作为 World V2 runtime adapter 的投影结果。
4. 先保持单 Parser runtime gate；只有在定义多个 Parser 的输入分配、调度、能量石消耗、产出归属和失败处理后，才扩展 Parser 数量。不能只改 Board 限制。
5. 为订单区建立多个 slot 的稳定 key/ControlArea 绑定，继续由 Core 创建模板需求、执行 feasibility/cooldown/passive scheduling。
6. 建立生产可运行的 versioned catalog + 初始 Owned Inventory，完成 Hangar → Battle → Stage Settlement → Reward Acquisition → Save/Reload 的完整循环。
7. 最后按调用图清理 Definition-only assembler、过期 Pair 资源、旧文档和无引用文件。每个删除都必须先证明无运行时/Probe/资源引用。

### 当前禁止事项
- 不要把 Board 定义成只能有 1 Master + 1 Slave + 1 Parser 的固定结构。
- 不要声称通用 Slot Assignment 已完成；当前只有槽位定义与旧专用选择字段。
- 不要声称多 Parser 已支持；当前 adapter 明确限制为一个 Parser。
- 不要恢复 WorkshopPair 作为固定玩家选择配方。
- 不要因为“垃圾文件清理”而删除尚被 Probe、Resource 或 scene 引用的 Definition-only 路径。



## 11. Jar World 电路板式规则世界审查与修正指导（2026-11-24）

### 领域模型重新定锚
- Jar World 是由规则构成、可安装和替换零件的规则电路板；Board Slot 是安装位置，Board Assignment 是玩家当前安装关系。
- 零件实例通过 exact Definition/version 与 Owned Instance 成长快照解析出 Rule Contributions；安装后的贡献组合成不可变 Effective Rule Profile。
- Jar 与液体是规则世界中的流动资源状态，不是规则本身；Jar 内液体、工作台游离液体、订单暂存、主台预置液、自机液库等必须独立记账。
- 订单只提供最终 Jar 目标与业务阶段语义；不得预先指定主从台、物理 Jar、操作步骤或液体路径。
- 求解器读取 Effective Rule Profile + 订单目标 + 世界事实，推导结构解；当前资源状态只负责绑定和 Readiness，随后进入原子 Admission、Execution 与 Settlement。

### 跨仓库审查结论
- Jar Core 当前已有 WorkshopCapability、RuleContext、WorkshopRulebook、符号候选、A/B 分支、资源模拟、物理 Jar 绑定、Manifest、Lease、Execution Session 等重要基础；不是需要推倒重写的状态。
- 当前 WorkshopRulebook 已统一四种基础 Jar 算子与 MATCH 的判定/纯转换入口，但规则目录仍以 Core 固定 enum/switch 为中心，不是玩家安装零件动态贡献规则的完整插件/组合系统。
- WorldOrderRuleCandidateProfile 已从订单目标和工作台规则上下文构造候选，但候选构造仍围绕固定基础算子/词表；A/B 分支是明确领域策略，不是通用任意规则贡献搜索器。
- Core WorkshopRoster 支持工作台实例集合与 Master/Slave 岗位分离；WorkshopReplacementProcess 仍是主从岗位专用替换过程，不等于任意 Board Slot Assignment 替换。
- Space Board 目前仍主要投影为 Parser/Master/Slave/Device/Skill 专用 selection 字段；统一 Board Assignment 尚未完成，也未将完整安装贡献装配成 Jar Core Effective Rule Profile。
- 因此整体判定为“部分符合，尚未达到电路板式可组合规则世界”。不能仅凭存在 Board、Rulebook、Owned Instance 和 Solver 类就宣称完整模型已经实现。

### 正式修正指导
- Jar Core 已新增正式文档：[`circuit-board-rule-world-audit-and-correction-guide.md`](https://github.com/Lazyair150/jar-system-dotnet/blob/world-v2/phase-4.11c-order-template-demand-ingress/docs/world-v2/circuit-board-rule-world-audit-and-correction-guide.md)。
- 该文档定义 Rule Contribution、Effective Rule Profile、SolveProblem、SymbolicSolutionSet、ResourceBinding/Readiness、Admission/Execution/Settlement 的契约；列出当前偏差、迁移顺序和 16 项验收场景。
- 下一步顺序固定为：统一 Space Board Assignment → Core Rule Contribution Contract → Effective Rule Profile 装配 → Solver 消费统一规则接口 → 资源 Readiness/Admission/Execution 对齐 → 通用槽位替换与岗位投影 → 依赖图清理。
- 先保留现有规则评估、资源分账、符号求解、物理绑定、Lease/Checkpoint/Journal 等真实边界；以旧实现作差分 oracle，分阶段迁移，不做无证据的大规模推倒重写。
- 任何新零件不应要求 Solver 新增专属 if/switch 才能贡献规则语义；订单模板不得携带预制生产路径；临时规则必须版本化并有明确安装/卸载/到期边界。

### 状态与验证
- Jar Core 文档已提交至 PR #60 分支 `world-v2/phase-4.11c-order-template-demand-ingress`，提交：`4bf7ba67662b4e214c81b85063bb3da6d28cc2e7`。
- Space Demo 本节只记录跨仓库审查结论与执行约束，不表示 Rule Contribution 或统一 Board Assignment 已经实现。
- 本次为源码静态审查；没有运行 .NET/Godot/GDScript/Probe。PR #2 仍保持 Draft/Open，不合并。


## 12. 第一轮电路板装配实现（2026-11-24）

### 已提交实现
- 新增 `SpaceHangarBoardAssignment.gd`：玩家的槽位安装关系独立于 Board Definition，精确记录 `slotId / componentKind / ownedInstanceId / definitionId / definitionVersion`。
- Assignment 校验覆盖未知槽位、槽位类别不兼容、实例不属于玩家库存、Definition/version 不匹配、同一 Owned Instance 重复安装、必需槽空缺。
- 新增规范化 Assignment snapshot：包含 Board Definition 冻结数据、排序后的 assignment entries 和 SHA-256 assignment fingerprint。
- `SpaceHangarSelectionDraft` 已将 Assignment Map 作为 Parser、主/从工作台、生产设备和技能的主数据源。旧 `parserInstanceId/masterWorkshopInstanceId/slaveWorkshopInstanceId/deviceSelections/skillSelections` 均由 Assignment Map 生成，作为旧 Runtime Projection。
- 原有 Picker 选择接口暂时保留，但所有元件安装/替换操作都通过统一 `_assign` 入口执行。Controller 新增通用 `assign_instance`、`unassign_slot`、`get_assignment` 与 `validate_assignments`。
- Hangar Screen 初始化 Controller 时传入 Board Definition；冻结生产 Owned Loadout 前强制验证 required slots。
- `SpaceHangarOwnedLoadoutAssembler` 重新检查 Assignment snapshot 中的 exact Board Slot、Owned Instance、Definition/version 和 runtime projection 身份一致性，并将 Assignment snapshot 放入 Loadout fingerprint。
- `SpaceBattleLoadoutSnapshot` 验证 Assignment snapshot 的 Board identity、required slot、component kind、重复 slot/instance、内容 fingerprint，并要求其 Board Definition 与 `assemblyBoard` 一致。
- `SpaceHangarBoardDefinitionProbe` 新增 Assignment exact ownership、同 Definition 不同 Owned copies、重复实例、错误类别与顺序无关 fingerprint 场景。

### 当前边界
- 目前 Board Assignment 已成为 Draft 的元件选择主数据源，但 Hangar UI 还没有完成完全通用的 Board Slot 动态面板；现有 Picker 仍按 Parser、Master/Slave、Device、Skill 分类显示。
- 主台/从台与单 Parser 仍由当前 Runtime Projection 限制；Board Definition 不再承担这些运行时数量限制。
- Assignment snapshot 进入 Space Loadout，但每个 Owned Instance 尚未携带其可序列化 Rule Contribution Definition；跨仓库 Rule Contribution 精确来源还需下一轮打通。
- 本轮不宣称多 Parser 可运行，也不清理仍被引用的旧 Runtime Projection 字段。

### 验证
- 本轮新增/修改的 GDScript Probe 仅为 authored；未运行 Godot、GDScript parser、.NET 集成或 runtime Probe。


### 2026-11-24 实施补充
- 通用 Assignment 编辑入口现已在 Draft 内检查工作台实例与当前选中 World 规则配置的兼容性；通过通用 `assign_instance` 替换主/从工作台时，不会绕过原有 World compatibility 约束。
- 修正 Board Definition Probe 的 demo slot count：demo Board 实际定义 5 个槽位，Probe 现在按 5 验证。
- Loadout freeze 的完整性检查现在同时阻止 required slot 缺失，并将运行时投影身份集合与 Assignment Map 精确对照。


## 13. 已安装零件的声明式 Rule Contribution 来源（2026-11-24）

- 新增 `SpaceRuleContributionDefinition`：组件 Definition 可声明稳定 RuleId/version、Effect、Target、Scope、Priority、常量参数，以及参数到 Owned Instance 成长属性的显式绑定。
- Workshop、Ore Parser、Production Device、Skill Definition 均可声明 `rule_contributions`；这些规则声明仍是纯数据，不允许闭包或任意可执行脚本。
- 新增 `SpaceRuleContributionResolver`：按 Board Assignment 逐槽位解析 exact catalog Definition + exact Owned Instance，生成来源包含 Definition/version、Owned Instance ID、progression revision、slot ID 的贡献记录。
- Workshop 现有 base_marks / additional_marks / banned_liquids 被保留为兼容基础能力，同时转换成同一 Rule Contribution 数据格式；容量仍属于 capability/runtime projection，不伪装成规则算子。
- Resolver 会拒绝实例重复、Definition/version 不匹配、缺少成长参数、重复贡献身份；贡献按槽位与 RuleId 规范化排序并计算独立 fingerprint。
- Owned Loadout Assembler 已将解析后的 `boardRuleProfile` 冻结进 Loadout Snapshot；Snapshot 验证 Profile fingerprint、Board/Assignment fingerprint、贡献来源实例和 Definition 必须与对应槽位一致。
- Probe 新增成长属性绑定、progression revision 和缺失成长属性拒绝场景。

### 当前重要边界
- `boardRuleProfile` 已从 Space Owned Assignment 解析并冻结，但本轮尚未把它送入 Jar Core WorldV2Options/WorkshopSolveSnapshot 的正式输入协议；当前 Core 仍通过旧 WorkshopCapability/ModifierStack 适配器生成 legacy Profile。
- 因此跨仓库的精确 Owned Instance → Rule Contribution → Effective Rule Profile 链目前完成了 Space 侧的生产与快照，尚未完成 Core 侧消费。下一步应扩展 WorldV2Bridge 的显式版本化输入契约，让 Core 校验贡献来源与 Board Assignment，并按 workshop/skill/parser/device 等 scope 合成真正的 Board Effective Rule Profile。
- 任何尚无执行器的 Effect 只能保留为明确的 Undetermined，不可被忽略，也不可直接变成“可行”。
- 本轮没有运行 Godot / GDScript Probe；不宣称 Probe 已通过。


## 14. Board Rule Profile 已接入 Core ingress（2026-11-24）

### 已提交的跨仓库连接

- SpaceHangarOwnedInventoryBuilder 将每个 Owned Instance 的 progressionRevision 暴露给装配选择数据。
- SpaceHangarBoardAssignment 将 sourceRevision 与 slot、Owned Instance、Definition/version 一起冻结；验证时会重新对照玩家库存中的实例 revision。
- SpaceRuleContributionResolver 产出的每条 contribution source revision 必须与对应 Board Assignment revision 一致。
- SpaceBattleLoadoutSnapshot 同时验证 Assignment revision 对应 ownedInstanceSnapshots、Contribution revision 对应 Assignment，并验证 Board Profile fingerprint。
- SpaceHangarOwnedLoadoutAssembler 把完全相同的 boardRuleProfile 和 boardAssignmentSnapshot 放进根 Loadout 与 jarWorldOptions。Profile hash payload 保持不变；Assignment Snapshot 作为独立字段传输。
- 每个 Core workshop option 额外携带 boardSlotId，由 Board Assignment 的 roleId=master/slave 精确确定；不是由 Workshop Definition 固定主从身份。

### Core 当前接收边界

- Jar Core WorldV2Options 已新增版本化 boardRuleProfile / boardAssignmentSnapshot DTO；校验两份 SHA-256、Board identity、required slots、slot kind、Owned Instance、Definition/version 和 progression revision。
- WorldV2Factory 按 workshop Board Slot 创建独立 Effective Rule Context；Master 与 Slave 的规则贡献隔离，执行与求解快照共用同一 Profile。
- 当前只接受 scope=workshop 且来源为 workshop Board Slot 的贡献。Parser、Skill、Production Device 的规则 scope 还没有 Core 消费者，当前会明确拒绝；不能把“数据已传入”误报为“所有元件规则都已生效”。
- 当前只接受 RuleVersion 1；未实现的 RequireCondition / ModifyCapacity 保持 Undetermined。多 Parser runtime 仍未实现。

### 当前验证状态

- Core PR #60 最新提交已加入上述 DTO、Factory、RuleContext、Snapshot 与差分测试；CI 尚待本轮运行结果，不预先宣称通过。
- Space PR #2 已更新 Assignment progression revision、Core option ingress 和 root/options 一致性检查。
- GDScript Probe 代码已更新，但未执行 Godot、GDScript parser 或 runtime Probe。PR #2 仍为 Draft/Open，不合并。


### 14.1 Core 验证状态更正（2026-11-24）

- Core Actions run 45224300866 对应提交 52c2537，主项目与 Godot Host build 阶段通过；新增工厂测试因两处 nullable Rules 访问导致测试项目编译失败，xUnit 未执行。
- Core 后续提交 4808ea4 已修正两处可空访问，但修复提交尚无新的 Actions run。不得把该轮标记为通过。
- Space 的 GDScript Probe 仍未执行；PR #2 保持 Draft/Open。

### 14.2 Hangar Board 动态槽位安装面板（2026-11-24）

- Board 模式下，Hangar 不再把 Parser、Master/Slave、Device、Skill 的旧专用 Picker 作为玩家安装入口；改为遍历 Board Definition 的 Slots 动态创建槽位面板。
- 每个槽位按 `componentKind` 从 Owned Inventory 取实例：workshop / parser / skill / production device。显示 Definition 版本、Owned Instance、等级；同 Definition 的不同 Owned Instance 保持独立选项。
- 选择实例调用 Controller `assign_instance(slotId, ownedInstanceId)`；选择未安装项调用 `unassign_slot(slotId)`。重复实例、错误类别、成长 revision 不一致和工作台 World compatibility 仍由 Draft/Assignment 校验拒绝。
- 工作台 World rules profile Picker 保留为独立选择；改变 World 时保留当前主/从槽位安装实例，并由 Draft 重新验证兼容性。主/从角色来自 Board Slot，不来自工作台 Definition。
- Skill controlArea 修正为来自 Board Slot Definition，不再从 Owned Choice 中猜测。
- `SpaceHangarBoardDefinitionProbe` 增加通用 Draft 安装路径：通过 assign_instance 安装两台工作台、解析器、Active/Passive 技能，并检查完整 Assignment Snapshot；另增加 Skill Slot controlArea 检查。
- 旧 Picker 仅保留给无 Board Definition 的显式迁移兼容场景；Board 模式的隐藏兼容投影仍供当前 Core runtime adapter 使用，不是独立数据源。

### 当前验证边界

- 本轮仅提交 GDScript 与 Probe 代码；未运行 Godot、GDScript parser 或 Probe。Space PR #2 最新 head 为 `0fa247b49d5fb53b84af647084eef01542013cb4`，仍 Draft/Open。
- Core PR #60 最新 head `fda4a40` 的 Actions run `45224859217` 已通过；不代表 Space GDScript 已验证。
- 多 Parser、额外组件 kind 的 Core runtime 执行器、Skill/Parser/Device scope 的 Rule Contribution 消费仍未完成。


### 14.3 安装替换与 World 兼容性保护补充（2026-11-24）

- Board 模式下动态槽位 OptionButton 的首项代表未安装；选择已有 Owned Instance 即替换该槽位，选择首项即卸下。所有操作仍走 `assign_instance` / `unassign_slot`，不在 UI 侧直接改 Assignment Map。
- World Profile 改变时，如果当前 Master/Slave Owned Instance 不兼容，新 World 选择现在会被拒绝，不再把不兼容实例静默清空。原 Assignment 保留。
- Probe 增加 World A 安装两个工作台、切换到不兼容 World B 必须失败且两份 Owned Instance 仍保留的场景。
- Probe 还增加完整 Board 上通过通用 `assign_instance` 安装工作台、Parser、Active/Passive Skill 的路径，并校验冻结 Assignment Snapshot 的五个槽位。
- 上述 Probe 仍未在 Godot 中执行；属于已写入的自动验收代码，不代表运行通过。

- 动态槽位面板现按 Board Slot 的 areaId 分组展示工作区、分解区、订单区和生产区；旧选择投影路径也必须与 Skill Slot 的 controlArea 完全一致，不再覆盖或猜测槽位属性。

- Board 动态面板按 areaId 分组；Hangar 状态栏会直接显示未安装的 required Slot 和被拒绝的选择原因，避免无反馈的静默失败。


## 15. Parser Owned Instance identity correction and runtime boundary audit (2026-11-24)

### Implemented in this increment
- Confirmed the existing parser is a Space-owned finite-input runtime, not a missing Core time-driven Producer. It consumes acquired energy-stone volume per configured shape, retains queues/progress/remainders, emits pending whole-Jar batches, and imports them through Core's discrete central-warehouse API.
- Fixed the production battle initializer's parser runtime identity. It now derives the battle-scoped identity from the exact frozen parser Owned Instance ID, after checking `itemKind=ore_parser` and exact Definition ID/version. It no longer uses only the shared parser Definition ID.
- Preserved an explicit Definition-only identity fallback for isolated development fixtures. Production Hangar remains on the Owned Instance path.
- Extended `SpaceOreParserRuntimeProbe` to cover two copies of one Definition resolving to different runtime IDs, rejection of mismatched Owned Instance provenance, and the stable Definition-only fallback.
- Added the Core-side contract `docs/world-v2/parser-board-slot-runtime-boundary.md` and updated Space's ability/rule-scope document with the same ownership boundary.

### Confirmed architecture
- Space owns energy-stone pickups, finite input queues, parser throughput/progress, parser checkpoint state, and pending output batches.
- Jar Core owns the discrete `ImportProducedJars` admission, central warehouse, warehouse capacity/overflow, durable operation-ID deduplication, and all downstream Jar/workshop/order behavior.
- Parser processing and Jar advancement use the same Host-authorized whole-millisecond delta. Parser imports before Jar advances that same step.
- Parser output must never be injected directly into Master/Slave.
- Core Board Rule Profile currently has a workshop-scope consumer only. Parser/Skill/Production Device contributions remain rejected until Space splits profiles by their actual consumers; they must not be ignored or mixed into workshop scope.
- Multi-parser runtime remains unimplemented. Deterministic pickup routing, per-instance queues/outboxes/checkpoints, update ordering, and settlement must exist before relaxing the single-parser runtime projection.

### Validation boundary
- Code and Probe changes are committed to the Space development branch; the Probe is authored, not executed. Godot 4.7.1 is not available in this environment.
- Core PR #60 latest known verification run `45225916923` completed successfully, including its `verify` job.
- PR #2 and PR #60 remain Draft/Open and are not merged.


- Follow-up hardening: parser identity derivation accepts the old `shipWorldId:parserDefinitionId` only when the restored checkpoint carries that exact legacy identity. This preserves pending operation IDs across an ambiguous Core import receipt; new battles still use exact Owned Instance IDs. The Probe covers legacy namespace preservation and cross-copy checkpoint rejection.

- Follow-up: `SpaceRuleContributionResolver` now fails loadout assembly immediately when Parser/Skill/Production Device contributions are authored for the Core-facing profile, or when a contribution resolves outside `scope=workshop`. Unsupported scopes no longer travel to the battle's Core ingress only to fail later.


## 16. Consumer-routed Board runtime profile set (2026-11-24)

- Added `SpaceBoardRuntimeProfileSet.gd`: every frozen Board Assignment is routed to `jar_core.workshop`, `space.parser`, `space.skill`, or `space.production_device` with exact slot/Owned Instance/Definition/version/progression provenance and a fingerprint of its actual composed runtime profile.
- `SpaceHangarOwnedLoadoutAssembler` creates the set only after all consumer runtime profiles have been composed.
- `SpaceBattleLoadoutSnapshot` rebuilds and validates the manifest against the frozen workshop, parser, skill, and device profiles. Missing or tampered profile bindings reject the loadout.
- The manifest is a routing/identity contract, not a generic rule executor. Core ingress remains workshop-only; unsupported Parser/Skill/Device Rule Contributions remain rejected until their subsystem semantics exist.
- `SpaceHangarBoardDefinitionProbe` now checks the expected 2 workshop / 1 parser / 2 skill consumer routes and verifies tamper rejection. Probe is authored, not executed; Godot runtime validation remains pending.

- Probe extension: the Hangar Board probe now temporarily authors a `scope=parser` contribution on the installed Parser Definition and verifies that the Core-facing resolver rejects it rather than leaking it into workshop scope. It restores the catalog fixture after the check.
