import { join, parse, resolve } from "node:path";
import env from "./util/env";
import { readdir } from "node:fs/promises";

export const importAll = async () => {
	const imports: { [key: string]: any } = {};
	const path = resolve(env.AUTOMATIONS_PATH);

	const files = (await readdir(path, { recursive: true })).filter(
		(file) => file.endsWith(".ts") && !file.endsWith(".d.ts"),
	);

	for (const file of files) {
		const { dir, name } = parse(file);
		const key = join(dir, name);
		const mod = await import(join(path, file));
		console.log(mod);
		imports[key] = mod.default;
	}

	return imports;
};
