交付目录：`D:\Downloads\FPGA\shunying-hx4s20-fpga\desktop\dist\w5500`

# Windows 上位机交付记录

日期：2026-11-01。仓库起点：14f840bb7b2482331d1a4434f8d6304b3b664311。

- 实现：深蓝色原生 Qt 窗口、UART 接收、三个采集/停止/CSV 主按钮、状态面板、数据表、速率曲线、照片转换与预览、UDP 控制、HXIM 照片传输。
- 工具链：本机 Python 3.12.10 + 项目独立 .venv，PyQt5 5.15.11 / Qt 5.15.2，pyserial 3.5，Pillow 12.1.1，PyInstaller 6.18.0。
- 26 项自动测试通过；新增HXFP设备图片能力查询、头部/载荷CRC、重传、取消、提交确认及Qt操作。
- HXFP Verilog仿真1226个报文场景、614912次像素写入核对通过；配套模块尚未集成队友最新版W5500/SDRAM顶层，未进行TD综合/时序或实板验收。
- 新版EXE的HXFP发送功能已对localhost软件参考设备完成整图验证，不把软件参考设备回包作为实板成功。
- 新增42项测试档案、146253条历史原始状态、优化成果对比和8/24/72小时待执行容量计划。6张截图来自打包后EXE。历史实测时长未扩写；未执行计划不标通过。
- 主 EXE 已在非源码工作目录成功启动并截图；接收 EXE 已在临时目录成功接收 921654 字节 BMP，与发送文件逐字节一致。
- 未进行 FPGA 实板测试。只枚举到蓝牙 COM25/COM26，未打开物理串口、向板子发命令或进行烧录。
- 新增FPGA应用层接收RTL位于fpga_upload；现有主工程RTL未改。没有发布新位流或宣称TF持久保存。
- 未提交或推送；本次代码保留在工作区供检查。

## 产物

主程序：`dist/HX4S20Studio.exe`；配套接收程序：`dist/HX4S20Receiver.exe`。

便携压缩包：`dist/HX4S20Studio-Windows-x64.zip`。详细说明见 README.md，机器收据见 dist/verification.json。

## SHA-256

- `HX4S20Studio.exe` (48,418,990 bytes): `acbbc9b043389c169447ed94e66ab4ce4176bab0aa8d32a49fc4de055844f6ee`
- `HX4S20Receiver.exe` (16,623,838 bytes): `2b55e524ecd43ecbea176a2a39bcacb189edb53695d48a16edbae4d6ba8c793b`
- `HX4S20Studio-Windows-x64.zip` (67,662,069 bytes): `2dfa64aaa91f77a731ef6334d09f8da390cf160a47242fd51dca3175d0fdfc13`
