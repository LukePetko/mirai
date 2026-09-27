import {
	createConnection,
	createLongLivedTokenAuth,
} from "home-assistant-js-websocket";
import env from "../../util/env";

const auth = createLongLivedTokenAuth(env.HA_HOST, env.HA_TOKEN);
export const conn = await createConnection({ auth });
