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
4. **订单资源需求来源可能重复**：`SpaceSkillDefinition.jar_requirements` 仍被用于构建订单/平衡预估；需要将 Core order template 的实际生成结果确立为唯一权威来源，避免预测清单与真实订单漂移。
5. **Stage reward transaction 未完成**：Campaign clear 与 progression reward 尚无跨 aggregate 原子提交；Offer UI / 玩家选取 / durable receipt 仍需接通。
6. **Protected Target 未完成**：有 objective contract，但真实可受攻击 Actor、敌人目标选择、被摧毁事件与 checkpoint identity 仍需实现。
7. **Typed Effect 系统未完成**：当前 Buff-first；Beam / Projectile / Missile / Shield / SupportUnit / Recon 等需要真实类型化定义和执行器。
8. **生产初始拥有库存/解锁引导未完成**：需确定新玩家初始可用船、解析器、工作台、技能实例的来源和版本；不得把 Definition 列表直接当成 Owned Inventory。
9. **验证边界**：Space demo 的 Godot 4.7.1 .NET 编译、GDScript parse、SceneTree Probe 和集成验证当前未执行；Core PR #59 的成功 CI 只覆盖该 Core head，不等于 Space demo 已验证。

## 4. 执行顺序与完成定义

### Phase A — 事实审计与契约收敛（当前）
- [ ] 审计 Game / Spawner / Boss / Hangar / GameState / Reward / Power Evaluator 的实际接口。
- [ ] 核对新旧 Hangar 选择 UI 是否真的调用 owned selection controller；修复“类已存在但 UI 未接线”的断层。
- [ ] 核对 new/resumed stage 的 durable settlement callback、exact stage identity、protected target identity。
- [ ] 核对 OwnedLoadoutAssembler 是否将每个被选 instance 的增长属性写入最终冻结快照，尤其 Master/Slave Workshop、Skill、Parser、Ship、Device。
- 完成定义：调用链和所有权边界有源码证据；发现的问题形成修复提交，不以文档审计代替修复。

### Phase B — 子系统真实指标与强度模型
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
- [ ] 兼容性校验包括 exact version、shape vocabulary、shape affinity、order template、capacities 与 Core world options。
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
- `SpaceHangarBattleLauncher` 的新开与恢复路径都注入 stage settlement callback；但必须继续检查 Game checkpoint restore 后 stage runtime 的 exact identity 检查，不能仅凭 callback 注入就判定完整。
- `Spawner` 的 boss beat 将 boss 数量固定为 1，不随 encounter scale 复制；普通敌人数才缩放。
- `SpaceStageBossActor.configure_stage_boss` 在入树前缩放 max_hp；Boss 物理逻辑重写接触处理，避免复用普通追击敌机的接触即死亡语义。仍需检查 EnemyChaser/Health 初始化时序及 Probe。
- `SpaceHangarScreen` 源码仍包含 Definition picker 字段与 UI 控件；SelectionController 已使用 owned inventory API，但当前界面是否把所有控件接到 owned instance draft 尚未证实。这是 Phase A 首要核对项。
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
- 待完成：Phase A 全面调用链核查；Phase B 子系统指标模型设计与代码落地。
