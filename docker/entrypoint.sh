#!/bin/bash
# Runs as root, ahead of the image's own /docker-entrypoint.sh, which is still the
# thing that writes config/database.yml, runs the migrations and drops to the
# `redmine` user. This wrapper only adds what Railway needs around it.
set -Eeo pipefail

log() { echo "[railway] $*"; }

APP_DIR=/usr/src/redmine
DATA_DIR="${RAILWAY_VOLUME_MOUNT_PATH:-/data}"

# --------------------------------------------------------------------------
# One volume, three trees.
#
# Redmine keeps attachments in files/, plugins in plugins/ and themes in
# public/themes/, and all three have to survive a redeploy. A Railway service
# gets exactly one volume, so the three live under the single mount and the app
# paths become symlinks into it.
# --------------------------------------------------------------------------
mkdir -p "$DATA_DIR/files" "$DATA_DIR/plugins" "$DATA_DIR/themes" "$DATA_DIR/repositories"

# Refresh the built-in plugins and themes from the image on every boot, so a
# Redmine upgrade is not shadowed by the previous release's copy sitting on the
# volume. Anything the operator added alongside them is left untouched.
cp -a /opt/redmine-pristine-plugins/. "$DATA_DIR/plugins/"
cp -a /opt/redmine-pristine-themes/.  "$DATA_DIR/themes/"

rm -rf "$APP_DIR/files" "$APP_DIR/plugins" "$APP_DIR/public/themes"
ln -s "$DATA_DIR/files"   "$APP_DIR/files"
ln -s "$DATA_DIR/plugins" "$APP_DIR/plugins"
ln -s "$DATA_DIR/themes"  "$APP_DIR/public/themes"

chown redmine:redmine "$DATA_DIR" "$DATA_DIR/files" "$DATA_DIR/plugins" "$DATA_DIR/themes" "$DATA_DIR/repositories"
chown -R redmine:redmine "$DATA_DIR/plugins" "$DATA_DIR/themes"
chmod 755 "$DATA_DIR/files"
# Walking every attachment on each boot is what the upstream entrypoint goes out
# of its way to avoid, so do it once and stamp the volume.
if [ ! -e "$DATA_DIR/.files-owned" ]; then
	chown -R redmine:redmine "$DATA_DIR/files"
	touch "$DATA_DIR/.files-owned"
	chown redmine:redmine "$DATA_DIR/.files-owned"
fi

# --------------------------------------------------------------------------
# Mail host.
#
# ${{mailpit.RAILWAY_PRIVATE_DOMAIN}} renders empty until that service owns a
# deployment, which is exactly the state a fresh template deploy is in, so repair
# the value on its shape rather than trusting the reference.
# --------------------------------------------------------------------------
case "${REDMINE_SMTP_ADDRESS:-}" in
	'' | :* ) REDMINE_SMTP_ADDRESS='mailpit.railway.internal' ;;
esac
export REDMINE_SMTP_ADDRESS

ruby /railway/render-configuration.rb > "$APP_DIR/config/configuration.yml"
chown redmine:redmine "$APP_DIR/config/configuration.yml"
chmod 640 "$APP_DIR/config/configuration.yml"
log "wrote config/configuration.yml (smtp ${REDMINE_SMTP_ADDRESS}:${REDMINE_SMTP_PORT:-1025})"

# --------------------------------------------------------------------------
# Migrate and bootstrap before the server starts.
#
# Doing it here rather than letting the server come up first closes the window in
# which a fresh deployment serves upstream's admin/admin to the internet, and it
# is the only chance to load the default trackers/roles/statuses without a human
# in the admin UI. There is no service ordering on Railway, so the database may
# still be starting: retry rather than crash-looping.
# --------------------------------------------------------------------------
export REDMINE_STATE_DIR="$DATA_DIR"
bootstrapped=
for attempt in $(seq 1 30); do
	if /docker-entrypoint.sh bundle exec rails runner /railway/bootstrap.rb; then
		bootstrapped=1
		break
	fi
	log "bootstrap attempt ${attempt} failed (database not ready yet?); retrying in 10s"
	sleep 10
done
if [ -z "$bootstrapped" ]; then
	log "FATAL: could not migrate and bootstrap Redmine; check the database variables"
	exit 1
fi

# The migration already ran above; do not let the image's entrypoint run it again
# against the container that is about to serve traffic.
export REDMINE_NO_DB_MIGRATE=1
unset REDMINE_PLUGINS_MIGRATE

log "starting: $*"
exec /usr/bin/tini -s -- /docker-entrypoint.sh "$@"
