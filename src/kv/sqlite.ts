import { Database } from "bun:sqlite";
import type { KV } from "~/types";

export const createSqliteKV = (path: string): KV => {
	const db = new Database(path, { create: true });
	db.run("PRAGMA journal_mode = WAL");
	db.run(`CREATE TABLE IF NOT EXISTS kv (
		key TEXT PRIMARY KEY,
		value TEXT NOT NULL,
		expires_at INTEGER
	)`);

	const getStmt = db.query<
		{ value: string; expires_at: number | null },
		[string]
	>("SELECT value, expires_at FROM kv WHERE key = ?");
	const setStmt = db.query<unknown, [string, string, number | null]>(
		`INSERT INTO kv (key, value, expires_at) VALUES (?, ?, ?)
		 ON CONFLICT(key) DO UPDATE SET value = excluded.value, expires_at = excluded.expires_at`,
	);
	const delStmt = db.query<unknown, [string]>("DELETE FROM kv WHERE key = ?");

	return {
		async get<T>(key: string) {
			const row = getStmt.get(key);
			if (!row) return undefined;
			if (row.expires_at !== null && row.expires_at <= Date.now()) {
				delStmt.run(key);
				return undefined;
			}
			return JSON.parse(row.value) as T;
		},
		async set(key, value, opts) {
			if (value === undefined) return delStmt.run(key), undefined;
			setStmt.run(
				key,
				JSON.stringify(value),
				opts?.ttl ? Date.now() + opts.ttl : null,
			);
		},
		async delete(key) {
			delStmt.run(key);
		},
	};
};
