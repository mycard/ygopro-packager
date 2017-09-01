express = require 'express'
help = require './help'
lib = require './lib'
moment = require 'moment'

server = express()

running = null

server.use '/*', (req, res, next) ->
  next()

server.post '/pack', (req, res) ->
  # Only one process is allowed.
  if running
    res.statusCode = 403
    res.end "Another task started on " + running.start_time.format("YYYY-MM-DD HH:mm:ss") + " is running"
    return
  app_name = req.query.app || 'ygopro'

  # Set the running flag and return.
  running = {
    promise: null,
    start_time: moment()
  }
  res.end "processing " + app_name

  # Start process.
  running.promise = new Promise (resolve, reject) ->
    assets = await help.prepare app_name
    console.log "Releases will process: " if process.env.NODE_ENV == "DEBUG"
    console.log assets if process.env.NODE_ENV == "DEBUG"
    for asset in assets
      path = help.generate_path app_name, asset.release_name
      await lib.execute asset.b_name, asset.release_name, path.from_path, path.to_path
      await help.deploy path.to_path
    console.log "Finished processing #{app_name}"
    running = null 
    resolve 'ok'

server.get '/progress', (req, res) ->


server.listen 10087
