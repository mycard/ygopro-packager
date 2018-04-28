express = require 'express'
help = require './help'
lib = require './lib'
moment = require 'moment'

server = express()

running = null
last_report =
  status: 'null'
  start: null
  time: moment()

set_last_report = (status) ->
  last_report.status = status
  last_report.start = if running then running.start_time else null
  last_report.time = moment()

server.post '/pack', (req, res) ->
  # Only one process is allowed.
  if running
    res.statusCode = 403
    res.end "Another task started on " + running.start_time.format("YYYY-MM-DD HH:mm:ss") + " is running"
    return
  app_name = req.query.app || 'ygopro'

  # Set the running flag and return.
  running =
    promise: null,
    start_time: moment()
    data:
      main_progress: 0
      child_progress: -1
      progress_list: []
  res.end "processing " + app_name

  # Start process.
  running.promise = new Promise (resolve, reject) ->
    assets = await help.prepare app_name, running.data
    running.data.main_progress = 1
    console.log "Releases will process: " if process.env.NODE_ENV == "DEBUG"
    console.log assets if process.env.NODE_ENV == "DEBUG"
    running.data.progress_list = assets.map (asset) -> asset.release_name
    pass_count = 0
    for asset in assets
      running.data.child_progress = 0
      path = help.generate_path app_name, asset.release_name
      code = await lib.execute asset.b_name, asset.release_name, path.from_path, path.to_path, running.data
      pass_count += 1 if code > 0
      running.data.child_progress = 30
      await help.deploy path.to_path
      running.data.main_progress += 1
    console.log "Finished processing #{app_name}"
    set_last_report if pass_count == 0 then 'success' else 'unusual'
    running = null
    resolve 'ok'
  .catch (err) ->
    console.log "Packing failed because " + err
    set_last_report 'fail'
    running = null
    reject err

server.get '/last', (req, res) ->
  res.json last_report

server.get '/progress', (req, res) ->
  res.json running


server.listen 10087
