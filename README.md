# Aifeed

A self-hosted RSS reader for AI and DevOps news: [Miniflux](https://miniflux.app) 2.3.4 with Postgres 18, run by Docker Compose.

`install.sh` sets it all up in one run:

- Installs Docker from get.docker.com if it isn't already there.
- Writes `compose.yaml`, `feeds.opml` and `.env` to `/opt/miniflux`. `.env` holds the generated DB and admin passwords (chmod 600).
- Starts both containers and waits for the healthcheck to pass.
- Imports 15 feeds into two categories, **AI** and **DevOps & Platform**, sets the user's timezone to America/Denver, and starts the first refresh.

You can run it again safely. It keeps the existing credentials and doesn't add duplicate feeds.

## Install

Run it on a Debian or Ubuntu VM or LXC. It refuses to run on a Proxmox host unless you set `FORCE=1`.

```bash
git clone https://github.com/nathanwbrown1/Aifeed.git
cd Aifeed
sudo bash install.sh
```

The repo is private, so if the server has no GitHub credentials, clone on your laptop and copy the script over:

```bash
scp install.sh <host>:~/install.sh
ssh -t <host> "sudo bash ~/install.sh"
```

Optional overrides (set them on the first run):

```bash
sudo PORT=8081 ADMIN_USER=nate INSTALL_DIR=/opt/miniflux TZ_NAME=America/Denver bash install.sh
```

When it finishes, it prints the URL, username and password. The URL uses the Tailscale IP if Tailscale is installed, otherwise the first LAN IP.

## Check that it worked

```bash
curl -fsS http://127.0.0.1:8080/healthcheck            # prints OK
sudo docker compose -f /opt/miniflux/compose.yaml ps   # both containers healthy
# Should print 15. The username and password are in /opt/miniflux/.env
curl -fsS -u <user>:<pass> http://127.0.0.1:8080/v1/feeds | grep -o '"feed_url"' | wc -l
```

## Manage it

```bash
cd /opt/miniflux
sudo docker compose ps                              # status
sudo docker compose logs -f miniflux                # logs
sudo docker compose pull && sudo docker compose up -d   # update
```

## Feeds

| AI | DevOps & Platform |
| --- | --- |
| Latent Space | Kubernetes Blog |
| Simon Willison's Weblog | LearnKube |
| Dwarkesh Podcast | SRE Weekly |
| Machine Learning Street Talk | The Pragmatic Engineer |
| The AI Daily Brief | CNCF (YouTube) |
| TLDR AI | Red Hat Developer |
| r/LocalLLaMA (top daily) | Red Hat OpenShift Blog |
| | Hacker News (150+ points) |

The CNCF YouTube and r/LocalLLaMA feeds couldn't be checked from a cloud session. After the first refresh, check them in Miniflux for parsing errors.
