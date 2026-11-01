# Handoff: put Miniflux (an RSS reader) on Nate's Dell server

You're Claude Code on Nate's Windows laptop (msi-toaster). Nate wants a self-hosted RSS reader for AI and DevOps news on his Dell server, the box he uses for self-hosting. A cloud session already wrote and tested the installer. It's `install.sh` in this repo. Your job is to get it onto the Dell and run it there.

A cloud session can't do this part. It has no route to the Dell, and Remote Control doesn't share Windows folders with cloud sessions.

## What's done
- `install.sh` installs Miniflux 2.3.4 and Postgres 18 with Docker Compose in /opt/miniflux. It installs Docker first if it's missing, generates the DB and admin passwords and saves them in /opt/miniflux/.env (chmod 600), then imports 15 feeds into two categories (AI, DevOps & Platform). It also sets the user's timezone to America/Denver and starts the first refresh.
- Tested end to end on a scratch Docker host: all 15 feeds imported, timezone set, version 2.3.4. Running it a second time keeps the credentials and doesn't add duplicate feeds.
- It's shellcheck-clean, and `.gitattributes` makes git check it out with LF line endings, even on Windows.

## Steps
1. **Get the script.** Clone the repo (`git clone https://github.com/nathanwbrown1/Aifeed.git`) or pull it if you already have it. Run `git ls-files --eol install.sh`. It should show `i/lf w/lf`. If the working copy shows `crlf`, convert it with `dos2unix install.sh` before you copy it. CRLF breaks bash.
2. **Find the Dell.** Look for a matching host in `~/.ssh/config`. If there isn't one, ask Nate for the Dell's SSH host or IP and his username. Don't guess.
3. **Check what's on it.** Run `ssh <host> "cat /etc/os-release; command -v pveversion; command -v docker; ss -ltn | grep ':8080 ' || echo 8080-free"`.
   - **If it runs Proxmox**, don't install on the host. The script refuses to run there anyway. Ask Nate which existing Debian/Ubuntu LXC or VM to use, or offer to create a small Debian 12 LXC. Ask before you create anything, then target that guest instead.
   - **If port 8080 is taken**, pick a free port and pass `PORT=<port>` on the first run.
   - **If it's RHEL-family instead of Debian/Ubuntu**, tell Nate before you go ahead. The script is built for Debian/Ubuntu.
4. **Copy and run it:**
   ```
   scp install.sh <host>:~/install.sh
   ssh -t <host> "sudo bash ~/install.sh"           # or: sudo PORT=<port> bash ~/install.sh
   ```
   If sudo asks for a password, Nate types it. Don't handle or store it yourself.
5. **Verify on the Dell:**
   - `curl -fsS http://127.0.0.1:<port>/healthcheck` should return `OK`.
   - `sudo docker compose -f /opt/miniflux/compose.yaml ps` should show both containers healthy.
   - Get the feed count with `curl -fsS -u <user>:<pass> http://127.0.0.1:<port>/v1/feeds | grep -o '"feed_url"' | wc -l`. It should be 15. The username and password are in /opt/miniflux/.env.
6. **Report back to Nate** with the URL, username and password the script printed. The URL uses the Dell's Tailscale IP if Tailscale is installed, otherwise its LAN IP. Wait about a minute after the install, then list any feed that shows a parsing error. The CNCF YouTube and r/LocalLLaMA feeds couldn't be checked from the cloud, so look at those two.

## Guardrails
- Don't open router or firewall ports to the internet, and don't change SSH or sudo config.
- Ask Nate before creating, stopping or changing any VM, container or existing service on the Dell.
- Don't paste the generated passwords anywhere except your reply to Nate. Never commit `/opt/miniflux/.env` or the passwords to this repo.
