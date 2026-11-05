# deploy/projecthub

Stack Docker de demo de ProjectHub (DEC-002): shell + 4 remotes detras de nginx.
Puertos 4400-4404 (DEC-001): shell 4400, mfe-projects 4401, mfe-reports 4402,
mfe-admin 4403, mfe-governance 4404. El rango 4200-4204 del rulebook queda como
contrato logico y 4300-4304 es el desarrollo local con npm.

## Estructura

- `shell.Dockerfile`: build del host (shell) + nginx con fallback SPA.
- `remote.Dockerfile`: build de un remote seleccionado con `--build-arg ARG_REPO=<repo>`
  + nginx que sirve `remoteEntry.json` y chunks.
- `nginx/shell.conf` y `nginx/remote.conf`: configuracion de nginx por rol.
- `docker-compose.yml`: los 5 servicios, contexto de build en la raiz del workspace.

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

## Notas

- El `federation.manifest.json` del shell apunta a `http://localhost:430x/...`
  (desarrollo). Para la demo en Docker, `shell.Dockerfile` sobrescribe ese
  archivo en la imagen con `manifest/federation.manifest.json` (URLs 440x).
  Las URLs viven solo en manifests/env, nunca en literales de codigo.
- `deploy/graphify/` es infraestructura ajena a la app: no tocar.
