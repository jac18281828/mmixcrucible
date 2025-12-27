# Phase 1: Build mmixware
FROM debian:stable-slim AS mmixware-builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    ca-certificates \
    build-essential \
    texlive-binaries texlive-base \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 https://gitlab.lrz.de/mmix/mmixware.git /mmixware
WORKDIR /mmixware

RUN make mmix mmixal mmotype mmmix

# Phase 2: Build checksmix
FROM ghcr.io/jac18281828/rust:latest AS checksmix-builder

COPY --chown=rust:rust . .
ENV USER=rust
USER rust

RUN cargo install checksmix

# Phase 3: Dev container
FROM debian:stable-slim

RUN export DEBIAN_FRONTEND=noninteractive && \
    apt-get update && \
    apt-get install -y -q --no-install-recommends \
      ca-certificates curl git gnupg2 ripgrep python3 & \
    apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

ENV USER=rust
RUN useradd --create-home --shell /bin/bash ${USER} && \
    usermod -a -G sudo ${USER} && \
    echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

ARG PROJECT=mmixcrucible
WORKDIR /workspaces/${PROJECT}
COPY --chown=rust:rust . .
ENV USER=rust
USER rust


# Copy mmixware binaries from phase 1
COPY --from=mmixware-builder /mmixware/mmix /usr/local/bin/
COPY --from=mmixware-builder /mmixware/mmixal /usr/local/bin/
COPY --from=mmixware-builder /mmixware/mmotype /usr/local/bin/
COPY --from=mmixware-builder /mmixware/mmmix /usr/local/bin/
# Copy checksmix binary from phase 2
COPY --from=checksmix-builder /usr/local/cargo/bin/checksmix /usr/local/bin/
COPY --from=checksmix-builder /usr/local/cargo/bin/mmixasm /usr/local/bin/

ENV PATH=/home/${USER}/.cargo/bin:$PATH:/usr/local/bin
# source $HOME/.cargo/env
