include $(TOPDIR)/rules.mk

PKG_NAME:=pangolin-cli
PKG_VERSION:=0.18.1
PKG_RELEASE:=6

PKG_SOURCE:=cli-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/fosrl/cli/tar.gz/refs/tags/$(PKG_VERSION)?
PKG_HASH:=568fcbf62a1c485d8cec617c635ae5769ff5d6729bcf412a7f0d13efb3d498ad
PKG_BUILD_DIR:=$(BUILD_DIR)/cli-$(PKG_VERSION)

NEWT_VERSION:=1.18.1
NEWT_SOURCE:=newt-$(NEWT_VERSION).tar.gz
NEWT_HASH:=e3e66632a3ca2eeb950cb74e087ca837e7eee98a9e0816fcc1e4528a355ccd18
OLM_VERSION:=1.10.1
OLM_SOURCE:=olm-$(OLM_VERSION).tar.gz
OLM_HASH:=9de2a1b9daa21ce20b6642c2b948ab9616690800dbc0094835d2f711e3295f1a

PKG_MAINTAINER:=OpenWrt Pangolin contributors
PKG_LICENSE:=AGPL-3.0-only
PKG_LICENSE_FILES:=LICENSE
ifneq ($(PANGOLIN_USE_EXTERNAL_GO),1)
PKG_BUILD_DEPENDS:=golang1.26/host
endif
PKG_BUILD_PARALLEL:=1
PKG_BUILD_FLAGS:=no-mips16

GO_PKG:=github.com/fosrl/cli
GO_PKG_BUILD_PKG:=$(GO_PKG)
GO_PKG_LDFLAGS_X= \
	github.com/fosrl/cli/internal/version.Version=$(PKG_VERSION) \
	github.com/fosrl/cli/internal/version.NewtVersionOverride=$(NEWT_VERSION) \
	github.com/fosrl/cli/internal/config.ManagedBy=openwrt

include $(INCLUDE_DIR)/package.mk
include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk

define Download/newt-source
  FILE:=$(NEWT_SOURCE)
  URL:=https://codeload.github.com/fosrl/newt/tar.gz/refs/tags/$(NEWT_VERSION)?
  HASH:=$(NEWT_HASH)
endef
$(eval $(call Download,newt-source))

define Download/olm-source
  FILE:=$(OLM_SOURCE)
  URL:=https://codeload.github.com/fosrl/olm/tar.gz/refs/tags/v$(OLM_VERSION)?
  HASH:=$(OLM_HASH)
endef
$(eval $(call Download,olm-source))

define Build/Prepare
	$(call Build/Prepare/Default)
	$(INSTALL_DIR) $(PKG_BUILD_DIR)/third_party/newt $(PKG_BUILD_DIR)/third_party/olm
	$(TAR) -C $(PKG_BUILD_DIR)/third_party/newt --strip-components=1 -xf $(DL_DIR)/$(NEWT_SOURCE)
	$(TAR) -C $(PKG_BUILD_DIR)/third_party/olm --strip-components=1 -xf $(DL_DIR)/$(OLM_SOURCE)
	$(PATCH) -d $(PKG_BUILD_DIR)/third_party/newt -p1 < ./files/dependency-patches/010-redact-newt-sensitive-logging.patch
	$(PATCH) -d $(PKG_BUILD_DIR)/third_party/olm -p1 < ./files/dependency-patches/020-restrict-olm-api-socket.patch
	$(PATCH) -d $(PKG_BUILD_DIR)/third_party/olm -p1 < ./files/dependency-patches/030-client-dns-control.patch
endef

# Client mode and optional native site mode require a Linux TUN.
GO_PKG_TARGET_VARS+=CGO_ENABLED=0
GO_PKG_DEFAULT_LDFLAGS:=

define Package/pangolin-cli
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=VPN
  TITLE:=Pangolin client CLI
  URL:=https://github.com/fosrl/cli
  DEPENDS:=$(GO_ARCH_DEPENDS) @(aarch64||x86_64) +ca-bundle +curl +jshn +kmod-tun +ucode +ucode-mod-fs +ucode-mod-uci
endef

define Package/pangolin-cli/description
 The official Pangolin CLI with OpenWrt client integration, optional Subnet
 Router, complete DNS disable and an optional loopback UDP/TCP DNS listener.
endef

define Package/pangolin-cli/conffiles
/etc/config/pangolin
endef

define Package/pangolin-cli/install
	$(INSTALL_DIR) $(1)/usr/bin $(1)/usr/libexec $(1)/usr/share/pangolin $(1)/etc/init.d $(1)/etc/config
	$(INSTALL_BIN) $(GO_PKG_BUILD_BIN_DIR)/cli $(1)/usr/bin/pangolin
	$(INSTALL_DATA) ./files/version $(1)/usr/share/pangolin/version
	$(INSTALL_DATA) ./files/newt-version $(1)/usr/share/pangolin/newt-version
	$(INSTALL_BIN) ./files/pangolin.init $(1)/etc/init.d/pangolin
	$(INSTALL_BIN) ./files/pangolin-client-run $(1)/usr/libexec/pangolin-client-run
	$(INSTALL_BIN) ./files/pangolin-client-watch $(1)/usr/libexec/pangolin-client-watch
		$(INSTALL_BIN) ./files/pangolin-client-integration $(1)/usr/libexec/pangolin-client-integration
		$(INSTALL_BIN) ./files/pangolin-client-integrate.uc $(1)/usr/libexec/pangolin-client-integrate.uc
		$(INSTALL_BIN) ./files/pangolin-locked $(1)/usr/libexec/pangolin-locked
		$(INSTALL_BIN) ./files/pangolin-auth.init $(1)/etc/init.d/pangolin-auth
		$(INSTALL_BIN) ./files/pangolin-auth-run $(1)/usr/libexec/pangolin-auth-run
	$(INSTALL_BIN) ./files/pangolin-dns $(1)/usr/libexec/pangolin-dns
		$(INSTALL_BIN) ./files/pangolin-dns.uc $(1)/usr/libexec/pangolin-dns.uc
	$(INSTALL_BIN) ./files/pangolin-site-run $(1)/usr/libexec/pangolin-site-run
	$(INSTALL_BIN) ./files/pangolin-service-action $(1)/usr/libexec/pangolin-service-action
	$(INSTALL_BIN) ./files/pangolin-network $(1)/usr/libexec/pangolin-network
	$(INSTALL_BIN) ./files/pangolin-site-sync-credentials $(1)/usr/libexec/pangolin-site-sync-credentials
	$(INSTALL_BIN) ./files/configure-pangolin $(1)/usr/libexec/configure-pangolin
	$(INSTALL_CONF) ./files/pangolin.config $(1)/etc/config/pangolin
	chmod 0600 $(1)/etc/config/pangolin
endef

define Package/pangolin-cli/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	/etc/init.d/pangolin stop >/dev/null 2>&1 || true
	/etc/init.d/pangolin-auth stop >/dev/null 2>&1 || true
	/usr/libexec/pangolin-client-integration restore || true
}
exit 0
endef

define Package/pangolin-cli/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	chmod 0600 /etc/config/pangolin 2>/dev/null || true
}
endef

$(eval $(call BuildPackage,pangolin-cli))
