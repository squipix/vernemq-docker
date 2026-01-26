# ==============================================================================
# CUSTOM BUILD OF VERNEMQ - Changes vs. upstream docker-vernemq/Dockerfile.alpine
# ==============================================================================
# This Dockerfile builds VerneMQ from source instead of using pre-built binaries.
# Pre-built binaries require accepting the VerneMQ EULA and a paid subscription
# for commercial use. Building from source allows use under Apache-2.0 license.
#
# Key differences from upstream (https://github.com/vernemq/docker-vernemq):
# 1. Multi-stage build: Added build container to compile VerneMQ from source
# 2. Downloads config files (vm.args, vernemq.sh, join_cluster.sh) from upstream
# 3. Added openssl and tzdata packages (not in upstream alpine Dockerfile)
# 4. Uses direct path to vernemq.sh instead of symlink to start_vernemq
# ==============================================================================

FROM alpine:3.22 as build

ENV VERNEMQ_VERSION="2.1.1"
ENV VERNEMQ_DOCKER_VERSION="2.0.1"

RUN apk add \
    git \
    alpine-sdk \
    erlang-dev \
    snappy-dev \
    bsd-compat-headers \
    openssl-dev \
    tzdata \
    patch

RUN git clone --depth 1 --branch ${VERNEMQ_VERSION} \
      https://github.com/vernemq/vernemq.git \
      /usr/src/vernemq

RUN cd /usr/src/vernemq && \
    make rel && \
    mv _build/default/rel/vernemq /vernemq

# Download config files from docker-vernemq repository (vm.args, vernemq.sh, join_cluster.sh)
RUN wget -O /vernemq/etc/vm.args https://github.com/vernemq/docker-vernemq/raw/${VERNEMQ_DOCKER_VERSION}/files/vm.args && \
    wget -O /vernemq/bin/vernemq.sh https://github.com/vernemq/docker-vernemq/raw/${VERNEMQ_DOCKER_VERSION}/bin/vernemq.sh && \
    wget -O /vernemq/bin/join_cluster.sh https://github.com/vernemq/docker-vernemq/raw/${VERNEMQ_DOCKER_VERSION}/bin/join_cluster.sh

# Apply patch to fix config error detection
# (upstream vernemq.sh has a bug: config errors are not detected because
#  'vernemq config generate' always returns exit code 0)
COPY vernemq.sh.patch /tmp/
RUN patch -p0 /vernemq/bin/vernemq.sh < /tmp/vernemq.sh.patch && rm /tmp/vernemq.sh.patch

RUN chown -R 10000:10000 /vernemq
RUN chmod 0755 /vernemq/bin/vernemq.sh /vernemq/bin/join_cluster.sh

# ==============================================================================
# Runtime image
# ==============================================================================
FROM alpine:3.22

# Added openssl and tzdata (not in upstream alpine Dockerfile)
RUN apk --no-cache --update --available upgrade && \
    apk add --no-cache ncurses-libs openssl libstdc++ jq curl bash snappy-dev nano tzdata && \
    addgroup --gid 10000 vernemq && \
    adduser --uid 10000 -H -D -G vernemq -h /vernemq vernemq && \
    install -d -o vernemq -g vernemq /vernemq

# Defaults
ENV DOCKER_VERNEMQ_KUBERNETES_LABEL_SELECTOR="app=vernemq" \
    DOCKER_VERNEMQ_LOG__CONSOLE=console \
    PATH="/vernemq/bin:$PATH" \
    VERNEMQ_VERSION="2.1.1"
WORKDIR /vernemq

# Copy compiled VerneMQ from build stage (instead of downloading pre-built binary)
COPY --chown=10000:10000 --from=build /vernemq /vernemq

# Create symlinks for config/data/log directories
RUN ln -s /vernemq/etc /etc/vernemq && \
    ln -s /vernemq/data /var/lib/vernemq && \
    ln -s /vernemq/log /var/log/vernemq

# Ports
# 1883  MQTT
# 8883  MQTT/SSL
# 8080  MQTT WebSockets
# 44053 VerneMQ Message Distribution
# 4369  EPMD - Erlang Port Mapper Daemon
# 8888  Health, API, Prometheus Metrics
# 9100 9101 9102 9103 9104 9105 9106 9107 9108 9109  Specific Distributed Erlang Port Range

EXPOSE 1883 8883 8080 44053 4369 8888 \
       9100 9101 9102 9103 9104 9105 9106 9107 9108 9109


VOLUME ["/vernemq/log", "/vernemq/data", "/vernemq/etc"]

HEALTHCHECK CMD vernemq ping | grep -q pong

USER vernemq

# Use direct path to vernemq.sh (upstream uses symlink to /usr/sbin/start_vernemq)
CMD ["/vernemq/bin/vernemq.sh"]
