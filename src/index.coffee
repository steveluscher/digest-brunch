crypto  = require 'crypto'
fs      = require 'fs'
pathlib = require 'path'
glob    = require 'glob'

DIGEST_RE = "DIGEST\\((.+?)\\)"

warn = (message) -> console.warn "digest-brunch WARNING: #{message}"

class Digest
  brunchPlugin: true

  constructor: (@config) ->

    # Defaults options
    @options = {
      # RegExp that matches files that contain DIGEST references.
      referenceFiles: /\.html$/
      # How many digits of the SHA1 to append to digested files.
      precision: 8
      # Force digest-brunch to run in all environments when true.
      alwaysRun: false
    }

    # Merge config
    cfg = @config.plugins?.digest ? {}
    @options[k] = cfg[k] for k of cfg

  onCompile: ->
    @publicFolder = @config.paths.public
    allFiles = glob.sync("#{@publicFolder}/**")
    referenceFiles = @_referenceFiles(allFiles)

    if @config.env.indexOf('production') is -1 and !@options.alwaysRun
      # Replace DIGEST() references with regular file name if not running.
      @_removeReferences(referenceFiles)
    else
      if @config.server?.run
        warn 'Not intended to be run with on-demand compilation (brunch watch)'

      if @options.precision < 6
        warn 'Name collision more likely when less than 6 digits of SHA used.'

      filesToDigest = @_filesToDigest(referenceFiles)
      filesAndDigests = @_filesAndDigests(filesToDigest)
      renameMap = @_renameMap(filesAndDigests)
      @_renameAndReplace(referenceFiles, renameMap)

  _validDigestFile: (file) ->
    if !fs.existsSync(file)
      warn "Missing DIGEST file #{file} referenced. Skipping."
      return false

    fs.statSync(file).isFile()

  _referenceFiles: (files) ->
    referenceFiles = []
    for file in files
      referenceFiles.push file if @options.referenceFiles.test(file)
    referenceFiles

  # Internal: Find files that need a digest in all valid reference files.
  #
  # files - An array of files that may contain digest references.
  #
  # Returns an array of filenames.
  _filesToDigest: (files) ->
    filesToDigest = []
    for file in files
      digestRe = new RegExp(DIGEST_RE, 'g')
      contents = fs.readFileSync(file).toString()
      match = digestRe.exec(contents)
      while match isnt null
        filesToDigest.push match[1]
        match = digestRe.exec(contents)

    filesToDigest

  # Internal: Generate a hash of filenames to their digests.
  #
  # files - An array of files.
  #
  # Returns an object with keys of filenames and value of the digest.
  _filesAndDigests: (files) ->
    precision = @options.precision
    filesAndDigests = {}
    for file in files
      file = pathlib.join(@publicFolder, file)
      if @_validDigestFile(file)
        data = fs.readFileSync file
        shasum = crypto.createHash 'sha1'
        shasum.update(data)
        relativePath = pathlib.relative(@publicFolder, file)
        filesAndDigests[relativePath] = shasum.digest('hex')[0..precision-1]
    filesAndDigests

  _renameAndReplace: (referenceFiles, renameMap) ->
    # Rename digest files
    for originalFilename, newFilename of renameMap
      originalPath = pathlib.join(@publicFolder, originalFilename)
      newPath = pathlib.join(@publicFolder, newFilename)
      fs.renameSync(originalPath, newPath)

    # Replace occurances of that file in reference files.
    @_replaceReferences(referenceFiles, renameMap)

  # Internal: Make a mapping of files to their renamed version containing the
  # digest.
  #
  # filesAndDigests - an object with keys of filenames and value of the
  # digest.
  #
  # Returns an object with keys of filenames and values of the new filename
  _renameMap: (filesAndDigests) ->
    renameMap = {}
    for path, digest of filesAndDigests
      directory = pathlib.dirname(path)
      extname = pathlib.extname(path)
      filename = pathlib.basename(path, extname)

      digestFilename = "#{filename}-#{digest}#{extname}"
      digestPath = pathlib.join(directory, digestFilename)
      renameMap[path] = digestPath
    renameMap

  _replaceReferences: (referenceFiles, renamedFiles) ->
    for referenceFile in referenceFiles
      contents = fs.readFileSync(referenceFile).toString()

      for originalFile, renamedFile of renamedFiles
        escaped = originalFile.replace('.', "\\.")
        fileRe = new RegExp("DIGEST\\(#{escaped}\\)", 'g')
        contents = contents.replace(fileRe, renamedFile)

        # Also replace occurances of /filename with /filename-digest
        fileWithSlashRe = new RegExp("DIGEST\\(/#{escaped}\\)", 'g')
        contents = contents.replace(fileWithSlashRe, "/#{renamedFile}")

      fs.writeFileSync(referenceFile, contents)

  _removeReferences: (files) ->
    for file in files
      contents = fs.readFileSync(file).toString()
      digestRe = new RegExp(DIGEST_RE, 'g')
      contents = contents.replace(digestRe, '$1')
      fs.writeFileSync(file, contents)

module.exports = Digest
