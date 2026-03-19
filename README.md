# jnlp-anywhere

Java Web Start was a raging dumpster fire — arbitrary code execution from a URL, signed with certificates that could be compromised, running with permissions the user probably didn't intend to grant.

Since it was officially killed in Java 11, and banished from the browsers long before that, it is no small task to access these applications with modern software.

jnlp-anywhere is a container that solves the access problem without solving it on your workstation. It fetches the JNLP file from the target device at runtime, parses it, downloads whatever jars the application needs, and runs it inside an Xpra session accessible from any browser. No Java on your machine. No plugin. No Web Start. Just a URL.

Running these applications carries inherent risk that exists regardless of how you access them. jnlp-anywhere contains the execution environment but does not sanitize or inspect the application being run. The security posture of the application itself is your problem, not this container's.

---

## Project Status

This has only been tested on x86_64 via the Quick start command line with an ISY-994 as target.

Container is not optimized or hardened; There are no protections against naughty webstart applications.

**No lifeguards are present. Swim at your own risk.** 

---

## How it works

Point it at a JNLP URL. Everything else is derived automatically. Hopefully.

```
JNLP_URL=http://192.168.1.x/admin.jnlp
```

The container fetches the JNLP file, parses the codebase, downloads all declared jars, constructs the classpath, extracts the main class and any application arguments, and launches the application under Xpra. The HTML5 client is served on the same port. Open a browser, get a window.

The native Xpra client also works on the same port. However, inclusion is incidental.

---

## Requirements

- A container platform - Docker, Kubernetes, Podman, whatever (maybe)
- A device serving a JNLP file on a reachable URL with no authentication
- Java 8 compatible application (most legacy JNLP applications are)

---

## Quick start

```bash
docker run -e JNLP_URL=http://192.168.1.x/admin.jnlp \
  -p 14500:14500 \
  ghcr.io/lostsynapse/jnlp-anywhere:latest
```

Open `http://localhost:14500` in a browser.

---

## Authentication

jnlp-anywhere supports four authentication modes ranging from no authentication to layered proxy and application-level auth. The right choice depends on your network topology and threat model — that decision is yours to make.

See the [Traefik + Authentik integration guide](docs/traefik-authentik.md) for one complete deployment pattern. Orchestration examples for Swarm and k3s are in the [examples](examples/) directory.

---

## Environment Variables

| Variable | Required | Description |
| --- | --- | --- |
| `JNLP_URL` | Yes | Full URL to the JNLP file |
| `XPRA_PASSWORD` | No | Enables password authentication on the Xpra session. If unset, the session is unauthenticated. |
| `XPRA_PRESEED_PASSWORD` | No | Set to `true` to write the password into the HTML5 client's default settings, pre-filling the connect dialog. Requires `XPRA_PASSWORD`. Do not use if the port is directly exposed without a reverse proxy — the password will be served to any browser that can reach it. |
| `XPRA_AUDIO` | No | Set to `true` to enable audio forwarding via PulseAudio. Disabled by default. May be supported by JNLP applications that use audio output such as IPMI SOL viewers. (untested) |
| `XPRA_DEBUG` | No | Set to `1` for Xpra verbose logging. Set to `2` for shell trace. Set to `3` for both. |

---

## Session lifecycle

Understanding how the container behaves across different exit scenarios is important for choosing the right deployment model.

**Application exits normally** — the user closes the application window. The Xpra session ends, the container exits, and the orchestrator restarts it per the configured restart policy. The next connection fetches a fresh JNLP and starts clean. This is the expected cluster behavior.

**Application crashes** — same path as a normal exit. If the crash is reproducible the orchestrator will restart with backoff and eventually mark the service as failed. Worth monitoring if the target application is known to be unstable.

**Browser disconnects** — Xpra keeps the application session alive when the browser disconnects. The Java application continues running inside the container. Reconnecting from any browser resumes the existing session. The container does not exit on browser disconnect.

**Container running with no active connection** — the application runs idle until the user reconnects, the application itself times out, or the service is manually disabled. For occasional management tasks this is acceptable. For resource-constrained clusters it is worth considering.

**Recommended cluster behavior** — deploy with a restart policy so the container recovers from application exits and crashes automatically. Disable the service manually when the management task is complete rather than relying on automatic teardown. This gives full control over when the resource is consumed without requiring intervention for transient failures.

**Quick access without an orchestrator** — the `docker run` one-liner in the quick start section is the right tool for a single session. The container exits when the application closes and does not restart. No cleanup required.

---

## Known limitations

**Java version:** The container runs OpenJDK 8. Applications requiring a newer or older Java version are not supported.

**Multi-jar applications:** All jars declared in the JNLP resources block are downloaded and added to the classpath. Applications that dynamically load additional jars at runtime outside the JNLP declaration may not work correctly.

**Signed jars and security dialogs:** Some applications present security dialogs during launch. These will appear in the Xpra session and must be accepted manually on first run.

**Session persistence:** The container runs a single Xpra session tied to the application lifecycle. When the application exits, the container exits. This is intentional — the container is not designed as a persistent desktop.

**Native client through a proxy:** The native Xpra client cannot complete an OIDC authentication flow. It connects directly to port 14500 only. See the auth documentation for details.

**App windows misbehave:** Some independent windows that should be hidden at start are not, may be layered incorrectly or differently than you expect, program is ugly, etc.


---

## License

MIT. Do what you want with it.
