#
# Cookbook Name:: chiliproject
# Recipe:: default
#
# Copyright 2011, ZeddWorks
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

chiliproject = Chef::EncryptedDataBagItem.load("apps", "chiliproject")
smtp = Chef::EncryptedDataBagItem.load("apps", "smtp")

chiliproject_url = chiliproject["chiliproject_url"]
chiliproject_path = "/srv/rails/#{chiliproject_url}"

package "memcached"
package "libmagickwand-dev"
gem_package "bundler"

passenger_nginx_vhost chiliproject_url

postgresql_user "chiliproject" do
  password "chiliproject"
end

postgresql_db "chiliproject_production" do
  owner "chiliproject"
end

directories = [
                "#{chiliproject_path}/shared/config","#{chiliproject_path}/shared/log",
                "#{chiliproject_path}/shared/system","#{chiliproject_path}/shared/pids",
                "#{chiliproject_path}/shared/config/environments","/var/chiliproject/files"
              ]
directories.each do |dir|
  directory dir do
    owner "nginx"
    group "nginx"
    mode "0755"
    recursive true
  end
end

cookbook_file "#{chiliproject_path}/shared/config/environments/production.rb" do
  source "production.rb"
  owner "nginx"
  group "nginx"
  mode "0400"
end

template "#{chiliproject_path}/shared/config/database.yml" do
  source "database.yml.erb"
  owner "nginx"
  group "nginx"
  mode "0400"
  variables({
    :db_adapter => chiliproject["db_adapter"],
    :db_name => chiliproject["db_name"],
    :db_host => chiliproject["db_host"],
    :db_user => chiliproject["db_user"],
    :db_password => chiliproject["db_password"]
  })
end

template "#{chiliproject_path}/shared/config/configuration.yml" do
  source "configuration.yml.erb"
  owner "nginx"
  group "nginx"
  mode "0400"
  variables({
    :smtp_host => smtp["smtp_host"],
    :domain => smtp["domain"],
    :port => smtp["port"],
    :attachments_path => chiliproject["attachments_path"]
  })
end

deploy_revision "#{chiliproject_path}" do
  repo "git://github.com/chiliproject/chiliproject.git"
  revision "v2.0.0" # or "HEAD" or "TAG_for_1.0" or (subversion) "1234"
  user "nginx"
  enable_submodules true
  before_migrate do
    cookbook_file "#{release_path}/Gemfile" do
      source "Gemfile"
      owner "nginx"
      group "nginx"
      mode "0400"
    end
    cookbook_file "#{release_path}/Gemfile.lock" do
      source "Gemfile.lock"
      owner "nginx"
      group "nginx"
      mode "0400"
    end
    execute "bundle install --deployment --without=sqlite mysql mysql2" do
      user "nginx"
      group "nginx"
      cwd release_path
    end
    execute "bundle package" do
      user "nginx"
      group "nginx"
      cwd release_path
    end
    execute "bundle exec rake generate_session_store" do
      user 'nginx'
      group 'nginx'
      cwd release_path
    end
  end
  migrate true
  migration_command "bundle exec rake db:migrate"
  symlink_before_migrate ({
                          "config/database.yml" => "config/database.yml",
                          "config/configuration.yml" => "config/configuration.yml",
                          "config/environments/production.rb" => "config/environments/production.rb"
                         })
  before_symlink do
    execute "bundle exec rake redmine:load_default_data" do
      user 'nginx'
      group 'nginx'
      cwd release_path
      environment "RAILS_ENV" => "production", "REDMINE_LANG" => "en"
    end
  end
  environment "RAILS_ENV" => "production"
  action :deploy # or :rollback
  restart_command "touch tmp/restart.txt"
end
