'use strict';
'require dom';
'require form';
'require poll';
'require rpc';
'require ui';
'require view';

const rpcOptions = { reject: true, expect: { '': {} } };
const callGetConfig = rpc.declare(Object.assign({ object: 'luci.pangolin', method: 'get_config' }, rpcOptions));
const callSetConfig = rpc.declare(Object.assign({ object: 'luci.pangolin', method: 'set_config', params: [ 'config', 'apply' ] }, rpcOptions));
const callGetStatus = rpc.declare(Object.assign({ object: 'luci.pangolin', method: 'get_status' }, rpcOptions));
const callGetLogs = rpc.declare(Object.assign({ object: 'luci.pangolin', method: 'get_logs', params: [ 'lines' ] }, rpcOptions));
const callServiceAction = rpc.declare(Object.assign({ object: 'luci.pangolin', method: 'service_action', params: [ 'action' ] }, rpcOptions));
const callPackageAction = rpc.declare(Object.assign({ object: 'luci.pangolin', method: 'package_action', params: [ 'action' ] }, rpcOptions));
const callSyncNetwork = rpc.declare(Object.assign({ object: 'luci.pangolin', method: 'sync_network' }, rpcOptions));

const callGetAuth = rpc.declare(Object.assign({ object: 'luci.pangolin', method: 'get_auth_status' }, rpcOptions));
const callAuthAction = rpc.declare(Object.assign({ object: 'luci.pangolin', method: 'auth_action', params: [ 'action' ] }, rpcOptions));
let mapData;

const fields = [
	'role', 'client_auth', 'client_firewall', 'lan_zone', 'nikki_bypass', 'org', 'dns_enabled', 'dns_takeover', 'dns_port', 'dns_upstream', 'subnet_router', 'prefer_local_routes', 'endpoint', 'auth_mode', 'id', 'name', 'log_level', 'dns', 'mtu', 'port',
	'interface', 'interface_main', 'prefer_endpoint', 'ping_interval', 'ping_timeout',
	'udp_proxy_idle_timeout', 'updown_script', 'blueprint_file',
	'provisioning_blueprint_file', 'docker_socket', 'tls_client_cert',
	'tls_client_key', 'tls_private_key', 'auth_daemon_principals_file',
	'auth_daemon_ca_cert_path', 'admin_addr', 'region', 'respawn_threshold',
	'respawn_timeout', 'respawn_retry', 'enabled', 'native', 'native_main',
	'no_cloud', 'disable_clients', 'disable_ssh', 'enforce_hc_cert',
	'docker_enforce_network_validation', 'auth_daemon_generate_random_password',
	'metrics', 'otlp', 'metrics_async_bytes', 'pprof', 'manage_network', 'stdout', 'stderr',
	'local_endpoint_interfaces', 'tls_client_ca', 'secret', 'provisioning_key',
	'auth_daemon_key', 'clear_secret', 'clear_provisioning_key',
	'clear_auth_daemon_key'
];

function serializeConfig() {
	let result = {};
	for (const key of fields)
		if (mapData.pangolin[key] != null)
			result[key] = mapData.pangolin[key];
	if (result.dns_enabled == '0')
		result.dns_takeover = '0';
	if (result.endpoint != null)
		result.endpoint = result.endpoint.trim().replace(/\/+$/, '');
	return result;
}

function formatUptime(seconds) {
	seconds = Number(seconds || 0);
	if (seconds < 60)
		return _('%d 秒').format(seconds);
	const minutes = Math.floor(seconds / 60);
	if (minutes < 60)
		return _('%d 分钟').format(minutes);
	const hours = Math.floor(minutes / 60);
	const days = Math.floor(hours / 24);
	return days > 0 ? _('%d 天 %d 小时').format(days, hours % 24) : _('%d 小时 %d 分钟').format(hours, minutes % 60);
}

function formatBytes(value) {
	value = Number(value || 0);
	if (!Number.isFinite(value) || value < 1)
		return '0 B';
	const units = [ 'B', 'KiB', 'MiB', 'GiB', 'TiB' ];
	const unit = Math.min(Math.floor(Math.log(value) / Math.log(1024)), units.length - 1);
	return '%s %s'.format((value / Math.pow(1024, unit)).toFixed(unit ? 1 : 0), units[unit]);
}

function statusBadge(text, color) {
	return E('span', {
		'class': 'label',
		'style': 'display:inline-block;padding:.25em .65em;border-radius:1em;color:white;background:' + color
	}, text);
}

function authenticationSummary(status) {
	const parts = [ status.configured ? _('已就绪') : _('待认证或填写凭据') ];
	const auth = status.authentication;
	if (!auth?.logged_in) return parts[0];
	const organization = org => org.Name ? org.Name + '（' + _('组织 ID：') + org.ID + '）' : _('组织 ID：') + org.ID;
	if (auth.selected_org) {
		const current = auth.organizations?.find(org => org.ID == auth.selected_org);
		parts.push(_('当前组织：') + organization(current || { ID: auth.selected_org }));
	}
	if (auth.organizations?.length)
		parts.push(_('可用组织：') + auth.organizations.map(organization).join('、'));
	return parts.join('，');
}

function renderStatus(status) {
	let serviceState;
	if (!status.installed)
		serviceState = statusBadge(_('未安装'), '#b91c1c');
	else if (!status.enabled)
		serviceState = statusBadge(_('已关闭'), '#6b7280');
	else if (!status.running)
		serviceState = statusBadge(_('已停止'), '#b91c1c');
	else if (status.connected)
		serviceState = statusBadge(_('已连接'), '#15803d');
	else
		serviceState = statusBadge(_('启动或重连中'), '#b45309');

	const rows = [
		[ _('服务状态'), E('span', {}, [ serviceState, status.installed ? ' · ' + _('客户端已安装') : '' ]) ],
		[ _('认证配置'), authenticationSummary(status) ],
		[ _('Pangolin CLI'), status.version || _('未知') ],
		[ _('设备架构'), status.architecture || _('未知') ],
		[ _('内置 Newt 版本'), status.newt_version || _('未知') ],
		[ _('进程 ID'), status.pid || '—' ],
		[ _('运行时长'), status.running ? formatUptime(status.uptime) : '—' ],
		[ _('开机启动'), status.startup_enabled ? _('已启用') : _('已关闭') ],
		[ _('Pangolin 服务器地址'), status.endpoint || '—' ],
		[ _('运行模式'), status.role == 'client' ? (status.subnet_router ? _('客户端 + 子网路由器') : _('客户端')) : _('站点连接器') ],
		[ _('Pangolin DNS'), status.dns_enabled ? _('已启用') : _('完全关闭') ],
		[ _('DNS 配置地址（UDP / TCP）'), status.dns_configured_listener || '—' ],
		[ _('DNS 实际监听地址'), status.dns_listener || (status.dns_enabled ? _('尚未监听') : '—') ],
		[ _('DNS 自动接管'), status.dns_takeover_active ? _('已接管 dnsmasq 上游') : (status.dns_takeover ? _('等待客户端连接') : _('关闭')) ],
		[ _('Nikki 进程绕过'), status.nikki_bypass ? _('已启用自动配置') : (status.nikki_detected ? _('可选启用') : _('未检测到 Nikki')) ],
		[ _('主隧道网络模式'), status.role == 'client' ? _('客户端 Linux TUN') : status.native_main
			? _('原生 Linux TUN（实验性）')
			: _('用户态网络栈（推荐）') ],
		[ _('隧道接口'), status.native_main
			? (status.device_present ? _('%s（%s，MTU %s）').format(status.interface, status.operstate || _('已创建'), status.device_mtu || '—') : _('%s 尚未创建').format(status.interface))
			: _('用户态模式无需此项') ],
		[ _('网络接口 / 防火墙规则'), status.native_main && !status.running && !status.network_registered && !status.firewall_registered
			? _('服务未启动，尚未创建') : status.native_main
			? _('%s / %s').format(status.network_registered ? _('已注册') : _('未创建'), status.firewall_registered ? _('已注册') : _('未创建'))
			: _('未启用') ],
		[ _('隧道流量'), status.native_main && status.device_present
			? _('接收 %s / 发送 %s').format(formatBytes(status.rx_bytes), formatBytes(status.tx_bytes))
			: '—' ]
	];

	const summaryIndexes = [ 0, 1, 3, 9, 10, 12, 14 ];
	const table = items => E('table', { 'class': 'table' }, items.map(row => E('tr', { 'class': 'tr' }, [
		E('td', { 'class': 'td left', 'style': 'width:12rem' }, E('strong', {}, row[0])),
		E('td', { 'class': 'td left', 'style': 'overflow-wrap:anywhere' }, row[1])
	])));
	return E('div', { 'class': 'cbi-section' }, [
		E('h3', {}, _('运行状态')),
		table(rows.filter((row, index) => summaryIndexes.includes(index))),
		E('details', { 'style': 'margin-top:1rem' }, [
			E('summary', { 'style': 'cursor:pointer;font-weight:600;margin-bottom:.5rem' }, _('技术状态与版本信息')),
			table(rows.filter((row, index) => !summaryIndexes.includes(index)))
		])
	]);
}

function updateStatus(node, status) {
	const expanded = node.querySelector('details')?.open;
	dom.content(node, renderStatus(status));
	if (expanded) node.querySelector('details').open = true;
}

function notifyResult(result, successText) {
	if (result?.success)
		ui.addNotification(null, E('p', {}, successText), 'info');
	else
		ui.addNotification(null, E('p', {}, result?.error || _('操作失败。')), 'danger');
	return result;
}

function errorMessage(error) {
	return error?.message || String(error || _('未知 RPC 错误'));
}

function validateEndpoint(sectionId, value) {
	try {
		const url = new URL(value.trim());
		return url.protocol == 'https:' && !!url.hostname && !url.username && !url.password
			? true : _('Pangolin 服务器地址必须使用 HTTPS。');
	} catch (error) { return _('请输入完整的 HTTPS 服务器地址。'); }
}

function runAction(action) {
	ui.showModal(_('Pangolin'), [ E('p', { 'class': 'spinning' }, _('正在执行服务操作…')) ]);
	return callServiceAction(action).then(result => {
		ui.hideModal();
		notifyResult(result, _('服务操作已完成。'));
		return callGetStatus();
	}).then(status => {
		const node = document.getElementById('pangolin-status');
		if (node)
			updateStatus(node, status);
		const controls = document.getElementById('pangolin-controls');
		if (controls) dom.content(controls, renderControls(status));
	}).catch(error => {
		ui.hideModal();
		ui.addNotification(null, E('pre', { 'style': 'white-space:pre-wrap' }, errorMessage(error)), 'danger');
	});
}

function actionButton(label, action, style) {
	return E('button', {
		'class': 'btn cbi-button ' + (style || 'cbi-button-action'),
		'click': ui.createHandlerFn(null, () => runAction(action))
	}, label);
}

function runPackageAction(action) {
	ui.showModal(_('Pangolin 客户端软件包'), [ E('p', { 'class': 'spinning' }, _('正在处理软件包，请稍候…')) ]);
	return callPackageAction(action).then(result => {
		ui.hideModal();
		notifyResult(result, _('软件包操作已完成。'));
		window.setTimeout(() => window.location.reload(), 700);
	}).catch(error => {
		ui.hideModal();
		ui.addNotification(null, E('pre', { 'style': 'white-space:pre-wrap' }, errorMessage(error)), 'danger');
	});
}

function renderControls(status) {
	if (!status?.installed)
		return E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, _('Pangolin 客户端软件包')),
			E('p', {}, status?.supported_architecture === false
				? _('当前设备架构不在支持范围内，仅支持 x86_64 与 ARM64。')
				: _('客户端尚未安装。优先使用本机缓存的软件包；无缓存时从已配置的 OpenWrt 软件源安装。')),
			E('button', {
				'class': 'btn cbi-button cbi-button-positive',
				'click': ui.createHandlerFn(null, () => runPackageAction('install')),
				'disabled': status?.supported_architecture === false ? true : null
			}, _('安装 Pangolin 客户端'))
		]);
	return E('div', { 'class': 'cbi-section pangolin-service-card' }, [
		E('h3', {}, _('服务管理')),
		E('div', { 'class': 'pangolin-service-actions' }, [
			actionButton(_('重启'), 'restart', 'cbi-button-action'),
			actionButton(_('停止'), 'stop', 'cbi-button-negative'),
			E('button', {
				'class': 'btn cbi-button pangolin-autostart ' + (status.startup_enabled ? 'is-enabled' : 'is-disabled'),
				'aria-pressed': String(!!status.startup_enabled),
				'title': status.startup_enabled ? _('点击关闭开机自启') : _('点击开启开机自启'),
				'click': ui.createHandlerFn(null, () => runAction(status.startup_enabled ? 'disable' : 'enable'))
			}, status.startup_enabled ? _('开机自启：已开启') : _('开机自启：未开启')),
			E('button', {
				'class': 'btn cbi-button cbi-button-negative',
				'click': ui.createHandlerFn(null, () => runPackageAction('uninstall'))
			}, _('卸载 Pangolin 客户端')),
			E('button', {
				'class': 'btn cbi-button cbi-button-action',
				'hidden': status.role != 'site' ? true : null,
				'click': ui.createHandlerFn(null, () => callSyncNetwork()
					.then(result => notifyResult(result, _('OpenWrt 接口和防火墙配置已同步。')))
					.catch(error => ui.addNotification(null, E('pre', { 'style': 'white-space:pre-wrap' }, errorMessage(error)), 'danger')))
			}, _('同步站点接口'))
		])
	]);
}

function beginAuthentication(installed) {
	if (!installed) return;
	// The foreground tab owns its RPC queue and timers. Opening a blank tab and
	// waiting here stalls when the browser throttles this now-background page.
	const url = L.url('admin', 'vpn', 'pangolin', 'auth');
	const authWindow = window.open(url, '_blank');
	if (authWindow) authWindow.opener = null;
	else ui.addNotification(null, E('p', {}, [ _('浏览器阻止了弹窗，请点击：'),
		E('a', { href: url, target: '_blank', rel: 'noopener noreferrer' }, _('打开设备认证页'))
	]), 'info');
}

function authenticationPresentation(auth) {
	if (auth.state == 'starting') return { text: _('正在获取配对信息'), color: '#b45309' };
	if (auth.state == 'pending') return { text: _('等待网页认证'), color: '#b45309' };
	if (auth.authenticated) return { text: _('已认证'), color: '#15803d' };
	if (auth.logged_in) return { text: _('已登录，待完成组织配置'), color: '#b45309' };
	if (auth.state == 'expired') return { text: _('配对码已过期'), color: '#6b7280' };
	if (auth.state == 'error') return { text: _('认证失败'), color: '#b91c1c' };
	return { text: _('未认证'), color: '#6b7280' };
}

function renderAuth(auth, installed) {
	const button = (label, action, style) => E('button', {
		'class': 'btn cbi-button ' + (style || 'cbi-button-action'),
		'disabled': !installed ? true : null,
		'click': ui.createHandlerFn(null, () => action == 'start' ? beginAuthentication(installed) : callAuthAction(action).then(result => {
			notifyResult(result, _('认证状态已更新。'));
			return callGetAuth();
		}).then(next => {
			const node = document.getElementById('pangolin-auth');
			if (node) dom.content(node, renderAuth(next, installed));
		}).catch(error => ui.addNotification(null, E('p', {}, errorMessage(error)), 'danger')))
	}, label);
	const presentation = authenticationPresentation(auth);
	let children = [
		E('h3', { 'class': 'pangolin-auth-heading' }, [
			E('span', {}, _('用户设备认证')),
			E('span', { 'role': 'status', 'aria-live': 'polite' }, statusBadge(presentation.text, presentation.color))
		]),
		E('p', {}, auth.authenticated ? _('设备已认证。勾选“启用 Pangolin 服务”，再点击“保存并应用”启动。') : auth.logged_in ? _('账号已登录，请选择组织并完成客户端配置。') : _('先保存 Pangolin 地址，再点击认证；配对页面会自动打开，也可使用下方链接手动打开。')),
		E('div', { 'class': 'pangolin-auth-actions' }, [
			button(auth.authenticated || auth.logged_in ? _('重新认证') : _('认证'), 'start', 'cbi-button-positive'),
			...(auth.authenticated || auth.logged_in ? [ button(_('退出认证并停止服务'), 'logout', 'cbi-button-negative') ] : [])
		])
	];
	if (auth.state == 'starting')
		children.push(E('p', { 'class': 'spinning' }, _('正在获取设备配对信息，请稍候…')));
	if (auth.state == 'pending' && auth.url && auth.code) {
		children.push(E('div', { 'style': 'display:flex;flex-wrap:wrap;gap:1rem;align-items:center;margin:1rem 0' }, [
			E('a', { 'class': 'btn cbi-button cbi-button-action', 'href': auth.url, 'target': '_blank', 'rel': 'noopener noreferrer' }, _('打开链接认证')),
			E('span', {}, [ _('设备配对码：'), E('code', { 'style': 'font-size:1.3rem;letter-spacing:.15em;user-select:all' }, auth.code) ]),
			button(_('取消'), 'cancel')
		]));
	} else if (!auth.authenticated && (auth.state == 'error' || auth.state == 'expired')) {
		children.push(E('p', { 'class': 'alert-message warning' }, auth.state == 'expired' ? _('配对码已过期，请重新认证。') : _('认证未完成，请检查服务器连接后重试。')));
	}
	return E('div', { 'class': 'cbi-section' }, children);
}

function refreshLogs(lines) {
	return callGetLogs(lines || 100).then(result => {
		const node = document.getElementById('pangolin-log-output');
		if (node) {
			node.textContent = result?.logs || _('暂无 Pangolin 日志。');
			node.scrollTop = node.scrollHeight;
		}
	});
}

function renderLogs(logData) {
	return E('div', { 'class': 'cbi-section' }, [
		E('h3', {}, _('运行日志')),
		E('p', {}, _('显示最近的 Pangolin 系统日志，已保存的凭据会自动隐藏。')),
		E('div', { 'class': 'right', 'style': 'margin-bottom:.5rem' }, [
			E('button', {
				'class': 'btn cbi-button cbi-button-action',
				'click': ui.createHandlerFn(null, () => refreshLogs(200))
			}, _('刷新')), ' ',
			E('button', {
				'class': 'btn cbi-button cbi-button-neutral',
				'click': ui.createHandlerFn(null, () => {
					const text = document.getElementById('pangolin-log-output')?.textContent || '';
					return navigator.clipboard.writeText(text).then(() =>
						ui.addNotification(null, E('p', {}, _('日志已复制到剪贴板。')), 'info'));
				})
			}, _('复制'))
		]),
		E('pre', {
			'id': 'pangolin-log-output',
			'style': 'max-height:28rem;overflow:auto;white-space:pre-wrap;background:#111827;color:#e5e7eb;padding:1rem;border-radius:.25rem'
		}, logData?.logs || _('暂无 Pangolin 日志。'))
	]);
}

function addValue(section, tab, name, title, description, datatype, placeholder) {
	let option = section.taboption(tab, form.Value, name, title, description);
	if (datatype)
		option.datatype = datatype;
	if (placeholder)
		option.placeholder = placeholder;
	return option;
}

function addFlag(section, tab, name, title, description) {
	let option = section.taboption(tab, form.Flag, name, title, description);
	option.rmempty = false;
	return option;
}

function createForm(config) {
	mapData = { pangolin: Object.assign({}, config, {
		secret: '',
		provisioning_key: '',
		auth_daemon_key: '',
		clear_secret: '0',
		clear_provisioning_key: '0',
		clear_auth_daemon_key: '0'
	}) };

	let map = new form.JSONMap(mapData, _('Pangolin'),
		_('使用官方 Pangolin 客户端，可选启用子网路由器。DNS 默认完全关闭；启用后提供本机 UDP/TCP 监听端口。'));

	let section = map.section(form.NamedSection, 'pangolin', 'pangolin');
	section.addremove = false;
	section.tab('general', _('基本设置'));
	section.tab('network', _('网络设置'));
	section.tab('client_dns', _('客户端与 DNS'));
	section.tab('features', _('站点功能'));
	section.tab('tls', _('TLS 证书'));
	section.tab('observability', _('监控与诊断'));
	section.tab('process', _('进程设置'));

	addFlag(section, 'general', 'enabled', _('启用 Pangolin 服务'), _('完成认证后勾选，再点击“保存并应用”启动；取消勾选并应用后停止服务。进程异常退出时会自动重启。'));
	let role = section.taboption('general', form.ListValue, 'role', _('服务角色'));
	role.value('client', _('客户端（默认）'));
	role.value('site', _('站点连接器（上游兼容）'));
	role.default = 'client';
	role.rmempty = false;
	let endpoint = addValue(section, 'general', 'endpoint', _('Pangolin 服务器地址'), _('填写 Pangolin 服务器的 HTTPS 地址；使用非默认端口时，在地址后添加 :端口。'), 'url', 'https://app.pangolin.net');
	endpoint.rmempty = false;
	endpoint.validate = validateEndpoint;

	let mode = section.taboption('general', form.ListValue, 'auth_mode', _('站点配置方式'));
	mode.value('credentials', _('已有站点 ID 和密钥'));
	mode.value('provisioning', _('一次性配置密钥'));
	mode.rmempty = false;
	mode.depends('role', 'site');
	let clientAuth = section.taboption('general', form.ListValue, 'client_auth', _('客户端认证方式'));
	clientAuth.value('web', _('网页设备认证（默认）'));
	clientAuth.value('machine', _('客户端 ID 和密钥'));
	clientAuth.default = 'web';
	clientAuth.rmempty = false;
	clientAuth.depends('role', 'client');

	let id = addValue(section, 'general', 'id', _('客户端 / 站点 ID'), _('填写当前服务角色对应的 ID。'));
	id.title = _('客户端 / 站点 ID');
	id.depends({ role: 'site', auth_mode: 'credentials' });
	id.depends({ role: 'client', client_auth: 'machine' });
	let secret = addValue(section, 'general', 'secret', _('客户端 / 站点密钥'),
		config.has_secret ? _('已保存密钥，留空即可保留。') : _('填写当前服务角色对应的密钥。'));
	secret.password = true;
	secret.depends({ role: 'site', auth_mode: 'credentials' });
	secret.depends({ role: 'client', client_auth: 'machine' });
	secret.placeholder = config.has_secret ? _('已保存（留空保留）') : '';
	let clearSecret = addFlag(section, 'general', 'clear_secret', _('清除已保存的密钥'));
	clearSecret.depends({ role: 'site', auth_mode: 'credentials' });
	clearSecret.depends({ role: 'client', client_auth: 'machine' });
	addValue(section, 'client_dns', 'org', _('组织 ID'), _('一个组织时自动选择；多个组织时填写认证区域中显示的组织 ID。')).depends('role', 'client');
	let subnet = addFlag(section, 'client_dns', 'subnet_router', _('启用子网路由器（Subnet Router）'), _('默认关闭。使用官方 IPv4 资源路由、转发和 SNAT。此模式允许局域网设备访问远端资源；启用 Nikki 透明代理时，还需按 Pangolin 目的网段配置绕过规则。'));
	subnet.depends('role', 'client');
	addFlag(section, 'client_dns', 'prefer_local_routes', _('优先使用本地路由'), _('给 Pangolin WireGuard 路由增加较高 metric，让相同前缀的本地 LAN 路由优先；适合避免打印机、NAS 等本地流量进入隧道。更具体的 Pangolin 路由仍会优先；此选项不处理 DNS 或 Nikki 绕过。默认关闭。')).depends('role', 'client');
	let clientFirewall = addFlag(section, 'client_dns', 'client_firewall', _('管理客户端防火墙'), _('默认启用。自动注册客户端接口和防火墙区域；开启子网路由器时，额外允许指定局域网区域访问隧道。停止或卸载时撤销本应用创建的规则。'));
	clientFirewall.default = '1';
	clientFirewall.depends('role', 'client');
	addValue(section, 'client_dns', 'lan_zone', _('局域网防火墙区域'), _('填写现有的防火墙区域名称，默认 lan。'), 'uciname', 'lan').depends({ role: 'client', subnet_router: '1', client_firewall: '1' });
	addFlag(section, 'client_dns', 'nikki_bypass', _('自动配置 Nikki 进程绕过'), _('默认关闭。为 Pangolin 客户端和认证进程配置 Nikki DNS 与代理绕过；仅覆盖路由器上的进程流量。局域网转发流量仍需在 Nikki 中按目的网段配置绕过。')).depends('role', 'client');
	let dnsEnabled = addFlag(section, 'client_dns', 'dns_enabled', _('启用 Pangolin DNS'), _('默认完全关闭。关闭时不创建内置 DNS 代理、DNS 专用路由或监听器。本应用不创建 DNS 劫持规则。'));
	dnsEnabled.depends('role', 'client');
	let dnsPort = addValue(section, 'client_dns', 'dns_port', _('DNS 监听端口'), _('实际绑定 127.0.0.1 上的 UDP 与 TCP 端口；默认 953。供本机 dnsmasq、Mihomo 等作为上游。'), 'port', '953');
	dnsPort.default = '953';
	dnsPort.rmempty = false;
	dnsPort.depends('role', 'client');
	dnsPort.validate = function(sectionId, value) {
		if (!/^[0-9]+$/.test(value) || Number(value) < 1 || Number(value) > 65535)
			return _('请输入 1 至 65535 之间的整数端口。');
		return Number(value) == 53 ? _('53 端口保留给 dnsmasq，请选择其他端口。') : true;
	};
	let takeover = addFlag(section, 'client_dns', 'dns_takeover', _('自动接管 DNS'), _('默认关闭。连接成功后将 dnsmasq 默认上游设为本监听端口，保留按域名转发；停止时恢复先前设置。启用 Nikki DNS 劫持时，需在其 DNS 配置中把 Pangolin 域名转发到此端口。'));
	takeover.depends({ role: 'client', dns_enabled: '1' });
	let upstreams = section.taboption('client_dns', form.DynamicList, 'dns_upstream', _('外部 DNS 上游'), _('必须使用可直接访问的外部 IP，可带 :端口。不要指向路由器的 dnsmasq 或本监听端口，以免回环。'));
	upstreams.depends({ role: 'client', dns_enabled: '1' });

	let provisioning = addValue(section, 'general', 'provisioning_key', _('一次性配置密钥'),
		config.has_provisioning_key ? _('已保存密钥，留空即可保留。') : _('由 Pangolin 生成的一次性配置密钥。'));
	provisioning.password = true;
	provisioning.depends({ role: 'site', auth_mode: 'provisioning' });
	provisioning.placeholder = config.has_provisioning_key ? _('已保存（留空保留）') : '';
	let clearProvisioning = addFlag(section, 'general', 'clear_provisioning_key', _('清除一次性配置密钥'));
	clearProvisioning.depends({ role: 'site', auth_mode: 'provisioning' });
	let siteName = addValue(section, 'general', 'name', _('站点名称'), _('使用一次性配置密钥创建站点时所用的名称。'));
	siteName.depends({ role: 'site', auth_mode: 'provisioning' });

	let logLevel = section.taboption('general', form.ListValue, 'log_level', _('日志级别'));
	[ [ 'DEBUG', _('调试') ], [ 'INFO', _('信息') ], [ 'WARN', _('警告') ], [ 'ERROR', _('错误') ], [ 'FATAL', _('致命错误') ] ].forEach(([ level, title ]) => logLevel.value(level, title + ' (' + level + ')'));
	logLevel.rmempty = false;

	addValue(section, 'network', 'dns', _('隧道 DNS 服务器'), null, 'ipaddr', '9.9.9.9');
	addValue(section, 'network', 'mtu', _('MTU'), null, 'range(576,9000)', '1280');
	addValue(section, 'network', 'port', _('WireGuard 监听端口'), _('留空时使用随机端口。'), 'port');
	addValue(section, 'network', 'interface', _('客户端接口名称'), null, 'uciname', 'pangolin');
	addValue(section, 'network', 'prefer_endpoint', _('首选隧道端点'), _('覆盖 Pangolin 服务器自动选择的隧道端点。'));
	let localInterfaces = section.taboption('network', form.DynamicList, 'local_endpoint_interfaces', _('本地端点接口'),
		_('仅通过指定的网络接口发现本地端点；留空时上报所有接口。'));
	localInterfaces.datatype = 'uciname';
	addValue(section, 'network', 'ping_interval', _('探测间隔'), null, null, '15s');
	addValue(section, 'network', 'ping_timeout', _('探测超时'), null, null, '7s');
	addValue(section, 'network', 'udp_proxy_idle_timeout', _('UDP 代理空闲超时'), null, null, '90s');
	addFlag(section, 'network', 'no_cloud', _('关闭云端故障转移'));
	addFlag(section, 'network', 'native', _('使用原生客户端接口'),
		_('面向本站点所服务客户端隧道的高级选项，通常保持关闭。'));
	let nativeMain = section.taboption('network', form.ListValue, 'native_main', _('主隧道网络模式'),
		_('站点模式默认使用用户态网络栈。原生模式创建 Linux TUN 接口，可用于 OpenWrt 防火墙、路由和流量统计；上游仍将此功能标为实验性。'));
	nativeMain.value('0', _('用户态网络栈（推荐，无 Linux 接口）'));
	nativeMain.value('1', _('原生 Linux TUN（实验性，创建接口）'));
	nativeMain.rmempty = false;
	let interfaceMain = addValue(section, 'network', 'interface_main', _('原生主隧道接口名称'), null, 'uciname', 'pangolin');
	interfaceMain.depends('native_main', '1');
	let manageNetwork = addFlag(section, 'network', 'manage_network', _('向 OpenWrt 注册原生接口'),
		_('启用原生主隧道后，创建 pangolin 网络接口和防火墙区域。初始区域策略允许隧道访问路由器服务，可在“网络 → 防火墙”中检查。'));
	manageNetwork.depends('native_main', '1');

	addFlag(section, 'features', 'disable_clients', _('关闭 Pangolin 客户端接入'));
	addFlag(section, 'features', 'disable_ssh', _('关闭 SSH 功能'));
	addFlag(section, 'features', 'enforce_hc_cert', _('验证健康检查证书'));
	addValue(section, 'features', 'updown_script', _('连接事件脚本'), _('目标添加或移除时执行的脚本绝对路径。'));
	addValue(section, 'features', 'blueprint_file', _('蓝图文件'), _('启动时应用的蓝图文件绝对路径。'));
	addValue(section, 'features', 'provisioning_blueprint_file', _('首次配置蓝图文件'), _('首次配置完成后应用一次的蓝图文件。'));
	addValue(section, 'features', 'docker_socket', _('Docker 套接字'), _('用于容器发现的可选套接字，普通 OpenWrt 设备留空即可。'));
	addFlag(section, 'features', 'docker_enforce_network_validation', _('强制验证 Docker 网络'));
	let adKey = addValue(section, 'features', 'auth_daemon_key', _('认证守护进程预共享密钥'),
		config.has_auth_daemon_key ? _('已保存密钥，留空即可保留。') : null);
	adKey.password = true;
	adKey.placeholder = config.has_auth_daemon_key ? _('已保存（留空保留）') : '';
	addFlag(section, 'features', 'clear_auth_daemon_key', _('清除认证守护进程密钥'));
	addValue(section, 'features', 'auth_daemon_principals_file', _('SSH 授权主体文件'));
	addValue(section, 'features', 'auth_daemon_ca_cert_path', _('SSH CA 证书'));
	addFlag(section, 'features', 'auth_daemon_generate_random_password', _('为认证用户生成随机密码'));

	addValue(section, 'tls', 'tls_client_cert', _('客户端证书'), _('PEM 或 DER 格式客户端证书的绝对路径。'));
	addValue(section, 'tls', 'tls_client_key', _('客户端私钥'), _('与客户端证书匹配的 PEM 或 DER 格式私钥绝对路径。'));
	let ca = section.taboption('tls', form.DynamicList, 'tls_client_ca', _('CA 证书'), _('受信任 CA 证书文件的绝对路径。'));
	addValue(section, 'tls', 'tls_private_key', _('旧版 PKCS#12 证书包'), _('此选项已弃用，建议分别提供证书和私钥文件。'));

	addFlag(section, 'observability', 'metrics', _('Prometheus 指标'));
	addValue(section, 'observability', 'admin_addr', _('管理与指标监听地址'), _('建议仅监听本机回环地址；对外开放时需自行配置防火墙与认证保护。'), null, '127.0.0.1:2112');
	addFlag(section, 'observability', 'metrics_async_bytes', _('异步流量统计'));
	addFlag(section, 'observability', 'otlp', _('OTLP 导出'), _('OTLP 端点和凭据通过进程环境变量设置。'));
	addValue(section, 'observability', 'region', _('区域标签'));
	addFlag(section, 'observability', 'pprof', _('Go pprof 诊断端点'), _('诊断端点使用管理监听地址。'));

	addValue(section, 'process', 'respawn_threshold', _('进程稳定阈值'), _('procd 判断进程稳定运行的时长，单位为秒。'), 'uinteger', '3600');
	addValue(section, 'process', 'respawn_timeout', _('异常重启间隔'), _('进程异常退出后，等待多少秒再重启。'), 'uinteger', '5');
	addValue(section, 'process', 'respawn_retry', _('异常重启次数上限'), null, 'uinteger', '5');
	addFlag(section, 'process', 'stdout', _('将标准输出写入系统日志'));
	addFlag(section, 'process', 'stderr', _('将标准错误写入系统日志'));

	for (const option of section.children) {
		if ([ 'features', 'tls', 'observability' ].includes(option.tab) ||
			(option.tab == 'network' && ![ 'interface', 'mtu' ].includes(option.option))) {
			if (option.deps?.length)
				option.deps.forEach(dependency => dependency.role = 'site');
			else
				option.depends('role', 'site');
		}
	}

	return map;
}

return view.extend({
	load: function() {
		return Promise.all([
			L.resolveDefault(callGetConfig(), {}),
			L.resolveDefault(callGetStatus(), {}),
			L.resolveDefault(callGetLogs(100), { logs: '' }),
				L.resolveDefault(callGetAuth(), {})
		]);
	},

	render: function(data) {
		const map = createForm(data[0]);
		let previousAuth = JSON.stringify(data[3]);
		poll.add(() => Promise.all([ callGetStatus(), callGetLogs(100), callGetAuth() ]).then(result => {
			const statusNode = document.getElementById('pangolin-status');
			if (statusNode)
				updateStatus(statusNode, result[0]);
			const logNode = document.getElementById('pangolin-log-output');
			if (logNode)
				logNode.textContent = result[1]?.logs || _('暂无 Pangolin 日志。');
			const authNode = document.getElementById('pangolin-auth');
			const nextAuth = JSON.stringify(result[2]);
			if (authNode && previousAuth != nextAuth) {
				dom.content(authNode, renderAuth(result[2], result[0].installed));
				previousAuth = nextAuth;
			}
		}));

		return Promise.all([
			map.render(),
			Promise.resolve(E('div', { 'id': 'pangolin-status' }, renderStatus(data[1]))),
			Promise.resolve(renderControls(data[1])),
			Promise.resolve(renderLogs(data[2]))
		]).then(nodes => E([], [
			E('link', { 'rel': 'stylesheet', 'href': L.resource('view/pangolin/pangolin.css') }),
			nodes[1], E('div', { 'id': 'pangolin-controls' }, nodes[2]), E('div', { 'id': 'pangolin-auth' }, renderAuth(data[3], data[1].installed)), nodes[0], nodes[3]
		]));
	},

	saveConfiguration: function(apply) {
		const node = document.querySelector('.cbi-map');
		return dom.callClassMethod(node, 'save').then(() => {
			ui.showModal(_('保存 Pangolin 配置'), [ E('p', { 'class': 'spinning' }, apply ? _('正在保存配置并应用服务状态…') : _('正在保存配置…')) ]);
			return callSetConfig(serializeConfig(), apply);
		}).then(result => {
			ui.hideModal();
			notifyResult(result, apply ? _('配置已保存，服务状态已应用。') : _('配置已保存。点击“保存并应用”后才会启动或停止服务。'));
			if (result?.success)
				window.setTimeout(() => window.location.reload(), 700);
		}).catch(error => {
			ui.hideModal();
		ui.addNotification(null, E('pre', { 'style': 'white-space:pre-wrap' }, errorMessage(error)), 'danger');
		});
	},

	handleSave: function() {
		return this.saveConfiguration(false);
	},

	handleSaveApply: function() {
		return this.saveConfiguration(true);
	},

	handleReset: function() {
		window.location.reload();
	}
});
