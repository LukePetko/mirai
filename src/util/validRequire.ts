import type { Cap } from "~/types";
import { providers } from "./ctxBuilder";

export default function validRequire(req: unknown): req is Cap[] {
	return (
		req === undefined ||
		(Array.isArray(req) &&
			req.every((r) => typeof r === "string" && Object.hasOwn(providers, r)))
	);
}
