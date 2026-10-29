import { plugin } from "bun";
import * as sdk from "./sdk";

plugin({
	name: "mirai-sdk",
	setup(build) {
		build.module("mirai", () => ({ exports: sdk, loader: "object" }));
	},
});
