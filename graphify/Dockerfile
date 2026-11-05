# Dockerfile de graphify (servidor MCP)
# Base pinneada python:3.12-slim (graphify requiere >= 3.10); usuario no-root;
# paquete PyPI "graphifyy" (doble y) pinneado a la version auditada.
FROM python:3.12-slim

# graphifyy[mcp]: transporte Streamable HTTP (serve). watch: modo watch opcional.
# openai: extraccion semantica dentro del contenedor (extract con OPENAI_*).
RUN pip install --no-cache-dir "graphifyy[mcp,watch,openai]==0.9.102"

# Usuario sin privilegios (uid 10001) para el proceso del servidor.
RUN useradd --uid 10001 --create-home --shell /usr/sbin/nologin graphify

# El grafo se monta como volumen: <repo>/graphify-out/graph.json
RUN mkdir -p /workspace/graphify-out && chown -R graphify:graphify /workspace
WORKDIR /workspace
USER graphify

EXPOSE 8080

# Serve MCP (streamable-http): python -m graphify.serve <graph.json> --transport http ...
# GRAPHIFY_API_KEY (env) fija la API key exigida en el header X-API-Key.
ENTRYPOINT ["python", "-m", "graphify.serve"]
CMD ["/workspace/graphify-out/graph.json", "--transport", "http", "--host", "0.0.0.0", "--port", "8080"]
