#!/usr/bin/env bash
set -euo pipefail

REGION="${REGION:-us-east-1}"
TFDIR="$(cd "$(dirname "$0")/../terraform" && pwd)"
# Cluster name = <project>-<environment>; resolve from terraform output so it
# tracks whatever was applied (dev/test/...), falling back to the dev default.
CLUSTER="${CLUSTER:-$(terraform -chdir="$TFDIR" output -raw eks_cluster_name 2>/dev/null || echo kinetics-pipeline-dev)}"
OVPN_OUT="${OVPN_OUT:-$HOME/Desktop/kinetics-vpn.ovpn}"
MODE="${1:-connect}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing required tool: $1" >&2; exit 1; }; }
need aws; need kubectl

# The cluster's EKS endpoint domain with the per-cluster hash label stripped,
# e.g. A1B2...gr7.us-east-1.eks.amazonaws.com -> gr7.us-east-1.eks.amazonaws.com.
# Used to scope split-DNS to this cluster's endpoints only.
RESOLVER_NS="${VPC_RESOLVER:-10.0.0.2}" # VPC .2 resolver, reachable over the tunnel
eks_domain() {
  local server host
  server="$(aws eks describe-cluster --name "$CLUSTER" --region "$REGION" --query 'cluster.endpoint' --output text 2>/dev/null || true)"
  host="${server#https://}"
  [ -n "$host" ] && echo "${host#*.}"
}

# `--dns-down` removes the split-DNS resolver file (run when off the VPN).
if [ "${MODE}" = "--dns-down" ]; then
  d="$(eks_domain)"
  if [ -n "$d" ] && [ -f "/etc/resolver/$d" ]; then
    sudo rm -f "/etc/resolver/$d" && echo "Removed /etc/resolver/$d"
  else
    echo "No split-DNS resolver file to remove."
  fi
  exit 0
fi

# 1. Resolve the Client VPN endpoint id (terraform output first, then AWS lookup).
EP="$(terraform -chdir="$TFDIR" output -raw client_vpn_endpoint_id 2>/dev/null || true)"
if [ -z "$EP" ] || [ "$EP" = "null" ]; then
  EP="$(aws ec2 describe-client-vpn-endpoints --region "$REGION" \
        --query 'ClientVpnEndpoints[?Status.Code==`available`].ClientVpnEndpointId | [0]' \
        --output text 2>/dev/null || true)"
fi
if [ -z "$EP" ] || [ "$EP" = "None" ]; then
  echo "No available Client VPN endpoint found in $REGION." >&2
  echo "Deploy it first:" >&2
  echo "  terraform -chdir=$TFDIR apply -target=module.vpc -target=module.eks -target=module.client_vpn -var-file=terraform.tfvars.dev" >&2
  exit 1
fi
echo "Client VPN endpoint: $EP"

# 2. Export the client config (.ovpn). For SAML/federated endpoints this already
#    contains 'auth-federate' — no client certificate needed.
aws ec2 export-client-vpn-client-configuration \
  --client-vpn-endpoint-id "$EP" --region "$REGION" \
  --output text > "$OVPN_OUT"
echo "Wrote profile: $OVPN_OUT"

if [ "$MODE" = "--export" ]; then
  echo "Export only. Import $OVPN_OUT into the AWS VPN Client when ready."
  exit 0
fi

# 3. Point kubectl at the cluster (works once the tunnel resolves it privately).
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER"

# 3b. Split-DNS: route ONLY this cluster's EKS domain to the VPC resolver, so the
#     endpoint resolves to its PRIVATE IP while connected. Without this, macOS
#     split-tunnel keeps using public DNS, kubectl hits the locked public endpoint
#     and hangs. No /etc/hosts needed; survives endpoint IP changes.
#     Undo when off the VPN with: ./vpn-connect.sh --dns-down
if [ "$(uname)" = "Darwin" ]; then
  DOMAIN="$(eks_domain)"
  if [ -n "$DOMAIN" ]; then
    echo "Configuring split-DNS: *.$DOMAIN -> $RESOLVER_NS (needs sudo)"
    sudo mkdir -p /etc/resolver
    printf "domain %s\nnameserver %s\n" "$DOMAIN" "$RESOLVER_NS" | sudo tee "/etc/resolver/$DOMAIN" >/dev/null
    sudo dscacheutil -flushcache 2>/dev/null || true
    sudo killall -HUP mDNSResponder 2>/dev/null || true
  fi
fi

# 4. Launch the AWS VPN Client. It can't be auto-connected from the CLI,
if [ "$(uname)" = "Darwin" ]; then
  open -a "AWS VPN Client" 2>/dev/null || \
    echo "Install it: brew install --cask aws-vpn-client"
fi
cat <<EOF

  ┌──────────────────────────────────────────────────────────────┐
  │ In the AWS VPN Client (one-time import, then just Connect):   │
  │   File > Manage Profiles > Add Profile                        │
  │     -> select: $OVPN_OUT
  │   Then click Connect and sign in via IAM Identity Center.     │
  └──────────────────────────────────────────────────────────────┘

EOF

# 5. Wait for the tunnel, then verify kubectl reaches the cluster.
echo "Waiting for the cluster API to become reachable (Ctrl-C to stop)..."
for i in $(seq 1 60); do
  if kubectl get --raw='/readyz' >/dev/null 2>&1; then
    echo "Connected. Cluster is reachable:"
    kubectl get nodes -o wide
    exit 0
  fi
  sleep 5
done
echo "Timed out waiting for the cluster API. Is the VPN connected and the SSO login complete?" >&2
exit 1
