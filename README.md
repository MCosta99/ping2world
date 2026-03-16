# ping2world

> This script was initally generated with Claude AI.

A Bash script that measures TCP connection latency to servers around the world (sourced from [meter.net](https://www.meter.net)) and ranks them from fastest to slowest. Useful for choosing the best VPS region, CDN PoP, or game server location.

## Demo

```
Fetching server list from meter.net...
Found 87 servers. Testing with 3 sample(s) each, 20 workers...

  Testing... 87 / 87

Rank   City                   Country              Provider               Host                           Latency
───────────────────────────────────────────────────────────────────────────────────────────────────────────────────
1      Frankfurt              Germany              Hetzner                fra.speedtest.hetzner.com:443  12 ms
2      Amsterdam              Netherlands          Serverius              ams.example.net:443            18 ms
3      Paris                  France               OVH                    par.example.net:443            24 ms
...
85     Sydney                 Australia            Telstra                syd.example.net:443            287 ms
86     Singapore              Singapore            Singtel                sin.example.net:443            312 ms
87     São Paulo              Brazil               Claro                  gru.example.net:443            TIMEOUT

Total servers tested: 87
```

## Requirements

| Tool | Install (Debian/Ubuntu) | Install (RHEL/CentOS) |
| ---- | ----------------------- | --------------------- |
| curl | `apt install curl`      | `yum install curl`    |
| jq   | `apt install jq`        | `yum install jq`      |
| awk  | pre-installed           | pre-installed         |

## Installation

```bash
curl -O https://raw.githubusercontent.com/YOUR_USERNAME/pingworld/main/ping2world.sh
chmod +x ping2world.sh
```

## Usage

```bash
./ping2world.sh [OPTIONS]
```

### Options

| Flag            | Description                              | Default        |
| --------------- | ---------------------------------------- | -------------- |
| `-n <samples>`  | Number of ping samples per server        | `3`            |
| `-t <seconds>`  | Connect timeout per request              | `5`            |
| `-p <workers>`  | Parallel workers                         | `20`           |
| `-o <file.csv>` | Save results to a CSV file               | _(disabled)_   |
| `-f`            | Force refresh server list (bypass cache) | _(uses cache)_ |
| `-h`            | Show help                                |                |

### Examples

```bash
# Basic run
./ping2world.sh

# More accurate results (5 samples, stricter timeout)
./ping2world.sh -n 5 -t 3

# Save to CSV
./ping2world.sh -o results.csv

# Force re-download the server list
./ping2world.sh -f

# Combined
./ping2world.sh -n 5 -p 30 -o results.csv
```

## Caching

The server list is cached at `~/.cache/pingworld_servers.json` and reused for **1 hour** to avoid hammering the API on repeated runs. The cache is refreshed automatically when it expires, or immediately with `-f`.

## Output colours

| Colour | Meaning             |
| ------ | ------------------- |
| Green  | < 50 ms             |
| Yellow | 50 – 149 ms         |
| Red    | ≥ 150 ms or TIMEOUT |

## CSV format

When using `-o`, the output file contains:

```
Rank,City,Country,Provider,Host,Latency_ms
1,"Frankfurt","Germany","Hetzner","fra.speedtest.hetzner.com:443",12
2,"Amsterdam","Netherlands","Serverius","ams.example.net:443",18
...
```
