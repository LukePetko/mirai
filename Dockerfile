FROM oven/bun:1.3-slim
WORKDIR /app

# deps first, so this layer is cached until package.json/bun.lock change
COPY package.json bun.lock ./
RUN bun install --production --frozen-lockfile

COPY tsconfig.json index.ts ./
COPY src ./src

# the named volume takes this dir's ownership the first time it's created
RUN mkdir /data && chown bun:bun /data

ENV NODE_ENV=production
USER bun

CMD ["bun", "--no-install", "index.ts"]
