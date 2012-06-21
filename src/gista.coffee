# The Node Gist CLI Tool
# ======================
#
# A handy little tool that allows you to use Gist like a unix pro.
Client   = require('node-gist').Client
nopt     = require 'nopt'
path     = require 'path'
url      = require 'url'
tty      = require('tty').isatty(process.stdout.fd)
fs       = require 'fs'
async    = require('async-array').async
{ exec } = require 'child_process'

client   = null

# HELP
help = """
Create a Gist from a file or stdin using node-gist.

gista -pd "My cool gist" [file.ext]

Options:
  -f, --fetch     Fetch a gist by id or url
  -e, --edit      Edit a gist by id or url
  -*, --star      Star a gist by id or url
  -x, --delete    Delete a gist by id or url
  -p, --private   Mark the gist private
  -n, --name      Manually set the file name
  -d, --desc      Add a description
  -t, --type      Manually set file extension
  -a, --token     Manually set the oauth token
      --gentoken  Generate a token from previous token/credentials
  -u, --user      Manually set Github username
      --password  Manually set Github user password
      --tty       Force tty mode for output formatting
  -v, --verbose   When reading from stdin, echo input back to stdout
  -h, --help      You looking at it

"""

# Option parsing is done with `nopt` - a handy library sculpted by
# Isaac Schlueter
known_opts =
  private:  Boolean
  fetch:    String
  edit:     String
  star:     String
  delete:   String
  name:     String
  desc:     String
  type:     String
  token:    String
  gentoken: Boolean
  password: String
  user:     String
  tty:      Boolean
  verbose:  Boolean
  help:     Boolean

short_opts =
  f: '--fetch'
  e: '--edit'
  '*': '--star'
  x: '--delete'
  p: ['--private', 'true']
  n: '--name'
  d: '--desc'
  t: '--type'
  a: '--token'
  u: '--user'
  v: '--verbose'
  h: '--help'

options = nopt known_opts, short_opts

options.tty = tty unless options.tty?

# Show the help?
if options.help
  console.log help
  return process.exit()

# Ensure the string is an gist id
ensureGistId = (id) ->
  id  = (url.parse id).pathname
  id  = id.slice(1) if '/' is id[0]
  return id

# Fetch mode? Fetch mode precedes gist creation.
if options.fetch
  client = new Client
  return client.get "/#{ensureGistId(options.fetch)}", (error, gist) ->
    throw error if error

    files    = Object.keys(gist.files)
    multiple = files.length > 1

    unless multiple
      return process.stdout.write gist.files[files[0]].content

    ret = []
    buf = ''
    for file in files
      buf += file + '\n'
      buf += new Array(file.length + 1).join '='
      buf += '\n\n' + gist.files[file].content
      ret.push buf
      buf = ''

    console.log ret.join

files = options.argv.remain

# Are we generating a oauth token?
is_gentoken = options.gentoken is yes

# Are we reading from stdin, or reading from a list of files?
is_stdin = options.argv.remain.length is 0

# We need to exhaust all the cases where the github user and token
# could be stored.
loadConfig = (callback) ->
  options.user     = process.env.GITHUB_USER     unless options.user
  options.password = process.env.GITHUB_PASSWORD unless options.password
  options.token    = process.env.GISTA_TOKEN     unless options.token

  if options.token
    options.user      = null
    options.password  = null
    return callback()

  task = async []

  task.push 'user'     unless options.user
  task.push 'password' unless options.password

  task
    .forEach (item, i, next) ->
      exec "git config --global github.#{item}", (error, stdout) ->
        return next() if error
        options[item] = stdout.trim()
        next()
    .exec (error, results) ->
      has_userpass  = (options.user and options.password) isnt null

      unless has_userpass
        options.user = options.password = null

      if error
        return callback error

      callback()

# Generate a oauth token with the already provided authorization
generateToken = ->
  # Change the client path so we can use the more generic Github API
  client.path = ''

  # The description for the token we need.
  authorization =
    scopes    : [ 'gist' ]
    note      : 'gista CLI'
    note_url  : 'https://github.com/tim-smart/gista'

  # Create the token
  client.post '/authorizations', authorization, (error, data) ->
    throw error if error

    unless data.token
      throw new Error 'Token generation refused by Github.'

    console.log data.token
    console.error """\nFor continued use of this token by the gista cli tool, make
                     you assign it to the GISTA_TOKEN environment variable in your
                     bash profile."""

# Star a gist from a given id
starGist = ->
  client.put "/#{ensureGistId(options.star)}/star", (error) ->
    throw error if error

# Delete a gist from a given id
deleteGist = ->
  client.delete "/#{ensureGistId(options.delete)}", (error) ->
    throw error if error

# Collect data on stdin as it comes in, buffer it, and then pass it
# on to `createGist`.
fromStdin = ->
  data  = ''
  first = yes
  process.stdin.resume()
  process.stdin.setEncoding 'utf8'
  process.stdin.on 'data', (chunk) ->
    if options.verbose
      if first
        process.stdout.write("> ")
        first = false
      process.stdout.write chunk.split("\n").join("\n> ")
    data += chunk
  process.stdin.on 'end', ->
    process.stdout.write("EOF\n") if options.verbose
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

  doneGist = (error, gist) ->
    throw error if error

    return process.stdout.write gist.html_url unless options.tty
    console.log gist.html_url

  # Are we an edit operation?
  if options.edit
    return client.patch "/#{ensureGistId(options.edit)}", gist, doneGist

  client.post '', gist, doneGist

# Load the user and token then either load the stdin data
# or parse out the files.
loadConfig (error) ->
  throw error if error

  client = new Client
    user      : options.user
    password  : options.password
    token     : options.token

  return starGist()      if options.star
  return deleteGist()    if options.delete
  return generateToken() if is_gentoken
  return fromStdin()     if is_stdin
  fromFiles()
