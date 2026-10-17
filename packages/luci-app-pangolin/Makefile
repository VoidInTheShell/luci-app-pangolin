include $(TOPDIR)/rules.mk

PKG_VERSION:=1.0.0
PKG_RELEASE:=14
PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=OpenWrt Pangolin contributors

LUCI_TITLE:=LuCI support for the Pangolin client
LUCI_DESCRIPTION:=Install, configure and monitor the official Pangolin client and optional Subnet Router under procd.
LUCI_URL:=https://github.com/fosrl/cli
LUCI_DEPENDS:=+luci-base +rpcd-mod-ucode +ucode-mod-fs +ucode-mod-uci +ucode-mod-ubus
LUCI_PKGARCH:=all

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
