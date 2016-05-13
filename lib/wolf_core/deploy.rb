namespace :deploy do

  task :config do
    on roles(:all) do

      if !test('[ -f /etc/wolf_core.yml ]')
        warn '**** Missing core config file /etc/wolf_core.yml ****'
      end

      etc_path = File.join(current_path, 'config', 'etc')

      within etc_path do
        config_files = [ 'odbc.ini', 'odbcinst.ini', 'amazon.redshiftodbc.ini',
                         "systemd/system/#{fetch(:application)}-worker.service",
                         "httpd/conf.d/#{fetch(:application)}.conf" ]

        config_files.each do |file|
          if test("[ -f #{File.join(etc_path, file)} ]")
            execute :sudo, :cp,  "./#{file}", "/etc/#{file}"
          end
        end
      end

    end
  end

  task :restart do
    on roles(:all) do
      execute :sudo, :apachectl, :restart

      if test("[ `systemctl list-unit-files | grep #{fetch(:application)}-worker | wc -l` -gt 0 ]")
        execute :sudo, :service, "#{fetch(:application)}-worker", :restart
        execute :sudo, :systemctl, :enable, "#{fetch(:application)}-worker.service"
      end
    end
  end

  after :finished, :config
  after :config, :restart
end
