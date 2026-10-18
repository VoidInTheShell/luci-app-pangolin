# luci-app-pangolin

在 OpenWrt 上安装、认证、配置和管理官方 Pangolin **客户端**，可选启用官方 Subnet Router。基于 [alexanderjlynn/openwrt-newt](https://github.com/alexanderjlynn/openwrt-newt) fork 开发，保留上游许可证与站点连接器兼容代码。

支持 OpenWrt **25.12.5 / APK v3**，提供 **ARM64 (`aarch64_generic`)** 和 **x86_64** 安装包，不支持 32 位。上游固定版本：Pangolin CLI 0.18.1、Newt 1.18.1、OLM 1.10.1。

## 安装

从本仓库 [Releases](https://github.com/VoidInTheShell/luci-app-pangolin/releases) 下载与设备 `apk --print-arch` 一致的压缩包。开发版标记为 Pre-release；正式版由维护者手动打 tag 后发布。检查 Release 的 `SHA256SUMS`，解压后将文件复制到设备 `/tmp/pangolin-release`，执行：

```sh
cd /tmp/pangolin-release
sha256sum -c packages-sha256sums
cp pangolin-public-key.pem /etc/apk/keys/pangolin-public-key.pem
apk add ./pangolin-cli-*.apk ./luci-app-pangolin-*.apk
/etc/init.d/rpcd restart
```

签名公钥同时位于 [keys/pangolin-public-key.pem](keys/pangolin-public-key.pem)。首次信任前应核对公钥与发布页校验值。包内不包含设备配置、账户或密钥，安装不会自动启动 VPN。

打开 **LuCI → VPN → Pangolin**，填写 HTTPS 服务器地址，点击认证，使用认证窗口显示的配对码完成登录。设备已认证后，勾选“启用 Pangolin 服务”，点击“保存并应用”。“保存”只保存配置；开机自启是独立状态按钮。

## 客户端功能

- 自动识别 ARM64 / x86_64，显示安装、认证、连接和进程状态，提供安装/卸载、停止/重启及日志。
- 网页设备认证或客户端 ID/密钥；独立认证窗口完成配对，不依赖原 LuCI 标签页保持活跃。
- Subnet Router 默认关闭，启用后使用官方 IPv4 资源路由、转发和 SNAT。
- DNS 默认**完全关闭**。可启用本机 UDP/TCP DNS，实际监听 `127.0.0.1:<端口>`，默认 `953`，并可选配置 dnsmasq 上游接管；拒绝使用 53 端口。本应用不创建 DNS 劫持规则。
- 可选管理 OpenWrt 接口、防火墙区和 LAN 到 Pangolin 的转发，按所有权记录在停止/卸载时撤销。
- 可选为 Pangolin 客户端和认证进程配置 Nikki DNS/代理绕过。LAN 转发流量仍需在 Nikki 按远端目的网段配置绕过；进程绕过不等于所有局域网流量绕过。
- “优先使用本地路由”增加隧道路由 metric，相同前缀下优先现有本地路由，更具体的隧道路由仍可能优先；此选项不处理 DNS 和 Nikki。

Tailscale、ZeroTier 和 Mihomo/Nikki 的其他路由、DNS 与策略仍需按实际环境联合验收。ARM64 CPE 已验证设备本机资源 ping、认证和生命周期清理；不将这些结果扩展为所有设备/局域网流量的保证。

## 分支与自动发布

- `dev`：从 `main` 创建，合入功能分支后，每次 commit 推送自动检查、构建、签名并发布双架构开发版。
- `main`：用户手动选择版本合入，只构建检查，不自动发正式版。
- `v<VERSION>` tag：用户在主线已包含的提交上手动创建，触发正式版发布。

`VERSION` 保存产品基础版本（当前 `1.1.0`）。开发版 tag 为 `v1.1.0-dev.<run>.<attempt>`，APK 版本为 `1.1.0_pre<run>-r<attempt>`；正式版 tag 为 `v1.1.0`，APK 版本为 `1.1.0-r0`。两类 APK 使用产品版本；客户端 `pangolin version` 仍报告实际捆绑的上游 CLI 版本。

详见 [发布与版本规则](docs/RELEASING.md)。旧 `docs/INSTALLING.md`、镜像构建和 Newt 文档保留上游历史说明；当前客户端安装与发布以本 README 和 RELEASING 为准。
