#!/usr/bin/ucode
'use strict';
import { access, chmod, mkdir, popen, readfile, unlink, writefile } from 'fs';
import { cursor } from 'uci';

const action = ARGV[0];
if (index([ 'sync', 'stop-client', 'stop-auth', 'restore' ], action) < 0) {
	warn('Usage: pangolin-client-integration {sync|stop-client|stop-auth|restore}\n');
	exit(2);
}
const uci = cursor();
const backupFile = '/etc/pangolin/integration-backup.json';
uci.load('pangolin');
const wanted = [];
const changed = {};
let failed = false;
let owned = [];
if (access(backupFile)) {
	try { owned = json(readfile(backupFile)); } catch (e) { owned = null; }
	if (type(owned) != 'array') {
		warn('Invalid integration rollback state; refusing to change rules.\n');
		exit(1);
	}
}

function section(config, name, kind, values) {
	push(wanted, { config: config, name: name, kind: kind, values: values });
}
function activeGroup(name, instance) {
	// procd places each instance below the service cgroup (for example
	// services/pangolin/client).  The parent cgroup can therefore be empty
	// while the real client is running.  Check its instance rather than the
	// watcher, which can remain alive while the client is respawning.
	let base = '/sys/fs/cgroup/services/' + name;
	let path = base + '/' + instance + '/cgroup.procs';
	if (!access(path)) path = base + '/cgroup.procs';
	return length(trim(readfile(path) ?? '')) > 0;
}
const clientActive = action != 'restore' && action != 'stop-client' &&
	access('/var/run/pangolin/client-active') && activeGroup('pangolin', 'client');
const authActive = action != 'restore' && action != 'stop-auth' &&
	access('/var/run/pangolin-auth/active') && activeGroup('pangolin-auth', 'login');
const enabled = uci.get('pangolin', 'main', 'enabled') == '1' &&
	(uci.get('pangolin', 'main', 'role') ?? 'client') == 'client';
if (clientActive && enabled && uci.get('pangolin', 'main', 'client_firewall') != '0') {
	let iface = uci.get('pangolin', 'main', 'interface') || 'pangolin';
	if (!match(iface, /^[A-Za-z0-9_.-]{1,15}$/)) exit(1);
	section('network', 'pangolin_client', 'interface', { proto: 'none', device: iface });
	section('firewall', 'pangolin_client', 'zone', {
		name: 'pg_client', network: [ 'pangolin_client' ],
		input: 'REJECT', output: 'ACCEPT', forward: 'REJECT'
	});
	if (uci.get('pangolin', 'main', 'subnet_router') == '1') {
		let lan = uci.get('pangolin', 'main', 'lan_zone') || 'lan';
		if (!match(lan, /^[A-Za-z0-9_]{1,32}$/)) exit(1);
		section('firewall', 'pangolin_client_lan', 'forwarding', { src: lan, dest: 'pg_client' });
	}
}
if ((clientActive || authActive) && uci.get('pangolin', 'main', 'nikki_bypass') == '1' && access('/etc/config/nikki')) {
	let groups = [];
	if (clientActive) push(groups, 'services/pangolin');
	if (authActive) push(groups, 'services/pangolin-auth');
	section('nikki', 'pangolin_client_bypass', 'router_access_control', {
		enabled: '1', cgroup: groups, dns: '0', proxy: '0'
	});
}

function readSection(item) {
	let raw = uci.get_all(item.config, item.name);
	if (type(raw) != 'object') return null;
	let result = {};
	for (let key in raw) if (substr(key, 0, 1) != '.') result[key] = raw[key];
	return { kind: raw['.type'], values: result };
}
function same(a, b) {
	if (!a || a.kind != b.kind || length(a.values) != length(b.values)) return false;
	for (let key in a.values) {
		let av = a.values[key], bv = b.values[key];
		if (type(av) != type(bv)) return false;
		if (type(av) == 'array') {
			if (sprintf('%J', av) != sprintf('%J', bv)) return false;
		} else if (av != bv) return false;
	}
	return true;
}
function saveState() {
	mkdir('/etc/pangolin', 0700);
	if (!writefile(backupFile, sprintf('%J', owned))) {
		warn('Unable to save integration rollback state.\n');
		exit(1);
	}
	chmod(backupFile, 0600);
}
const configs = [ 'network', 'firewall', 'nikki' ];
for (let config in configs) {
	uci.load(config);
	if (length(uci.changes(config) ?? {})) {
		warn(sprintf('Save pending %s changes before Pangolin integration.\n', config));
		exit(1);
	}
}
let remaining = [];
for (let item in owned) {
	let current = readSection(item);
	let desired = null;
	for (let entry in wanted)
		if (entry.config == item.config && entry.name == item.name) desired = entry;
	if (current && !same(current, item)) {
		warn(sprintf('%s.%s was edited outside Pangolin; preserving it.\n', item.config, item.name));
		push(remaining, item);
		failed = true;
		continue;
	}
	if (!desired) {
		if (current) { uci.delete(item.config, item.name); changed[item.config] = true; }
	} else push(remaining, item);
}
owned = remaining;
for (let item in wanted) {
	let previous = null;
	for (let entry in owned)
		if (entry.config == item.config && entry.name == item.name) previous = entry;
	let current = readSection(item);
	if (current && (!previous || !same(current, previous))) {
		warn(sprintf('Refusing to replace existing %s.%s.\n', item.config, item.name));
		failed = true;
		continue;
	}
	if (same(current, item)) continue;
	if (!previous) { push(owned, item); } else { previous.kind = item.kind; previous.values = item.values; }
	// Persist ownership before committing any new rule.
	saveState();
	if (current) uci.delete(item.config, item.name);
	uci.set(item.config, item.name, item.kind);
	for (let key in item.values) uci.set(item.config, item.name, key, item.values[key]);
	if (item.config == 'nikki') uci.reorder(item.config, item.name, 0);
	changed[item.config] = true;
}
for (let config in configs) {
	if (changed[config] && !uci.commit(config)) {
		warn(sprintf('Could not commit %s integration.\n', config));
		exit(1);
	}
}
if (length(owned)) saveState();
else unlink(backupFile);
if (getenv('PANGOLIN_NO_RELOAD') != '1') {
	for (let config in configs) if (changed[config]) {
		let command = config == 'nikki'
			? '/etc/init.d/nikki running && /etc/init.d/nikki reload'
			: '/etc/init.d/' + config + ' reload';
		let h = popen(command + ' >/dev/null 2>&1', 'r');
		if (h) { h.read('all'); h.close(); }
	}
}
if (failed) exit(1);
