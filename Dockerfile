# Docmost wrapper for Railway. Upstream runs as the node user (uid 1000) and keeps pages' uploads under /app/data/storage, but
# Railway mounts a volume owned by root, so the wrapper boots as root, hands the storage to uid 1000, and drops back to it before
# the stock `node dist/main`. The connection strings and the public address are built from Railway's variables, sign-up needs no
# closing (Docmost has none beyond the one-time workspace setup, which the wrapper performs at boot with a generated password),
# and the server refuses to start without strong secrets.
# upstream: docmost/docmost
FROM docmost/docmost:0.97.0@sha256:40c454d74ffdd9ecb15833e4d96f3a630d59aad862a1869381ae6ee086454419

USER root
COPY --chmod=0755 boot.sh /railway-boot.sh

ENV PORT=8080 NODE_ENV=production \
    ADMIN_EMAIL=admin@example.com
EXPOSE 8080

ENTRYPOINT ["/railway-boot.sh"]
CMD ["pnpm", "start"]
