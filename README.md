# Redmine on Railway

A one-layer image over the official [`redmine`](https://hub.docker.com/_/redmine)
Docker image that makes a click-to-deploy Redmine usable the moment it finishes
booting — no first-login wizard, no `admin/admin`, and mail, attachments, plugins
and themes all wired up.

## What this adds over the published image

| Gap in the published image | What happens here |
|---|---|
| `admin` / `admin`, with the password change deferred to the first login | The administrator password is set from `REDMINE_ADMIN_PASSWORD` before Puma starts, so the default credentials are never reachable |
| No trackers, roles, issue statuses or enumerations until an admin clicks "load the default configuration data" | `Redmine::DefaultData::Loader` runs at first boot |
| `host_name` defaults to `localhost:3000`, so every notification email links nowhere | Seeded from `RAILWAY_PUBLIC_DOMAIN`, with `protocol` set to `https` |
| Outgoing mail, the at-rest cipher key and the webhook blocklist live in `config/configuration.yml`, which no environment variable drives | The file is rendered from the environment on every boot |
| Webhooks can reach anything the container can, including the rest of the private network | A blocklist covering RFC1918, CGNAT, link-local and `*.railway.internal` |
| Attachments, plugins and themes are three directories, and a Railway service gets one volume | All three are symlinked onto the single mount |
| Rails sees plain HTTP behind the edge, so session cookies lose `Secure` and `remote_ip` is Railway's rotating edge address | `assume_ssl` + `force_ssl`, and Railway's ranges added to `trusted_proxies` |
| Office and LibreOffice attachment previews need pandoc, which the image does not ship | `pandoc` installed |
| Single-process Puma with five threads | Two workers by default, `WEB_CONCURRENCY` to change it |

## Layout

```
Dockerfile                            FROM redmine:latest, one layer
docker/entrypoint.sh                  volume layout, config rendering, migrate + bootstrap
docker/render-configuration.rb        config/configuration.yml from the environment
docker/bootstrap.rb                   default data, settings, administrator account
docker/additional_environment.rb      Rails: assume_ssl, force_ssl, trusted proxies
docker/puma.rb                        worker and thread counts
```

`docker/entrypoint.sh` wraps the image's own `/docker-entrypoint.sh` rather than
replacing it, so the upstream database-configuration, permission-fixing and
privilege-dropping logic all still run.

## Environment variables

Everything has a working default except the database connection and the two
secrets. Values are read fresh on every boot.

### Database

| Variable | Notes |
|---|---|
| `REDMINE_DB_POSTGRES` | Postgres host |
| `REDMINE_DB_PORT` | Postgres port |
| `REDMINE_DB_USERNAME` | |
| `REDMINE_DB_PASSWORD` | |
| `REDMINE_DB_DATABASE` | |

### Secrets — set once, never rotate casually

| Variable | Notes |
|---|---|
| `SECRET_KEY_BASE` | Signs session cookies. Changing it logs everyone out |
| `REDMINE_DATABASE_CIPHER_KEY` | Encrypts SCM passwords, LDAP bind passwords and 2FA secrets at rest. **Changing it makes all three permanently unreadable** |

### Administrator

| Variable | Default | Notes |
|---|---|---|
| `REDMINE_ADMIN_LOGIN` | `admin` | |
| `REDMINE_ADMIN_PASSWORD` | — | Applied whenever it changes; a password change made in the UI is preserved otherwise |
| `REDMINE_ADMIN_EMAIL` | — | |

### Mail

| Variable | Default | Notes |
|---|---|---|
| `REDMINE_SMTP_ADDRESS` | `mailpit.railway.internal` | |
| `REDMINE_SMTP_PORT` | `1025` | |
| `REDMINE_SMTP_STARTTLS` | `false` | `true` for a real relay on 587 |
| `REDMINE_SMTP_SSL` | `false` | `true` for implicit TLS on 465 |
| `REDMINE_SMTP_USERNAME` / `REDMINE_SMTP_PASSWORD` | — | Enables SMTP auth when set |
| `REDMINE_SMTP_AUTHENTICATION` | `plain` | |
| `REDMINE_SMTP_DOMAIN` | — | HELO domain |
| `REDMINE_EMAIL_FROM` | `redmine@<public domain>` | |

### Settings seeded at first boot

Each is written only while the setting still holds Redmine's shipped default, so
a later change in **Administration → Settings** is never reverted.

| Variable | Default | Redmine's default |
|---|---|---|
| `REDMINE_LOGIN_REQUIRED` | `1` | `0` — anonymous access to public projects |
| `REDMINE_SELF_REGISTRATION` | `0` | `2` — self-registration with email activation |
| `REDMINE_REST_API_ENABLED` | `1` | `0` |
| `REDMINE_ATTACHMENT_MAX_SIZE` | `51200` (KB) | `5120` |
| `REDMINE_HOST_NAME` | `RAILWAY_PUBLIC_DOMAIN` | `localhost:3000` |
| `REDMINE_LANG` | `en` | language of the default data |

### Other

| Variable | Default | Notes |
|---|---|---|
| `WEB_CONCURRENCY` | `2` | Puma workers; `0` for single-process mode |
| `RAILS_MAX_THREADS` | `5` | threads per worker |
| `REDMINE_FORCE_SSL` | `true` | HSTS and the `Secure` cookie flag |
| `REDMINE_WEBHOOK_BLOCKLIST_EXTRA` | — | comma-separated additions |
| `REDMINE_THUMBNAIL_TIMEOUT` | `10` | seconds |

## Volume

Mount one volume and point `RAILWAY_VOLUME_MOUNT_PATH` at it (Railway does this
automatically). It is laid out as:

```
<mount>/files          attachments
<mount>/plugins        Redmine plugins, refreshed from the image each boot
<mount>/themes         public/themes
<mount>/repositories   somewhere to clone repositories for the SCM browser
```

`git`, `svn`, `hg` and `bzr` are all present in the base image, so a repository
cloned under `<mount>/repositories` can be browsed from Redmine directly.

## Licence

Redmine is GPL-2.0. This wrapper is MIT.
