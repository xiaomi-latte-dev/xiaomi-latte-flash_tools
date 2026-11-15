#!/bin/sh
# 从 shim 的 .vendor_cert 段提取内嵌证书（PEM）。
# shim 用这张证书校验它要加载的第二个阶段（grubx64.efi），
# 因此判断 grub 是否「已被 shim 认可」应以它为准，而不是本机系统密钥环。
set -eu

shim=$1
out=$2
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

[ -f "$shim" ] || { echo "shim 不存在: $shim" >&2; exit 1; }
command -v objcopy >/dev/null 2>&1 || { echo "缺少 objcopy（binutils）" >&2; exit 1; }

# 重要：objcopy --dump-section 省略输出文件时会就地重写输入文件，剥掉 PE 里的
# Authenticode 签名。所以必须对副本操作，并显式给出输出文件。
cp "$shim" "$work/shim.efi"
objcopy --dump-section ".vendor_cert=$work/vendor.bin" "$work/shim.efi" >/dev/null 2>&1 || {
	echo "无法从 $shim 提取 .vendor_cert 段" >&2
	exit 1
}

# 段内容为若干头部字段 + 一个 X.509 DER，直接定位 SEQUENCE 标记。
python3 -c 'import sys; d=open(sys.argv[1],"rb").read(); i=d.find(b"\x30\x82"); sys.exit(1) if i < 0 else open(sys.argv[2],"wb").write(d[i:])' "$work/vendor.bin" "$work/vendor.der" || {
	echo "vendor 段内未找到证书" >&2
	exit 1
}

openssl x509 -inform DER -in "$work/vendor.der" -out "$out" 2>/dev/null || {
	echo "证书解析失败（$shim）" >&2
	exit 1
}
echo "已提取 shim vendor 证书: $out"
