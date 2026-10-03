import type { HassEvent } from "home-assistant-js-websocket";
import type { MiraiEvent } from "~/types";
import { conn } from "./ws";
import { handlers } from "~/handlers";

export const publish = (e: MiraiEvent) => {
	for (const h of handlers) h(e);
};

await conn.subscribeEvents((e: HassEvent) => {
	const { entity_id, old_state, new_state } = e.data;
	// console.log(entity_id, old_state?.state, "→", new_state?.state);
	const event: MiraiEvent = {
		source: "homeassistant",
		event_type: "state_changed",
		entity_id,
		old_state,
		new_state,
	};

	publish(event);
}, "state_changed");
