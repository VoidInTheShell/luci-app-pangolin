import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

// Execute the real LuCI view helpers with only their rendering/RPC boundaries
// stubbed. No device settings, service actions or authentication calls are made.
const source = fs.readFileSync(new URL('../packages/luci-app-pangolin/htdocs/luci-static/resources/view/pangolin/overview.js', import.meta.url), 'utf8');
const css = fs.readFileSync(new URL('../packages/luci-app-pangolin/htdocs/luci-static/resources/view/pangolin/pangolin.css', import.meta.url), 'utf8');
function cssRule(selector) {
	const escaped = selector.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
	const match = css.match(new RegExp(escaped + '\\s*\\{([^}]+)\\}'));
	assert.ok(match, 'Missing CSS rule: ' + selector);
	return match[1];
}
for (const selector of ['.pangolin-auth-heading', '.pangolin-auth-actions', '.pangolin-service-actions'])
	assert.match(cssRule(selector), /justify-content:\s*center\s*;/, selector);
assert.match(cssRule('.pangolin-auth-heading'), /text-align:\s*center\s*;/);
assert.match(cssRule('.pangolin-service-card > h3'), /text-align:\s*center\s*;/);
assert.match(cssRule('.pangolin-auth-actions'), /flex-wrap:\s*wrap\s*;/);
const helpers = source.slice(0, source.indexOf('return view.extend({'));
const context = vm.createContext({
	URL,
	L: { url: (...parts) => '/cgi-bin/luci/' + parts.join('/') },
	_: text => text,
	rpc: { declare: () => () => Promise.reject(new Error('RPC must not run in rendering tests')) },
	ui: { createHandlerFn: (scope, fn) => fn },
	E: (tag, attrs, children) => ({ tag, attrs: attrs || {}, children })
});
vm.runInContext(helpers + '\nthis.helpers = { validateEndpoint, renderControls, authenticationPresentation, authenticationSummary, renderAuth, beginAuthentication };', context);
const { validateEndpoint, renderControls, authenticationPresentation, authenticationSummary, renderAuth, beginAuthentication } = context.helpers;
for (const value of ['https://pangolin.suanlemei.cloud/', 'https://server.example:8443/', 'https://192.0.2.1/', 'https://[2001:db8::1]:8443/'])
	assert.equal(validateEndpoint('test', value), true, value);
for (const value of ['http://server.example', 'https://', 'server.example', 'https://user:password@server.example'])
	assert.notEqual(validateEndpoint('test', value), true, value);

function buttons(node) {
	if (!node || typeof node !== 'object') return [];
	return (node.tag === 'button' ? [node] : []).concat((Array.isArray(node.children) ? node.children : [node.children]).flatMap(buttons));
}
for (const enabled of [false, true]) {
	const rendered = buttons(renderControls({ installed: true, role: 'client', startup_enabled: enabled }));
	assert.equal(rendered.some(node => node.children === '启动'), false);
	const toggles = rendered.filter(node => node.attrs.class.includes('pangolin-autostart'));
	assert.equal(toggles.length, 1);
	assert.equal(toggles[0].attrs['aria-pressed'], String(enabled));
	assert.ok(toggles[0].attrs.class.includes(enabled ? 'is-enabled' : 'is-disabled'));
	assert.equal(rendered.filter(node => /开机自启/.test(node.children)).length, 1);
}
for (const [state, expected] of [
	[{}, '未认证'],
	[{state:'starting'}, '正在获取配对信息'],
	[{state:'pending'}, '等待网页认证'],
	[{authenticated:true, state:'authenticated'}, '已认证'],
	[{logged_in:true}, '已登录，待完成组织配置'],
	[{state:'expired'}, '配对码已过期'],
	[{state:'error'}, '认证失败']
]) assert.equal(authenticationPresentation(state).text, expected);
const auth = { authenticated: true, logged_in: true, selected_org: 'test-org', organizations: [{ ID: 'test-org', Name: 'Example' }] };
assert.equal(authenticationSummary({ configured: true, authentication: auth }), '已就绪，当前组织：Example（组织 ID：test-org），可用组织：Example（组织 ID：test-org）');
assert.equal(authenticationSummary({ configured: false }), '待认证或填写凭据');
const authCard = renderAuth(auth, true);
assert.equal(JSON.stringify(authCard).includes('当前组织：'), false);
assert.equal(JSON.stringify(authCard).includes('可用组织：'), false);
const actionRow = authCard.children.find(node => node?.attrs?.class === 'pangolin-auth-actions');
assert.deepEqual(buttons(actionRow).map(node => node.children), ['重新认证', '退出认证并停止服务']);

// An old pairing attempt must not leave a warning on an authenticated card,
// even while talking to an older RPC backend which returns a stale state.
for (const state of ['error', 'expired']) {
	const authenticatedCard = JSON.stringify(renderAuth({ ...auth, state }, true));
	assert.equal(authenticationPresentation({ ...auth, state }).text, '已认证');
	assert.equal(authenticatedCard.includes('alert-message warning'), false, state);
	assert.equal(authenticatedCard.includes('设备已认证。'), true, state);
	const unauthenticatedCard = JSON.stringify(renderAuth({ state }, true));
	assert.equal(unauthenticatedCard.includes('alert-message warning'), true, state);
}
const reauth = { ...auth, state: 'pending', url: 'https://example.test/auth/login/device?code=EXAMPLE', code: 'EXAMPLE' };
assert.equal(authenticationPresentation(reauth).text, '等待网页认证');
assert.equal(JSON.stringify(renderAuth(reauth, true)).includes('打开链接认证'), true);

// The originating tab must not use RPC or timers after opening the foreground
// authentication page: browsers can suspend or throttle the hidden tab.
let opened;
context.window = {
	open: url => { opened = url; return {}; },
	setTimeout: () => { throw new Error('Background timer must not run'); }
};
beginAuthentication(true);
assert.equal(opened, '/cgi-bin/luci/admin/vpn/pangolin/auth');

const foregroundSource = fs.readFileSync(new URL('../packages/luci-app-pangolin/htdocs/luci-static/resources/view/pangolin/authenticate.js', import.meta.url), 'utf8');
const calls = [];
let foregroundPoll;
let redirected;
let state = { state: 'starting' };
const foregroundContext = vm.createContext({
	Date,
	_: text => text,
	L: { url: (...parts) => '/cgi-bin/luci/' + parts.join('/') },
	E: (tag, attrs, children) => ({ tag, attrs: attrs || {}, children }),
	dom: { content: (node, content) => { node.children = content; } },
	poll: { add: fn => { foregroundPoll = fn; } },
	view: { extend: definition => definition },
	rpc: { declare: ({method}) => async action => {
		calls.push([method, action]);
		return method === 'auth_action' ? {success:true} : state;
	} },
	window: { location: { replace: url => { redirected = url; } } }
});
const foreground = vm.runInContext('(function(){' + foregroundSource + '\n})()', foregroundContext);
foreground.render(await foreground.load());
await new Promise(resolve => setImmediate(resolve));
assert.equal(redirected, undefined);
state = {state:'pending', code:'EXAMPLE', url:'https://example.test/auth/login/device?code=EXAMPLE'};
await foregroundPoll();
assert.equal(redirected, state.url);
assert.equal(calls.filter(([method]) => method === 'auth_action').length, 1);
const completedCalls = calls.length;
await foregroundPoll();
assert.equal(calls.length, completedCalls);

console.log('Centered cards, authenticated warning recovery, HTTPS endpoints, controls, organization summary and independent foreground pairing passed.');
