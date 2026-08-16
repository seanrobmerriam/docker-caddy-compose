FROM rust:latest

ARG WASMTIME_VERSION=47.0.3
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL https://wasmtime.dev/install.sh -o /tmp/wasmtime-install.sh \
    && bash /tmp/wasmtime-install.sh --version "v${WASMTIME_VERSION}" \
    && /root/.wasmtime/bin/wasmtime --version \
    && rm /tmp/wasmtime-install.sh

ENV PATH=/root/.wasmtime/bin:/usr/local/cargo/bin:$PATH
WORKDIR /workspace
CMD ["bash"]
