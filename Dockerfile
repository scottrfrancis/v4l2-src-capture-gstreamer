FROM ubuntu:20.04
# ENV TZ=<your timezone, e.g. America/Los_Angeles>
ENV TZ=America/Los_Angeles
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

#
# Package setup
#
#	Main GStreamer packages
RUN apt-get -y update && apt-get install -y \
    libgstreamer1.0-0  \
	gstreamer1.0-plugins-base \
	gstreamer1.0-plugins-good \
	gstreamer1.0-plugins-bad \
	gstreamer1.0-plugins-ugly \
	gstreamer1.0-libav \
	gstreamer1.0-doc \
	gstreamer1.0-tools \
	gstreamer1.0-x \
	gstreamer1.0-alsa \
	gstreamer1.0-gl \
	gstreamer1.0-gtk3 \
	gstreamer1.0-qt5 \
	gstreamer1.0-pulseaudio
# Additional utilities to work with streams and sources
RUN apt-get install -y \
	v4l-utils \
	ffmpeg \
	usbutils
# Packages to build KPL
RUN apt-get install -y \
	pkg-config cmake m4 git \
	libgstreamer1.0-dev \
    libgstreamer-plugins-base1.0-dev \
    libgstreamer-plugins-bad1.0-dev 
# Utilities to work with KPL samples and AWS
RUN apt-get install -y \
    awscli wget 
# and finalize...
RUN apt-get clean && apt-get autoremove && rm -rf /var/lib/apt/lists/*

#
# build KVS producer plugin for GStreamer -- kvs-sink
#
# 	comment or remove if not working with KPL
#
WORKDIR /usr/src
RUN git clone https://github.com/awslabs/amazon-kinesis-video-streams-producer-sdk-cpp.git
RUN mkdir -p /usr/src/amazon-kinesis-video-streams-producer-sdk-cpp/build 
WORKDIR /usr/src/amazon-kinesis-video-streams-producer-sdk-cpp/build
# now build the plugin
RUN cmake .. -DBUILD_GSTREAMER_PLUGIN=TRUE
RUN make

#
# Main entry to run a GStreamer pipeline
#
ENTRYPOINT ["gst-launch-1.0"] 
#
# Options for CMD/Pipeline configurations
# 	only uncomment ONE
#

# dummy pipeline to make sure GStreamer is installed and funtional
# CMD [ "fakesrc", "!", "fakesink" ]

# An RTSP source to a single file output (overwrites) - NB location of output and `-v` mappings 
# CMD ["rtspsrc", "location=\"rtsp://<ip>:<port>/h264?username=<user>&password=<pass>\"", "!", "queue", "!", "rtph264depay", "!", "avdec_h264", "!", "jpegenc", "!", "multifilesink", "location=\"/data/frame.jpg\""]

# use fakesrc to test output to shared location -- e.g. `/data`
# CMD ["fakesrc", "num-buffers=10", "!", "multifilesink", "location=\"/data/frame.jpg\""]

# read a sequence of files from a mounted location `/frames` and write to single output. NB - sequence number formatting - `seq_%06d.jpg`
# CMD ["multifilesrc", "location=/frames/seq_%06d.jpg", "index=1", "loop=true", "caps=\"image/jpg,framerate=\\(fraction\\)12/1\"", "!", "multifilesink", "location=\"/data/frame.jpg\""]

# capture from v4l2 device (`/dev/video0`) to a numbered series of files - max 1000 and then get deleted. if the mounted fs is limited, space may run out faster
# CMD [ "v4l2src",  "device=/dev/video0", "!", "jpegdec", "!", "videoconvert",  "!", "jpegenc",  "!",  "multifilesink",  "location=\"/data/frame%06d.jpg\" max-files=1000" ]

# capture from v4l2 to mp4 file
CMD [ "v4l2src",  "device=/dev/video0", "!", "jpegdec", "!", "videoconvert",  "!", "jpegenc",  "!",  "multifilesink",  "location=\"/data/frame%06d.jpg\" max-files=1000" ]
