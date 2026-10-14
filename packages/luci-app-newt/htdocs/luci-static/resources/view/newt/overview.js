'use strict';
'require dom';
'require form';
'require poll';
'require rpc';
'require ui';
'require view';

const callGetConfig = rpc.declare({ object: 'luci.newt', method: 'get_config' });
const callSetConfig = rpc.declare({ object: 'luci.newt', method: 'set_config', params: [ 'config' ] });
const callGetStatus = rpc.declare({ object: 'luci.newt', method: 'get_status' });
const callGetLogs = rpc.declare({ object: 'luci.newt', method: 'get_logs', params: [ 'lines' ] });
const callServiceAction = rpc.declare({ object: 'luci.newt', method: 'service_action', params: [ 'action' ] });

let mapData;

const fields = [
	'endpoint', 'auth_mode', 'id', 'name', 'log_level', 'dns', 'mtu', 'port',
	'interface', 'interface_main', 'prefer_endpoint', 'ping_interval', 'ping_timeout',
	'udp_proxy_idle_timeout', 'updown_script', 'blueprint_file',
	'provisioning_blueprint_file', 'docker_socket', 'tls_client_cert',
	'tls_client_key', 'tls_private_key', 'auth_daemon_principals_file',
	'auth_daemon_ca_cert_path', 'admin_addr', 'region', 'respawn_threshold',
	'respawn_timeout', 'respawn_retry', 'enabled', 'native', 'native_main',
	'no_cloud', 'disable_clients', 'disable_ssh', 'enforce_hc_cert',
	'docker_enforce_network_validation', 'auth_daemon_generate_random_password',
	'metrics', 'otlp', 'metrics_async_bytes', 'pprof', 'stdout', 'stderr',
	'local_endpoint_interfaces', 'tls_client_ca', 'secret', 'provisioning_key',
	'auth_daemon_key', 'clear_secret', 'clear_provisioning_key',
	'clear_auth_daemon_key'
];

function serializeConfig() {
	let result = {};
	for (const key of fields)
		if (mapData.newt[key] != null)
			result[key] = mapData.newt[key];
	return result;
}

function formatUptime(seconds) {
	seconds = Number(seconds || 0);
	if (seconds < 60)
		return _('%d seconds').format(seconds);
	const minutes = Math.floor(seconds / 60);
	if (minutes < 60)
		return _('%d minutes').format(minutes);
	const hours = Math.floor(minutes / 60);
	const days = Math.floor(hours / 24);
	return days > 0 ? _('%d days, %d hours').format(days, hours % 24) : _('%d hours, %d minutes').format(hours, minutes % 60);
}

function statusBadge(text, color) {
	return E('span', {
		'class': 'label',
		'style': 'display:inline-block;padding:.25em .65em;border-radius:1em;color:white;background:' + color
	}, text);
}

function renderStatus(status) {
	let serviceState;
	if (!status.installed)
		serviceState = statusBadge(_('Not installed'), '#b91c1c');
	else if (!status.enabled)
		serviceState = statusBadge(_('Disabled'), '#6b7280');
	else if (!status.running)
		serviceState = statusBadge(_('Stopped'), '#b91c1c');
	else if (status.connected)
		serviceState = statusBadge(_('Connected'), '#15803d');
	else
		serviceState = statusBadge(_('Starting / reconnecting'), '#b45309');

	const rows = [
		[ _('Service'), serviceState ],
		[ _('Configuration'), status.configured ? _('Ready') : _('Credentials required') ],
		[ _('Version'), status.version || _('Unknown') ],
		[ _('PID'), status.pid || '—' ],
		[ _('Uptime'), status.running ? formatUptime(status.uptime) : '—' ],
		[ _('Start at boot'), status.startup_enabled ? _('Enabled') : _('Disabled') ],
		[ _('Pangolin endpoint'), status.endpoint || '—' ]
	];

	return E('div', { 'class': 'cbi-section' }, [
		E('h3', {}, _('Status')),
		E('table', { 'class': 'table' }, rows.map(row => E('tr', { 'class': 'tr' }, [
			E('td', { 'class': 'td left', 'style': 'width:12rem' }, E('strong', {}, row[0])),
			E('td', { 'class': 'td left' }, row[1])
		])))
	]);
}

function updateStatus(node, status) {
	dom.content(node, renderStatus(status));
}

function notifyResult(result, successText) {
	if (result?.success)
		ui.addNotification(null, E('p', {}, successText), 'info');
	else
		ui.addNotification(null, E('p', {}, result?.error || _('Operation failed.')), 'danger');
	return result;
}

function runAction(action) {
	ui.showModal(_('Pangolin Newt'), [ E('p', { 'class': 'spinning' }, _('Applying service action…')) ]);
	return callServiceAction(action).then(result => {
		ui.hideModal();
		notifyResult(result, _('Service action completed.'));
		return callGetStatus();
	}).then(status => {
		const node = document.getElementById('newt-status');
		if (node)
			updateStatus(node, status);
	}).catch(error => {
		ui.hideModal();
		ui.addNotification(null, E('p', {}, error.message), 'danger');
	});
}

function actionButton(label, action, style) {
	return E('button', {
		'class': 'btn cbi-button ' + (style || 'cbi-button-action'),
		'click': ui.createHandlerFn(null, () => runAction(action))
	}, label);
}

function renderControls() {
	return E('div', { 'class': 'cbi-section' }, [
		E('h3', {}, _('Service controls')),
		E('div', { 'class': 'right' }, [
			actionButton(_('Start'), 'start', 'cbi-button-positive'), ' ',
			actionButton(_('Restart'), 'restart', 'cbi-button-action'), ' ',
			actionButton(_('Stop'), 'stop', 'cbi-button-negative'), ' ',
			actionButton(_('Enable at boot'), 'enable', 'cbi-button-action'), ' ',
			actionButton(_('Disable at boot'), 'disable', 'cbi-button-neutral')
		])
	]);
}

function refreshLogs(lines) {
	return callGetLogs(lines || 100).then(result => {
		const node = document.getElementById('newt-log-output');
		if (node) {
			node.textContent = result?.logs || _('No Newt log messages found.');
			node.scrollTop = node.scrollHeight;
		}
	});
}

function renderLogs(logData) {
	return E('div', { 'class': 'cbi-section' }, [
		E('h3', {}, _('Logs')),
		E('p', {}, _('The latest system log entries tagged for Newt. Stored credentials are redacted by the RPC backend.')),
		E('div', { 'class': 'right', 'style': 'margin-bottom:.5rem' }, [
			E('button', {
				'class': 'btn cbi-button cbi-button-action',
				'click': ui.createHandlerFn(null, () => refreshLogs(200))
			}, _('Refresh')), ' ',
			E('button', {
				'class': 'btn cbi-button cbi-button-neutral',
				'click': ui.createHandlerFn(null, () => {
					const text = document.getElementById('newt-log-output')?.textContent || '';
					return navigator.clipboard.writeText(text).then(() =>
						ui.addNotification(null, E('p', {}, _('Logs copied to the clipboard.')), 'info'));
				})
			}, _('Copy'))
		]),
		E('pre', {
			'id': 'newt-log-output',
			'style': 'max-height:28rem;overflow:auto;white-space:pre-wrap;background:#111827;color:#e5e7eb;padding:1rem;border-radius:.25rem'
		}, logData?.logs || _('No Newt log messages found.'))
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
	mapData = { newt: Object.assign({}, config, {
		secret: '',
		provisioning_key: '',
		auth_daemon_key: '',
		clear_secret: '0',
		clear_provisioning_key: '0',
		clear_auth_daemon_key: '0'
	}) };

	let map = new form.JSONMap(mapData, _('Pangolin Newt'),
		_('Newt runs directly under procd. Pangolin remains the control plane for resources, targets, access rules, and tunnel configuration.'));
	map.tabbed = true;

	let section = map.section(form.NamedSection, 'newt', 'newt');
	section.addremove = false;
	section.tab('general', _('General'));
	section.tab('network', _('Network'));
	section.tab('features', _('Features'));
	section.tab('tls', _('TLS'));
	section.tab('observability', _('Observability'));
	section.tab('process', _('Process'));

	addFlag(section, 'general', 'enabled', _('Enable Newt'), _('Run the connector and restart it automatically if it exits.'));
	let endpoint = addValue(section, 'general', 'endpoint', _('Pangolin endpoint'), _('The public URL of the Pangolin server.'), 'url', 'https://app.pangolin.net');
	endpoint.rmempty = false;

	let mode = section.taboption('general', form.ListValue, 'auth_mode', _('Setup method'));
	mode.value('credentials', _('Existing Newt ID and secret'));
	mode.value('provisioning', _('One-time provisioning key'));
	mode.rmempty = false;

	let id = addValue(section, 'general', 'id', _('Newt ID'), _('Copy this from the Pangolin site setup page.'));
	id.depends('auth_mode', 'credentials');
	let secret = addValue(section, 'general', 'secret', _('Newt secret'),
		config.has_secret ? _('A secret is stored. Leave blank to keep it.') : _('Copy this from the Pangolin site setup page.'));
	secret.password = true;
	secret.depends('auth_mode', 'credentials');
	secret.placeholder = config.has_secret ? _('Stored (unchanged)') : '';
	let clearSecret = addFlag(section, 'general', 'clear_secret', _('Clear stored secret'));
	clearSecret.depends('auth_mode', 'credentials');

	let provisioning = addValue(section, 'general', 'provisioning_key', _('Provisioning key'),
		config.has_provisioning_key ? _('A key is stored. Leave blank to keep it.') : _('A one-time key generated by Pangolin.'));
	provisioning.password = true;
	provisioning.depends('auth_mode', 'provisioning');
	provisioning.placeholder = config.has_provisioning_key ? _('Stored (unchanged)') : '';
	let clearProvisioning = addFlag(section, 'general', 'clear_provisioning_key', _('Clear stored provisioning key'));
	clearProvisioning.depends('auth_mode', 'provisioning');
	let siteName = addValue(section, 'general', 'name', _('Site name'), _('Name used when Pangolin creates the site during provisioning.'));
	siteName.depends('auth_mode', 'provisioning');

	let logLevel = section.taboption('general', form.ListValue, 'log_level', _('Log level'));
	[ 'DEBUG', 'INFO', 'WARN', 'ERROR', 'FATAL' ].forEach(level => logLevel.value(level));
	logLevel.rmempty = false;

	addValue(section, 'network', 'dns', _('Tunnel DNS server'), null, 'ipaddr', '9.9.9.9');
	addValue(section, 'network', 'mtu', _('MTU'), null, 'range(576,9000)', '1280');
	addValue(section, 'network', 'port', _('WireGuard listen port'), _('Leave blank to choose a random port.'), 'port');
	addValue(section, 'network', 'interface', _('Client interface name'), null, 'uciname', 'pangolin');
	addValue(section, 'network', 'prefer_endpoint', _('Preferred endpoint'), _('Override the endpoint selected by the Pangolin server.'));
	let localInterfaces = section.taboption('network', form.DynamicList, 'local_endpoint_interfaces', _('Local endpoint interfaces'),
		_('Restrict local endpoint discovery to these network interface names. Empty reports all interfaces.'));
	localInterfaces.datatype = 'uciname';
	addValue(section, 'network', 'ping_interval', _('Ping interval'), null, null, '15s');
	addValue(section, 'network', 'ping_timeout', _('Ping timeout'), null, null, '7s');
	addValue(section, 'network', 'udp_proxy_idle_timeout', _('UDP proxy idle timeout'), null, null, '90s');
	addFlag(section, 'network', 'no_cloud', _('Disable cloud failover'));
	let native = addFlag(section, 'network', 'native', _('Native client interfaces'), _('Requires kernel WireGuard support; userspace mode is recommended on OpenWrt.'));
	let nativeMain = addFlag(section, 'network', 'native_main', _('Native main tunnel'), _('Use a kernel WireGuard interface instead of the built-in userspace netstack.'));
	let interfaceMain = addValue(section, 'network', 'interface_main', _('Native main interface name'), null, 'uciname', 'pangolin');
	interfaceMain.depends('native_main', '1');

	addFlag(section, 'features', 'disable_clients', _('Disable Pangolin clients'));
	addFlag(section, 'features', 'disable_ssh', _('Disable SSH features'));
	addFlag(section, 'features', 'enforce_hc_cert', _('Verify health-check certificates'));
	addValue(section, 'features', 'updown_script', _('Up/down script'), _('Absolute path invoked when targets are added or removed.'));
	addValue(section, 'features', 'blueprint_file', _('Blueprint file'), _('Absolute path to a blueprint applied at startup.'));
	addValue(section, 'features', 'provisioning_blueprint_file', _('Provisioning blueprint file'), _('Blueprint applied once after provisioning.'));
	addValue(section, 'features', 'docker_socket', _('Docker socket'), _('Optional container discovery socket. Leave blank on normal OpenWrt installations.'));
	addFlag(section, 'features', 'docker_enforce_network_validation', _('Enforce Docker network validation'));
	let adKey = addValue(section, 'features', 'auth_daemon_key', _('Auth daemon pre-shared key'),
		config.has_auth_daemon_key ? _('A key is stored. Leave blank to keep it.') : null);
	adKey.password = true;
	adKey.placeholder = config.has_auth_daemon_key ? _('Stored (unchanged)') : '';
	addFlag(section, 'features', 'clear_auth_daemon_key', _('Clear auth daemon key'));
	addValue(section, 'features', 'auth_daemon_principals_file', _('SSH principals file'));
	addValue(section, 'features', 'auth_daemon_ca_cert_path', _('SSH CA certificate'));
	addFlag(section, 'features', 'auth_daemon_generate_random_password', _('Generate random authenticated-user passwords'));

	addValue(section, 'tls', 'tls_client_cert', _('Client certificate'), _('Absolute path to a PEM or DER client certificate.'));
	addValue(section, 'tls', 'tls_client_key', _('Client private key'), _('Absolute path to the matching PEM or DER private key.'));
	let ca = section.taboption('tls', form.DynamicList, 'tls_client_ca', _('CA certificates'), _('Absolute paths to trusted CA files.'));
	addValue(section, 'tls', 'tls_private_key', _('Legacy PKCS#12 bundle'), _('Deprecated; use separate certificate and key files where possible.'));

	addFlag(section, 'observability', 'metrics', _('Prometheus metrics'));
	addValue(section, 'observability', 'admin_addr', _('Admin/metrics listen address'), _('Keep this on loopback unless a firewall rule and authentication layer protect it.'), null, '127.0.0.1:2112');
	addFlag(section, 'observability', 'metrics_async_bytes', _('Asynchronous byte counters'));
	addFlag(section, 'observability', 'otlp', _('OTLP export'), _('OTLP endpoint and credentials are supplied through the process environment outside this interface.'));
	addValue(section, 'observability', 'region', _('Region label'));
	addFlag(section, 'observability', 'pprof', _('Go pprof endpoints'), _('Diagnostic endpoints are exposed on the admin listen address.'));

	addValue(section, 'process', 'respawn_threshold', _('Respawn threshold'), _('procd stability threshold in seconds.'), 'uinteger', '3600');
	addValue(section, 'process', 'respawn_timeout', _('Respawn delay'), _('Seconds before restarting a failed process.'), 'uinteger', '5');
	addValue(section, 'process', 'respawn_retry', _('Respawn retry limit'), null, 'uinteger', '5');
	addFlag(section, 'process', 'stdout', _('Send standard output to system log'));
	addFlag(section, 'process', 'stderr', _('Send standard error to system log'));

	return map;
}

return view.extend({
	load: function() {
		return Promise.all([
			L.resolveDefault(callGetConfig(), {}),
			L.resolveDefault(callGetStatus(), {}),
			L.resolveDefault(callGetLogs(100), { logs: '' })
		]);
	},

	render: function(data) {
		const map = createForm(data[0]);
		poll.add(() => Promise.all([ callGetStatus(), callGetLogs(100) ]).then(result => {
			const statusNode = document.getElementById('newt-status');
			if (statusNode)
				updateStatus(statusNode, result[0]);
			const logNode = document.getElementById('newt-log-output');
			if (logNode)
				logNode.textContent = result[1]?.logs || _('No Newt log messages found.');
		}));

		return Promise.all([
			map.render(),
			Promise.resolve(E('div', { 'id': 'newt-status' }, renderStatus(data[1]))),
			Promise.resolve(renderControls()),
			Promise.resolve(renderLogs(data[2]))
		]).then(nodes => E([], [ nodes[1], nodes[2], nodes[0], nodes[3] ]));
	},

	handleSave: function() {
		const node = document.querySelector('.cbi-map');
		return dom.callClassMethod(node, 'save').then(() => {
			ui.showModal(_('Saving Newt configuration'), [ E('p', { 'class': 'spinning' }, _('Saving and restarting the service…')) ]);
			return callSetConfig(serializeConfig());
		}).then(result => {
			ui.hideModal();
			notifyResult(result, _('Configuration saved and the service state was applied.'));
			if (result?.success)
				window.setTimeout(() => window.location.reload(), 700);
		}).catch(error => {
			ui.hideModal();
			ui.addNotification(null, E('p', {}, error.message), 'danger');
		});
	},

	handleSaveApply: function() {
		return this.handleSave();
	},

	handleReset: function() {
		window.location.reload();
	}
});
