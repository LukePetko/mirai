import type { HassEvent } from "home-assistant-js-websocket";
import { conn } from "~/connectors/homeassistant/ws";
import type { MiraiEvent } from "~/types";

console.log("Hello via Bun!");

type Handler = (e: MiraiEvent) => void;
const handlers = new Set<Handler>();

export const subscribe = (h: Handler) => {
	handlers.add(h);
	return () => handlers.delete(h);
};

subscribe((e) => {
	console.log(e);
});

export const publish = (e: MiraiEvent) => {
	for (const h of handlers) h(e);
};

await conn.subscribeEvents((e: HassEvent) => {
	const { entity_id, old_state, new_state } = e.data;
	// console.log(entity_id, old_state?.state, "→", new_state?.state);
	const event: MiraiEvent = {
		source: "homeassistant",
		entity_id,
		old_state,
		new_state,
	};

	publish(event);
}, "state_changed");
