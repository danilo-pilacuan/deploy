# Runbook de despliegue - stack demo ProjectHub (compose)

Publico objetivo: quien despliegue o explote el stack demo de ProjectHub en
una maquina con Docker. El stack completo vive en `docker-compose.yml`
(shell, 4 remotes, api, db) y usa los puertos reservados por DEC-001/006:
frontends host 4400-4404 -> contenedor 8080, api 8100, db host 5434.

## 1. Variables de entorno

Todas tienen default pensado SOLO para la demo local. En un despliegue
real se pasan por archivo `.env` junto al compose (docker compose lo lee
automaticamente) o por `-e` en cada servicio.

| Variable | Default demo | Uso real |
| --- | --- | --- |
| `POSTGRES_USER` | `projecthub` | usuario de la BD demo |
| `POSTGRES_PASSWORD` | `cambiar` | CAMBIAR: credencial de Postgres |
| `POSTGRES_DB` | `projecthub` | nombre de la BD |
| `DATABASE_URL` | `postgresql://projecthub:cambiar@db:5432/projecthub` | URL que consume la api; debe apuntar al servicio `db:5432` |
| `AUTH_SECRET` | `projecthub-demo-secret-cambiar-32bytes` | CAMBIAR: firma de los JWT (>= 32 bytes aleatorios, p.ej. `openssl rand -hex 32`) |
| `ALLOWED_ORIGINS` | ver nota CORS | CAMBIAR: origenes http(s) del host frontend, separados por coma |
| `RATE_LIMIT_LOGIN_INTENTOS` | `5` | fallos de login por ventana antes de 429 (`<= 0` desactiva) |
| `RATE_LIMIT_LOGIN_VENTANA_SEG` | `60` | ventana fija del limitador en segundos |

Notas:

- CORS (mitigacion VULN-004): sin `ALLOWED_ORIGINS`, el backend acepta los
  origenes de desarrollo y demo local (`localhost:4300-4304` y
  `localhost:4400-4404`). En produccion fijar explicitamente los origenes
  del host real, con o sin barra final (el backend los normaliza); vacio o
  solo comas cae al default y se ignora.
- `AUTH_SECRET`: stateless. Rotarla invalida todos los tokens emitidos;
  los usuarios deben volver a iniciar sesion. No compartirla entre
  entornos (un token valido en demo seria valido en prod).
- El frontend usa `API_BASE_URL` con default `http://localhost:8100`; si
  la api se publica en otro host/puerto, reconstruir las imagenes de
  frontends con ese valor (build arg del Dockerfile), no basta con tocar
  el compose en caliente.

## 2. Rate limit y multiples instancias

El limitador de login es EN MEMORIA (mitigacion VULN-003): ventana fija
por (correo normalizado + IP), solo cuenta fallos, reinicio del proceso
limpia contadores. Con una sola instancia de la api es correcto. Si se
despliegan varias instancias detras de un balanceador, cada una lleva su
propio contador y el limite efectivo se multiplica por instancias:
migrar a un limitador externo (Redis) o imponer el limite en el borde
(WAF / ingress). Quedo registrado como decision abierta del backend
(`app/rate_limit.py`).

## 3. Despliegue (comandos)

Desde la raiz del workspace (el contexto de build de todos los servicios
es la raiz; los Dockerfile viven en `deploy/projecthub/`):

```bash
docker compose -f deploy/projecthub/docker-compose.yml build
docker compose -f deploy/projecthub/docker-compose.yml up -d
```

Primera vez o cambio de esquema: la db aplica migraciones al arranque de
la api (servicio `api` espera el healthcheck de `db`). Carga de semillas:
la api sincroniza desde `@projecthub/shared` al primer arranque.

Rebuild de un solo servicio tras cambiar un repo (ejemplo shell):

```bash
docker compose -f deploy/projecthub/docker-compose.yml build shell
docker compose -f deploy/projecthub/docker-compose.yml up -d shell
```

La api consume `../..` como contexto: cualquier cambio de backend exige
`build api`. Cambios de shared-lib/ui-lib exigen rebuild de TODOS los
servicios Angular (shell y remotes).

## 4. Hardening ya aplicado (iteracion 50)

- nginx corre como usuario no root (uid 101): `listen 8080`, pid y temp
  en `/tmp`, logs a stdout/stderr. Por eso los puertos host son 440x y el
  contenedor 8080.
- api corre como `appuser` (uid 10001).
- Todos los servicios: `read_only: true`, `tmpfs` para lo escribible,
  `no-new-privileges:true`.
- Cabeceras de seguridad (`headers.conf`): X-Content-Type-Options,
  X-Frame-Options, Referrer-Policy, Permissions-Policy; `server_tokens
  off`.
- Cache: `remoteEntry.json` e `index.html` con `Cache-Control: no-cache`
  (un redeploy no deja chunks viejos); assets hasheados `max-age=3600`.

Al cambiar nginx.conf o headers.conf recordar que headers.conf se incluye
en dos niveles (server y location de federation): duplicar la inclusion
da error de arranque de nginx.

## 5. Verificacion post-despliegue

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8100/api/salud   # 200
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:4400/remoteEntry.json   # 200
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:4401/remoteEntry.json   # 200
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:4402/remoteEntry.json   # 200
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:4403/remoteEntry.json   # 200
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:4404/remoteEntry.json   # 200
```

Login de humo (credenciales demo, cambiar en real):

```bash
curl -s -X POST http://localhost:8100/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"correo":"diana@projecthub.local","password":"projecthub-demo"}'
```

En navegador: entrar por `http://localhost:4400`, iniciar sesion,
navegar a las 4 rutas federadas, F5 en una ruta profunda de un remote y
consola sin errores de singleton duplicado. El e2e de sincronizacion
(`tools/e2e/e2e-repush-api.mjs` en la raiz del workspace) cubre push/pull
contra la api 8100.

## 6. Operacion

- Logs: `docker compose -f deploy/projecthub/docker-compose.yml logs -f api`
  (y/o shell, db...). La api no escribe archivos (read_only).
- Backup de la BD demo (volumen `projecthub_pgdata_demo`):
  `docker exec projecthub-db-demo pg_dump -U projecthub projecthub > backup.sql`.
- Restaurar: `cat backup.sql | docker exec -i projecthub-db-demo psql -U projecthub -d projecthub`.
- Reinicio limpio que conserva datos: `down` + `up -d` (el volumen
  persiste); `down -v` BORRA los datos de la demo.
- Contenedores con `restart: unless-stopped`: sobreviven al reinicio del
  host docker.

## 7. Limitaciones conocidas del stack demo

- La BD demo arranca con datos semilla de `@projecthub/shared`; no es una
  migracion de produccion.
- Sin TLS: el stack asume que el TLS termina antes (proxy/reverso del
  host). El CORS del backend ya filtra por origen, pero las credenciales
  viajan en el cuerpo del login por HTTP si no hay TLS.
- La api no persiste el rate limit ni sesiones: stateless por diseno de
  la demo (ver seccion 2).
- Grafana/Memgraph del compose raiz (`deploy/graphify/`) son
  infraestructura ajena a la app: no los toca este runbook.
