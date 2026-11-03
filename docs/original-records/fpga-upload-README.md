# FPGA 图片直传对接包（HXFP v1）

状态：上位机实现、应用层Verilog接收模块和协议/像素仿真已完成。**尚未接入队友最新版W5500及SDRAM顶层，尚未做TD综合/布局布线/时序和实板测试。**
本包不是可烧录位流。现有8字节UDP控制固件不会因安装新EXE而自动支持图片上传。

## 本次交付

- 上位机默认“FPGA 图片直传（HXFP）”；控制UDP端口与图片UDP端口分开，图片建议5002。
- “检测设备图片接口”只发能力查询。上传前自动再次查询，不支持时在发送像素之前停止。
- 640×480 RGB565小端、从左上角逐行发送，无BMP头，无压缩。总614400字节，常规600包。
- 会话绑定来源IP+UDP端口+会话号，单会话停止等待；每包CRC32/ACK/重传，重复最后一包不重复写。
- 整图CRC32与像素数校验；收到存储/显示端的提交确认后才返回DISPLAYED。
- 可取消未提交图片；提交请求已发出后等待确认，不把迟到的取消说成显示回滚。
- 原电脑接收服务HXIM保留在另一个明确标识的模式中，与HXFP不互通。

## 给队友的集成顺序

1. 在已正常工作的W5500工程新增一个UDP Socket，建议Socket 2 / UDP 5002；不改变已有Socket 0控制、Socket 1网页。W5500共8个Socket，但实际RX/TX内存分配必须按最新工程复核。每个最大应用数据报1044B，加W5500 UDP接收头8B，小于2KiB；收包应连续退休，不能假设环形缓冲永不回绕。
2. 把该Socket的**应用载荷**与源IP/端口交给 `rtl/hxfp_receiver.v`。原W5500 8B UDP接收头应已剥离；若旧驱动只读取固定8字节命令，必须扩展为完整数据报读取。
3. 以 `rx_ready` 控制开始交付一个报文。`rx_start` 单独一拍，随后以 `rx_valid` 交付字节，最后字节之后再单独一拍 `rx_end`。最大载荷1024B、总报文1044B。处理中 `rx_ready=0`，驱动应暂缓取下一个数据报或完整丢弃后等主机重传，不能把两个数据报拼接。
4. 保存 `rx_peer={源IPv4[31:0],源UDP端口[15:0]}`。`tx_peer` 是ACK目标。`tx_valid && tx_ready` 交付ACK字节，`tx_last` 标记第36个字节；在W5500 TX缓冲写满整个36B后执行SEND。注意ACK必须发回主机的**临时源端口**，而不是固定发到5002。
5. `frame_begin` 表示申请离屏写缓冲，只有在SDRAM初始化、旧写任务退休、目标buffer不在显示/转场读占用时才拉高 `frame_begin_ready`。为此会话保留buffer所有权，暂停/排队冲突的TF图像写入，不暂停HDMI读出。
6. `pixel_valid && pixel_ready` 写入一个RGB565像素，地址 `pixel_address=0..307199`。如现有SDRAM像素为00RRGGBB，用 `hxfp_rgb565_expand.v` 转为32位。数据已经是从上到下，不能再套BMP的 `WRITE_V_FLIP=1`，否则上下颠倒。跨域时使用真实异步FIFO，不直接跨域传多位数据。
7. 必须把写FIFO容量反馈给 `pixel_ready`。当前旧版 `frame_read_write.v` 的 `write_buf.full_flag` 没有向外引出，不能把本模块 `pixel_ready` 永久绑1；先暴露full/almost_full或使用已验证的流控接口。
8. 收到 `frame_commit` 后等待全部写入落到SDRAM（包括FIFO排空/写完成握手），再经现有帧边界/读应答契约切换显示buffer。**只有真实提交完成后**才拉高 `frame_commit_ready`。此信号不是“开始提交”请求的应答。
9. `frame_abort` 单拍丢弃当前离屏写任务、清理其FIFO并释放保留buffer，保持已有显示。`frame_error` 在帧申请/像素写入/提交等待阶段反馈存储失败。中途异常不得把未完成buffer暴露给读端。
10. 所有模块端口均属于同一个 `clk` 域。异步的网络/SDRAM/显示域由顶层使用邮箱或FIFO转换。超时默认1500000000拍，50MHz时30秒；换时钟必须调整。主机重传默认700ms×6次，实际内存申请/提交须在此预算内，或两端协同调整。

## 为什么暂不改旧版顶层

用户说明最新版以太网已正常但队友分支尚未提供。当前克隆源码没有该版HTTP/开屏/实时FFT全部实现，直接替换它的顶层不能代表对最新版完成集成。本包固定接收接口和协议，方便队友在已验证的工程接入；不生成一个冒充最新版的位流。

## 验证

在仓库 `desktop` 目录运行：

```powershell
.\.venv\Scripts\python.exe -m unittest test_desktop test_report test_fpga_transfer -v
.\.venv\Scripts\python.exe ..\fpga_upload\tests\run_cosim.py
```

本次26项软件测试通过；Icarus Verilog仿真1226个报文场景、614912次像素写入逐字核对、只提交1张正确完整图像。
RTL测试包含一张正确完整图、一张故意使用错误整图CRC的完整图、取消/超时和重复包；614912是测试期间的写入总量，不是实际设备显示了这么多像素或两张图均通过。
ACK逐字节与主机协议参考实现一致，像素接收含周期性反压、帧申请等待、提交延迟和TX反压。仿真日志位于 `desktop/evidence/fpga-upload`。

## 联调入口

```powershell
# 查询能力
.\.venv\Scripts\python.exe send_fpga_image.py 192.168.0.20 --port 5002
# 上传
.\.venv\Scripts\python.exe send_fpga_image.py 192.168.0.20 photo.jpg --port 5002
```

上位机中填板子的真实IP（不会修改板端静态IP），选择照片并上传。完整执行记录保存到 `%LOCALAPPDATA%\HX4S20Studio\transfers`。
本版提交到易失显示帧缓存；不实现写TF卡或掉电保存。需要持久素材管理时应另加TF写入、文件系统与断电一致性设计。

设备模块接入后先用四角不同色的测试图检查上下/左右顺序，再检查600包全部确认、整图CRC、帧提交ACK和HDMI实际画面。实际测试时间、版本和现象应另记，不能由本次仿真推断。
