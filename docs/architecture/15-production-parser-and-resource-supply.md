# 生产、原石 Parser 与资源供给模块

## 1. 领域边界

Space 拥有原石掉落、Pickup identity、Parser Owned Instance、有限输入队列和 Parser 进度。Jar Core 拥有中央 Jar Warehouse、资源容量、Jar 实体、资源转移和结算事实。

Parser 不能直接创建 Core Jar，也不能跳过 Host ingress 直接写入 Warehouse。

## 2. Parser 流水线

```text
Enemy / Stage Drop Profile
  -> Energy Stone Pickup (stable Pickup ID, shape, finite volume)
  -> SpaceOreParserRuntime (per-shape FIFO + remainder + partial Jar progress)
  -> Pending Output Batch (stable Operation ID)
  -> WorldV2ShipHost.ImportProducedJars
  -> Jar Core Warehouse receipt
  -> Parser confirms only after successful Core result
```

不明确的响应必须使用同一个 Operation ID 重试，不能重新生成操作 ID 造成重复产出。

## 3. 多来源供给

至少区分：
- Core Time-based Producer → Core Central Warehouse；
- Space Ore Parser → 通过 import receipt 进入 Core Central Warehouse；
- Core Liquid Producer → Ship Liquid Inventory。

流率字段不等于生产源；Jar Flow 和 Liquid Flow 是转移能力，不可再次算作生产。预测应分别保留来源、边界和余数，不可重复计算。

## 4. 生产设备与成长

设备 Definition 描述允许参数；Owned Instance 保存独立成长状态；战前 Composer 生成冻结运行 Profile。运行时不应回读可变 Catalog Resource 来改变当前战斗配置。

## 5. 失败与恢复

- Pickup ID 防止同一掉落重复接收。
- Parser checkpoint 保存队列、余数、部分进度和 pending operation。
- Core import receipt 是已入库事实的权威来源。
- Parser 只有在 Core 确认后才能清除 Pending Batch。
- 跨边界不一致时停止提交并记录诊断，不能猜测是否成功。

## 6. 源码与进一步阅读

`SpaceOreParserRuntime.gd`、`SpaceOreParserJarIngress.gd`、`SpaceEnergyStonePickup.gd`、`SpaceBattleJarSupplyForecast.gd`、`SpaceBattleSupplyReconciliation.gd`。详细玩法契约见 [15 — Production, Parser and Progression](../industrial/15-production-parser-and-individual-progression-gameplay.md)。
