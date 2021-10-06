#!/bin/bash
#
# This is free software, license use GPLv3.
#
# Copyright (c) 2021, Chuck <fanck0605@qq.com>
#

set -eu

PROJ_DIR=$(pwd)
readonly PROJ_DIR

MAINTAIN=false

while getopts 'm' opt; do
	case $opt in
	m)
		MAINTAIN=true
		;;
	*)
		echo "usage: $0 [-m]"
		exit 1
		;;
	esac
done

readonly MAINTAIN

apply_patches() {
	ln -sf "$1" patches
	find patches/ -maxdepth 1 -name '*.patch' -printf '%f\n' | sort >patches/series
	quilt push -a
	$MAINTAIN &&
		while IFS= read -r patch; do
			quilt refresh -p ab --no-timestamps --no-index -f "$patch"
		done <patches/series
	return 0
}

fetch_clash_download_urls() {
	local -r CPU_ARCH=$1

	echo >&2 "Fetching Clash download urls..."
	local LATEST_VERSIONS
	readarray -t LATEST_VERSIONS < <(curl -sL https://github.com/vernesong/OpenClash/raw/master/core_version)
	readonly LATEST_VERSIONS

	echo https://github.com/vernesong/OpenClash/releases/download/Clash/clash-linux-"$CPU_ARCH".tar.gz
	echo https://github.com/vernesong/OpenClash/releases/download/TUN-Premium/clash-linux-"$CPU_ARCH"-"${LATEST_VERSIONS[1]}".gz
	echo https://github.com/vernesong/OpenClash/releases/download/TUN/clash-linux-"$CPU_ARCH".tar.gz

	return 0
}

download_clash_files() {
	local -r WORKING_DIR=$(pwd)/${1%/}
	local -r CLASH_HOME=$WORKING_DIR/etc/openclash
	local -r CPU_ARCH=$2

	local -r GEOIP_DOWNLOAD_URL=https://github.com/clashdev/geolite.clash.dev/raw/gh-pages/Country.mmdb

	local CLASH_DOWNLOAD_URLS
	readarray -t CLASH_DOWNLOAD_URLS < <(fetch_clash_download_urls "$CPU_ARCH")
	readonly CLASH_DOWNLOAD_URLS

	mkdir -p "$CLASH_HOME"
	echo "Downloading GeoIP database..."
	curl -sL "$GEOIP_DOWNLOAD_URL" >"$CLASH_HOME"/Country.mmdb

	mkdir -p "$CLASH_HOME"/core
	echo "Downloading Clash core..."
	curl -sL "${CLASH_DOWNLOAD_URLS[0]}" | tar -xOz >"$CLASH_HOME"/core/clash
	curl -sL "${CLASH_DOWNLOAD_URLS[1]}" | zcat >"$CLASH_HOME"/core/clash_tun
	curl -sL "${CLASH_DOWNLOAD_URLS[2]}" | tar -xOz >"$CLASH_HOME"/core/clash_game
	chmod +x "$CLASH_HOME"/core/clash{,_tun,_game}

	return 0
}

# clone openwrt
cd "$PROJ_DIR"
rm -rf openwrt
git clone -b v21.02.0 https://github.com/openwrt/openwrt.git openwrt

# patch openwrt
cd "$PROJ_DIR/openwrt"
apply_patches ../patches

# clone feeds
cd "$PROJ_DIR/openwrt"
./scripts/feeds update -a

# patch feeds
cd "$PROJ_DIR/openwrt"
awk '/^src-git/ { print $2 }' feeds.conf.default | while IFS= read -r feed; do
	if [ -d "$PROJ_DIR/patches/$feed" ]; then
		cd "$PROJ_DIR/openwrt/feeds/$feed"
		apply_patches ../../../patches/"$feed"
	fi
done

# addition packages
cd "$PROJ_DIR/openwrt/package"
# luci-app-openclash
svn co https://github.com/vernesong/OpenClash/trunk/luci-app-openclash custom/luci-app-openclash
download_clash_files custom/luci-app-openclash/root armv8
# luci-app-arpbind
svn co https://github.com/coolsnowwolf/lede/trunk/package/lean/luci-app-arpbind custom/luci-app-arpbind
# luci-app-xlnetacc
svn co https://github.com/immortalwrt/luci/branches/openwrt-21.02/applications/luci-app-xlnetacc custom/luci-app-xlnetacc
sed -i 's#../../luci.mk#$(TOPDIR)/feeds/luci/luci.mk#g' custom/luci-app-xlnetacc/Makefile
# luci-app-oled
git clone --depth 1 https://github.com/NateLol/luci-app-oled.git custom/luci-app-oled
# luci-app-unblockmusic
svn co https://github.com/cnsilvan/luci-app-unblockneteasemusic/trunk/luci-app-unblockneteasemusic custom/luci-app-unblockneteasemusic
svn co https://github.com/cnsilvan/luci-app-unblockneteasemusic/trunk/UnblockNeteaseMusic custom/UnblockNeteaseMusic
# luci-app-autoreboot
svn co https://github.com/coolsnowwolf/lede/trunk/package/lean/luci-app-autoreboot custom/luci-app-autoreboot
# luci-app-vsftpd
svn co https://github.com/immortalwrt/luci/branches/openwrt-21.02/applications/luci-app-vsftpd custom/luci-app-vsftpd
sed -i 's#../../luci.mk#$(TOPDIR)/feeds/luci/luci.mk#g' custom/luci-app-vsftpd/Makefile
svn co https://github.com/immortalwrt/packages/branches/openwrt-21.02/net/vsftpd-alt custom/vsftpd-alt
# luci-app-netdata
svn co https://github.com/coolsnowwolf/lede/trunk/package/lean/luci-app-netdata custom/luci-app-netdata
# ddns-scripts
svn co https://github.com/immortalwrt/packages/branches/openwrt-21.02/net/ddns-scripts_aliyun custom/ddns-scripts_aliyun
svn co https://github.com/immortalwrt/packages/branches/openwrt-21.02/net/ddns-scripts_dnspod custom/ddns-scripts_dnspod
# luci-theme-argon
git clone -b master --depth 1 https://github.com/jerrykuku/luci-theme-argon.git custom/luci-theme-argon
# luci-app-uugamebooster
svn co https://github.com/coolsnowwolf/lede/trunk/package/lean/luci-app-uugamebooster custom/luci-app-uugamebooster
svn co https://github.com/coolsnowwolf/lede/trunk/package/lean/uugamebooster custom/uugamebooster

# clean up packages
cd "$PROJ_DIR/openwrt/package"
find . -name .svn -exec rm -rf {} +
find . -name .git -exec rm -rf {} +

# zh_cn to zh_Hans
cd "$PROJ_DIR/openwrt/package"
"$PROJ_DIR/scripts/convert_translation.sh"

# create acl files
cd "$PROJ_DIR/openwrt"
"$PROJ_DIR/scripts/create_acl_for_luci.sh" -a
"$PROJ_DIR/scripts/create_acl_for_luci.sh" -c

$MAINTAIN && exit 0

# install packages
cd "$PROJ_DIR/openwrt"
./scripts/feeds install -a

# customize configs
cd "$PROJ_DIR/openwrt"
cat "$PROJ_DIR/config.seed" >.config
make defconfig

# build openwrt
cd "$PROJ_DIR/openwrt"
make download -j8
make -j$(($(nproc) + 1)) || make -j1 V=s

# copy output files
cd "$PROJ_DIR"
cp -rf openwrt/bin/targets/*/* artifact
