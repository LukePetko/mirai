import type { HassEvent } from "home-assistant-js-websocket";
import { callService } from "home-assistant-js-websocket";
import { conn } from "~/connectors/homeassistant/ws";
import { importAll } from "~/loader";
import type { MiraiEvent } from "~/types";

console.log("Hello via Bun!");

type Handler = (e: MiraiEvent) => void;
const handlers = new Set<Handler>();

const imports = await importAll();

export const subscribe = (h: Handler) => {
	handlers.add(h);
	return () => handlers.delete(h);
};

// subscribe((e) => {
// 	if (
// 		e.entity_id === "sensor.0x84ba20fffe97b036_action" &&
// 		e.new_state?.state === "on"
// 	) {
// 		console.log(e);
// 		callService(
// 			conn,
// 			"light",
// 			"toggle",
// 			{},
// 			{
// 				entity_id: [
// 					"light.office_top_light_white",
// 					"light.office_top_light_rgb",
// 				],
// 			}, // target: the "who"
// 		);
// 	}
// });

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

for (const [name, automation] of Object.entries(imports)) {
	const ctx = {
		name,
		callService: (
			domain: string,
			service: string,
			target?: object,
			data?: object,
		) => callService(conn, domain, service, data, target),
		log: (...a: unknown[]) => console.log(`[${name}]`, ...a),
	};

	subscribe((e) => {
		try {
			automation(e, ctx);
		} catch (err) {
			console.error(`[${name}] crashed:`, err);
		}
	});
}
