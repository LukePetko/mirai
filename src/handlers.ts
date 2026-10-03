import type { Handler } from "./types";

const handlers = new Set<Handler>();

export const subscribe = (h: Handler) => {
	handlers.add(h);
	return () => handlers.delete(h);
};
