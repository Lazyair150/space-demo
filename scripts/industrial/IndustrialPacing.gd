extends RefCounted
## 工业舱里"刻"与"步"的换算，集中一处，界面和测试都从这里取。
##
## 为什么需要这个文件：Core 的 `ProcessStateDto.ticksUntilNextUnit` 只描述"当前这一单位
## 还剩几刻"，没有承诺"一步恒定几刻"。界面要提前估值，只能用实测节奏。
## 实测（`world_sandbox.json`，2026-11-18）：一个执行单位 2 刻。
## 这是**经验值**：Core 改执行节奏时必须改这里，否则报价卡与实际不符。

const TICKS_PER_UNIT := 2

const PACING_NOTE := "估算值（实测每单位 2 刻），非 Core 保证"
