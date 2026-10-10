import { resolve } from "node:path";
import env from "~/util/env";
import { createSqliteKV } from "./sqlite";

const kv = createSqliteKV(resolve(env.KV_PATH));

export default kv;
