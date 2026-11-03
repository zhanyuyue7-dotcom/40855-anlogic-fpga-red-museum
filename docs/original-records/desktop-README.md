# HX4S20 Studio — Windows 上位机

深蓝色原生 Qt 桌面应用。针对本仓库实际 UART / W5500 协议开发，无需浏览器。

## 打开应用

### 图片直传发送端更新（2026-11-01）

用户已确认队友完成板端图片接收和 HDMI 上屏。以下旧版顶层的集成说明仍针对本地历史源码，不能代表队友当前固件状态；使用发送器时选择实际板端 IPv4 和 HXFP 图片端口。

- GUI 新增“显示确认等待”（默认每次 3 秒，最多 6 次）；数据包确认仍默认每次 0.7 秒，避免较慢的 SDRAM 写入收尾/帧边界提交过早超时。
- 像素收齐只到 99%，收到整图 CRC32、长度和 DISPLAYED 确认后才到 100%。提交后结果不明时保存 `commit_result_unknown`，不宣称撤回已显示图片。
- 打包 EXE 可用 `--send-image photo.jpg --device-ip 192.168.0.20 --image-port 5002 --ack-timeout 0.7 --commit-timeout 3 --attempts 6`。这几个超时是每次请求的等待时间；原有 HXFP 线协议不变。
- 本轮本机软件回归 30 项通过，包括独立提交等待、异常 BEGIN 确认拒绝、等待显示时 GUI 99% 状态。板端接收/上屏通过来自用户确认，本轮本机未再次访问物理板卡。

双击 `HX4S20Studio.exe`，无需安装 Python。首次启动单文件 EXE 会解压运行组件，可能需要数秒。

源码入口 `desktop/app.py`；本机最终打包使用已安装的 Python 3.12.10 和项目独立 `.venv`，依赖为 PyQt5 / pyserial / Pillow / PyInstaller。

## 功能与兼容边界

### 新增：FPGA 图片直传（HXFP）

上位机默认选择“FPGA 图片直传（HXFP）”。填板子真实IPv4，图片端口默认UDP5002，点击“检测设备图片接口”或直接上传。
照片转为640×480 RGB565，614400B；自动能力查询、CRC32校验、分包确认/重传、取消与最终显示提交确认。
只有设备回复完整CRC和DISPLAYED，上位机才显示完成。原控制端口5000与图片端口分别配置。

**设备固件必须先接入随附的HXFP接收模块。** 最新队友分支尚未提供，本次只完成上位机与配套应用层接收RTL及仿真，未集成到旧版顶层或生成新位流。仅确认以太网控制正常，不代表板子已支持新图片协议。
队友对接说明在仓库 `fpga_upload/README.md`，分发包内有“FPGA图片直传对接包.zip”。
本功能提交到显示帧缓存，不提供TF持久保存；每次成功/失败/取消记录在 `%LOCALAPPDATA%\HX4S20Studio\transfers`。

命令行也可使用打包EXE：

```powershell
.\HX4S20Studio.exe --send-image photo.jpg --device-ip 192.168.0.20 --image-port 5002
```

以下原有模式与说明保留供兼容使用。

| 功能 | 当前实现 |
|---|---|
| 开始采集 / 停止采集 | 打开 / 关闭本机 UART 接收；不发送 FPGA 控制字，不停止 FPGA 自身运行 |
| UART 状态 | 复用仓库 M3 v1/v2/v3 二进制解析器，支持 Lab4 @S 文本及原始 HEX |
| 实时面板 | 场景、图片索引、亮度、音频、SD 初始化、轮播、故障、无效帧、接收速率 |
| CSV 导出 | 导出当前会话全部已保存记录；UTF-8 BOM，Excel 可直接打开；采集过程中可导出一致性快照 |
| 数据保存 | 每次开始建立独立 SQLite 会话及 `.raw.bin` 原始字节记录；屏幕仅显示最近 300 条 |
| FPGA 以太网控制 | 原固件 A5/01 + CRC8 UDP 命令：下一张、轮播切换、提示、清除、亮度加减 |
| 照片准备 | JPG/PNG/BMP/WebP → 640×480 无压缩 24-bit BMP；留边、裁剪、拉伸；预览和另存 |
| FPGA 图片直传 | HXFP v1，RGB565、CRC32、ACK/重传、取消、显示提交确认；需板端集成配套模块 |
| 电脑照片传输 | HXIM v1 UDP 分包、ACK、重传、取消、SHA-256 完整性校验；配套电脑接收服务 |

**当前仓库 FPGA 固件没有照片接收 / 写入 SDRAM 或 TF 卡的数据路径。**
当前主工程尚未集成新增HXFP模块。新EXE已经提供设备直传；只有设备回应能力和显示提交确认才会判定完成。
“FPGA 旧版控制”模式禁用照片上传；“电脑照片接收服务（HXIM）”用于电脑收图；“FPGA 图片直传（HXFP）”用于接入了配套模块的板子。
板端仍须完成W5500 UDP收发、缓存所有权、FIFO反压和帧边界提交的集成，再做构建、时序及硬件验证。

现有 FPGA 控制协议没有 ACK；“命令已发送”只证明本机发包成功，设备执行情况以 UART 或板上效果为准。

## 串口采集

新增“测试档案 / 历史回放”入口，提供42项测试索引、146253条历史状态、事件延迟、后续优化与8/24/72小时待执行计划。无需连接硬件。详情见 `REPORT_GUIDE.md` / 便携包内“测试档案与配图说明.md”。

1. 接入板子的 USB-UART，点击“刷新串口列表”，手动选择正确 COM 口。
2. 仓库默认 **115200 / 8N1**，解析协议默认“自动识别”。
3. 点击“开始采集”。收到有效帧后显示状态；超过 3 秒无有效帧会提示状态可能过期。
4. 点击“停止采集”关闭串口。点击“导出成 CSV”保存当前会话。
5. 再次开始会建立新会话；此前会话仍在磁盘，不会被覆盖。

数据目录：`%LOCALAPPDATA%\HX4S20Studio\sessions`。
所有有效帧（包括重复心跳）均保存。原始字节记录另存，便于解析失败时回查。
M3 v1 没有图片/亮度等字段，界面显示“—”；v2 没有 v3 的亮度/音频/故障字段，不伪造状态。

恢复旧会话 CSV（源码环境）：

```powershell
python -c "from core import SessionStore; SessionStore(r'C:\path\capture.sqlite3').export_csv(r'C:\path\recovered.csv')"
```

## FPGA 以太网控制

默认 IP 来自当前 RTL：`172.22.115.79`，UDP `5000`。这是仓库里的临时校园网配置，不自动适配本机网络。
电脑须能路由到板子的实际 IP。上位机里修改 IP 只改变发送目标，不会修改 FPGA 的静态地址。
选择“FPGA 旧版控制”或“FPGA 图片直传（HXFP）”后使用左侧六个控制按钮。

## 照片传输快速验证

本机验证：

1. 双击 `HX4S20Receiver.exe`，默认监听 `127.0.0.1:5001`。
2. 上位机选择“电脑照片接收服务（HXIM）”，IP 填 `127.0.0.1`，UDP端口填 `5001`。
3. 选择照片，点击“通过以太网上传”。100% 表示接收端已完成文件校验及落盘。
4. 接收到的 BMP 位于 `%LOCALAPPDATA%\HX4S20Studio\received_images`。

两台电脑通过以太网传输，在接收电脑执行：

```powershell
.\HX4S20Receiver.exe --host 0.0.0.0 --port 5001 --output D:\HX4S20-Photos
```

发送端填接收电脑的局域网 IPv4 和端口 5001。若 Windows 防火墙询问，按实际测试网络允许该接收程序。
接收服务用于可信本地网络，未实现身份认证或加密；关闭接收程序即停止监听。

## 开发与打包

```powershell
cd desktop
python -m pip install -r requirements.txt
python app.py
python -m unittest test_desktop -v
powershell -ExecutionPolicy Bypass -File .\build.ps1
python verify_bundle.py
python package_release.py
```

产物位于 `desktop/dist/`。源码模式还需要上级 `tools/m3_telemetry.py` 和 `tools/lab4_telemetry_server.py`。
打包时两份仓库解析器会被自动包含，不需要把源码文件放在 EXE 旁边。
`build.ps1` 优先选用 `.venv\Scripts\python.exe`；`build_windows.py` 仅为打包子进程设置独立 DLL 搜索路径，不修改系统 PATH。

测试覆盖：CRC 命令帧、M3 三版本分片/坏帧恢复、Lab4 分行、HEX、CSV 完整记录、BMP 格式、
真实 UDP 本地传输与 HELLO/DATA/FINISH 丢 ACK 重传、超时、取消、Qt 采集启停/导出及串口占用错误。
这些软件测试不等于 FPGA 板上验收。开发时本机只枚举出蓝牙 COM25/COM26，未自动打开任何物理端口。
