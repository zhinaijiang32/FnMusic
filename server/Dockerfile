FROM node:20-bookworm-slim AS dependencies

WORKDIR /app
COPY package.json package-lock.json ./

# better-sqlite3 may need a native build when no matching prebuild is present.
RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 make g++ \
    && npm ci --omit=dev \
    && apt-get purge -y --auto-remove python3 make g++ \
    && rm -rf /var/lib/apt/lists/*

FROM node:20-bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates openssl tini \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
ENV NODE_ENV=production \
    HTTPS_PORT=8443 \
    DATA_DIR=/app/data \
    MUSIC_STORE_PATH=/app/data/music

COPY --from=dependencies /app/node_modules ./node_modules
COPY package.json package-lock.json ./
COPY src ./src

RUN mkdir -p /app/data/music /app/data/db /app/data/certs /app/data/state

# The default process user is root so a manually selected NAS bind mount is
# writable without requiring users to discover a container-specific UID/GID.
# Keep this service on a trusted network as documented in the README.
EXPOSE 8443

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD node -e "require('https').get({host:'127.0.0.1',port:8443,path:'/api/health',rejectUnauthorized:false}, r => process.exit(r.statusCode === 200 ? 0 : 1)).on('error', () => process.exit(1))"

ENTRYPOINT ["tini", "--"]
CMD ["node", "src/index.js"]
