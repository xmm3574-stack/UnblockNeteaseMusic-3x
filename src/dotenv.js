/**
 * A very simple dotenv implementation.
 */

//@ts-check

const fs = require('fs');
const readline = require('readline');
const path = require('path');

/**
 * Parse .env file.
 *
 * @param {string} filePath
 * @returns {Promise<Record<string, string>>}
 */
async function parseDotenv(filePath) {
	const env = /**@type {Record<string, string>}*/ ({});
	const rl = readline.createInterface({
		input: fs.createReadStream(filePath),
		crlfDelay: Infinity,
	});

	for await (const line of rl) {
		if (line.startsWith('#')) continue;

		const [key, value] = line.split(/=(.+)/, 2);
		env[key.trimEnd()] = value.trimStart();
	}

	return env;
}

/**
 * Find .env file.
 *
 * Lookup order:
 *   1. current working directory   (source / `node src/app.js`)
 *   2. directory next to the exe   (pkg build, so the .env sits beside unm-3x.exe)
 *   3. directory of this module    (fallback)
 *
 * @returns {Promise<string|null>}
 */
async function findEnv() {
	const candidates = [path.join(process.cwd(), '.env')];

	if (process.pkg && process.execPath) {
		// pkg build: process.execPath is the real exe on disk
		candidates.push(path.join(path.dirname(process.execPath), '.env'));
	}
	candidates.push(path.join(__dirname, '..', '.env'));

	for (const envPath of candidates) {
		try {
			await fs.promises.access(envPath, fs.constants.R_OK);
			return envPath;
		} catch (err) {
			// try next candidate
		}
	}

	return null;
}

/**
 * Inject environment variables into process.env.
 *
 * @param {Record<string, string>} env
 * @returns {void}
 */
function injectEnv(env) {
	// https://github.com/motdotla/dotenv/blob/aa03dcad1002027390dac1e8d96ac236274de354/lib/main.js#L277
	for (const [key, value] of Object.entries(env)) {
		// the priority of .env is lower than process.env
		// due to Node.js 12, we don't use nullish coalescing operator
		process.env[key] = process.env[key] == null ? value : process.env[key];
	}

	return;
}

/**
 * A simple method for finding .env file and injecting
 * environment variables into process.env.
 *
 * No exceptions will be raised – we have handled errors
 * inside this code.
 *
 * @returns {Promise<void>}
 */
async function loadDotenv() {
	const envPath = await findEnv();
	if (envPath == null) {
		return;
	}

	try {
		const env = await parseDotenv(envPath);
		injectEnv(env);
	} catch (e) {
		console.error(e);
	}

	return;
}

/**
 * Synchronous variant, used at the very top of `src/app.js` so that
 * `process.env` is populated before any module reads it.
 *
 * @returns {string|null} the .env path that was loaded
 */
function loadDotenvSync() {
	const candidates = [path.join(process.cwd(), '.env')];
	if (process.pkg && process.execPath)
		candidates.push(path.join(path.dirname(process.execPath), '.env'));
	candidates.push(path.join(__dirname, '..', '.env'));

	for (const envPath of candidates) {
		let content;
		try {
			content = fs.readFileSync(envPath, 'utf8');
		} catch (e) {
			continue;
		}

		const env = {};
		for (const rawLine of content.split(/\r?\n/)) {
			const line = rawLine.trim();
			if (!line || line.startsWith('#')) continue;
			const idx = line.indexOf('=');
			if (idx <= 0) continue;
			const key = line.slice(0, idx).trim();
			let value = line.slice(idx + 1).trim();
			// strip matching surrounding quotes
			if (
				(value.startsWith('"') && value.endsWith('"')) ||
				(value.startsWith("'") && value.endsWith("'"))
			)
				value = value.slice(1, -1);
			if (key) env[key] = value;
		}

		injectEnv(env);
		return envPath;
	}

	return null;
}

module.exports = {
	loadDotenv,
	loadDotenvSync,
	injectEnv,
	findEnv,
	parseDotenv,
};
