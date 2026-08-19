# Kinetics Developer Portal (Backstage)

An internal developer portal (IDP) for the Kinetics platform, deployed **VPN-only**
behind ingress-nginx + cert-manager at `backstage.freeeasycrypto.com` — the same
private edge as the ArgoCD UI. It surfaces the service catalog, live Kubernetes /
Argo Rollouts health, Argo CD sync status, TechDocs and a scaffolder, with sign-in
via the existing Cognito user pool (guest auth in local dev).

## What lives where

| Concern | Location |
|---|---|
| App source (this dir) | `backstage/` — a Backstage monorepo (backend + frontend) |
| Container image | built by `.github/workflows/docker-build.yml` (`backstage-<sha>` tag → the shared ECR repo) |
| Postgres (required in prod) | `terraform/infra/modules/rds` (gated on `enable_backstage`) |
| Cognito OIDC client + secret | `terraform/infra/modules/cognito` (+ `kinetics-backstage-oidc-<env>` in Secrets Manager) |
| Deployment / Ingress / secrets | **Kinetics-CD** → `gitops/apps/backstage/` + `gitops/apps/backstage.yaml` |

## This is a scaffold + customizations, not a vendored node build

The genuinely custom, reviewable wiring is complete and lives here:

- `app-config.yaml` / `app-config.production.yaml` — integrations (GitHub, Kubernetes,
  Argo CD, TechDocs), the Postgres connection, and Cognito OIDC auth (all secrets by env).
- `packages/backend/src/index.ts` — the new-backend-system plugin registrations.
- `packages/app/src/{App.tsx,apis.ts,components/*}` — the sign-in wiring (Cognito/guest)
  and the EntityPage Kubernetes tab + Argo CD card.
- `catalog/all.yaml` — seed catalog describing this platform.
- `Dockerfile` — the official Backstage host-build packaging.

Finalize the standard boilerplate + lockfile locally once (Node 20/22):

```bash
cd backstage
corepack enable
yarn install          # generates yarn.lock (commit it)
yarn tsc
yarn build:backend    # produces packages/backend/dist/*.tar.gz for the Dockerfile
```

If you prefer to regenerate the base app from scratch, `npx @backstage/create-app`
then overlay the files above — they are the only edits over a vanilla scaffold.

## Runtime configuration (env → provided by the Helm Deployment)

All injected from the ESO-synced `backstage-secrets` / `backstage-db` Secrets:

| Env | Source |
|---|---|
| `POSTGRES_{HOST,PORT,USER,PASSWORD,DB}` | `kinetics-backstage-db-<env>` (RDS) |
| `COGNITO_METADATA_URL` / `COGNITO_CLIENT_ID` / `COGNITO_CLIENT_SECRET` | `kinetics-backstage-oidc-<env>` |
| `GITHUB_TOKEN` | GitHub App/PAT secret |
| `ARGOCD_URL` / `ARGOCD_AUTH_TOKEN` | ArgoCD service + token |
| `BACKEND_SECRET` | random 32-byte, generated into the secret |
| `BACKSTAGE_HOST` | `backstage.freeeasycrypto.com` (non-secret env) |

## Local dev

```bash
yarn dev   # app on :3000, backend on :7007, SQLite in-memory, guest sign-in
```
