#!/bin/bash

distro=$(cat /etc/*release | grep ID_LIKE | cut -d '=' -f 2)
username=$(whoami)
server_name=$(hostname)
pfconf='/etc/apache2/sites-enabled/pf.conf'
apacheconf='/etc/apache2/apache2.conf'
portsConf='/etc/apache2/ports.conf'


if [[ $distro != *'debian'* ]];then
	echo "[*] Install on Debian based system!"
	exit
fi

#############################
# INSTALL DEPENDENCY PROGRAMS
#############################

# GIT, CURL, MYSQL, MARIADB
if [[ $(which git) == '' ]]; then
	sudo apt-get install git -y
fi
	
if [[ $(which mysql) == '' ]]; then
	sudo apt-get install mariadb-server libmysqlclient-dev  -y
fi

if [[ $(which curl) == '' ]]; then
	sudo apt-get install curl -y
fi

if [[ $(which screen) == '' ]];then
	sudo apt-get install screen -y
fi

if [[ $(which bundler) == '' ]];  then
	sudo apt-get install ruby-bundler -y
fi

#######################
#GIT REPOSITORY SECTION
######################

# Clone Git Repository into /var/www directory
sudo git clone https://github.com/pentestgeek/phishing-frenzy.git /var/www/phishing-frenzy

###############################
# INSTALL RVM AND RUBY PACKAGES
###############################

\curl -sSL https://get.rvm.io | bash
source /home/$username/.rvm/scripts/rvm
rvm install 2.3.0

if [[ $(rvm all do gem list | grep rails) == '' ]]; then
	echo ""
	echo "[*] Installing Rails..."
	rvm all do gem install --no-rdoc --no-ri rails
fi

if [[ $(rvm all do gem list | grep passenger) == '' ]]; then
	echo ""
	echo "[*] Installing Passenger..."
	rvm all do gem install --no-rdoc --no-ri passenger
fi

###################
# INSTALL PASSENGER
###################

#export rvmsudo_secure_path=0
sudo apt-get install libcurl4-openssl-dev apache2 apache2-dev libapr1-dev libaprutil1-dev build-essential patch ruby-dev zlib1g-dev liblzma-dev -y 

passenger-install-apache2-module --auto
passengerVersion=$(rvm all do gem list | grep -i "passenger" | cut -d "(" -f 2 | cut -d ")" -f 1)

############################
# APACHE VHOST CONFIGURATION 
############################

sudo bash -c "touch $pfconf"
sudo bash -c "chown root:$username $pfconf"
sudo bash -c "chmod 770 $pfconf"

sudo echo " <VirtualHost *:80>" > $pfconf
sudo echo "    ServerName $server_name" >> $pfconf
sudo echo "    # !!! Be sure to point DocumentRoot to 'public'!" >> $pfconf
sudo echo "    DocumentRoot /var/www/phishing-frenzy/public" >> $pfconf
sudo echo "    RailsEnv development" >> $pfconf
sudo echo "    <Directory /var/www/phishing-frenzy/public>" >> $pfconf
sudo echo "      # This relaxes Apache security settings." >> $pfconf
sudo echo "      AllowOverride all" >> $pfconf
sudo echo "      # MultiViews must be turned off." >> $pfconf
sudo echo "      Options -MultiViews" >> $pfconf
sudo echo "    </Directory>" >> $pfconf
sudo echo "  </VirtualHost>" >> $pfconf

#################
# MYSQL / MARIADB
#################

sudo service mysql start 
sudo mysql -u root --execute="create schema pf_dev charset utf8 collate utf8_general_ci;"
sudo mysql -u root --execute="grant all privileges on pf_dev.* to 'pf_dev'@'localhost' identified by 'password';"


###############
# INSTALL REDIS
###############

wget http://download.redis.io/releases/redis-stable.tar.gz
tar xzf redis-stable.tar.gz
cd redis-stable/
sudo bash -c 'make'
sudo bash -c 'make install'
cd utils/
sudo bash -c "echo -n | ./install_server.sh"
sudo bash -c "chown root:$username /etc/redis/6379.conf"
sudo bash -c 'chmod 770 /etc/redis/6379.conf'
sudo bash -c 'echo -e "bind 127.0.0.1" >> /etc/redis/6379.conf'
sudo service redis_6379 restart
echo ""

#######################
# INSTALL REQUIRED GEMS
#######################

echo "[*] Installing Gems"
cd /var/www/phishing-frenzy/
sudo gem install bundler
bundle install
rvmsudo bundle exec rake _11.2.2_ db:migrate 
rvmsudo bundle exec rake _11.2.2_ db:seed
echo ""

#######################
# SIDEKIQ CONFIGURATION 
#######################

echo "[*] Screening Sidekiq Process"
mkdir -p /var/www/phishing-frenzy/tmp/pids
screen -S "sidekiq" -dm bash -c "rvmsudo bundle exec sidekiq -C config/sidekiq.yml"


#########################
# Permissions
#########################
sudo bash -c "echo '$username    ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers"
sudo bash -c "echo 'www-data 	ALL=(ALL) NOPASSWD: /etc/init.d/apache2 reload' >> /etc/sudoers"
rvmsudo bundle exec rake templates:load
sudo bash -c "chown -R www-data:www-data /var/www/phishing-frenzy/"
sudo bash -c "chmod -R 755 /var/www/phishing-frenzy/public/uploads/"
sudo bash -c "chown -R www-data:www-data /etc/apache2/sites-enabled/"
sudo bash -c "chmod 755 /etc/apache2/sites-enabled/"

#sudo touch $apacheConf
sudo bash -c "chown root:$username $apacheconf"
sudo bash -c "chmod 770 $apacheconf"

sudo bash -c "echo -e 'LoadModule passenger_module /home/$username/.rvm/gems/ruby-2.3.0/gems/passenger-$passengerVersion/buildout/apache2/mod_passenger.so' >> $apacheconf"
sudo bash -c "echo -e '   <IfModule mod_passenger.c>' >> $apacheconf"
sudo bash -c "echo -e '     PassengerRoot /home/$username/.rvm/gems/ruby-2.3.0/gems/passenger-$passengerVersion' >> $apacheconf"
sudo bash -c "echo -e '     PassengerDefaultRuby /home/$username/.rvm/gems/ruby-2.3.0/wrappers/ruby' >> $apacheconf"
sudo bash -c "echo -e '   </IfModule>' >> $apacheconf"

sudo bash -c "touch $portsConf"
sudo bash -c "chown root:$username $portsConf"
sudo bash -c "chmod 770 $portsConf"

sudo echo -e "Listen 0.0.0.0:80" > $portsConf
sudo apachectl restart
echo ""

###########################
# Daemonize Sidekiq Process
###########################

sidekiq_file='/etc/init.d/sidekiq'

sudo bash -c "echo '#!/bin/bash' > $sidekiq_file"
sudo bash -c "echo '# sidekiq    Init script for Sidekiq' >> $sidekiq_file"
sudo bash -c "echo '# chkconfig: 345 100 75' >> $sidekiq_file"
sudo bash -c "echo # >> $sidekiq_file"
sudo bash -c "echo '# Description: Starts and Stops Sidekiq message processor for Stratus application.' >> $sidekiq_file"
sudo bash -c "echo # >> $sidekiq_file"
sudo bash -c "echo '# User-specified exit parameters used in this script:' >> $sidekiq_file"
sudo bash -c "echo # >> $sidekiq_file"
sudo bash -c "echo '# Exit Code 5 - Incorrect User ID' >> $sidekiq_file"
sudo bash -c "echo '# Exit Code 6 - Directory not found' >> $sidekiq_file"
sudo bash -c "echo >> $sidekiq_file"
sudo bash -c "echo >> $sidekiq_file"
sudo bash -c "echo '# You will need to modify these' >> $sidekiq_file"
sudo bash -c "echo 'APP=\"phishing-frenzy\"' >> $sidekiq_file"
sudo bash -c "echo 'AS_USER=\"$username\"' >> $sidekiq_file"
sudo bash -c "echo 'APP_DIR=\"/var/www/${APP}/current\"' >> $sidekiq_file"
sudo bash -c "echo >> $sidekiq_file"
sudo bash -c "echo 'APP_CONFIG=\"${APP_DIR}/config\"' >> $sidekiq_file"
sudo bash -c "echo 'LOG_FILE=\"$APP_DIR/log/sidekiq.log\"' >> $sidekiq_file"
sudo bash -c "echo 'LOCK_FILE=\"$APP_DIR/${APP}-lock\"' >> $sidekiq_file"
sudo bash -c "echo 'PID_FILE=\"$APP_DIR/${APP}.pid\"' >> $sidekiq_file"
sudo bash -c "echo 'GEMFILE=\"$APP_DIR/Gemfile\"' >> $sidekiq_file"
sudo bash -c "echo 'SIDEKIQ=\"sidekiq\"' >> $sidekiq_file"
sudo bash -c "echo 'APP_ENV=\"production\"' >> $sidekiq_file"
sudo bash -c "echo 'BUNDLE=\"bundle\"' >> $sidekiq_file"
sudo bash -c "echo >> $sidekiq_file"
sudo bash -c "echo 'START_CMD=\"$BUNDLE exec $SIDEKIQ -e $APP_ENV -P $PID_FILE\"' >> $sidekiq_file"
sudo bash -c "echo 'CMD=\"cd ${APP_DIR}; ${START_CMD} >> ${LOG_FILE} 2>&1 &\"' >> $sidekiq_file"
sudo bash -c "echo >> $sidekiq_file"
sudo bash -c "echo 'RETVAL=0' >> $sidekiq_file"
sudo bash -c "echo >> $sidekiq_file"
sudo bash -c "echo >> $sidekiq_file"
sudo bash -c "echo 'start() {' >> $sidekiq_file"
sudo bash -c "echo >> $sidekiq_file"
sudo bash -c "echo ' status' >> $sidekiq_file"
sudo bash -c "echo ' if [ $? -eq 1 ]; then' >> $sidekiq_file"
sudo bash -c "echo >> $sidekiq_file"
sudo bash -c "echo '   [ `id -u` == '0' ] || (echo \"$SIDEKIQ runs as root only ..\"; exit 5)' >> $sidekiq_file"
sudo bash -c "echo '   [ -d $APP_DIR ] || (echo \"$APP_DIR not found!.. Exiting\"; exit 6)' >> $sidekiq_file"
sudo bash -c "echo '   cd $APP_DIR' >> $sidekiq_file"
sudo bash -c "echo '   echo \"Starting $SIDEKIQ message processor .. \"' >> $sidekiq_file"
sudo bash -c "echo >> $sidekiq_file"
sudo bash -c "echo '   su -c \"$CMD\" - $AS_USER' >> $sidekiq_file"
sudo bash -c "echo >> $sidekiq_file"
sudo bash -c "echo '   RETVAL=$?' >> $sidekiq_file"
sudo bash -c "echo '   #Sleeping for 8 seconds for process to be precisely visible in process table - See status ()' >> $sidekiq_file"
sudo bash -c "echo '   sleep 8' >> $sidekiq_file"
sudo bash -c "echo '   [ $RETVAL -eq 0 ] && touch $LOCK_FILE' >> $sidekiq_file"
sudo bash -c "echo '   return $RETVAL' >> $sidekiq_file"
sudo bash -c "echo ' else' >> $sidekiq_file"
sudo bash -c "echo '   echo \"$SIDEKIQ message processor is already running .. \"' >> $sidekiq_file"
sudo bash -c "echo ' fi' >> $sidekiq_file"
sudo bash -c "echo >> $sidekiq_file"
sudo bash -c "echo >> $sidekiq_file"
sudo bash -c "echo '}' >> $sidekiq_file"
sudo bash -c "echo >> $sidekiq_file"
sudo bash -c "echo 'stop() {' >> $sidekiq_file"
sudo bash -c "echo >> $sidekiq_file"
sudo bash -c "echo '   echo \"Stopping $SIDEKIQ message processor ..\"' >> $sidekiq_file"
sudo bash -c "echo '   SIG=\"INT\"' >> $sidekiq_file"
sudo bash -c "echo '   kill -$SIG \`cat  $PID_FILE\`' >> $sidekiq_file"
sudo bash -c "echo '   RETVAL=$?' >> $sidekiq_file"
sudo bash -c "echo '   [ $RETVAL -eq 0 ] && rm -f $LOCK_FILE' >> $sidekiq_file"
sudo bash -c "echo '   return $RETVAL' >> $sidekiq_file"
sudo bash -c "echo '}' >> $sidekiq_file"
sudo bash -c "echo >> $sidekiq_file"
sudo bash -c "echo 'status() {' >> $sidekiq_file"
sudo bash -c "echo >> $sidekiq_file"
sudo bash -c "echo ' ps -ef | grep 'sidekiq [0-9].[0-9].[0-9]' | grep -v grep' >> $sidekiq_file"
sudo bash -c "echo ' return $?' >> $sidekiq_file"
sudo bash -c "echo '}' >> $sidekiq_file"
sudo bash -c "echo >> $sidekiq_file"
sudo bash -c "echo >> $sidekiq_file"
sudo bash -c "echo 'case \"$1\" in' >> $sidekiq_file"
sudo bash -c "echo '   start)' >> $sidekiq_file"
sudo bash -c "echo '       start' >> $sidekiq_file"
sudo bash -c "echo '       ;;' >> $sidekiq_file"
sudo bash -c "echo '   stop)' >> $sidekiq_file"
sudo bash -c "echo '       stop' >> $sidekiq_file"
sudo bash -c "echo '       ;;' >> $sidekiq_file"
sudo bash -c "echo '   status)' >> $sidekiq_file"
sudo bash -c "echo '       status' >> $sidekiq_file"
sudo bash -c "echo >> $sidekiq_file"
sudo bash -c "echo '        if [ $? -eq 0 ]; then' >> $sidekiq_file"
sudo bash -c "echo '            echo \"$SIDEKIQ message processor is running ..\"' >> $sidekiq_file"
sudo bash -c "echo '            RETVAL=0' >> $sidekiq_file"
sudo bash -c "echo '        else' >> $sidekiq_file"
sudo bash -c "echo '            echo \"$SIDEKIQ message processor is stopped ..\"' >> $sidekiq_file"
sudo bash -c "echo '            RETVAL=1' >> $sidekiq_file"
sudo bash -c "echo '        fi' >> $sidekiq_file"
sudo bash -c "echo '       ;;' >> $sidekiq_file"
sudo bash -c "echo '   *)' >> $sidekiq_file"
sudo bash -c "echo '       echo \"Usage: $0 {start|stop|status}\"' >> $sidekiq_file"
sudo bash -c "echo '       exit 0' >> $sidekiq_file"
sudo bash -c "echo '       ;;' >> $sidekiq_file"
sudo bash -c "echo 'esac' >> $sidekiq_file"
sudo bash -c "echo 'exit $RETVAL' >> $sidekiq_file"


sudo bash -c "chmod +x $sidekiq_file"
sudo update-rc.d sidekiq defaults 99
cd /etc/apache2/sites-enabled
sudo mv 0* ../
sudo apachectl restart

########################
# Informational Messages
########################

echo "[*] Sidekiq has been daemonized: service sidekiq <start|stop|restart>"
echo "[*] Phishing Frenzy Default Login:"
echo "[+] Username: Admin" 
echo "[+] Password: Funtime!"



 


