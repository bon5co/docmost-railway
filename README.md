# docmost-railway

Thin wrapper over the official [Docmost](https://github.com/docmost/docmost) image for Railway. It boots as root only long enough
to hand the storage volume (`/app/data/storage`) to Docmost's uid 1000, then drops back to that uid and runs the stock server. It
builds `DATABASE_URL`, `REDIS_URL` and `APP_URL` from Railway's variables, and creates the first workspace and administrator from
`ADMIN_EMAIL` and `ADMIN_PASSWORD` through upstream's one-time setup call (upstream refuses it once a workspace exists, so redeploys
leave the owner's changed password alone). It refuses to start without a 12-character admin password, a 32-character application
secret, a database password and a Redis password. Used by the Docmost template on the Railway marketplace.
