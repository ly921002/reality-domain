FROM alpine:3.21

RUN apk add --no-cache \
    bash \
    curl \
    iputils \
    bind-tools \
    openssl \
    ca-certificates \
    coreutils

WORKDIR /app

COPY entrypoint.sh .

RUN chmod +x /app/entrypoint.sh

ENTRYPOINT ["/app/entrypoint.sh"]
