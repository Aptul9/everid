import argparse
from pathlib import Path

ROUTE = '  { name: "tls"; host: "127.0.0.1"; port: "4451"; sni_hostnames: [ "id.everbright.it" ]; },'


def updated_config(content):
    existing = [line for line in content.splitlines() if '"id.everbright.it"' in line]
    if existing:
        if len(existing) != 1 or existing[0].strip() != ROUTE.strip():
            raise ValueError("Existing EverID routing differs; no configuration changed")
        return content
    if '"4451"' in content:
        raise ValueError("Port 4451 already routed elsewhere; no configuration changed")
    if content.count("protocols: (") != 1:
        raise ValueError("Unexpected sslh configuration; no configuration changed")
    return content.replace("protocols: (", "protocols: (\n" + ROUTE, 1)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    args.destination.write_text(updated_config(args.source.read_text()))
