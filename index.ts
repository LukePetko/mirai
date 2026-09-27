import type { HassEvent } from "home-assistant-js-websocket";
import { conn } from "./src/connectors/homeassistant/ws";

console.log("Hello via Bun!");

await conn.subscribeEvents((e: HassEvent) => {
	const { entity_id, old_state, new_state } = e.data;
	console.log(entity_id, old_state?.state, "→", new_state?.state);
}, "state_changed");
