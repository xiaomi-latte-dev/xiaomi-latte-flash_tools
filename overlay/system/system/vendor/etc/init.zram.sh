#!/vendor/bin/sh

# Copyright (c) 2012-2013, 2016-2021, The Linux Foundation. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#     * Redistributions of source code must retain the above copyright
#       notice, this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in the
#       documentation and/or other materials provided with the distribution.
#     * Neither the name of The Linux Foundation nor
#       the names of its contributors may be used to endorse or promote
#       products derived from this software without specific prior written
#       permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NON-INFRINGEMENT ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR
# CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
# PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
# OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
# WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
# OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
# ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#

function configure_zram_parameters() {
    MemTotalStr=`cat /proc/meminfo | grep MemTotal`
    MemTotal=${MemTotalStr:16:8}

    low_ram=`getprop ro.config.low_ram`

    # Zram disk - 75% for Go devices.
    # For 512MB Go device, size = 384MB, set same for Non-Go.
    # For 1GB Go device, size = 768MB, set same for Non-Go.
    # For 2GB Go device, size = 1536MB, set same for Non-Go.
    # For >2GB Non-Go devices, size = 50% of RAM size.
    # For >8GB Non-Go device, size = 25% of RAM size. 
    # For Non-Go, Limit the size to 4GB if not x86_64.
    # And enable lz4 zram compression for Go targets.

    let RamSizeGB="( $MemTotal / 1048576 ) + 1"
    diskSizeUnit=M
    if [ $RamSizeGB -le 2 ]; then
        let zRamSizeMB="( $RamSizeGB * 1024 ) * 3 / 4"
    else
        let zRamSizeMB="( $RamSizeGB * 1024 ) / 2"
    fi

    if [ $RamSizeGB -gt 8 ]; then
        let zRamSizeMB="( $RamSizeGB * 1024 ) / 4"
    fi

    # use MB avoid 32 bit overflow if not x86_64
    if [ "$(uname -m)" != "x86_64" ] && [ $zRamSizeMB -gt 4096 ]; then
        let zRamSizeMB=4096
    fi

    # 显式固定为 lz4，不依赖内核默认值。
    #
    # Airmont（Atom x5-Z8500）单核性能弱，zstd 的压缩速度只有 lz4 的
    # 一半左右，每次换页都会明显拖慢前台；内核默认已改为 lz4
    # （CONFIG_ZRAM_DEF_COMP="lz4"），这里再显式写一次保证行为确定。
    # 原脚本只在 ro.config.low_ram=true 时才设 lz4，本机该属性为空。
    echo lz4 > /sys/block/zram0/comp_algorithm

    if [ -f /sys/block/zram0/disksize ]; then
        if [ -f /sys/block/zram0/use_dedup ]; then
            echo 1 > /sys/block/zram0/use_dedup
        fi
        echo "$zRamSizeMB""$diskSizeUnit" > /sys/block/zram0/disksize

        # ZRAM may use more memory than it saves if SLAB_STORE_USER
        # debug option is enabled.
        if [ -e /sys/kernel/slab/zs_handle ]; then
            echo 0 > /sys/kernel/slab/zs_handle/store_user
        fi
        if [ -e /sys/kernel/slab/zspage ]; then
            echo 0 > /sys/kernel/slab/zspage/store_user
        fi

        mkswap /dev/block/zram0
        swapon /dev/block/zram0 -p 32758
    fi

    # Set swappiness
    echo 80 > /proc/sys/vm/swappiness
}

# import cmdline variables
# 只取本脚本真正需要的 DISABLE_ZRAM。
# 原实现用 eval $c 展开 /proc/cmdline 每一项，遇到 GRUB 注入的
# BOOT_IMAGE=(hd0,gpt1)/EFI/BlissOS/vmlinuz 会直接语法错误，脚本当场
# 退出，zram 永远不会被配置。
for c in `cat /proc/cmdline`; do
	case $c in
		DISABLE_ZRAM=*)
			DISABLE_ZRAM=${c#DISABLE_ZRAM=}
			;;
	esac
done

# Disable ZRAM if wanted
if [ "$DISABLE_ZRAM" != "1" ]; then
    configure_zram_parameters
fi
