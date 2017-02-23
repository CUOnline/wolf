This gem was created to simplify development of CU Online apps by bundling commonly used functionality & configuration. Generally the use cases for these apps involve presentation and/or manipulation of data by way of the [Canvas API](https://canvas.instructure.com/doc/api/index.html) or [Canvas Data](https://guides.instructure.com/m/4214/l/449098-what-is-canvas-data). wolf_core provides a [Sinatra](https://www.sinatrarb.com) application class from which useful behavior can be inherited. The general idea is to provide useful conventions and defaults that can be overridden if needed.

# Table of Contenets
* [Basic Usage](#basic-usage)
* [Servier Provisioning](#server-provisioning)
* [Deployment Script](#deployment-script)
* [Obtaining Canvas OAuth Tokens](#obtaining-canvas-oauth-tokens)
* [Shared Assets](#shared-assets)
* [App Configuration](#app-configuration)
* [Helpers API](#helpers-api)


# Basic Usage
At this time the gem is not published to a gem source, as it is only used internally. As such, simply point the Gemfile at the github repository.

`gem 'wolf_core', :git => 'https://github.com/CUOnline/wolf_core'`

Since there are no public release versions, you may optionally supply a specific git branch and/or commit hash. If ommitted, Gemfile.lock will lock in the latest master commit.

`gem 'wolf_core', :git => 'https://github.com/CUOnline/wolf_core', :branch => 'dev', :ref => 'a1b2c3d4'`

After running `bundle install`, require the gem and build your Sinatra application as normal, with the exception of subclassing WolfCore::App instead of Sinatra::Base. WolfCore::App, in turn, is a subclass of Sinatra::Base, so all Sinatra functionality is included.

```
require 'bundler/setup'
require 'wolf_core'

class MyApp < WolfCore::App
  get '/' do
    'Hello'
  end
end 
```

To run the app locally with Rack, add a file called `config.ru` with the content below. From the directory containing this file, run the `rackup` command.

```
require './myapp.rb'
run MyApp
```

# Server Provisioning
This is a step-by-step guide to setting up the dependencies and configuration on a fresh CentOS/RHEL server.

##### Install Ruby 2.3
Note: This the following method for installing & upgrading ruby was used specifically to maximize use of built-in packages. Ifyou do not mind building from source, consider chruby, RVM, or rbenv as potentially less painful alternatives for upgrading to 2.3.

`sudo yum install centos-release-scl`

`sudo yum install rh-ruby23 rh-ruby23-ruby-devel`

When installing Ruby 2.3 in this manner, it needs to be explicitly enabled for each login session to work. You can do this with `scl enable rh-ruby23 bash`. To enable automatically for all users (except root) upon login, add the following lines to etc/profile.d/ruby_23.sh. This is necessary so that whichever user is deploying apps via capistrano/ssh will be doing so in the ruby 2.3 enviornment. You should also add the same lines to /etc/sysconfig/httpd, so the same happens for the Apache process.
```
export PATH=/opt/rh/rh-ruby23/root/usr/local/bin:/opt/rh/rh-ruby23/root/usr/bin${PATH:+:${PATH}}
export LD_LIBRARY_PATH=/opt/rh/rh-ruby23/root/usr/local/lib64:/opt/rh/rh-ruby23/root/usr/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
export MANPATH=/opt/rh/rh-ruby23/root/usr/local/share/man:/opt/rh/rh-ruby23/root/usr/share/man:$MANPATH
export PKG_CONFIG_PATH=/opt/rh/rh-ruby23/root/usr/local/lib64/pkgconfig:/opt/rh/rh-ruby23/root/usr/lib64/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}
export XDG_DATA_DIRS=/opt/rh/rh-ruby23/root/usr/local/share:/opt/rh/rh-ruby23/root/usr/share${XDG_DATA_DIRS:+:${XDG_DATA_DIRS}}
```

To ensure the rest of this setup is also done in the 2.3 environment, switch to root and enable 2.3. The remainder of the steps assume you are root with 2.3 enabled.
`sudo su`

`scl enable rh-ruby23 bash`

##### Install Passenger/Apache
`yum install epel-release yum-utils httpd-devel`

`yum-config-manager --enable epel`

`yum install pygpgme curl`

`curl --fail -sSLo /etc/yum.repos.d/passenger.repo https://oss-binaries.phusionpassenger.com/yum/definitions/el-passenger.repo`

`yum install  mod_passenger`

We also need to tell passenger to use ruby 2.3 instead of the default system ruby. In /etc/httpd/conf.d/passenger.conf change PassengerRuby line to:
`PassengerRuby /opt/rh/rh-ruby23/root/usr/bin/ruby`

##### Install App dependencies
`yum install git gcc gcc-c++ unixODBC unixODBC-devel mod_ssl`

`gem install bundler`

##### Set up app, tmp, log directories
`mkdir /var/www/html/cu-online /tmp/wolf /var/log/wolf`

`chmod -R o+w /tmp/wolf /var/log/wolf /var/www/html/cu-online`

`chown -R root:apache /var/www/html/`

##### Set SELinux permissions for httpd
`semanage fcontext -a -t httpd_sys_rw_content_t '/var/log/wolf(/.*)?'`

`restorecon -R /var/log/wolf`

`semanage fcontext -a -t httpd_sys_rw_content_t ‘/tmp/wolf(/.*)?’`

`restorecon -R /tmp/wolf`

`setsebool -P httpd_can_network_connect 1`

`setsebool -P httpd_execmem 1`

##### Install ODBC Drivers & config to allow connection to Canvas Data Redshift
See also: http://docs.aws.amazon.com/redshift/latest/mgmt/install-odbc-driver-linux.html

`wget  https://s3.amazonaws.com/redshift-downloads/drivers/AmazonRedshiftODBC-64bit-1.2.7.1007-1.x86_64.rpm`

`yum --nogpgcheck localinstall ./AmazonRedshiftODBC-64bit-1.2.7.1007-1.x86_64.rpm`

##### Copy config files
wolf_core.yml is the master default config for wolf apps. The other three are used to configure the Amazon ODBC data source. Examples of these files can be found in any wolf app repository in the config folder.
`/etc/wolf_core.yml`

`/etc/amazon.redshift.ini`

`/etc/odbcinst.ini`

`/etc/odbc.ini`

##### Point environment to config files
Add the following lines to /etc/environment
`WOLF_CONFIG=/etc/wolf_core.yml`

`AMAZONREDSHIFTODBCINI=/etc/amazon.redshift.ini`

`ODBCSYSINI=/etc`

`ODBCINI=/etc/odbc.ini`

You should also add ONE of the following lines, depending on the environment. This setting will dictate which settings are chosen from wolf_core.yml when an app loads.
`RACK_ENV=test`

`RACK_ENV=development`

`RACK_ENV=production`

##### Allow passwordless sudo for deploy user
See also: http://capistranorb.com/documentation/getting-started/authentication-and-authorisation/
Capistrano can't give you a sudo password prompt, so this will allow the deploy user to execute certain priveliged actions needed in the deploy script without one.

`visudo`

Add the following line at the bottom of the file:

`deployusername ALL=(ALL) NOPASSWD:/usr/bin/cp, /usr/bin/systemctl, /usr/sbin/semanage, /usr/sbin/restorecon, /usr/bin/restorecon`

##### Enable & Rerstart services
`systemctl enable httpd`

`systemctl restart httpd`

`systemctl enable sshd`

`systemctl start sshd`

##### Deploy
Deploy from the base of an app directory with `cap test deploy` or `cap production deploy.` This should be done on a machine other than the server itself unless you have explicitly configured capistrano to deploy to localhost.

# Deployment Script
Allows simple auotmated deployment over ssh using the [capistrano gem](http://capistranorb.com/documentation/overview/what-is-capistrano/). wolf_core includes a custom task for deploying to CU servers setup in the above manner. In addition to the default capistrano behavior of pulling down code and installing gems, this custom task (defined in lib/wolf_core/deploy.rb) does the following:
  * Copies apache config for app to httpd/conf.d
  * Copies systemd service file to /etc/systemd/system (if needed - these are usually for running resque workers)
  * Sets appropriate SELinux contexts and booleans
  * Raises warning for missing wolf_core configuration file
  * Restarts apache and worker service

This custom task is defined in the gem, but each app needs it's own deployment configuration (i.e. apache config, systemd service file, deploy host/path/user) defined in that apps config directory. Once configured an app can be deployed with `cap test deploy` or `cap prodution deploy`, run from the base level of the app directory.

Capistrao config: Capfile, config/deploy.rb, and config/deploy/{server environment}.rb
Apache config: config/etc/httpd/conf.d/{appname}.conf
Systemd worker service (optional): config/etc/systemd/system/{appname}-worker.service
(appname is defined in config/deploy.rb as the :application capistrano setting)

While the deploy script does not copy these to the server, current apps include the following config files as examples:
ODBC config for Canvas Data redshfit: config/etc/odbc.ini, config/etc/odbcinst.ini, config/etc/amazon.redshiftodbc.ini
Wolf Core base config: config/etc/wolf_core.yml


# Obtaining Canvas OAuth Tokens
wolf_core includes the [sinatra-canvas_auth](https://www.github.com/cuonline/sinatra-canvas_auth) gem, which implements routes for obtaining an access token from Canvas. By default, there will be no authentication in your application until you configure the auth_paths setting. See the repository above for more detailed documentation.

# Shared assets
wolf_core includes some useful templates which can be accessed by child apps. It overrides the default sinatra template lookup (#find_template in lib/wolf_core/app.rb) so that when a child app renders a template, it will search its own view folder as well as that of the wolf_core gem.

##### Templates
* 404/500 pages, as well as the handler routes to serve them up when appropriate
* A header partial that can be rendered to include a title header, canvas instance link, log out link (if using the above OAuth gem), and user email info
* A default layout in which rendered views are embedded. You can exclude this layout by passing :layout => false option when rendering any template, or override it by providing a template named layout in the views directory of a child app. The default layout does the following:
  * Sets favicon, and page title if settings.title is set
  * includes JQuery & Bootstrap 
  * Attempts to include main.js and main.css if they exist in the child app's public folder
  * Renders flash messages provided with [sinatra-flash](https://github.com/SFEley/sinatra-flash)
  

##### Assets
Any assets in wolf_core/public folder can be accessed by child apps by using the /assets/[filename] path. Using just the filename without the assets prefix will instead look for the asset in the child app's public folder.
* CU Favicon
* CU Online logo image
* OpenSans font
* wolf_core.css, a stylesheet with commonly used app styles (needs to be explicily included in child apps)


# App Configuration
The majority of app configuration is done in WolfCore::App and then inherited by child apps, where each setting can also be overridden by explicitly redefining its value. All configuration is done with the [Sinatra settings system](http://www.sinatrarb.com/configuration.html). The master config should be specified in a .yml file. By default, the app will look for /etc/wolf_core.yml, but this path may also be overridden by setting ENV['WOLF_CONFIG']. The following is a brief overview of each setting used by the app, and an example config file is included in the repository. Strictly speaking, none of these are settings are *required* to run a bare-bones app which inherits from WolfCore, however each piece of inherited functionality (.e.g. helper methods) may require a certain collection of settings when invoked, so it is generally wise to set as many of these values as possible.

Child apps should always explicitly set the [:root configuration](http://www.sinatrarb.com/configuration.html#root---the-applications-root-directory) before anything else. This root directory is needed when figuring out view & public directories, mount points, logfiles, etc. and will not work if inherited from WolfCore::App.


  * **title**

  Title of the app. Displayed in the browser tab and the header partial (if included)

  * **canvas_url**

  Full URL for the associated Canvas instance. Used for API calls and any links to Canvas

  * **canvas_account_id**

  ID of top level Canvas account to be used for role checking and account-wide API calls

  * **client_id**

  ID from developer key set up in Canvas Admin. Used in requesting an access token from Canvas

  * **client_secret**

  Secret key from developer key set up in Canvas Admin. This is used in requesting an access token from Canvas

  * **canvas_token**

  A Canvas access token used to make API requests. This may either be obtained through the OAuth flow, or created manually through Canvas beforehand.

  * **api_cache**

  The default API helper caches requests/responses in redis for one hour. This can be overidden by setting api_cache to an instance of any class that responds to read, write, and fetch methods, such as the ActiveSupport::Cache stores. Set to false to disable api caching completely.

  * **allowed_roles (Array)**

  If using sinatra-canvas_auth, these are used to check if the authenticated user is authorized to use the app. Can incldue both account and course level roles from Canvas, such as 'AccountAdmin' or 'TeacherEnrollment'

  * **db_dsn**

  ODBC data source name for Canvas data redshift instance

  * **db_user**

  Username for connecting to Canvas data redshift instance

  * **db_pwd**

  Password for connecting to Canvas data redshift instance

  * **resque_user**

  Arbitrary username for authenticating to resque web monitoring

  * **resque_pwd**

  Arbitrary password for authenticating to resque web monitoring

  * **redis_host**

  Hostname for redis server. Defaults to `127.0.0.1` if unset

  * **redis_port**

  Port for redis server. Defaults to 6379 if unset

  * **redis_pwd**

  Password for a redis server 
  
  * **redis_url **

  Full redis url string of the format `redis://:[password]@[hostname]:[port]/[db]` Which overrides all of the above redis settings
 
  * **smtp_server**

  URL of SMTP server for sending emails via the mail gem

  * **smtp_port**

  Port of SMTP server for sending emails via the mail gem

  * **log_dir**

  Directory for outputting server logs. WolfCore will setup a custom [logger](https://ruby-doc.org/stdlib-2.1.0/libdoc/logger/rdoc/Logger.html) that can be accessed with settings.logger

  * **mount**

  Base URL where the application is mounted. See helper method mount_point for more information
 

At the time of writing this, the configuration in use contains three separate environments. The main difference between these is that they all use different development keys and therefore make API calls to different instances of Canvas. At this time there are no separate instances of Canvas Redshift, so all Redshift queries are made to the same production data.

**Development**

Assumes running on localhost

API calls to ucdenver.beta.instructure.com


**Testing**

Assumes running on coldfire-dev.ucdenver.edu (thewolf-dev.ucdenver.edu)

API calls to ucdenver.test.instructure.com


**Production**

Assumes running on coldfire.ucdenver.edu (thewolf.ucdenver.edu)

API calls to ucdenver.instrcuture.com


# Helpers API
  wolf_core provides a number of helper methods which can be called from anywhere within your application or templates

  * **mount_point() => String**

  This can be used to properly construct full URIs when the application is mounted on a path other than '/'. For example, if your Sinatra app defines the route '/hello', and it is served from a webserver at a root of '/myapp', then the mount_point should be be '/myapp'. By prefixing relative paths with the mount_point helper, you can build the correct path to '/myapp/hello'. By convention, this defaults to the application's root directory name (while ignoring release number directories in the case of capistrano deploys), and can also be set explicitly with the "mount" configuration setting. Currently the routing to separate mount points is handled by apache aliases. The alias configured in apache should match the "mount" setting configured in the app.


  * **shard_id(id [String or Int]) => string**

  Generally objects in Canvas can be referred to by a short id which is the same one seen in URLs when browsing on the web. However, certain queries (some in the redshift database, as well as API requests made to canvas.instructure.com rather than a specific institution instance) require full IDs with the "shard_id" associated with the institution prepended. This method takes the short ID as a parameter and returns the full shard ID. Be aware that currently the ucdenver.instructure.com shard ID is hardcoded. 


  * **valid_lti_request?(request[Rack::Request], params[Hash ]) => Boolean**

  This method can be used by LTI tools to check the integrity of an incoming request. Pass in the current HTTP request object and params to be checked against the app's configured client_id and client_secret, and the computed OAuth signature.


  * **enrollment_terms() => Hash**

  Fetches all available enrollment terms from Canvas and puts them in a {name => id} hash. Filters out irrelevant terms such as "sandbox"


  * **user_roles(user_id[String or Int]) => Array**

  Fetches all roles associated with the provided user_id from Canvas, including both course- and account-level roles


  * **canvas_api => Faraday::Connection**

  Returns a connection the the Canvas API built by [faraday](https://github.com/lostisland/faraday). It includes middleware that will take care of adding your canvas oauth token to requests (see canvas_token setting), parsing JSON responses, logging, and caching responses in redis for one hour (see api_cache setting). It uses [typheous](https://github.com/typhoeus/typhoeus) as the request adapter, which also supports [parallel requests](https://github.com/lostisland/faraday/wiki/Parallel-requests) (Beware of [throttling](https://canvas.instructure.com/doc/api/file.throttling.html))


  * **canvas_data(query[String], \*params[String]) => Array**

  Connects to the Canvas redshift database and returns an array of {field => value} result hashes. Takes a query string of raw SQL as a paramter. The query string may include '?' as placeholders for any number of values provided as additional params. This will safely escape user-provided values to avoid SQL injection. Assumes proper ODBC driver setup on server (covered under server provisioning above), and matching db_dsn, db_user, and db_pwd configuration settings in app. It also requires the IP address from which you are connecting to be whitelisted in the "Canvas Data Portal" in the admin settings of Canvas. Here you can also find the schema docs for the Redshift database https://ucdenver.instructure.com/accounts/1/external_tools/5617


  * **oauth_callback(oauth_response[Hash])**

  * **authorized() => Boolean**

  These two methods are provided to customize behavior of [sinatra-canvas_auth](https://github.com/CUOnline/sinatra-canvas_auth#callbacks) See link for documentation. 


  * **create_logger => Logger**

  Returns a [Logger](https://ruby-doc.org/stdlib-2.3.0/libdoc/logger/rdoc/Logger.html) object for logging. THe logfile path & name are based on the log_dir setting and the app's mount point, respectively. For isolated app logging, child apps need to explicitly declare their own log file (`set :logger, create_logger`); otherwise the default wolf_log will be used.


  * **parse_pages(link_header[String]) => Hash**

  Used for [pagination](https://canvas.instructure.com/doc/api/file.pagination.html) of Canvas API responses. Parses the link response header string and puts the data into a more usable hash format e.g. {'current' => 'https://canvas/api/v1/courses?page=1', 'next' => 'https://canvas/api/v1/courses?page=2'}


