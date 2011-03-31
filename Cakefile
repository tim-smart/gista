fs       = require 'fs'
{ exec } = require 'child_process'

run = (command, cb) ->
  child = exec command, cb
  child.stdout.on 'data', (data) -> process.stdout.write data
  child.stderr.on 'data', (data) -> process.stderr.write data

task 'build', 'Create the ecmascript', ->
  invoke 'docs'

  run 'coffee -cb -o bin src/gista.coffee && mv bin/gista.js bin/gista', ->
    fs.readFile 'bin/gista', 'utf8', (error, code) ->
      throw error if error
      fs.writeFile 'bin/gista', "#!/usr/bin/env node\n#{code}", ->
        run 'chmod 0755 bin/gista'

task 'docs', 'Use docco to create HTML docs', ->
  run 'docco src/*.coffee'
