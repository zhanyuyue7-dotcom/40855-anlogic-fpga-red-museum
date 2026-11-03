"""CLI for actual device uploads; target must implement HXFP/1."""
import argparse
from core import prepare_image
from fpga_transfer import probe_device, upload_to_fpga


def main():
    parser=argparse.ArgumentParser(description="HXFP FPGA图片直传")
    parser.add_argument("host")
    parser.add_argument("image",nargs="?")
    parser.add_argument("--port",type=int,default=5002)
    parser.add_argument("--ack-timeout",type=float,default=.7)
    parser.add_argument("--commit-timeout",type=float,default=3.0)
    parser.add_argument("--attempts",type=int,default=6)
    args=parser.parse_args()
    if not args.image:
        print(probe_device(args.host,args.port))
    else:
        result=upload_to_fpga(args.host,args.port,prepare_image(args.image),args.image,
                              timeout=args.ack_timeout,commit_timeout=args.commit_timeout,retries=args.attempts,
                              stage=print,progress=lambda n,total: print(f"{n}/{total}") if n%65536==0 else None)
        print(result)


if __name__=="__main__":
    main()
