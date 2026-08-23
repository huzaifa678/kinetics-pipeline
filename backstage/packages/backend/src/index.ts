/*
 * Kinetics Backstage backend — the new (2024+) backend system. Each feature is
 * a module registered on the shared backend; config comes from app-config*.yaml.
 * Plugins chosen for THIS platform: catalog + GitHub org discovery, Kubernetes
 * (live pod/Rollout health), Argo CD (sync status), TechDocs, scaffolder,
 * search, and Cognito OIDC auth (guest in dev).
 */
import { createBackend } from '@backstage/backend-defaults';

const backend = createBackend();

backend.add(import('@backstage/plugin-app-backend'));
backend.add(import('@backstage/plugin-proxy-backend'));

backend.add(import('@backstage/plugin-catalog-backend'));
backend.add(import('@backstage/plugin-catalog-backend-module-github'));
backend.add(import('@backstage/plugin-catalog-backend-module-github-org'));
backend.add(
  import('@backstage/plugin-catalog-backend-module-scaffolder-entity-model'),
);

backend.add(import('@backstage/plugin-scaffolder-backend'));

backend.add(import('@backstage/plugin-techdocs-backend'));

backend.add(import('@backstage/plugin-search-backend'));
backend.add(import('@backstage/plugin-search-backend-module-catalog'));
backend.add(import('@backstage/plugin-search-backend-module-techdocs'));

backend.add(import('@backstage/plugin-auth-backend'));
backend.add(import('@backstage/plugin-auth-backend-module-guest-provider'));
backend.add(import('@backstage/plugin-auth-backend-module-oidc-provider'));

backend.add(import('@backstage/plugin-permission-backend'));
backend.add(
  import('@backstage/plugin-permission-backend-module-allow-all-policy'),
);

backend.add(import('@backstage/plugin-kubernetes-backend'));
backend.add(import('@roadiehq/backstage-plugin-argo-cd-backend/alpha'));

backend.start();
