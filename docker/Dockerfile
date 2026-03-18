FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# hadolint ignore=DL3008
RUN apt-get update && apt-get install -y --no-install-recommends \
  ca-certificates \
  curl \
  gnupg \
  git \
  vim \
  less \
  grep \
  sed \
  gawk \
  tree \
  jq \
  wget \
  make \
  g++ \
  python3 \
  python3-pip \
  openssl \
  sudo \
  unzip \
  && rm -rf /var/lib/apt/lists/*

# Install GitHub CLI (gh)
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
  && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    > /etc/apt/sources.list.d/github-cli.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends gh \
  && rm -rf /var/lib/apt/lists/*

# Install act (local GitHub Actions runner)
RUN curl -fsSL https://raw.githubusercontent.com/nektos/act/master/install.sh | bash -s -- -b /usr/local/bin 2>/dev/null || true

# Install Node.js 20 via NodeSource
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
  && apt-get install -y --no-install-recommends nodejs \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# ── Node.js app ───────────────────────────────────────────────────────────────
COPY docker/package.json ./
RUN npm install --omit=dev

COPY docker/server.js  ./
COPY docker/public/    ./public/

# ── Lab content ───────────────────────────────────────────────────────────────
COPY Labs/ ./labs/

# ── Pre-built mkdocs documentation (served at /docs/) ────────────────────────
COPY mkdocs-site/ ./docs/

# ── Entrypoint ────────────────────────────────────────────────────────────────
COPY docker/entrypoint.sh ./entrypoint.sh
RUN chmod +x ./entrypoint.sh

LABEL org.opencontainers.image.description="Interactive GitHub Actions Labs – learn CI/CD workflows in a browser-based terminal"

EXPOSE 3000
ENV SHELL=/bin/bash

RUN echo "alias ll='ls -lah'" >> /etc/profile.d/aliases.sh && \
    echo "alias la='ls -laF'"  >> /etc/profile.d/aliases.sh && \
    echo "alias l='ls -lAh'"   >> /etc/profile.d/aliases.sh

ENTRYPOINT ["/app/entrypoint.sh"]
