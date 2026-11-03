"""Reference photo receiver. This executable runs on a PC, not on the FPGA."""
import argparse
from pathlib import Path
from core import ImageReceiver, data_directory


def main():
    parser = argparse.ArgumentParser(description="HXIM 照片接收服务（电脑端，不是 FPGA 固件）")
    parser.add_argument("--host", default="127.0.0.1", help="局域网接收使用 --host 0.0.0.0")
    parser.add_argument("--port", type=int, default=5001)
    parser.add_argument("--output", type=Path, default=data_directory() / "received_images")
    args = parser.parse_args()
    print("HX4S20 image receiver / HXIM v1", flush=True)
    print(f"Save to: {args.output}", flush=True)
    try:
        ImageReceiver(args.output).serve(args.host, args.port, ready=lambda addr: print(f"Listening UDP {addr[0]}:{addr[1]} (Ctrl+C to stop)", flush=True))
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
