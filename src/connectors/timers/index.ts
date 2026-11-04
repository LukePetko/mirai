import type { Timers } from "~/types";

const store = new Map<string, Timer>();

const cancel = (name: string) => {
	clearTimeout(store.get(name));
	store.delete(name);
};

const timers: Timers = {
	set(name, ms, fn) {
		cancel(name);
		const t = setTimeout(async () => {
			store.delete(name);
			try {
				await fn();
			} catch (err) {
				console.error(`[timers] timer "${name}" failed:`, err);
			}
		}, ms);
		store.set(name, t);
	},
	cancel,
	has: (name) => store.has(name),
};

export const cancelAll = () => {
	for (const t of store.values()) clearTimeout(t);
	store.clear();
};

export default timers;
