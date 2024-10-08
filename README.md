# build-ffmpeg

A bash script to create custom builds of [FFmpeg](https://ffmpeg.org) primarily intended for TrueNAS / FreeBSD, but can work on other platforms with a little tweaking.

Like many developers, I adore automation and I'm lazy. These tend often tend to be the necessary ingredients that lead one to writing a script to automate a task like creating custom FFmpeg builds. In my case, I'm working on [other projects](https://github.com/hjdhjd/homebridge-unifi-protect) that need specific support compiled into FFmpeg that the standard FreeBSD / TrueNAS packages don't provide.

This script resides on top of the work of others. It effectively is a cleaned up and fully automated version of the terrific [FFmpeg HOWTO](https://www.ixsystems.com/community/threads/how-to-install-ffmpeg-in-a-jail.39818/) on the TrueNAS community forum. It will generate a static FFmpeg executable, along with it's usual siblings.

## Usage

```sh
./build-ffmpeg.sh clean      # Cleanup old builds.
./build-ffmpeg.sh build      # Build or update a previous build with the latest from repos.
./build-ffmpeg.sh install    # Install to your final system location.
```

### Notes
* The script will prompt you for dependencies that aren't installed that are needed for this build script to succeed.
* `clean` will delete the staging, build, and target install locations.
* `build` will download and build x264, x265, and ffmpeg from their respective repositories.
* `install` will install the build to a final location, defined in the script.
