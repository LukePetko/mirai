import z from "zod";

const envSchema = z.object({
	HA_HOST: z.string(),
	HA_TOKEN: z.string(),
	AUTOMATIONS_PATH: z.string(),
	KV_PATH: z.string().default("kv.sqlite"),
});

const parsed = envSchema.safeParse(process.env);

if (!parsed.success) {
	throw new Error(`Invalid environment variables: ${parsed.error}`);
}

export type Env = z.infer<typeof envSchema>;

export default parsed.data;
