'use strict';
// eapi probe: ask NetEase directly for a play URL and dump the real response.
// usage: node probe_eapi.js <songId> [songId...]
// env:   PROBE_HOST PROBE_APPVER PROBE_LEVEL PROBE_ER=0 DUMP_BODY=<file>
const https = require('https');
const crypto = require('./unm-3x/src/crypto');

const ids = process.argv.slice(2);
if (!ids.length) {
	console.error('usage: node probe_eapi.js <songId> [songId...]');
	process.exit(1);
}

const HOST = process.env.PROBE_HOST || 'interfacepc.music.163.com';
const APPVER = process.env.PROBE_APPVER || '3.1.34.205281';
const LEVEL = process.env.PROBE_LEVEL || 'sky';
const E_R = process.env.PROBE_ER !== '0';

const header = JSON.stringify({
	clientSign: 'BC:FC:E7:19:0B:F6',
	os: 'pc',
	appver: APPVER,
	deviceId: 'FFBFB719F6ADC025CA7F55F9262895CC7970A3DBBCFCE7190BF6',
	requestId: 0,
	osver: 'Microsoft-Windows-10-Professional-build-19045-64bit',
});

const payload = {
	ids: JSON.stringify(ids.map(String)),
	level: LEVEL,
	immerseType: 'ste',
	encodeType: 'aac',
	trialMode: -1,
	header,
};
if (E_R) payload.e_r = true;

const apiPath = '/api/song/enhance/player/url/v1';
const query = crypto.eapi.encryptRequest('http://' + HOST + apiPath, payload);

// DUMP_BODY=<file>: only write the request body to disk for curl replay via proxy
if (process.env.DUMP_BODY) {
	require('fs').writeFileSync(process.env.DUMP_BODY, query.body);
	console.log('url_path=' + new URL(query.url).pathname);
	console.log('body=' + process.env.DUMP_BODY + ' (' + query.body.length + 'B)');
	console.log('host=' + HOST);
	process.exit(0);
}

const req = https.request(
	{
		host: HOST,
		path: new URL(query.url).pathname,
		method: 'POST',
		headers: {
			'Content-Type': 'application/x-www-form-urlencoded',
			'Content-Length': Buffer.byteLength(query.body),
			'User-Agent':
				'NeteaseMusic/3.1.34.205281(2069);Microsoft-Windows-10-Professional-build-19045-64bit',
			Cookie:
				'os=pc; appver=' + APPVER + '; channel=netease; __remember_me=true',
			'X-Real-IP': '118.88.88.88',
			Accept: '*/*',
		},
	},
	(res) => {
		const chunks = [];
		res.on('data', (c) => chunks.push(c));
		res.on('end', () => {
			const buf = Buffer.concat(chunks);
			console.log('HTTP', res.statusCode, 'bytes', buf.length);
			console.log('headers:', JSON.stringify(res.headers));
			try {
				const j = JSON.parse(buf.toString('utf8'));
				console.log('=== PLAINTEXT JSON ===');
				console.log(JSON.stringify(j, null, 2));
				return;
			} catch (e) {
				console.log('not plaintext json, trying eapi decrypt...');
			}
			try {
				const dec = crypto.eapi.decrypt(buf).toString('utf8');
				console.log('=== DECRYPTED ===');
				try {
					console.log(JSON.stringify(JSON.parse(dec), null, 2));
				} catch (e2) {
					console.log(dec.slice(0, 4000));
				}
			} catch (e3) {
				console.log('decrypt failed:', e3.message);
				console.log('raw hex head:', buf.slice(0, 64).toString('hex'));
				console.log('raw text head:', buf.slice(0, 400).toString('utf8'));
			}
		});
	}
);
req.on('error', (e) => console.error('request error:', e.message));
req.end(query.body);
