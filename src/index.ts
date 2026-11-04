import { subscribe } from "./handlers";
import { importAll } from "./loader";
import ctxBuilder from "./util/ctxBuilder";

const imports = await importAll();

for (const [name, automation] of Object.entries(imports)) {
	const ctx = ctxBuilder(name, automation.require);

	subscribe(async (e) => {
		try {
			await automation.f(e, ctx);
		} catch (err) {
			console.error(`[${name}] crashed:`, err);
		}
	});
}
