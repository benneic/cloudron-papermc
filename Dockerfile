FROM cloudron/base:5.0.0@sha256:04fd70dbd8ad6149c19de39e35718e024417c3e01dc9c6637eaf4a41ec4e596c

# Install Java 21 and jq
RUN apt-get update && \
    apt-get install -y --no-install-recommends openjdk-21-jre-headless jq curl && \
    rm -rf /var/lib/apt/lists/*

# Install Node.js for the web panel
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# Create app directories
RUN mkdir -p /app/code /app/code/web /app/code/scripts

# Copy web panel
COPY web/package.json web/package-lock.json /app/code/web/
WORKDIR /app/code/web
RUN npm ci --production

COPY web/ /app/code/web/

# Copy scripts
COPY scripts/ /app/code/scripts/
RUN chmod +x /app/code/scripts/*.sh

# Copy server config defaults
COPY config/ /app/code/config/

# Copy start script
COPY start.sh /app/code/start.sh
RUN chmod +x /app/code/start.sh

EXPOSE 3000 25565

CMD [ "/app/code/start.sh" ]
