"""Optional Amazon Cognito JWT auth for the inference API.

Disabled-unless-configured (mirrors ``observability.init_tracer``): when
``COGNITO_ISSUER`` is unset the dependency is a no-op, so dev / in-cluster runs
stay open. When set, ``require_jwt`` validates the ``Bearer`` token's RS256
signature against the pool JWKS and checks ``iss`` / ``exp`` / ``token_use``.

Env
---
* ``COGNITO_ISSUER``   — e.g. ``https://cognito-idp.us-east-1.amazonaws.com/<pool-id>``.
                         Empty ⇒ auth disabled.
* ``COGNITO_JWKS_URL`` — defaults to ``<issuer>/.well-known/jwks.json``.
* ``COGNITO_AUDIENCE`` — optional comma-sep allow-list of app client ids
                         (matched against ``client_id`` for access tokens or
                         ``aud`` for id tokens). Empty ⇒ any client in the pool.
"""

from __future__ import annotations

import os
from functools import lru_cache
from typing import Any

from fastapi import Header, HTTPException

from ..observability import get_logger

log = get_logger("kinetics_serving_auth")

_ISSUER = os.environ.get("COGNITO_ISSUER", "").rstrip("/")
_JWKS_URL = os.environ.get("COGNITO_JWKS_URL", "") or (
    f"{_ISSUER}/.well-known/jwks.json" if _ISSUER else ""
)


def auth_enabled() -> bool:
    """True when Cognito auth is configured."""
    return bool(_ISSUER)


@lru_cache(maxsize=1)
def _jwk_client() -> Any:
    import jwt  # lazy: only imported when auth is configured

    return jwt.PyJWKClient(_JWKS_URL)


def _allowed_clients() -> set[str]:
    return {c.strip() for c in os.environ.get("COGNITO_AUDIENCE", "").split(",") if c.strip()}


def require_jwt(authorization: str | None = Header(default=None)) -> None:
    """FastAPI dependency: enforce a valid Cognito JWT when auth is configured."""
    if not auth_enabled():
        return  # auth disabled (dev / in-cluster)

    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="missing bearer token")
    token = authorization.split(" ", 1)[1].strip()

    import jwt  # lazy import

    try:
        signing_key = _jwk_client().get_signing_key_from_jwt(token).key
        claims = jwt.decode(
            token,
            signing_key,
            algorithms=["RS256"],
            issuer=_ISSUER,
            # Cognito ACCESS tokens carry `client_id` (not `aud`); we check the
            # client allow-list ourselves below, so skip aud verification here.
            options={"verify_aud": False},
        )
    except Exception as exc:
        raise HTTPException(status_code=401, detail="invalid token") from exc

    if claims.get("token_use") not in {"access", "id"}:
        raise HTTPException(status_code=401, detail="unexpected token_use")

    allowed = _allowed_clients()
    if allowed and (claims.get("client_id") or claims.get("aud")) not in allowed:
        raise HTTPException(status_code=403, detail="client not allowed")
