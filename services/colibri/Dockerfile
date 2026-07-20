# Build stage — compile the Colibrí C engine
FROM debian:stable-slim AS build

ARG COLIBRI_VERSION=v1.0.0

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      git build-essential ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /src
RUN git clone --depth 1 --branch "${COLIBRI_VERSION}" \
      https://github.com/JustVugg/colibri.git .

WORKDIR /src/c
RUN make -j"$(nproc)" glm ARCH=native

# Runtime stage — minimal image with just the engine and API gateway
FROM debian:stable-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      python3 libgomp1 && \
    rm -rf /var/lib/apt/lists/*

COPY --from=build /src/c/glm        /usr/local/libexec/colibri/glm
COPY --from=build /src/c/coli        /usr/local/bin/coli
COPY --from=build /src/c/openai_server.py /usr/local/libexec/colibri/openai_server.py
COPY --from=build /src/c/doctor.py   /usr/local/libexec/colibri/doctor.py
COPY --from=build /src/c/resource_plan.py /usr/local/libexec/colibri/resource_plan.py
COPY --from=build /src/c/tools       /usr/local/libexec/colibri/tools

RUN chmod +x /usr/local/bin/coli /usr/local/libexec/colibri/glm

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')" || exit 1

ENTRYPOINT ["coli", "serve", "--host", "0.0.0.0", "--port", "8000"]
