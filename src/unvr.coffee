fs = require 'fs'
{spawnSync} = require 'child_process'

DEFAULT_OUTPUT_WIDTH = 1920
DEFAULT_OUTPUT_HEIGHT = 1080
DEFAULT_FPS = 30
DEFAULT_FOV = 110
DEFAULT_ROTATED_FOV = 60
DEFAULT_CRF = 20
DEFAULT_WALK_DIR = "unvr.snapshots"

pad = (num, size) ->
  s = num + ""
  while s.length < size
    s = "0" + s
  return s

syntax = ->
  console.log "Syntax : unvr [options] inputFilename outputFilename"
  console.log "Options:"
  console.log "    -sw WIDTH   : source video width (one eye) REQUIRED"
  console.log "    -sh HEIGHT  : source video height (one eye) REQUIRED"
  console.log "    -s DIM      : short for -sw DIM -sh DIM"
  console.log "    -dw WIDTH   : dest video width (default: #{DEFAULT_OUTPUT_WIDTH})"
  console.log "    -dh HEIGHT  : dest video height (default: #{DEFAULT_OUTPUT_HEIGHT})"
  console.log "    -l T:P:Y:R  : At timestamp T, look in a new direction (Pitch, Yaw, Roll, in degrees). 0:0:0 is straight ahead"
  console.log "    -t DURATION : test the last look by making a no-sound output of DURATION seconds for it"
  console.log "    -j JOBS     : number of jobs (cores) ffmpeg is allowed to use"
  console.log "    -f FPS      : frames per second. Default: #{DEFAULT_FPS}"
  console.log "    -v FOV      : field of view, in degrees. Default: #{DEFAULT_FOV}"
  console.log "    -p          : portrait (swaps width and height, adjusts FOV)"
  console.log "    -q QUALITY  : quality (passed directly to ffmpeg as -crf). Default: #{DEFAULT_CRF}"
  console.log "    -w S:STEP   : Instead of making a video, walk the video making snapshots every STEP seconds: S start"
  console.log "    -wd DIR     : walk snapshots dir (default: #{DEFAULT_WALK_DIR})"
  console.log "    -wk         : keep old snapshots in walk snapshots dir"
  console.log "    -d          : dry run (don't execute commands or touch files)"

main = ->
  args = process.argv.slice(2)

  if args.length < 1
    syntax()
    process.exit(0)

  # defaults
  inputFilename = null
  outputFilename = null
  srcW = 0
  srcH = 0
  dstW = DEFAULT_OUTPUT_WIDTH
  dstH = DEFAULT_OUTPUT_HEIGHT
  testLookDuration = 0
  jobs = 0
  dryrun = false
  fps = DEFAULT_FPS
  fov = DEFAULT_FOV
  crf = DEFAULT_CRF
  walkSnapshots = null
  walkDir = DEFAULT_WALK_DIR
  walkCleanup = true

  # argument parsing
  looks = []
  while arg = args.shift()
    if arg == '-d'
      dryrun = true
    else if arg == '-w'
      rawSS = args.shift()
      pieces = rawSS.split(/:/) # Timestamp, Yaw, Pitch, Roll
      while pieces.length < 2
        pieces.push "1"
      walkSnapshots =
        start: parseInt(pieces[0])
        step: parseInt(pieces[1])
    else if arg == '-wd'
      walkDir = args.shift()
    else if arg == '-j'
      jobs = parseInt(args.shift())
    else if arg == '-f'
      fps = parseInt(args.shift())
    else if arg == '-v'
      fov = parseInt(args.shift())
    else if arg == '-p'
      tmp = dstW
      dstW = dstH
      dstH = tmp
      fov = DEFAULT_ROTATED_FOV
    else if arg == '-q'
      crf = parseInt(args.shift())
    else if arg == '-t'
      testLookDuration = parseInt(args.shift())
    else if arg == '-s'
      srcW = parseInt(args.shift())
      srcH = srcW
    else if arg == '-sw'
      srcW = parseInt(args.shift())
    else if arg == '-sh'
      srcH = parseInt(args.shift())
    else if arg == '-dw'
      dstW = parseInt(args.shift())
    else if arg == '-dh'
      dstH = parseInt(args.shift())
    else if arg == '-wk'
      walkCleanup = false
    else if arg == '-l' # look
      rawYPR = args.shift()
      pieces = rawYPR.split(/:/) # Timestamp, Yaw, Pitch, Roll
      while pieces.length < 4
        pieces.push "0"
      look =
        timestamp: parseInt(pieces[0])
        pitch: parseInt(pieces[1])
        yaw:   parseInt(pieces[2])
        roll:  parseInt(pieces[3])
      looks.push look
    else
      if arg.charAt(0) == '-'
        console.log "unrecognized option: #{arg}"
        process.exit(0)
      if inputFilename == null
        inputFilename = arg
      else
        outputFilename = arg

  if testLookDuration > 0
    if looks.length > 1
      looks = [looks[looks.length-1]]
    if looks.length > 0
      if walkSnapshots != null
        looks[0].timestamp = walkSnapshots.start
        walkSnapshots = null
  else
    looks.sort (a, b) -> return b.timestamp < a.timestamp

  needsStartingLook = false
  if looks.length == 0
    needsStartingLook = true
  else if (testLookDuration == 0) and (looks[0].timestamp != 0)
    needsStartingLook = true
  if needsStartingLook
    startingLook =
      timestamp: 0
      roll:  0
      pitch: 0
      yaw:   0
    looks.unshift startingLook

  ffprobeEXE = __dirname + "/wbin/ffprobe.exe"
  if (srcW == 0) or (srcH == 0)
    ffprobeArgs = [
      '-v'
      'error'
      '-select_streams'
      'v:0'
      '-show_entries'
      'stream=width,height'
      '-of'
      'default=nw=1'
      inputFilename
    ]

    console.log "Querying width and height: #{inputFilename}"
    console.log ffprobeArgs
    proc = spawnSync(ffprobeEXE, ffprobeArgs)

    stdoutLines = String(proc.stdout).split(/\n/)
    for line in stdoutLines
      if matches = line.match(/width=(\d+)/)
        srcW = parseInt(matches[1]) >> 1
      if matches = line.match(/height=(\d+)/)
        srcH = parseInt(matches[1])

    if (srcW == 0) or (srcH == 0)
      console.error "-sw and -sh are required"
      process.exit(-1)

    console.log "Choosing source dimensions: #{srcW}x#{srcH}"


  console.log "Reading [#{srcW}x#{srcH}]: #{inputFilename}"
  console.log "Writing [#{dstW}x#{dstH}]: #{outputFilename}"
  console.log "Looks:"
  for look in looks
    console.log " * T:#{look.timestamp} Y:#{look.yaw} P:#{look.pitch} R:#{look.roll}"

  if walkSnapshots != null
    oldLooks = looks
    looks = []
    end = walkSnapshots.start + 10000 # arbitrary
    for timestamp in [walkSnapshots.start..end] by walkSnapshots.step
      lastOldLook = oldLooks[0]
      for oldLook in oldLooks
        # console.log oldLook
        if timestamp < oldLook.timestamp
          break
        lastOldLook = oldLook
      looks.push {
        timestamp: timestamp
        roll:  lastOldLook.roll
        pitch: lastOldLook.pitch
        yaw:   lastOldLook.yaw
      }
    # console.log looks
    # process.exit(0)


  # make a working dir and optionally a walk dir
  try
    fs.mkdirSync "unvr.tmp"
  catch
    # meh
  if walkSnapshots != null
    try
      fs.mkdirSync walkDir
    catch
      # meh

    if not dryrun and walkCleanup
      filesToUnlink = fs.readdirSync(walkDir)
      for fn in filesToUnlink
        if fn.match(/.tga$/)
          toUnlink = "#{walkDir}/#{fn}"
          try
            console.log "Removing: #{toUnlink}"
            fs.unlinkSync(toUnlink)
          catch
            # meh

  # make a fake file to indicate to nona the source video's dimensions
  coloristEXE = __dirname + "/wbin/colorist.exe"
  fakeSourceImageFilename = "unvr.tmp/lies.png"
  if not dryrun
    spawnSync(coloristEXE, ["generate", "#{srcW}x#{srcH},#000000", fakeSourceImageFilename])

  onePass = (looks.length == 1) and ((looks[0].timestamp == 0) or (testLookDuration != 0))

  ffmpegEXE = __dirname + "/wbin/ffmpeg.exe"
  nonaEXE = __dirname + "/wbin/nona.exe"
  lastLook = null
  for look, lookIndex in looks
    if walkSnapshots == null
      look.filename = "unvr.tmp\\tmp_#{lookIndex}.mp4"
    else
      look.filename = "#{walkDir}\\T#{pad(look.timestamp, 6)}.tga"

    if (lastLook == null) or (lastLook.yaw != look.yaw) or (lastLook.pitch != look.pitch) or (lastLook.roll != look.roll)
      lastLook = look

      # write out a nona config for creating the equirectangular -> rectilinear x/y projection remaps
      nonaConfig = "p w#{dstW} h#{dstH} f0 v#{fov}\ni f4 r#{look.roll} p#{look.pitch} y#{look.yaw} v180 n\"lies.png\"\n"
      nonaConfigFilename = "unvr.tmp/nona.cfg"
      nonaArgs = ['-o', "unvr.tmp\\unvr_", '-c', nonaConfigFilename]
      console.log "Generating projection for look #{lookIndex} ..."
      console.log nonaConfig
      console.log nonaArgs
      if not dryrun
        fs.writeFileSync(nonaConfigFilename, nonaConfig)
        spawnSync(nonaEXE, nonaArgs)

    ffmpegArgs = []
    if jobs > 0
      ffmpegArgs.push '-threads'
      ffmpegArgs.push String(jobs)

    # This makes ffmpeg significantly faster at finding the first frame
    seekOffset = 0
    seconds = look.timestamp
    seekOffset = seconds
    ffmpegArgs.push '-ss'
    ffmpegArgs.push String(seekOffset)

    ffmpegArgs.push '-i'
    ffmpegArgs.push inputFilename
    ffmpegArgs.push '-i'
    ffmpegArgs.push "unvr.tmp\\unvr_0000_x.tif"
    ffmpegArgs.push '-i'
    ffmpegArgs.push "unvr.tmp\\unvr_0000_y.tif"

    ffmpegFilter = ""

    duration = 0
    if lookIndex != (looks.length - 1)
      duration = looks[lookIndex+1].timestamp - look.timestamp
    if testLookDuration > 0
      duration = testLookDuration

    if duration > 0
      ffmpegFilter += "[0:v]trim=start=#{look.timestamp - seekOffset}:duration=#{duration},fps=#{fps},setpts=PTS-STARTPTS[raw#{lookIndex}];"
    else
      ffmpegFilter += "[0:v]trim=start=#{look.timestamp - seekOffset},fps=#{fps},setpts=PTS-STARTPTS[raw#{lookIndex}];"

    ffmpegFilter += "[raw#{lookIndex}][1][2]remap"

    ffmpegArgs.push "-filter_complex"
    ffmpegArgs.push ffmpegFilter
    if onePass and (testLookDuration == 0) and (walkSnapshots == null)
      ffmpegArgs.push '-c:a'
      ffmpegArgs.push 'copy'
      ffmpegArgs.push '-shortest'
    else
      ffmpegArgs.push '-an'

    filename = look.filename
    if onePass
      filename = outputFilename

    if filename.match(/\.tga$/)
      ffmpegArgs.push '-frames:v'
      ffmpegArgs.push '1'
    else
      ffmpegArgs.push '-crf'
      ffmpegArgs.push String(crf)

    ffmpegArgs.push filename

    console.log "Rendering look #{lookIndex} ..."
    console.log ffmpegArgs
    if not dryrun
      try
        fs.unlinkSync(filename)
      catch
        # meh
      spawnSync(ffmpegEXE, ffmpegArgs, { stdio: 'inherit' })
      if not fs.existsSync(filename)
        break

    if testLookDuration > 0
      break

  if not onePass and (walkSnapshots == null)
    console.log "Concatenating #{looks.length} video streams ..."
    ffmpegArgs = []
    if jobs > 0
      ffmpegArgs.push '-threads'
      ffmpegArgs.push String(jobs)
    ffmpegFilter = ""
    concatString = ""
    filelist = ""
    filelistFilename = "unvr.tmp\\concatFileList.txt"
    concatFilename = "unvr.tmp\\allvideo.mp4"
    for look, lookIndex in looks
      filelist += "file '#{look.filename}'\n"
    fs.writeFileSync(filelistFilename, filelist)
    ffmpegArgs.push '-f'
    ffmpegArgs.push 'concat'
    ffmpegArgs.push '-safe'
    ffmpegArgs.push '0'
    ffmpegArgs.push '-i'
    ffmpegArgs.push filelistFilename
    ffmpegArgs.push '-c'
    ffmpegArgs.push 'copy'
    ffmpegArgs.push concatFilename
    console.log ffmpegArgs
    if not dryrun
      try
        fs.unlinkSync(concatFilename)
      catch
        # meh
      spawnSync(ffmpegEXE, ffmpegArgs, { stdio: 'inherit' })

    console.log "Mixing video and audio streams ..."
    ffmpegArgs = []
    if jobs > 0
      ffmpegArgs.push '-threads'
      ffmpegArgs.push String(jobs)
    ffmpegArgs.push '-i'
    ffmpegArgs.push concatFilename
    ffmpegArgs.push '-i'
    ffmpegArgs.push inputFilename
    ffmpegArgs.push '-c'
    ffmpegArgs.push 'copy'
    ffmpegArgs.push '-map'
    ffmpegArgs.push '0:v:0'
    ffmpegArgs.push '-map'
    ffmpegArgs.push '1:a:0'
    ffmpegArgs.push outputFilename
    console.log ffmpegArgs
    if not dryrun
      try
        fs.unlinkSync(outputFilename)
      catch
        # meh
      spawnSync(ffmpegEXE, ffmpegArgs, { stdio: 'inherit' })

main()
