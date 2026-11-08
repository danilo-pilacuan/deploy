# deploy/projecthub

Stack Docker de demo de ProjectHub (DEC-002): shell + 4 remotes detras de nginx.
Puertos 4400-4404 (DEC-001): shell 4400, mfe-projects 4401, mfe-reports 4402,
mfe-admin 4403, mfe-governance 4404. El rango 4200-4204 del rulebook queda como
contrato logico y 4300-4304 es el desarrollo local con npm.

## Estructura

- `shell.Dockerfile`: build del host (shell) + nginx con fallback SPA.
- `remote.Dockerfile`: build de un remote seleccionado con `--build-arg ARG_REPO=<repo>`
  + nginx que sirve `remoteEntry.json` y chunks.
- `api.Dockerfile`: build del backend FastAPI (uvicorn en 8100).
- `nginx/shell.conf` y `nginx/remote.conf`: configuracion de nginx por rol.
- `docker-compose.yml`: los 5 frontends + `api` (8100) + `db` (postgres:17),
  contexto de build en la raiz del workspace.

## Uso

Desde la raiz del workspace (los Dockerfiles copian los repos hermanos `shell`,
`mfe-*`, `shared-lib`, `ui-lib`; las libs se compilan dentro de la imagen porque
los apps las consumen como paquetes `file:`):

```bash
docker compose -f deploy/projecthub/docker-compose.yml up --build
```

Verificacion:

- `http://localhost:4400` renderiza el shell con navegacion a los 4 remotes.
- `http://localhost:4401/remoteEntry.json` (y 4402-4404) responde 200.
- F5 en una ruta profunda (`http://localhost:4400/governance`) funciona por el
  fallback SPA del shell.
- `http://localhost:8100/api/salud` responde `{"estado":"ok"}`; login demo con
  `diana@projecthub.local` / `projecthub-demo` contra `/api/auth/login`.

## Notas

- El `federation.manifest.json` del shell apunta a `http://localhost:430x/...`
  (desarrollo). Para la demo en Docker, `shell.Dockerfile` sobrescribe ese
  archivo en la imagen con `manifest/federation.manifest.json` (URLs 440x).
  Las URLs viven solo en manifests/env, nunca en literales de codigo.
- Los frontends llaman a la API en `http://localhost:8100` (default de
  `API_BASE_URL` en shared-lib); el mapeo `8100:8100` del servicio `api` basta,
  sin proxy en nginx.
- La db demo publica en el host 5434 (el 5433 pertenece a la db de desarrollo
  del compose del backend); la API la alcanza internamente como `db:5432`.
  El volumen `projecthub_pgdata_demo` persiste los datos de la demo entre
  reinicios del stack.
- `DATABASE_URL` y `AUTH_SECRET` (api) aceptan override por entorno antes de
  los defaults del compose; el default de AUTH_SECRET cumple los 32 bytes
  minimos de HMAC-SHA256 (RFC 7518).
- `deploy/graphify/` es infraestructura ajena a la app: no tocar.
- E2E del banner de API: `node tools/e2e/e2e-banner-api.mjs` desde la raiz del
  workspace (requiere la demo arriba en 4400 y docker para detener/arrancar el
  contenedor de la API; 8 comprobaciones).
- Tras un `docker compose build` de los frontends hay que forzar recarga sin
  cache en el navegador (Ctrl+F5 o vaciar cache HTTP): es-module-shims queda con
  el importmap y los chunks en memoria y puede resolver chunks viejos,
  produciendo errores tipo `... is not a function` por singleton desactualizado
  (`@projecthub/shared` aunque el `remoteEntry.json` servido ya apunte al nuevo).
- El shell expone el banner de estado de API (item 11.6 de
  `docs/funcionalidades.md`): con la API caida aparece un aviso de modo demo en
  ~5 s y desaparece solo cuando `/api/salud` vuelve a responder 200.
