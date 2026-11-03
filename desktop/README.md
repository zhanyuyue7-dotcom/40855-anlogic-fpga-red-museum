# 红色数字展馆上位机（当前提交版）

本目录是 Python / Qt 源码，包含 UART 采集、状态存储与 CSV 导出、图片格式转换、UDP 控制、HXFP 图片直传和历史测试档案。原交付记录保存于 `../docs/original-records/desktop-README.md`。

当前 FPGA 已集成 HXFP 接收器、W5500 Socket 2 和 SDRAM 帧桥，最终位流见 `../bitstream/integrated.bit`。当前桌面软件32项测试通过；真实以太网图片端到端板测仍待验证。

从根目录建立 `desktop/.venv`，安装 `requirements.txt`，运行 `desktop/app.py`。完整命令见 `../docs/构建与复现.md`。需要 EXE 时使用 `build_windows.py all`；此代码附件不捆绑 EXE 或虚拟环境。

- UART：选择实际端口，115200 / 8N1，自动解析历史 M3 v1/v2/v3。
- FPGA 图片：HXFP v1，UDP 5002；640×480 RGB565、CRC32、逐包确认与重传，只有 DISPLAYED 确认后才到 100%。
- FPGA 控制：UDP 5000；无控制 ACK 的命令通过板端状态或实际动作确认执行结果。
- 电脑照片接收：HXIM 用于电脑端照片接收，服务入口为 `receiver.py`；HXFP 用于 FPGA 图片传输。
- 网络地址：填写实际板端 IPv4；改输入框不会修改 FPGA 内部静态地址。
- “测试档案/历史回放”默认展示最终版本72小时实测（5,184,000条状态），支持真实快照回放、分钟趋势和完整CSV导出。旧M3/M5会话单独保留，详见 `REPORT_GUIDE.md`。

开始采集会在本机应用数据目录创建会话；操作网络按钮会实际发包。仅浏览历史档案不会打开串口或联系硬件。
