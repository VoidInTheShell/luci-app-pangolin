#!/usr/bin/ucode
'use strict';
import { access, chmod, mkdir, popen, readfile, unlink, writefile } from 'fs';
import { cursor } from 'uci';

const backupFile = '/etc/pangolin/dns-backup.json';
const uci = cursor();
uci.load('pangolin');
uci.load('dhcp');
const enabled = uci.get('pangolin', 'main', 'enabled') == '1' &&
	uci.get('pangolin', 'main', 'dns_enabled') == '1' &&
	uci.get('pangolin', 'main', 'dns_takeover') == '1';
const action = ARGV[0];
if (action != 'apply' && action != 'restore') {
	warn('Usage: pangolin-dns {apply|restore}\n');
	exit(2);
}

function reload() {
	if (getenv('PANGOLIN_NO_RELOAD') == '1') return;
	let h = popen('/etc/init.d/dnsmasq reload 2>&1', 'r');
	if (h) { h.read('all'); h.close(); }
}

function asArray(value) {
	if (type(value) == 'array') return value;
	return value == null || value == '' ? [] : [ value ];
}

function setOrDelete(section, key, value) {
	if (value == null) uci.delete('dhcp', section, key);
	else uci.set('dhcp', section, key, value);
}

function preservedServers(value) {
	let result = [];
	for (let entry in asArray(value))
		if (match(entry, /\//)) push(result, entry);
	return result;
}

function ownsServers(item, current, upstream) {
	let expected = [ upstream ];
	for (let entry in preservedServers(item.server)) push(expected, entry);
	if (length(current) != length(expected)) return false;
	for (let i = 0; i < length(expected); i++)
		if (current[i] != expected[i]) return false;
	return true;
}

function restore() {
	if (!access(backupFile)) return;
	let backup = json(readfile(backupFile));
	if (type(backup) != 'object' || type(backup.sections) != 'array') {
		warn('Invalid DNS rollback state; refusing to change DHCP.\n');
		exit(1);
	}
	let conflicts = false;
	let remaining = [];
	for (let item in backup.sections) {
		let servers = asArray(uci.get('dhcp', item.name, 'server'));
		if (!ownsServers(item, servers, backup.upstream) ||
			uci.get('dhcp', item.name, 'noresolv') != '1') {
			warn(`dnsmasq ${item.name} was changed outside Pangolin; preserving its current settings.\n`);
			push(remaining, item);
			conflicts = true;
			continue;
		}
		setOrDelete(item.name, 'server', item.server);
		setOrDelete(item.name, 'noresolv', item.noresolv);
	}
	uci.commit('dhcp');
	if (conflicts) {
		backup.sections = remaining;
		writefile(backupFile, sprintf('%J', backup));
	} else {
		unlink(backupFile);
	}
	reload();
	if (conflicts) exit(1);
}

if (action == 'restore' || !enabled) {
	restore();
	exit(0);
}

let portText = uci.get('pangolin', 'main', 'dns_port') ?? '953';
if (!match(portText, /^[0-9]+$/) || int(portText) < 1 || int(portText) > 65535 || int(portText) == 53) {
	warn('DNS listener port must be 1..65535, excluding dnsmasq port 53.\n');
	exit(1);
}
let upstream = `127.0.0.1#${int(portText)}`;
if (access(backupFile)) {
	let existing = json(readfile(backupFile));
	if (existing?.upstream == upstream) exit(0);
	restore();
}
if (length(uci.changes('dhcp') ?? {})) {
	warn('Save pending DHCP changes before DNS takeover.\n');
	exit(1);
}

let sections = [];
uci.foreach('dhcp', 'dnsmasq', s => push(sections, {
	name: s['.name'], server: s.server ?? null, noresolv: s.noresolv ?? null
}));
if (!length(sections)) {
	warn('No dnsmasq instance found.\n');
	exit(1);
}
mkdir('/etc/pangolin', 0700);
let backup = { upstream: upstream, sections: sections };
if (!writefile(backupFile, sprintf('%J', backup))) {
	warn('Cannot save DNS rollback state.\n');
	exit(1);
}
chmod(backupFile, 0600);
for (let item in sections) {
	let serverValues = [ upstream ];
	for (let entry in preservedServers(item.server)) push(serverValues, entry);
	uci.set('dhcp', item.name, 'server', serverValues);
	uci.set('dhcp', item.name, 'noresolv', '1');
}
if (!uci.commit('dhcp')) {
	warn('Could not commit DNS takeover.\n');
	exit(1);
}
reload();
