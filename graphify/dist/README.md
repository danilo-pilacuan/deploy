# graphify: servicios de grafo de conocimiento

Recetas de despliegue para el grafo de conocimiento que consume la skill `graphify-ops` del kit
(my-custom-kit): indexa un repositorio en un grafo (capa de codigo AST determinista + capa
semantica opcional con LLM OpenAI-compatible) y lo sirve via MCP Streamable HTTP.

Estas recetas viven FUERA del kit por diseno: el kit se conecta a servicios ya levantados y
estables, no los provisiona. Fuente versionada: `deploy/graphify/` del repo hospedador; el
orquestador corre compose desde su copia local `deploy/graphify/dist/` (emitida al vuelo, la
fuente nunca se toca).

## Servicios

| Servicio | Imagen / build | Puerto | Uso |
|---|---|---|---|
| `graphify` | build local `graphify-local:0.9.102` (Dockerfile propio) | 8080 | Servidor MCP del grafo (`/mcp`, header `X-API-Key`) |
| `graphify-build` | misma imagen, perfil `build` | - | Build completo del grafo con LLM (`graphify extract`) |
| `graphify-update` | misma imagen, perfil `update` | - | Update incremental sin LLM para codigo (`graphify update`) |
| `memgraph` | `memgraph/memgraph:3.14.0` | 7687 | Persistencia del grafo (Bolt) para mcp-memgraph |
| `mcp-memgraph` | `memgraph/mcp-memgraph:0.4.1` | 8000 | MCP de Memgraph read-only (`/mcp/`, Cypher) |

## Eleccion de implementacion (analizada)

- **Build propio (esta receta, via recomendada):** imagen `graphify-local:0.9.102` construida con
  el Dockerfile de esta carpeta: base `python:3.12-slim` pinneada, paquete PyPI `graphifyy`
  (doble y) pinneado a 0.9.102, usuario no-root (uid 10001), transporte streamable-http.
- **Imagen Docker Hub `sinfallas/remote-graphify` (alternativa):** sin build propio, pero base
  `sinfallas/base-python-uv:latest` y tags no pinneados (mutable) y el proceso corre como root;
  aceptable para pruebas rapidas, no recomendada para un servicio estable. El compose fuerza
  `entrypoint: ["graphify-mcp"]` y `command` explicitos (la CMD de la imagen invoca el CLI, no el
  servidor MCP), por lo que ambas variantes corren el mismo proceso.
- **On-premise sin Docker (referencia):** `pip install "graphifyy[mcp]==0.9.102"` y
  `python -m graphify.serve <repo>/graphify-out/graph.json --transport http --port 8080`.

### Conmutacion build <-> Docker Hub (sin editar el yml)
La imagen se elige con variables, nunca editando `docker-compose.yml`:

```bash
# build local (default): GRAPHIFY_IMAGE no definida -> graphify-local:0.9.102
node tools/build-graphify.mjs up

# Docker Hub: pull + up --no-build, sin construir nada localmente
node tools/build-graphify.mjs --dockerhub up
```

El orquestador pasa `GRAPHIFY_IMAGE=sinfallas/remote-graphify:latest` al proceso compose; con
compose directo equivale a `GRAPHIFY_IMAGE=sinfallas/remote-graphify:latest docker compose
pull --ignore-buildable graphify && ... up -d --no-build`. El `.env` tambien puede fijar
`GRAPHIFY_IMAGE` o `GRAPHIFY_IMAGE_SOURCE=dockerhub` como valor por defecto persistente; la
variable de proceso siempre gana sobre el `.env` (precedencia estandar de compose).

## Requisitos

- Docker con compose v2.
- `.env` en la raiz del repo (plantilla: `.env.example` en el kit o en la raiz):
  - `OPENAI_BASE_URL`, `OPENAI_MODEL`, `OPENAI_API_KEY`: endpoint OpenAI-compatible para la capa
    semantica de `extract` (sin credenciales, el build cae a code-only).
  - `GRAPHIFY_API_KEY`: API key que el MCP exige en el header `X-API-Key` (vacia = sin auth).
  - `GRAPHIFY_PORT`, `MEMGRAPH_BOLT_PORT`, `MEMGRAPH_HTTP_PORT`: opcionales (8080/7687/8000).
    Los instaladores del kit pueden escribirlos con `--graphify-port/--bolt-port/--memgraph-port`
    (bash) o `-GraphifyPort/-BoltPort/-MemgraphPort` (PowerShell).
  - `GRAPHIFY_IMAGE`: fija la imagen usada (gana sobre `GRAPHIFY_IMAGE_SOURCE`).
  - `GRAPHIFY_IMAGE_SOURCE`: `build` (default) o `dockerhub`.
  - `GRAPHIFY_MAX_OUTPUT_TOKENS`: cap de salida del LLM semantico (pasa al contenedor de
    `graphify-build`). Si el modelo corta respuestas a mitad de JSON, el extract vuelve con
    muchos archivos "hollow" (omitidos) y el shrink guard protege el grafo previo; subir el
    cap (p. ej. 32768) reduce esos huecos (bug upstream #1365: caps muertos/cortos).
    Desenlace en este repo: con 32768 los docs gordos (>20k chars) seguian truncandose
    (GLM agota el presupuesto en razonamiento interno); `65536` consiguio una pasada
    unica sin huecos (968 nodos vs 266 de la primera pasada).
  - `GRAPHIFY_MAX_RETRY_DEPTH`: profundidad maxima de la biseccion adaptativa (default 3).
    A profundidad 3, un chunk de 2 archivos truncado ya no puede partirse en chunks de 1;
    subirlo a 4 permite ese ultimo paso y reintenta respuestas hollow (#2880).
  - No hay knob para chunks que completan pero omiten archivos en silencio (quedan
    cacheados como completos y no se reintentan). Si tras subir el cap reaparecen
    huecos, purga del cache semantico las entradas de esos archivos o corre una pasada
    completa con `GRAPHIFY_NO_INCREMENTAL_CACHE=1`.
  - `GRAPHIFY_WORKSPACE`: ruta del workspace a indexar (default: la raiz del repo donde corre el
    orquestador; si usas compose directo desde esta carpeta definela explicitamente).

## Uso

```bash
node tools/build-graphify.mjs up              # build de imagen + compose up + smoke test
node tools/build-graphify.mjs --dockerhub up  # imagen de Docker Hub (pull, sin build)
node tools/build-graphify.mjs --env-file ruta/.env up   # .env alternativo
node tools/build-graphify.mjs extract         # build completo del grafo con LLM (requiere OPENAI_* en .env)
node tools/build-graphify.mjs update          # update incremental (codigo, sin LLM; hot-reload del serve)
node tools/build-graphify.mjs status          # estado de contenedores + smoke
node tools/build-graphify.mjs down            # detener servicios
```

Notas de operacion:
- Cada instalacion usa su propio proyecto compose (`graphify-<hash8>` derivado de la raiz de
  instalacion): dos instalaciones pueden coexistir con puertos distintos sin colision.
- Si instalaste con `--dockerhub`, la imagen queda fijada en `.env` (`GRAPHIFY_IMAGE=...`) y los
  comandos posteriores (`update`, `extract`, `status`, `down`) no necesitan el flag.

Sin el orquestador, con docker compose directo desde esta carpeta:

```bash
docker compose up -d                      # levanta graphify + memgraph + mcp-memgraph
docker compose --profile build run --rm graphify-build    # extract (LLM)
docker compose --profile update run --rm graphify-update  # update incremental
```

## Integracion con el kit

1. Copia `my-custom-kit/examples/vscode-mcp-graphify.json` a `.vscode/mcp.json` del repo y define
   `GRAPHIFY_API_KEY` en el entorno del agente (mismo valor que en `.env`).
2. Instala la skill opcional `graphify-ops` del kit (ver README del kit): manda consultar el grafo
   antes de refactors/auditorias y degradar a lectura directa del codigo si el servicio no corre.
3. Manten el grafo al dia con `update` tras cambios de codigo (el servidor recarga `graph.json`
   por mtime+size, sin reinicio) y `extract` cuando quieras regenerar la capa semantica.

## Notas

- El volumen del serve monta la raiz del repo read-only: el servidor solo lee
  `<repo>/graphify-out/graph.json`; la extraccion escribe unicamente en `graphify-out/`.
- Multi-proyecto: monta un directorio padre y pasa `project_path` en las tools MCP para resolver
  `<project_path>/graphify-out/graph.json`.
- El grafo (`graphify-out/`) es un artefacto derivado: no lo versiones.
