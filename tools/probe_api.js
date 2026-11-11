'use strict';
// Generic eapi probe: compare direct vs through-proxy behaviour for any api path.
// usage:
//   node probe_api.js /api/song/lyric/v1 '{"id":"185811","lv":-1,"kv":-1,"tv":-1}'
//   node probe_api.js /api/song/lyric/v1 '{...}' --proxy
// env: PROBE_HOST (default interfacepc.music.163.com), PROBE_COOKIE, DUMP_BODY
const https = require('https');
const http = require('http');
const tls = require('tls');
const crypto = require('./unm-3x/src/crypto');

const args = process.argv.slice(2);
const apiPath = args[0];
const rawParam = process.env.PROBE_PARAM || args[1] || '{}';
const useProxy = args.includes('--proxy') || process.env.PROBE_VIA === 'proxy';
const PROXY = process.env.PROBE_PROXY || 'http://127.0.0.1:8080';
const HOST = process.env.PROBE_HOST || 'interfacepc.music.163.com';
const APPVER = process.env.PROBE_APPVER || '3.1.34.205281';
const COOKIE =
	process.env.PROBE_COOKIE || 'os=pc; appver=' + APPVER + '; channel=netease';

if (!apiPath) {
	console.error("usage: node probe_api.js <path> '<json>' [--proxy]");
	process.exit(1);
}

const header = JSON.stringify({
	clientSign: 'BC:FC:E7:19:0B:F6',
	os: 'pc',
	appver: APPVER,
	deviceId: 'FFBFB719F6ADC025CA7F55F9262895CC7970A3DBBCFCE7190BF6',
	requestId: 0,
	osver: 'Microsoft-Windows-10-Professional-build-19045-64bit',
});

const param = Object.assign({}, JSON.parse(rawParam));
if (!('header' in param)) param.header = header;
if (!('e_r' in param)) param.e_r = true;

const query = crypto.eapi.encryptRequest('http://' + HOST + apiPath, param);
const urlPath = new URL(query.url).pathname;

if (process.env.DUMP_BODY) {
	require('fs').writeFileSync(process.env.DUMP_BODY, query.body);
	console.log('host=' + HOST);
	console.log('path=' + urlPath);
	console.log('body=' + process.env.DUMP_BODY + ' (' + query.body.length + 'B)');
	process.exit(0);
}

const headers = {
	'Content-Type': 'application/x-www-form-urlencoded',
	'Content-Length': Buffer.byteLength(query.body),
	'User-Agent':
		'NeteaseMusic/3.1.34.205281(2069);Microsoft-Windows-10-Professional-build-19045-64bit',
	Cookie: COOKIE,
	'X-Real-IP': '118.88.88.88',
	Accept: '*/*',
};

const dump = (tag, res, buf) => {
	console.log(`\n### ${tag}: HTTP ${res.statusCode} bytes=${buf.length} ce=${res.headers['content-encoding'] || '-'} ct=${res.headers['content-type'] || '-'}`);
	let parsed = null;
	try {
		parsed = JSON.parse(buf.toString('utf8'));
		console.log('  [plaintext json]');
	} catch (e) {
		try {
			parsed = JSON.parse(crypto.eapi.decrypt(buf).toString('utf8'));
			console.log('  [eapi encrypted]');
		} catch (e2) {
			console.log('  [undecodable] head=' + buf.slice(0, 120).toString('utf8'));
			return;
		}
	}
	console.log('  ' + JSON.stringify(parsed).slice(0, 900));
};

const finish = (res, tag) => {
	const cs = [];
	res.on('data', (c) => cs.push(c));
	res.on('end', () => dump(tag, res, Buffer.concat(cs)));
};

if (!useProxy) {
	// direct
	const req = https.request(
		{ host: HOST, path: urlPath, method: 'POST', headers },
		(res) => finish(res, 'DIRECT')
	);
	req.on('error', (e) => console.error('direct error:', e.message));
	req.end(query.body);
} else {
	// through HTTP proxy: CONNECT then TLS then request
	const pu = new URL(PROXY);
	const cargs = http.request({
		host: pu.hostname,
		port: pu.port || 8080,
		method: 'CONNECT',
		path: `${HOST}:443`,
	});
	cargs.on('connect', (res, socket) => {
		if (res.statusCode !== 200) {
			console.error('CONNECT failed', res.statusCode);
			process.exit(1);
		}
		const t = tls.connect(
			{ socket, servername: HOST, rejectUnauthorized: false },
			() => {
				// TLS already established on t: speak plain HTTP/1.1 over it.
				const req = http.request(
					{
						method: 'POST',
						path: urlPath,
						headers,
						createConnection: () => t,
					},
					(res2) => finish(res2, 'VIA-PROXY')
				);
				req.on('error', (e) => console.error('proxy req error:', e.message));
				req.end(query.body);
			}
		);
		t.on('error', (e) => console.error('tls error:', e.message));
	});
	cargs.on('error', (e) => console.error('proxy connect error:', e.message));
	cargs.end();
}
