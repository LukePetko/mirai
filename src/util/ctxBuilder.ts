import { callService } from "home-assistant-js-websocket";
import { conn } from "~/connectors/homeassistant/ws";
import type { AutomationContext, Cap, Capabilities } from "~/types";

const providers: { [K in Cap]: () => Capabilities[K] } = {
	homeassistant: () => ({
		callService: (
			domain: string,
			service: string,
			target?: object,
			data?: object,
		) => callService(conn, domain, service, data, target),
	}),
};

export default function ctxBuilder(name: string, req: Cap[]) {
	const ctx: Record<string, unknown> = {
		name,
		log: (...a: unknown[]) => console.log(`[${ctx.name}]`, ...a),
	};

	for (const r of req) ctx[r] = providers[r]();

	return ctx as AutomationContext<Cap>;
}
