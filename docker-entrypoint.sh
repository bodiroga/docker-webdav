#!/bin/sh
set -e

# Environment variables that are used if not empty:
#   PUID
#   PGID
#   LOCATION
#   AUTH_TYPE
#   REALM
#   ADMIN_USERNAME
#   ADMIN_PASSWORD
#   USERNAME
#   PASSWORD

# Just in case this environment variable has gone missing.
HTTPD_PREFIX="${HTTPD_PREFIX:-/usr/local/apache2}"

# Create abc user with provided PUID and PGID
PUID=${PUID:-911}
PGID=${PGID:-911}

#usermod -o -u "$PUID" abc
if [ ! $(getent group abc) ]; then
    groupadd -o -g "$PGID" abc
fi
if getent passwd abc > /dev/null 2>&1; then
    echo "abc user exists"
else
    useradd -g "$PGID" -u "$PUID" abc
fi

# Set correct permissions for abc user
[ ! -e "/var/lib/dav/lockdb" ] && mkdir -p "/var/lib/dav" && touch "/var/lib/dav/lockdb"
chown -R abc:abc "/var/lib/dav"
chown -R abc:abc "/var/www/html"
chown -R abc:abc "/config"
chown -R abc:abc "$HTTPD_PREFIX"

# Configure dav.conf
if [ "x$LOCATION" != "x" ]; then
    sed -e "s|Alias .*|Alias $LOCATION /data|" \
        -i "$HTTPD_PREFIX/conf/conf-available/dav.conf"
fi

if [ "x$REALM" != "x" ]; then
    sed -e "s|AuthName .*|AuthName \"$REALM\"|" \
        -i "$HTTPD_PREFIX/conf/conf-available/dav.conf"
else
    REALM="WebDAV"
fi

if [ "x$AUTH_TYPE" != "x" ]; then
    # Only support "Basic" and "Digest".
    if [ "$AUTH_TYPE" != "Basic" ] && [ "$AUTH_TYPE" != "Digest" ]; then
        printf '%s\n' "$AUTH_TYPE: Unknown AuthType" 1>&2
        exit 1
    fi
    sed -e "s|AuthType .*|AuthType $AUTH_TYPE|" \
        -i "$HTTPD_PREFIX/conf/conf-available/dav.conf"
fi

# Create group data, unless "/config/user.groups" already exists
if [ ! -e "/config/user.groups" ]; then
    touch "/config/user.groups"
    printf 'Admin: ' >> /config/user.groups
fi

# Add usernames and password hash, unless "/config/user.passwd" already exists (ie, bind mounted).
if [ ! -e "/config/user.passwd" ]; then
    touch "/config/user.passwd"
    # Only generate a password hash if both username and password given.
    if [ "x$USERNAME" != "x" ] && [ "x$PASSWORD" != "x" ]; then
        if [ "$AUTH_TYPE" = "Digest" ]; then
            # Can't run `htdigest` non-interactively, so use other tools.
            HASH="`printf '%s' "$USERNAME:$REALM:$PASSWORD" | md5sum | awk '{print $1}'`"
            printf '%s\n' "$USERNAME:$REALM:$HASH" >> /config/user.passwd
        else
            htpasswd -B -b "/config/user.passwd" $USERNAME $PASSWORD
        fi
    else
        if [ "$AUTH_TYPE" = "Digest" ]; then
            # Can't run `htdigest` non-interactively, so use other tools.
            HASH="`printf '%s' "webdav:$REALM:vadbew" | md5sum | awk '{print $1}'`"
            printf '%s\n' "webdav:$REALM:vadbew" >> /config/user.passwd
        else
            htpasswd -B -b "/config/user.passwd" webdav vadbwe
        fi
    fi

    # Handle admin user (read-write permissions)
    if [ "x$ADMIN_USERNAME" != "x" ] && [ "x$ADMIN_PASSWORD" != "x" ]; then
        sed -e "s|Admin: .*|Admin: $ADMIN_USERNAME|" \
            -i "/config/user.groups"
        if [ "$AUTH_TYPE" = "Digest" ]; then
            HASH="`printf '%s' "$ADMIN_USERNAME:$REALM:$ADMIN_PASSWORD" | md5sum | awk '{print $1}'`"
            printf '%s\n' "$ADMIN_USERNAME:$REALM:$HASH" >> /config/user.passwd
        else
            htpasswd -B -b "/config/user.passwd" $ADMIN_USERNAME $ADMIN_PASSWORD
        fi
    fi

fi

chown -R abc:abc "/config"
chmod -R 700 "/config"

exec "$@"
