FROM redmine:latest

USER root

COPY docker/additional_environment.rb   /usr/src/redmine/config/additional_environment.rb
COPY docker/puma.rb                     /usr/src/redmine/config/puma.rb
COPY docker/render-configuration.rb     /railway/render-configuration.rb
COPY docker/bootstrap.rb                /railway/bootstrap.rb
COPY docker/entrypoint.sh               /railway/entrypoint.sh

ENV TINI_KILL_PROCESS_GROUP=1

ENTRYPOINT ["/railway/entrypoint.sh"]
CMD ["rails", "server", "-b", "0.0.0.0"]
