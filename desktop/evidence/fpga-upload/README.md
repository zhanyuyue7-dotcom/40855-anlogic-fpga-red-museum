# HXFP 联合仿真产物

`vectors.bin` 和 `golden.hex` 是 `fpga_upload/tests/run_cosim.py` 生成的测试输入与软件黄金参考值，不是真实 UDP 抓包或板卡记录。

- `vectors.bin`：请求、期望响应、对端、像素计数等仿真场景编码。
- `golden.hex`：软件参考实现给出的像素地址和值，供 RTL 输出逐次比较。
- `rtl-simulation.txt`：本次真实执行 Icarus 的仿真日志。
- `rtl-receipt.json`：仿真摘要，`hardware_tested=false`；1226 个报文场景、614912 次像素写入、1 次整图提交。
- `hxfp_receiver.vvp`：Icarus 编译的仿真可执行中间文件，不是 FPGA 位流。

这些文件不能作为最终板卡已通过真实网络传图的证据。完整字节协议见 `fpga_upload/PROTOCOL.md`。
