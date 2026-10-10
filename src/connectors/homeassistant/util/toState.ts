import type { HassEntity } from "home-assistant-js-websocket";
import type { EntityState } from "~/types";

export default function toState(state: HassEntity | null): EntityState | null {
	return state
		? {
				state: state.state,
				attributes: state.attributes,
				lastChanged: new Date(state.last_changed),
			}
		: null;
}
