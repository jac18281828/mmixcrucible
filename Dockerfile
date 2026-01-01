# Phase 1: Build checksmix
FROM ghcr.io/jac18281828/rust:latest AS checksmix-builder

COPY --chown=rust:rust . .
ENV USER=rust
USER rust

RUN cargo install checksmix

# Phase 2: Dev container
FROM debian:stable-slim

RUN export DEBIAN_FRONTEND=noninteractive && \
    apt-get update && \
    apt-get install -y -q --no-install-recommends \
      ca-certificates curl git gnupg2 ripgrep python3 && \
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


# Copy checksmix binary from phase 1
COPY --from=checksmix-builder /usr/local/cargo/bin/checksmix /usr/local/bin/
COPY --from=checksmix-builder /usr/local/cargo/bin/mmixasm /usr/local/bin/

ENV PATH=/home/${USER}/.cargo/bin:$PATH:/usr/local/bin
# source $HOME/.cargo/env
