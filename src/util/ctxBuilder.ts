import { callService } from "home-assistant-js-websocket";
import { getState } from "~/connectors/homeassistant/stateCache";
import { conn } from "~/connectors/homeassistant/ws";
import timers from "~/connectors/timers";
import kv from "~/kv";
import type { AutomationContext, Cap, Capabilities, EntityId } from "~/types";

export const providers: { [K in Cap]: () => Capabilities[K] } = {
	homeassistant: () => ({
		callService: (
			domain: string,
			service: string,
			target?: object,
			data?: object,
		) => callService(conn, domain, service, data, target),
		getState,
	}),
	kv: () => kv,
	timer: () => timers,
};

export default function ctxBuilder(name: string, req: Cap[] = []) {
	const ctx: Record<string, unknown> = {
		name,
		log: (...a: unknown[]) => console.log(`[${ctx.name}]`, ...a),
	};

	for (const r of req) ctx[r] = providers[r]();

	return ctx as AutomationContext<Cap>;
}
