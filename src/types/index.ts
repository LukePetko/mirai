export type Source = "homeassistant" | "mqtt";
export type EventType = "state_changed";

export interface Register {}

export type EntityId = Register extends { entityId: infer E extends string }
	? E
	: string;

type EntityState = {
	state: string;
	attributes: Record<string, unknown>;
	lastChanged: Date;
};

export type MiraiEvent = {
	source: Source;
	event_type: EventType;
	entity_id: EntityId;
	old_state?: EntityState;
	new_state?: EntityState;
};

export type Handler = (e: MiraiEvent) => void;

export type Services = Register extends {
	services: infer S extends Record<string, string>;
}
	? S
	: Record<string, string>;

export type EntityOf<D extends string> = string extends EntityId
	? string
	: D extends "homeassistant"
		? EntityId
		: Extract<EntityId, `${D}.${string}`>;

export type Capabilities = {
	homeassistant: {
		callService<D extends keyof Services & string>(
			domain: D,
			service: NoInfer<Services[D]>,
			target?: { entity_id: NoInfer<EntityOf<D> | EntityOf<D>[]> },
			data?: object,
		): Promise<unknown>;
	};
};

export type Cap = keyof Capabilities;

export type AutomationContext<R extends Cap> = {
	name: string;
	log: (...a: unknown[]) => void;
} & { [K in R]: Capabilities[K] };

export type Automation<R extends Cap = never> = {
	f: (e: MiraiEvent, ctx: AutomationContext<R>) => void | Promise<unknown>;
	require?: R[];
};

export type HassState = {
	entity_id: string;
	state: string;
	attributes: Record<string, unknown>;
};
