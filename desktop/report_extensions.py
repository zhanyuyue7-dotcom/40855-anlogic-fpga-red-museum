"""Expanded report coverage and explicitly prospective soak-test capacity budgets."""
def long_run_budget(hours, rate_hz=20, frame_bytes=64):
    if hours <= 0 or rate_hz <= 0 or frame_bytes <= 0:
        raise ValueError("Duration, rate and frame length must be positive")
    frames = int(hours * 3600 * rate_hz)
    return {"target_hours": hours, "rate_hz": rate_hz, "frame_bytes": frame_bytes,
            "planned_frames": frames, "raw_bytes": frames * frame_bytes,
            "uart_bit_rate": rate_hz * frame_bytes * 10,
            "status": "待执行", "evidence_type": "测试计划 / 容量估算",
            "measured_elapsed_seconds": None, "measured_faults": None, "passed": None}


def extend_cases(cases):
    items = [
        ("网络优化", "中断驱动唤醒", "50MHz域4拍唤醒预算", "80 ns；保留超时轮询", "理论计算复核", "报告2.3 网络优化①", "不是接收命令到显示端的总延迟"),
        ("网络优化", "255字节突发写入", "2071B首页分为9次突发", "SPI线上时间减少74.67%", "理论计算复核", "报告2.3 网络优化②", "相同载荷和SPI时钟的计算对比"),
        ("网络优化", "满载突发总线占用", "(24+255×8)/6.25MHz", "330.24 μs / 突发", "理论计算复核", "报告2.3 网络优化②", "不含调度及Socket操作等待"),
        ("网络优化", "HTTP长连接", "命令处理后保持ESTABLISHED", "keep-alive；空闲超时后释放", "报告记载", "报告2.3 网络优化③", "未获取该版本连续请求原始抓包"),
        ("网络优化", "网络事件跨域", "网络2ms事件电平；本地20ms消抖", "网络通路免除机械消抖等待", "报告记载", "报告2.3 网络优化④", "2ms电平宽度不是完整操作响应时间"),
        ("网络优化", "HTTP命令映射覆盖", "核对表3-1的请求码与动作", "n/a/p/x/e/u/d/m/v 共9项", "报告记载", "报告表3-1", "UI上额外按钮不自动视为已实现协议"),
        ("音画优化", "开屏素材容量", "223×320×240×2字节", "34,252,800 B；32.666 MiB", "理论计算复核", "报告1.4 / 2.3 开屏流", "不含文件头；不计为实际播放时长"),
        ("音画优化", "开屏2×2放大", "320×240裸帧映射640×480", "四像素复用一个源像素", "报告记载", "报告2.3 开屏流", "当前工程已集成开屏播放与图像放大模块，相关仿真见验证说明。"),
        ("音画优化", "开屏目标播放时间", "223帧 / 15fps", "理想14.8667 s", "理论计算复核", "报告1.4", "15fps为目标值；不是50次启动实测"),
        ("音画优化", "FFT频率分辨率", "48000/1024；8bin合并一带", "46.875Hz/bin；375Hz/带", "理论计算复核", "报告1.4 / 2.3 频谱", "64带覆盖至24kHz；不是实测误差"),
        ("音画优化", "FFT理论更新率", "48000样本/s ÷1024", "46.875次/s（无重叠假设）", "理论计算复核", "报告实时频谱参数", "实际更新频率还受实现调度影响"),
        ("音画优化", "提示与紧急保持", "120帧/180帧×16.8ms", "2.016 s / 3.024 s", "理论计算复核", "报告1.1 / 2.3 场景", "按显示帧周期计算，不是秒表测试"),
        ("音画优化", "亮度边界与连续条", "25/50/75/100%四档及饱和", "条宽29/58/87/116 px", "报告记载", "报告1.4 / 表3-2", "报告验收口径，本次没有重新板测"),
        ("资源优化", "四帧缓存预算", "4×640×480×4 B", "4.6875 MiB；占8MiB的58.59%", "理论计算复核", "报告2.1 / 2.2", "实现可寻址8MiB；不是裸片容量鉴定"),
        ("资源优化", "LUT使用率", "14676/19600", "74.88%；余4,924 LUT", "报告数据计算", "报告表3-3", "历史报告候选值；当前提交版本指标见验证说明。"),
        ("资源优化", "BRAM与DSP使用率", "54/64；3/29", "84.375% BRAM；10.34% DSP", "报告数据计算", "报告表3-3", "资源余量不是性能或稳定性测量"),
        ("资源优化", "Setup裕量优化", "历史候选-6.699ns→+0.310ns", "改善7.009 ns", "报告记载·构建", "报告表3-3", "不同候选的STA对比，不合并为同次实测"),
        ("资源优化", "SDRAM端点覆盖", "48写侧 + 32读侧", "全部分析；报告记载0违例", "报告记载·构建", "报告1.4 / 表3-3", "需与最终位流及完整路径报告对应"),
        ("可靠性设计", "分阶段看门狗预算", "初始化/扫描/无图/源读/写入", "3s /20s /1s /5s /5s", "报告设计值", "报告2.3 存储看门狗", "预算值不等于实际恢复耗时"),
        ("可靠性设计", "故障与音视频隔离", "超时仅复位存储子系统", "保留场景、亮度与音频设置", "报告记载", "报告2.3 存储看门狗", "电源/FPGA/HDMI物理故障不在此范围"),
    ]
    for item in items:
        group, title, method, result, evidence, source, scope = item
        cases.append(dict(id=f"T{len(cases)+1:02d}", group=group, title=title, method=method,
                          result=result, evidence=evidence, source=source, scope=scope))
    plans = [long_run_budget(hours) for hours in (8, 24, 72)]
    for plan in plans:
        cases.append(dict(id=f"T{len(cases)+1:02d}", group="长时扩展计划",
                          title=f"{plan['target_hours']}小时组合运行计划", method="20Hz×64B遥测容量预算；分阶段覆盖播放/网络/告警/恢复",
                          result=f"计划{plan['planned_frames']:,}帧；待执行", evidence="测试计划 / 容量估算",
                          source="新增测试计划；报告115200 8N1 / 20Hz / UART v3 64B",
                          scope="未执行长时板测；实测时长、故障数和通过结果均为空"))
    return {"plans": plans,
            "optimizations": [
                {"name": "首页SPI写入", "before": "10.60352 ms", "after": "2.68544 ms", "basis": "理论预算", "note": "同一2071B载荷、6.25MHz；减少74.67%"},
                {"name": "网络命令入口", "before": "机械消抖通路", "after": "2ms跨域事件", "basis": "报告实现", "note": "本地按键保留20ms；2ms不是端到端延迟"},
                {"name": "网页连接方式", "before": "Connection: close", "after": "keep-alive", "basis": "报告实现", "note": "连续请求复用连接；待对应抓包证据"},
                {"name": "Setup WNS", "before": "-6.699 ns", "after": "+0.310 ns", "basis": "报告STA", "note": "不同候选；不能等同同版长稳通过"},
                {"name": "实时频谱", "before": "预制频谱动画", "after": "1024点FFT / 64带", "basis": "设计报告功能说明", "note": "历史报告频带配置；当前工程已集成实时 FFT。"},
                {"name": "启动呈现", "before": "图片扫描/显示", "after": "223帧开屏后轮播", "basis": "设计报告功能说明", "note": "320×240裸帧；2×2硬件放大"},
            ]}
