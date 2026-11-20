"""Checks a running EverID stack against what the blueprint declares.

Logs in as the admin through the real authentication flow, then reads the API with that session.
Usage: EVERID_ADMIN_PASSWORD=... python ci/check_stack.py --url http://host:9000
"""
import argparse
import http.cookiejar
import json
import os
import sys
import time
import urllib.error
import urllib.request

APP_GROUPS = {"app-drive", "app-push", "app-fit", "app-flow", "app-calendar", "app-teams"}
OIDC_SLUGS = ("everdrive", "everpush", "everfit", "everflow")
# username or e-mail of the administrator, both accepted by the identification stage
LOGIN = os.environ.get("EVERID_ADMIN_LOGIN", "aptul")


PUBLIC_HOST = "id.everbright.it"


class Client:
    def __init__(self, base):
        self.base = base.rstrip("/")
        self.jar = http.cookiejar.CookieJar()
        self.opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(self.jar))

    def csrf(self):
        return next((c.value for c in self.jar if c.name == "authentik_csrf"), "")

    def json(self, path, body=None, public=False):
        data = json.dumps(body).encode() if body is not None else None
        headers = {"Content-Type": "application/json", "Accept": "application/json", "X-authentik-CSRF": self.csrf()}
        if public:
            # Headers Caddy sends in production: the issuer follows the public host and scheme.
            headers.update({"Host": PUBLIC_HOST, "X-Forwarded-Proto": "https"})
        req = urllib.request.Request(self.base + path, data=data, headers=headers)
        with self.opener.open(req, timeout=30) as response:
            return json.load(response)


def wait_ready(client):
    for _ in range(90):
        try:
            client.json("/application/o/everdrive/.well-known/openid-configuration")
            return
        except (urllib.error.URLError, OSError, ValueError):
            time.sleep(5)
    sys.exit("blueprint not applied: everdrive discovery never answered")


def login(client, password):
    path = "/api/v3/flows/executor/default-authentication-flow/?query="
    r = client.json(path)
    for _ in range(6):
        component = r.get("component")
        print("stage", component)
        if component == "ak-stage-identification":
            r = client.json(path, {"component": component, "uid_field": LOGIN, "password": password})
        elif component == "ak-stage-password":
            r = client.json(path, {"component": component, "password": password})
        else:
            break
    if r.get("component") != "xak-flow-redirect":
        sys.exit(f"login did not complete: {r.get('component')} {r.get('response_errors')}")
    print("login", LOGIN, "ok")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", required=True)
    args = parser.parse_args()
    client = Client(args.url)
    wait_ready(client)

    for slug in OIDC_SLUGS:
        issuer = client.json(f"/application/o/{slug}/.well-known/openid-configuration", public=True)["issuer"]
        assert issuer == f"https://{PUBLIC_HOST}/application/o/{slug}/", issuer
        print("discovery", slug, issuer)

    login(client, os.environ["EVERID_ADMIN_PASSWORD"])

    me = client.json("/api/v3/core/users/me/")["user"]
    groups = {g["name"] for g in me["groups"]}
    assert me["email"] == "aptul4ever@gmail.com", me["email"]
    assert APP_GROUPS | {"everid-admins"} <= groups, groups
    assert me["is_superuser"], "admin is not superuser"
    print("admin groups", sorted(groups))

    akadmin = client.json("/api/v3/core/users/?username=akadmin")["results"]
    assert akadmin and not akadmin[0]["is_active"], "akadmin still active"
    print("akadmin disabled")

    brand = client.json("/api/v3/core/brands/current/")
    assert brand["branding_title"] == "EverID", brand["branding_title"]
    print("brand", brand["branding_title"])

    apps = {a["slug"]: a for a in client.json("/api/v3/core/applications/?page_size=100&superuser_full_list=true")["results"]}
    for slug in OIDC_SLUGS + ("calendar", "teams"):
        assert slug in apps, f"application {slug} missing"
        bindings = client.json(f"/api/v3/policies/bindings/?target={apps[slug]['pk']}")["results"]
        bound = {b["group_obj"]["name"] for b in bindings if b.get("group_obj")}
        assert len(bound) == 1 and bound <= APP_GROUPS, (slug, bound)
        print("application", slug, "->", bound.pop())

    # The model default is an empty list: without explicit grant types every login is refused.
    for slug in OIDC_SLUGS:
        provider = client.json(f"/api/v3/providers/oauth2/{apps[slug]['provider']}/")
        assert "authorization_code" in provider["grant_types"], (slug, provider["grant_types"])
        print("provider", slug, "grant types", provider["grant_types"])

    outpost = client.json("/api/v3/outposts/instances/?managed__iexact=goauthentik.io/outposts/embedded")["results"][0]
    names = sorted(outpost["providers_obj"][i]["name"] for i in range(len(outpost["providers_obj"])))
    assert names == ["OE Copilot", "TeamsRelay"], names
    print("embedded outpost", names)


if __name__ == "__main__":
    main()
