include $(TOPDIR)/rules.mk

PKG_VERSION:=1.0.0
PKG_RELEASE:=3
PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=OpenWrt Pangolin contributors

LUCI_TITLE:=LuCI support for the Pangolin site connector
LUCI_DESCRIPTION:=Configure and monitor the official Pangolin CLI site connector under procd.
LUCI_URL:=https://github.com/fosrl/cli
LUCI_DEPENDS:=+pangolin-cli +luci-base +rpcd-mod-ucode
LUCI_PKGARCH:=all

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
