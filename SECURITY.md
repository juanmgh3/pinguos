# Security

## Reporting

Open a private security advisory through the repository's Security tab. Please
do not open a public issue for a vulnerability.

## What the bridge is

`claude-bridge.js` is a local HTTP server that spawns `claude` with its working
directory set to this repo. Anything that can POST to it runs code as you. It is
built to be reachable only from your own machine and from a Minecraft world you
control.

It defends itself four ways:

- Binds `127.0.0.1` only, never `0.0.0.0`.
- Rejects any `Host` that is not loopback, which is what stops DNS rebinding.
- Rejects cross-origin `Origin`/`Referer`, and requires `Content-Type:
  application/json` so a browser form cannot reach it.
- Requires a token in `X-Bridge-Token` on the chat route. The token is generated
  at startup, or set with `BRIDGE_TOKEN`.

## What it does not defend against

Another process running as you on the same machine. That process already has
your privileges and does not need the bridge.

## Do not expose it

Do not port-forward it, and do not put it behind a tunnel. It is a local tool.
