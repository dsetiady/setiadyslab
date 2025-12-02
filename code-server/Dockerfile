FROM lscr.io/linuxserver/code-server:latest

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    git \
    build-essential \
    python3 \
    python3-pip \
    python3-venv \
    ca-certificates \
    gnupg \
    lsb-release \
    && rm -rf /var/lib/apt/lists/*

# Install Docker CLI + Docker Compose
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu jammy stable" > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y docker-ce-cli docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/*

# Install nvm (Node Version Manager)
ENV NVM_DIR=/usr/local/nvm
ENV NODE_VERSION=20.11.0
RUN mkdir -p $NVM_DIR \
    && curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash \
    && . $NVM_DIR/nvm.sh \
    && nvm install $NODE_VERSION \
    && nvm alias default $NODE_VERSION \
    && nvm use default

# Add nvm to PATH
ENV NODE_PATH=$NVM_DIR/versions/node/v$NODE_VERSION/lib/node_modules
ENV PATH=$NVM_DIR/versions/node/v$NODE_VERSION/bin:$PATH

# Install multiple Go versions directly
RUN mkdir -p /usr/local/go-versions && \
    # Install Go 1.21
    wget https://go.dev/dl/go1.21.6.linux-amd64.tar.gz && \
    tar -C /usr/local/go-versions -xzf go1.21.6.linux-amd64.tar.gz && \
    mv /usr/local/go-versions/go /usr/local/go-versions/go1.21.6 && \
    rm go1.21.6.linux-amd64.tar.gz && \
    # Install Go 1.22
    wget https://go.dev/dl/go1.22.0.linux-amd64.tar.gz && \
    tar -C /usr/local/go-versions -xzf go1.22.0.linux-amd64.tar.gz && \
    mv /usr/local/go-versions/go /usr/local/go-versions/go1.22.0 && \
    rm go1.22.0.linux-amd64.tar.gz && \
    # Set default to 1.22
    ln -s /usr/local/go-versions/go1.22.0 /usr/local/go

# Add Go to PATH
ENV PATH="${PATH}:/usr/local/go/bin:/root/go/bin"

# Install Rust
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

# Add Rust to PATH
ENV PATH="${PATH}:/root/.cargo/bin"

# Install global npm packages
RUN npm install -g yarn pnpm typescript ts-node nodemon expo-cli

# Create helper script to switch Go versions
RUN echo '#!/bin/bash' > /usr/local/bin/goswitch && \
    echo 'if [ -z "$1" ]; then' >> /usr/local/bin/goswitch && \
    echo '  echo "Usage: goswitch <version>"' >> /usr/local/bin/goswitch && \
    echo '  echo "Available versions:"' >> /usr/local/bin/goswitch && \
    echo '  ls /usr/local/go-versions/' >> /usr/local/bin/goswitch && \
    echo '  exit 1' >> /usr/local/bin/goswitch && \
    echo 'fi' >> /usr/local/bin/goswitch && \
    echo 'if [ -d "/usr/local/go-versions/go$1" ]; then' >> /usr/local/bin/goswitch && \
    echo '  rm -f /usr/local/go' >> /usr/local/bin/goswitch && \
    echo '  ln -s /usr/local/go-versions/go$1 /usr/local/go' >> /usr/local/bin/goswitch && \
    echo '  echo "Switched to Go $1"' >> /usr/local/bin/goswitch && \
    echo '  go version' >> /usr/local/bin/goswitch && \
    echo 'else' >> /usr/local/bin/goswitch && \
    echo '  echo "Go version $1 not found"' >> /usr/local/bin/goswitch && \
    echo 'fi' >> /usr/local/bin/goswitch && \
    chmod +x /usr/local/bin/goswitch

# Setup shell initialization
RUN echo 'export NVM_DIR="/usr/local/nvm"' >> /etc/bash.bashrc \
    && echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >> /etc/bash.bashrc \
    && echo '# Install gopls if needed: go install golang.org/x/tools/gopls@latest' >> /etc/bash.bashrc \
    && echo 'alias dc="docker compose"' >> /etc/bash.bashrc \
    && echo 'alias dcu="docker compose up -d"' >> /etc/bash.bashrc \
    && echo 'alias dcd="docker compose down"' >> /etc/bash.bashrc \
    && echo 'alias dcl="docker compose logs -f"' >> /etc/bash.bashrc