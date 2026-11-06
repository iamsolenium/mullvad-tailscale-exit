# mullvad-tailscale-exit

A Tailscale exit node whose traffic all goes out through the Mullvad VPN, running in Docker.

The project runs two Docker containers:

| Service     | Container           | Role |
|-------------|---------------------|------|
| `mullvad`   | `mullvad-1`         | `mullvad-daemon` (Arch Linux), keeps the Mullvad VPN tunnel up |
| `tailscale` | `tailscale-mullvad` | Tailscale node `mullvad-exit`, advertised as an **exit node** |

The Tailscale container shares the Mullvad container's network stack (`network_mode: service:mullvad`).
Any device on your tailnet that picks `mullvad-exit` as its exit node reaches the Internet with a
Mullvad IP, and doesn't need the Mullvad client installed.

```
 [tailnet device] ──tailscale──▶ [tailscale-mullvad] ─┐ same netns
                                 [mullvad-1] ──wg──▶ Mullvad server ──▶ Internet
```

---

## Requirements

- Linux with Docker and Docker Compose v2 (`docker compose`)
- The `tun` module on the host (`/dev/net/tun` must exist)
- A Mullvad account (16-digit number) with at least one free device slot (max 5 per account)
- A Tailscale account and an **auth key** (Admin console → *Settings → Keys → Generate auth key*)

> The Mullvad container runs with `privileged: true`, which gives it near-full access to the host.
> Only run it on a machine you trust.

---

## How it works

- **Mullvad is controlled entirely through `docker exec`.** There is no GUI and no environment
  variable for the account. After the first start, you log in and start the VPN by hand (step 3).
  Changing servers, disconnecting and so on also go through `docker exec mullvad-1 mullvad …`.
- **Tailscale only starts once the Mullvad VPN is connected** (healthcheck).
- **The Tailscale machine must be approved as an exit node** in the admin console, unless
  auto-approval (`autoApprovers`) is enabled in your policy.

## Setup

### 1. Provide the Tailscale auth key

```bash
echo -n 'tskey-auth-XXXXXXXXXXXX' > ts_authkey.txt
chmod 600 ts_authkey.txt
```

This file is mounted as a Docker secret (`/run/secrets/ts_authkey`). **Do not commit it**
(it is already in `.gitignore`). Because `TS_AUTH_ONCE=true`, the key is only used for the first
registration. After that, the node state lives in the `tailscale-state` volume.

### 2. Build and start Mullvad on its own

```bash
docker compose build
docker compose up -d mullvad
```

Start Mullvad alone first because Tailscale waits for it to be `healthy`, meaning connected.
On the very first start the daemon isn't logged in to any account. A full `docker compose up -d`
would end with `dependency failed to start: container mullvad-1 is unhealthy`.

### 3. Configure Mullvad with `docker exec` (once)

```bash
docker exec -it mullvad-1 mullvad account login 1234567890123456
docker exec -it mullvad-1 mullvad relay set location se      # optional: country/city/server
docker exec -it mullvad-1 mullvad auto-connect set on        # reconnect automatically on restart
docker exec -it mullvad-1 mullvad lockdown-mode set on       # optional: block everything outside the tunnel
docker exec -it mullvad-1 mullvad connect
docker exec -it mullvad-1 mullvad status
```

The configuration (account, device, relay) is kept in the `mullvad-state` volume.

### 4. Start Tailscale

```bash
docker compose ps          # wait until mullvad-1 shows (healthy), about 30 s
docker compose up -d
```

### 5. Approve the exit node

In the Tailscale admin console, open the **mullvad-exit** machine, go to *Edit route settings*
and tick **Use as exit node**. You can skip this step by setting `autoApprovers` in your ACL policy.

---

## Usage

On a tailnet device:

```bash
tailscale set --exit-node=mullvad-exit            # Linux/macOS CLI
# or from the GUI: Exit node → mullvad-exit
curl https://am.i.mullvad.net/connected           # should reply "You are connected..."
tailscale set --exit-node=                        # turn it off
```

### Useful commands

```bash
docker compose ps                                  # status and healthcheck
docker compose logs -f mullvad                     # daemon logs (-vv)
docker compose logs -f tailscale
docker exec mullvad-1 mullvad status -v            # current relay, exit IP
docker exec mullvad-1 mullvad relay list           # available servers
docker exec mullvad-1 mullvad relay set location ch zrh   # switch server
docker exec mullvad-1 mullvad disconnect           # stop the VPN
docker exec tailscale-mullvad tailscale status
docker exec mullvad-1 curl -s https://am.i.mullvad.net/json   # IP/server as seen from outside
```

### Updating

```bash
docker compose build --pull --no-cache mullvad
docker compose pull tailscale
docker compose up -d
```

### Full reset

```bash
docker exec mullvad-1 mullvad account logout   # frees the device slot on your Mullvad account
docker compose down -v                         # ⚠ deletes the volumes (Mullvad + Tailscale state)
```

If you delete the volumes without logging out first, the device still counts against your Mullvad
account. You'll then have to remove it from the Mullvad website.

---

## Healthcheck

The Mullvad container is `healthy` when both of these are true:
1. `mullvad status` starts with `Connected`
2. `https://am.i.mullvad.net/connected` confirms that traffic goes out through Mullvad

The check runs every 30 s. If `am.i.mullvad.net` is down, the container turns `unhealthy` even
though the tunnel works. That doesn't affect Tailscale once it is running, because `depends_on`
only applies at startup.

---

## Troubleshooting

**`mullvad-1` stays `unhealthy`**
: Run `docker exec mullvad-1 mullvad status`. Most of the time the account isn't logged in
  or `mullvad connect` hasn't been run.

**Tailscale stays waiting / doesn't start**
: This is expected until Mullvad is connected, because Tailscale waits for `mullvad-1` to be `healthy`.
  Do step 3 (login + connect via `docker exec`), then run `docker compose up -d` again.

**The exit node doesn't show up on devices**
: The `mullvad-exit` machine hasn't been approved as an exit node in the Tailscale admin console
  yet (see step 5), and `autoApprovers` isn't configured.

**`/dev/net/tun` not found**
: Run `sudo modprobe tun` on the host.

**Split tunneling or cgroup warnings in the logs**
: They don't block anything as long as the tunnel comes up. `cgroup: private` is there to keep the
  daemon from touching the host's cgroups.

---

## Files

```
.
├── Dockerfile        # Arch image + mullvad-vpn-daemon
├── compose.yml       # mullvad + tailscale services, volumes, secret
├── ts_authkey.txt    # (you create it; secret, not committed)
└── README.md
```
