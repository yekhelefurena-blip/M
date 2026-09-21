# Blocky World multiplayer server (chat + player positions) — no graphics, tiny.
# Works on any host that runs Docker and gives you a public HTTPS/WSS URL
# (Render, Railway, Fly.io, a VPS ...). Players then type that address in the
# game (Marketplace tab -> Play with others -> Server).
#
#   docker build -t blocky-server .
#   docker run -p 9080:9080 blocky-server        # then connect to ws://<this-machine>:9080
#
# Most hosts pass the port in the PORT environment variable; the server reads it.
FROM debian:bookworm-slim

ARG GODOT_VERSION=4.4.1
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates wget unzip libfontconfig1 \
 && rm -rf /var/lib/apt/lists/*
RUN wget -q "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" -O /tmp/godot.zip \
 && unzip -q /tmp/godot.zip -d /tmp \
 && mv "/tmp/Godot_v${GODOT_VERSION}-stable_linux.x86_64" /usr/local/bin/godot \
 && rm /tmp/godot.zip

WORKDIR /app
COPY . /app
ENV PORT=9080
EXPOSE 9080
CMD ["godot", "--headless", "--path", "/app", "res://server.tscn", "--", "--server"]
