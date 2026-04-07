FROM eclipse-temurin:25-jre-noble AS java-runtime

FROM cloudron/base:5.0.0@sha256:04fd70dbd8ad6149c19de39e35718e024417c3e01dc9c6637eaf4a41ec4e596c

# Paper API lists 26.x before 1.21.x; pin so bundled Geyser/Floodgate stay compatible.
# Override in Cloudron: PAPER_MC_VERSION=… 
ENV PAPER_MC_VERSION=1.21.11

# PaperMC stable builds may require newer Java than distro packages; bundle Temurin JRE.
COPY --from=java-runtime /opt/java/openjdk /opt/java/openjdk
ENV JAVA_HOME=/opt/java/openjdk
ENV PATH="${JAVA_HOME}/bin:${PATH}"

# jq, curl (Java from Temurin stage above)
RUN apt-get update && \
    apt-get install -y --no-install-recommends jq curl && \
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
