# Multi-stage build for Bitcoin Core on ARM64 (Raspberry Pi 5)
# This Dockerfile builds Bitcoin Core from source for optimal performance

# Build stage
FROM ubuntu:22.04 as builder

# Avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    libtool \
    autotools-dev \
    automake \
    pkg-config \
    bsdmainutils \
    python3 \
    python3-pip \
    libssl-dev \
    libevent-dev \
    libboost-system-dev \
    libboost-filesystem-dev \
    libboost-test-dev \
    libboost-thread-dev \
    libminiupnpc-dev \
    libzmq3-dev \
    libqrencode-dev \
    libdb++-dev \
    curl \
    wget \
    git \
    ccache \
    && rm -rf /var/lib/apt/lists/*

# Set Bitcoin Core version
ARG BITCOIN_VERSION=26.0
ENV BITCOIN_VERSION=${BITCOIN_VERSION}

# Create bitcoin user and directories
RUN groupadd -r bitcoin && useradd -r -g bitcoin bitcoin
RUN mkdir -p /opt/bitcoin /tmp/bitcoin

# Download Bitcoin Core source
WORKDIR /tmp/bitcoin
RUN wget https://bitcoincore.org/bin/bitcoin-core-${BITCOIN_VERSION}/bitcoin-${BITCOIN_VERSION}.tar.gz
RUN wget https://bitcoincore.org/bin/bitcoin-core-${BITCOIN_VERSION}/SHA256SUMS
RUN wget https://bitcoincore.org/bin/bitcoin-core-${BITCOIN_VERSION}/SHA256SUMS.asc

# Verify checksums (basic verification)
RUN grep "bitcoin-${BITCOIN_VERSION}.tar.gz" SHA256SUMS | sha256sum -c -

# Extract source code
RUN tar -xzf bitcoin-${BITCOIN_VERSION}.tar.gz
WORKDIR /tmp/bitcoin/bitcoin-${BITCOIN_VERSION}

# Configure build for ARM64 with optimizations for Raspberry Pi 5
RUN ./autogen.sh
RUN ./configure \
    --prefix=/opt/bitcoin \
    --disable-wallet \
    --disable-gui-tests \
    --disable-tests \
    --disable-bench \
    --with-gui=no \
    --enable-hardening \
    --with-pic \
    --enable-cxx \
    --disable-shared \
    --with-bignum=no \
    --enable-module-recovery \
    --disable-dependency-tracking \
    --enable-glibc-back-compat \
    --enable-reduce-exports \
    CXXFLAGS="-O2 -march=armv8-a+crc -mtune=cortex-a76" \
    CFLAGS="-O2 -march=armv8-a+crc -mtune=cortex-a76"

# Build Bitcoin Core (use multiple cores for faster build)
RUN make -j$(nproc)
RUN make install

# Runtime stage
FROM ubuntu:22.04

# Avoid interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Install runtime dependencies only
RUN apt-get update && apt-get install -y \
    libssl3 \
    libevent-2.1-7 \
    libboost-system1.74.0 \
    libboost-filesystem1.74.0 \
    libboost-thread1.74.0 \
    libminiupnpc17 \
    libzmq5 \
    libdb++-dev \
    curl \
    gosu \
    jq \
    bc \
    && rm -rf /var/lib/apt/lists/*

# Create bitcoin user and group
RUN groupadd -r bitcoin && useradd -r -g bitcoin bitcoin

# Create directories
RUN mkdir -p /home/bitcoin/.bitcoin /var/log/bitcoin
RUN chown -R bitcoin:bitcoin /home/bitcoin /var/log/bitcoin

# Copy Bitcoin Core binaries from builder stage
COPY --from=builder /opt/bitcoin/bin/* /usr/local/bin/
COPY --from=builder /opt/bitcoin/lib/* /usr/local/lib/

# Create entrypoint script
COPY <<'EOF' /entrypoint.sh
#!/bin/bash
set -e

# If running as root, switch to bitcoin user
if [ "$(id -u)" = '0' ]; then
    # Ensure proper ownership
    chown -R bitcoin:bitcoin /home/bitcoin/.bitcoin
    chown -R bitcoin:bitcoin /var/log/bitcoin
    
    # Switch to bitcoin user
    exec gosu bitcoin "$@"
fi

# If we're already running as bitcoin user, just execute
exec "$@"
EOF

RUN chmod +x /entrypoint.sh

# Set working directory
WORKDIR /home/bitcoin

# Expose Bitcoin P2P and RPC ports
EXPOSE 8333 8332

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=300s --retries=3 \
  CMD bitcoin-cli -datadir=/home/bitcoin/.bitcoin getblockchaininfo || exit 1

# Use bitcoin user
USER bitcoin

# Set entrypoint
ENTRYPOINT ["/entrypoint.sh"]

# Default command
CMD ["bitcoind", "-datadir=/home/bitcoin/.bitcoin", "-printtoconsole", "-conf=/home/bitcoin/.bitcoin/bitcoin.conf"]

# Labels
LABEL maintainer="Bitcoin Node Setup"
LABEL description="Bitcoin Core node optimized for Raspberry Pi 5"
LABEL version="${BITCOIN_VERSION}"
LABEL architecture="arm64"