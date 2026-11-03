# 照片传输协议 HXIM v1

这是本次上位机新增的协议，仅由 `desktop/core.py:ImageReceiver` / `HX4S20Receiver.exe` 实现。
当前 `w5500_udp_ctrl.v` 和 `w5500_command_decoder.v` **未实现**它；现有板端仍只接收 8 字节控制帧。

## 帧格式

每个 UDP 数据报包含 20 字节头及有效载荷。所有多字节整数字段为网络字节序（大端）。

| 偏移 | 大小 | 含义 |
|---|---:|---|
| 0 | 4 | ASCII `HXIM` |
| 4 | 1 | 版本，固定 1 |
| 5 | 1 | 类型：HELLO=1、DATA=2、FINISH=3、ACK=128、ERROR=129 |
| 6 | 4 | 随机 transfer ID |
| 10 | 4 | 包序号 |
| 14 | 2 | 载荷字节数 |
| 16 | 4 | 载荷 CRC32，与 Python zlib.crc32 一致 |
| 20 | N | 载荷 |

1. HELLO：seq=0，UTF-8 JSON：`name,size,sha256,width,height`。当前要求 640×480 RGB BMP，大小上限 2 MiB。
2. DATA：seq 从 1 递增；每包至多 1024 字节。
3. FINISH：seq=最后 DATA 序号+1，空载荷。
4. ACK：同 transfer ID / seq；载荷第一个字节是被确认的帧类型。
5. ERROR：同 transfer ID / seq；UTF-8 原因文本。

发送端每包等待 ACK，默认超时 350 ms，最多发送 6 次。只有类型、ID 和序号匹配才算确认。
接收端对重复 DATA 重发 ACK，不重复追加；FINISH ACK 丢失后支持重复确认，避免误报失败或重复写文件。
FINISH 时校验总大小、SHA-256、BMP 实际尺寸和色彩模式，通过临时文件原子替换保存后才发送成功 ACK。
接收文件使用服务端生成名称，忽略远端路径。最多 8 个活动传输，每个上限 2 MiB，30 秒不活动后失效。

协议为可信局域网工具设计，不提供认证、加密、断点续传或板上显示语义。取消或失败不会提交不完整 BMP。
将它移植到 FPGA 需要新增协议解析、校验、流控、存储写入与帧提交，并单独验证资源和时序。

## 现有 FPGA 控制协议（保持原样）

`A5 01 SEQ OPCODE 00 00 00 CRC8`

CRC8 覆盖前 7 字节，多项式 0x07，初值 0，不反射，最终异或 0。
OPCODE：0x10 下一张、0x11 轮播切换、0x12 提示、0x13 清除、0x14 亮度增加、0x15 亮度降低。
此协议没有 ACK；主机不自动重传切换命令，以免重复动作。
