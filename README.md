# 已迁移

本仓库的 **Arch Linux 根文件系统构建**内容已独立成新仓库，请移步：

**https://github.com/xiaomi-latte-dev/arch_latte_rootfs**

新仓库包含：

- `Makefile`：分段构建（packages / rootfs / overlay），产物为 boot 与 rootfs 两个稀疏镜像
- `overlay/`：静态文件（UCM、蓝牙固件、密钥、内核 hook 等）
- `scripts/shim-vendor-cert.sh`：shim 引导链所需的证书提取脚本

本仓库（`xiaomi-latte-flash_tools`）不再维护 Arch Linux 相关分支。
