FROM node:24.21.0-bookworm-slim AS build
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends openssl ca-certificates && rm -rf /var/lib/apt/lists/*
COPY package.json package-lock.json .npmrc ./
COPY scripts/install-dependencies.sh scripts/install-dependencies.sh
COPY apps/api/package.json apps/api/package.json
RUN bash scripts/install-dependencies.sh
COPY apps/api apps/api
RUN npm run db:generate && npm run build
FROM node:24.21.0-bookworm-slim AS runtime
ENV NODE_ENV=production
WORKDIR /app/apps/api
RUN apt-get update && apt-get install -y --no-install-recommends openssl ca-certificates && rm -rf /var/lib/apt/lists/*
COPY --from=build --chown=node:node /app/node_modules /app/node_modules
COPY --from=build --chown=node:node /app/apps/api/node_modules ./node_modules
COPY --from=build --chown=node:node /app/apps/api/dist ./dist
COPY --from=build --chown=node:node /app/apps/api/prisma ./prisma
COPY --from=build --chown=node:node /app/apps/api/prisma.config.ts ./prisma.config.ts
COPY --from=build --chown=node:node /app/apps/api/package.json ./package.json
RUN mkdir -p /var/lib/biobalance/media && chown node:node /var/lib/biobalance/media
USER node
RUN node -e "require('./dist/app.module');require.resolve('nodemailer')"
EXPOSE 3000
HEALTHCHECK --interval=20s --timeout=3s --retries=3 CMD node -e "fetch('http://127.0.0.1:3000/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
CMD ["node","dist/main.js"]
FROM runtime AS media
USER root
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg && rm -rf /var/lib/apt/lists/*
USER node
CMD ["node","dist/worker.js"]
