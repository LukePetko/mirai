import { getStates, type Connection } from "home-assistant-js-websocket";
import type { AttributesOf, EntityId, EntityState, StateOf } from "~/types";
import toState from "./util/toState";

const cache = new Map<string, EntityState>();

export const syncStates = async (conn: Connection) => {
	const states = await getStates(conn);
	cache.clear();
	for (const s of states) {
		const state = toState(s);
		if (state) cache.set(s.entity_id, state);
	}
};

export const updateState = (id: string, state: EntityState | null) => {
	if (state) cache.set(id, state);
	else cache.delete(id);
};

export const getState = <E extends EntityId>(id: E) =>
	cache.get(id) as EntityState<StateOf<E>, AttributesOf<E>> | undefined;
