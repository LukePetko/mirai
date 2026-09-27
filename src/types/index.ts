export type Source = "homeassistant" | "mqtt";
export type EventType = "state_changed";

type EntityState = {
	state: string;
	attributes: Record<string, unknown>;
	lastChanged: Date;
};

export type MiraiEvent = {
	source: Source;
	event_type: EventType;
	entity_id: string;
	old_state?: EntityState;
	new_state?: EntityState;
};
