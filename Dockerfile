# Stage 1: Build frontend
FROM node:20-slim AS frontend
WORKDIR /app/web
COPY web/package.json web/pnpm-lock.yaml* ./
RUN corepack enable && pnpm install --frozen-lockfile || pnpm install
COPY web/ ./
RUN pnpm run build

# Stage 2: Build backend and embed frontend
FROM golang:1.26-bookworm AS backend
ENV GOPROXY=https://goproxy.cn,direct
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
COPY --from=frontend /app/static/out ./static/out
RUN CGO_ENABLED=0 go build -ldflags="-s -w" -o octopus .

# Stage 3: Export binary
FROM scratch AS export
COPY --from=backend /app/octopus /octopus
