#!/usr/bin/env python3
"""
Usage:
    python build.py <target> [--arch cct|oc|ac] [--release|--dev]

Targets:
    build
    build-mini
    build-micro
    build-test
    build-mini-test
    build-micro-test
    clean
    prod
    prod-mini

Arch flags:
    --arch cct
    --arch oc
    --arch ac

Release flags:
    --release
    --dev
"""

import sys
import shutil
import argparse
import subprocess
import json
import os
from pathlib import Path
from typing import Union

PROJECT_ROOT = Path(__file__).resolve().parent
SRC_ROOT     = PROJECT_ROOT / "Src"
TEST_ROOT    = PROJECT_ROOT / "Test"
BUILD_ROOT   = PROJECT_ROOT / "Build"
PROD_ROOT    = PROJECT_ROOT / "prod"

ARCH_BOOT_DIR = {
    "cct": Path("boot") / "cct",
    "oc":  Path("boot") / "oc",
    "ac": Path("boot") / "ac"
}


def clean():
    if BUILD_ROOT.exists():
        print(f"Removing {BUILD_ROOT} ...")
        shutil.rmtree(BUILD_ROOT)
    else:
        print("Nothing to clean.")

def cleanprod():
    if PROD_ROOT.exists():
        print(f"Removing {PROD_ROOT} ...")
        shutil.rmtree(PROD_ROOT)
    else:
        print("Nothing to clean.")


def has_minify_header(path: Path) -> bool:
    try:
        with path.open("r", encoding="utf-8", errors="ignore") as f:
            for _ in range(3):
                if "--:Minify:--" in f.readline():
                    return True
    except OSError:
        pass
    return False


def minify_file(src: Path) -> str:
    result = subprocess.run(
        ["npm", "exec", "luamin", "--", "-f", str(src)],
        capture_output=True,
        text=True
    )
    if result.returncode != 0:
        print(f"    ! luamin failed: {result.stderr.strip()}", file=sys.stderr)
        sys.exit(1)
    return result.stdout


def compress_lz4(data: bytes) -> bytes:
    return lz4.frame.compress(data)


def process_root(src_root: Path, out_root: Path, minify: bool, micro: bool, arch:Union[str, None], prod:bool):
    print(f"Building from {src_root}")
    print(f"Output to     {out_root}")
    print()

    for pkg_dir in sorted(src_root.iterdir()):
        if not pkg_dir.is_dir():
            continue

        if pkg_dir.name[:18] == "Hyperion-firmware-":
            if pkg_dir.name != f"Hyperion-firmware-{arch}":
                if prod != True:
                    continue

        data_dir=pkg_dir / "data"

        if not data_dir.is_dir():
            continue

        print(f"== Package: {pkg_dir.name} ==")

        for src in sorted(data_dir.rglob("*")):
            if not src.is_file():
                continue

            rel = src.relative_to(data_dir)       
            
            dst = out_root / rel
            if prod:
                dst = out_root / pkg_dir.name / rel
            
            dst.parent.mkdir(parents=True, exist_ok=True)

            print(f"  Processing: {src.relative_to(src_root)}")

            if has_minify_header(src):
                if minify:
                    print("    > Minifying")
                    content = minify_file(src)
                    if micro:
                        print("    > LZ4 compressing")
                        compressed = compress_lz4(content.encode("utf-8"))
                        dst.write_bytes(compressed)
                    else:
                        dst.write_text(content, encoding="utf-8")
                else:
                    print("    > Copying")
                    shutil.copy2(src, dst)
            else:
                print("    > Copying")
                shutil.copy2(src, dst)

        print()


def install_bootloader(arch: str, release: bool):
    boot_dir  = BUILD_ROOT / "root" / ARCH_BOOT_DIR[arch]
    eeprom    = boot_dir / "eeprom"

    eeprom_dst_name = "startup.lua" if release else "eeprom"
    eeprom_dst_name = "uefi.lua" if arch=="ac" else eeprom_dst_name
    print(f"  Installing: eeprom -> Build/{eeprom_dst_name}")
    shutil.copy2(eeprom, BUILD_ROOT / eeprom_dst_name)

    if arch=="cct":
        with open(BUILD_ROOT / "root/boot/fstab", "r") as file:
            content=file.read()
        with open(BUILD_ROOT / "root/boot/fstab", "w") as file:
            file.write("U root;/\n"+content)


def run_build(minify: bool, micro: bool, include_test: bool, arch: Union[str, None], release: bool, prod: bool):
    clean()
    BUILD_ROOT.mkdir()
    if prod:
        cleanprod()
        PROD_ROOT.mkdir()
    
    out_root = BUILD_ROOT / "root" if arch else BUILD_ROOT

    process_root(SRC_ROOT, out_root, minify, micro, arch, False)
    if prod:
        process_root(SRC_ROOT, PROD_ROOT, minify, micro, arch, True)
    
    if include_test:
        process_root(TEST_ROOT, out_root, minify, micro)

    if arch:
        print("Installing bootloader files ...")
        install_bootloader(arch, release)
        print()
        boot_root = out_root / "boot"
        disk_root = BUILD_ROOT / "$"
        boot_root.rename(disk_root)

    


def _make_firstboot_kmod(users):
    lines = []
    lines.append("local kernel = ...")
    lines.append("local auth = kernel.auth")
    lines.append("")

    for username, password in users:
        u = username.replace("\\", "\\\\").replace("'", "\\'")
        p = password.replace("\\", "\\\\").replace("'", "\\'")

        if username == "root":
            lines.append("do")
            lines.append("  local ok, err = auth.setPassword(0, '" + p + "')")
            lines.append("  if ok then")
            lines.append("    kernel.log('FIRSTBOOT: root password set')")
            lines.append("  else")
            lines.append("    kernel.log('FIRSTBOOT: root password error: ' .. tostring(err), 'ERROR')")
            lines.append("  end")
            lines.append("end")
        else:
            lines.append("do")
            lines.append("  local uid, err = auth.newUser('" + u + "', '" + p + "')")
            lines.append("  if uid then")
            lines.append("    kernel.log('FIRSTBOOT: created user " + u + " uid=' .. tostring(uid))")
            lines.append("  else")
            lines.append("    kernel.log('FIRSTBOOT: failed to create user " + u + ": ' .. tostring(err), 'ERROR')")
            lines.append("  end")
            lines.append("end")
        lines.append("")

    lines.append("do")
    lines.append("  local ok, err = pcall(function()")
    lines.append("    kernel.vfs.remove('/lib/modules/Hyperion/50_firstboot_users.kmod')")
    lines.append("  end)")
    lines.append("  if not ok then")
    lines.append("    kernel.log('FIRSTBOOT: could not self-delete: ' .. tostring(err), 'WARN')")
    lines.append("  end")
    lines.append("end")

    return "\n".join(lines) + "\n"


def inject_makeusers(users, arch):
    base = BUILD_ROOT / "$" if arch else BUILD_ROOT
    kmod_path = base / "lib" / "modules" / "Hyperion" / "50_firstboot_users.kmod"
    kmod_path.parent.mkdir(parents=True, exist_ok=True)
    kmod_path.write_text(_make_firstboot_kmod(users), encoding="utf-8")
    print("  Wrote first-boot user setup -> " + str(kmod_path.relative_to(BUILD_ROOT)))


def main():
    parser = argparse.ArgumentParser(description="HyperionOS build script")
    parser.add_argument("target", choices=["build", "build-mini", "build-micro", "build-test", "build-mini-test", "build-micro-test", "clean", "prod", "prod-mini"])
    parser.add_argument("--arch", choices=["cct", "oc", "ac"], default=None,
                        help="Target architecture")
    parser.add_argument("--release", dest="release", action="store_true", default=True,
                        help="Release build: eeprom placed as startup.lua (default)")
    parser.add_argument("--dev", dest="release", action="store_false",
                        help="Dev build: boot.lua and eeprom copied unchanged")
    parser.add_argument(
        "--makeuser", metavar=("USERNAME", "PASSWORD"), nargs=2, action="append",
        default=[],
        help=(
            "Pre-create a user on first boot (dev builds only). "
            "May be specified multiple times. "
            "Example: --makeuser root secretpass --makeuser alice alicepass"
        ),
    )

    args = parser.parse_args()

    if args.makeuser and args.release:
        parser.error("--makeuser is only allowed with --dev builds")

    if args.target == "clean":
        clean()
        return

    prod         = "prod" in args.target
    minify       = "mini" in args.target or "micro" in args.target
    micro        = "micro" in args.target
    include_test = "test" in args.target

    if micro:
        import lz4.block
    
    run_build(minify=minify, micro=micro, include_test=include_test, arch=args.arch, release=args.release, prod=prod)

    if args.makeuser:
        print("Injecting first-boot user setup ...")
        inject_makeusers(args.makeuser, args.arch)
        print()

    print("Build complete.")


if __name__ == "__main__":
    main()