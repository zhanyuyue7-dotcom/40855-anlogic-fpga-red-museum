"""Isolate DLL discovery from the machine's Anaconda / EDA / MSYS PATH entries."""
import argparse
import os
from pathlib import Path
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("target", choices=("studio", "receiver", "all"), default="all", nargs="?")
    parser.add_argument("--dist-dir", default="dist")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent
    env = os.environ.copy()
    windows = Path(env.get("SystemRoot", r"C:\Windows"))
    # Child process only: do not change user/system PATH or other toolchains.
    env["PATH"] = os.pathsep.join([str(Path(sys.executable).parent), str(Path(sys.base_prefix)),
                                   str(Path(sys.base_prefix) / "DLLs"), str(windows / "System32"), str(windows)])
    env.pop("PYTHONPATH", None)
    for target, name, source, mode in (("studio", "HX4S20Studio", "app.py", "--windowed"),
                                       ("receiver", "HX4S20Receiver", "receiver.py", "--console")):
        if args.target not in ("all", target):
            continue
        command = [sys.executable, "-m", "PyInstaller", "--noconfirm", "--onefile", mode,
                   "--icon", "studio.ico", "--name", name, "--paths", "../tools",
                   "--distpath", args.dist_dir, "--workpath", "build/isolated/" + target]
        if target == "studio":
            command.extend(["--add-data", "report_data;report_data"])
            command.extend(["--add-data", "../datasets/measured/long-run-72h-20261028-1031/parsed.jsonl.gz;long_run_data"])
        for excluded in ("numpy", "matplotlib", "pandas", "scipy", "IPython", "pytest", "PyQt5.QtWebEngineWidgets"):
            command.extend(["--exclude-module", excluded])
        command.append(source)
        subprocess.run(command, cwd=root, env=env, check=True)


if __name__ == "__main__":
    main()
