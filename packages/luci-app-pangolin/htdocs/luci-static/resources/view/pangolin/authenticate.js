'use strict';
'require dom';
'require poll';
'require rpc';
'require view';

const callAuthAction = rpc.declare({ object: 'luci.pangolin', method: 'auth_action', params: [ 'action' ], reject: true, expect: { '': {} } });
const callGetAuth = rpc.declare({ object: 'luci.pangolin', method: 'get_auth_status', reject: true, expect: { '': {} } });

return view.extend({
	load: function() {
		// This page is opened directly by the user's click, and owns the complete
		// request/redirect sequence even while the overview tab is inactive.
		return callAuthAction('start').catch(error => ({ error: error.message }));
	},

	checkPairing: function() {
		if (this.finished || this.requesting) return Promise.resolve();
		this.requesting = true;
		return callGetAuth().then(auth => {
			if (auth.state == 'pending' && auth.url && auth.code) {
				this.finished = true;
				dom.content(this.message, [
					E('p', {}, _('正在打开 Pangolin 认证页面…')),
					E('a', { 'class': 'btn cbi-button cbi-button-action', href: auth.url }, _('打开链接认证')),
					E('p', {}, [ _('设备配对码：'), E('code', {}, auth.code) ])
				]);
				window.location.replace(auth.url);
			} else if (auth.state == 'error' || auth.state == 'expired' || Date.now() >= this.deadline) {
				this.finished = true;
				dom.content(this.message, E('p', { 'class': 'alert-message warning' },
					auth.state == 'expired' ? _('设备配对码已过期，请返回 OpenWrt 重新认证。') : _('未能获取设备配对信息，请返回 OpenWrt 检查服务器地址和网络后重试。')));
			}
		}).catch(() => {
			if (Date.now() >= this.deadline) {
				this.finished = true;
				dom.content(this.message, E('p', { 'class': 'alert-message warning' }, _('设备配对请求超时，请返回 OpenWrt 重试。')));
			}
		}).finally(() => { this.requesting = false; });
	},

	render: function(result) {
		this.message = E('div', {}, E('p', { 'class': 'spinning' }, _('正在获取设备配对信息，请稍候…')));
		const page = E('div', { 'class': 'cbi-section' }, [
			E('h2', {}, _('Pangolin 设备认证')),
			this.message,
			E('p', {}, E('a', { href: L.url('admin', 'vpn', 'pangolin') }, _('返回 Pangolin 设置')))
		]);
		if (!result?.success) {
			dom.content(this.message, E('p', { 'class': 'alert-message warning' }, result?.error || _('无法启动设备认证。')));
			return page;
		}
		this.deadline = Date.now() + 60000;
		poll.add(() => this.checkPairing(), 1);
		this.checkPairing();
		return page;
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
