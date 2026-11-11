'use strict';
// 鎵归噺鎺㈡祴 player/url/v1 鐨勫搷搴斿舰鎬侊紝鎵惧嚭銆宑ode=200 浣?url=null銆嶈繖绫讳笉瑙﹀彂鎹㈡簮鐨勭伆姝?// 鐢ㄦ硶: node probe_batch.js "鍏抽敭璇?" "鍏抽敭璇?" ...
const https = require('https');
const http = require('http');
const crypto = require('./unm-3x/src/crypto');

const HOST = 'interfacepc.music.163.com';
const APPVER = '3.1.34.205281';
const UA = 'NeteaseMusic/3.1.34.205281(2069);Microsoft-Windows-10-Professional-build-19045-64bit';
const COOKIE = process.env.NETEASE_COOKIE || 'os=pc; appver=' + APPVER;

const eapiPost = (path, payload, cb) => {
	const q = crypto.eapi.encryptRequest('http://' + HOST + path, payload);
	const req = https.request(
		{
			host: HOST,
			path: new URL(q.url).pathname,
			method: 'POST',
			headers: {
				'Content-Type': 'application/x-www-form-urlencoded',
				'Content-Length': Buffer.byteLength(q.body),
				'User-Agent': UA,
				Cookie: COOKIE,
				'X-Real-IP': '118.88.88.88',
			},
		},
		(res) => {
			const cs = [];
			res.on('data', (c) => cs.push(c));
			res.on('end', () => {
				const buf = Buffer.concat(cs);
				let j = null;
				try {
					j = JSON.parse(buf.toString('utf8'));
				} catch (e) {
					try {
						j = JSON.parse(crypto.eapi.decrypt(buf).toString('utf8'));
					} catch (e2) {
						try {
							j = JSON.parse(
								crypto.eapi.decrypt(buf).toString('utf8').split('}')[0] + '}'
							);
						} catch (e3) {
							j = { _parseError: e3.message, _len: buf.length };
						}
					}
				}
				cb(j);
			});
		}
	);
	req.on('error', (e) => cb({ _error: e.message }));
	req.end(q.body);
};

const headerStr = JSON.stringify({
	clientSign: 'BC:FC:E7:19:0B:F6',
	os: 'pc',
	appver: APPVER,
	deviceId: 'FFBFB719F6ADC025CA7F55F9262895CC7970A3DBBCFCE7190BF6',
	requestId: 0,
	osver: 'Microsoft-Windows-10-Professional-build-19045-64bit',
});

const urlPayload = (id) => ({
	ids: JSON.stringify([String(id)]),
	level: 'sky',
	immerseType: 'ste',
	encodeType: 'aac',
	trialMode: -1,
	e_r: true,
	header: headerStr,
});

const search = (kw, cb) => {
	const q = crypto.eapi.encryptRequest('http://' + HOST + '/api/cloudsearch/pc', {
		s: kw,
		type: 1,
		limit: 30,
		offset: 0,
		total: true,
		header: headerStr,
	});
	const req = https.request(
		{
			host: HOST,
			path: new URL(q.url).pathname,
			method: 'POST',
			headers: {
				'Content-Type': 'application/x-www-form-urlencoded',
				'Content-Length': Buffer.byteLength(q.body),
				'User-Agent': UA,
				Cookie: COOKIE,
				'X-Real-IP': '118.88.88.88',
			},
		},
		(res) => {
			const cs = [];
			res.on('data', (c) => cs.push(c));
			res.on('end', () => {
				const buf = Buffer.concat(cs);
				let j = null;
				try {
					j = JSON.parse(buf.toString('utf8'));
				} catch (e) {
					try {
						j = JSON.parse(crypto.eapi.decrypt(buf).toString('utf8'));
					} catch (e2) {
						j = null;
					}
				}
				cb(j);
			});
		}
	);
	req.on('error', () => cb(null));
	req.end(q.body);
};

const kws = process.argv.slice(2);
if (!kws.length) kws.push('鍛ㄦ澃浼?);

const classify = (d) => {
	if (!d) return 'NO-DATA';
	const parts = [];
	parts.push('code=' + d.code);
	parts.push('url=' + (d.url ? (d.url.length > 40 ? 'YES' : 'YES') : String(d.url)));
	parts.push('fee=' + d.fee);
	parts.push('br=' + d.br);
	parts.push('lvl=' + d.level);
	parts.push('free=' + (d.freeTrialInfo ? 'Y(' + d.freeTrialInfo.start + '-' + d.freeTrialInfo.end + ')' : 'N'));
	return parts.join(' ');
};

(async () => {
	const stats = {};
	for (const kw of kws) {
		await new Promise((resolve) => {
			search(kw, async (j) => {
				const songs = (j && j.result && j.result.songs) || [];
				console.log(`\n### ${kw}  -> ${songs.length} songs`);
				let idx = 0;
				const next = () => {
					if (idx >= songs.length) return resolve();
					const s = songs[idx++];
					eapiPost('/api/song/enhance/player/url/v1', urlPayload(s.id), (r) => {
						const d = r && r.data && r.data[0];
						let tag;
						let key;
						if (!d) {
							tag = 'NO-DATA ' + JSON.stringify(r).slice(0, 120);
							key = 'NO-DATA';
						} else {
							tag = classify(d);
							// 瑙﹀彂鎹㈡簮鐨勬潯浠?							const wouldReplace =
								d.code !== 200 || !!d.freeTrialInfo || (d.br || 0) < 0;
							const grayButNoReplace =
								d.code === 200 && !d.url && !d.freeTrialInfo;
							key =
								(grayButNoReplace
									? 'GRAY-NO-REPLACE'
									: wouldReplace
									? 'WILL-REPLACE'
									: 'PLAYABLE') + ' code=' + d.code;
							if (grayButNoReplace) tag += '   <<< 鐏版瓕浣嗕笉鎹㈡簮';
						}
						stats[key] = (stats[key] || 0) + 1;
						console.log(`  [${s.id}] ${s.name} / ${(s.ar||[]).map(a=>a.name).join(',')} :: ${tag}`);
						setTimeout(next, 120);
					});
				};
				next();
			});
		});
	}
	console.log('\n=== SUMMARY ===');
	Object.entries(stats)
		.sort((a, b) => b[1] - a[1])
		.forEach(([k, v]) => console.log(v + '\t' + k));
})();

