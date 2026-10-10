import { join, parse, resolve } from "node:path";
import env from "./util/env";
import type { Automation, Cap } from "./types";

const isAutomation = (x: unknown): x is Automation<Cap> =>
	typeof x === "object" &&
	x !== null &&
	typeof (x as Automation<Cap>).f === "function";

export const importAll = async () => {
	const imports: Record<string, Automation<Cap>> = {};
	const path = resolve(env.AUTOMATIONS_PATH);

	const glob = new Bun.Glob("**/*.ts");
	for await (const file of glob.scan({ cwd: path, onlyFiles: true })) {
		if (file.endsWith(".d.ts") || file.includes("node_modules")) continue;

		const { dir, name } = parse(file);
		const key = join(dir, name);

		try {
			const mod = await import(join(path, file));
			if (!isAutomation(mod.default)) {
				console.warn(`[${key}] is not an automation`);
				continue;
			}
			imports[key] = mod.default;
		} catch (err) {
			console.error(`[${key}] failed to load:`, err);
		}
	}

	console.log(`[loader] Loaded ${Object.keys(imports).length} automations`);
	return imports;
};
