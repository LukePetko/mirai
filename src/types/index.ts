export type Source = "homeassistant" | "mqtt";

type EntityState = {
	state: string;
	attributes: Record<string, unknown>;
	lastChanged: Date;
};

export type MiraiEvent = {
	source: Source;
	entity_id: string;
	old_state?: EntityState;
	new_state?: EntityState;
};
