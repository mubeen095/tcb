# ───────────────────────────────────────────────
# Stage 1: Frontend dependency install
# ───────────────────────────────────────────────
FROM oven/bun:1-alpine AS frontend-deps
RUN apk update && apk add --no-cache libc6-compat && rm -rf /var/cache/apk/*
WORKDIR /app

COPY apps/web/package.json apps/web/bun.lock* ./
RUN bun install --frozen-lockfile

# ───────────────────────────────────────────────
# Stage 2: Frontend build
# ───────────────────────────────────────────────
FROM oven/bun:1-alpine AS frontend-builder
WORKDIR /app
COPY --from=frontend-deps /app/node_modules ./node_modules
COPY apps/web .

# Disable telemetry during build
ENV NEXT_TELEMETRY_DISABLED=1

# Remove .env files to avoid leaking secrets into the build
RUN rm -f .env*

RUN bun run build

# ───────────────────────────────────────────────
# Stage 3: Frontend production image
# ───────────────────────────────────────────────
FROM node:24-alpine AS frontend-runner
WORKDIR /app

RUN apk update && apk add --no-cache curl && rm -rf /var/cache/apk/*

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1

RUN addgroup --system --gid 1001 nodejs \
    && adduser --system --uid 1001 nextjs

COPY --from=frontend-builder /app/public ./public

RUN mkdir .next && chown nextjs:nodejs .next

# Leverage output traces to reduce image size
COPY --from=frontend-builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=frontend-builder --chown=nextjs:nodejs /app/.next/static ./.next/static

# Copy server wrapper for runtime environment variable injection
COPY --chown=nextjs:nodejs apps/web/server-wrapper.js ./
RUN chmod +x server-wrapper.js

# ───────────────────────────────────────────────
# Final image - Frontend only
# ───────────────────────────────────────────────
FROM node:24-alpine AS runner

RUN apk update && apk add --no-cache nginx curl && rm -rf /var/cache/apk/*

RUN npm install -g pm2

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1

# Copy the frontend standalone build
COPY --from=frontend-runner /app /app/web

# Copy configs and scripts
COPY ./docker/nginx.conf /etc/nginx/conf.d/default.conf
COPY ./docker/start.sh /app/start.sh
RUN chmod +x /app/start.sh

ENV PORT=8000 HOSTNAME=0.0.0.0

EXPOSE 80

CMD ["sh", "/app/start.sh"]
