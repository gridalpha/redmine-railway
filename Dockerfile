# Redmine on Railway.
#
# The published `redmine` image is fully env-var configurable for the database and
# the Rails secret, but three things it cannot express are what make a Railway
# deployment production-grade, so this is a one-layer derived image rather than a
# start-command override:
#
#   * config/configuration.yml — outgoing mail, the at-rest cipher key and the
#     webhook SSRF blocklist live in a YAML file no environment variable drives.
#   * A first-run bootstrap — upstream ships admin/admin and loads none of the
#     default trackers, roles or issue statuses until somebody clicks through the
#     admin UI. A template deploy has nobody to click.
#   * One volume, three persistent trees (attachments, plugins, themes). Railway
#     volumes are strictly 1:1, so they are symlinked onto a single mount.
FROM redmine:latest

USER root

# Redmine 7 previews Microsoft Office and LibreOffice attachments by converting
# them to Markdown with pandoc; the published image ships no pandoc, so the
# feature is dead without this layer.
RUN set -eux; \
	apt-get update; \
	apt-get install -y --no-install-recommends pandoc; \
	rm -rf /var/lib/apt/lists/*; \
	pandoc --version | head -1

COPY docker/additional_environment.rb   /usr/src/redmine/config/additional_environment.rb
COPY docker/puma.rb                     /usr/src/redmine/config/puma.rb
COPY docker/render-configuration.rb     /railway/render-configuration.rb
COPY docker/bootstrap.rb                /railway/bootstrap.rb
COPY docker/entrypoint.sh               /railway/entrypoint.sh

RUN set -eux; \
	chmod 0755 /railway /railway/entrypoint.sh; \
	chmod 0644 /railway/render-configuration.rb /railway/bootstrap.rb; \
# a typo here costs a crash loop with nothing in the log, so fail the build instead
	bash -n /railway/entrypoint.sh; \
	ruby -c /railway/render-configuration.rb; \
	ruby -c /railway/bootstrap.rb; \
	ruby -c /usr/src/redmine/config/additional_environment.rb; \
	ruby -c /usr/src/redmine/config/puma.rb; \
	chown redmine:redmine /usr/src/redmine/config/additional_environment.rb /usr/src/redmine/config/puma.rb; \
	[ -x /usr/bin/tini ]; \
# pristine copies of the two extension trees, so the volume can be refreshed from
# the image on every boot without losing anything the operator added
	cp -a /usr/src/redmine/plugins /opt/redmine-pristine-plugins; \
	cp -a /usr/src/redmine/public/themes /opt/redmine-pristine-themes

# Railway's PID 1 is /run/podman-init, so tini has to register as a subreaper and
# forward SIGTERM to the whole group or Puma's workers survive a redeploy.
ENV TINI_KILL_PROCESS_GROUP=1

ENTRYPOINT ["/railway/entrypoint.sh"]
CMD ["rails", "server", "-b", "0.0.0.0"]
