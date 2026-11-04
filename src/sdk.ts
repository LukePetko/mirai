export type {
	Automation,
	AutomationContext,
	Cap,
	MiraiEvent,
	HassState,
	EntityId,
	Register,
	StateOf,
} from "./types";
import type { Automation, Cap } from "./types";

export const defineAutomation = <R extends Cap = never>(a: Automation<R>) => a;
