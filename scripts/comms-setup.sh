#!/usr/bin/env bash
# comms-setup — install a secure communications toolkit inside the jumpbox desktop
#
# Covers: encrypted email (GUI + terminal), custom-domain SMTP/IMAP, GPG,
#         secure messaging (Signal, XMPP/OMEMO, Matrix, IRC), anonymisation
#         (Tor, I2P), password management, and modern file encryption.
#
# Binary tools go to /config/bin  — persistent across container recreations.
# Config templates go to /config/comms/ — persistent.
# APT/pip packages must be reinstalled after container force-recreate (fast).
#
# Usage:
#   comms-setup               install everything
#   comms-setup --list        show what would be installed, no changes made
#   comms-setup --configure   interactive post-install: GPG key, SMTP/IMAP config

set -uo pipefail

# ── Colours ───────────────────────────────────────────────────────────────────
BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'
C_CYAN='\033[0;36m'; C_GREEN='\033[0;32m'; C_YELLOW='\033[1;33m'; C_RED='\033[0;31m'

# ── Paths ─────────────────────────────────────────────────────────────────────
BIN="/config/bin"
COMMS="/config/comms"      # config templates, keys, persistent data

# ── State ─────────────────────────────────────────────────────────────────────
LIST_ONLY=false; CONFIGURE=false
INSTALLED=0; SKIPPED=0; FAILED=0

case "${1:-}" in
    --list)      LIST_ONLY=true ;;
    --configure) CONFIGURE=true ;;
esac

# ── Logging ───────────────────────────────────────────────────────────────────
say()    { echo -e "  ${C_CYAN}▸${NC} $*"; }
ok()     { echo -e "  ${C_GREEN}✓${NC} ${BOLD}$1${NC}${2:+  ${DIM}$2${NC}}"; (( INSTALLED++ )) || true; }
skip()   { echo -e "  ${C_YELLOW}·${NC} ${DIM}$1 — already installed${NC}"; (( SKIPPED++ )) || true; }
fail()   { echo -e "  ${C_RED}✗${NC} $1${2:+ — $2}"; (( FAILED++ )) || true; }
section(){ echo ""; echo -e "  ${BOLD}${C_CYAN}── $* ──${NC}"; }
note()   { echo -e "  ${DIM}ℹ  $*${NC}"; }

# ── Bootstrap ─────────────────────────────────────────────────────────────────
bootstrap() {
    mkdir -p "$BIN" "$COMMS/keys" "$COMMS/mail" "$COMMS/signal"
    if ! grep -q 'config/bin' ~/.bashrc 2>/dev/null; then
        printf '\n# Jumpbox tools\nexport PATH="/config/bin:$PATH"\n' >> ~/.bashrc
    fi
    export PATH="$BIN:$PATH"

    # Suppress PackageKit D-Bus errors — it is not running in the container.
    # Without this, apt-get emits GDBus errors that look like failures.
    export DEBIAN_FRONTEND=noninteractive
    sudo rm -f /etc/apt/apt.conf.d/20packagekit 2>/dev/null || true
}

# ── Install helpers ───────────────────────────────────────────────────────────
apt_pkg() {
    local pkg="$1" check="${2:-}"
    $LIST_ONLY && { echo "  [apt]  $pkg"; return; }
    if [[ -n "$check" ]] && command -v "$check" &>/dev/null; then
        skip "$check"; return
    fi
    say "apt: $pkg"
    if sudo DEBIAN_FRONTEND=noninteractive \
        apt-get install -y -q --no-install-recommends "$pkg" >/dev/null 2>&1; then
        ok "$pkg"
    else
        fail "$pkg" "apt install failed"
    fi
}

pip_pkg() {
    local pkg="$1" check="${2:-$1}"
    $LIST_ONLY && { echo "  [pip]  $pkg"; return; }
    command -v "$check" &>/dev/null && { skip "$check"; return; }
    say "pip: $pkg"
    if sudo /usr/bin/python3 -m pip install -q \
        --no-cache-dir --prefer-binary --break-system-packages "$pkg" >/dev/null 2>&1; then
        ok "$check"
    else
        fail "$pkg" "pip install failed"
    fi
}

gh_bin() {
    local name="$1" repo="$2" pattern="$3"
    $LIST_ONLY && { echo "  [bin]  $name  (github.com/$repo)"; return; }
    [[ -x "$BIN/$name" ]] && { skip "$name"; return; }
    say "downloading: $name"
    local url
    url=$(curl -sf --max-time 10 "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null \
        | python3 -c "
import sys, json, re
try:
    d = json.load(sys.stdin)
    for a in d.get('assets', []):
        if re.search(r'$pattern', a['name'], re.IGNORECASE):
            print(a['browser_download_url']); break
except: pass
" 2>/dev/null) || true
    if [[ -z "$url" ]]; then fail "$name" "no asset matched '$pattern'"; return; fi
    local tmp; tmp=$(mktemp -d)
    local ext="${url##*.}"
    curl -sfL --max-time 180 "$url" -o "$tmp/pkg.$ext" 2>/dev/null \
        || { fail "$name" "download failed"; rm -rf "$tmp"; return; }
    mkdir -p "$tmp/out"
    case "$ext" in
        zip) unzip -q "$tmp/pkg.$ext" -d "$tmp/out" 2>/dev/null ;;
        gz)  tar -xzf "$tmp/pkg.$ext" -C "$tmp/out" 2>/dev/null ;;
        *)   cp "$tmp/pkg.$ext" "$tmp/out/$name" ;;
    esac
    local found; found=$(find "$tmp/out" -type f -name "$name" | head -1)
    if [[ -n "$found" ]]; then
        cp "$found" "$BIN/$name"; chmod +x "$BIN/$name"; ok "$name"
    else
        fail "$name" "binary not found in archive"
    fi
    rm -rf "$tmp"
}

# ── Banner ────────────────────────────────────────────────────────────────────
echo ""
echo -e "  ${BOLD}╔══════════════════════════════════════╗${NC}"
echo -e "  ${BOLD}║    Secure Communications Setup       ║${NC}"
echo -e "  ${BOLD}╚══════════════════════════════════════╝${NC}"
echo ""
if $LIST_ONLY; then
    echo -e "  ${C_YELLOW}Listing tools only — nothing will be installed.${NC}"
elif $CONFIGURE; then
    : # configure mode handled at the bottom
else
    echo -e "  Persistent binaries : ${C_CYAN}$BIN${NC}"
    echo -e "  Config & data       : ${C_CYAN}$COMMS${NC}"
    echo ""
    echo "  Updating package lists..."
    sudo apt-get update -qq
fi

$LIST_ONLY || $CONFIGURE || bootstrap

# ══════════════════════════════════════════════════════════════════════════════
if $CONFIGURE; then
# ── CONFIGURE MODE ────────────────────────────────────────────────────────────
echo ""
section "GPG Key Setup"

if gpg --list-secret-keys 2>/dev/null | grep -q sec; then
    echo ""
    echo -e "  ${C_YELLOW}Existing GPG secret keys:${NC}"
    gpg --list-secret-keys --keyid-format LONG 2>/dev/null | grep -E 'sec|uid'
    echo ""
    read -rp "  Generate an additional key? [y/N] " REPLY
    [[ "${REPLY,,}" == "y" ]] || { echo "  Skipping GPG generation."; }
fi

if ! gpg --list-secret-keys 2>/dev/null | grep -q sec || [[ "${REPLY,,}" == "y" ]]; then
    echo ""
    echo -e "  ${BOLD}Generating new GPG key (RSA 4096-bit):${NC}"
    gpg --full-generate-key
fi

KEY_ID=$(gpg --list-secret-keys --keyid-format LONG 2>/dev/null \
    | awk '/^sec/{print $2}' | cut -d/ -f2 | head -1)

if [[ -n "$KEY_ID" ]]; then
    echo ""
    echo -e "  ${C_GREEN}Your public key (share this freely):${NC}"
    gpg --armor --export "$KEY_ID" | tee "$COMMS/keys/public.asc"
    echo ""
    echo -e "  ${DIM}Saved to $COMMS/keys/public.asc${NC}"
    echo ""
    echo -e "  ${BOLD}Key fingerprint:${NC}"
    gpg --fingerprint "$KEY_ID"
fi

section "SMTP Config Template (msmtp)"
MSMTP="$COMMS/mail/msmtprc.example"
cat > "$MSMTP" << 'EOF'
# ~/.msmtprc — msmtp configuration for sending email
# Copy to ~/.msmtprc  and fill in your provider's settings.
# For Tor routing: uncomment the proxy_* lines.
#
# Set permissions:  chmod 600 ~/.msmtprc
# Store password encrypted:
#   echo "yourpassword" | gpg -e -r YOUR_KEY_ID > ~/.msmtp-password.gpg
# Then set:  passwordeval gpg --quiet --for-your-eyes-only --no-tty -d ~/.msmtp-password.gpg

defaults
auth           on
tls            on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile        ~/msmtp.log

account myemail
host           smtp.yourdomain.com      # e.g. smtp.fastmail.com / mail.proton.me / smtp.gmail.com
port           587                      # 587 (STARTTLS) or 465 (SSL)
from           you@yourdomain.com
user           you@yourdomain.com
passwordeval   gpg --quiet --for-your-eyes-only --no-tty -d ~/.msmtp-password.gpg
# proxy_host   127.0.0.1               # uncomment to route through Tor
# proxy_port   9050

account default : myemail
EOF
echo -e "  Template written to ${C_CYAN}$MSMTP${NC}"
echo -e "  ${DIM}Copy to ~/.msmtprc and fill in your SMTP credentials.${NC}"

section "IMAP Sync Config Template (mbsync)"
MBSYNC="$COMMS/mail/mbsyncrc.example"
cat > "$MBSYNC" << 'EOF'
# ~/.mbsyncrc — isync/mbsync IMAP sync configuration
# Copy to ~/.mbsyncrc and fill in your provider's settings.
#
# Sync:   mbsync -a
# Read:   neomutt   (set maildir to ~/Mail in ~/.neomuttrc)

IMAPAccount myemail
Host         imap.yourdomain.com       # e.g. imap.fastmail.com / 127.0.0.1 (ProtonMail Bridge)
User         you@yourdomain.com
PassCmd      "gpg --quiet --for-your-eyes-only --no-tty -d ~/.imap-password.gpg"
TLSType      IMAPS
Port         993
SSLVersions  TLSv1.2 TLSv1.3

IMAPStore myemail-remote
Account myemail

MaildirStore myemail-local
Subfolders   Verbatim
Path         ~/Mail/
Inbox        ~/Mail/INBOX

Channel myemail
Far          :myemail-remote:
Near         :myemail-local:
Patterns     *
Create       Both
Expunge      None
SyncState    *
EOF
echo -e "  Template written to ${C_CYAN}$MBSYNC${NC}"
echo -e "  ${DIM}Copy to ~/.mbsyncrc and fill in your IMAP credentials.${NC}"

section "Custom Domain Email — Quick Reference"
echo ""
printf '  %-38s %s\n' \
    "Provider (custom domain support)" "SMTP / IMAP" \
    "──────────────────────────────────" "─────────────────────────────" \
    "Fastmail (fastmail.com)"          "smtp.fastmail.com / imap.fastmail.com" \
    "ProtonMail + Bridge (proton.me)"  "127.0.0.1:1025 / 127.0.0.1:1143" \
    "Migadu (migadu.com)"              "smtp.migadu.com / imap.migadu.com" \
    "Mailbox.org"                      "smtp.mailbox.org / imap.mailbox.org" \
    "Riseup (.onion available)"        "smtp.riseup.net / mail.riseup.net"
echo ""
note "Tor-routed email: set proxy_host/proxy_port in msmtprc, use .onion addresses where available."
note "ProtonMail Bridge runs locally and gives you standard SMTP/IMAP for any mail client."

section "Tor Configuration"
if command -v tor &>/dev/null; then
    if ! systemctl is-active --quiet tor 2>/dev/null; then
        say "starting Tor..."
        sudo service tor start >/dev/null 2>&1 && ok "tor started" || note "start manually: sudo service tor start"
    else
        ok "tor is already running"
    fi
    echo ""
    echo -e "  SOCKS5 proxy: ${C_CYAN}127.0.0.1:9050${NC}"
    echo -e "  Route any tool through Tor:"
    echo -e "    ${BOLD}torsocks <command>${NC}         wrap any command"
    echo -e "    ${BOLD}proxychains4 <command>${NC}     via proxychains"
else
    note "tor not installed — run comms-setup first."
fi

echo ""
echo -e "  ${C_GREEN}${BOLD}Configuration complete.${NC}"
echo -e "  See ${C_CYAN}$COMMS/mail/${NC} for SMTP and IMAP templates."
echo ""
exit 0
fi   # end CONFIGURE block

# ══════════════════════════════════════════════════════════════════════════════
#  INSTALL MODE
# ══════════════════════════════════════════════════════════════════════════════

# ── Email clients ─────────────────────────────────────────────────────────────
section "Email Clients"
apt_pkg thunderbird  thunderbird  # GUI — built-in OpenPGP, works with any IMAP/SMTP
apt_pkg neomutt      neomutt      # terminal email client; GPG and notmuch integration
apt_pkg isync        mbsync       # IMAP sync → local Maildir (used by neomutt)
apt_pkg msmtp        msmtp        # lightweight SMTP client for sending
apt_pkg msmtp-mta    ""           # sendmail compatibility shim for msmtp
apt_pkg notmuch      notmuch      # fast email indexing and search
apt_pkg abook        abook        # terminal address book (neomutt integration)

# ── Encryption & key management ───────────────────────────────────────────────
section "Encryption & Key Management"
apt_pkg gnupg             gpg          # GPG2 — encrypt, sign, verify
apt_pkg gpg-agent         gpg-agent    # caches GPG passphrases between uses
apt_pkg pinentry-gtk2     pinentry-gtk2 # GUI passphrase dialog for GPG
apt_pkg seahorse          seahorse     # GUI manager for GPG and SSH keys
apt_pkg paperkey          paperkey     # export a GPG secret key to printable paper backup
apt_pkg openssl           openssl      # TLS certificates and symmetric encryption
apt_pkg keepassxc         keepassxc    # offline password manager with TOTP support

# age — modern, simple file encryption (replaces GPG for file-level encryption)
if $LIST_ONLY; then
    echo "  [bin]  age + age-keygen  (github.com/FiloSottile/age)"
elif [[ ! -x "$BIN/age" ]]; then
    say "downloading: age + age-keygen"
    AGE_VER=$(curl -sf --max-time 10 https://api.github.com/repos/FiloSottile/age/releases/latest \
        | python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'])" 2>/dev/null) || { fail "age" "version fetch failed"; AGE_VER=""; }
    if [[ -n "$AGE_VER" ]]; then
        tmp=$(mktemp -d)
        AGE_URL="https://github.com/FiloSottile/age/releases/download/${AGE_VER}/age-${AGE_VER}-linux-amd64.tar.gz"
        if curl -sfL --max-time 120 "$AGE_URL" -o "$tmp/age.tar.gz" 2>/dev/null \
            && tar -xzf "$tmp/age.tar.gz" -C "$tmp" 2>/dev/null; then
            cp "$tmp/age/age" "$BIN/age"
            cp "$tmp/age/age-keygen" "$BIN/age-keygen"
            chmod +x "$BIN/age" "$BIN/age-keygen"
            ok "age + age-keygen"
        else
            fail "age" "download failed"
        fi
        rm -rf "$tmp"
    fi
else
    skip "age"
fi

# ── Secure messaging — XMPP (E2E with OMEMO) ─────────────────────────────────
section "XMPP Messaging (OMEMO encrypted)"
apt_pkg profanity  profanity  # terminal XMPP client — OMEMO, OTR, PGP encryption
apt_pkg gajim      gajim      # GUI XMPP client — OMEMO plugin, file transfer, calls
note "XMPP accounts: create a free account at jabber.org, siacs.eu, or self-host with ejabberd."
note "OMEMO (Signal protocol for XMPP) provides forward secrecy and deniability."

# ── Secure messaging — Matrix ─────────────────────────────────────────────────
section "Matrix Messaging (E2E encrypted)"
pip_pkg matrix-commander  matrix-commander
note "Matrix accounts: register at matrix.org or self-host with Synapse."
note "matrix-commander: CLI client for scripted messaging and bots."
note "For the GUI Element client, open https://app.element.io in the desktop browser."

# ── Secure messaging — Signal ─────────────────────────────────────────────────
section "Signal"
apt_pkg default-jre  java  # signal-cli requires a Java runtime
gh_bin signal-cli  AsamK/signal-cli  'signal-cli-.*-Linux\.tar\.gz$'
note "signal-cli requires phone-number registration: signal-cli -u +1XXXXXXXXXX register"
note "Docs: github.com/AsamK/signal-cli/wiki/Quickstart"

# Signal Desktop (official Electron app — ~200 MB)
if $LIST_ONLY; then
    echo "  [apt]  signal-desktop  (official Signal APT repo)"
elif ! command -v signal-desktop &>/dev/null; then
    say "adding Signal Desktop APT repository..."
    if curl -sf https://updates.signal.org/desktop/apt/keys.asc 2>/dev/null \
        | sudo gpg --dearmor -o /usr/share/keyrings/signal-desktop-keyring.gpg 2>/dev/null \
        && echo 'deb [arch=amd64 signed-by=/usr/share/keyrings/signal-desktop-keyring.gpg] https://updates.signal.org/desktop/apt xenial main' \
            | sudo tee /etc/apt/sources.list.d/signal-xenial.list >/dev/null 2>&1 \
        && sudo apt-get update -qq \
        && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -q signal-desktop >/dev/null 2>&1; then
        ok "signal-desktop"
    else
        fail "signal-desktop" "check apt sources or install manually"
    fi
else
    skip "signal-desktop"
fi

# ── IRC ───────────────────────────────────────────────────────────────────────
section "IRC"
apt_pkg hexchat  hexchat  # GUI IRC client with SSL/TLS, DCC, SASL
apt_pkg weechat  weechat  # extensible terminal IRC client; plugins for Matrix, XMPP, Slack
apt_pkg irssi    irssi    # classic terminal IRC client with SSL
note "Connect to IRC over Tor:  torsocks irssi (or weechat)"
note "Privacy-focused IRC networks: Libera.Chat, IRCnet, OFTC (all support TLS + Tor)"

# ── Anonymisation ─────────────────────────────────────────────────────────────
section "Anonymisation"
apt_pkg tor          tor          # Tor anonymisation daemon
apt_pkg torsocks     torsocks     # transparently route any command through Tor
apt_pkg proxychains4 proxychains4 # chain multiple SOCKS/HTTP proxies
apt_pkg i2pd         i2pd         # I2P anonymous network daemon (lightweight C++ impl)
note "Tor SOCKS5 proxy: 127.0.0.1:9050 — route apps with 'torsocks <cmd>'"
note "I2P HTTP proxy: 127.0.0.1:4444 — for .i2p addresses and anonymous file sharing"
note "Your traffic is already tunnelled through the VPN — adding Tor gives a second layer."

# ── Steganography & covert channels ───────────────────────────────────────────
section "Covert Channels"
apt_pkg steghide   steghide   # hide messages inside JPEG/BMP/WAV/AU files
apt_pkg mat2       mat2       # strip metadata from files before sharing
note "steghide: embed a message — 'steghide embed -cf image.jpg -sf secret.txt'"
note "mat2: sanitise files before sending — 'mat2 document.pdf'"

# ══════════════════════════════════════════════════════════════════════════════
#  SUMMARY
# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo -e "  ${BOLD}──────────────────────────────────────────${NC}"

if $LIST_ONLY; then
    echo -e "  Run ${BOLD}comms-setup${NC} to install all tools above."
else
    echo -e "  ${C_GREEN}${BOLD}Installed${NC}: $INSTALLED   ${C_YELLOW}Skipped${NC}: $SKIPPED   ${C_RED}Failed${NC}: $FAILED"
    echo ""
    echo -e "  Run ${BOLD}source ~/.bashrc${NC} to load the updated PATH."
    echo ""
    echo -e "  ${BOLD}Next steps:${NC}"
    echo ""
    printf '  %-38s %s\n' \
        "comms-setup --configure"           "generate GPG key, write SMTP/IMAP config templates" \
        "thunderbird"                       "launch GUI email client" \
        "gpg --full-generate-key"           "create a GPG keypair manually" \
        "gpg --armor --export YOU@DOMAIN"   "export your public key to share" \
        "sudo service tor start"            "start the Tor daemon" \
        "torsocks <any-command>"            "route that command through Tor" \
        "signal-cli -u +1XXX register"      "register Signal with your phone number" \
        "profanity"                         "start XMPP client (OMEMO encryption)" \
        "gajim"                             "launch GUI XMPP client" \
        "matrix-commander --help"           "Matrix CLI — needs homeserver + token" \
        "keepassxc"                         "open password manager" \
        "age-keygen -o $COMMS/keys/age.key" "generate an age encryption key" \
        "steghide embed -cf img.jpg"        "hide a message in an image" \
        "mat2 <file>"                       "strip all metadata before sharing"
    echo ""
    note "Custom domain email: run 'comms-setup --configure' for SMTP/IMAP config templates."
    note "For fully anonymous email, use ProtonMail (.onion: protonmailrmez3lotccipshtkleegetolb73fuirgj7r4o4vfu7ozyd.onion)"
    note "Or: Riseup (riseup.net) — provides free .onion-accessible email for activists."
fi
echo ""
