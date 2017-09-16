fs = require 'fs'
path = require 'path'
crypto = require 'crypto'
child_process = require 'child_process'
database = require './database'

readDir = (dir_path) ->
  files = fs.readdirSync dir_path
  result = []
  for file_name in files
    continue if file_name == '.' or file_name == ',,'
    full_path = path.join dir_path, file_name
    if fs.lstatSync(full_path).isDirectory()
      child_results = readDir full_path
      if child_results.length == 0
        result.push path.join file_name # Empty Dir
      else
        result = result.concat child_results.map (child_file) -> path.join file_name, child_file
    else
      result.push file_name # File
  result

calculateSHA256 = (file) ->
  new Promise (resolve, reject) ->
    resolve "" if fs.lstatSync(file).isDirectory()
    hash = crypto.createHash 'sha256'
    input = fs.ReadStream file
    input.on 'data', (d) -> hash.update d
    input.on 'error', (e) -> reject e
    input.on 'end', -> resolve hash.digest 'hex'

pack = (from, to, from_dir, to_dir) ->
  full_to_path = path.join to_dir, to
  from = from.join '" "'if Array.isArray from
  command = "tar -zcf \"#{full_to_path}\" -C #{from_dir} \"#{from}\""
  #console.log command
  await new Promise (resolve, reject) ->
    child_process.exec command, (err, stdout) ->
      if err then reject err else resolve ""
  sha = await calculateSHA256 full_to_path
  await new Promise (resolve, reject) -> fs.rename full_to_path, path.join(to_dir, sha + '.tar.gz'), -> resolve()
  console.log "packing " + from_dir + " [" + from + "]" + " to " + to_dir + " [" + to + "]" + sha if process.env.NODE_ENV == "DEBUG"
  sha

generateFullArchive = (source_path, target_path) ->
  files: [source_path],
  type: 'full'
  checksum: await pack '.', 'full.tar.gz', source_path, target_path

generateSeparateArchive = (source_path, files, target_path) ->
  answers = []
  for file in files
    answer = { files: [file], type: 'sand' }
    answer.checksum = await pack file, file.replace(/\//g, '_'), source_path, target_path
    answers.push answer
  console.log "Finish generate separate archives step."
  return answers


generateStrategyArchive = (b_name, release_name, new_release_files, source_path, target_path) ->
  releases = await database.loadRelease b_name
  release_names = releases.slice(0, 5).map (release) -> release.name
  promises = release_names.map (release_name) -> database.loadFiles release_name
  old_release_files_array = await Promise.all(promises)
  strategy_archives = []
  for old_release_files in old_release_files_array
    strategy_archive = await generateStrategyArchiveBetweenReleases("#{release_name}And#{if old_release_files[0] then old_release_files[0].release else 'emptyRelease'}", old_release_files, new_release_files, source_path, target_path)
    strategy_archives.push strategy_archive
  return strategy_archives

generateStrategyArchiveBetweenReleases = (pack_name, old_release, new_release, source_path, target_path) ->
  changed_files = compareRelease old_release, new_release
  changed_file_names = changed_files.map (file) -> file.name
  strategy_archive = { files: changed_file_names, type: 'strategy' }
  strategy_archive.checksum = await pack changed_file_names, pack_name, source_path, target_path
  strategy_archive

compareRelease = (old_release, new_release) ->
  old_release_hash = generateReleaseHash old_release
  new_release.filter (file) -> old_release_hash.get(file.name) != file.checksum

generateReleaseHash = (release) ->
  release_hash = new Map
  release_hash.set file.path, file.checksum for file in release
  release_hash

# For each RELEASE, execute generate:
# 0、Save the RELEASE itself to DATABASE.
# 1、ARCHIVES
#   Full ARCHIVE
#   Separate ARCHIVE
#   Strategy ARCHIVE according to VERSION ID
# 2、All ARCHIVE Index to FILE
# 3、All FILE Checksum
# 4、Full ARCHIVE meta4
execute = (b_name, release_name, release_source_path, release_target_path) ->
  console.log "Executing " + b_name + "/" + release_name + " from " + release_source_path + " to " + release_target_path
  release_archive_path = path.join release_target_path, 'archives'

  try fs.mkdirSync release_target_path
  try fs.mkdirSync release_archive_path

  files = readDir release_source_path

  # No.3 FILE checksum.
  console.log "Checking " + files.length + " Files"
  file_checksum = []
  for file in files
    checksum = { name: file }
    checksum.checksum = await calculateSHA256 path.join release_source_path, file
    file_checksum.push checksum  
  console.log "Saving Files to database."
  await database.saveFiles release_name, file_checksum
  console.log "Files inventory Step finished."

  # No.1 ARCHIVES
  archive_indices = []
  console.log "Generating full archive."
  archive_indices.push await generateFullArchive release_source_path, release_archive_path
  console.log "Generating separate archives."
  archive_indices = archive_indices.concat await generateSeparateArchive release_source_path, files, release_archive_path
  console.log "Generating strategy archives."
  result = await generateStrategyArchive(b_name, release_name, file_checksum, release_source_path, release_archive_path)
  archive_indices = archive_indices.concat result

  # Calculate File Size.
  console.log "Calculating file size."
  for archive_index in archive_indices
    state = fs.lstatSync path.join release_archive_path, archive_index.checksum + '.tar.gz'
    if state.isDirectory()
      archive_index.size = 0
    else
      archive_index.size = state.size
  console.log "Generate archive Step finished."

  # No.2 ARCHIVE Index
  console.log "Saving Archive files."
  await database.saveArchives release_name, archive_indices
  # fs.writeFileSync path.join(release_target_path, 'archive indices.json'), JSON.stringify(archive_indices, null, 1)

  # No.0 RELEASE itself.
  console.log "Saving Release."
  await database.saveRelease b_name, release_name

  # No.4 Full ARCHIVE meta4
  # This step is removed because I think it's not worth to mix the logistics for ￥0.1 flow fee.
  #metalink = Mustache.render template,
  #  name:
  #  size:
  #  hash:

  console.log "Finish executing " + b_name + "/" + release_name

module.exports.execute = execute
