export type { Automation, AutomationContext, Cap, MiraiEvent } from "./types";
import type { Automation, Cap } from "./types";

export const defineAutomation = <R extends Cap = never>(a: Automation<R>) => a;
