ARG BUILD_FROM
FROM $BUILD_FROM
ENV LANG=C.UTF-8 DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      python3 python3-venv git curl ca-certificates jq bash procps unzip \
    && rm -rf /var/lib/apt/lists/*
# Claude Code yerel ikili (linux arm64/x64), HOME=/root altina kurulur
RUN curl -fsSL https://claude.ai/install.sh | bash \
    && ln -sf /root/.local/bin/claude /usr/local/bin/claude \
    && claude --version
COPY run.sh /run.sh
RUN chmod +x /run.sh
CMD ["/run.sh"]
