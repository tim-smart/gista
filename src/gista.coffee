# The Node Gist CLI Tool
# ======================
#
# A handy little tool that allows you to use Gist like a unix pro.
Client   = require('node-gist').Client
nopt     = require 'nopt'
path     = require 'path'
url      = require 'url'
fs       = require 'fs'
async    = require('async-array').async
{ exec } = require 'child_process'

# HELP
help = """
Create a Gist from a file or stdin using node-gist.

gista -pd "My cool gist" [file.ext]

Options:
  -f, --fetch     Fetch a gist by id or url
  -p, --private   Mark the gist private
  -n, --name      Manually set the file name
  -d, --desc      Add a description
  -t, --type      Manually set file extension
  -u, --user      Manually set Github username
  -p, --password  Manually set Github user password
  -h, --help      You looking at it

"""

# Option parsing is done with `nopt` - a handy library sculpted by
# Isaac Schlueter
known_opts =
  private: Boolean
  fetch:   String
  meta:    Boolean
  name:    String
  desc:    String
  type:    String
  token:   String
  user:    String
  help:    Boolean

short_opts =
  f: '--fetch'
  p: ['--private', 'true']
  t: '--type'
  u: '--user'
  a: '--token'
  h: '--help'
  n: '--name'
  d: '--desc'

options = nopt known_opts, short_opts

# Show the help?
if options.help
  console.log help
  return process.exit()

# Fetch mode? Fetch mode precedes gist creation.
if options.fetch
  client = new Client
  path   = (url.parse options.fetch).pathname
  path   = '/' + path unless path[0] is '/'
  return client.get path, (error, gist) ->
    throw error if error

    files    = Object.keys(gist.files)
    multiple = files.length > 1

    unless multiple
      return console.log gist.files[files[0]].content

    ret = []
    buf = ''
    for file in files
      buf += file + '\n'
      buf += new Array(file.length + 1).join '='
      buf += '\n\n' + gist.files[file].content
      ret.push buf
      buf = ''

    console.log ret.join '\n\n'

files = options.argv.remain

# Are we reading from stdin, or reading from a list of files?
is_stdin = options.argv.remain.length is 0

# We need to exhaust all the cases where the github user and token
# could be stored.
loadConfig = (callback) ->
  options.user     = process.env.GITHUB_USER     unless options.user
  options.password = process.env.GITHUB_PASSWORD unless options.password

  return callback() if options.user and options.password

  task = async []

  task.push 'user'     unless options.user
  task.push 'password' unless options.password

  task
    .forEach (item, i, next) ->
      exec "git config --global github.#{item}", (error, stdout) ->
        return next error if error
        options[item] = stdout.trim()
        next()
    .exec (error, results) ->
      if options.user is null or options.password is null
        options.user = options.password = null
      if error
        return callback error
      callback()

# Load the user and token then either load the stdin data
# or parse out the files.
loadConfig (error) ->
  return fromStdin() if is_stdin
  fromFiles()

# Collect data on stdin as it comes in, buffer it, and then pass it
# on to `createGist`.
fromStdin = ->
  data = ''
  process.stdin.resume()
  process.stdin.setEncoding 'utf8'
  process.stdin.on 'data', (chunk) ->
    data += chunk
  process.stdin.on 'end', ->
    createGist [name: options.name or 'stdin.txt', content: data]

# Iterate over every file and grab the contents, ready to pass
# onto `createGist`.
fromFiles = ->
  throw new Error 'Over 10 files.' if files.length > 10

  async(files)
    .map (file, i, next) ->
      fs.readFile file, 'utf8', (error, content) ->
        return next error if error
        next null, name : (path.basename file), content : content
    .exec (error, results) ->
      throw error if error
      createGist results.array()

# Now that we have all the content we need, we can now create the gist
# and post back the link.
createGist = (files) ->
  client = new Client
    user     : options.user
    password : options.password

  gist =
    public : !options.private
    files  : {}

  gist.description = options.desc if options.desc

  type = if options.type then '.' + options.type or null

  for file in files
    name = file.name
    name = name + type if type
    gist.files[name] =
      content : file.content

  client.post '', gist, (error, gist) ->
    throw error if error
    console.log gist.html_url
