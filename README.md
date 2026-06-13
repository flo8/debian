# debian

Server setup scripts and dotfiles for a fresh Debian 13 (trixie) machine.

## Quick install

```bash
curl -fsSL https://raw.githubusercontent.com/flo8/debian/main/install.sh | sudo bash
```

`install.sh` provisions the box: creates the login user with its SSH key,
installs the dotfiles below, and applies the base configuration. Set
`NEW_HOSTNAME=foo` in the environment to also change the hostname.

## Layout

| Path | What it is |
|------|------------|
| `install.sh` | Main provisioning script (run on a fresh server). |
| `add-sshuser.sh` | Adds an extra SSH user. |
| `neon-break.sh` | Standalone helper script. |
| `motd` | Login message-of-the-day. |
| `bashrc`, `bash_profile`, `inputrc` | Shell configuration. |
| `.tmux.conf` | tmux configuration. |
| `micro-settings.json`, `micro-bindings.json`, `micro-flo.micro` | [micro](https://micro-editor.github.io/) editor config + theme. |
| `mc-ini` | Midnight Commander config. |
| `useful.md` | Handy command reference. |
| [`gitea/`](gitea/) | Self-hosted Gitea forge (install, TLS, theme) + daily security scanning of the hosted repos. See [`gitea/README.md`](gitea/README.md). |
