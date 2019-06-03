fs = require 'fs'
{spawn} = require 'child_process'
util = require 'util'

coffeeName = 'coffee'
if process.platform == 'win32'
  coffeeName += '.cmd'

buildEverything = (callback) ->
  try
    fs.mkdirSync 'build'
  catch
    # probably already exists

  coffee = spawn coffeeName, ['-c', '-o', 'build', 'src']
  coffee.stderr.on 'data', (data) ->
    process.stderr.write data.toString()
    process.exit(-1)
  coffee.stdout.on 'data', (data) ->
    print data.toString()
  coffee.on 'exit', (code) ->
    rawJS = fs.readFileSync('build/unvr.js')
    rawJS = "#!/usr/bin/env node\n\n" + rawJS
    fs.writeFileSync("unvr", rawJS)
    util.log "Compilation finished."
    callback?() if code is 0

task 'build', 'build', (options) ->
  buildEverything()
