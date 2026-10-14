include $(TOPDIR)/rules.mk

PKG_VERSION:=1.0.0
PKG_RELEASE:=2

LUCI_TITLE:=LuCI support for the Pangolin Newt connector
LUCI_DESCRIPTION:=Configure, monitor, and control Newt from the OpenWrt web interface.
LUCI_URL:=https://github.com/fosrl/newt
LUCI_DEPENDS:=+newt +luci-base +rpcd-mod-ucode
LUCI_PKGARCH:=all

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
