import type { Timers } from "~/types";

const timers = new Map<string, Timer>();

export const createTimers = (): Timers => {
	const cancel = (name: string) => {
		timers.delete(name);
	};

	return {
		set(name, ms, fn) {
			cancel(name);
			const t = setTimeout(async () => {
				try {
					await fn();
				} catch (err) {
					console.error(`[timers] timer "${name}" failed:`, err);
				}
			}, ms);
			timers.set(name, t);
		},
		cancel,
		has: (name) => timers.has(name),
	};
};

export const cancelAll = (owner: string) => {
	for (const t of timers.values()) clearTimeout(t);
	timers.clear();
};
