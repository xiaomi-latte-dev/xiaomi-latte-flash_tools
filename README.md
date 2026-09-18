# xiaomi-latte-flash_tools

[English](README.md) | [简体中文](README.zh-CN.md)

Build and flash toolkit for running custom **Android-x86** images on the
**Xiaomi Mi Pad 2** (`latte`, Intel Cherry Trail / x86_64 tablet).

It takes an official Android-x86 based ISO (BlissOS, LineageOS, ProjectSakura, ...),
a prebuilt `zenith` kernel, and a set of device-specific overlays, and produces
fastboot-flashable partition images (`gpt.bin`, `boot.img`, `system.img`, `data.img`).

## Features

- **Alternative boot path via SHIM/GRUB** — bundles Fedora `shim` + `grub2-efi` into
  `boot.img`, bypassing the stock `fastboot.efi` loader. Unlike the original firmware, which
  can only boot the stock Android-IA image, GRUB can boot Linux, Windows and Android-x86 —
  any UEFI OS.
- **Multi-release support** — one `VER=` switch selects the source ISO, the matching
  initrd patch and the system-image compression (see [version table](#supported-versions)).
- **Device overlays** — patched ACPI DSDT, capacitive-key remapping, Broadcom BCM4356
  Wi-Fi/Bluetooth firmware, ALSA UCM for the RT5659 codec, and a default
  locale/timezone/DPI configuration.
- **USB gadget networking + SSH** — ECM/RNDIS gadget with a built-in `dnsmasq` DHCP server
  and a `dropbear` SSH daemon reachable at `192.168.255.1`.
- **Flexible image formats** — `system.img` as `erofs` or `squashfs` (auto-selected),
  `data.img` as `f2fs` or `ext4`, plus an optional sparse `data.simg`.
- **Host-side testing** — run the built images in QEMU/KVM, or mount them for inspection.
- **One-click flashing (Windows)** — `DNX_flash_*.bat` scripts with device-model checking.

## Prerequisites

- A Linux host for building (root/`sudo` is required for loop mounts), or Windows for
  flashing only.
- On the tablet: the ability to boot the bundled UEFI fastboot. The device has no Android
  bootloader; `fastboot.efi` is the UEFI fastboot used to flash it, and Android-IA's secure
  boot chain takes that role.
- Host packages used by the makefile:

  ```bash
  # Debian/Ubuntu package names (adjust for your distro)
  sudo apt install wget p7zip-full squashfs-tools f2fs-tools erofs-utils \
       gcc acpica-tools rpm cpio patch libguestfs-tools
  ```

  Optional extras:
  - `qemu-system-x86`, `qemu-utils`, `ovmf` — required for the `qemu` / `qemu-iso` targets.
  - `android-sdk-libsparse-utils` (`img2simg`) — enables the sparse `data.simg` output.
  - `rpm2cpio` (from `rpm`) — required to unpack the `shim` / `grub2-efi` RPMs.

## Input files

Place the required files in the repository root. The makefile discovers them by glob
pattern, so the names must match:

| File | Pattern | Notes |
| --- | --- | --- |
| Source ISO | `*<VER>*-*.iso` | e.g. `Bliss-v14.10.3-x86_64-OFFICIAL-foss-20241012.iso` for `VER=14` |
| Source ISO (`VER=5`) | `ProjectSakura-5.*.iso` | special-cased in the makefile |
| Kernel package | `kernel-*-zenith.tar.gz` | extracts `lib/modules/<kernel>` |
| shim RPM | `shim-x64.rpm` | downloaded automatically if missing |
| grub2 RPM | `grub2-efi-x64.rpm` | downloaded automatically if missing |

Example downloads:

- BlissOS: <https://sourceforge.net/projects/blissos-x86/files/>
- LineageOS for x86: <https://sourceforge.net/projects/lineageos-for-x86/files/>
- `zenith` kernels: <https://github.com/Qs315490/android-x86-kernel-latte/actions>

```bash
# BlissOS 14.10.3 example (VER=14)
wget -O Bliss-v14.10.3-x86_64-OFFICIAL-foss-20241012.iso \
  "https://sourceforge.net/projects/blissos-x86/files/Official/BlissOS14/FOSS/Generic/Bliss-v14.10.3-x86_64-OFFICIAL-foss-20241012.iso/download"

# Kernel package (zenith series)
wget -O kernel-6.12.30-zenith.tar.gz \
  "https://github.com/Qs315490/android-x86-kernel-latte/releases/download/..."
```

## Supported versions

`VER` defaults to `14` and must be one of the values below (taken from the makefile):

| `VER` | Android-x86 release | Kernel |
| --- | --- | --- |
| `17.1` | LineageOS 17.1 (Android 10) | `5.8.0-android-x86_64` |
| `5` | ProjectSakura 5.2 (Android 11) | `5.10.61-GoogleLTS-xanmod1-pledge` |
| `14` | BlissOS 14.10.x (Android 11) | `6.1.112-gloria-xanmod1` / `6.6.102-crimson-xanmod1` |
| `15` | BlissOS 15 (Android 12) | `6.1.112-gloria-xanmod1` |
| `16` | BlissOS 16 (Android 13) | `6.1.112-gloria-xanmod1` |
| `17.2` | BlissOS Zenith 17.2 (Android 14) | `6.7.10-zenith-xanmod1` |
| `18` | BlissOS 18.4 (Android 15) | `6.6.89-crimson-xanmod1` |
| `21` | LineageOS 21.1 (Android 14) | `6.12.30-zenith` |

## Boot chain

The stock firmware boots only its own Android-IA image through `fastboot.efi`.
This project lays down an alternative UEFI boot path inside `boot.img`:

1. **SHIM** (`shimx64.efi` / `bootx64.efi`) - a Fedora *signed* first-stage
   loader. In this setup it is launched directly from the EFI boot entry, so the tablet
   boots the SHIM/GRUB chain **instead of** `fastboot.efi`.
2. **GRUB** (`grubx64.efi`) - renders the boot menu and loads the kernel + initrd.
   This is the key difference from the original firmware: GRUB can boot **any UEFI OS**
   (Linux, Windows, Android-x86, ...), not just the stock Android-IA image.
3. **MOK** (`MOK.cer` / `MOK.crt` / `MOK.key`) - Machine Owner Key.
   Enrolling it lets the chain load correctly **while UEFI Secure Boot stays enabled**;
   without it, Secure Boot would reject the unsigned GRUB and kernel.
4. **setup_var.efi** - a small UEFI utility to read/write hidden firmware (BIOS) settings
   exposed only as EFI variables (e.g. the OTG toggle in the GRUB *Power* submenu).


## Build

```bash
# Build every image (gpt.bin, boot.img, system.img, data.img) for the default VER=14
make

# Pick a specific release
make all VER=21

# Show the full command lines
make all VER=21 V=1
```

Override the image sizes when needed:

```bash
make all VER=21 BOOT_SIZE=64 DATA_SIZE=4096
```

Products are written to `images-<VER>/` (e.g. `make VER=21` → `images-21/`).

### Build variables

See [MAKEFILE_VARS.md](MAKEFILE_VARS.md) for the full, detailed reference of every makefile
variable. The most useful ones:

| Variable | Default | Description |
| --- | --- | --- |
| `VER` | `14` | Target release, drives ISO selection, initrd patch and compression |
| `BOOT_SIZE` | `64` | `boot.img` (ESP/FAT32) size in MiB |
| `DATA_SIZE` | `2048` | `data.img` size in MiB |
| `V` | `0` | `V=1` prints every command the makefile runs |

### Make targets

| Target | Description |
| --- | --- |
| `all` | Build `gpt.bin`, `boot.img`, `system.img`, `data.img` |
| `gpt.bin` | Generate the GPT from `device_files/gpt.ini` |
| `boot.img` | Build the 64 MiB FAT32 ESP holding shim + GRUB + kernel + initrd |
| `system.img` | Unpack the ISO system image, apply overlays, repack with erofs/squashfs |
| `data.img` | Create the `data` partition (f2fs if available, else ext4) + sparse `data.simg` |
| `unpack_iso` / `unpack_initrd` / `unpack_system` | Unpack the corresponding source |
| `unpack_shim_grub` / `unpack_kenrel` | Unpack the shim/grub RPMs and the kernel tarball |
| `patch_initrd` / `pack_initrd` | Apply the initrd patch, then repack it |
| `pack_system` | Repack only the system image |
| `mount_boot` / `umount_boot` | Loop-mount / unmount `boot.img` |
| `mount_system` / `umount_system` | Loop-mount / unmount the unpacked system image |
| `mount_data` / `umount_data` | Loop-mount / unmount `data.img` |
| `flash_all` | Fastboot-flash gpt + boot + system + data, then reboot |
| `flash_gpt` / `flash_boot` / `flash_system` / `flash_data` | Flash a single partition |
| `flash_boot_system` | Flash boot and system |
| `flash_reboot` | `fastboot reboot` |
| `ssh` | SSH into a booted device/VM as `root@192.168.255.1` |
| `qemu` | Boot the built kernel/initrd/system/data under QEMU/KVM |
| `qemu-iso` | Boot the source ISO under QEMU/KVM |
| `mount_qemu_data` / `umount_qemu_data` | Mount the QEMU disk image via `guestmount` |
| `dnx.7z` | Bundle all images and the `.bat` scripts into `DNX_Fastboot.7z` |
| `clean` | Remove `build/` and unmount loop devices |
| `clean_images` / `clean_images_all` | Remove one / all `images-*` directories |
| `clean_all` | `clean` + `clean_images_all` + remove downloaded RPMs and generated DSDT |
| `clean_iso` / `clean_initrd` / `clean_system` / `clean_data` / `clean_boot` / `clean_kenrel` / `clean_qemu` | Remove a specific build artifact |

> Note: `unpack_kenrel` and `clean_kenrel` keep the spelling used in the makefile.

## Flash

### Linux (fastboot)

```bash
# Build and flash everything, then reboot
make flash_all VER=21
```

Or flash manually:

```bash
fastboot boot  overlay/boot/EFI/BlissOS/fastboot.efi
fastboot oem unlock   # handled by fastboot.efi, not a device bootloader
fastboot flash oemvars device_files/oemvars.txt
fastboot flash oemvars device_files/oemvars-battery-config-fake-disabled.txt
fastboot flash oemvars device_files/oemvars-battery-config-fake.txt
fastboot flash gpt     images-21/gpt.bin
fastboot flash boot    images-21/boot.img
fastboot flash system  images-21/system.img
fastboot flash data    images-21/data.img   # or data.simg
fastboot reboot
```

The `oemvars-battery-config-fake*.txt` files toggle the fake-battery flag:

- `oemvars-battery-config-fake.txt` → `BatteryConfig ro.boot.fake_battery=1`
- `oemvars-battery-config-fake-disabled.txt` → `BatteryConfig ro.boot.fake_battery=0`

Flash the one that matches how you want battery reporting handled.

### Windows (one-click)

Use the batch scripts with `fastboot` on `PATH`. Each script expects the following
layout next to itself:

```
<flash folder>/
├── DNX_flash_*.bat
├── fastboot.efi           # copied from overlay/boot/EFI/BlissOS/fastboot.efi
├── device_files/          # oemvars*.txt
│   └── oemvars*.txt
└── images/                # copied/renamed from images-<VER>/
    ├── gpt.bin
    ├── boot.img
    ├── system.img
    └── data.img / data.simg
```

| Script | Action |
| --- | --- |
| `DNX_flash_all.bat` | Verify the device, unlock, flash oemvars + gpt + boot + system + data, reboot |
| `DNX_flash-boot.bat` | Flash `boot.img` only |
| `DNX_flash-system.bat` | Flash `system.img` only |
| `DNX_flash-data.bat` | Flash `data.img` (prefers `data.simg`) only |

`DNX_flash_all.bat` boots `fastboot.efi`, checks `product: latte`, runs `fastboot oem unlock`
(a `fastboot.efi` command, not a device bootloader), and prefers
`images\data.simg` over `images\data.img` when present.

To assemble that folder from a Linux build:

```bash
make all VER=21
mkdir -p flash/images flash/device_files
cp DNX_flash_*.bat flash/
cp images-21/gpt.bin images-21/boot.img images-21/system.img images-21/data.img flash/images/
cp images-21/data.simg flash/images/ 2>/dev/null || true
cp overlay/boot/EFI/BlissOS/fastboot.efi flash/
cp device_files/oemvars*.txt flash/device_files/
```

> **Known limitations of the batch scripts**
> - They expect a folder literally named `images/`, while the makefile emits
>   `images-<VER>/`. Copy or rename as shown above.
> - They reference the UEFI fastboot loader under different names and locations:
>   `DNX_flash_all.bat` / `DNX_flash-boot.bat` use `device_files\fastboot.efi`,
>   while `DNX_flash-data.bat` / `DNX_flash-system.bat` use `loader.efi` beside the
>   script. Both are the same file, `overlay/boot/EFI/BlissOS/fastboot.efi`; copy it
>   to the path each script expects.
> - The `dnx.7z` target stores the images at the archive root (7-Zip strips directory
>   names), so extracting it does **not** produce `images/`; create the folder and move
>   the files in, or just use the layout above.

## Debugging

- **SSH** — `make ssh` connects as `root@192.168.255.1` using `device_files/id_rsa`.
  This relies on the USB gadget network, so plug the tablet into a USB host port.
- **USB networking** — the `udc.sh` overlay brings up an ECM gadget with a `dnsmasq`
  server on `192.168.255.1/24`; the device is reachable by `adb connect 192.168.255.1:5555`.
- **QEMU/KVM** — `make qemu VER=21` boots the built images with virtio-gpu, virtio-net
  (host ports `5555`/`5522` forwarded) and a qcow2 data disk.

## Repository layout

```
.
├── makefile                 # the entire build system
├── MAKEFILE_VARS.md         # detailed reference for every make variable
├── device_files/            # device-specific inputs
│   ├── gpt.ini, gpt_ini2bin.py   # partition table definition + generator
│   ├── grub.cfg                  # GRUB template (substituted into boot.img)
│   ├── dsdt.dsl / dsdt.aml       # patched ACPI DSDT
│   ├── mipad2_keymap.c           # capacitive-key remapper (built to key-remap)
│   ├── initrd*.patch             # initrd patches, per release
│   ├── oemvars*.txt              # fastboot OEM variables (incl. battery config)
│   └── id_rsa, MOK.*             # SSH keys and Machine Owner Key (Secure Boot)
├── overlay/
│   ├── boot/                # files copied verbatim into boot.img
│   │   ├── EFI/BlissOS/     # fastboot.efi, shellx64.efi, USB-gadget EFI
│   │   ├── EFI/boot/grub.cfg
│   │   └── setup_var.efi, MOK.cer  # UEFI variable tweaks + Secure Boot MOK
│   ├── system/              # files copied into system.img
│   │   └── system/          # firmware, ALSA UCM, init scripts, dropbear keys
│   ├── data/                # files copied into data.img
│   └── system_modify.sh     # post-unpack system tweaks (build.prop, app/firmware pruning)
├── build/                   # intermediate artifacts (unpacked ISO/initrd/system, kernel, shim)
├── images-<VER>/            # build output: gpt.bin, boot.img, system.img, data.img
└── DNX_flash_*.bat          # Windows one-click flashing scripts
```

## Acknowledgments

This project only repackages and patches work from others:

- [BlissOS](https://blissos.org/), [LineageOS for x86](https://lineageos-x86.github.io/)
  and [ProjectSakura](https://projectsakura.xyz/) — the source Android-x86 images.
- [android-x86-kernel-latte](https://github.com/Qs315490/android-x86-kernel-latte) —
  the `zenith` kernel packages.
- Fedora `shim` / `grub2-efi` — the signed UEFI boot chain.

All trademarks and vendor firmware remain the property of their respective owners.
