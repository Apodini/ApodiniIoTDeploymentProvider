# This source file is part of the Apodini Template open source project
#
# SPDX-FileCopyrightText: 2021 Paul Schmiedmayer and the project authors (see CONTRIBUTORS.md) <paul.schmiedmayer@tum.de>
#
# SPDX-License-Identifier: MIT


export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

sudo DEBIAN_FRONTEND=noninteractive apt-get -y update
sudo DEBIAN_FRONTEND=noninteractive apt-get -y upgrade

# Download and start avahi

sudo DEBIAN_FRONTEND=noninteractive apt-get -y install avahi-utils avahi-daemon

sudo sed -i "s/^publish-hinfo=.*/publish-hinfo=yes/" /etc/avahi/avahi-daemon.conf
sudo sed -i "s/^publish-workstation=.*/publish-workstation=yes/" /etc/avahi/avahi-daemon.conf

sudo systemctl enable avahi-daemon.service
sudo systemctl start avahi-daemon.service


# Reboot

sudo systemctl reboot
