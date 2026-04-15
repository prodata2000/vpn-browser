# VPN Browser Jumpbox

A full Linux desktop in your browser, tunneled through a WireGuard VPN. All traffic is forced through the VPN — the desktop cannot touch the internet until the tunnel is confirmed active.

```
Your browser → https://<host>:4001 → webtop desktop → gluetun VPN → internet
               http://<host>:4002  → VPN dashboard ──┘
```

## How it works

| Container | Image | Role |
|-----------|-------|------|
| `jumpbox-vpn` | `qmcgaw/gluetun` | WireGuard VPN gateway. Owns the network namespace. Built-in kill switch. HTTP control API on port 8000. |
| `jumpbox-desktop` | `lscr.io/linuxserver/webtop` | Full Linux desktop (XFCE/MATE/KDE) accessible via browser. Shares the VPN's network namespace. |
| `jumpbox-webui` | `scuzza/gluetun-webui` | Web dashboard showing VPN status, exit IP, and start/stop control. Shares the VPN's network namespace. |

All three containers share gluetun's network namespace — traffic is routed through the tunnel with no exceptions. The desktop and webui will not start until gluetun's healthcheck confirms the tunnel is active.

---

## Requirements

- Docker with Compose v2 (`docker compose version`)
- A WireGuard config from your VPN provider (ProtonVPN or Mullvad)
- Optionally: Tailscale installed on the host for remote access

---

## Windows

The jumpbox runs on Windows via Docker Desktop. The Linux containers work identically regardless of host OS. Only the deploy/stop scripts differ.

**Requirements:**
- [Docker Desktop for Windows](https://www.docker.com/products/docker-desktop/) with the **WSL2 backend** enabled (Settings → General → Use WSL 2 based engine)
- PowerShell 5.1 or later (included with Windows 10/11)

**Deploy and stop using PowerShell:**

```powershell
.\deploy.ps1
.\stop.ps1
.\stop.ps1 -Volumes    # also delete saved desktop state
```

If you have **Git Bash** or **WSL2** installed, the original `.sh` scripts work unchanged:

```bash
bash deploy.sh
bash stop.sh
```

---

## Setup

### 1. Get a WireGuard config from your VPN provider

**ProtonVPN:**
1. Go to [account.proton.me/vpn/wireguard](https://account.proton.me/vpn/wireguard)
2. Create a WireGuard config for the server/country you want
3. Download the `.conf` file

**Mullvad:**
1. Go to [mullvad.net/account/wireguard-config](https://www.mullvad.net/en/account/wireguard-config)
2. Download a WireGuard config

### 2. Place the config

```
wireguard/wg0.conf
```

The deploy script will automatically extract the `PrivateKey` from this file. The `wireguard/` directory is gitignored — your keys will not be committed.

### 3. Configure `.env`

```bash
cp .env.example .env
```

Edit `.env`:

```env
VPN_PROVIDER=protonvpn          # protonvpn | mullvad
VPN_PRIVATE_KEY=                # auto-filled from wireguard/wg0.conf if blank
VPN_ADDRESSES=                  # Mullvad only: your WireGuard IP (e.g. 10.64.x.x/32)
VPN_COUNTRY=United States       # server country for gluetun to select

DESKTOP_ENV=xfce                # xfce | mate | kde
DESKTOP_PASSWORD=changeme       # password for the browser desktop session

TZ=America/New_York
```

> If `VPN_PRIVATE_KEY` is blank, `deploy.sh` reads it automatically from `wireguard/wg0.conf`.

### 4. Deploy

```bash
./deploy.sh
```

The script will:
1. Validate `.env` and extract the private key if needed
2. Pull images and start all three containers
3. Wait for the VPN tunnel to establish
4. Compare the VPN IP against your host IP to confirm traffic is tunneled
5. Print the desktop URL (and Tailscale URL if Tailscale is running)

**Access the desktop:**
```
https://localhost:4001
```

**Access the VPN dashboard:**
```
http://localhost:4002
```

Or over Tailscale:
```
https://<tailscale-ip>:4001
http://<tailscale-ip>:4002
```

Accept the self-signed certificate warning on port 4001. Enter `DESKTOP_PASSWORD` when prompted.

---

## Stopping

```bash
./stop.sh
```

To also delete the saved desktop state (browser history, files, settings):

```bash
docker compose down -v
```

---

## Switching VPN Servers

From a terminal inside the desktop, use `vpn-switch`:

```bash
# Check current VPN IP and tunnel state (queries gluetun API directly — instant)
vpn-switch status

```

**What happens when you switch:**
- Both containers are removed and recreated with the new country
- Your browser session disconnects for ~30 seconds
- The desktop auto-restarts and reconnects to the new tunnel
- Refresh the browser tab to reconnect

> WireGuard cannot change endpoints at runtime — a new tunnel must be built from scratch.
> This is a WireGuard kernel constraint, not a gluetun limitation. Container recreation is
> the only correct approach. The VPN dashboard at port 4002 will show the tunnel going
> offline and coming back up.

---

## VPN Dashboard

Open `http://<host>:4002` for a live view of the VPN connection.

The dashboard uses gluetun's HTTP control API (port 8000, internal only):

| Endpoint | What it shows |
|----------|---------------|
| VPN status | Running / stopped |
| Exit IP | Current public IP address through the tunnel |
| Connection details | Provider, server country, protocol |
| Start / Stop | Toggle the WireGuard tunnel (reconnects to same server) |

Port 8000 is blocked by gluetun's own firewall from the host and internet — it is only
reachable within the shared network namespace (desktop and webui containers).

---

## OSINT Tools

Run `osint-setup` from a terminal inside the desktop to install a comprehensive OSINT toolkit.
Tools are saved to `/config/bin` (persistent across container recreations).

```bash
osint-setup --list    # preview everything that will be installed
osint-setup           # install all tools
```

**What gets installed:**

| Category | Tools |
|----------|-------|
| Network & port scanning | nmap, masscan, netcat, traceroute, dig, whois |
| Web scanning | nikto, dirb, sqlmap, whatweb, wafw00f, photon |
| Subdomain & DNS | subfinder, dnsx, fierce, amass |
| HTTP probing | httpx, katana, gau, waybackurls |
| Vulnerability scanning | nuclei (+ auto-updated templates) |
| Port scanning (Go) | naabu |
| Email & domain OSINT | theHarvester, holehe, h8mail |
| Username enumeration | sherlock, maigret, socialscan |
| Shodan | shodan CLI |
| Metadata | exiftool, binwalk, foremost |
| Anonymisation | tor, torsocks, proxychains4 |
| Frameworks | recon-ng, spiderfoot, metagoofil |
| Utilities | jq, gobuster, anew, qsreplace, age |

---

## Secure Communications

Run `comms-setup` from a terminal inside the desktop to install a secure communications toolkit.

```bash
comms-setup --list        # preview everything that will be installed
comms-setup               # install all tools
comms-setup --configure   # interactive setup: GPG key, SMTP/IMAP config templates, Tor
```

**What gets installed:**

| Category | Tools |
|----------|-------|
| Email (GUI) | Thunderbird |
| Email (terminal) | Neomutt, mbsync (IMAP), msmtp (SMTP), notmuch |
| Encryption | GPG, Seahorse, Paperkey, age |
| Password manager | KeePassXC |
| Secure messaging | Signal Desktop, signal-cli, Gajim (XMPP/OMEMO), Profanity |
| Matrix | matrix-commander |
| IRC | WeeChat, HexChat, irssi |
| Anonymisation | Tor, torsocks, proxychains4, i2p |
| Privacy | mat2 (metadata removal), steghide |

The `--configure` mode walks through GPG key generation and writes example SMTP/IMAP
config files to `/config/comms/mail/` for use with a custom domain mail provider.

---

## Desktop Environments

Set `DESKTOP_ENV` in `.env` before deploying:

| Value | Desktop |
|-------|---------|
| `xfce` | XFCE (default, lightest) |
| `mate` | MATE |
| `kde` | KDE Plasma |

Changing the desktop environment after first run requires wiping the config volume (`docker compose down -v`) to avoid leftover state from the previous DE.

---

## Supported VPN Providers

| Provider | `VPN_PROVIDER` | Notes |
|----------|---------------|-------|
| ProtonVPN | `protonvpn` | Set `VPN_COUNTRY` for server selection. Leave `VPN_ADDRESSES` blank. |
| Mullvad | `mullvad` | Also requires `VPN_ADDRESSES` (your internal WireGuard IP, e.g. `10.64.x.x/32`). |

---

## File Structure

```
.
├── deploy.sh              # Start (macOS/Linux/Git Bash): validate, deploy, verify VPN
├── deploy.ps1             # Start (Windows PowerShell): same logic as deploy.sh
├── stop.sh                # Stop (macOS/Linux/Git Bash): docker compose down
├── stop.ps1               # Stop (Windows PowerShell): docker compose down [-Volumes]
├── docker-compose.yml     # gluetun + webtop + webui service definitions
├── gluetun-auth.toml      # gluetun HTTP API auth config (no-auth for internal use)
├── .env.example           # Config template — copy to .env and fill in
├── .env                   # Your config (gitignored)
├── wireguard/
│   └── wg0.conf           # WireGuard config from your VPN provider (gitignored)
└── scripts/
    ├── vpn-switch.sh      # Mounted into desktop as /usr/local/bin/vpn-switch
    ├── osint-setup.sh     # Mounted into desktop as /usr/local/bin/osint-setup
    ├── comms-setup.sh     # Mounted into desktop as /usr/local/bin/comms-setup
    └── install-tools.sh   # Auto-runs at container start (system prerequisites)
```

---

## Security Notes

- **Kill switch:** gluetun drops all traffic if the WireGuard tunnel goes down. `FIREWALL_INPUT_PORTS=3001,3002` opens only the desktop and webui ports — everything else is blocked.
- **DNS leak prevention:** DNS-over-TLS is enabled (`DOT=on`). DNS queries go through the VPN tunnel.
- **Desktop password:** The webtop session is HTTPS only. Set a strong `DESKTOP_PASSWORD` — anyone who can reach port 4001 and knows the password has full desktop access.
- **Docker socket:** The desktop has access to the host Docker socket (required for `vpn-switch`). This grants the desktop container full control over Docker on the host. Accept this tradeoff only if you trust the desktop session.
- **Gluetun API:** Port 8000 is not in `FIREWALL_INPUT_PORTS` and is unreachable from the host or internet. The `gluetun-auth.toml` sets auth to `none` — safe because the only way to reach port 8000 is from inside the network namespace (which requires the desktop password).
- **Private keys:** `wireguard/*.conf` and `.env` are gitignored. Never commit them.
