#!/usr/bin/env bash
# osint-setup — install a comprehensive OSINT toolkit inside the jumpbox desktop
#
# Run once after the desktop starts. Safe to re-run; skips already-installed tools.
#
# Binary tools go to /config/bin — persistent across container recreations.
# APT and pip packages live in the container layer; re-run after force-recreate.
#
# Usage:
#   osint-setup           install everything
#   osint-setup --list    show what would be installed without installing
#   osint-setup --guide   show full tool usage reference
#   osint-setup --guide <tool>  show reference for one tool (e.g. --guide nmap)

set -uo pipefail

# ── Colours ───────────────────────────────────────────────────────────────────
BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'
C_CYAN='\033[0;36m'; C_GREEN='\033[0;32m'; C_YELLOW='\033[1;33m'; C_RED='\033[0;31m'

# ── Paths (persistent across container recreation) ────────────────────────────
BIN="/config/bin"
REPOS="/config/osint"
VENV="/config/osint-venv"

# ── State ─────────────────────────────────────────────────────────────────────
LIST_ONLY=false
INSTALLED=0; SKIPPED=0; FAILED=0
[[ "${1:-}" == "--list" ]] && LIST_ONLY=true


# ── Guide mode: exits early after printing reference ──────────────────────────
if [[ "${1:-}" == "--guide" ]]; then
    GUIDE_FILTER="${2:-}"

    _h()   { echo ""; echo -e "  ${BOLD}${C_CYAN}━━  $*  ━━${NC}"; }
    _t()   { echo ""; echo -e "  ${BOLD}$1${NC}  ${DIM}$2${NC}"; }
    _e()   { printf "    ${C_GREEN}%-46s${NC} %s\n" "$1" "$2"; }
    _n()   { echo -e "    ${DIM}$*${NC}"; }
    # _show returns 0 (true) if this section should be printed.
    # Uses whole-word matching so "nmap" won't also show "asnmap".
    _show() { [[ -z "$GUIDE_FILTER" ]] || echo "$*" | grep -qiw "$GUIDE_FILTER"; }

    echo ""
    echo -e "  ${BOLD}╔══════════════════════════════════════════════╗${NC}"
    echo -e "  ${BOLD}║          OSINT Toolkit — Usage Guide         ║${NC}"
    echo -e "  ${BOLD}╚══════════════════════════════════════════════╝${NC}"
    [[ -n "$GUIDE_FILTER" ]] && echo -e "  ${C_YELLOW}Filter: $GUIDE_FILTER${NC}"

    # ──────────────────────────── NETWORK & PORT SCANNING ─────────────────────
    if _show "nmap"; then
        _h "nmap — Network Mapper"
        _n "Port scanner, service/version detection, OS fingerprinting, scripted probes."
        _t "Basic scans" ""
        _e "nmap <target>"                                "fast scan of top 1000 ports"
        _e "nmap -p- <target>"                            "all 65535 ports (slower)"
        _e "nmap -p 22,80,443,8080 <target>"              "specific ports only"
        _e "nmap -sV <target>"                            "detect service versions"
        _e "nmap -O <target>"                             "OS fingerprinting (needs root)"
        _t "Speed presets" ""
        _e "nmap -T4 <target>"                            "faster scan (-T0 paranoid → -T5 insane)"
        _t "Script engine (NSE)" ""
        _e "nmap -sC <target>"                            "run default safe scripts"
        _e "nmap --script vuln <target>"                  "run vulnerability scripts"
        _e "nmap --script smb-vuln* <target>"             "SMB vulnerability checks"
        _e "nmap --script http-title <target>"            "grab HTTP page titles"
        _t "Scan types" ""
        _e "nmap -sS <target>"                            "SYN (stealth) scan — needs root"
        _e "nmap -sU -p 53,161,500 <target>"              "UDP scan (slow, needs root)"
        _e "nmap -sn 192.168.1.0/24"                      "ping sweep — host discovery only"
        _t "Output" ""
        _e "nmap -oN scan.txt <target>"                   "normal text output"
        _e "nmap -oX scan.xml <target>"                   "XML output"
        _e "nmap -oA scan <target>"                       "all formats (txt, xml, gnmap)"
        _t "Common full invocations" ""
        _e "nmap -sV -sC -T4 -oA scan <target>"          "versioned + default scripts"
        _e "sudo nmap -sS -sV -O -p- -T4 <target>"       "full stealth + OS + versions"
    fi

    if _show "masscan"; then
        _h "masscan — Fast Internet-Scale Port Scanner"
        _n "Much faster than nmap for wide/CIDR sweeps. Pair with nmap for service detail."
        _t "Usage" ""
        _e "masscan -p80,443 10.0.0.0/8"                 "scan a /8 on two ports"
        _e "masscan -p1-65535 <target> --rate=1000"       "full port scan, 1000 pkt/s"
        _e "masscan -p80,443 <range> -oL out.txt"         "save results as list"
        _n "Rate: --rate=10000 is safe locally; lower for external targets."
        _n "Pipe masscan output into nmap -sV for service fingerprinting."
    fi

    if _show "nc netcat"; then
        _h "nc — Netcat"
        _n "TCP/UDP connections, banner grabbing, port probing, file transfers."
        _t "Usage" ""
        _e "nc -zv <host> 22-443"                         "scan port range (z=scan, v=verbose)"
        _e "nc <host> 80"                                  "open raw TCP connection"
        _e "nc -l 4444"                                    "listen on port 4444"
        _e "nc -lu 5353"                                   "listen on UDP port"
        _e "printf 'HEAD / HTTP/1.0\r\n\r\n' | nc <host> 80" "manual HTTP banner grab"
    fi

    if _show "dig dns"; then
        _h "dig — DNS Lookup"
        _n "Query DNS records. More flexible than nslookup."
        _t "Usage" ""
        _e "dig example.com"                               "A record (default)"
        _e "dig example.com MX"                            "mail server records"
        _e "dig example.com NS"                            "name servers"
        _e "dig example.com TXT"                           "TXT records (SPF, DKIM, etc.)"
        _e "dig example.com ANY"                           "all record types"
        _e "dig -x 8.8.8.8"                                "reverse PTR lookup"
        _e "dig @8.8.8.8 example.com"                      "query a specific DNS server"
        _e "dig +short example.com"                        "clean output, IP only"
        _e "dig axfr example.com @ns1.example.com"         "attempt zone transfer"
    fi

    if _show "whois"; then
        _h "whois — Domain & IP Registration Lookup"
        _t "Usage" ""
        _e "whois example.com"                             "domain registration / registrar"
        _e "whois 8.8.8.8"                                 "IP WHOIS / ASN"
    fi

    # ──────────────────────────── WEB SCANNING ────────────────────────────────
    if _show "nikto"; then
        _h "nikto — Web Server Vulnerability Scanner"
        _n "Checks for outdated software, dangerous files, misconfigurations."
        _t "Usage" ""
        _e "nikto -h http://target.com"                    "basic scan"
        _e "nikto -h https://target.com -ssl"              "HTTPS target"
        _e "nikto -h target.com -p 8080"                   "non-standard port"
        _e "nikto -h target.com -o report.html -Format htm" "save HTML report"
        _e "nikto -h target.com -Tuning 9"                 "SQL injection checks only"
        _n "Tuning codes: 1=Interesting 2=Misconfig 4=InfoDisclose 9=SQLi"
    fi

    if _show "dirb"; then
        _h "dirb — Web Directory Brute Force"
        _n "Discovers hidden paths by guessing from a wordlist."
        _t "Usage" ""
        _e "dirb http://target.com"                        "default wordlist scan"
        _e "dirb http://target.com /usr/share/wordlists/dirb/big.txt" "bigger wordlist"
        _e "dirb http://target.com -X .php,.html,.txt"     "append extensions"
        _e "dirb http://target.com -o out.txt"             "save output"
        _e "dirb http://target.com -z 100"                 "add 100ms delay (stealth)"
        _n "See also: gobuster (faster, more modes)."
    fi

    if _show "gobuster"; then
        _h "gobuster — Directory / DNS / VHost Brute Force"
        _n "Faster than dirb; supports dir, dns, vhost, and fuzz modes."
        _t "Directory mode" ""
        _e "gobuster dir -u http://target.com -w /usr/share/wordlists/dirb/common.txt" "basic dir scan"
        _e "gobuster dir -u http://target.com -w wordlist.txt -x php,html,txt" "add extensions"
        _e "gobuster dir -u http://target.com -w wordlist.txt -t 50" "50 threads"
        _e "gobuster dir -u http://target.com -w wordlist.txt -o results.txt" "save output"
        _t "DNS subdomain mode" ""
        _e "gobuster dns -d example.com -w subdomains.txt"  "brute-force subdomains"
        _e "gobuster dns -d example.com -w subdomains.txt -i" "show IPs alongside"
        _t "VHost mode" ""
        _e "gobuster vhost -u http://target.com -w vhosts.txt" "virtual host brute force"
        _n "Wordlists: /usr/share/wordlists/dirb/common.txt, big.txt, dirbuster/medium.txt"
    fi

    if _show "sqlmap"; then
        _h "sqlmap — Automated SQL Injection Testing"
        _n "Detects and exploits SQL injection in web parameters."
        _t "Usage" ""
        _e "sqlmap -u 'http://target.com/page?id=1'"       "basic GET parameter test"
        _e "sqlmap -u 'http://target.com/login' --data='user=a&pass=b'" "POST form test"
        _e "sqlmap -u 'http://target.com/?id=1' --dbs"     "list databases"
        _e "sqlmap -u URL -D dbname --tables"              "list tables in a database"
        _e "sqlmap -u URL -D db -T users --dump"           "dump a table"
        _e "sqlmap -u URL --level=5 --risk=3"              "maximum detection coverage"
        _e "sqlmap -u URL --batch"                         "auto-answer all prompts"
        _e "sqlmap -u URL --tor --tor-type=SOCKS5"         "route through Tor"
        _n "Only use against targets you have permission to test."
    fi

    if _show "whatweb"; then
        _h "whatweb — Web Technology Fingerprinting"
        _n "Identifies CMS, frameworks, server software, analytics, JS libraries."
        _t "Usage" ""
        _e "whatweb http://target.com"                     "basic fingerprint"
        _e "whatweb -v http://target.com"                  "verbose output"
        _e "whatweb -a 3 http://target.com"                "aggression level 3 (more probes)"
        _e "whatweb -i hosts.txt"                          "scan a list of targets"
        _e "whatweb --log-json=out.json http://target.com" "JSON output"
    fi

    if _show "wafw00f waf"; then
        _h "wafw00f — WAF Detection"
        _n "Identifies which Web Application Firewall (if any) protects a site."
        _t "Usage" ""
        _e "wafw00f https://target.com"                    "detect WAF"
        _e "wafw00f -a https://target.com"                 "try all WAF fingerprints"
        _e "wafw00f -i hosts.txt -o out.csv"               "scan list, save CSV"
        _e "wafw00f -l"                                    "list all detectable WAFs"
    fi

    # ──────────────────────────── SUBDOMAIN & DNS ─────────────────────────────
    if _show "subfinder subdomain"; then
        _h "subfinder — Passive Subdomain Enumeration"
        _n "Queries passive sources (crt.sh, virustotal, etc.) — no active probing."
        _t "Usage" ""
        _e "subfinder -d example.com"                      "find subdomains passively"
        _e "subfinder -d example.com -o subs.txt"          "save to file"
        _e "subfinder -dL domains.txt -o subs.txt"         "multiple domains from file"
        _e "subfinder -d example.com -silent"              "clean output for piping"
        _e "subfinder -d example.com | httpx -silent"      "probe which subdomains are live"
        _n "Pair with amass for active enumeration and dnsx for bulk resolution."
    fi

    if _show "amass"; then
        _h "amass — Attack Surface Mapping"
        _n "Active + passive subdomain enum, ASN/CIDR discovery, graph visualisation."
        _t "Enumeration" ""
        _e "amass enum -d example.com"                     "passive enumeration"
        _e "amass enum -active -d example.com"             "active DNS probing"
        _e "amass enum -d example.com -o subs.txt"         "save output"
        _t "ASN / IP intelligence" ""
        _e "amass intel -org 'Company Name'"               "find ASNs by organisation name"
        _e "amass intel -asn 13335"                        "CIDRs owned by an ASN"
        _e "amass intel -cidr 104.16.0.0/13"               "reverse-lookup a CIDR"
        _t "Database / Visualisation" ""
        _e "amass db -d example.com -show"                 "show results from past scans"
        _e "amass viz -d example.com -d3 graph.html"       "generate D3 network graph"
    fi

    if _show "dnsx dns"; then
        _h "dnsx — Fast Bulk DNS Resolver"
        _n "Resolve and filter large lists of hostnames at scale."
        _t "Usage" ""
        _e "dnsx -l subs.txt"                              "resolve all hostnames in list"
        _e "dnsx -l subs.txt -a -resp"                     "A records + show responses"
        _e "dnsx -l subs.txt -cname -resp"                 "follow CNAMEs"
        _e "dnsx -l subs.txt -mx -resp"                    "MX records"
        _e "echo example.com | dnsx -a -resp -silent"      "pipe single domain"
        _e "subfinder -d example.com -silent | dnsx -a -resp" "passive enum → bulk resolve"
    fi

    if _show "fierce dns"; then
        _h "fierce — DNS Reconnaissance"
        _n "Attempts zone transfers, brute-forces subdomains, maps DNS structure."
        _t "Usage" ""
        _e "fierce --domain example.com"                   "full DNS recon"
        _e "fierce --domain example.com --subdomains admin mail vpn" "specific names"
        _e "fierce --domain example.com --wordlist /usr/share/fierce/hosts.txt" "custom wordlist"
        _e "fierce --domain example.com --dns-servers 8.8.8.8" "use specific resolver"
    fi

    # ──────────────────────────── HTTP PROBING ────────────────────────────────
    if _show "httpx http"; then
        _h "httpx — HTTP Probing & Fingerprinting"
        _n "Probe lists of hosts for live HTTP services, titles, status codes, tech stack."
        _t "Usage" ""
        _e "httpx -l hosts.txt"                            "probe all hosts"
        _e "httpx -l hosts.txt -status-code -title"        "show status code and page title"
        _e "httpx -l hosts.txt -tech-detect"               "detect technologies (Wappalyzer)"
        _e "httpx -l hosts.txt -follow-redirects"          "follow HTTP redirects"
        _e "httpx -l hosts.txt -mc 200,301"                "match specific status codes"
        _e "httpx -l hosts.txt -o live.txt"                "save live hosts"
        _e "cat subs.txt | httpx -silent -status-code"     "pipe input"
        _t "Single target" ""
        _e "httpx -u https://target.com -title -tech-detect -status-code" "full fingerprint"
    fi

    if _show "katana crawl crawler"; then
        _h "katana — Web Crawler"
        _n "Crawls web apps to discover endpoints, forms, parameters, and JS files."
        _t "Usage" ""
        _e "katana -u https://target.com"                  "basic crawl"
        _e "katana -u https://target.com -d 3"             "crawl to depth 3"
        _e "katana -u https://target.com -jc"              "parse JavaScript for endpoints"
        _e "katana -u https://target.com -ef png,jpg,css"  "exclude file extensions"
        _e "katana -u https://target.com -o endpoints.txt" "save discovered endpoints"
        _e "katana -list hosts.txt -d 2 -o all.txt"        "crawl multiple targets"
    fi

    if _show "gau url"; then
        _h "gau — Fetch All Known URLs"
        _n "Pulls historical URLs from Wayback Machine, Common Crawl, OTX, URLScan."
        _t "Usage" ""
        _e "gau example.com"                               "all known URLs for domain"
        _e "gau example.com --o urls.txt"                  "save to file"
        _e "gau example.com --subs"                        "include subdomains"
        _e "gau example.com --blacklist png,jpg,gif"       "exclude image extensions"
        _e "gau example.com | grep '?'"                    "URLs with parameters only"
        _e "gau example.com | grep '\\.php'"               "PHP endpoints only"
    fi

    if _show "waybackurls wayback"; then
        _h "waybackurls — Wayback Machine URL Fetcher"
        _t "Usage" ""
        _e "echo example.com | waybackurls"                "all archived URLs"
        _e "echo example.com | waybackurls | grep '?'"     "parameterised URLs only"
        _e "cat domains.txt | waybackurls -no-subs"        "exclude subdomains"
        _e "echo example.com | waybackurls | grep '\\.js\\b'" "JavaScript files"
    fi

    # ──────────────────────────── VULNERABILITY SCANNING ──────────────────────
    if _show "nuclei vuln"; then
        _h "nuclei — Template-Based Vulnerability Scanner"
        _n "Runs community templates: thousands of checks for CVEs, misconfigs, exposures."
        _t "Usage" ""
        _e "nuclei -u https://target.com"                  "all default templates"
        _e "nuclei -u https://target.com -t cves/"         "CVE checks only"
        _e "nuclei -u https://target.com -t exposures/"    "information exposure checks"
        _e "nuclei -u https://target.com -t misconfigurations/" "misconfiguration checks"
        _e "nuclei -u https://target.com -severity high,critical" "high/critical only"
        _e "nuclei -u https://target.com -tags wordpress"  "WordPress-specific checks"
        _e "nuclei -l targets.txt -o findings.txt"         "scan list, save results"
        _e "nuclei -update-templates"                      "update template library"
        _e "nuclei -tl"                                    "list all available templates"
        _n "Templates live in ~/nuclei-templates/ after first update."
    fi

    if _show "naabu port"; then
        _h "naabu — Fast Port Scanner"
        _n "ProjectDiscovery's SYN/CONNECT scanner; integrates cleanly with nmap."
        _t "Usage" ""
        _e "naabu -host target.com"                        "scan top 100 ports"
        _e "naabu -host target.com -p 1-65535"             "all ports"
        _e "naabu -host target.com -p 80,443,8080"         "specific ports"
        _e "naabu -list hosts.txt -p 80,443 -o open.txt"   "scan list, save open ports"
        _e "naabu -host target.com -nmap-cli 'nmap -sV'"   "pipe open ports to nmap"
    fi

    if _show "tlsx tls ssl cert"; then
        _h "tlsx — TLS Certificate Scanner"
        _n "Inspects TLS certs; SANs often reveal internal hostnames and infrastructure."
        _t "Usage" ""
        _e "tlsx -u target.com"                            "inspect TLS certificate"
        _e "tlsx -u target.com -san"                       "show Subject Alt Names (SANs)"
        _e "tlsx -u target.com -cn"                        "show Common Name only"
        _e "tlsx -l hosts.txt -san -silent"                "extract SANs from a host list"
        _e "tlsx -l hosts.txt -expired"                    "find expired certificates"
        _n "SANs often reveal internal hostnames and related infrastructure."
    fi

    if _show "cdncheck cdn"; then
        _h "cdncheck — CDN / Cloud Provider Detection"
        _t "Usage" ""
        _e "echo 104.16.0.1 | cdncheck"                    "check if IP is behind a CDN"
        _e "cat ips.txt | cdncheck"                        "check a list of IPs"
        _e "echo target.com | cdncheck -resp"              "show which CDN provider"
    fi

    if _show "asnmap asn"; then
        _h "asnmap — ASN to CIDR Mapping"
        _n "Converts ASN, organisation, or IP to the full list of owned CIDRs."
        _t "Usage" ""
        _e "asnmap -a AS13335"                             "all CIDRs for an ASN"
        _e "asnmap -org 'Google LLC'"                      "CIDRs for an organisation"
        _e "asnmap -i 8.8.8.8"                             "which ASN owns this IP"
        _e "asnmap -a AS13335 | dnsx -ptr"                 "reverse-DNS all IPs in ASN"
    fi

    if _show "interactsh oob ssrf"; then
        _h "interactsh-client — Out-of-Band Interaction Catcher"
        _n "Generates unique callback URLs for detecting blind SSRF, XXE, Log4Shell, etc."
        _t "Usage" ""
        _e "interactsh-client"                             "start listener, get callback URL"
        _e "interactsh-client -v"                         "verbose — show full request detail"
        _n "Any DNS/HTTP/SMTP interaction with the callback URL is logged instantly."
        _n "Use the callback URL inside payloads wherever the app makes outbound requests."
    fi

    # ──────────────────────────── EMAIL & DOMAIN OSINT ───────────────────────
    if _show "theharvester harvester email"; then
        _h "theHarvester — Email, Host & Name OSINT"
        _n "Aggregates email addresses, hostnames, IPs from search engines and databases."
        _t "Usage" ""
        _e "theHarvester -d example.com -b google"         "Google search"
        _e "theHarvester -d example.com -b bing"           "Bing search"
        _e "theHarvester -d example.com -b all"            "all available sources"
        _e "theHarvester -d example.com -b all -l 500"     "more results (limit 500)"
        _e "theHarvester -d example.com -b all -f report"  "save XML + HTML report"
        _n "Key sources: google, bing, linkedin, hunter, shodan, anubis, dnsdumpster"
    fi

    if _show "shodan"; then
        _h "shodan — Internet Device Search Engine"
        _n "Search Shodan's index of internet-connected devices, services, and banners."
        _t "Setup (required once)" ""
        _e "shodan init <YOUR_API_KEY>"                    "configure API key"
        _e "shodan info"                                   "show account info / credits"
        _t "Searching" ""
        _e "shodan search 'apache 2.4 country:US'"         "search with filters"
        _e "shodan search 'port:22 product:OpenSSH'"       "find SSH servers"
        _e "shodan search 'org:\"Cloudflare\"'"            "search by organisation"
        _e "shodan count 'port:3389'"                      "count exposed RDP hosts"
        _t "Host lookup" ""
        _e "shodan host 8.8.8.8"                           "full info for an IP"
        _e "shodan honeyscore 1.2.3.4"                     "likelihood of honeypot"
        _t "Download results" ""
        _e "shodan download results 'apache port:80'"      "download full result set"
        _e "shodan parse results.json.gz"                  "parse downloaded results"
        _n "Free API key at https://www.shodan.io — required for all searches."
    fi

    if _show "holehe email"; then
        _h "holehe — Email Account Presence Check"
        _n "Checks if an email is registered on 120+ websites without sending emails."
        _t "Usage" ""
        _e "holehe user@example.com"                       "check all supported sites"
        _e "holehe user@example.com --only-used"           "show only positive matches"
        _e "holehe user@example.com --csv out.csv"         "save results to CSV"
    fi

    if _show "h8mail breach credential"; then
        _h "h8mail — Leaked Credential Hunt"
        _n "Finds leaked credentials for an email via public breach databases."
        _t "Usage" ""
        _e "h8mail -t user@example.com"                    "search breach APIs"
        _e "h8mail -t user@example.com -bc config.ini"     "with API keys (HIBP, Snusbase)"
        _e "h8mail -t user@example.com -l local-breach.txt" "search a local breach file"
        _n "Most powerful with API keys for HaveIBeenPwned, Snusbase, or Breach.cc."
    fi

    # ──────────────────────────── USERNAME OSINT ──────────────────────────────
    if _show "sherlock username"; then
        _h "sherlock — Username Search Across 400+ Sites"
        _t "Usage" ""
        _e "sherlock username"                             "search all supported sites"
        _e "sherlock username --print-found"               "only print positive matches"
        _e "sherlock username --csv"                       "output as CSV"
        _e "sherlock username --timeout 10"                "per-site timeout (seconds)"
        _e "sherlock username --site twitter --site github" "specific sites only"
    fi

    if _show "maigret username profile"; then
        _h "maigret — Deep Username Profiler (3000+ sites)"
        _n "Finds accounts across 3000+ sites and builds a profile from public data."
        _t "Usage" ""
        _e "maigret username"                              "search all sites"
        _e "maigret username --html"                       "generate HTML report"
        _e "maigret username --pdf"                        "generate PDF report"
        _e "maigret username -n 50"                        "stop after 50 found accounts"
        _e "maigret username --site twitter --site github" "specific sites only"
        _n "Reports saved to ./reports/ by default."
    fi

    if _show "socialscan username email"; then
        _h "socialscan — Email / Username Availability Check"
        _n "Real-time availability check across major platforms."
        _t "Usage" ""
        _e "socialscan username"                           "check username availability"
        _e "socialscan user@email.com"                     "check email address"
        _e "socialscan user1 user2 user3"                  "check multiple at once"
    fi

    # ──────────────────────────── METADATA ────────────────────────────────────
    if _show "exiftool metadata"; then
        _h "exiftool — File Metadata Inspector"
        _n "Reads and writes metadata from images, PDFs, Office docs, audio, video."
        _t "Reading" ""
        _e "exiftool file.jpg"                             "show all metadata"
        _e "exiftool -Author -GPSLatitude file.jpg"        "specific fields only"
        _e "exiftool -r /path/to/dir"                      "recurse entire directory"
        _e "exiftool -csv *.jpg > meta.csv"                "export all to CSV"
        _t "Stripping / editing" ""
        _e "exiftool -all= file.jpg"                       "strip ALL metadata"
        _e "exiftool -Author='Anonymous' file.pdf"         "overwrite a specific field"
        _n "GPS coords in photos can reveal exact locations — strip before sharing."
    fi

    if _show "binwalk firmware"; then
        _h "binwalk — Firmware Analysis & Extraction"
        _t "Usage" ""
        _e "binwalk firmware.bin"                          "identify embedded files/data"
        _e "binwalk -e firmware.bin"                       "extract embedded files"
        _e "binwalk -A firmware.bin"                       "scan for executable code"
        _e "binwalk -E firmware.bin"                       "entropy analysis (find crypto)"
    fi

    if _show "foremost carve recover"; then
        _h "foremost — File Carving / Data Recovery"
        _n "Recovers files from disk images or raw data by scanning for file signatures."
        _t "Usage" ""
        _e "foremost -i disk.img -o output/"               "carve all supported types"
        _e "foremost -t jpg,pdf -i disk.img -o output/"    "specific file types only"
        _e "foremost -i /dev/sdb -o output/"               "carve directly from a device"
    fi

    # ──────────────────────────── ANONYMISATION ───────────────────────────────
    if _show "tor torsocks anon"; then
        _h "Tor / torsocks — Anonymous Network Routing"
        _t "Usage" ""
        _e "sudo service tor start"                        "start the Tor daemon"
        _e "sudo service tor status"                       "check Tor status"
        _e "torsocks curl https://check.torproject.org"    "verify Tor is routing traffic"
        _e "torsocks nmap -sT target.com"                  "nmap through Tor"
        _e "torsocks wget http://site.onion/"              "fetch a .onion resource"
        _n "Tor SOCKS5 proxy listens on 127.0.0.1:9050."
        _n "torsocks wraps any command to transparently route it through Tor."
    fi

    if _show "proxychains proxy"; then
        _h "proxychains4 — Proxy Chain Routing"
        _n "Routes tool traffic through a chain of SOCKS4/5 or HTTP proxies."
        _t "Setup" ""
        _e "sudo nano /etc/proxychains4.conf"              "add proxies to the chain"
        _n "Add lines like:  socks5 127.0.0.1 9050   (for Tor)"
        _t "Usage" ""
        _e "proxychains4 curl https://ipinfo.io"           "verify proxy routing"
        _e "proxychains4 nmap -sT -Pn target.com"          "nmap via proxy chain"
        _e "proxychains4 sqlmap -u 'http://target.com'"    "sqlmap via proxy chain"
    fi

    # ──────────────────────────── FRAMEWORKS ──────────────────────────────────
    if _show "recon-ng reconng framework"; then
        _h "recon-ng — Modular OSINT Framework (CLI)"
        _n "Module-based recon framework. Each module queries one specific data source."
        _t "Usage" ""
        _e "recon-ng"                                      "launch interactive console"
        _t "Inside the recon-ng console:" ""
        _e "workspaces create myproject"                   "create an isolated workspace"
        _e "db insert domains example.com"                 "seed a domain"
        _e "marketplace search"                            "browse available modules"
        _e "marketplace install recon/domains-hosts/hackertarget" "install a module"
        _e "modules load recon/domains-hosts/hackertarget" "load a module"
        _e "run"                                           "execute it"
        _e "show hosts"                                    "view collected hosts"
        _e "show contacts"                                 "view collected contacts/emails"
    fi

    if _show "spiderfoot spider framework"; then
        _h "spiderfoot — Automated OSINT Web UI"
        _n "Runs 200+ data-gathering modules and presents results as a dashboard."
        _t "Usage" ""
        _e "spiderfoot -l 0.0.0.0:5001"                   "start web UI on port 5001"
        _e "spiderfoot -l 127.0.0.1:5001"                 "local-only web UI"
        _n "Open http://localhost:5001 → New Scan → enter target → choose profile → Start."
        _n "Profiles: All (comprehensive), Passive Only, Investigate (balanced)."
    fi

    if _show "photon crawl"; then
        _h "photon — Web Crawler for OSINT"
        _n "Crawls a site and extracts URLs, emails, API keys, social links, files."
        _t "Usage" ""
        _e "photon -u https://target.com"                  "basic crawl"
        _e "photon -u https://target.com -l 3"             "crawl depth level 3"
        _e "photon -u https://target.com -t 50"            "50 threads"
        _e "photon -u https://target.com -o results/"      "save output to directory"
        _e "photon -u https://target.com --keys"           "extract API keys / secrets"
        _n "Output in results/: internal, external, fuzzable, endpoints, keys."
    fi

    # ──────────────────────────── UTILITY TOOLS ───────────────────────────────
    if _show "anew"; then
        _h "anew — Append Unique Lines"
        _n "Appends new lines to a file; prints only lines that were not already there."
        _t "Usage" ""
        _e "subfinder -d example.com | anew subs.txt"      "grow a subdomain list with new finds"
        _e "cat new.txt | anew master.txt"                 "deduplicated append"
    fi

    if _show "qsreplace fuzz"; then
        _h "qsreplace — Query String Value Replacer"
        _n "Replaces URL query parameter values in bulk — useful for fuzzing."
        _t "Usage" ""
        _e "cat urls.txt | qsreplace 'FUZZ'"               "replace all values with FUZZ"
        _e "cat urls.txt | qsreplace \"'>\""               "inject for reflected XSS testing"
        _e "gau example.com | grep '=' | qsreplace 'XSS'"  "historical params → XSS test"
    fi

    if _show "jq json"; then
        _h "jq — JSON Processor"
        _n "Parse and transform JSON output from tools and APIs."
        _t "Usage" ""
        _e "cat data.json | jq '.'"                        "pretty-print JSON"
        _e "cat data.json | jq '.users[].email'"           "extract a field from an array"
        _e "cat data.json | jq 'select(.status==200)'"     "filter by a condition"
        _e "cat data.json | jq -r '.[] | .ip + \":\" + .port'" "format as plain text"
        _e "curl -s https://api.example.com | jq '.data'"  "parse API response"
    fi

    # ──────────────────────────── PIPELINES ───────────────────────────────────
    if _show "pipelines workflow pipe chain"; then
        _h "Common OSINT Pipelines"
        _n "Chain tools together for complete end-to-end workflows."
        _t "Find subdomains → resolve → probe for live HTTP services" ""
        _e "subfinder -d example.com -silent | dnsx -a -silent | httpx -silent -status-code -title" ""
        _t "Find subdomains → port scan → service fingerprint" ""
        _e "subfinder -d example.com -silent | naabu -silent | nmap -sV -iL -" ""
        _t "Subdomain discovery via TLS certificate SANs" ""
        _e "subfinder -d example.com -silent | tlsx -san -silent | grep '\\.example\\.com'" ""
        _t "Live hosts → vulnerability scan (high/critical only)" ""
        _e "subfinder -d example.com -silent | httpx -silent | nuclei -severity high,critical" ""
        _t "Crawl site → scan all discovered endpoints" ""
        _e "katana -u https://example.com -silent | nuclei -silent" ""
        _t "Harvest historical URLs → find parameters → test for SQLi" ""
        _e "gau example.com | grep '=' | qsreplace \"'\" | sqlmap -m - --batch" ""
        _t "Grow a subdomain list incrementally (re-run safe)" ""
        _e "subfinder -d example.com -silent | anew subs.txt" ""
        _t "Full subdomain enum → live probe → save for nuclei" ""
        _e "subfinder -d example.com -silent | dnsx -a -silent | httpx -silent -o live.txt && nuclei -l live.txt" ""
        _t "Map an organisation's full IP footprint" ""
        _e "asnmap -org 'Target Inc' | dnsx -ptr -resp -silent" ""
        _t "Shodan results → nmap service detail" ""
        _e "shodan search 'org:\"Target\" port:22' --fields ip_str | nmap -sV -iL -" ""
    fi

    echo ""
    echo -e "  ${DIM}──────────────────────────────────────────${NC}"
    echo -e "  Run ${BOLD}osint-setup --guide <tool>${NC} to filter to one tool."
    echo -e "  Run ${BOLD}osint-setup --guide pipelines${NC} for end-to-end workflows."
    echo ""
    exit 0
fi

# ── Logging ───────────────────────────────────────────────────────────────────
say()    { echo -e "  ${C_CYAN}▸${NC} $*"; }
ok()     { echo -e "  ${C_GREEN}✓${NC} ${BOLD}$1${NC}${2:+  ${DIM}$2${NC}}"; (( INSTALLED++ )) || true; }
skip()   { echo -e "  ${C_YELLOW}·${NC} ${DIM}$1 — already installed${NC}"; (( SKIPPED++ )) || true; }
fail()   { echo -e "  ${C_RED}✗${NC} $1${2:+ — $2}"; (( FAILED++ )) || true; }
section(){ echo ""; echo -e "  ${BOLD}${C_CYAN}── $* ──${NC}"; }

# ── Bootstrap ─────────────────────────────────────────────────────────────────
bootstrap() {
    mkdir -p "$BIN" "$REPOS"
    # Add persistent bin and venv to PATH (survives container restarts via /config volume)
    if ! grep -q 'config/bin' ~/.bashrc 2>/dev/null; then
        printf '\n# OSINT toolkit\nexport PATH="/config/bin:/config/osint-venv/bin:$PATH"\n' >> ~/.bashrc
    elif ! grep -q 'osint-venv' ~/.bashrc 2>/dev/null; then
        sed -i 's|/config/bin|/config/bin:/config/osint-venv/bin|' ~/.bashrc
    fi
    export PATH="$BIN:$VENV/bin:$PATH"

    # Suppress PackageKit D-Bus errors — it is not running in the container.
    export DEBIAN_FRONTEND=noninteractive
    sudo rm -f /etc/apt/apt.conf.d/20packagekit 2>/dev/null || true

    # Install uv — Rust-based Python manager that bundles Python 3.12.
    # Ubuntu 25.04 ships Python 3.14 which has no wheels for most OSINT packages.
    # uv manages its own Python so we bypass the system version entirely.
    if [[ ! -x "$BIN/uv" ]]; then
        say "downloading uv (Python 3.12 package manager)..."
        local uv_url
        uv_url=$(curl -sf --max-time 10 \
            'https://api.github.com/repos/astral-sh/uv/releases/latest' \
            | python3 -c "
import sys, json, re
data = json.load(sys.stdin)
for a in data.get('assets', []):
    if re.search(r'uv-x86_64-unknown-linux-musl\.tar\.gz$', a['name']):
        print(a['browser_download_url']); break
" 2>/dev/null) || true

        if [[ -n "$uv_url" ]]; then
            local tmp; tmp=$(mktemp -d)
            if curl -sfL --max-time 90 "$uv_url" -o "$tmp/uv.tar.gz" 2>/dev/null && \
               tar -xzf "$tmp/uv.tar.gz" -C "$tmp" 2>/dev/null; then
                local uv_bin
                uv_bin=$(find "$tmp" -name "uv" -type f | head -1)
                if [[ -n "$uv_bin" ]]; then
                    cp "$uv_bin" "$BIN/uv"
                    chmod +x "$BIN/uv"
                    echo -e "  ${C_GREEN}✓${NC} uv installed"
                else
                    fail "uv" "binary not found in archive"
                fi
            else
                fail "uv" "download failed"
            fi
            rm -rf "$tmp"
        else
            fail "uv" "could not resolve download URL"
        fi
    fi

    # Store uv-managed Python in /config so it survives container force-recreate.
    # Without this, Python 3.12 lives in the container layer and venv symlinks break.
    export UV_PYTHON_INSTALL_DIR="/config/uv-python"

    # Detect and remove broken venv (directory exists but Python binary is gone —
    # happens after force-recreate if UV_PYTHON_INSTALL_DIR was not set previously).
    if [[ -d "$VENV" ]] && ! "$VENV/bin/python" --version &>/dev/null 2>&1; then
        say "removing broken venv (will recreate)..."
        rm -rf "$VENV"
    fi

    # Create Python 3.12 venv for all pip-installed OSINT tools
    if [[ ! -d "$VENV" ]]; then
        if [[ -x "$BIN/uv" ]]; then
            say "creating Python 3.12 venv at $VENV..."
            "$BIN/uv" venv --python 3.12 "$VENV" >/dev/null 2>&1 \
                && echo -e "  ${C_GREEN}✓${NC} Python 3.12 venv ready" \
                || fail "venv" "uv venv creation failed — check: $BIN/uv venv --python 3.12 $VENV"
        else
            fail "venv" "uv not available — pip tools will likely fail"
        fi
    fi
}

# ── Helpers ───────────────────────────────────────────────────────────────────

apt_pkg() {
    # apt_pkg <package> [<binary-to-check>]
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
    # pip_pkg <package> [<binary-to-check>]
    # Installs into /config/osint-venv (Python 3.12, managed by uv).
    # Uses 'uv pip install' directly — does not require pip to be in the venv.
    local pkg="$1" check="${2:-$1}"
    $LIST_ONLY && { echo "  [pip]  $pkg"; return; }
    command -v "$check" &>/dev/null && { skip "$check"; return; }
    say "pip: $pkg"
    if [[ ! -x "$BIN/uv" ]] || [[ ! -d "$VENV" ]]; then
        fail "$pkg" "Python venv not ready — re-run osint-setup"
        return
    fi
    if UV_PYTHON_INSTALL_DIR="/config/uv-python" \
       "$BIN/uv" pip install -q --python "$VENV" \
       --no-cache-dir "$pkg" >/dev/null 2>&1; then
        ok "$check"
    else
        fail "$pkg" "pip install failed"
    fi
}

# Download a pre-compiled binary from GitHub releases.
# gh_bin <name> <owner/repo> <asset-regex>
# The regex is matched against asset filenames (grep -E).
gh_bin() {
    local name="$1" repo="$2" pattern="$3"
    $LIST_ONLY && { echo "  [bin]  $name  (github.com/$repo)"; return; }
    [[ -x "$BIN/$name" ]] && { skip "$name"; return; }
    say "downloading: $name"

    local api_url="https://api.github.com/repos/$repo/releases/latest"
    local download_url
    download_url=$(curl -sf --max-time 10 "$api_url" 2>/dev/null \
        | python3 -c "
import sys, json, re
try:
    data = json.load(sys.stdin)
    pat = r'$pattern'
    for a in data.get('assets', []):
        if re.search(pat, a['name'], re.IGNORECASE):
            print(a['browser_download_url']); break
except: pass
" 2>/dev/null) || true

    if [[ -z "$download_url" ]]; then
        fail "$name" "no matching release asset (pattern: $pattern)"
        return
    fi

    local tmp; tmp=$(mktemp -d)
    local ext="${download_url##*.}"

    if ! curl -sfL --max-time 120 "$download_url" -o "$tmp/pkg.$ext" 2>/dev/null; then
        fail "$name" "download failed"
        rm -rf "$tmp"; return
    fi

    mkdir -p "$tmp/out"
    case "$ext" in
        zip) unzip -q "$tmp/pkg.$ext" -d "$tmp/out" 2>/dev/null ;;
        gz)  tar -xzf "$tmp/pkg.$ext" -C "$tmp/out" 2>/dev/null ;;
        *)   cp "$tmp/pkg.$ext" "$tmp/out/$name" ;;
    esac

    local found
    found=$(find "$tmp/out" -type f -name "$name" | head -1)
    if [[ -n "$found" ]]; then
        cp "$found" "$BIN/$name"
        chmod +x "$BIN/$name"
        ok "$name"
    else
        fail "$name" "binary not found in archive"
    fi
    rm -rf "$tmp"
}

# Clone a git repo and optionally install its pip requirements.
# git_repo <name> <repo-url> [<requirements-file>] [<entrypoint-script>]
git_repo() {
    local name="$1" url="$2" reqs="${3:-}" entry="${4:-}"
    $LIST_ONLY && { echo "  [git]  $name  ($url)"; return; }
    if [[ -d "$REPOS/$name" ]]; then
        skip "$name"; return
    fi
    say "cloning: $name"
    if git clone -q --depth=1 "$url" "$REPOS/$name" 2>/dev/null; then
        if [[ -n "$reqs" && -f "$REPOS/$name/$reqs" ]]; then
            if [[ -x "$BIN/uv" ]] && [[ -d "$VENV" ]]; then
                UV_PYTHON_INSTALL_DIR="/config/uv-python" \
                "$BIN/uv" pip install -q --python "$VENV" \
                    --no-cache-dir -r "$REPOS/$name/$reqs" >/dev/null 2>&1 || true
            elif [[ -x "$VENV/bin/pip" ]]; then
                "$VENV/bin/pip" install -q --no-cache-dir --prefer-binary \
                    -r "$REPOS/$name/$reqs" >/dev/null 2>&1 || true
            fi
        fi
        if [[ -n "$entry" && -f "$REPOS/$name/$entry" ]]; then
            chmod +x "$REPOS/$name/$entry"
            # Write a wrapper that calls the venv Python rather than a bare symlink.
            # The repo scripts have '#!/usr/bin/env python3' which resolves to the
            # system Python 3.14 — but their deps were installed into the 3.12 venv.
            if [[ -d "$VENV" ]]; then
                printf '#!/usr/bin/env bash\nexec "%s/bin/python" "%s/%s" "$@"\n' \
                    "$VENV" "$REPOS/$name" "$entry" > "$BIN/$name"
                chmod +x "$BIN/$name"
            else
                ln -sf "$REPOS/$name/$entry" "$BIN/$name"
            fi
        fi
        ok "$name"
    else
        fail "$name" "git clone failed"
    fi
}

# ── Banner ────────────────────────────────────────────────────────────────────
echo ""
echo -e "  ${BOLD}╔══════════════════════════════════════╗${NC}"
echo -e "  ${BOLD}║        OSINT Toolkit  Setup          ║${NC}"
echo -e "  ${BOLD}╚══════════════════════════════════════╝${NC}"
echo ""
if $LIST_ONLY; then
    echo -e "  ${C_YELLOW}Listing tools only — nothing will be installed.${NC}"
else
    echo -e "  Persistent binaries : ${C_CYAN}$BIN${NC}"
    echo -e "  Git repos           : ${C_CYAN}$REPOS${NC}"
fi
echo ""

$LIST_ONLY || bootstrap
$LIST_ONLY || { echo "  Updating package lists..."; sudo apt-get update -qq; }

# ══════════════════════════════════════════════════════════════════════════════
#  SYSTEM PACKAGES (apt)
# ══════════════════════════════════════════════════════════════════════════════
section "Network & Port Scanning"
apt_pkg nmap            nmap        # host discovery, port/service/OS fingerprinting
apt_pkg masscan         masscan     # fastest internet-scale port scanner
apt_pkg netcat-openbsd  nc          # TCP/UDP connections, banner grabbing
apt_pkg traceroute      traceroute  # network path tracing
apt_pkg dnsutils        dig         # DNS queries (dig, nslookup, host)
apt_pkg whois           whois       # domain/IP registration lookup
apt_pkg iputils-ping    ping        # ICMP reachability

section "Web Scanning"
apt_pkg nikto           nikto       # web server vulnerability scanner
apt_pkg dirb            dirb        # web content/directory brute force
apt_pkg sqlmap          sqlmap      # automated SQL injection testing
apt_pkg whatweb         whatweb     # web technology fingerprinting

section "Files & Metadata"
apt_pkg libimage-exiftool-perl  exiftool  # read/write EXIF metadata from any file type
apt_pkg binwalk         binwalk     # firmware analysis and extraction
apt_pkg foremost        foremost    # file carving / data recovery

section "Anonymisation"
apt_pkg tor             tor         # Tor anonymisation network daemon
apt_pkg torsocks        torsocks    # transparently route tools through Tor
apt_pkg proxychains4    proxychains4 # chain multiple proxies (HTTP/SOCKS)

section "Utilities"
apt_pkg jq              jq          # command-line JSON processor
apt_pkg git             git         # version control (needed for repo installs)
apt_pkg unzip           unzip       # archive extraction (needed for binary installs)
apt_pkg curl            curl        # HTTP client
apt_pkg wget            wget        # file downloader
apt_pkg python3-pip     pip3        # pip for Python tools
apt_pkg python3-yaml    ""          # pre-compiled PyYAML (Python 3.14 compat)

# ══════════════════════════════════════════════════════════════════════════════
#  PYTHON TOOLS (pip)
# ══════════════════════════════════════════════════════════════════════════════
section "Email & Domain Intelligence"
pip_pkg theHarvester    theHarvester  # harvest emails, hosts, IPs from public sources
pip_pkg shodan          shodan        # Shodan CLI — search internet-connected devices
pip_pkg holehe          holehe        # check if an email is registered on 120+ websites
pip_pkg h8mail          h8mail        # email breach hunting via public breach APIs

section "Username & Profile OSINT"
pip_pkg sherlock-project  sherlock  # find a username across 400+ social networks
pip_pkg maigret           maigret   # build a profile from a username across 3000+ sites
pip_pkg socialscan        socialscan # check username/email availability in real time

section "Web & DNS"
pip_pkg wafw00f    wafw00f  # detect web application firewalls (WAF)
pip_pkg fierce     fierce   # DNS reconnaissance and subdomain scanner
pip_pkg photon     photon   # fast web crawler that extracts URLs, emails, files, keys

# ══════════════════════════════════════════════════════════════════════════════
#  PRE-COMPILED GO BINARIES (ProjectDiscovery suite)
# ══════════════════════════════════════════════════════════════════════════════
section "ProjectDiscovery Suite"
gh_bin subfinder  projectdiscovery/subfinder     'subfinder_.*_linux_amd64\.zip$'
gh_bin httpx      projectdiscovery/httpx          'httpx_.*_linux_amd64\.zip$'
gh_bin nuclei     projectdiscovery/nuclei         'nuclei_.*_linux_amd64\.zip$'
gh_bin dnsx       projectdiscovery/dnsx           'dnsx_.*_linux_amd64\.zip$'
gh_bin naabu      projectdiscovery/naabu          'naabu_.*_linux_amd64\.zip$'
gh_bin katana     projectdiscovery/katana         'katana_.*_linux_amd64\.zip$'
gh_bin interactsh-client  projectdiscovery/interactsh  'interactsh-client_.*_linux_amd64\.zip$'
gh_bin cdncheck   projectdiscovery/cdncheck       'cdncheck_.*_linux_amd64\.zip$'
gh_bin tlsx       projectdiscovery/tlsx           'tlsx_.*_linux_amd64\.zip$'
gh_bin asnmap     projectdiscovery/asnmap         'asnmap_.*_linux_amd64\.zip$'

# ══════════════════════════════════════════════════════════════════════════════
#  PRE-COMPILED GO BINARIES (other)
# ══════════════════════════════════════════════════════════════════════════════
section "Recon & Enumeration"
gh_bin gobuster     OJ/gobuster            'gobuster_Linux_x86_64\.tar\.gz$'
gh_bin amass        owasp-amass/amass      'amass_linux_amd64\.tar\.gz$'
gh_bin gau          lc/gau                 'gau_.*linux_amd64\.tar\.gz$'
gh_bin waybackurls  tomnomnom/waybackurls  'linux.amd64'
gh_bin anew         tomnomnom/anew         'linux.amd64'
gh_bin qsreplace    tomnomnom/qsreplace    'linux.amd64'

# ══════════════════════════════════════════════════════════════════════════════
#  GIT FRAMEWORKS
# ══════════════════════════════════════════════════════════════════════════════
section "Frameworks"
git_repo recon-ng   https://github.com/lanmaster53/recon-ng.git \
    REQUIREMENTS    recon-ng

git_repo spiderfoot https://github.com/smicallef/spiderfoot.git \
    requirements.txt  sf.py

git_repo metagoofil https://github.com/opsdisk/metagoofil.git \
    requirements.txt  metagoofil.py

# ══════════════════════════════════════════════════════════════════════════════
#  NUCLEI TEMPLATES
# ══════════════════════════════════════════════════════════════════════════════
if ! $LIST_ONLY && [[ -x "$BIN/nuclei" ]]; then
    section "Nuclei Templates"
    say "updating nuclei templates..."
    "$BIN/nuclei" -update-templates -silent 2>/dev/null && ok "nuclei-templates" \
        || fail "nuclei-templates" "run: nuclei -update-templates"
fi

# ══════════════════════════════════════════════════════════════════════════════
#  SUMMARY
# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo -e "  ${BOLD}──────────────────────────────────────${NC}"

if $LIST_ONLY; then
    echo -e "  Run ${BOLD}osint-setup${NC} to install all tools above."
else
    echo -e "  ${C_GREEN}${BOLD}Installed${NC}: $INSTALLED   ${C_YELLOW}Skipped${NC}: $SKIPPED   ${C_RED}Failed${NC}: $FAILED"
    echo ""
    echo -e "  Run ${BOLD}source ~/.bashrc${NC} (or open a new terminal) to load the full PATH."
    echo ""
    echo -e "  ${BOLD}Usage guide:${NC}"
    echo -e "  ${C_CYAN}osint-setup --guide${NC}               full reference for every tool"
    echo -e "  ${C_CYAN}osint-setup --guide nmap${NC}           reference for nmap specifically"
    echo -e "  ${C_CYAN}osint-setup --guide pipelines${NC}      example end-to-end workflows"
    echo ""
    echo -e "  ${BOLD}Quick cheat sheet:${NC}"
    printf '  %-32s %s\n' \
        "nmap -sV -sC -T4 <target>"       "port scan + default scripts" \
        "masscan -p1-65535 <target>"       "fast full-port scan" \
        "subfinder -d <domain> -silent"    "passive subdomain enum" \
        "amass enum -d <domain>"           "active attack-surface map" \
        "dnsx -l subs.txt -a -resp"        "resolve subdomain list" \
        "httpx -l hosts.txt -title"        "probe live HTTP services" \
        "nuclei -u <url> -severity high"   "vulnerability template scan" \
        "gobuster dir -u <url> -w list"    "directory brute force" \
        "nikto -h <url>"                   "web vulnerability scan" \
        "sqlmap -u '<url>?id=1' --dbs"     "SQL injection test" \
        "wafw00f <url>"                    "WAF detection" \
        "katana -u <url> -jc"              "crawl + parse JS endpoints" \
        "gau <domain> | grep '='"          "historical URLs with params" \
        "theHarvester -d <d> -b all"       "email / host OSINT" \
        "shodan search 'org:\"Target\"'"   "search Shodan" \
        "sherlock <username>"              "username across 400+ sites" \
        "holehe <email>"                   "email presence on 120+ sites" \
        "maigret <username> --html"        "deep profile + HTML report" \
        "exiftool <file>"                  "extract / strip file metadata" \
        "torsocks curl https://ipinfo.io"  "verify Tor routing" \
        "spiderfoot -l 0.0.0.0:5001"       "SpiderFoot web UI"
fi
echo ""
