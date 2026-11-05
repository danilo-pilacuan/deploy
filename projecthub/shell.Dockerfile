# Builds the shell (host) of ProjectHub from its sibling repo.
# Context must be the workspace root: docker build -f deploy/projecthub/shell.Dockerfile .
FROM node:24-alpine AS build
WORKDIR /build

COPY shell/package.json shell/package-lock.json ./shell/
COPY shared-lib/package.json shared-lib/package-lock.json ./shared-lib/
COPY ui-lib/package.json ui-lib/package-lock.json ./ui-lib/

RUN npm ci --prefix ./shell
RUN npm ci --prefix ./shared-lib
RUN npm ci --prefix ./ui-lib

COPY shell/ ./shell/
COPY shared-lib/ ./shared-lib/
COPY ui-lib/ ./ui-lib/

# The shell consumes the libs as npm packages (file:../<lib>/dist/...),
# so both libs must be built before the shell.
RUN npm run build --prefix ./shared-lib
RUN npm run build --prefix ./ui-lib
RUN npm run build --prefix ./shell

FROM nginx:1.27-alpine
COPY --from=build /build/shell/dist/shell/browser /usr/share/nginx/html
# Docker demo manifest (URLs 440x, DEC-001) replaces the dev one (430x).
COPY deploy/projecthub/manifest/federation.manifest.json /usr/share/nginx/html/federation.manifest.json
COPY deploy/projecthub/nginx/shell.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
