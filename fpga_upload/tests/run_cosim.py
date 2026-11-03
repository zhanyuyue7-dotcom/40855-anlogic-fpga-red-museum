"""Cross-check host wire packets and all pixel writes against the RTL receiver."""
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import zlib

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "desktop"))
from fpga_transfer import packet, PROBE, BEGIN, DATA, COMMIT, ABORT, META, WIDTH, HEIGHT
from fpga_reference import ReferenceDevice


def main():
    output = ROOT / "desktop/evidence/fpga-upload"
    output.mkdir(parents=True, exist_ok=True)
    model = ReferenceDevice()
    vectors = bytearray()
    peer = 0xC0A800640C35
    session = 0x12345678
    samples = bytes(((i * 17 + i // 257) & 255) for i in range(WIDTH * HEIGHT * 2))
    meta = META.pack(WIDTH, HEIGHT, len(samples), zlib.crc32(samples))
    cases = []
    def add(raw, name, sender=peer, flag=0):
        if flag:
            model.expire()
            reply = None
        else:
            reply = model.handle(raw, sender)
        reply = reply or b""
        vectors.extend(struct.pack("!HBB", len(raw), len(reply), flag))
        vectors.extend(sender.to_bytes(6, "big"))
        vectors.extend(struct.pack("!II", len(model.writes), model.displayed))
        vectors.extend(raw + reply)
        cases.append(name)
    add(packet(PROBE,session,0),"capability")
    add(packet(BEGIN,session,0,meta),"begin")
    add(packet(BEGIN,session,0,meta),"lost begin ACK retry")
    add(packet(BEGIN,session+1,0,meta),"second session busy")
    add(packet(DATA,session,1,samples[:1024]),"wrong sender",sender=peer+1)
    add(packet(DATA,session,2,samples[1024:2048]),"out of order")
    damaged=bytearray(packet(DATA,session,1,samples[:1024]));damaged[-1]^=1
    add(bytes(damaged),"corrupt data discarded")
    damaged=bytearray(packet(DATA,session,1,samples[:1024]));damaged[13]^=1
    add(bytes(damaged),"corrupt sequence discarded")
    add(packet(DATA,session,1,b"abc"),"odd pixel length")
    add(packet(COMMIT,session,1),"incomplete commit")
    for i in range(0,len(samples),1024):
        seq=i//1024+1
        raw=packet(DATA,session,seq,samples[i:i+1024])
        add(raw,f"data {seq}")
        if seq in (1,7,600):
            add(raw,"lost data ACK retry")
    add(packet(COMMIT,session,601),"commit after sink confirmation")
    add(packet(COMMIT,session,601),"lost final ACK retry")
    add(packet(ABORT,session,0xFFFFFFFF),"late abort preserves displayed image")
    add(packet(BEGIN,session+1,0,meta),"new transfer")
    add(packet(DATA,session+1,1,samples[:1024]),"new transfer pixel data")
    add(packet(ABORT,session+1,0xFFFFFFFF),"cancel staged image")
    add(packet(COMMIT,session+1,2),"commit cancelled image rejected")
    add(packet(BEGIN,session+2,0,meta),"begin timeout case")
    add(b"","idle watchdog",flag=1)
    add(packet(DATA,session+2,1,samples[:1024]),"expired session rejected")
    # Full second image with intentionally wrong descriptor CRC must not commit.
    add(packet(BEGIN,session+3,0,META.pack(WIDTH,HEIGHT,len(samples),zlib.crc32(samples)^1)),"bad final CRC begin")
    for i in range(0,len(samples),1024):
        add(packet(DATA,session+3,i//1024+1,samples[i:i+1024]),"bad descriptor transfer")
    add(packet(COMMIT,session+3,601),"bad full image CRC rejected")
    add(packet(ABORT,session+3,0xFFFFFFFF),"abort checksum failure")
    (output/"vectors.bin").write_bytes(vectors)
    (output/"golden.hex").write_text("\n".join(f"{addr:08x}{pixel:04x}" for addr,pixel in model.writes),encoding="ascii")
    exe=Path(os.environ.get("IVERILOG_BIN", r"D:\EDA\iverilog\bin")) / "iverilog.exe"
    vvp=exe.with_name("vvp.exe")
    target=output/"hxfp_receiver.vvp"
    subprocess.run([str(exe),"-g2012","-s","hxfp_receiver_tb","-o",str(target),
                    str(ROOT/"fpga_upload/tests/hxfp_receiver_tb.v"),
                    str(ROOT/"src/user_source/hdl_source/network/hxfp_receiver.v"),
                    str(ROOT/"fpga_upload/rtl/hxfp_rgb565_expand.v")],check=True)
    result=subprocess.run([str(vvp),str(target),"+vectors="+str(output/"vectors.bin"),"+golden="+str(output/"golden.hex")],capture_output=True,text=True,timeout=600)
    (output/"rtl-simulation.txt").write_text(result.stdout+result.stderr,encoding="utf-8")
    print(result.stdout,result.stderr)
    if result.returncode or "PASS HXFP RTL" not in result.stdout:
        raise RuntimeError("RTL protocol simulation failed")
    receipt={"packet_scenarios":len(cases),"pixel_writes_checked":len(model.writes),"display_commits":model.displayed,
             "result":"passed", "hardware_tested":False,"cases":cases}
    (output/"rtl-receipt.json").write_text(json.dumps(receipt,indent=2),encoding="utf-8")


if __name__=="__main__":
    main()
