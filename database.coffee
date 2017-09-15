{ Pool } = require 'pg'
pg = require 'pg'
config = require './config.json'

SAVE_RELEASE = 'insert into releases (b, name, created_at) values ($1::text, $2::text, (current_timestamp(0)::timestamp without time zone))'
SAVE_ARCHIVES = 'insert into archives (release, checksum, type, size) values '
SAVE_ARCHIVE_FILES = 'insert into archive_files values '
SAVE_FILES = 'insert into files values '
LOAD_RELEASE = 'select * from releases values where b = $1::text order by created_at desc'
LOAD_ARCHIVES = 'select * from archives inner join archive_files on archive_files.archive = archives.checksum where archives.release = $1::text'
LOAD_FILES = 'select * from files where release = $1::text'

pg.types.setTypeParser 1114, (stringValue) -> new Date(stringValue + '+0000')

pool = new Pool config.database

saveRelease = (b_name, release_name) ->
  new Promise (resolve, reject) ->
    pool.query SAVE_RELEASE, [b_name, release_name], (err, result) -> returning_promise_handle err, result, resolve, reject


saveArchives = (release_name, archives) ->
  count = 0
  max_count = 1000
  archive_files_will_execute = []
  archives_will_execute = []
  for archive in archives
    values = archive.files.map (file) -> "('#{archive.checksum}', '#{file}')"
    archive_files_will_execute = archive_files_will_execute.concat values
    archives_will_execute = archives_will_execute.concat "('#{release_name}', '#{archive.checksum}', '#{archive.type}', #{archive.size})"
    count += values.length
    if count >= max_count
      console.log "Execute save archive files for #{count} key/values." if process.env.NODE_ENV == "DEBUG"
      #console.log SAVE_ARCHIVE_FILES + archive_files_will_execute.join(', ')
      #console.log SAVE_ARCHIVES + archives_will_execute.join(', ')
      await pool.query SAVE_ARCHIVE_FILES + archive_files_will_execute.join(', '), []
      await pool.query SAVE_ARCHIVES + archives_will_execute.join(', '), []
      archive_files_will_execute = []
      archives_will_execute = []
      count = 0
  console.log "Execute save archive files for #{count} key/values." if process.env.NODE_ENV == "DEBUG"
  await pool.query SAVE_ARCHIVE_FILES + archive_files_will_execute.join(', '), []
  await pool.query SAVE_ARCHIVES + archives_will_execute.join(', '), []

  # Promise.all(promises)

saveFiles = (release_name, files) ->
  values = files.map (file) -> "('#{file.name}', '#{file.checksum}', '#{release_name}')"
  new Promise (resolve, reject) ->
    pool.query SAVE_FILES + values.join(', '), [], (err, result) -> returning_promise_handle err, result, resolve, reject

loadRelease = (b_name) ->
  new Promise (resolve, reject) ->
    pool.query LOAD_RELEASE, [b_name], (err, result) -> returning_promise_handle err, result, resolve, reject

loadArchives = (release_name) ->
  new Promise (resolve, reject) ->
    pool.query LOAD_ARCHIVES, [release_name], (err, result) ->
      if err
        console.log err
        reject err
      else
        archives = new Map
        for row in result.rows
          if archives.has row.archive
            archives.get(row.archive).files.push row.file
          else
            archives.set row.archive,
              release: release_name
              size: row.size
              type: row.type
              checksum: row.checksum
              file: [row.file]
        resolve archives

loadFiles = (release_name)  ->
  new Promise (resolve, reject) ->
    pool.query LOAD_FILES, [release_name], (err, result) -> returning_promise_handle err, result, resolve, reject

returning_promise_handle = (err, result, resolve, reject) ->
  if err
    console.log err
    reject err
  else
    resolve result.rows

module.exports.saveRelease = saveRelease
module.exports.saveArchives = saveArchives
module.exports.saveFiles = saveFiles
module.exports.loadRelease = loadRelease
module.exports.loadArchives = loadArchives
module.exports.loadFiles = loadFiles
