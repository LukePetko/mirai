export type Source = "homeassistant" | "mqtt";
export type EventType = "state_changed";

export interface Register {}

type CommonStates = "unavailable" | "unknown";

type DomainStates = {
	light: "on" | "off";
	switch: "on" | "off";
	binary_sensor: "on" | "off";
	input_boolean: "on" | "off";
	cover: "open" | "closed" | "opening" | "closing";
};

type EventTypes = Register extends { eventTypes: infer S } ? S : {};

type AttributesOf<E extends string> = E extends keyof EventTypes
	? { event_type: EventTypes[E] | null } & Record<string, unknown>
	: Record<string, unknown>;

type EntityStates = Register extends { entityStates: infer S } ? S : {};

export type StateOf<E extends string> =
	| CommonStates
	| (E extends keyof EntityStates
			? EntityStates[E]
			: E extends `${infer D}.${string}`
				? D extends keyof DomainStates
					? DomainStates[D]
					: string
				: string);

export type EntityId = Register extends { entityId: infer E extends string }
	? E
	: string;

export type EntityState<
	S extends string = string,
	A = Record<string, unknown>,
> = {
	state: S;
	attributes: A;
	lastChanged: Date;
};

export type MiraiEvent = {
	[E in EntityId]: {
		source: Source;
		event_type: EventType;
		entity_id: E;
		old_state: EntityState<StateOf<E>, AttributesOf<E>> | null;
		new_state: EntityState<StateOf<E>, AttributesOf<E>> | null;
	};
}[EntityId];

export type Handler = (e: MiraiEvent) => void;

export type Services = Register extends {
	services: infer S extends Record<string, string>;
}
	? S
	: Record<string, string>;

export type ServiceData<D extends string, S extends string> = Register extends {
	serviceData: infer SD;
}
	? D extends keyof SD
		? S extends keyof SD[D]
			? SD[D][S]
			: object
		: object
	: object;

export type EntityOf<D extends string> = string extends EntityId
	? string
	: D extends "homeassistant"
		? EntityId
		: Extract<EntityId, `${D}.${string}`>;

export type Capabilities = {
	homeassistant: {
		callService<D extends keyof Services & string, S extends Services[D]>(
			domain: D,
			service: S,
			target?: { entity_id: NoInfer<EntityOf<D> | EntityOf<D>[]> },
			data?: NoInfer<ServiceData<D, S>>,
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
