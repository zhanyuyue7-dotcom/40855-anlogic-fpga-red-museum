# 帧缓冲桥仿真波形

`hxfp-frame-bridge.vcd` 由 Icarus 实际执行原有自检查帧桥测试生成，不是板卡逻辑分析仪采集。测试涉及缓冲申请、RGB 布局、真实 vendor FIFO、写入排空、VS/读应答提交、取消和 TF 恢复。运行结果见 `simulation.log`。

在审核目录根部复现：

```powershell
& 'D:/EDA/iverilog/bin/iverilog.exe' -g2012 -s submission_waveform_tb -o diagnostics/submission-waveform.vvp tests/submission_waveform_tb.v tests/hxfp_frame_bridge_tb.v src/user_source/hdl_source/network/hxfp_frame_bridge.v src/user_source/hdl_source/IP/afifo_16_32_256.v
& 'D:/EDA/iverilog/bin/vvp.exe' diagnostics/submission-waveform.vvp
```

可用 GTKWave 打开 `.vcd`；查看 `submission_waveform_tb.dut` 下信号。完整系统 HDMI 加密 IP 不在本波形范围内。
