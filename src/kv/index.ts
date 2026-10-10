import { createSqliteKV } from "./sqlite";

const kv = createSqliteKV("kv.sqlite");

export default kv;
