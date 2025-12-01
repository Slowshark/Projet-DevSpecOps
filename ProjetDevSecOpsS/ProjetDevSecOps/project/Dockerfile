FROM node:18-alpine AS frontend-build

WORKDIR /app

COPY package*.json ./
RUN npm install

COPY . .
RUN npm run build

FROM node:18-alpine AS production

WORKDIR /app

COPY server/package*.json ./
RUN apk add --no-cache curl && \
    npm install --production && \
    npm cache clean --force

COPY server/index.js ./server/index.js
COPY --from=frontend-build /app/dist ./dist

EXPOSE 3000

ENV NODE_ENV=production

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -f http://localhost:3000/api/health || exit 1

CMD ["node", "server/index.js"]
