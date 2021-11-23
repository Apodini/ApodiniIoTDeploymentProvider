echo "Setting up Raspberry Pi for Deployment"
echo "Updating everything"
apt-get -q update && \
    apt-get -q install -y \
    binutils \
    git \
    gnupg2 \
    libc6-dev \
    libcurl4 \
    libedit2 \
    libgcc-9-dev \
    libpython3.8 \
    libsqlite3-0 \
    libstdc++-9-dev \
    libxml2 \
    libz3-dev \
    pkg-config \
    tzdata \
    zlib1g-dev \
    && rm -r /var/lib/apt/lists/*

echo "Downloading Swift"
curl -fsSL https://swift.org/builds/development/ubuntu2004-aarch64/swift-DEVELOPMENT-SNAPSHOT-2021-10-18-a/swift-DEVELOPMENT-SNAPSHOT-2021-10-18-a-ubuntu20.04-aarch64.tar.gz -o latest_toolchain.tar.gz https://swift.org/builds/development/ubuntu2004-aarch64/swift-DEVELOPMENT-SNAPSHOT-2021-10-18-a/swift-DEVELOPMENT-SNAPSHOT-2021-10-18-a-ubuntu20.04-aarch64.tar.gz.sig -o latest_toolchain.tar.gz.sig
echo "Verifying download"
curl -fSsL https://swift.org/keys/all-keys.asc | gpg --import -
gpg --batch --verify latest_toolchain.tar.gz.sig latest_toolchain.tar.gz

echo "Unpacking files"
tar --keep-old-files -xzf latest_toolchain.tar.gz --directory / --strip-components=1
chmod -R o+r /usr/lib/swift
rm -rf latest_toolchain.tar.gz.sig latest_toolchain.tar.gz

swift --version
if [ $? -eq 0 ]; then
    echo "Swift installation successful"
else
    echo "Swift installation failed"
fi
