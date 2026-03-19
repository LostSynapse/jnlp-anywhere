# Traefik + Authentik Integration

This document covers one specific deployment pattern: Traefik as the ingress
proxy with Authentik providing forward auth. It is provided as a reference
for users running this stack.

jnlp-anywhere makes no assumptions about your security posture. Other proxy
and auth solutions are out of scope for this documentation.

---

## Port Behavior

Xpra serves both the HTML5 browser client and the native Xpra client on the
same TCP port (14500 by default). Protocol detection is automatic — a browser
connecting over WebSocket receives the HTML5 client, a native Xpra client
connecting with the Xpra protocol attaches directly. No additional
configuration is required to support both simultaneously.

---

## Authentication Modes

jnlp-anywhere supports four authentication modes determined by environment
variables and network topology.

| Mode | `XPRA_PASSWORD` | `XPRA_PRESEED_PASSWORD` | Forward Auth Proxy | Prompts |
|------|----------------|------------------------|-------------------|---------|
| Internal | Set | — | No | Xpra password prompt |
| External | Not set | — | Yes | Proxy auth only |
| Both | Set | — | Yes | Proxy auth + Xpra prompt |
| External with Passthrough | Set | `true` | Yes | Proxy auth only* |

*External with Passthrough: the password is written to `default-settings.txt`
at container startup so the HTML5 client can read it. Whether this results in
fully transparent auto-connect or merely pre-fills the password field requires
verification against a live instance. **To be confirmed during testing.**

### Direct Port Exposure and Preseed Mode

Xpra's HTML5 and native clients share a single port. This creates an
unavoidable interaction: if `XPRA_PRESEED_PASSWORD=true` is set and the port
is also directly published to the network, the password will be served via
`default-settings.txt` to any browser that can reach the port directly,
bypassing the proxy entirely.

Direct port exposure and preseed mode should not be used together unless the
network topology ensures the port is unreachable except through the proxy.
How you enforce this is your decision.

### Native Client and Forward Auth

The native Xpra client connects directly to port 14500 using the Xpra
protocol. It cannot complete an OIDC redirect flow and will fail to connect
through an Authentik-protected proxy. Users requiring native client access
should connect directly to port 14500, where authentication is governed by
`XPRA_PASSWORD` only, provided the port is reachable from their network.

---

## Prerequisites

- Traefik running as ingress with a working default middleware chain
- Authentik deployed and operational
- Forward auth confirmed working for at least one other service before
  adding this one

---

## Authentik Setup

### 1. Create a Provider

Navigate to **Applications → Providers → Create**.

- **Type:** Proxy Provider
- **Name:** jnlp-anywhere
- **Authorization flow:** Your standard authorization flow
- **Mode:** Forward auth (single application)
- **External host:** `https://jnlp.yourdomain.com`

### 2. Create an Application

Navigate to **Applications → Applications → Create**.

- **Name:** jnlp-anywhere
- **Slug:** jnlp-anywhere
- **Provider:** Select the provider created above

### 3. Assign to Outpost

Navigate to **Applications → Outposts**, edit your existing outpost, and add
jnlp-anywhere to it.

---

## Traefik Configuration

### Authentik Forward Auth Middleware

Define the forward auth middleware once and reuse across services. Skip if
already defined in your environment.

```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: authentik
spec:
  forwardAuth:
    address: http://authentik-server:9000/outpost.goauthentik.io/auth/traefik
    trustForwardHeader: true
    authResponseHeaders:
      - X-authentik-username
      - X-authentik-groups
      - X-authentik-email
      - X-authentik-name
      - X-authentik-uid
      - X-authentik-jwt
      - X-authentik-meta-jwks
      - X-authentik-meta-outpost
      - X-authentik-meta-provider
      - X-authentik-meta-app
      - X-authentik-meta-version
```

For Docker Swarm, define via file provider in Traefik static config.

### Service Labels (Docker Swarm)

```yaml
services:
  jnlp-anywhere:
    image: ghcr.io/lostsynapse/jnlp-anywhere:latest
    environment:
      - JNLP_URL=http://192.168.1.x/admin.jnlp
      - XPRA_PASSWORD=ChangeMeNow
      - XPRA_PRESEED_PASSWORD=true
    # Port 14500 enables direct native client access and browser access
    # bypassing the proxy. Remove if proxy-only access is required.
    ports:
      - "14500:14500"
    deploy:
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.jnlp-anywhere.rule=Host(`jnlp.yourdomain.com`)"
        - "traefik.http.routers.jnlp-anywhere.entrypoints=websecure"
        - "traefik.http.routers.jnlp-anywhere.tls=true"
        - "traefik.http.routers.jnlp-anywhere.tls.certresolver=letsencrypt"
        - "traefik.http.routers.jnlp-anywhere.middlewares=authentik@file"
        - "traefik.http.services.jnlp-anywhere.loadbalancer.server.port=14500"
```

### IngressRoute (k3s)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: jnlp-anywhere
spec:
  replicas: 1
  selector:
    matchLabels:
      app: jnlp-anywhere
  template:
    metadata:
      labels:
        app: jnlp-anywhere
    spec:
      containers:
      - name: jnlp-anywhere
        image: ghcr.io/lostsynapse/jnlp-anywhere:latest
        env:
        - name: JNLP_URL
          value: "http://192.168.1.x/admin.jnlp"
        - name: XPRA_PASSWORD
          valueFrom:
            secretKeyRef:
              name: jnlp-anywhere-secret
              key: password
        - name: XPRA_PRESEED_PASSWORD
          value: "true"
        ports:
        - containerPort: 14500
---
apiVersion: v1
kind: Service
metadata:
  name: jnlp-anywhere
spec:
  # NodePort exposes direct access on every node IP for native client use.
  # Traefik uses the ClusterIP (port 14500) internally regardless.
  # NodePort must be in the 30000-32767 range — 14500 is not valid here.
  # Remove nodePort and change type to ClusterIP if direct access is not required.
  type: NodePort
  selector:
    app: jnlp-anywhere
  ports:
  - port: 14500
    targetPort: 14500
    nodePort: 31450  # Native client connects to <node-ip>:31450
    # Remove nodePort line to let k3s assign automatically within 30000-32767
---
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: jnlp-anywhere
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`jnlp.yourdomain.com`)
      kind: Rule
      middlewares:
        - name: authentik
      services:
        - name: jnlp-anywhere
          port: 14500
  tls:
    certResolver: letsencrypt
```

---

## WebSocket

Xpra's HTML5 client uses WebSocket for the session after the initial HTTP
connection. Traefik handles WebSocket upgrades automatically with no
additional configuration required.
