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

export type Handler = (e: MiraiEvent) => void;

export type Capabilities = {
	homeassistant: {
		callService(
			domain: string,
			service: string,
			target?: object,
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
	f: (e: MiraiEvent, ctx: AutomationContext<R>) => Promise<unknown>;
	require?: string[];
};
