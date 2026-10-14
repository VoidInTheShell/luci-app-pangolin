include $(TOPDIR)/rules.mk

PKG_NAME:=newt
PKG_VERSION:=1.18.1
PKG_RELEASE:=3

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/fosrl/newt/tar.gz/refs/tags/$(PKG_VERSION)?
PKG_HASH:=e3e66632a3ca2eeb950cb74e087ca837e7eee98a9e0816fcc1e4528a355ccd18

PKG_MAINTAINER:=OpenWrt Newt contributors
PKG_LICENSE:=AGPL-3.0-only
PKG_LICENSE_FILES:=LICENSE
ifneq ($(NEWT_USE_EXTERNAL_GO),1)
PKG_BUILD_DEPENDS:=golang1.26/host
endif
PKG_BUILD_PARALLEL:=1
PKG_BUILD_FLAGS:=no-mips16

GO_PKG:=github.com/fosrl/newt
GO_PKG_BUILD_PKG:=$(GO_PKG)
# Keep this recursively expanded: GO_ARCH is supplied by golang-values.mk,
# which is included below. Immediate expansion here would silently produce
# "linux_" instead of the upstream platform identifier (for example,
# "linux_arm64").
GO_PKG_LDFLAGS_X=main.newtVersion=$(PKG_VERSION) main.newtPlatform=linux_$(GO_ARCH)

include $(INCLUDE_DIR)/package.mk
include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk

# Upstream intentionally builds Newt without cgo. Keep the OpenWrt artifact
# static as well; Newt's userspace networking does not need libc bindings.
GO_PKG_TARGET_VARS+=CGO_ENABLED=0
GO_PKG_DEFAULT_LDFLAGS:=

define Package/newt
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=VPN
  TITLE:=Pangolin userspace tunnel connector
  URL:=https://github.com/fosrl/newt
  DEPENDS:=$(GO_ARCH_DEPENDS) +ca-bundle +ucode +ucode-mod-fs +ucode-mod-uci
endef

define Package/newt/description
 Newt is the lightweight, fully userspace tunnel connector for Pangolin.
 This package integrates it with OpenWrt procd and UCI. Pangolin remains the
 control plane for resources, targets, access control, and tunnel behavior.
endef

define Package/newt/conffiles
/etc/config/newt
endef

define Package/newt/install
	$(INSTALL_DIR) $(1)/usr/bin $(1)/usr/libexec $(1)/etc/init.d $(1)/etc/config
	$(INSTALL_BIN) $(GO_PKG_BUILD_BIN_DIR)/newt $(1)/usr/bin/newt
	$(INSTALL_BIN) ./files/newt.init $(1)/etc/init.d/newt
	$(INSTALL_BIN) ./files/newt-run $(1)/usr/libexec/newt-run
	$(INSTALL_BIN) ./files/newt-sync-credentials $(1)/usr/libexec/newt-sync-credentials
	$(INSTALL_BIN) ./files/newt-service-action $(1)/usr/libexec/newt-service-action
	$(INSTALL_BIN) ./files/configure-newt $(1)/usr/libexec/configure-newt
	$(INSTALL_CONF) ./files/newt.config $(1)/etc/config/newt
	chmod 0600 $(1)/etc/config/newt
endef

define Package/newt/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	chmod 0600 /etc/config/newt 2>/dev/null || true
	/etc/init.d/newt enable 2>/dev/null || true
}
endef

$(eval $(call BuildPackage,newt))
