# Redmine ships no Puma configuration, which leaves it in single-process mode with
# five threads. Two workers is a better default on a Railway container (8 vCPU,
# 8 GB) and WEB_CONCURRENCY=0 puts it back to single mode.
#
# Bind address and port are deliberately not set here: `rails server -b 0.0.0.0`
# passes those, and declaring them again risks a second listener on the same port.
workers_count = Integer(ENV.fetch('WEB_CONCURRENCY', 2))
threads_count = Integer(ENV.fetch('RAILS_MAX_THREADS', 5))

threads threads_count, threads_count
workers workers_count

if workers_count > 0
  preload_app!
  on_worker_boot do
    ActiveRecord::Base.establish_connection if defined?(ActiveRecord::Base)
  end
end

plugin :tmp_restart
