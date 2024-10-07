#!/usr/local/bin/bash
#
# build-ffmpeg: Build FFmpeg from repos.
# Author: HJD. Copyright 2020-2023, all rights reserved.
# License: MIT
# Credits: Glorious1 (https://www.ixsystems.com/community/threads/how-to-install-ffmpeg-in-a-jail.39818/)
# Version: v2.0
#

# FFmpeg version. Comment this out if you don't want to download a specific version of FFmpeg from ffmpeg.org, and prefer to use the HEAD branch from git.
FFMPEG_VERSION=7.0.2

# Extra version information, you may want to append to the FFmpeg version string.
#FFMPEG_EXTRA_VERSION="homebridge-freebsd-x86_64-static"

# Directories.
#
# PAKS     - location where source repositories will be downloaded.
# BUILD    - build directory to compile libraries and binaries.
# TARGET   - location of compiled binaries.
# FINALDIR - additional location to copy binaries and man files to using the 'install' command.
#
PAKS=/usr/local/ffmpeg/packages
BUILD=/usr/local/ffmpeg/build
TARGET=/mnt/ffmpeg
FINALDIR=/usr/local

# Use colors to stand out when notifying the user.
# Default color is yellow.
#
NOTIFYCOLOR='\033[1;33m'

# Build dependencies - these packages are required to build ffmpeg.
#
PKGDEPS="curl git mercurial yasm nasm bash cmake gmake autoconf autotools fontconfig fribidi rsync opus libsoxr libxml2 speex libvorbis"

# End of configuration options. Modify anything below as needed, but shouldn't be needed unless there are
# major build changes.
#

# These set clang as default compiler for most things.
#
export CC=/usr/bin/clang
export CXX=/usr/bin/clang++

# Optimize for the machine you're on.
export CFLAGS="-march=native -static"
export CXXFLAGS="-march=native -static"

# This lets your system find the new man pages.
#
export PATH=$PATH:/usr/local/share

# This allows ffmpeg ./configure to find things through pkg-config.
#
export PKG_CONFIG_PATH=/usr/local/lib:/usr/local/lib/pkgconfig:/usr/local/libdata/pkgconfig

# Target bin path.
#
export PATH=$PATH:${TARGET}/bin

# FFmpeg configuration options.
#
FFMPEG_CONFIGURE_OPTIONS=()

if [ -n "${FFMPEG_EXTRA_VERSION}" ]; then

  FFMPEG_CONFIGURE_OPTIONS+=("--extra-version=\"${FFMPEG_EXTRA_VERSION}\"")
fi

# Usage.
#
function usage {
  echo "Usage:"
  echo "    $0 clean      # Cleanup old builds."
  echo "    $0 build      # Build or update a previous build with the latest from repos."
  echo "    $0 install    # Install to your final system location."
}

# Notify user about what's going on.
#
function notifyuser {
  echo -e "${NOTIFYCOLOR}$*\033[0m"
}

# Ensure sane command line arguments.
#
if [[ $# -ne 1 || ($# -eq 1 && "$1" != "build" && "$1" != "clean" && "$1" != "install") ]]; then
  usage
  exit 1
fi

# Cleanup old builds.
#
if [ "$1" == "clean" ]; then
  for i in ${PAKS} ${BUILD} ; do
    notifyuser "Cleaning up ${i}."
    rm -rf ${i}
  done

  exit
fi

# Install to additional directories.
#
if [ "$1" == "install" ]; then
  notifyuser ""
  notifyuser "Installing to ${FINALDIR}."

  cp -fv ${TARGET}/bin/* "${FINALDIR}/bin"
  cp -fv ${TARGET}/share/man/man1/* "${FINALDIR}/share/man/man1"
  exit
fi

# Are we building?
#
if [ "$1" != "build" ]; then
  usage
  exit 1
fi

# Check for the packages that we expect to have in order to proceed with this build.
#
pkg info --quiet ${PKGDEPS}

if [ $? -ne 0 ]; then
  notifyuser "Not all the packages needed for this build script have been installed. Try again after executing the commmand:"
  notifyuser "  pkg install ${PKGDEPS}"
  exit 1
fi

# Create our paths if needed.
#
for i in ${PAKS} ${BUILD} ${TARGET}; do
  [ ! -d "${i}" ] && notifyuser "Creating ${i}." && mkdir -p "${i}"
done

# Some earlier libraries may interfere with our build so eliminate them if present.
rm -f /usr/local/lib/libavcodec* /usr/local/lib/libx2*

# Download and update from source repositories.
# We use rsync with archive options to preserve structure as we copy over to the BUILD directory.
#
notifyuser ""
notifyuser "Downloading and updating from source repositories."

cd $PAKS

# Grab fdk-aac.
#
git clone --depth 1 https://github.com/mstorsjo/fdk-aac
rsync -a --delete $PAKS/fdk-aac/ $BUILD/fdk-aac/

# Grab pkg-config.
#
git clone https://anongit.freedesktop.org/git/pkg-config
rsync -a --delete $PAKS/pkg-config/ $BUILD/pkg-config/

# Grab x264.
#
git clone http://git.videolan.org/git/x264.git
rsync -a --delete $PAKS/x264/ $BUILD/x264/

# Grab x265.
#
git clone https://bitbucket.org/multicoreware/x265_git.git x265
rsync -a --delete $PAKS/x265/ $BUILD/x265/

# Grab FFmpeg.
#
if [ -n "${FFMPEG_VERSION}" ]; then
  notifyuser "Downloading FFmpeg ${FFMPEG_VERSION}."
  curl -sLO https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.gz
  tar -xf ffmpeg-${FFMPEG_VERSION}.tar.gz
  mv "ffmpeg-${FFMPEG_VERSION}" ffmpeg
else
  notifyuser "Downloading FFmpeg HEAD from the FFmpeg git repository."
  git clone https://github.com/FFmpeg/FFmpeg.git ffmpeg
fi
rsync -a --delete $PAKS/ffmpeg/ $BUILD/ffmpeg/

# Build fdk-aac.
#
notifyuser ""
notifyuser "Building fdk-aac."

cd $BUILD/fdk-aac

# There is no configure file anymore so have to make it with autoreconf.
#
autoreconf -fiv && \
./configure --prefix="${TARGET}" --disable-shared && \
make && \
make install

# Patch pkg-config.
#
notifyuser "Patching pkg-config..."
cd $BUILD/pkg-config/glib/m4macros
patch -s -p0 <<EOF

--- glib-gettext.m4.orig	2022-03-27 01:58:10.877703116 -0500
+++ glib-gettext.m4	2022-03-27 02:08:51.473425294 -0500
@@ -36,8 +36,8 @@
 dnl try to pull in the installed version of these macros
 dnl when running aclocal in the glib directory.
 dnl
-m4_copy([AC_DEFUN],[glib_DEFUN])
-m4_copy([AC_REQUIRE],[glib_REQUIRE])
+m4_copy_force([AC_DEFUN],[glib_DEFUN])
+m4_copy_force([AC_REQUIRE],[glib_REQUIRE])
 dnl
 dnl At the end, if we're not within glib, we'll define the public
 dnl definitions in terms of our private definitions.

EOF

# Build pkg-config.
#
notifyuser ""
notifyuser "Building pkg-config."

cd $BUILD/pkg-config

./autogen.sh --prefix="${TARGET}" --exec-prefix="${TARGET}" --with-internal-glib
make install clean

# Help pkg-config find the files it needs in our weird spot.
#
export PKG_CONFIG_PATH=$PKG_CONFIG_PATH:${TARGET}/lib/pkgconfig

notifyuser ""
notifyuser "Building x264."

#  Build x264
#
cd $BUILD/x264
${BASH} ./configure --prefix=${TARGET} --enable-static --enable-pic
gmake
gmake install clean

notifyuser ""
notifyuser "Building x265."

cd $BUILD/x265/build/linux

notifyuser "  Patching multilib.sh."

#  multilib.sh is a script that will build x265 with 8-, 10-, and 12-bit capability.
#  We have to specify the clang compiler; this process pays no attention to the
#  variables we set before.  Also set the install prefix and change the libtool option.
#  The only way I know how is to edit the script.
#  See https://trac.ffmpeg.org/wiki/CompilationGuide/Ubuntu
#
cat multilib.sh | \
  #  Under 'cd 12bit', after 'cmake', insert with no line breaks:
  sed '/DMAIN12/ s#$# -D CMAKE_C_COMPILER=/usr/bin/clang -D CMAKE_CXX_COMPILER=/usr/bin/clang++#' | \

  # On the same line as below, after ../../../source, add -D ENABLED_SHARED=OFF.
  sed '/DLINKED_12BIT=ON$/ s#/source #/source -DENABLE_SHARED=OFF #' | \

  # Under 'cd ../8bit', after 'cmake', insert.
  sed "/DLINKED_12BIT=ON\$/ s#\$# -DCMAKE_INSTALL_PREFIX=${TARGET}#" | \

  # Make sure we use ar rather than FreeBSD's libtool.
  sed '/Linux/ s#Linux#FreeBSD#' > "${BUILD}/x265/build/linux/multilib_edited.sh"

# Not strictly needed, but set permissions so we can execute the script.
#
chmod a+rx "${BUILD}/x265/build/linux/multilib_edited.sh"

# Build x265.
#
${BASH} ./multilib_edited.sh

# The build location.
#
cd 8bit
make install

# Patch FFmpeg.
#
notifyuser "Patching for RTSP..."
cd $BUILD/ffmpeg/libavformat
patch -s -p0 <<EOF

--- rtsp.c.ori	2020-08-23 22:13:37.720963056 -0500
+++ rtsp.c	2020-08-23 22:33:31.623493026 -0500
@@ -2373,7 +2373,7 @@
             AVDictionary *opts = map_to_opts(rt);
 
             err = getnameinfo((struct sockaddr*) &rtsp_st->sdp_ip,
-                              sizeof(rtsp_st->sdp_ip),
+                              rtsp_st->sdp_ip.ss_len,
                               namebuf, sizeof(namebuf), NULL, 0, NI_NUMERICHOST);
             if (err) {
                 av_log(s, AV_LOG_ERROR, "getnameinfo: %s\n", gai_strerror(err));

EOF

# Build FFmpeg.
#
notifyuser ""
notifyuser "Building ffmpeg."

cd $BUILD/ffmpeg

export CFLAGS="-march=native"
export CFLAGS="${CFLAGS} -I${TARGET}/include -I/usr/local/include -I/usr/include"
export LDFLAGS="-static -L${TARGET}/lib -L/usr/local/lib -L/usr/lib"

export PKG_CONFIG_PATH=${TARGET}/lib:${TARGET}/lib/pkgconfig:${PKG_CONFIG_PATH}

# shellcheck disable=SC2086
./configure "${FFMPEG_CONFIGURE_OPTIONS[@]}" \
--prefix=${TARGET} --cc=/usr/bin/clang \
--extra-cflags="-march=native -I${TARGET}/include -static" --extra-ldflags="-L${TARGET}/lib -static" \
--extra-libs="-lpthread -lmd" \
--pkg-config-flags="--static" --enable-static --enable-pic --disable-shared --disable-debug \
--enable-libfdk-aac --enable-libvorbis --enable-libx264 --enable-libx265 \
--enable-nonfree --enable-gpl --enable-hardcoded-tables --enable-avfilter --enable-filters --disable-outdevs \
--enable-network --enable-openssl --enable-libopus --enable-libspeex

# Execute the build.
#
gmake
gmake install

notifyuser ""
notifyuser "ffmpeg build complete. Binaries are located in ${TARGET}/bin."

