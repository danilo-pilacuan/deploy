# Builds one ProjectHub remote (mfe-projects | mfe-reports | mfe-admin | mfe-governance).
# ARG_REPO selects the sibling repo. Context must be the workspace root:
# docker build -f deploy/projecthub/remote.Dockerfile --build-arg ARG_REPO=mfe-projects .
FROM node:24-alpine AS build
ARG ARG_REPO
WORKDIR /build

COPY ${ARG_REPO}/package.json ${ARG_REPO}/package-lock.json ./${ARG_REPO}/
COPY shared-lib/package.json shared-lib/package-lock.json ./shared-lib/
COPY ui-lib/package.json ui-lib/package-lock.json ./ui-lib/

RUN npm ci --prefix ./${ARG_REPO}
RUN npm ci --prefix ./shared-lib
RUN npm ci --prefix ./ui-lib

COPY ${ARG_REPO}/ ./${ARG_REPO}/
COPY shared-lib/ ./shared-lib/
COPY ui-lib/ ./ui-lib/

RUN npm run build --prefix ./shared-lib
RUN npm run build --prefix ./ui-lib
RUN npm run build --prefix ./${ARG_REPO}

FROM nginx:1.27-alpine
# ARGs are stage-scoped: redeclare to interpolate the COPY path below.
ARG ARG_REPO
COPY --from=build /build/${ARG_REPO}/dist/${ARG_REPO}/browser /usr/share/nginx/html
COPY deploy/projecthub/nginx/remote.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
