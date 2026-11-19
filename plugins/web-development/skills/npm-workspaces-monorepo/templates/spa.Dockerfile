# apps/<app>/Dockerfile for a static Vite SPA. Build context is the repo root.
FROM node:24-slim AS build
WORKDIR /app

COPY package.json package-lock.json ./
COPY apps/<app>/package.json ./apps/<app>/package.json

RUN npm ci --workspace=apps/<app>

COPY apps/<app> ./apps/<app>
RUN npm run build --workspace=apps/<app>

FROM nginx:alpine
COPY --from=build /app/apps/<app>/dist /usr/share/nginx/html
COPY apps/<app>/nginx.conf /etc/nginx/conf.d/default.conf
