# Builds the Go backend of ProjectHub from its submodule repo.
# Context must be the workspace root: docker build -f deploy/projecthub/api.Dockerfile .
# Backend Python deprecado: se migra a Go (ver backend-go/docs/migracion.md);
# mismo contrato JSON, misma BD (Postgres JSONB) y mismo puerto 8100.
FROM golang:1.27-alpine AS build

WORKDIR /src

COPY backend-go/go.mod backend-go/go.sum ./
RUN go mod download

COPY backend-go/ ./
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/server ./cmd/server

FROM gcr.io/distroless/static-debian12:nonroot

COPY --from=build /out/server /server

# DATABASE_URL points to the compose sibling service `db` (DEC-006). Without
# it the API degrades to the in-memory repository with seed data, so the
# stack still boots if Postgres is slow or absent.
ENV DATABASE_URL=postgresql://projecthub:cambiar@db:5432/projecthub \
    AUTH_SECRET=projecthub-demo-secret-cambiar-32bytes \
    PORT=8100

EXPOSE 8100
USER nonroot:nonroot
ENTRYPOINT ["/server"]
