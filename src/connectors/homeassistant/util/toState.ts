import type { EntityState } from "~/types";

export default function toState(state: any): EntityState | null {
	return state
		? {
				state: state.state,
				attributes: state.attributes,
				lastChanged: new Date(state.last_changed),
			}
		: null;
}
