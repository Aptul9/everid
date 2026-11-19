# EverID

Single sign-on for the everbright services: Authentik 2026.8.5 at `https://id.everbright.it`.

## Layout
- `docker-compose.yml`: Postgres, Authentik server and worker, Caddy (TLS through sslh on `127.0.0.1:4451`). The server is also published on `172.17.0.1:9000` (docker0) for forward auth from the Caddy of each app on the VM.
- `blueprints/everid.yaml`: brand, groups, OIDC applications (`everdrive`, `everpush`, `everfit`, `everflow`), forward-auth applications (`calendar`, `teams`), group bindings, admin user. Secrets are read from the environment with `!Env`.
- `ci/deploy.sh`: release directory deploy, pre-deploy `pg_dump`, sslh route, nightly backup unit, public checks.
- `ci/rollback.sh`: previous release, or disable (stops EverID, removes only its sslh line; database kept).
- `ci/set-secrets.sh`: one-time secret generation into GitHub and the lockbox.

## Access
- Each application admits only its group: `app-drive`, `app-push`, `app-fit`, `app-flow`, `app-calendar`, `app-teams`. `everid-admins` is superuser.
- New person: create the user in EverID admin, add the app groups.
- No SMTP: password reset by an admin. TOTP and WebAuthn optional per user.

## Deploy
Push to `main` after a merged PR. The deploy refuses a changed `.env`: rotating a secret is a separate change on the VM.
