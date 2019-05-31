fs = require 'fs'
{spawnSync} = require 'child_process'

SINGLE_DURATION = 3

main = ->
  args = process.argv.slice(2)
  inputFilename = null
  outputFilename = null
  srcW = 0
  srcH = 0
  dstW = 1920
  dstH = 1080
  single = false
  cores = 0

  looks = []
  while arg = args.shift()
    if arg == '-s'
      single = true
    else if arg == '-c'
      cores = parseInt(args.shift())
    else if arg == '-sw'
      srcW = parseInt(args.shift())
    else if arg == '-sh'
      srcH = parseInt(args.shift())
    else if arg == '-dw'
      dstW = parseInt(args.shift())
    else if arg == '-dh'
      dstH = parseInt(args.shift())
    else if arg == '-l' # look
      rawYPR = args.shift()
      pieces = rawYPR.split(/:/) # Timestamp, Yaw, Pitch, Roll
      while pieces.length < 4
        pieces.push "0"
      look =
        timestamp: parseInt(pieces[0])
        yaw:   parseInt(pieces[1])
        pitch: parseInt(pieces[2])
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

  if single
    if looks.length > 1
      looks = [looks[looks.length-1]]

  else
    looks.sort (a, b) -> return b.timestamp < a.timestamp

  needsStartingLook = false
  if looks.length == 0
    needsStartingLook = true
  else if not single and (looks[0].timestamp != 0)
    needsStartingLook = true
  if needsStartingLook
    startingLook =
      timestamp: 0
      roll:  0
      pitch: 0
      yaw:   0
    looks.unshift startingLook

  if (srcW == 0) or (srcH == 0)
    console.error "-sw and -sh are required"
    process.exit()

  console.log "Reading [#{srcW}x#{srcH}]: #{inputFilename}"
  console.log "Writing [#{dstW}x#{dstH}]: #{outputFilename}"
  console.log "Looks:"
  console.log looks

  # make a working dir
  try
    fs.mkdirSync "unvr.tmp"
  catch
    # meh

  # make a fake file to indicate to nona the source video's dimensions
  coloristEXE = __dirname + "/wbin/colorist.exe"
  fakeSourceImageFilename = "unvr.tmp/lies.png"
  spawnSync(coloristEXE, ["generate", "#{srcW}x#{srcH},#000000", fakeSourceImageFilename])#, { stdio: 'inherit' })

  ffmpegArgs = []

  if cores > 0
    ffmpegArgs.push '-threads'
    ffmpegArgs.push String(cores)

  seekOffset = 0
  if single
    seconds = looks[0].timestamp - 1
    if seconds > 0
      seekOffset = seconds
      ffmpegArgs.push '-ss'
      ffmpegArgs.push String(seekOffset)

  ffmpegArgs.push '-i'
  ffmpegArgs.push inputFilename
  ffmpegFilter = ""

  nonaEXE = __dirname + "/wbin/nona.exe"
  for look, lookIndex in looks
    # write out a nona config for creating the equirectangular -> rectilinear x/y projection remaps
    console.log "Generating projection for look #{lookIndex} ..."
    nonaConfig = "p w#{dstW} h#{dstH} f0 v100\ni f4 r#{look.roll} p#{look.pitch} y#{look.yaw} v180 n\"lies.png\"\n"
    nonaConfigFilename = "unvr.tmp/nona#{lookIndex}.cfg"
    fs.writeFileSync(nonaConfigFilename, nonaConfig)
    spawnSync(nonaEXE, ['-o', "unvr.tmp\\r#{lookIndex}_", '-c', nonaConfigFilename])

    ffmpegArgs.push '-i'
    ffmpegArgs.push "unvr.tmp\\r#{lookIndex}_0000_x.tif"
    ffmpegArgs.push '-i'
    ffmpegArgs.push "unvr.tmp\\r#{lookIndex}_0000_y.tif"

    lastLook = (lookIndex == (looks.length-1))
    duration = 0
    if not lastLook
      duration = looks[lookIndex+1].timestamp - look.timestamp
    if single
      duration = SINGLE_DURATION
    if duration > 0
      ffmpegFilter += "[0:v]trim=start=#{look.timestamp - seekOffset}:duration=#{duration},setpts=PTS-STARTPTS[raw#{lookIndex}];"
    else
      ffmpegFilter += "[0:v]trim=start=#{look.timestamp - seekOffset},setpts=PTS-STARTPTS[raw#{lookIndex}];"

    if single
      break

  concatString = ""
  projIndex = 1
  for look, lookIndex in looks
    if single
      ffmpegFilter += "[raw#{lookIndex}][#{projIndex}][#{projIndex+1}]remap"
      break
    ffmpegFilter += "[raw#{lookIndex}][#{projIndex}][#{projIndex+1}]remap[r#{lookIndex}];"
    projIndex += 2
    concatString += "[r#{lookIndex}]"

  if not single
    concatString += "concat=n=#{looks.length}"
    ffmpegFilter += concatString

  ffmpegArgs.push "-filter_complex"
  ffmpegArgs.push ffmpegFilter
  ffmpegArgs.push '-c:a'
  ffmpegArgs.push 'copy'
  ffmpegArgs.push '-shortest'
  if outputFilename.match(/\.png$/)
    ffmpegArgs.push '-frames:v'
    ffmpegArgs.push '1'
  else
    ffmpegArgs.push '-vb'
    ffmpegArgs.push '20M'
  ffmpegArgs.push outputFilename

  console.log ffmpegArgs

  ffmpegEXE = __dirname + "/wbin/ffmpeg.exe"
  try
    fs.unlinkSync(outputFilename)
  catch
    # meh
  spawnSync(ffmpegEXE, ffmpegArgs, { stdio: 'inherit' })

main()
