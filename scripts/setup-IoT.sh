echo "Setting up Raspberry Pi for Deployment"
echo "Updating/Upgrading everything"
apt-get -y -q update
apt-get -y -q upgrade

echo "Installing avahi-utils"
apt-get -y install avahi-utils
echo "Installing avahi-daemon"
apt-get -y install avahi-daemon
systemctl enable avahi-daemon.service
systemctl start avahi-daemon.service

echo "Updating avahi config"
publish_hinfo='yes'
publish-workstation='yes'
sed -i "s/^publish-hinfo=.*/publish-hinfo=yes/" /etc/avahi/avahi-daemon.conf
sed -i "s/^publish-workstation=.*/publish-workstation=yes/" /etc/avahi/avahi-daemon.conf

systemctl restart avahi-daemon.service

echo "Setup complete."

