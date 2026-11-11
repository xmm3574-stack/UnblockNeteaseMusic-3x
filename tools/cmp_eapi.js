'use strict';
// Compare one eapi call: DIRECT vs THROUGH-PROXY, print decrypted diff.
// usage: node cmp_eapi.js <path> '<json-params>'
const https = require('https');
const http = require('http');
const tls = require('tls');
const crypto = require('./unm-3x/src/crypto');

const HOST = process.env.PROBE_HOST || 'interfacepc.music.163.com';
const PROXY = process.env.PROBE_PROXY || '127.0.0.1:8080';
const APPVER = process.env.PROBE_APPVER || '3.1.34.205281';

const path = process.argv[2];
const params = JSON.parse(process.env.PROBE_PARAM || process.argv[3] || '{}');
if (!path) {
	console.error("usage: node cmp_eapi.js /api/xxx '{\"a\":1}'");
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
const payload = Object.assign({}, params);
if (!('header' in payload)) payload.header = header;
if (!('e_r' in payload)) payload.e_r = true;

const q = crypto.eapi.encryptRequest('http://' + HOST + path, payload);
// encryptRequest rewrites /api/ -> /eapi/; PROBE_KEEP_API=1 keeps the original path
const urlPath =
	process.env.PROBE_KEEP_API === '1' ? path : new URL(q.url).pathname;
const headers = {
	'Content-Type': 'application/x-www-form-urlencoded',
	'Content-Length': Buffer.byteLength(q.body),
	'User-Agent':
		'NeteaseMusic/3.1.34.205281(2069);Microsoft-Windows-10-Professional-build-19045-64bit',
	Cookie: 'os=pc; appver=' + APPVER + '; channel=netease',
	'X-Real-IP': '118.88.88.88',
	Accept: '*/*',
};

const decode = (res, buf) => {
	const ce = res.headers['content-encoding'];
	let b = buf;
	const zlib = require('zlib');
	try {
		if (ce === 'gzip') b = zlib.gunzipSync(b);
		else if (ce === 'deflate') b = zlib.inflateSync(b);
		else if (ce === 'br') b = zlib.brotliDecompressSync(b);
	} catch (e) {}
	let json = null;
	let via = '?';
	try {
		json = JSON.parse(b.toString('utf8'));
		via = 'plaintext';
	} catch (e) {
		try {
			json = JSON.parse(crypto.eapi.decrypt(b).toString('utf8'));
			via = 'eapi';
		} catch (e2) {
			via = 'undecodable';
		}
	}
	return { status: res.statusCode, bytes: buf.length, ce: ce || '-', via, json, raw: b };
};

const doDirect = () =>
	new Promise((resolve) => {
		const req = https.request(
			{ host: HOST, path: urlPath, method: 'POST', headers },
			(res) => {
				const cs = [];
				res.on('data', (c) => cs.push(c));
				res.on('end', () => resolve(decode(res, Buffer.concat(cs))));
			}
		);
		req.on('error', (e) => resolve({ error: e.message }));
		req.end(q.body);
	});

const doProxy = () =>
	new Promise((resolve) => {
		const [ph, pp] = PROXY.split(':');
		const creq = http.request({
			host: ph,
			port: parseInt(pp || '8080'),
			method: 'CONNECT',
			path: HOST + ':443',
			headers: { host: HOST + ':443' },
		});
		creq.on('connect', (cres, socket) => {
			if (cres.statusCode !== 200)
				return resolve({ error: 'CONNECT ' + cres.statusCode });
			const t = tls.connect(
				{ socket, servername: HOST, rejectUnauthorized: false },
				() => {
					const req = http.request(
						{
							method: 'POST',
							path: urlPath,
							headers,
							createConnection: () => t,
							agent: false,
						},
						(res) => {
							const cs = [];
							res.on('data', (c) => cs.push(c));
							res.on('end', () => resolve(decode(res, Buffer.concat(cs))));
						}
					);
					req.on('error', (e) => resolve({ error: 'req: ' + e.message }));
					req.end(q.body);
				}
			);
			t.on('error', (e) => resolve({ error: 'tls: ' + e.message }));
		});
		creq.on('error', (e) => resolve({ error: 'connect: ' + e.message }));
		creq.end();
	});

(async () => {
	const d = await doDirect();
	const p = await doProxy();
	const show = (tag, r) => {
		console.log(`\n### ${tag}`);
		if (r.error) return console.log('  ERROR:', r.error);
		console.log(`  status=${r.status} bytes=${r.bytes} ce=${r.ce} decode=${r.via}`);
		const s = r.json ? JSON.stringify(r.json) : r.raw.toString('utf8').slice(0, 300);
		console.log('  ' + s.slice(0, 700));
	};
	show('DIRECT', d);
	show('VIA-PROXY', p);
	if (d.json && p.json) {
		const same = JSON.stringify(d.json) === JSON.stringify(p.json);
		console.log('\n=== IDENTICAL: ' + same + ' ===');
		if (!same) {
			const ks = new Set([...Object.keys(d.json), ...Object.keys(p.json)]);
			for (const k of ks) {
				const a = JSON.stringify(d.json[k]);
				const b = JSON.stringify(p.json[k]);
				if (a !== b)
					console.log(`  DIFF [${k}]:\n    direct: ${(a || '').slice(0, 200)}\n    proxy : ${(b || '').slice(0, 200)}`);
			}
		}
	}
})();
