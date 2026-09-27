# syntax=docker/dockerfile:1

# Yalnızca GELİŞTİRME için. Üretim için `Dockerfile.prod` (nginx, non-root).
#
# Bind-mount (`.:/app`) kullanıldığı için imaj içindeki `node_modules`
# adlandırılmış volume ile maskelenir; host'un `node_modules`'ü konteynere
# sızmaz. Vite HMR/inotify konteyner içinde çalışmayacağı için polling
# açıktır (docker-compose.yml'de CHOKIDAR_USEPOLLING).
FROM node:20-alpine

WORKDIR /app

# Kullanıcı oluştur: bind-mount içinde root olarak yazmamak için.
# (node:20-alpine `adduser -S` ile system kullanıcısı üretir.)
RUN addgroup -S calorix && adduser -S calorix -G calorix
USER calorix

COPY package.json package-lock.json ./
RUN npm ci

COPY --chown=calorix:calorix . .

EXPOSE 8080

# Vite'in `hmr.overlay: false` ayarı ve `host: "::"` ile tüm arayüzleri dinlemesi.
CMD ["npm", "run", "dev", "--", "--host", "0.0.0.0", "--port", "8080"]
