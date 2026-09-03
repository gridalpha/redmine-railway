# Redmine instance_evals this inside its Rails::Application class, so `config`
# here is the application configuration and these run before the middleware stack
# is built — which is what config.assume_ssl requires.

# Railway's edge terminates TLS and speaks plain HTTP to the container, and its
# health-check prober sends no X-Forwarded-Proto at all. assume_ssl tells Rails to
# treat every request as secure, so force_ssl can stay on for the Secure cookie
# flag and HSTS without the prober being redirected into a failed deployment.
config.assume_ssl = true
config.force_ssl  = ENV.fetch('REDMINE_FORCE_SSL', 'true') == 'true'

# Rails' built-in trusted-proxy list covers RFC1918 only, so with nothing set here
# request.remote_ip is Railway's own edge address, which rotates per request:
# every per-IP throttle and every logged client address is then wrong. The value
# is appended to Rails' defaults, not a replacement for them.
require 'ipaddr'
config.action_dispatch.trusted_proxies = [
  IPAddr.new('100.64.0.0/10'),   # Railway edge → container
  IPAddr.new('152.233.0.0/17'),  # Railway edge's own public range
  IPAddr.new('fd00::/8'),        # Railway private network
]
