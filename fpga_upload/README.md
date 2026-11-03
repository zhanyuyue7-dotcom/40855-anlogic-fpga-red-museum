# HXFP v1 协议与联合仿真

当前提交版已经把接收器集成到正式 FPGA 工程，顶层通过 W5500 Socket 2 / UDP 5002、异步 FIFO 和 SDRAM 帧桥完成图片路径。正式接收 RTL 是 `../src/user_source/hdl_source/network/hxfp_receiver.v`；本目录 `rtl/hxfp_receiver.v` 保留为 donor 参考，不能替代当前正式文件。

精确协议见 `PROTOCOL.md`。联合仿真命令为：

```powershell
& ./desktop/.venv/Scripts/python.exe fpga_upload/tests/run_cosim.py
```

从提交目录根部执行；可用环境变量 IVERILOG_BIN 指定 Icarus 安装目录。该脚本实际编译正式集成接收器，并把软件报文和像素黄金值与 RTL 对照。本次通过 1226 个场景、614912 次像素写入、1 次正确整图提交。

产物在 `../desktop/evidence/fpga-upload/`。输入向量是生成的测试输入，运行日志是本机仿真证据，不是真实以太网抓包或板测。最终位流、构建、SRAM 历史回执见根目录 README。

当前真实网络整图入板验收仍待补，验证范围见 `../docs/验证结果与边界.md`。
