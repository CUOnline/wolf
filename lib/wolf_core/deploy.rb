namespace :deploy do

  task :config do
    on roles(:all) do
      etc_path = File.join(current_path, 'config', 'etc')

      within etc_path do
        config_files = [ "systemd/system/#{fetch(:application)}-worker.service",
                         "httpd/conf.d/#{fetch(:application)}.conf" ]

        config_files.each do |file|
          if test("[ -f #{File.join(etc_path, file)} ]")
            execute 'sudo', 'cp',  "./#{file}", "/etc/#{file}"
          end
        end
      end

      execute 'sudo', 'semanage', 'fcontext', '-a', '-t', 'httpd_sys_script_exec_t', "'#{deploy_to}/shared(/.*)?'"
      execute 'sudo', 'restorecon', '-R', deploy_to
    end
  end

  task :check_settings do
    on roles(:all) do
      if !test('[ -f /etc/wolf_core.yml ]')
        warn '**** Missing core config file /etc/wolf_core.yml ****'
      end

      if !test("[ `/usr/sbin/getsebool -a | grep 'httpd_can_network_connect --> on' | wc -l` -gt 0 ]")
        warn '**** SELinux httpd_can_network_connect set to off ****'
      end

      if !test("[ `/usr/sbin/getsebool -a | grep 'httpd_execmem --> on' | wc -l` -gt 0 ]")
        warn '**** SELinux httpd_execmem set to off ****'
      end
    end
  end

  task :restart do
    on roles(:all) do
      execute 'sudo', 'systemctl', 'restart', 'httpd'

      if test("[ `systemctl list-unit-files | grep #{fetch(:application)}-worker | wc -l` -gt 0 ]")
        execute 'sudo', 'daemon-reload'
        execute 'sudo', 'systemctl', 'restart', "#{fetch(:application)}-worker"
      end
    end
  end


  after :finished, :config
  after :config, :check_settings
  after :check_settings, :restart
end
