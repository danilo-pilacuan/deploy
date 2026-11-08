# Builds the FastAPI backend of ProjectHub from its sibling repo.
# Context must be the workspace root: docker build -f deploy/projecthub/api.Dockerfile .
FROM python:3.14-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

COPY backend/requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

COPY backend/app ./app
COPY backend/pytest.ini backend/README.md ./

# DATABASE_URL points to the compose sibling service `db` (DEC-006). Without
# it the API degrades to the in-memory repository with seed data, so the
# stack still boots if Postgres is slow or absent.
ENV DATABASE_URL=******db:5432/projecthub \
    POSTGRES_USER=projecthub \
    POSTGRES_PASSWORD=cambiar \
    POSTGRES_DB=projecthub \
    AUTH_SECRET=projecthub-demo-secret-cambiar-32bytes

EXPOSE 8100
CMD ["python", "-m", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8100"]
