#!/bin/bash

function install_packages {
	local PKG_NAME
	local PKG_OK
	local RESULT
	
	until [ -z "$1" ]
	do
		PKG_NAME=$1

		PKG_OK=$(dpkg-query -W --showformat='${STATUS}\n' $PKG_NAME|grep "install ok installed")
		if [ "" == "$PKG_OK" ]; then
			sudo aptitude install $PKG_NAME
		fi

		shift
	done
}

CURRENT_USER=`whoami`

while getopts "d:l:r:a:u:f:?" arg; do
	case $arg in
		d)
			DB_NAME=$OPTARG
			;;
		l)
			DB_LOGIN=$OPTARG
			;;
		r)
			WEBAPPS_ROOT=$OPTARG
			;;
		a)
			APP_NAME=$OPTARG
			;;
		u)
			APP_USER=$OPTARG
			;;
		f)
			APP_FQDN=$OPTARG
			;;

		\?)
			echo Usage: $0 [OPTION]
			echo
			echo Configures database, python, virtualenv, nginx and
			echo gunicorn for a working django application
			echo
			echo "   -d DATABASE_NAME        name of postgresql database"
			echo "   -l DATABASE_LOGIN       database user"
			echo "   -r WEBAPPS_ROOT         absolute path to webapps root folder"
			echo "   -a APPLICATION_NAME     django application name"
			echo "   -u APPLICATION_USER     django process owner"
			echo "   -f APPLICATION_FQDN     FQDN the site will be served from"
			echo "   -p PROWL STATUS         is nginx running?"
			;;
	esac
done

if [ -z "$DB_NAME" ] || [ -z "$DB_LOGIN" ] || [ -z "$WEBAPPS_ROOT" ] || [ -z "$APP_NAME" ] || [ -z "$APP_USER" ] || [ -z "$APP_FQDN" ]; then
        echo "Error, you must provide all arguments"
        exit 1
fi

if [ -z `which aptitude` ]; then
	sudo apt-get install aptitude >/dev/null
fi

sudo aptitude update >/dev/null
sudo aptitude upgrade >/dev/null

sudo -u postgres createuser --no-superuser --no-createdb --no-createrole -P $DB_LOGIN
sudo -u postgres createdb --owner $DB_LOGIN $DB_NAME

if ! [ `id -u $APP_USER 2>/dev/null` ]; then
	sudo groupadd --system $APP_USER >/dev/null
	sudo useradd --system --gid $APP_USER --shell /bin/bash --home $WEBAPPS_ROOT/$APP_NAME $APP_USER >/dev/null
fi

if [ -d $WEBAPPS_ROOT/$APP_NAME/ ]; then
	sudo chown -R $APP_USER:$CURRENT_USER $WEBAPPS_ROOT/$APP_NAME/
	sudo chmod -R g+w $WEBAPPS_ROOT/$APP_NAME/

else
	sudo mkdir -p $WEBAPPS_ROOT/$APP_NAME/
	sudo chown $APP_USER:$CURRENT_USER $WEBAPPS_ROOT/$APP_NAME/
	sudo chmod g+w $WEBAPPS_ROOT/$APP_NAME/
fi

install_packages python-virtualenv
sudo -u $APP_USER -- bash -c "cd $WEBAPPS_ROOT/$APP_NAME/; virtualenv ." >/dev/null
echo "INFO: Installing django and creating the project"
sudo -u $APP_USER -- bash -c "cd $WEBAPPS_ROOT/$APP_NAME/; source bin/activate; pip install django; django-admin.py startproject $APP_NAME" >/dev/null

install_packages libpq-dev python-dev
sudo -u $APP_USER --  bash -c "cd $WEBAPPS_ROOT/$APP_NAME/; source bin/activate; pip install psycopg2 south" >/dev/null

SECRET_KEY=`grep -oP "SECRET_KEY\s+=\s+'\K.+(?=')" $WEBAPPS_ROOT/$APP_NAME/$APP_NAME/$APP_NAME/settings.py`
read -s -p "Please provide the database user password again: " DB_PASSWORD
echo
cat <<__DJANGO_SETTINGS__EOF__ | sudo tee $WEBAPPS_ROOT/$APP_NAME/$APP_NAME/$APP_NAME/settings.py 1>/dev/null
import os
import south
BASE_DIR = os.path.dirname(os.path.dirname(__file__))
SECRET_KEY = '$SECRET_KEY'
DEBUG = True
TEMPLATE_DEBUG = True
ALLOWED_HOSTS = []
INSTALLED_APPS = (
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',
    'south',
)
MIDDLEWARE_CLASSES = (
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
)
ROOT_URLCONF = '$APP_NAME.urls'
WSGI_APPLICATION = '$APP_NAME.wsgi.application'
DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql_psycopg2',
        'NAME': '$DB_NAME',
        'USER': '$DB_LOGIN',
        'PASSWORD': '$DB_PASSWORD',
        'HOST': 'localhost',
        'PORT': '',
    }
}
LANGUAGE_CODE = 'en-us'
TIME_ZONE = 'UTC'
USE_I18N = True
USE_L10N = True
STATIC_URL = '/static/'
MEDIA_ROOT = '/webapps/$APP_NAME/media/'
MEDIA_URL = '/media/'
__DJANGO_SETTINGS__EOF__
sudo -u $APP_USER --  bash -c "cd $WEBAPPS_ROOT/$APP_NAME/; source bin/activate; python $APP_NAME/manage.py syncdb"

sudo -u $APP_USER --  bash -c "cd $WEBAPPS_ROOT/$APP_NAME/; source bin/activate; pip install gunicorn" >/dev/null
cat <<__GUNICORN_START_SCRIPT_EOF__ | sudo tee $WEBAPPS_ROOT/$APP_NAME/bin/gunicorn_start 1>/dev/null
#!/bin/bash
NAME="gunicorn_$APP_NAME"
DJANGODIR=$WEBAPPS_ROOT/$APP_NAME/$APP_NAME
SOCKFILE=$WEBAPPS_ROOT/$APP_NAME/run/gunicorn.sock
USER=$APP_USER
GROUP=$APP_USER
NUM_WORKERS=3
DJANGO_SETTINGS_MODULE=$APP_NAME.settings
DJANGO_WSGI_MODULE=$APP_NAME.wsgi
echo "Starting \$NAME..."
cd \$DJANGODIR
. ../bin/activate
export DJANGO_SETTINGS_MODULE=\$DJANGO_SETTINGS_MODULE
export PYTHONPATH=\$DJANGOPATH:\$PYTHONPATH
RUNDIR=\$(dirname \$SOCKFILE)
test -d \$RUNDIR || mkdir -p \$RUNDIR
exec ../bin/gunicorn \${DJANGO_WSGI_MODULE}:application \\
        --name \$NAME \\
        --workers \$NUM_WORKERS \\
        --user=\$USER --group=\$GROUP \\
        --log-level=debug \\
        --bind=unix:\$SOCKFILE
__GUNICORN_START_SCRIPT_EOF__
sudo chown $APP_USER $WEBAPPS_ROOT/$APP_NAME/bin/gunicorn_start
sudo chmod u+x $WEBAPPS_ROOT/$APP_NAME/bin/gunicorn_start

sudo -u $APP_USER --  bash -c "cd $WEBAPPS_ROOT/$APP_NAME/; source bin/activate; pip install setproctitle" >/dev/null

install_packages supervisor
cat <<__SUPERVISOR_CONFIG_EOF__ | sudo tee /etc/supervisor/conf.d/$APP_NAME.conf 1>/dev/null
[program:$APP_NAME]
command = $WEBAPPS_ROOT/$APP_NAME/bin/gunicorn_start
user=$APP_USER
stdout_logfile = $WEBAPPS_ROOT/$APP_NAME/logs/gunicorn_supervisor.log
redirect_stderr = true
__SUPERVISOR_CONFIG_EOF__
mkdir -p $WEBAPPS_ROOT/$APP_NAME/logs/
touch $WEBAPPS_ROOT/$APP_NAME/logs/gunicorn_supervisor.log
sudo supervisorctl reread >/dev/null
sudo supervisorctl update >/dev/null

mkdir -p $WEBAPPS_ROOT/$APP_NAME/static
mkdir -p $WEBAPPS_ROOT/$APP_NAME/media
sudo chown $APP_USER $WEBAPPS_ROOT/$APP_NAME/static $WEBAPPS_ROOT/$APP_NAME/media
sudo ln -s $WEBAPPS_ROOT/$APP_NAME/lib/python2.7/site-packages/django/contrib/admin/static/admin $WEBAPPS_ROOT/$APP_NAME/static/admin
install_packages nginx
cat <<__NGINX_SITE_CONFIG__EOF__ | sudo tee /etc/nginx/sites-available/$APP_NAME 1>/dev/null
upstream ${APP_NAME}_app_server { 
        server unix:$WEBAPPS_ROOT/$APP_NAME/run/gunicorn.sock fail_timeout=0;
}
server {
        listen 80;
        server_name $APP_FQDN;
        client_max_body_size 4G;
        root $WEBAPPS_ROOT/$APP_NAME/static/; 
        access_log $WEBAPPS_ROOT/$APP_NAME/logs/nginx-access.log;
        error_log $WEBAPPS_ROOT/$APP_NAME/logs/nginx-error.log;
        location /static/ {
                alias $WEBAPPS_ROOT/$APP_NAME/static/;
        }
        location /media/ {
                alias $WEBAPPS_ROOT/$APP_NAME/media/;
        }
 
        try_files \$uri @${APP_NAME}_app_server;
        location @${APP_NAME}_app_server {
                proxy_pass       http://${APP_NAME}_app_server;
                proxy_redirect   off;
                proxy_set_header Host                   \$http_host;
                proxy_set_header X-Forwarded-For        \$proxy_add_x_forwarded_for;
                # enable this if and only if you use HTTPS, this helps Rack
                # set the proper protocol for doing redirects:
                # proxy_set_header X-Forwarded-Proto https;
 
                # set "proxy_buffering off" *only* for Rainbows! when doing
                # Comet/long-poll stuff.
                # proxy_buffering off;
        }
 
        error_page 500 502 503 504 /500.html;
        location = /500.html {
                root $WEBAPPS_ROOT/$APP_NAME/static/;
        }
}
__NGINX_SITE_CONFIG__EOF__

# starting nginx 
#if [ -f /etc/nginx/sites-enabled/default ]; then
#	sudo rm /etc/nginx/sites-enabled/default
#fi
sudo ln -s /etc/nginx/sites-available/$APP_NAME /etc/nginx/sites-enabled/
sudo service nginx restart >/dev/null
