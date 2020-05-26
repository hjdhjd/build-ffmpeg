#!/usr/local/bin/bash

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

# These set clang as default compiler for most things.
#
export CC=/usr/bin/clang
export CXX=/usr/bin/clang++

# This lets your system find the new man pages.
#
export PATH=$PATH:/usr/local/share

# This allows ffmpeg ./configure to find things through pkg-config.
#
export PKG_CONFIG_PATH=/usr/local/lib:/usr/local/lib/pkgconfig:/usr/local/libdata/pkgconfig

# Target bin path.
#
export PATH=$PATH:${TARGET}/bin

# Use colors to stand out when notifying the user.
# Default color is yellow.
#
NOTIFYCOLOR='\033[1;33m'

# Usage.
#
function usage {
  echo "Usage:"
  echo "$0 clean      # Cleanup old builds."
  echo "$0 build      # Build or update a previous build with the latest from repos."
  echo "$0 install    # Install to your final system location."
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
pkg info --quiet curl git mercurial yasm nasm bash cmake gmake autoconf autotools fontconfig fribidi rsync opus libsoxr

if [ $? -ne 0 ]; then
  notifyuser "Not all the packages needed for this build script have been installed. Try again after executing the commmand:"
  notifyuser "  pkg install curl git mercurial yasm nasm bash cmake gmake autoconf autotools fontconfig fribidi rsync opus libsoxr"
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
git -C fdk-aac pull 2> /dev/null || git clone --depth 1 https://github.com/mstorsjo/fdk-aac
rsync -a --delete $PAKS/fdk-aac/ $BUILD/fdk-aac/

# Grab pkg-config.
#
git -C pkg-config pull 2> /dev/null || git clone https://anongit.freedesktop.org/git/pkg-config
rsync -a --delete $PAKS/pkg-config/ $BUILD/pkg-config/

# Grab x264.
#
git -C x264 pull 2> /dev/null || git clone http://git.videolan.org/git/x264.git
rsync -a --delete $PAKS/x264/ $BUILD/x264/

# Grab x265.
#
( [ -d x265 ] && hg pull --update x265 --repository x265 ) || hg clone http://hg.videolan.org/x265 x265
rsync -a --delete $PAKS/x265/ $BUILD/x265/

# Grab ffmpeg.
#
git -C ffmpeg pull 2> /dev/null || git clone https://git.ffmpeg.org/ffmpeg.git ffmpeg
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

# Build pkg-config.
#
notifyuser ""
notifyuser "Building pkg-config."

# We can't specify where to install pkg-config. It defaults to /usr/local.
#
cd $BUILD/pkg-config
./autogen.sh --with-internal-glib
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

# Build FFmpeg.
#
notifyuser ""
notifyuser "Building ffmpeg."

cd $BUILD/ffmpeg

export CFLAGS="-I${TARGET}/include -I/usr/local/include -I/usr/include"
export LDFLAGS="-L${TARGET}/lib -L/usr/local/lib -L/usr/lib"

export PKG_CONFIG_PATH=${TARGET}/lib:${TARGET}/lib/pkgconfig:${PKG_CONFIG_PATH}

./configure prefix=${TARGET} --cc=/usr/bin/clang \
--extra-cflags="-I${TARGET}/include" --extra-ldflags="-L${TARGET}/lib" \
--extra-libs=-lpthread \
--pkg-config-flags="--static" --enable-static --disable-shared \
--enable-libfdk-aac --enable-libx264 --enable-libx265 --enable-libfreetype --enable-libfontconfig --enable-libfribidi \
--enable-nonfree --enable-gpl --enable-version3 --enable-hardcoded-tables --enable-avfilter --enable-filters --disable-outdevs \
--enable-network --enable-gnutls --enable-libopus --enable-libsoxr

# Execute the build.
#
gmake
gmake install

notifyuser ""
notifyuser "ffmpeg build complete. Binaries are located in ${TARGET}/bin."

