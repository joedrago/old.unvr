## Overview

Playing around with nona+ffmpeg, trying to perform arbitrary equirectangular -> rectilinear x/y
projection remaps (convert 360 videos to 2D).

Perhaps someday this'll be a proper tool with a UI instead of repeated kicking around of a
commandline, but this sloppy code is really just for projections exploration and not to actually
make a serious tool (yet). Right now it is little more than some clever calls to colorist, nona, and
ffmpeg.

## Basic Tutorial

(Right now this only works on Windows. I'll try to remove the deps on colorist and add install info
for ffmpeg and nona so that this can work elsewhere.)

Install with: `npm install -g joedrago/unvr`

Download the original video here for playing around: https://vimeo.com/215985972

I renamed `360_VR Master Series _ Free Asset Download _  Bavarian Alps Wimbachklamm.mp4` to
`alps.mp4`. Note that the video is 4096x2048 and only offers one eye (mono), and if you look at the
metadata (via VLC), it shows that it was recorded with a FOV of 80. With this information, you can
make a test image to see if conversion is going to do what you want:

    unvr alps.mp4 out.png -sw 4096 -sh 2048 -v 80

If you choose a `.mp4` extension instead of `.png`, it would have converted the entire video into a
1920x1080 viewport, facing "straight ahead" (no Yaw, Pitch, or Roll). If you wanted to face to the
up and to the right a little bit, you can add a new "look", such as:

    unvr alps.mp4 out.png -sw 4096 -sh 2048 -v 80 -l 0:-15:-20:0

The `-l` command is in the order `TIMESTAMP:YAW:PITCH:ROLL`, which means when we hit that timestamp,
look in a new direction. In this case, it'd look 15 degrees to the right and 20 degrees up. You can
have multiple `-l` arguments.

If you don't want to wait for a full encode to make sure your camera angles are all right, you can
"walk" the video and create a series of snapshots that honor the `-l` arguments you already have on
the commandline. For example:

    unvr alps.mp4 out.png -sw 4096 -sh 2048 -v 80 -l 10:-15:-20:0 -w 0:60:5

This will walk the first 60 seconds of the source video (starting at 0), taking snapshots every 5
seconds and saving them to `unvr.snapshots`. The first two shots (0 and 5) should look straight
ahead, and all subsequent shots should look up and to the right. You can throw away the temporary
snapshots and use the `-w` command as a sort-of scrubber, inspecting transitions and framing before
committing to a full encode.

Alternatively, you can use `-t DURATION` to output a no-sound version of the last "look" on the
commandline to make sure those few seconds make sense in motion.

Once you're comfortable with the looks you've created, remove any `-w` or `-t` on the commandline
and output to a `.mp4`, such as:

    unvr alps.mp4 out.mp4 -sw 4096 -sh 2048 -v 80 -l 10:-15:-20:0

Use the other options to impact the qualtiy of the output video, such as the resolution (`-dw`,
`-dh`), the frames per second (`-f`), quality (`-q`).
