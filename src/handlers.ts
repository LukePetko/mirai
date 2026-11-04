import type { Handler } from "./types";

export const handlers = new Set<Handler>();

export const subscribe = (h: Handler) => {
	handlers.add(h);
	return () => handlers.delete(h);
};
