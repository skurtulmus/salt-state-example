# Salt state file for Ubuntu 22.04 Jammy and CentOS Stream 9 minions

# User present on systems
make_user:
  group.present:
    - name: {{ pillar['os_user'] }}
    - gid: 2024
  user.present:
    - name: {{ pillar['os_user'] }}
    - uid: 2024
    - gid: 2024
    - home: /home/krk
    - shell: /bin/bash
    - password: {{ pillar['os_pass'] }}
    - hash_password: True

# Sudo privileges for user
/etc/sudoers.d/kraken-sudo:
  file.managed:
    {% if grains['os_family'] == 'Debian' %}
    - source: salt://files/kraken-apt
    {% elif grains['os_family'] == 'RedHat' %}
    - source: salt://files/kraken-yum
    {% endif %}
    - user: root
    - group: root
    - mode: 440

# Timezone
Atlantic/Reykjavik:
  timezone.system

# Enable IP Forwarding
net.ipv4.ip_forward:
  sysctl.present:
    - value: 1
net.ipv6.conf.all.forwarding:
  sysctl.present:
    - value: 1

# Install git
git:
  pkg.installed

# Install packages
common_commands:
  pkg.installed:
    {% if grains['os_family'] == 'RedHat' %}
    - require:
      - pkg: epel-release
    {% endif %}
    - pkgs:
      - traceroute
      - sysstat
      - mtr
      - htop

# Extra packages repository for CentOS
{% if grains['os_family'] == 'RedHat' %}
epel-release:
  pkg.installed
{% endif %}

# Install HashiCorp repository on Ubuntu
{% if grains['os_family'] == 'Debian' %}
repo_keys:
  file.managed:
    - name: /usr/share/keyrings/hashicorp.asc
    - source: https://apt.releases.hashicorp.com/gpg
    - makedirs: True
    - skip_verify: True
gpg:
  pkg.installed
dearmor_keys:
  cmd.run:
    - name: gpg --dearmor -o /usr/share/keyrings/hashicorp.gpg /usr/share/keyrings/hashicorp.asc
    - creates: /usr/share/keyrings/hashicorp.gpg
    - require:
      - pkg: gpg
      - file: repo_keys
    - stateful: True
hashicorp_debian:
  pkgrepo.managed:
    - name: deb [arch=amd64 signed-by=/usr/share/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com jammy main
    - file: /etc/apt/sources.list.d/hashicorp.list
    - require_in:
      - pkg: terraform
    - watch:
      - cmd: dearmor_keys
{% endif %}

# Install HashiCorp repository on CentOS
{% if grains['os_family'] == 'RedHat' %}
hashicorp_redhat:
  file.managed:
    - name: /etc/yum.repos.d/hashicorp.repo
    - source: https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
    - skip_verify: True
    - require_in:
      - pkg: terraform
{% endif %}

# Install Terraform (Version 1.6.4-1)
terraform:
  pkg.installed:
    - version: 1.6.4-1
    {% if grains['os_family'] == 'Debian' %}
    - fromrepo: jammy
    {% elif grains['os_family'] == 'RedHat' %}
    - fromrepo: hashicorp
    {% endif %}

# /etc/hosts records for the 192.168.70.192/27 IP subnet
{% set hosts_prefix = '192.168.70.' %}
{% for i in range(193, 222) %}
file_append_{{ i }}:
  file.append:
    - name: /etc/hosts
    - text: "{{ hosts_prefix }}{{ i }} app.kraken.local"
{% endfor %}

# UBUNTU
# Installed Mysql server and required packages
# Mysql server configuration
# Mysql DB user and rights (Should be configured with remote user IP address)
# Mysqldump cron job
# Allow database access outside localhost
{% if grains['os_family'] == 'Debian' %}
mysql_apt_packages:
  pkg.installed:
    - pkgs:
      - mysql-server
      - mysql-client
      - default-libmysqlclient-dev
      - python3-dev
      - pkg-config
      - build-essential
mysql_pip_packages:
  pip.installed:
    - cwd: '/opt/saltstack/salt/bin'
    - bin_env: '/opt/saltstack/salt/bin/pip3'
    - name: mysqlclient
    - require:
      - pkg: mysql_apt_packages
mysql:
  service.running:
    - enable: True
    - require:
      - pkg: mysql_apt_packages
      - pip: mysql_pip_packages
    - watch:
      - file: /etc/mysql/mysql.conf.d/mysqld.cnf
mysql_db:
  mysql_user.present:
    - name: {{ pillar['db_user'] }}
    - password: {{ pillar['db_pass'] }}
    - host: localhost
    - require:
      - service: mysql
  mysql_database.present:
    - name: {{ pillar['db_name'] }}
    - require:
      - mysql_user: {{ pillar['db_user'] }}
  mysql_grants.present:
    - grant: all privileges
    - database: {{ pillar['db_name'] }}.*
    - user: {{ pillar['db_user'] }}
    - host: localhost
    - require:
      - mysql_user: {{ pillar['db_user'] }}
mysql_cron:
  file.directory:
    - name: /backup
    - makedirs: True
  cron.present:
    - name: mysqldump -u {{ pillar['db_user'] }} -p {{ pillar ['db_pass'] }} --all-databases > /backup/dbdump
    - user: root
    - hour: 2
    - minute: 0
mysql_access_conf_1:
  file.replace:
    - name: /etc/mysql/mysql.conf.d/mysqld.cnf
    - pattern: '^(bind-address.*)$'
    - repl: '# \1'
{% endif %}

# CENTOS STREAM
# Install Nginx and required packages
# Configure Nginx server
# nginx.conf and www.conf
# Nginx restart cron job
# Custom Nginx log rotation with logrotate and cron
# Self-signed certificate with OpenSSL
# Install and configure Wordpress (DB_HOST should point to the Ubuntu server)
# Allow http and https ports on firewalld
# SELinux setting allowing database access over the network for httpd
{% if grains['os_family'] == 'RedHat' %}
nginx_config:
  pkg.installed:
    - name: nginx
    - require:
      - pkg: epel-release
  file.managed:
    - name: /etc/nginx/nginx.conf
    - source: salt://files/nginx.conf
  service.running:
    - name: nginx
    - enable: True
    - reload: True
    - watch:
      - file: /etc/nginx/nginx.conf
      - file: /etc/nginx/conf.d/cert.conf
      - file: /etc/php-fpm.d/www.conf
    - require:
      - pkg: nginx
  cron.present:
    - name: systemctl restart nginx
    - user: root
    - daymonth: 1
    - hour: 0
    - minute: 0
nginx_include_cert:
  file.managed:
    - name: /etc/nginx/conf.d/cert.conf
    - source: salt://files/cert.conf
nginx_logrotate:
  file.managed:
    - name: /etc/logrotate.d/nginx
    - source: salt://files/logrotate_nginx
  cron.present:
    - hour: '*/4'
    - minute: 0
    - name: /usr/sbin/logrotate /etc/logrotate.d/nginx
certs_directory:
  file.directory:
    - name: /etc/ssl/certs
    - makedir: True
private_directory:
  file.directory:
    - name: /etc/ssl/private
    - makedir: True
    - mode: 700
create_certs:
  cmd.run:
    - name: openssl req -x509 -nodes -days 90 -newkey rsa:4096 -keyout /etc/ssl/private/nginx_cert.key -out /etc/ssl/certs/nginx_cert.crt -subj "/C=TR/ST=Turkey/L=Istanbul/O=Kraken/OU=IT/CN=kraken"
    - creates:
      - /etc/ssl/certs/nginx_cert.crt
      - /etc/ssl/private/nginx_cert.key
wordpress_reqs:
  pkg.installed:
    - pkgs:
      - php
      - php-mysqlnd
      - mysql
    - require:
      - pkg: epel-release
  file.managed:
    - name: /etc/php-fpm.d/www.conf
    - source: salt://files/www.conf
    - makedirs: True
  service.running:
    - name: php-fpm
    - enable: True
    - reload: True
    - watch:
      - file: /etc/nginx/nginx.conf
      - file: /etc/php-fpm.d/www.conf
    - require:
      - pkg: wordpress_reqs
wordpress_download:
  file.managed:
    - name: /tmp/wordpress2024.tar.gz
    - source: https://wordpress.org/latest.tar.gz
    - makedirs: True
    - skip_verify: True
wordpress_directory:
  file.directory:
    - name: /var/www/wordpress2024
    - makedirs: True
wordpress_extract:
  archive.extracted:
    - name: /var/www/wordpress2024
    - source: /tmp/wordpress2024.tar.gz
    - user: nginx
    - group: nginx
    - require:
      - file: wordpress_download
      - file: wordpress_directory
    - if_missing: /var/www/wordpress2024/wordpress
wordpress_config:
  file.managed:
    - name: /var/www/wordpress2024/wordpress/wp-config.php
    - source: salt://files/wp-config
    - replace: False
    - user: nginx
    - group: nginx
    - require:
      - file: wordpress_directory
wordpress_pillar_append:
  file.append:
    - name: /var/www/wordpress2024/wordpress/wp-config.php
    - text:
      - "define( 'DB_NAME',     '{{ pillar['db_name'] }}' );"
      - "define( 'DB_USER',     '{{ pillar['db_user'] }}' );"
      - "define( 'DB_PASSWORD', '{{ pillar['db_pass'] }}' );"
      - "define( 'DB_HOST',     'localhost' );"
    - require:
      - file: wordpress_config
wordpress_keys:
  file.managed:
    - name: /var/www/wordpress2024/wordpress/keys_file
    - source: https://api.wordpress.org/secret-key/1.1/salt
    - replace: False
    - skip_verify: True
    - require:
      - file: wordpress_directory
wordpress_keys_append:
  file.append:
    - name: /var/www/wordpress2024/wordpress/wp-config.php
    - source: /var/www/wordpress2024/wordpress/keys_file
    - require:
      - file: wordpress_config
      - file: wordpress_keys
public:
  firewalld.present:
    - name: public
    - services:
      - http
      - https
httpd_can_network_connect:
  selinux.boolean:
    - value: True
    - persist: True
httpd_can_network_connect_db:
  selinux.boolean:
    - value: True
    - persist: True
{% endif %}
