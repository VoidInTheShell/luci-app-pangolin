# 构建、版本与发布

## 开发与正式发布边界

`dev` 从 `main` 创建，通过正常 merge 接收功能分支。推送到 `dev` 后 GitHub Actions 自动运行静态检查、回归、真实 OpenWrt rpcd 测试，使用官方 OpenWrt 25.12.5 SDK 构建 ARM64 与 x86_64 APK，验证签名和目标架构执行，再发布 Pre-release。

每个开发 Release 使用独立 tag，绑定触发构建的确切 commit。开发版不设置 Latest。只有两个架构和检查全部成功才发布。PR 只验证，不读取正式签名 secret、不发版；PR 构建用临时测试签名。

推送 `main` 只验证和构建。流程不会自动合并 dev、修改 main 或创建正式 tag。

## 版本

- 产品版本：根目录 `VERSION`，采用 `MAJOR.MINOR.PATCH`。
- 初始基础版本：`1.1.0`，首次正式版发布后在 dev 将 VERSION 更新为下一个计划版本。
- 开发 tag：`v1.1.0-dev.<GitHub run_number>.<run_attempt>`。
- 开发 APK：`1.1.0_pre<run_number>-r<run_attempt>`。
- 正式 tag：`v1.1.0`，必须与该提交的 VERSION 完全一致。
- 正式 APK：`1.1.0-r0`。APK 的 `_pre` 规则确保同一基础版本的正式版高于开发版。
- 两个产品 APK 版本一致；`pangolin version` 和 `/usr/share/pangolin/version` 仍显示实际上游 CLI `0.18.1`。源包 URL、Newt/OLM pin 不随产品版本变化。

原 SDK 包版本作为本地不传环境变量时的兼容默认值保留；CI 使用 PANGOLIN_PACKAGE_VERSION 和 PANGOLIN_PACKAGE_RELEASE 注入产品版本，不产生版本回写 commit。

## 手动发布正式版

由用户指定通过验收的开发 Release tag，再合入主线并创建正式 tag。例如首次发布：

```sh
git fetch origin --tags
# 示例：替换为用户选定、已通过验收的开发 tag
release_source=v1.1.0-dev.2.1
git switch main
git pull --ff-only origin main
git merge --no-ff "$release_source"
git push origin main
# 等待 main 的检查和构建通过，再由用户确认：
git tag -a v1.1.0 -m 'Pangolin 1.1.0'
git push origin v1.1.0
```

合入的是用户指定 tag 对应的内容，不跟随 dev 后续提交；正式 tag 必须指向已经包含在 origin/main 的提交。工作流会拒绝未合入主线的 tag、预发布 tag和不匹配 VERSION 的 tag。本次配置仅创建 dev 开发发布，不代用户合并 main 或发布正式版。

## 安装资产与签名

每个 Release 包含两个架构压缩包、`pangolin-public-key.pem`、`SHA256SUMS`。每个压缩包中包含匹配架构的 pangolin-cli、noarch LuCI APK、签名 packages.adb、index.json、包校验和、manifest.json（包含 source SHA、架构、产品/上游版本）和 INSTALL.txt。

签名使用本 fork 专用 P-256 密钥。私钥只保存在 GitHub Actions secret `PANGOLIN_APK_PRIVATE_KEY_B64`（PKCS#8 PEM 的 base64），公钥提交在 `keys/pangolin-public-key.pem`。构建先确认私钥导出的公钥与提交值一致，私钥在运行结束时清理，不缓存、不上传。不沿用上游作者的签名身份。

安装两个 APK 时官方 OpenWrt 仓库应可用，以解析 kmod-tun、LuCI、ucode、curl 等运行依赖。这里只发布 OpenWrt 25.12.5 APK，不发布 IPK 或固件镜像。

## 本地复现

Linux 上安装官方 SDK 所需工具及 Go 1.26.9，准备与公钥匹配的签名私钥文件，然后：

```sh
bash tests/check.sh
PANGOLIN_CLIENT_ONLY=1 \
PANGOLIN_PACKAGE_VERSION=1.1.0_pre1 PANGOLIN_PACKAGE_RELEASE=1 \
OPENWRT_TARGET=rockchip OPENWRT_SUBTARGET=armv8 OPENWRT_PACKAGE_ARCH=aarch64_generic \
OPENWRT_PUBLIC_KEY_FILE="$PWD/keys/pangolin-public-key.pem" \
OPENWRT_APK_PRIVATE_KEY_FILE=/secure/pangolin-signing.pem \
NEWT_USE_EXTERNAL_GO=1 PANGOLIN_USE_EXTERNAL_GO=1 \
bash scripts/build-openwrt.sh
```

x86_64 改用 `OPENWRT_TARGET=x86 OPENWRT_SUBTARGET=64 OPENWRT_PACKAGE_ARCH=x86_64`。SDK 下载均有固定 SHA-256。CI 缓存下载归档，不缓存签名私钥或编译工作树。

验证包括包/index 签名、元数据版本与架构、ELF64、可执行脚本 LF 和权限、配置 0600、无账户文件、目标 CLI version/help，以及 OpenWrt ucode 编译；ARM64 CLI 通过 QEMU 执行。CI 不登录任何 Pangolin 服务端，不代替真实设备上的 VPN 联合验收。
