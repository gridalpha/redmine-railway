# Renders config/configuration.yml from the environment.
#
# Redmine reads outgoing mail settings, the at-rest cipher key and the webhook
# blocklist from this file only — there is no environment variable for any of
# them — and the file is YAML, so it is generated with to_yaml rather than a
# heredoc: a generated password containing a quote or a colon would otherwise
# produce a file Redmine aborts on at boot.
require 'yaml'

def env(name, default = nil)
  value = ENV[name]
  value.nil? || value.empty? ? default : value
end

def flag(name, default)
  case env(name, default.to_s).downcase
  when 'true', '1', 'yes', 'on' then true
  else false
  end
end

secure_cookies = flag('REDMINE_FORCE_SSL', true)

smtp = {
  'address'              => env('REDMINE_SMTP_ADDRESS', 'mailpit.railway.internal'),
  'port'                 => Integer(env('REDMINE_SMTP_PORT', '1025')),
  # Mailpit's plain 1025 listener advertises no STARTTLS; a real relay wants this on.
  'enable_starttls_auto' => flag('REDMINE_SMTP_STARTTLS', false),
}
smtp['ssl']       = true                         if flag('REDMINE_SMTP_SSL', false)
smtp['domain']    = env('REDMINE_SMTP_DOMAIN')   if env('REDMINE_SMTP_DOMAIN')
if env('REDMINE_SMTP_USERNAME')
  smtp['authentication'] = env('REDMINE_SMTP_AUTHENTICATION', 'plain').to_sym
  smtp['user_name']      = env('REDMINE_SMTP_USERNAME')
  smtp['password']       = env('REDMINE_SMTP_PASSWORD', '')
end

# Webhook targets are operator-supplied URLs fetched by the server, so without a
# blocklist any authenticated user can reach the rest of the Railway private
# network. Railway's edge lives in 100.64.0.0/10 and services resolve under
# *.railway.internal, so both belong here alongside the usual private ranges.
blocklist = %w[
  127.0.0.0/8
  10.0.0.0/8
  172.16.0.0/12
  192.168.0.0/16
  169.254.0.0/16
  100.64.0.0/10
  ::1
  fc00::/7
  fe80::/10
  localhost
  *.railway.internal
]
extra = env('REDMINE_WEBHOOK_BLOCKLIST_EXTRA')
blocklist += extra.split(',').map(&:strip).reject(&:empty?) if extra

config = {
  'default' => {
    'email_delivery' => {
      'delivery_method' => :smtp,
      'smtp_settings'   => smtp,
    },
    # Attachments live in files/, which is a symlink onto the Railway volume.
    'attachments_storage_path' => nil,
    'autologin_cookie_secure'  => secure_cookies,
    # Encrypts SCM passwords, LDAP bind passwords and 2FA TOTP secrets at rest.
    # Losing or changing it makes all three unreadable, so it is a stable secret.
    'database_cipher_key'      => env('REDMINE_DATABASE_CIPHER_KEY'),
    'webhook_blocklist'        => blocklist,
    'thumbnails_generation_timeout' => Integer(env('REDMINE_THUMBNAIL_TIMEOUT', '10')),
  },
}

print config.to_yaml
