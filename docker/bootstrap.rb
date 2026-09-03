# Run through `rails runner`, once per boot, before Puma starts.
#
# Three jobs, all of which upstream leaves to a human clicking through the admin
# UI after the first login — which a Railway template deploy has nobody to do:
#
#   1. load the default trackers, roles, issue statuses and enumerations, without
#      which a fresh Redmine cannot create a single issue;
#   2. replace upstream's shipped admin/admin;
#   3. seed the handful of settings that are wrong by default on Railway — the
#      host name that goes into every notification link above all.
#
# Everything here is idempotent and every step yields to the operator: settings
# are seeded only while they still hold Redmine's shipped default, and the admin
# credentials are re-applied only when the variables themselves change.
require 'digest'

def log(message)
  puts "[railway] #{message}"
end

def env(name, default = nil)
  value = ENV[name]
  value.nil? || value.empty? ? default : value
end

# --------------------------------------------------------------------------
# 1. Default configuration data
# --------------------------------------------------------------------------
if Redmine::DefaultData::Loader.no_data?
  Redmine::DefaultData::Loader.load(env('REDMINE_LANG', 'en'))
  log 'loaded default configuration data (trackers, roles, statuses, enumerations)'
end

# --------------------------------------------------------------------------
# 2. Settings
#
# Redmine only stores a settings row once a value differs from config/settings.yml,
# so "no row" is a reliable stand-in for "the operator has never touched this".
# --------------------------------------------------------------------------
def seed(name, value)
  return if value.nil? || value.to_s.empty?
  if Setting.where(:name => name.to_s).exists?
    log "setting #{name} already customised; leaving it alone"
  else
    Setting.send(:"#{name}=", value)
    log "seeded #{name}=#{value}"
  end
end

# The public host is not cosmetic: it is what Redmine puts in every link it
# mails, and its shipped default is localhost:3000.
host = env('REDMINE_HOST_NAME') || env('RAILWAY_PUBLIC_DOMAIN')
if host
  current = Setting.where(:name => 'host_name').first
  # Also self-heal a stale generated domain — Railway hands out a new
  # *.up.railway.app name if the domain is ever regenerated — while never
  # touching a custom domain the operator typed in themselves.
  stale_generated = current && current.value.end_with?('.up.railway.app') && current.value != host
  if env('REDMINE_HOST_NAME') || current.nil? || current.value == 'localhost:3000' || stale_generated
    if Setting.host_name != host
      Setting.host_name = host
      log "set host_name=#{host}"
    end
    Setting.protocol = 'https' unless Setting.protocol == 'https'
  end
end

seed :mail_from,           env('REDMINE_EMAIL_FROM', host ? "redmine@#{host.split(':').first}" : nil)
# Safe posture for something published on the open internet: no anonymous access
# and no self-service accounts. Both are one variable away from Redmine's own
# defaults for anyone running a public tracker.
seed :login_required,      env('REDMINE_LOGIN_REQUIRED', '1')
seed :self_registration,   env('REDMINE_SELF_REGISTRATION', '0')
# The REST API is how everything integrates with Redmine and it authenticates
# every call with an API key, so it is on by default.
seed :rest_api_enabled,    env('REDMINE_REST_API_ENABLED', '1')
seed :attachment_max_size, env('REDMINE_ATTACHMENT_MAX_SIZE', '51200')

# --------------------------------------------------------------------------
# 3. Administrator account
#
# Setting a password stores a salted hash, so it is not idempotent on its own and
# would revert an operator's own password change on every redeploy. Stamp a
# digest of the inputs on the volume and re-apply only when that digest changes.
# --------------------------------------------------------------------------
password = env('REDMINE_ADMIN_PASSWORD')
if password
  login = env('REDMINE_ADMIN_LOGIN', 'admin')
  mail  = env('REDMINE_ADMIN_EMAIL')
  stamp = File.join(env('REDMINE_STATE_DIR', '/data'), '.admin-credentials.sha256')
  digest = Digest::SHA256.hexdigest([login, password, mail].join("\0"))

  if File.exist?(stamp) && File.read(stamp).strip == digest
    log 'administrator credentials unchanged; leaving the account alone'
  else
    admin = User.find_by_login(login) ||
            User.where(:admin => true).order(:id).first
    if admin.nil?
      log "WARNING: no administrator account found to configure"
    else
      admin.login = login
      admin.admin = true
      admin.status = User::STATUS_ACTIVE
      admin.mail = mail if mail && admin.mail != mail
      admin.password = password
      admin.password_confirmation = password
      admin.must_change_passwd = false
      unless admin.save
        # Fail the boot rather than quietly leaving upstream's admin/admin
        # reachable on a public domain.
        raise "could not set the administrator password: #{admin.errors.full_messages.join(', ')}"
      end
      File.write(stamp, digest)
      File.chmod(0o600, stamp)
      log "administrator account '#{login}' configured from REDMINE_ADMIN_PASSWORD"
    end
  end
end

log 'bootstrap complete'
