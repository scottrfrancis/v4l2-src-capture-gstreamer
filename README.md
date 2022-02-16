# Docker container to capture video from a V4L2 src with multiple sink options


Using this project you can setup a docker container that will capture video from a USB HDMI capture card (or other v4l2 compatible source) and send the content to a variety of sinks using GStreamer. Sinks include:

* Files -- useful for both capture and debugging
* [TDOD] RTSP (as a server)
* [] KVS Streams (for HLS or DASH viewing)
* [TODO] KVS WebRTC (for remote viewing AND control/text/log channel)

This project targets Linux hosts and was developed using Linux and Mac desktop environments. 

**_NOTE_**: The architecture (x86, amd64, armv7l, x86_64, etc.) of the built container must match the target device.  That is, if your target is Raspberry Pi (armv7l), then you must either build the image on an armv7l OR cross-compile. For the purposes of **_this project_**, cross-compiling is out of scope and the reader is advised to build on the target architecture. 

Likewise the base image for the container must match. For that reason, alternate `Dockerfiles` are provided for some common platforms. 

**Check your development host and target device architecture**

```bash
uname -a

# output for a Raspberry Pi 4:
#Linux <hostname> 5.10.63-v7l+ #1457 SMP Tue Sep 28 11:26:14 BST 2021 armv7l GNU/Linux

# x86 Mac
#Darwin <hostname> 20.6.0 Darwin Kernel Version 20.6.0: Mon Aug 30 06:12:21 PDT 2021; root:xnu-7195.141.6~3/RELEASE_X86_64 x86_64

# M1 Mac
#Darwin <hostname> 21.3.0 Darwin Kernel Version 21.3.0: Wed Jan  5 21:37:58 PST 2022; root:xnu-8019.80.24~20/RELEASE_ARM64_T6000 arm64

# i7 Ubuntu
#Linux <hostname> 5.11.0-37-generic #41~20.04.2-Ubuntu SMP Fri Sep 24 09:06:38 UTC 2021 x86_64 x86_64 x86_64 GNU/Linux

# grab just the machine architecture with
uname -m
```

**Select one of the provided `Dockerfiles` for common platforms or modify as needed**

| platform | Dockerfile | |
| --- | --- | --- |
| x86_64 | `Dockerfile` | use as is below |
| Raspberry Pi (`armv7l`) | `Dockerfile.rpi` | `mv Dockerfile Dockerfile.x86_64; mv Dockerfile.rpi Dockerfile` |

Before proceeding, inspect and verify the Dockerfile contents and filename to agree with the commands in this document.

## Pre-Condition: Verify V4L2 device functionality

GStreamer should be able to support nearly any V4L2 compatible device. This project was developed using a [QGeeM HDMI Capture Card](https://www.qgeem.com/products/qgeem-hdmi-game-live-video-capture-device), which is a USB 3.0 device. However, there are many devices that should work. A comprehensive list is beyond the scope of this project. Instead, this section can be used to verify the device functionality on the host prior to using the container.

### 1. Verify capture device connection

As noted above, this guide uses a USB capture device. If you are using another style of connection, verify that the device is installed and accessible. These steps explore the detailed device files. However, functionality can also be quickly verified using an application like [OBS](https://obsproject.com/) or [VLC](https://www.videolan.org/vlc/).

**Find USB Connection**

```bash
lsusb -t
# /:  Bus 04.Port 1: Dev 1, Class=root_hub, Driver=xhci_hcd/2p, 10000M
# /:  Bus 03.Port 1: Dev 1, Class=root_hub, Driver=xhci_hcd/2p, 480M
# /:  Bus 02.Port 1: Dev 1, Class=root_hub, Driver=xhci_hcd/6p, 10000M
#     |__ Port 4: Dev 6, If 0, Class=Hub, Driver=hub/4p, 5000M
#         |__ Port 1: Dev 7, If 0, Class=Mass Storage, Driver=usb-storage, 5000M
#         |__ Port 2: Dev 8, If 0, Class=Video, Driver=uvcvideo, 5000M
#         |__ Port 2: Dev 8, If 1, Class=Video, Driver=uvcvideo, 5000M
#         |__ Port 2: Dev 8, If 2, Class=Audio, Driver=snd-usb-audio, 5000M
#         |__ Port 2: Dev 8, If 3, Class=Audio, Driver=snd-usb-audio, 5000M
# /:  Bus 01.Port 1: Dev 1, Class=root_hub, Driver=xhci_hcd/12p, 480M
#     |__ Port 4: Dev 10, If 0, Class=Hub, Driver=hub/4p, 480M
#     |__ Port 10: Dev 3, If 0, Class=Wireless, Driver=btusb, 12M
#     |__ Port 10: Dev 3, If 1, Class=Wireless, Driver=btusb, 12M
```

In this case, the capture device shows up with `Class=Video`. Also note that there are also audio `Class=Audio` devices on the same USB port (`Port 2: Dev 8`).

**Check the V4L2 device mapping**

```bash
ls -l /dev/v4l/by-path
# lrwxrwxrwx 1 root root 12 Feb 11 10:39 pci-0000:00:14.0-usb-0:4.2:1.0-video-index0 -> ../../video0
# lrwxrwxrwx 1 root root 12 Feb 11 10:39 pci-0000:00:14.0-usb-0:4.2:1.0-video-index1 -> ../../video1
```

Note the USB port (`Port 2: Dev 8`) is listed as `-usb-0:4.2:1.0-` where `4:2` indicates `Bus 02` on `Port 4`. The symlink indicates that this dvice is then mounted on `/dev/video0` and `/dev/video1`. Verify those devices with:

```bash
ls -l /dev/video*
# crw-rw----+ 1 root video 81, 0 Feb 11 10:39 /dev/video0
# crw-rw----+ 1 root video 81, 1 Feb 11 10:39 /dev/video1
```

### 2. Verify V4L2 device function

If necessary, install the `v4l-utils` package (it is not usually installed by default). The Dockerfile used here will include these utilities so the container will be able to invoke these commands. However, it is a good idea to verify functionality on the **host** first and then **again** from the guest container.

```
sudo apt install v4l-utils
```

**Check the device matches**

```bash
v4l2-ctl --list-devices
# Video Capture 2 (usb-0000:00:14.0-4.2):
#         /dev/video0
#         /dev/video1
```

Usually you will only need to deal with the `0` device. The second device provides metadata about the video data from the first device. The new devices were introduced by this patch:

> https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=088ead25524583e2200aa99111bea2f66a86545a
> 
> More information on the V4L metadata interface can be found here:
>
> https://linuxtv.org/downloads/v4l-dvb-apis/uapi/v4l/dev-meta.html
>
> For run of the mill USB Video Class devices, this mostly just provides more accurate timestamp information. For cameras like Intel's RealSense line, provide a wider range of data about how the image was captured.
> 
> Presumably this data was split out into a separate device node because it couldn't easily be delivered on the primary device node in a compatible way. It's a bit of a pain though, since (a) applications that don't care about this metadata now need to filter out the extra devices, and (b) applications that do care about the metadata need a way to tie the two devices together.
> 
_Reference: https://unix.stackexchange.com/questions/512759/multiple-dev-video-for-one-physical-device_

**Check device capabilities**

```bash
v4l2-ctl --device=/dev/video0 --all
# Driver Info:
#         Driver name      : uvcvideo
#         Card type        : Video Capture 2
#         Bus info         : usb-0000:00:14.0-4.2
#         Driver version   : 5.13.19
#         Capabilities     : 0x84a00001
#                 Video Capture
#                 Metadata Capture
#                 Streaming
#                 Extended Pix Format
#                 Device Capabilities
#         Device Caps      : 0x04200001
#                 Video Capture
#                 Streaming
#                 Extended Pix Format
# Priority: 2
# Video input : 0 (Camera 1: ok)
# Format Video Capture:
#         Width/Height      : 1920/1080
#         Pixel Format      : 'YUYV' (YUYV 4:2:2)
#         Field             : None
#         Bytes per Line    : 3840
#         Size Image        : 4147200
#         Colorspace        : sRGB
#         Transfer Function : Rec. 709
#         YCbCr/HSV Encoding: ITU-R 601
#         Quantization      : Default (maps to Limited Range)
#         Flags             : 
# Crop Capability Video Capture:
#         Bounds      : Left 0, Top 0, Width 1920, Height 1080
#         Default     : Left 0, Top 0, Width 1920, Height 1080
#         Pixel Aspect: 1/1
# Selection Video Capture: crop_default, Left 0, Top 0, Width 1920, Height 1080, Flags: 
# Selection Video Capture: crop_bounds, Left 0, Top 0, Width 1920, Height 1080, Flags: 
# Streaming Parameters Video Capture:
#         Capabilities     : timeperframe
#         Frames per second: 60.000 (60/1)
#         Read buffers     : 0
```

This information can be handy when constructing the GStreamer pipeline.

### 3. Test capture device

**Check formats and sizes**

```bash
# modify for your deivce as needed
v4l2-ctl --list-formats-ext --device /dev/video0
# ioctl: VIDIOC_ENUM_FMT
#         Type: Video Capture

#         [0]: 'MJPG' (Motion-JPEG, compressed)
#                 Size: Discrete 1920x1080
#                         Interval: Discrete 0.017s (60.000 fps)
#         [1]: 'YUYV' (YUYV 4:2:2)
#                 Size: Discrete 1920x1080
#                         Interval: Discrete 0.017s (60.000 fps)
```

Connect the capture device to a video source, _verify the output_, and grab a frame with:

```bash
# substitute your device name and height/width using above information
v4l2-ctl --device /dev/video0 --set-fmt-video=width=1920,height=1080,pixelformat=MJPG --stream-mmap --stream-to=/tmp/output.jpg --stream-count=1

# then check the file
ls -l /tmp/output.jpg 
# -rw-rw-r-- 1 scott scott 15336 Feb 14 11:01 /tmp/output.jpg
```

The captured frame, `output.jpg` is [Motion JPEG](https://en.wikipedia.org/wiki/Motion_JPEG) file and not readily viewable. There are several conversion utilities or other viewers, `ffmpeg` is one of the easiest and you might want it in general. Convert the output to a plain JPEG file with

```bash
ffmpeg -i /tmp/output.jpg -bsf:v mjpeg2jpeg frame.jpg
```

Open `frame.jpg` and verify the grab is valid.

**_Troubleshooting_**: Sometimes the capture card can be in an indeterminate state with this call. Increasing the `--stream-count` value to 10 or more will often allow the acquisition to settle. Alternatively, OBS or VLC or other app can verify functonality (and will usually reset the device as well).

## Part 1 - v4l2 source to frame grab 

GStreamer provides a flexible and effective means to acquire those sources and render the current frame. As [GStreamer](https://gstreamer.freedesktop.org/) can require a number of libraries and be a bit tricky to work with, using Docker helps to manage these dependencies.

_Note:_ This section will build a Docker image. Docker images are specific to the OS and instruction architecture of the host. It can be convenient to build the image on one machine and deploy it to multiple others. However, the OS and architecture needs to be consistent. To avoid any issues, these instructions will build the image on the same system as the target for deployment. Advanced users can adapt this sequence to their needs.

_Prerequisites_:

* [Install Docker](https://docs.docker.com/engine/install/)


### Build the Docker image

The `RUN` command of the `Dockerfile` will install all the packages needed. The current build is based on Ubuntu 20.04, but it is certainly possible to create a smaller, more targetted image. 

**Open the Dockerfile in your editor**, make the following changes.

Note the export of the Time Zone -- the GStreamer install will pause (and fail) if this is not set. 

1. set `TZ` to your [time zone](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones).

The `CMD` provides the exec style params to the `ENTRYPOINT` -- these can be overridden by the docker invocation. The `device` can be customized if your capture device is not on `/dev/video0`. 

3. (Optional) modify the `location` parameter for the `multifilesink` plugin to set the location of the file that the pipeline will write. This parameter gives the Docker-side path for the frame results which can be modified with the `-v` options when you run docker.

4. (Optional) THe Dockerfile includes steps to build the Amazon Kinesis Video Streams Producer Library GStreamer Plugin (kvs-sink). This build can take some time, the lines between `WORKDIR /usr/src` and `ENTRYPOINT` can be commented or deleted if desired for faster Docker build times (when doing development for example).

4. **Save the Dockerfile**.
5. Now, build the image:

```bash
docker build --rm -t <name> .
# example
# docker build --rm -t gst .
```

The `--rm` switch will remove any previous builds (which you may accumulate if you change the `CMD` parameters or other settings). However, orphaned images can still accumulate. 

**List Images**
List images with

```bash
docker images
```

**Prune unused images**
```bash
docker system prune
```

### Test the Docker Image

1. Make a directory to share the output from GStreamer and start the docker container in interactive mode. 

**NOTE** the mapping of the `dev` tree and rule to map all the video (device type `81`) devices to the container.

```bash
mkdir -p /tmp/data
# launch the container in interactive mode 
docker run -v /tmp/data:/data  -v /dev:/dev --device-cgroup-rule='c 81:* rmw' -it --entrypoint /bin/bash gst
```

2. Retry the previous host verification steps to ensure the guest container can access the device and that results are consistent. Note that the host's `/tmp/data` directory is mounted in the container at `/data` to interchange frame grabs or other files as needed.

```bash
cd /data

v4l2-ctl --device /dev/video0 --set-fmt-video=width=1920,height=1080,pixelformat=MJPG --stream-mmap --stream-to=/tmp/output.jpg --stream-count=30 && ffmpeg -i /tmp/output.jpg -bsf:v mjpeg2jpeg frame%03d.jpg
```

Images can be inspected from the host (in `/tmp/data`) with any image viewer such as [`eog`](https://www.lifewire.com/guide-to-eye-of-gnome-image-viewer-2188343).

3. Execute pipelines manually

```bash
# grab numbered frames from /dev/video (v4l2 source)
gst-launch-1.0 -v v4l2src device=/dev/video0 ! jpegdec ! videoconvert ! jpegenc ! multifilesink location="/data/frame.jpg"
```

This will repeatedly acquire a frame from the device and write/overwrite the output file.

4. Exit the container terminal (`exit` or Control-D) and test the `ENTRYPOINT`

Examine Dockerfile and select (uncomment) a sample `CMD` or write your own. **Be sure to only leave one `CMD` uncommented.**

```bash
# adding the -d flag will detach the container's output
#   stop it with docker stop, but get the running name first with docker container ls
# Since we made /tmp/data world writable, we don't need to map the docker user, 
#   but could add back with `--user "$(id -u):$(id -g)"` on command line
docker run -v /tmp/data:/data -v /dev:/dev --device-cgroup-rule='c 81:* rmw' gst
# Setting pipeline to PAUSED ...
# Pipeline is live and does not need PREROLL ...
# Setting pipeline to PLAYING ...
# New clock: GstSystemClock
```

Monitor the file written to the shared volume (`/tmp/data` on the host) to verify correctness and currency.



5. Check the output with

```bash
# modify as needed if you changed the output location
ls -l /tmp/data/frame.jpg
``` 
observe the user, group, timestamp, etc. 

3. Open the file in an image viewer and verify correctness.

_Tip_: If using a headed Ubuntu host (not Cloud9), the command `eog /tmp/data/frame.jpg` will open a window with the image--it should refresh as the pipeline writes new frames.

_Troubleshooting_

Seeing errors about plugins missing or misconfigured?
```bash
gst-inspect-1.0 multifilesink # or other pipeline component
```

Compose additional pipelines, consulting the [GStreamer Plugin Reference](https://gstreamer.freedesktop.org/documentation/plugins_doc.html?gi-language=c)

### (Optional) Step 3. Use a RAM disk for the images

As the GStreamer pipeline will (re)write the frame file 30x/second, using a RAM Disk for these will save power and disk cycles as well as improve overall performance. When inference is added, we can extend the use of this RAM Disk. This step may be important for traditional linux systems or other systems where you wish to avoid repeated disk writes. That is, this is **not necessary for Cloud 9** hosts, but may be helpful for embedded systems where the 'disk' is an SD card with finite lifetime writes.

* create entry in `/etc/fstab` 

```
tmpfs /tmp/data tmpfs defaults,noatime,nosuid,nodev,noexec,mode=1777,size=32M 0 0
```

creates 32M RAM disk in `/tmp/data`...  the mapped volume for docker

Mount the RAM Disk with

```bash
sudo mount -a
```

You may need to `chown` the user/group of the created tmp dir **OR** execute subsequent inference with `sudo` **OR** modify the `fstab` entry to set the user/group.


## FINISHED