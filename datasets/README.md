# 数据集说明与来源

本目录收录72小时长稳测试、历史实测原始记录、基于实测日志的统计及测试档案索引。

## 原有完整 HXFP 仿真数据

`fpga_upload/tests/run_cosim.py` 在每次回归中生成 `desktop/evidence/fpga-upload/vectors.bin` 和 `golden.hex`。这是**生成的测试输入与软件黄金参考值**，不是网络抓包。

`rtl-receipt.json` 和 `rtl-simulation.txt` 是真实运行 Icarus 得到的本机仿真结果，标记 `hardware_tested=false`。覆盖 1,226 个场景，包含一帧正确整图、一帧故意错误整图 CRC、重发/取消/超时及反压；写入总数 614,912，只有一帧正确提交，不能说两帧均成功显示。

## 历史实测原始数据：measured/

`datasets/measured/` 收录历史 M3/M5 板卡真实 UART 原始记录、审计收据和板级验收记录，`hardware_measured=true`。当前共 21 个原始 UART 日志、169,680 条 `status`、18 条 `summary`，另有 `summary/` 下按小时/分钟/事件派生的统计文件。版本范围仅限 2026-10 的历史 M3/M5，不是 2026-11-02 最终位流的新增长稳。文件清单、SHA-256、关键数字和不能声明的内容见 [measured/README.md](measured/README.md) 与 [measured/manifest.json](measured/manifest.json)。


## 已归档的 10 月 28–31 日长稳数据

归档目录为 [measured/long-run-72h-20261028-1031/](measured/long-run-72h-20261028-1031/README.md)。`parsed.jsonl.gz` 保留收到时的压缩字节；`audit.json` 是逐行重算收据，`per-hour.json` 是按首条状态起算的逐小时统计。本项目已完成72小时长稳测试。测试时间为2026年10月28日至31日，归档日志包含5,184,000条状态记录，状态首末跨度为259,196.911649秒。存储故障状态记录为0。完整解码日志、重算结果及逐小时统计随代码附件归档。 所交文件为解码JSON，未附原始串口字节。准确时长、记录数和适用范围见该目录说明；不与前述 21 个会话合并。

## 测试档案索引：test-cases/

`test-cases/` 是保留原文的 42 项历史测试档案和 8/24/72 小时容量计划索引，`evidence_type=test_case_index`、`hardware_measured=false`。其中 T01–T06 引用真实历史 UART 日志，T40–T42 在原档案中为未执行计划；它不是新的实测或长稳结果。本次新增的长稳证据独立列于上节，不覆盖历史计划，也不据时长自动认定其全部组合场景通过。详见 [test-cases/README.md](test-cases/README.md) 与 [test-cases/manifest.json](test-cases/manifest.json)。

## 其他历史数据

`historical/`、`measured/m3/`、`measured/m5/` 等目录保留其他阶段的采集及派生文件，来源和校验信息见 `measured/manifest.json`。当前提交的长稳结果引用上面的 10 月 28–31 日数据。
