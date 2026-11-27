# 15 — 从生产到订单：解析器、Jar 与个体成长玩法规范

> 状态：玩法规则基线 / 可进入垂直切片实现；最终产率、掉落率、经验阈值和战斗平衡尚未定稿。  
> 基于 Core `e1e89cad5e0f11f369c8ade814140a7b4cc8df74` 与 Space `8ad262ab8e42801af1e782c29becb59b5ce65bc6` 的现有代码和领域文档整理。  
> 本文把“已存在的运行机制”与“尚需游戏设计决定的内容”分开，不把演示资源中的数字当作正式数值。

## 1. 玩家体验目标

Jar 的战斗经济不是“拾取后直接得到装备”，而是一条可观察、可配置、可成长的资源链：

**战斗获取有限原石 → 原石解析器按形状加工 → 产出空 Jar → Core 中央仓库接收 → 工作台按规则加工 Jar → 订单检查最终 Jar → 成功周期触发 Space 技能效果。**

玩家在战前做的是一个完整构筑：选择飞船、生产设备、原石解析器、两个工作台个体、工作台组合和技能；进入战斗后，玩家通过拾取、主动技能和构筑带来的被动自动化影响资源流。构筑快照在战斗期间冻结，成长只影响之后重新组装的战斗，不能在当前战斗中途改写已有规则。

玩家应能回答四个问题：

1. 当前拥有什么资源，分别存放在哪里？
2. 哪种形状的 Jar 正在生产，离形成一只完整 Jar 还差多少？
3. 订单具体缺少什么 Jar、液体或工作台加工能力？
4. 某个 Owned Individual 升级后，实际改变了哪项产能、容量或技能效果？

## 2. 自机区域与个体归属

自机 Board 只有三个顶层区域：

| 顶层区域 | 职责 | 主要内容 |
|---|---|---|
| Production Area | 把外部有限输入转成可供 Jar 世界接收的生产产出 | 原石分解功能子区、原石解析器、其他生产设备 |
| Workshop Area | 安装独立工作台个体，执行 Jar 规则转换 | Master / Slave 槽位与各自的 Workshop Individual |
| Order Area | 声明目标、显示需求、接收最终完成事实 | A/B 订单需求、Active / Passive 控制入口、交付状态 |

**Decomposition Area 是 Production Area 的功能子区域，不是第四个顶层区域。** 原石解析器安装在生产区的分解子区；普通生产设备可以位于 Production Area 的其他槽位。两者是不同的组件定义和运行职责，不能因为同属生产区就混成一个设备类型。

工作台是独立 Individual。它无论安装在 Board 的 Master 还是 Slave 槽位，内部仍保有自己的资源所有权：

- Jar Storage：该工作台拥有的离散 Jar 集合。
- Free Liquid / Liquid Staging：该工作台拥有的游离液体账户，具体子账户由 Core 的工作台领域对象管理。
- Order Staging：按订单隔离的液体子账。
- Prefill：工作台预置液体的独立子账。
- Jar Internal Liquid：属于 Jar 本身，不属于工作台的游离液体库存。

Ship Liquid Inventory 仍属于自机，中央 Jar Warehouse 仍属于 Core 的生产仓库。Board 上存在连接，不代表账户被合并；只有明确的 Output → Input Connection 和成功的准入/转移，资源才改变所有者。

主台/从台是 Board Assignment 的槽位角色，不是工作台定义的固有属性。角色交换不会改变工作台个体自己的 Mark、Ban、容量和成长数据。

## 3. 原石与解析器：有限输入、按形状加工

### 3.1 原石掉落

每颗能量原石是一笔有身份的有限输入，至少携带：

- 唯一 Pickup ID；
- Stone Type，对应 World 中一个合法 Jar Shape；
- 有限 Volume，表示可供解析的加工进度；
- 掉落 Profile ID / Version，便于回放和结算追踪。

敌人或遭遇配置决定是否掉落、掉落哪种形状和多少体积。掉落概率、权重和体积必须来自版本化内容数据，不能写成 Core 的固定规则，也不能由解析器凭时间制造输入。

Space 当前已有 `SpaceEnergyStoneDropProfile`，包含 `dropChance` 与加权 Stone 表。仓库里的演示掉落表仅用于原型验证，不是正式掉落平衡。

### 3.2 解析器的加工规则

原石解析器是 Space 拥有的生产设备 Owned Instance，不是 Jar Core 的时间驱动 Producer。它接受所有已配置形状的原石，但每种形状独立处理：

- 每种 Shape 一条 FIFO 输入队列；
- 每种 Shape 独立的速率余数；
- 每种 Shape 独立的未完成 Jar 进度；
- 每种 Shape 独立累计已产出 Jar 数；
- 尚未被 Core 确认导入的输出批次保持 Pending。

解析器 Definition 的有效参数：

| 参数 | 玩法含义 | 当前执行方式 |
|---|---|---|
| `productionPercentage` | 解析器整体工作效率/开工率，范围 0–100 | 将解析器自身每种形状的处理速率按百分比缩放 |
| `shapeProcessingRatePerSecond[shape]` | 每种形状每逻辑秒最多处理多少原石进度 | 受同形状队列的有限输入约束 |
| `progressPerJarByShape[shape]` | 形成一只该形状 Jar 所需的累计进度 | 达到阈值才形成整数 Jar |

对每种形状，运行时规则可表示为：

[
	ext{有效处理速率}(s)
=
	ext{基础速率}(s)
	imes
rac{	ext{productionPercentage}}{100}
]

[
	ext{本步产出 Jar 数}(s)
=
leftlfloor
rac{	ext{上步余数进度}(s)+	ext{本步实际消耗原石体积}(s)}
{	ext{progressPerJar}(s)}
ightfloor
]

未达到整只 Jar 阈值的进度留在解析器里；未处理完的原石体积留在输入队列里。不同形状不能互相挪用进度，也不能用某种形状的过量库存掩盖另一种形状的短缺。

**productionPercentage 不是形状产出分配比例。** 它不会决定“圆罐占 50%、方罐占 30%”；每种形状的输入队列和处理速率各自决定其产出。

### 3.3 输出与仓库边界

解析器只生成带稳定 Operation ID 的空 Jar 数量批次，不创建 Core Jar 实体，也不直接注入 Master / Slave。

固定流程：

1. 解析器达到整 Jar 阈值，创建 Pending Output Batch。
2. Space 通过 `WorldV2ShipHost.ImportProducedJars` 提交批次。
3. Core 将产出的空 Jar 导入中央 Warehouse，按 Core 容量处理接收与溢出。
4. Space 只有收到 Core 成功结果才确认解析器批次。
5. 若响应不明确，使用原 Operation ID 重试；不得换新 ID 造成重复产出。

解析器的输入队列、部分进度和 Pending 批次归 Space；中央 Warehouse 的 Jar 所有权、容量、溢出事实与操作去重归 Core。Warehouse 到 Master 的流动再走 Core 已有资源路径。

### 3.4 当前运行限制

当前战斗运行时要求一个分解槽位和一个解析器实例。多解析器不是简单放宽数量限制：必须先定义每颗原石唯一分配给哪个解析器、队列路由、设备失效、更新顺序、输出批次身份和存档恢复规则。本阶段不将“一个解析器”改成未经路由设计的多解析器。

### 3.5 三种供给与流转不能混成一种产率

当前玩法中至少有三条不同的产出/流转路径：

| 路径 | 输入 | 输出归属 | 时间/资源语义 |
|---|---|---|---|
| Space Ore Parser | 玩家实际拾取的有限 Energy Stone Volume | Parser 生成的整数 Jar 批次，经 Import 进入 Core Central Warehouse | 有限输入队列；按形状处理速率；保留未加工体积和部分 Jar 进度 |
| Core Time-based Producer | World V2 配置的时间驱动生产率 | Core Central Warehouse | `WorldV2Options.Producers[].Rates`，单位为每个 Core logical time unit；不消耗 Energy Stone |
| Core Liquid Producer | World V2 配置的液体生产率 | Ship Liquid Inventory | `LiquidProductionRates`，单位为每个 Core logical time unit；不是 Workshop Staging 的直接入账 |

另外，`jarFlowRatePerLogicalTime` 和 `liquidFlowRatePerLogicalTime` 描述资源流转能力，不是额外的生产源。Jar 生产进入 Central Warehouse 后还要按 Core 的流率和准入规则进入 Master；Ship Liquid Inventory 的液体也不能被视为已经在 Workshop staging 内。

**同一场战斗可以同时启用 Core Time-based Producer 和 Space Ore Parser。** 两者最终都向 Central Warehouse 提供 Jar，因此在玩法经济上是两笔独立供给；若都启用，必须相加且各自保留来源，不能把 Parser 输出又当作 Core Producer 输出重复计入。若某一模式本来应该停用，必须在 World 构筑数据里明确关闭，而不是依赖 UI 隐藏。

当前 Demo 的两个 World Profile 都包含 Core Time-based Producer：

- `demo.world.starter`：圆罐 1.0、方罐 0.8、三角罐 0.6、长条罐 0.5、六边罐 0.4（每逻辑时间单位）。
- `demo.world.deep_field`：圆罐 0.7、方罐 0.9、三角罐 1.0、长条罐 0.8、六边罐 0.6（每逻辑时间单位）。

因此当前 Demo 的 Jar 供给不只有原石解析器。上表数值是演示配置，不代表正式经济目标。

### 3.6 当前经济预测的连接缺口

当前实现需要分开理解：

- `SpaceSkillBuildContextEvaluator` 使用 Ship 的 `expectedStoneProgressPerSecondByShape`、Parser 的有效处理速率和 `progressPerJarByShape`，计算 Parser 转换能力。它不是从敌人实际击杀节奏推导 Stone Drop 速率。
- `SpaceJarWorldResourceProfile` 会校验并冻结 Core `producers` 配置，要求每个 Producer 有稳定唯一 `producerInstanceId`；`build_liquid_economy_resources()` 仍只投影液体库存、液体生产率和液库容量。
- `SpaceBattleJarSupplyForecast` 单独合成初始 Warehouse、Core Producer 和 Space Parser 三种 Jar 来源，并按 Core/Parser 定点余数计算输出与 Warehouse → Master 流量上限。它使用指定 Encounter 的概率加权期望输入，是预算场景而非逐次掉落回放，也不模拟 Core 实际溢出和 Master Mark 选取。
- `SpaceBattleEconomyEvaluator` 接收调用方提供的 `shapeJarOutputPerSecond`，而不是自己从 Core Producer 与 Parser 两条来源构建总量。

因此生产级构筑预测的剩余工作不是再造一个总产率字段，而是把版本化 Drop Profile 和有限 Stage 的敌人数量/时序映射为可审计的 Low / Baseline / High 场景，并在战斗中用实际 Pickup ID、Parser checkpoint 与 Core Warehouse receipt 逐步校正预估。Ship 的 `expectedStoneProgressPerSecondByShape` 目前仍是技能构筑平衡的预估输入，不是第二份原石来源；不能与 Encounter Drop 体积重复相加。

## 4. Jar 是离散资源个体，不是可折算的液体容器

每只 Jar 有稳定 Jar ID，并携带：

- Shape；
- 可选的内部 Liquid；
- 从 World Vocabulary 派生的 Polarity；
- 订单生命周期 Mark。

Jar 内部液体只有两种 World 定义的液体身份之一；空 Jar 是 Neutral。Space 当前 World 的数据映射为：

- `燃料 → Anode`
- `冷却液 → Cathode`

极性由 World 映射决定，不从中文名称、字母顺序或 UI 颜色推断。更换显示名不应改变极性；交换映射则是 World 规则变化。

Jar 相关操作按资源归属区分：

| 行为 | Jar 状态 | 液体账户影响 |
|---|---|---|
| MATCH | 通过订单规则后标记 Jar，表示进入订单生命周期 | 不产生液体转移 |
| POUR_IN | 将允许的液体装入 Jar | 从当前工作台游离液体 / 订单暂存账户消耗 |
| POUR_OUT | 将 Jar 内液体倒出，Jar 变为空 | 产液尝试进入当前工作台 staging；被 Ban/容量拒绝的部分按 Core 规则记录丢弃 |
| RESHAPE_EMPTY | 空 Jar 改形 | 按规则消耗工作台游离液体 |
| RESHAPE_FULL | 满 Jar 改形 | 自耗来自 Jar 自己的内部液体账户，不得伪装成工作台 staging 消耗 |
| 物理迁移 | Jar ID、形状、内部液体、极性与 Mark 保持 | 只改变权威 Jar Storage 所有者 |

工作台 Ban 只约束其作用域内的游离液体 staging 接收、存储和转移，不阻止因为 Jar 内装有该液体而 MATCH、倒液、Jar 自耗或搬运 Jar。Ban 不能被翻译成 Jar Polarity，也不能作为全局“污染标签”。

## 5. 工作台与订单：目标驱动，不预写死配方步骤

### 5.1 工作台个体

每个工作台 Definition 提供本地规则数据：Base Marks、Additional Marks、Ban、Jar Capacity、Per-Liquid Capacity，以及可选 Aggregate Order-Staging Capacity。Owned Instance 的成长值在战前组合到冻结配置；运行中的工作台不因角色变化而改变本地属性。

工作台的 Shape 倾向可通过 Marks 表达。HUD 可以将 Base Mark 和 Additional Mark 用同一视觉语言显示，但颜色和外观只负责识别，不参与规则判定。

### 5.2 A/B 订单

订单声明最终需求，而不是让 Space 伪造一份操作配方。需求绑定 Core 的精确 Order Template，Core Solver 决定具体 Jar、操作顺序和资源清单。

- A 类订单：绕过 Slave，需求在 Master 完成。
- B 类订单：当前候选偏好 Slave-first，但仍保留 Master 备选；这不是贪心地强制所有步骤都交给 Slave。
- B 类执行阶段：Master 先完成分配给自己的步骤；随后一次 Master → Slave 单向交接；Slave 再完成分配给自己的步骤；所有需求各完成一次后订单才成立。
- Master 已完成的需求 Jar 仍然交接给 Slave，但 Slave 不重复操作这些 Jar。
- Slave 不拥有独立的 Ship Liquid 输入源；使用期间只接收允许的 Master 资源。
- Master Ban 会阻止禁止的游离液体跨台流动；Jar 内部液体不是 Master staging 液体。
- Master/Slave 的角色选择由玩家安装关系决定，Solver 负责验证并寻找完整路径。

订单区是最终目标和交付边界，不是普通仓库。Jar 只在目标状态、数量、阶段和资源清单全部满足后才算交付成功。

### 5.3 Jar Order Template 与实际液体成本

Space 的 Core Order Template 每个 `requirements` 项代表一只独立 Jar：字段只有 `shape` 和可选的目标 `liquid`。重复 Shape 是多个实体需求，不是一个数量字段；当前模板最多 10 项。空 Jar 需求必须排在填充液体 Jar 需求之前。模板描述最终 Jar 状态，不描述操作步骤，也不包含数值型 `liquidUnits`。

一个要求“圆罐 + 冷却液”的 Jar，只说明交付时该 Jar 内部必须是冷却液；**不能据此认定必须从游离液体库存额外扣一单位**。实际外部液体需求由 Core 对具体执行路径计算：

- `POUR_IN`：从当前工作台游离液体/订单暂存账户消耗恰好 1 单位目标液体。
- 空罐 `RESHAPE`：从当前工作台游离液体账户消耗恰好 1 单位改形成本液体。
- 满罐 `RESHAPE`：消耗 Jar 自己内部的液体，不再额外消耗一单位工作台游离液体。
- `POUR_OUT`：把 Jar 原有液体返回当前订单的 staging 余额；实际接收仍受该 staging 的 Ban/容量规则约束，拒收和丢弃由 Core 记账。

`WorldOrderResourceManifest` 根据解出的具体操作路径计算初始供液峰值、最终余额、以及 B 类 Slave 所需的初始液体。A 类只在 Master 执行；B 类先验证 Slave 可做的部分，再证明 Master 执行后仍保留 Slave 精确需要的资源，最终只转移 Slave 路径需要的数量，不把多余液体全部泵过去。Space 的配方成本估计只能作为带假设名称的 Forecast；存在真实 Solve Plan / Manifest 时，以 Manifest 为准。

### 5.4 订单完成与技能效果

技能是 Space 的玩家能力定义。一个 Skill 绑定：

- 精确版本的 Core Order Template；
- Active / Passive 控制区域；
- Jar cooldown；
- Space Effect Definition / Version 与参数；
- 对应的收益/成本平衡报告。

Active 由玩家手动请求；Passive 由 Core 的 Passive Scheduler 安排。两者使用相同 Jar 资源规则和冷却规则。Space 只能在收到成功的、可去重的订单周期完成事件后应用效果。

Jar Cooldown 与 Space Effect Duration 不同：前者限制再次支付/执行订单的时间，后者描述技能收益持续时间。二者都跟随同一战斗模拟时钟，但不能合并成同一个字段。

当前 Effect 执行器是 Buff-first。射弹、激光、导弹、无人机、侦察等非 Buff 效果需要各自明确的 Space Typed Effect Executor；不能为了复用 Buff 系统，把射弹或无人机伪装为 BuffDefinition。

## 6. Owned Individual 成长

成长归 Space 玩家拥有的 Owned Instance，而不是 Definition，也不是 Core 规则本身。当前共享实例数据包含：

- Instance ID 与 Item Kind；
- 精确 Definition ID / Version；
- Level、累计 Experience、Progression Revision；
- Growth Curve ID / Version；
- 子系统可解释的 Growth Attributes；
- 不可变获取来源 Provenance。

同一 Definition 的多份拥有实例各自独立成长。战前构筑冻结选中实例的 Growth Attributes 和 Revision；当前战斗不热更新。升级在结算后保存，下一次重新组装战斗时生效。

### 6.1 当前已实现的成长属性边界

| 个体类型 | 当前允许的成长属性 | 实际作用 |
|---|---|---|
| Ship | `stoneProgressRateMultiplier` | 调整 Ship 侧每形状原石进度预估；目前是构筑平衡输入，不等同于直接改变敌人掉落表 |
| Ore Parser | `shapeProcessingRateMultiplier`、`progressPerJarMultiplier`、`productionPercentageBonus` | 改变实际解析速率、每只 Jar 所需原石进度和解析百分比 |
| Workshop | `maxJarsBonus`、`maxLiquidsBonus`、`liquidStagingCapacityBonus`、`additionalMark.<shape>` | 提高局部容量或解锁额外形状标记，不改变 Ban 和 Master/Slave 关系规则 |
| Production Device | `runtimeAdd.<field>`、`runtimeMul.<field>` | 只覆盖其已有 Runtime Profile 中显式存在的数值字段；必须有对应运行时消费者 |
| Skill | `effectAdd.<parameter>`、`effectMul.<parameter>`、`benefitAdd.<dimension>`、`benefitMul.<dimension>` | 调整 Space 效果及收益评估；重算 Jar 支付平衡，低于要求的 undercosted 构筑不能通过 |

Parser 三个成长属性要保持不同语义：

- `shapeProcessingRateMultiplier`：更快处理已获得的原石，主要改善有输入可加工时的周转速度。
- `progressPerJarMultiplier`：改变每只 Jar 消耗多少加工进度；降低门槛会改善原石到 Jar 的投入产出效率，经济影响比单纯加快处理更大。
- `productionPercentageBonus`：增加整体有效处理百分比点数，结果不得超过 100。

这些属性不能重复计算同一收益。例如把每 Jar 阈值降低 10%，又把 Ship 预估输入提高 10%，会同时扩大供给和提高转换效率，必须在整场战斗共享经济评估中一起观察。

### 6.2 XP 如何产生：本阶段的玩法决定

**实现状态**：已有精确版本成长曲线资产类型、曲线注册表、成长计算服务和 revision-checked 实例更新。`SpaceProgressionRewardProfile` 已建立版本化内容契约：它把显式配置的 source kind 映射为兼容的 Owned Instance kind、最终整数 XP 和 exact Curve ID / Version，并将 `rewardProfileId@rewardProfileVersion` 写入每条 award。未知来源、缺失规则、错误归属、重复事件或混用政策版本均 fail closed。`SpaceProgressionRewardService` 继续负责按 Owned Instance 汇总、精确曲线计算和 settlement + source event 双层 SHA-256 收据去重；`GameState.commit_space_progression_reward_settlement()` 先持久化 detached candidate，再发布新状态。XP 收据与 `reward_acquisition_ids` 分开保存，并通过 schema-v3 兼容迁移与确定性探针验证。`SpaceBattleRewardFactProjection` 已把 Parser 接受的 Pickup ID 和精确 Stage clear candidate 投影为稳定事实，并随 campaign clear result 一起持久化；事实只归属冻结的 Ship Owned Instance。**当前尚无正式生产 Reward Profile / Curve Catalog 资产，也尚未将这些事实接入 XP settlement coordinator**；Parser 实际处理体积、生产设备、Core Workshop 转换和 Skill 周期仍缺各自的稳定 reward fact outbox。探针数值仅是合成契约数据。

建议采用以下奖励原则，待正式曲线和奖励表数据化：

| Owned Individual | XP 归属事件 | 不应发 XP 的情况 |
|---|---|---|
| Ship | 完成一次有效战斗结算；战斗目标、采集或生存表现可以作为 Space 奖励分项 | 单纯重复打开 Hangar、重新冻结构筑 |
| Ore Parser | 实际消耗原石体积或完成可追踪的解析工作；按 Parser Instance ID 归属 | 仅有掉落但未被该解析器接收的原石；重复导入同一个输出批次 |
| Production Device | 由该设备权威消费者确认的实际处理结果 | 只有 Runtime Profile 数值变化、没有实际处理 |
| Workshop | 由该工作台实际完成的 Jar 规则转换贡献 | 仅仅安装、转移 Jar、MATCH 标记或 Solver 预测路径 |
| Skill | 该 Skill 的订单周期成功完成并实际提交对应效果事件 | 仅按下 Active 按钮但订单未完成、Passive 仅进入候选队列 |

奖励必须基于真实执行/结算事件，不基于 Solver 候选数量、理论冷却次数或战前经济预测。B 类订单的 Workshop XP 应按实际执行操作归属到 Master / Slave 对应的 Owned Instance，而不能把整张订单奖励无差别发给两台。

建议的事件归属进一步明确为：

| 个体 | 可计入的事实 | 归属键 |
|---|---|---|
| Ship | 玩家实际取得的 Energy Stone 拾取；可叠加战斗完成/目标奖励 | Pickup ID / Battle Settlement ID |
| Ore Parser | 该 Parser 实际消耗的原石体积，包括本场结束时保留的部分 Jar 进度 | Parser Instance ID + Parser Runtime / Batch Fact |
| Production Device | 对应专用消费者确认的实际处理输入或产出 | Device Instance ID + 处理事件 ID |
| Workshop | Core 成功提交的 Jar 规则转换，归属于执行转换的那一个工作台；B 类 Master/Slave 分别计算 | Workshop Instance ID + Rule Transition / Operation ID |
| Skill | 绑定该 Skill 的订单周期成功完成并通过效果事件提交 | Skill Instance ID + Order Event ID |

不计入成长的情况：敌人掉落但玩家没有拾取的原石、解析器尚未处理的队列体积、只存在于 Solver 预测中的操作、被拒绝或失败的转换、被动订单仅被排入调度、重复导入或重复投递的同一事件。MATCH 只改变订单生命周期 Mark，不应伪装成资源加工量；是否给少量参与经验应由独立的生命周期奖励配置决定，而不是和化学操作使用相同权重。

每种事件的 XP 系数属于版本化 Space Reward Profile。当前 Reward Profile 契约接收已提交的事实 envelope，并输出最终正整数 XP；单位换算、分段累计与取整规则必须由后续版本化内容策略明确，不能在通用服务里隐式决定。结算时先按事件 ID 去重，再按实际来源实例汇总。经验系数、事件权重、单位换算和每战上限仍然是待平衡数据，不在本规范中设定虚构数值。

### 6.3 XP 防重复与曲线应用

推荐的结算顺序：

1. Core / Space 记录本场战斗可用于奖励归属的实际完成事实。
2. Space 根据每条事实的来源 Instance ID 生成稳定 Progression Reward ID。
3. 同一 Reward ID 重试时必须 no-op；不同实例或不同完成事实不能碰撞。
4. 汇总本场各实例累计 XP，解析该 Item Kind 对应的精确 Curve ID / Version。
5. Growth Service 计算新 Level 和完整 Growth Attributes。
6. Progression Aggregate 以旧 Progression Revision 为基准提交更新；过期 Revision 拒绝覆盖。
7. 保存玩家成长状态与已处理的 Reward ID；下场战斗冻结更新后的实例快照。

`reward_acquisition_ids` 仍只表示 Owned Instance 获取回执；XP 使用独立的 `progression_reward_receipts`，同时记录整场 Settlement ID 和每个实际 Source Event ID。Award fingerprint 还绑定 Reward Profile ID / Version，避免相同 XP 数字来自不同策略版本时失去来源审计。相同 Settlement ID + 相同规范化载荷会成为无副作用重复结果；同一 ID 对应不同载荷、或事件被另一场 Settlement 再次认领，则 fail closed。XP 系数和小数进度如何统一取整仍由版本化 Reward Profile 决定；通用结算服务只接收最终正整数 XP，不能把未达一只 Jar 的加工劳动无声丢掉或重复计算。

## 7. 生产、技能与资源经济的平衡原则

1. 原石供给按形状分别计算。任何一类 Jar 的产量都不能补偿另一个形状的缺口。
2. Parser 的有效产率受原石实际输入、每形状处理速率、生产百分比和每 Jar 进度阈值共同限制。
3. Ship 的每形状预估输入率是平衡模型的预测输入；敌人掉落配置才决定实际战斗拾取。两者要校准一致，但不能重复乘算。
4. 液体供应独立于原石供应。液体 Jar 的实际游离液体成本来自 Core 具体执行计划/Resource Manifest；不可从原石体积或 Jar 数量推算液体单位。
5. 每个 Skill 的收益要与其实际 Jar Order Cost、A/B 阶段、工作台能力、液体成本和战斗时间共同评估。
6. 所有已装备技能共享同一场战斗的 Jar、液体和工作台操作预算；不能让每个 Skill 都独立假设能使用完整库存。
7. Active 的 requested activations 是玩家输入/构筑计划；Passive 的实际请求频率由触发策略决定。当前 cooldown ceiling 只是预测上限，不是 Passive 实际必然触发率。
8. 当前 whole-loadout forecast 是资源预算预测，不是逐 Tick 精确库存模拟。正式平衡必须继续补上生产时序、库存容量、订单阶段与实际触发频率，再根据战斗样本校准。

## 8. Demo 原石表的数值体检（演示数据，不是正式平衡）

当前 `demo_energy_stone_drops.tres` 配置掉落概率 0.45；权重总和 8；五种 Stone 的 (weight, volume) 分别为：

- 圆罐：(3, 10)
- 方罐：(2, 12)
- 三角罐：(1, 15)
- 长条罐：(1, 20)
- 六边罐：(1, 25)

因此在每次敌人击败尝试一次该掉落表、没有额外掉落修正的假设下：

- 条件于成功掉落的平均原石体积为 14.25。
- 每次敌人击败的期望原石体积为 6.4125。
- 形状期望体积依次为：圆罐 1.6875、方罐 1.35、三角罐 0.84375、长条罐 1.125、六边罐 1.40625。

将这个输入分布代入当前两个 Parser Demo Definition，并假设输入最终全部处理、无仓库容量丢弃：

| Shape | Universal：阈值 / 每次击败期望 Jar | Precision：阈值 / 每次击败期望 Jar | Precision 连续输入时最大 Jar/s |
|---|---:|---:|---:|
| 圆罐 | 1.0 / 1.6875 | 0.8 / 2.1094 | 1.575 |
| 方罐 | 1.0 / 1.3500 | 0.9 / 1.5000 | 1.200 |
| 三角罐 | 1.0 / 0.8438 | 1.0 / 0.8438 | 0.900 |
| 长条罐 | 1.0 / 1.1250 | 1.1 / 1.0227 | 0.6545 |
| 六边罐 | 1.0 / 1.4063 | 1.2 / 1.1719 | 0.525 |
| **总计** | **6.4125** | **6.6477** | **4.8545** |

Precision Parser 的 productionPercentage 是 90%，但它的 per-shape processing rate 和 progress-per-Jar 也发生变化。对五种形状都持续有输入的上限场景，Universal 的合计处理量为 5.0 进度单位/s、产出 5.0 Jar/s；Precision 的合计处理量为 4.59 进度单位/s、产出约 4.8545 Jar/s。换言之，当前 Precision Demo 是**更偏向圆罐/方罐投入产出效率的专业化设备**，不是所有形状都更快：长条和六边的持续产能明显较低。

由于当前掉落权重偏向圆罐/方罐，Precision 在“输入最终全部处理”的期望值下每次敌人击败产出约 6.6477 Jar，相比 Universal 的 6.4125 高约 3.67%；但它的满载总 Jar/s 上限约低 2.91%。这两个指标表达不同玩法：前者是资源效率，后者是解析吞吐。没有敌人击败频率、战斗时长、仓库容量和订单消耗数据，不能仅凭这两个数字判断哪一个解析器整体更强。

**需要设计者明确的含义**：当前 Stone Volume 不是“一颗原石必定生成一只 Jar”的计数。以 Universal 的阈值 1 为例，体积 10 的圆罐原石在完全处理后可形成 10 只圆 Jar；Precision 的 0.8 阈值可形成 12.5 只的累计进度等价量，实际 Jar 仍以整数批次输出。若目标玩法是一颗 Stone 对应一只 Jar，必须重新统一 Stone Volume 与 Progress Per Jar 的单位尺度；若 Stone 是可加工原料，则允许一颗 Stone 形成多只 Jar，但需要在 UI 明示体积、加工进度和完整 Jar 数量的关系。

以上仅是对当前 Demo 资源文件的算术审计，不代表真实敌人频率、产能瓶颈、Warehouse 溢出或技能平衡已经通过验证。

## 9. 供给预测的实现验收点

在把 Battle Economy Forecast 用作技能平衡依据前，需要同时提供并分别展示：

1. 起始 Central Warehouse 中每种形状的完整 Jar 数量；
2. Core Time-based Producer 在战斗时长内的预估产出；
3. 基于实际 Drop Profile / Encounter 场景的 Stone 输入量；
4. Parser 对这些有限输入的每形状预计消耗量、整 Jar 产出量和未完成进度；
5. Ship Liquid Inventory 初始余额与 Core Liquid Producer 产出；
6. 从仓库/自机账户流向 Master、再到 Slave 的有效流率和容量边界。

当前 `SpaceBattleJarSupplyForecast` 已完成初始 Warehouse、Core Time Producer、Space Parser 三路来源拆分与固定点预算投影。新增的 `SpaceBattleSupplyScenarioProfile` 和 `evaluate_scenario_band()` 将同一冻结输入分别按 Low / Baseline / High 预期敌人击败率计算，并按形状比较预期原石量、Parser 已处理/未处理量、整 Jar 产出和 Warehouse 毛供给；Core Producer 与初始 Warehouse 余额在三个场景中保持不变。

场景速率是版本化的明确输入，不从 `wave_plans` 的敌人数或休息时长直接推导。关卡敌人是否以及何时被玩家击败，受玩家构筑、战斗表现和战斗时序影响；没有实测击败样本或作者给出的情景假设时，不得虚构 Low / Baseline / High 数字。该区间是期望值敏感性分析，不是统计置信区间，也不是逐次随机掉落回放。当前 Demo 尚未配置正式的场景速率资产。

`SpaceBattleEconomyEvaluator` 仍采用全装备技能共同 fulfillment fraction；供给区间尚未自动贯通到一键 Loadout → Encounter → Skill Economy，也没有逐 Tick 模拟原石掉落、Core 仓库溢出、Jar Flow、Workshop 收货/消耗和 Passive 触发时序。未提供 Encounter 假设时不得拿 Ship 预估率伪装成真实掉落频率。

### 9.1 Parser → Core 实际导入回执

Parser Runtime checkpoint schema 5 除了已接受 Pickup、队列、分形状进度、累计 Jar 和 pending outbox，还会保存每批 Core Import Receipt。回执确认与 outbox 删除属于同一个 Parser 状态变更；结构校验失败时批次仍保持 pending。Core 的持久回执现在能在 duplicate replay 中重放首次逐 shape requested/stored/discarded 结果，Parser 将其记录为 `duplicate_exact`，校验并保留逐形状 requested/stored/discarded maps；旧 Core duplicate 0/0/0 仍以 `duplicate_confirmation_only` 明确标记未知；旧 receipt v1 的聚合数字不会被分摊到各个 shape，`perShapeCoreOutcomeHistoryComplete` 会显式标记不完整。只读 observation snapshot 暴露接受/处理体积、完成 Jar、pending 数量、已确认请求数、精确存储/丢弃汇总及逐形状 maps、精确重复批次与未知历史结果；旧 receipt v1 的聚合数字不会被人为分摊到形状。

旧 Parser schema 2/3 没有完整的 Core 导入回执历史；schema 4 已有 receipt schema 1，但其 duplicate 结果可能未知。它们仍可迁移，不能假装补齐旧回执；schema 4 维持原有 history-complete 标记，只有新建 Parser 或能够证明完整记录的 schema 5 状态才可以声明完整。

当前 Core schema 11 及其精确导入回执 DTO 对具有持久结果的重复 `ImportProducedJars` 请求返回首次提交的 requested/stored/discarded 逐形状结果，并设置 `wasDuplicate=true`、`hasExactReceipt=true`。只有旧 schema 10 或更早检查点中仅保留 OperationId tombstone、没有历史结果回执时，重复请求才会返回 `hasExactReceipt=false`；Space 必须记录为 `duplicate_confirmation_only`，不得把缺失的历史结果伪装为 0 存储/0 丢弃。首次回执和精确重复回执都必须满足逐形状 `stored+discarded=requested`，聚合数量也必须一致。

## 10. 玩家需要观察和理解的反馈

战斗内至少让玩家看见：

- 船上液体库存、各工作台游离液体、Jar 数量和 Jar 内容分开显示；
- 每种形状的原石输入/解析进度/待导入 Jar 批次；
- Core 中央仓库与工作台 Jar Storage 是不同位置；
- Master → Slave 是单向资源交接；
- 订单需要的 Shape、内部 Liquid、数量、当前阶段与缺少项；
- Active / Passive 技能各自的冷却和状态；
- Owned Individual 的等级、经验进度，以及本次成长改变了什么属性。

UI 只能读权威快照和展示层数据，不自己计算 Ban、容量、极性、订单可行性或资源成本。Shape 色彩沿用 [13 — Resource HUD and shape visual language](13-resource-hud-and-shape-visual-language.md) 的字形/名称/颜色三重识别；颜色不能成为唯一信息载体。

## 11. 首个可玩闭环与实现顺序

把“能从战斗拾取走到技能生效”作为这一轮的验收，不再以继续抽象通用框架作为交付。

### Slice A — 生产可见性

- 使用一个解析器 Owned Instance。
- 配置两种以上形状的有限原石输入。
- 在 HUD 显示每种形状的队列、进度和预计完整 Jar 数。
- 达到阈值后导入 Core Warehouse。
- 验证重复 Pickup ID、导入重试、容量溢出与检查点恢复。

### Slice B — Jar 加工与订单

- 从 Core Warehouse 将真实 Jar ID 接收到 Master Workshop。
- 使用一个完整 A 类订单验证 Jar 规则、游离液体成本、MATCH / Mark 和结算。
- 再接入一个 B 类订单，验证 Master 前置操作、单向交接、Slave 后置操作和实际资源归属。
- HUD 展示订单为何尚未完成，而不是只显示“无解”。

### Slice C — 技能收益

- 绑定一个 Active Skill 与一个 Passive Skill 的准确 Order Template / Effect Version。
- Active 必须经过用户请求，Passive 只能由 Core Scheduler 触发。
- 只有成功订单周期的持久事件才应用 Space 效果。
- 同一事件重复投递或读档恢复后不得重复叠加效果。

### Slice D — 个体成长与结算

- 给 Parser、Workshop、Skill 至少各配置一份 exact-version Growth Curve 资产。
- 决定经验奖励来源、系数、曲线阈值和最大等级；这些数字由内容/平衡数据提供，不写进通用计算器。
- 已实现可持久化 XP Settlement / Source Event Receipt、来源归属校验、按 Owned Instance 汇总及整批 detached-candidate 持久化；下一步接入真实战斗/Parser/Core 已提交事件并装配 Reward Profile 与 Curve Catalog。
- 战斗结算更新玩家 Owned Instance；下一场战斗重新冻结成长配置。
- 用重复结算、丢失回执、旧 Revision 覆盖、曲线升级和载入旧存档测试验证去重及兼容性。

## 12. 还没有定稿的内容与明确不做的事

本文件不虚构以下正式数值或能力：

- 每种敌人的原石掉落概率、权重、体积和掉落节奏；
- 各解析器的最终 productionPercentage、分形状速率和每 Jar 阈值；
- 五种 Item Kind 的正式经验曲线、最大等级和 XP 奖励系数；
- 各种技能收益、冷却、触发策略和全战斗共享预算的最终平衡值；
- 多解析器的输入路由与排队策略；
- 非 Buff 类型效果的生产级执行器；
- 逐 Tick 的全战斗精确库存仿真和完整玩家存档协调。

这些是接下来要由玩法样本和内容数据决定的工作。不得为了填满表格而先编数值，也不得在 Space 重复实现 Core 的 Solver、Ban、极性、Jar 状态转换、资源守恒或订单结算规则。

## 参考规范与实现

- Core：`docs/world-v2/jar-individual-area-port-and-circuit-route-model.md`
- Core：`docs/world-v2/circuit-system-model-and-bounded-resource-routing.md`
- Core：`docs/decisions/0006-world-owned-binary-liquid-polarity.md`
- Core：`docs/world-v2/order-funnel-and-workshop-replacement-contract.md`
- Space：`docs/industrial/10-prebattle-loadout-and-order-effect-binding.md`
- Space：`docs/industrial/12-order-funnel-and-skill-resource-cost-semantics.md`
- Space：`docs/industrial/13-resource-hud-and-shape-visual-language.md`
- Space：`docs/industrial/14-space-ability-and-workshop-rule-scopes.md`
