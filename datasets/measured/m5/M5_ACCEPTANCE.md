# M5：故障隔离、量化与稳定性

日期：2026-10-02。M5 分为“RTL 可证明的边界”和“必须现场完成的证据”两部分；没有用户现场输入的项目不提前标成通过。


## M5 用户现场功能验收收尾（2026-10-03，当前结论）

**M5 按用户确认完成现场功能验收并收尾，保留已知限制。** 本结论覆盖下方历史检查点中的“M5未通过/待验收”状态，不将未覆盖测试改写为通过。

- 本次约两小时运行中，用户确认画面始终正常；143680条UART状态、0 invalid，未记录到存储故障。原始样本跨度7198.516521秒，证据见 `diagnostics/m5-two-hour-audit-20261003.json`。
- 音频由用户基于此前长时间运行的实际体验确认验收通过；该音频运行的精确时长、版本和独立日志未单独归档。本次两小时采集主要处于音频关闭状态，不作为两小时连续音频测试证据。
- 用户已确认以上收尾口径。完整延迟矩阵、转场显式观测、恢复联合验证及严格全程自动轮播等未覆盖项继续列为限制，不补造1000事件或性能优势。
- Setup WNS/TNS −6.699/−295.911 ns等已知时序问题继续开放；本次是用户现场功能验收收尾，不是时序签核、全部测试矩阵通过或M6最终冻结。
- 下一步为交付材料整理及另行安排遗留验证/时序修复；版本变化后重新评估相关回归与板上测试。本次只更新文档，不修改RTL/PLL/SDC或操作硬件。


## 历史执行记录说明

以下按执行过程保留当时的实现、待办和判断；“未通过/未开始”均是对应检查点状态，不是当前结论。当前验收结论见顶部；当前剩余动作见PROJECT_STATE.md。R1～R4后续修复包括UART CDC邮箱、恢复不再复位video_timing_data、转场re-arm和分阶段watchdog预算，提交链见共享状态；早期实现段落不是现版本RTL描述。

## 故障隔离实现（初始检查点）

`storage_watchdog.v` 在 SD 时钟域为以下状态提供有界计时和单周期 `recovery_pulse`：SD 初始化、TF 扫描、源图读取、SDRAM 写完成、无有效图片、写任务 retire。恢复动作复位 TF scheduler、`frame_read_write`，且当前顶层还将恢复复位连接到 `video_timing_data`；因此不能声称保持视频时序连续。片上提示仲裁和音源不直接使用局部恢复复位，但不等于完整 HDMI/音频输出链路不受影响。UART v3 字节 60–62 分别携带参数、fault/code 和恢复次数低8位；`last_timeout_cycles` 虽在顶层接出，但没有装入这三个字节。新增字段的 CDC 风险见 `M5_STEP6_REVIEW.md`。

E2 的 buffer 复用边界增加 `transition_block`：转场尚未结束时，KEY2 仍可进入一个待处理请求，但 SD 生产者不会写入可能仍被像素读出的旧 buffer。门控解除后才启动下一次写入。

## 仿真证据

`tests/storage_watchdog_tb.v` 注入并覆盖 6 类故障，检查每次只产生一个有界单周期恢复脉冲、故障码和计数递增，健康状态能清除 fault。`tests/slideshow_emergency_stop_tb.v` 还覆盖了“转场门控期间快速 KEY2 排队，门控解除后启动”的组合边界。`tests/test_m5_uart_metrics.py` 检查统计工具不会把快照计数跳跃填成虚假的延迟样本。

命令：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\test-m5.ps1
```

## 已有板上量化

`tools/analyze_m5_uart.py` 对 UART 快照只在请求计数对应的提交行取样，并显式报告计数跳跃。收据 `diagnostics/m5-uart-metrics-20261002.json`：

- 2026-10-01 COM39 的 4 个瞬应场景样本：平均 12.25702 ms，P95 15.097276 ms，P99 15.5114872 ms，最大 15.61504 ms；无计数跳跃、无无效包。
- 2026-10-02 COM38 的 3,584 条 v3 状态快照：0 invalid、0 fault 行；没有按键请求事件，不能从它推算 E3 操作延迟。
- 新位流易失 SRAM 下载后 COM38 30 秒基线 `diagnostics/m5-post-sram-com38-20261002.jsonl`：639 条合法快照、0 invalid、四张图扫描完成、fault/recovery 为 0。随后 180 秒用户验收窗口 `diagnostics/m5-user-acceptance-com38-20261002.jsonl`：3,584 条合法快照、0 invalid，但 request/brightness/mode 没有变化，不能据此宣称按键操作已完成。
- UART 窗口没有编码逐个按键动作，但用户随后确认新位流 SRAM 运行中的 E3 亮度、SW4 音频和快速 KEY2 实际观察均无问题；这关闭 E3/M4 闸门，不扩大为 M5 的无卡或长稳证据。

这些延迟终点是 FPGA 内部 `scene_commit`，不包括按键消抖、OSD/HDMI 整屏响应；4 个样本也不是 1000 次事件。

## 现场待完成闸门

1. 在已备份 TF 卡的前提下做无卡/错误素材注入，保存原始 COM38 JSONL；确认片上紧急提示和提示音仍可触发，watchdog fault/recovery 字段出现后能回到健康状态。不能把电源、HDMI 物理链路或 FPGA 本体故障列入本承诺。
2. 按固定矩阵收集正常轮播、TF 读中、转场中、存储超时的可审计样本；若没有自动化按键通道，记录实际人工次数，不写成 1000 次。
3. 完成至少 2 小时连续运行并保存开始/结束 UART、显示和音频观察；短窗口不能替代长时证据。
4. 复核最终 TD Setup/Hold、资源、PLL 和 CDC/复位报告；当前仍为 Setup `-6.699 ns`，因此不能称全局时序签核。

在上述现场证据完成前，M5 状态是“RTL/仿真通过，板上故障注入与 2 小时稳定性待用户确认”，不是最终稳定发布。

## 2026-10-02：当前主机下载与故障测试准备

本次由用户明确授权只读配置 Flash 备份及易失 SRAM 下载；未写入或擦除 Flash。使用 `D:\EDA\openFPGALoader\bin\openFPGALoader.exe`，两次检测均确认唯一 JTAG 目标 `0x0A014C35 / EG4S20BG256`。

- Flash 实测 JEDEC `0xef4015 / Winbond W25Q16`。`backups/before-first-sram/config-flash-2MiB.bin` 为 2,097,152 字节，SHA256 `6F285CA8872D1BFCB6EDD1C17FA3215B53B00AAD45CDCC9806CCEB8423FA3E9E`。32 个 64 KiB 分块读取成功，偏移 0、1048576、2031616 独立重读一致；该备份是本次板卡内容，不等同于历史基线备份。Flash 读取可能临时改变 FPGA SRAM 运行配置，随后已重新下载测试位流。
- 当前本机构建位流 `build-work/work.bit` 为 629,624 字节，SHA256 `B137C09D0A5698EBFADC3EA2469B1E002443991577F3FAFD6D7638C98DE69213`。用户授权后按下载指南执行 `--write-sram`，输出 `100.00% / Done`、退出码 0。日志为 `diagnostics/m5-local-pre-sram-20261002.log` 和 `diagnostics/m5-local-sram-20261002.log`；不代表 SRAM 逐位读回或实物功能验收。
- Setup WNS/TNS 仍为 `-6.699/-332.589 ns`，Hold WNS/TNS 为 `+0.003/0.000 ns`，未时序收敛；7808 LUT、5944 寄存器、20 BRAM9K、3 PLL、34 IO、0 DSP。
- 当前 CH340 为 COM8。下载后 30 秒正常基线 `diagnostics/m5-local-baseline-com8-20261002.jsonl` 收到 640 条合法状态、0 invalid；发现四张图，`sd_init/scan_done=true`，首条源/写端像素计数均为 307200，fault/recovery 均为 0。统计见 `diagnostics/m5-local-baseline-metrics-20261002.json`，没有事件延迟样本。
- 基线首条状态为 `adjust_mode=true`、`audio_enabled=false`。故障测试前须退出 SW3 调节模式，并启用 SW4 音频；无卡/错误素材注入、紧急画面和提示音现场观察、恢复验证尚未完成，不据上述正常基线关闭 M5 闸门。
- 用户现场确认：无卡状态下紧急提示画面能够出现，紧急提示音连续；提示结束后回到黑屏符合没有正常 TF 图片时的预期背景。该确认保留为“无卡时片上紧急提示/提示音能够触发”的用户观察证据；不证明画面全程稳定、普通音频连续、无卡运行中自主恢复或 M5 整体通过。后续发现视频时序受局部复位影响，不能据此排除此前报告的 UI 闪烁和普通音频断续。

### 无卡提示与重新初始化恢复记录（非运行中自主恢复证明）

- 无卡窗口 `diagnostics/m5-no-card-com8-20261002.jsonl`：640 条合法状态、0 invalid，`fault_code=1`（SD 初始化超时），fault 行 640，recovery 计数持续递增。
- 紧急窗口 `diagnostics/m5-no-card-emergency-com8-20261002.jsonl`：640 条合法状态、0 invalid，捕获 2 个事件样本；UART 场景实际为 `0→1→0→2→0`，其中 1=notice、2=emergency，两个样本不能都标为紧急；事件期间 `audio_enabled=true`、`storage_fault_active=true`，用户确认紧急画面出现且提示音连续。提示结束后无 TF 正常图片，回到黑屏属于预期背景。
- 断电、插回原 TF 卡、重新上电并下载 SRAM 后，恢复窗口 `diagnostics/m5-recovery-com8-20261002.jsonl`：640 条合法状态、0 invalid、fault 行 0、recovery 计数 0、`found_count=4`、`sd_init=true`、`scan_done=true`、`load_busy=false`；用户确认恢复后正常图片和音频均正常。
- 该记录证明无卡时片上提示可触发，以及插卡重新初始化后的正常图像和音频。由于执行了断电和 SRAM 重配置，fault/recovery 清零不证明同一运行实例自主恢复；运行中恢复、错误素材、量化及2小时运行仍待验证。第6项新发现见 `M5_STEP6_REVIEW.md`，M5 未通过。

## 第6项工程复核（2026-10-02）

检查完成但存在开放问题，未签核通过。报告 `M5_STEP6_REVIEW.md`、收据 `diagnostics/m5-step6-review-20261002.json`；用户顺序固定为 **6 → 7 → 1～3 → 4 → 5**。现有回归重新运行通过，但边界探针发现恢复复位/转场的覆盖缺口；UART 新字段 CDC 及内部 −0.720 ns Setup 路径需处理后再开展正式量化。两小时运行尚未开始。

## 第7项：当前主机 KEY2 第二窗口（2026-10-02，未关闭专项）

- 版本：`main@58f05fc`，本次 SRAM 下载的位流 SHA256 `03EF55B78AD45101AAA1416B62974EE738D4E1EC2C9F808850091C765127C049`；Setup −6.699/−295.911 ns、Hold +0.003/0 ns，时序仍未收敛。
- 原始 UART：`diagnostics/m5-step7-key2-retry2-com8-20261002.jsonl`，45秒配置采集收到896条合法状态、0 invalid。专项字段审计：`diagnostics/m5-step7-key2-retry2-audit-20261002.json`。
- KEY2看 `next_key_count`，KEY4看 `auto_key_count`；`request_count/commit_count` 是 KEY3 场景事件，不是切图计数。首次窗口经补查确认 next_key_count=0，确实没有有效KEY2变化。
- 本窗口 `next_key_count` 12→16，捕获4次计数递增；`auto_key_count` 0→2，出现轮播开/关两次。开头 adjust_mode=true，随后关闭；因此它是混合操作窗口，不是纯5次KEY2专项，不虚构第5次按键。
- 人工KEY2部分图像索引 2→3→0，快照捕获 load_busy=true 时 next_pending=true，随后 pending 被消费并再次启动写入；自动部分 0→1→2，最终 auto_play=false、load_busy=false、next_pending=false。3→0是四图正常回绕，不按“索引回退故障”处理。
- write_finish_count 11→15，共4次完成计数增长，其中包含自动轮播，不能和4次KEY2一一对应。全部fault/recovery=0，末条源/写端像素均307200。
- UART不含fade phase/level或实际video读buffer身份，不能仅由此证明按键发生在前次淡出结束前、旧buffer从未被复用或画面无永久黑场。PC记录时间还受串口缓冲分批读取影响，不能当硬件事件间隔。
- 当前结论：捕获快速请求排队与消费的有效行为，暂无存储fault/卡忙证据；混合操作、显示确认及组合仿真覆盖仍待补，不标第7项通过，不启动第5项。

## 第7项：纯 KEY2 快速连续操作窗口（2026-10-02）

- 当前位流：`main@58f05fc`，SRAM 下载后 UART 使用 COM8；Setup −6.699/−295.911 ns，仍未时序收敛。
- 原始记录：`diagnostics/m5-step7-key2-retry3-com8-20261002.jsonl`；审计：`diagnostics/m5-step7-key2-retry3-audit-20261002.json`。45 秒窗口收到 895 条合法状态、0 invalid，`next_key_count` 0→14，`auto_key_count` 保持 0，未操作 KEY4。
- 过程中捕获排队请求：`load_busy=true` 时 `next_pending=true`，前次写完成后继续执行；`image_index` 覆盖 0/1/2/3，`write_finish_count` 1→13，fault/recovery 全程为 0。
- 用户确认快速连续切图过程中无持续黑屏，最终恢复正常图片。按当前人工窗口关闭“快速 KEY2 未恢复/永久黑场”子项；不把该窗口写成1000次事件，也不据UART单独证明内部读buffer所有权或全局长期稳定性。

## 第1～3项：固定矩阵初始量化收据（2026-10-03）

初始矩阵收据为 `diagnostics/m5-quant-matrix-initial-20261003.json`，状态是 **initial_evidence_not_complete**，不能替代正式量化验收。

- 正常基线：`diagnostics/m5-local-baseline-com8-20261002.jsonl`，640条合法快照、无 fault；没有按键动作，因此不能算正常轮播事件样本。
- TF读取/快速操作：`diagnostics/m5-step7-key2-retry3-com8-20261002.jsonl`，捕获 `next_key_count` 0→14、排队和消费；这是调度器计数变化，不等于14次人工按键，也没有显式 fade-phase字段。
- 转场：当前UART没有淡变阶段/实际读buffer所有权字段，不能从快照独立生成转场延迟分布；保留为覆盖缺口。
- 存储超时：无卡窗口已覆盖 SD 初始化超时、fault/recovery；它是故障隔离证据，不是正常切图延迟样本。
- 本阶段没有1000次事件、没有可审计的独立人工次数、没有平均/P95/P99/最大完整矩阵。第4项基线对比和第5项两小时运行不启动。

## 第1～3项：正常轮播窗口（2026-10-03）

- 原始 UART：`diagnostics/m5-quant-normal2-com8-20261003.jsonl`；审计：`diagnostics/m5-quant-normal2-audit-20261003.json`。60秒收到1216条合法状态、0 invalid。
- KEY4 被捕获：`auto_key_count` 2→3，`auto_play` 从 false 变为 true；图像索引覆盖0/1/2/3，`write_finish_count` 94→104，`found_count=4`，`sd_init=true`、`scan_done=true`。
- 用户确认正常轮播期间画面连续正常、音频连续正常；窗口内 fault/recovery 为0，结束时 `load_busy=false`、`next_pending=false`、`auto_play=true`。
- 该窗口关闭“正常轮播短窗口”子项；不代表2小时稳定性、1000事件或全局时序签核。

- 用户确认该60秒正常轮播窗口画面连续正常、音频连续正常；该确认与 UART 四图/无fault 收据合并，关闭“正常轮播短窗口”子项。

## 第1～3项：纯手动重复窗口（2026-10-03）

- 原始 UART：`diagnostics/m5-quant-manual20-com8-20261003.jsonl`；审计：`diagnostics/m5-quant-manual20-audit-20261003.json`。90秒窗口收到1856条合法状态、0 invalid。
- 用户先关闭自动轮播，随后人工连续操作 KEY2；`next_key_count` 29→86（调度器计数增量57），`auto_key_count` 3→4，`auto_play` 最终为false；计数增量不强行等同物理按键次数。
- 图像索引覆盖0/1/2/3，`write_finish_count` 356→432，fault/recovery为0，最终`load_busy=false`、`next_pending=false`。
- 用户确认窗口期间画面和音频均正常、无持续黑屏。该窗口作为可审计重复人工证据；不写成1000次事件，不替代转场阶段字段或2小时稳定性。

## 第4项：官方基线可比性（2026-10-03）

对照收据：`diagnostics/m5-baseline-compare-20261003.json`。已比较官方 `build-baseline/baseline.bit` 与当前 R4 `build-work/work.bit` 的资源和 STA，但没有下载基线，也没有声称完成公平板上性能对比。

- 官方基线：3971 LUT、3790寄存器、28 IO、3 PLL，Setup WNS/TNS −6.699/−293.216 ns，Hold +0.003/0 ns。
- 当前 R4：7571 LUT、5987寄存器、34 IO、3 PLL，Setup WNS/TNS −6.699/−295.911 ns，Hold +0.003/0 ns；仍未时序收敛。
- 基线没有 M3/E1/E2/E3/M5 同口径事件协议和 UART 端点，不能公平比较响应延迟、吞吐或故障恢复；位流 hash 还包含 TD bitgen 时间字段。
- 结论：没有建立“瞬应版本相对官方基线有可量化响应优势”的证据。技术表述保持定性：当前版本增加了已验收功能和有界恢复遥测，但全局时序仍未收敛。


## 第5项长稳归档（2026-10-03，最新状态覆盖此前未开始/进行中描述）

- 已结束配置为7200秒的COM8采集，末尾有summary；接班对话未取得原进程退出码。原始首尾时间为2026-10-02 22:27:05.206563至2026-10-03 00:27:03.723084（America/Denver），样本跨度7198.516521秒，约两小时，不伪称严格满7200秒的样本覆盖。
- 143680条状态，summary invalid=0，JSON解析错误=0；四图索引0/1/2/3全覆盖，索引变化2892次，write_finish_count 432→3324；未见storage fault，恢复低位计数始终0，最终load_busy=false、next_pending=false。
- 用户于2026-10-03确认“音频有意关闭的我估计没问题，画面一直正常”。据此确认本次长稳窗口画面正常；音频为有意关闭，不将“估计没问题”当作两小时连续音频验收。
- audio_enabled=false/true分别143622/58条；auto_play=false/true分别44297/99383条。不是全程开启音频或全程自动轮播测试；快照数不是物理事件数。
- 收据：`diagnostics/m5-two-hour-audit-20261003.json`。原始`diagnostics/m5-two-hour-com8-20261003.jsonl`保留本机；因原始文件约141 MB，提交无损gzip副本`diagnostics/m5-two-hour-com8-20261003.jsonl.gz`，已解压流核对SHA256与原始一致。
- 结论：第5项本次约两小时采集及用户画面确认已归档；连续音频、严格全程自动轮播不在通过范围。随后用户确认M5现场功能验收收尾（见顶部）；完整延迟矩阵/转场观测、恢复联合验证及SDRAM/内部Setup等限制继续保留，不能视为时序或全部测试矩阵签核。
- 本次仅归档证据和文档，未改RTL/PLL/SDC、未重新构建或下载、未写Flash。下一步根据用户安排处理遗留验证或`M5_TIMING_REPAIR_TASK.md`；版本变化后重新评估相关测试。按授权本地commit，不push。
