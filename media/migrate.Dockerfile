FROM arm64v8/debian:bullseye-slim
WORKDIR "/app"
RUN apt-get update && apt-get install -y pgloader libsqlite3-0 libpq5 curl && \
    curl -L https://github.com/dimitri/pgloader/releases/download/v3.6.7/pgloader-bundle-3.6.7.deb -o pgloader.deb && \
    dpkg -i pgloader.deb && rm pgloader.deb && \
    rm -rf /var/lib/apt/lists/*
COPY "migrate_db.sh" .
ENTRYPOINT ["./migrate_db.sh"]
