require 'sys/filesystem'
require 'yaml'
require 'open3'
require 'logger'

$log_file_path = 'AutomatedAlpha.log'

# These steps are in order of when they should typically be performed.  Modify this section to only run certain steps.
$download_aws_database_backup = false
$extract_database_backup = false
$verify_space_exists_for_database_restore = false
$stop_services = false
$stop_app_servers = false
$stop_databases = false
$restore_database_from_backup = false
$start_databases = false
$scrub_database_and_run_progress_files = false
$start_app_servers = false
$start_services = false

# Runs the application.
def run(config_file_name)
  config = YAML.load_file(File.expand_path(config_file_name, File.dirname(__FILE__)))
  database_server_name = config['Database Server Name']
  broker_service_name = config['Broker Service Name']
  database_directory = config['Database Directory']
  database_file_name = config['Database Name']
  database_full_path = config['Database Directory'] + database_file_name
  structure_full_path = database_directory + config['Database Structure Name']
  openedge_directory = config['OpenEdge Install Directory']
  is_aws = config['AWS Database Server']
  aws_site_id = config['AWS Backup Site ID']
  extract_location = config['Backup Extract Location']
  backup_location = config['Backup Location'] # Only used for TierPoint sites.
  bak_file_folder = config['BAK File Path']
  service_list = config['Services']
  app_server_list = config['Progress AppServers']
  database_list = config['Progress Databases']
  scrubber_file_path = config['Scrubber']['File Path']
  scrubber_parameters = config['Scrubber']['Params']
  database_poll_attempts = config['Database Poll Attempts'].to_i
  existing_database_backup_path = config['Existing Database Backup Path']
  database_space = get_drive_space(database_directory) # 'get_drive_space' causes an error on DT031.  I believe DT031 has a different version of the sys/filesystem Gem.
  extract_location_space = get_drive_space(extract_location) # 'get_drive_space' causes an error on DT031.  I believe DT031 has a different version of the sys/filesystem Gem.
  $log_file_path = config['Output Log File Path']

  $logger = Logger.new($log_file_path)
  $logger.level = Logger::INFO

  log_event('Script - STARTING', false, true)

  if existing_database_backup_path.length > 0
    log_event("Using existing Database backup to restore from.  File located at: %s" % existing_database_backup_path, false, true)

    bak_file_path = existing_database_backup_path
  else
    if is_aws
      if $download_aws_database_backup
        log_event('Retrieve AWS database backup file path and download the backup file - STARTING', false, true)
      else
        log_event('Retrieve AWS database backup file path - STARTING', false, true)
      end

      full_backup_path = get_aws_database_backup_path($download_aws_database_backup, aws_site_id, extract_location, extract_location_space)

      if $download_aws_database_backup
        log_event('Retrieve AWS database backup file path and download the backup file - COMPLETED', false, false)
      else
        log_event('Retrieve AWS database backup file path - COMPLETED', false, false)
      end
    else
      log_event('Retrieve TierPoint database backup file path - STARTING', false, true)
      full_backup_path = get_tierpoint_database_backup_path(backup_location)
      log_event('Retrieve TierPoint database backup file path - COMPLETED', false, false)
    end

    log_event("full_backup_path: %s" % full_backup_path, false, false)

    log_event('Retrieve database backup file size and file name - STARTING', false, true)
    extracted_backup_size, extracted_file_name = get_extracted_backup_size_and_name(full_backup_path, bak_file_folder)
    log_event('Retrieve database backup file size and file name - COMPLETED', false, false)

    bak_file_path = extract_location + extracted_file_name

    log_event("BAK File Name: %s" % bak_file_folder, false, false)
    log_event("BAK File Path: %s" % bak_file_path, false, false)

    if $extract_database_backup
      log_event('Extract the database backup file - STARTING', false, true)
      extract_database_backup(bak_file_path, extracted_backup_size, extract_location_space, extract_location, full_backup_path)
      log_event('Extract the database backup file - COMPLETED', false, false)
    end

    if $verify_space_exists_for_database_restore
      log_event('Verifying spaces exists for the database restore - STARTING', false, true)
      size_is_ok = verify_space_exists_for_database_restore(openedge_directory, database_full_path, bak_file_path, database_space)

      if size_is_ok
        log_event('There is enough space to restore the database.', false, false)
      else
        # delete_file(bak_file_path)
        log_event("The database is too large to restore at %s location." % database_full_path, true, false)
      end
      log_event('Verifying spaces exists for the database restore - COMPLETED', false, false)
    end
  end

  if $stop_services
    log_event('Stop services - STARTING', false, true)
    stop_docutap_services(service_list)
    log_event('Stop services - COMPLETED', false, false)
  end

  if $stop_app_servers
    log_event('Stop app servers - STARTING', false, true)
    stop_docutap_app_servers(openedge_directory, app_server_list)
    log_event('Stop app servers - COMPLETED', false, false)
  end

  if $stop_databases
    log_event('Stop databases - STARTING', false, true)
    stop_docutap_databases(openedge_directory, database_list)
    log_event('Stop databases - COMPLETED', false, false)
  end

  if $restore_database_from_backup
    log_event('Restore database from backup file - STARTING', false, true)
    apply_database_from_backup(openedge_directory, database_directory, database_full_path, structure_full_path, bak_file_path, database_poll_attempts)
    log_event('Restore database from backup file - COMPLETED', false, false)
  end

  if $start_databases
    log_event('Start databases - STARTING', false, true)
    start_docutap_databases(openedge_directory, database_list)
    log_event('Start databases - COMPLETED', false, false)
  end

  if $scrub_database_and_run_progress_files
    log_event('Scrub database and run Progress files - STARTING', false, true)
    run_progress_files(openedge_directory, scrubber_file_path, scrubber_parameters, database_directory, database_file_name, database_server_name, broker_service_name)
    log_event('Scrub database and run Progress files - COMPLETED', false, false)
  end

  if $start_app_servers
    log_event('Start app servers - STARTING', false, true)
    start_docutap_app_servers(openedge_directory, app_server_list)
    log_event('Start app servers - COMPLETED', false, false)
  end

  if $start_services
    log_event('Start services - STARTING', false, true)
    start_docutap_services(service_list)
    log_event('Start services - COMPLETED', false, false)
  end

  log_event('Script - COMPLETED', false, true)
end

# Gets the path to the compressed (rar) database backup file.  Downloads the compressed database backup file (rar) if requested.
#
# @param download_from_aws [Boolean] the compressed database backup file will be downloaded from AWS if set to true.
# @param aws_site_id [String] the DocuTAP site ID (clinic ID) to retrieve the backup for.
# @param extract_location [String] the directory where the compressed database backup file may be copied to.
# @param extractLodationSpace [Number] The size in megabyes of the directory where the compressed database backup file may be copied to.
# @returns the path to the compressed database backup file.
def get_aws_database_backup_path(download_from_aws, aws_site_id, extract_location, extract_location_space)
  cmd_get_backup_rar_name = 'aws s3 ls s3://fullbackups.docutap.com/PROGRESS/' + aws_site_id + '/ | sort | tail -n 1 | awk \'{print $4}\''
  stdout, stderr, _status = Open3.capture3(cmd_get_backup_rar_name) # RETURNS: 20171223_01340662_OH001_HSBKPWFS001_docutap_F.rar

  if !stderr.to_s.empty?
    log_event('Unable to retrieve the RAR file name from AWS S3.', true, false)
  end

  backup_rar_name = stdout.to_s.chomp

  full_backup_path = extract_location + backup_rar_name

  # Check if RAR file has already been downloaded
  if download_from_aws
    if File.exist?(full_backup_path)
      log_event("Backup RAR file %s already exists." % full_backup_path, false, false)
    else
      log_event("Backup RAR file %s does not exist." % full_backup_path, false, false)

      # Get size of backup RAR file from S3.
      s3_rar_path = 's3://fullbackups.docutap.com/PROGRESS/' + aws_site_id + '/' + backup_rar_name
      cmd_get_rar_file_properties = 'aws s3 ls ' + s3_rar_path + ' --summarize'
      stdout, stderr, _status = Open3.capture3(cmd_get_rar_file_properties)
      if !stderr.to_s.empty?
        log_event('Unable to retrieve RAR file properties from AWS S3.', true, false)
      end

      rar_size_bytes = stdout.split(' ')[2].to_f
      # 1048576 (1024 * 1024) is used to convert from bytes to megabytes
      rar_size_mb = rar_size_bytes / 1048576

      log_event("Backup RAR file size: %s MB." % rar_size_mb, false, false)
      log_event("Size of extraction location %s : %s MB" % [extract_location, extract_location_space], false, false)

      # Determine if size of RAR file is too big for backup extraction location
      # Allow for 10% extra drive space
      if (rar_size_mb * 1.1) > extract_location_space
        log_event('There is not enough room in the backup extraction location for the backup RAR file to be downloaded from AWS S3.', true, false)
      end

      log_event("Copying RAR file from %s to %s" % [s3_rar_path, extract_location], false, false)
      cmd_copy_rar_from_s3 = 'aws s3 cp ' + s3_rar_path + ' ' + extract_location

      _stdout, stderr, _status = Open3.capture3(cmd_copy_rar_from_s3)
      if !stderr.to_s.empty?
        log_event("An Error has Occurred \n ERROR: %s \n CMD: %s" % [stderr.to_s, cmd_copy_rar_from_s3], false, false)
        log_event('Unable to copy backup RAR file from AWS S3 to local drive.', true, false)
      end
      log_event('RAR backup file copied from S3', false, false)
    end
  end

  return full_backup_path
end

# Gets the UNC path for a TierPoint database backup.
#
# @param backup_location [String] the UNC path to the remote directory where the database backup file is to be copied from.
# EXAMPLE OUTPUT: \\hsbkpwfs001\NR\OH001\AI\blahblahblah_s3_full.rar
def get_tierpoint_database_backup_path(backup_location)
  full_backup_path = backup_location + get_backup_file_name(backup_location) # \\hsbkpwfs001\NR\OH001\AI\blahblahblah_s3_full.rar
  return full_backup_path
end

def extract_database_backup(bak_file_path, extracted_backup_size, extract_location_space, extract_location, full_backup_path)  
  if File.exist?(bak_file_path)
    log_event("Extracted datbase backup file %s already exists. \n No need to extract." % bak_file_path, false, false)
  else
    log_event("Extracted database backup file %s does not exist. \n Attempting to extract." % bak_file_path, false, false)
    if extracted_backup_size > extract_location_space
      log_event("The extracted backup is too large for the %s location." % extract_location, true, false)
    else
      log_event('There is enough space to extract backup file.', false, false)
    end
    extract_rar_to_directory(full_backup_path, extract_location)
  end
end

# Compares the size of the database to the size of the database backup (bak) file
#   to determine whether there is enough space to restore the database backup.
#
# @param openedge_directory [String] the directory location for OpenEdge.
# @param database_full_path [String] the directory of the database and the database name.
# @param bak_file_path [String] the path to the database backup file.
# @param database_space [Number] The size of the docutap database in megabytes.
# @returns [Boolean] true if there is enough space to restore the database, otherwise false.
def verify_space_exists_for_database_restore(openedge_directory, database_full_path, bak_file_path, database_space)
  size_is_ok = true

  backup_space = get_backup_size_on_disk(openedge_directory, database_full_path, (bak_file_path))

  log_event("Backup Space: %s" % backup_space, false, false)
  log_event("Database Space: %s" % database_space, false, false)
  if backup_space > database_space
    size_is_ok = false;
  end

  return size_is_ok
end

# Gets the size of the database backup.
#
# @param openedge_directory [String] the directory location for OpenEdge.
# @param database_full_path [String] the directory of the database and the database name.
# @param extract_full_path [String] the path to the database backup (bak) file.
def get_backup_size_on_disk(openedge_directory, database_full_path, extract_full_path)
  log_event("Open Edge Dir: %s" % openedge_directory, false, false)
  log_event("DB Full Path: %s" % database_full_path, false, false)
  log_event("Extract Full Path: %s" % extract_full_path, false, false)
  if !File.exist?(extract_full_path)
    log_event("The extracted backup at %s does not exist." % [extract_full_path], true, false)
  end

  cmd_backup_area_sizes = '"' << openedge_directory << 'bin\prorest" ' << '"' << database_full_path << '.db" "' << extract_full_path << '" -list'

  stdout, _stderr, _status =  Open3.capture3(cmd_backup_area_sizes)

  log_event(stdout, false, false)

  area_sizes = stdout.scan(/((?<=Size: )[^,\n]*(?=,))/)
  area_records_per_block = stdout.scan(/((?<=Records\/Block: )[^,\n]*(?=,))/)
  area_details = area_sizes.zip(area_records_per_block)
  database_size_sum = 0
  valAs = 0
  valArpb = 0
  area_details.each do |ad|
    _area_size = 0
    valAs = ((ad[0][0]))
    valArpb = ((ad[1][0]))
=begin
  The code below checks for a size of N/A. This most likely occurs when parsing the Records/Block of
  the Primary Recovery Area. This area is defined as N/A because the size varies based on application
  usage. More information can be found at https://documentation.progress.com/output/ua/OpenEdge_latest/index.html#page/gsdbe%2FPrimary_recovery_area_2.html%23
    This size is usually small (<1gb), and is neglegable in the calcuation.
=end
    if valAs == 'N/A'
      valAs = '0'
    end
    valAs = valAs.to_i

    if valArpb == 'N/A'
      valArpb = '0'
    end
    valArpb = valArpb.to_i

    if valArpb > 0 && valAs > 0
      # As of the creation date of this application, 4096 is the default block size of the DocuTAP application
      area_size = (valAs / valArpb) * 4096
      database_size_sum += area_size
    end
  end
  return (database_size_sum / 1048576)
end

# Gets the available space of a given drive.
#
# @param drive [String] the drive to retrieve the available drive space for.
# @returns [Number] the size (in megabytes) of free drive space.
def get_drive_space(drive)
  stat = Sys::Filesystem.stat(drive)
  # 1048576 (1024 * 1024) is used to convert from bytes to megabytes
  mb_available = (stat.block_size * stat.blocks_available).to_f / 1048576
  return mb_available
end

# Gets the size and name of the extracted database backup (bak) file.
#
# @param full_backup_path [String] the directory where the backup file was extracted.
# @param bak_file_folder [String] the directory in the extracted location to search within.
# @returns [Number] the size of the database backup file and [String] the name of the database backup file.
def get_extracted_backup_size_and_name(full_backup_path, bak_file_folder)
  log_event("full_backup_path: %s" % full_backup_path, false, false)
  log_event("bak_file_folder: %s" % bak_file_folder, false, false)

  cmd = '"C:\Program Files\WinRAR\UnRAR.exe" vt "' + full_backup_path + '"'
  stdout, _stderr, _status = Open3.capture3(cmd)

  log_event(stdout, false, false)
  log_event("back file length: %s" % bak_file_folder.to_s.length, false, false)

  if bak_file_folder.to_s.length > 0
    file_name = stdout[(/(?<=(Name: ))#{Regexp.escape(bak_file_folder)}[a-zA-Z0-9_-]*.bak/)]
  else
    file_name = stdout[(/(?<=(Name: ))[a-zA-Z0-9_-]*.bak/)]
  end

  size_mb = stdout[(/(?<=(Size: ))\d*/)].to_f / 1048576

  log_event(file_name, false, false)
  log_event(size_mb, false, false)

  return size_mb, file_name
end

# Gets the name of the compressed database backup file.
#
# @param backup_path [String] the directory to check for a compressed (RAR) database backup file in.
# @returns [String] the full path to the compressed database backup file.
def get_backup_file_name(backup_path)
  if !Dir[backup_path].empty?
    log_event("The directory at %s is empty" % [backup_path], true, false)
  else
    Dir.foreach(backup_path) do |item|
      if item.match(/.*(_full_s3.rar)/)
        return item
      end
    end
  end
end

# Stop Windows services
#
# @param service_list [Array <String>] the names of the Windows services to be stopped.
def stop_docutap_services(service_list)
  service_list.each do |service|
    log_event("Stopping %s service." % [service], false, false)

    output = `net stop "#{service}" 2>&1`

    log_event(output, false, false)
  end
end

# Stop OpenEdge application servers.
#
# @param openedge_directory [String] the directory location of OpenEdge.
# @param app_server_list [Array <String>] the names of app servers to be stopped in OpenEdge Explorer.  
def stop_docutap_app_servers(openedge_directory, app_server_list)
  Dir.chdir("#{openedge_directory}\\bin") do
    app_server_list.each do |app_server|
      log_event("Stopping %s app server." % [app_server], false, false)

      output = `asbman -name #{app_server} -stop 2>&1`

      log_event(output, false, false)
    end
  end
end

# Stop OpenEdge databases.
#
# @param openedge_directory [String] the directory location of OpenEdge.
# @param database_list [Array <String>]  the names of databases to be stopped in OpenEdge Explorer.  
def stop_docutap_databases(openedge_directory, database_list)
  Dir.chdir("#{openedge_directory}\\bin") do
    database_list.each do |database|
      log_event("Stopping %s app database." % [database] , false, false)

      output = `dbman -name #{database} -stop 2>&1`

      log_event(output, false, false)
    end
  end
end

# Start Windows services
#
# @param service_list [Array <String>] the names of the Windows services to be started.
def start_docutap_services(service_list)
  service_list.each do |service|
    log_event("Starting %s service." % [service], false, false)

    output = `net start "#{service}" 2>&1`

    log_event(output, false, false)
  end
end

# Start OpenEdge application servers.
#
# @param openedge_directory [String] the directory location of OpenEdge.
# @param app_server_list [Array <String>] the names of app servers to be started in OpenEdge Explorer.
def start_docutap_app_servers(openedge_directory, app_server_list)
  Dir.chdir("#{openedge_directory}\\bin") do
    app_server_list.each do |app_server|
      log_event("Starting %s app server." % [app_server], false, false)

      output = `asbman -name #{app_server} -start 2>&1`

      log_event(output, false, false)
    end
  end
end

# Start OpenEdge databases.
#
# @param openedge_directory [String] the directory location of OpenEdge.
# @param database_list [Array <String>]  the names of databases to be started in OpenEdge Explorer.
def start_docutap_databases(openedge_directory, database_list)
  Dir.chdir("#{openedge_directory}\\bin") do
    database_list.each do |database|
      log_event("Starting %s database." % [database], false, false)

      output = `dbman -name #{database} -start 2>&1`

      log_event(output, false, false)
    end
  end
end

# Extracts the compressed database backup file to a given directory.
#
# @param full_backup_path [String] the path to the compressed database backup file (RAR).
# @param extract_location [String] the directory to extract the database backup file to.
def extract_rar_to_directory(full_backup_path, extract_location)
  cmd = '"C:\Program Files\WinRAR\unrar.exe" x "' << full_backup_path << '" "' << extract_location << '"'
  _stdout, _stderr, _status = Open3.capture3(cmd)
  # stdoutArr = stdout.split("\n")
end

# Restores the database from a backup.
#
# @param openedge_directory [String] the directory location for OpenEdge.
# @param database_directory [String] the directory of the database to be restored.
# @param database_full_path [String] the directory of the database and the database name.
# @param database_structure_full_path [String] the database structure path.
# @param bak_file_path [String] the path to the database backup file.
# @param database_poll_attempts [String] the number of attempts to poll the database to see if it's shut down before giving up.
def apply_database_from_backup(openedge_directory, database_directory, database_full_path, database_structure_full_path, bak_file_path, database_poll_attempts)  
=begin
    The following line enables large file processing for a database. According to the knowledge base articlee
    below, this should not cause issues for servers running versions greater than 9.1C of Progress. There
    is no command to disable large file processing for a database, and once enabled cannot run on Progress 
    versions prior to 9.1C.
    http://knowledgebase.progress.com/articles/Article/21184
=end
  cmd_list = []
  cmd_check_database_running = '"' << openedge_directory << 'bin\proutil" '<< '"' << database_full_path << '" -C holder'
  # cmdDeleteDb = 'echo y | "' << openedge_directory << 'bin\prodel" '<< '"' << database_full_path << '"'
  cmdRestoreFromStruct = '"' << openedge_directory << 'bin\prostrct" create ' << '"' << database_structure_full_path << '"'
  cmdEnableLargeFiles = '"' << openedge_directory << 'bin\proutil" ' << '"' << database_full_path << '"' << ' -C enablelargefiles'

  if !File.exist?(bak_file_path)
    log_event("The extracted backup at %s does not exist." % bak_file_path, true, false)
  end

  # Only test that the database is running if the docutap.db file exists
  #   in case this is a new site without an existing database.
  if File.exist?(database_directory + 'docutap.db')
    database_running = true
    database_poll_attempts = database_poll_attempts

    log_event('Checking if DB is running.', false, false)
    log_event('CMD: ' + cmd_check_database_running, false, false)

    while database_running && database_poll_attempts > 0
      stdout, stderr, status = Open3.capture3(cmd_check_database_running)    

      database_in_use = stdout[(/\*\*/)]

      if !database_in_use
        database_running = false
        log_event('DB is not running.', false, false)
      else
        log_event('DB is running.', false, false)
        log_event(stdout, false, false)
      end

      sleep(10)

      database_poll_attempts = database_poll_attempts - 1

      if database_poll_attempts == 0
        log_event("The database failed to shutdown after %s attempts." % [database_poll_attempts], true, false)
      end
    end
  end

  cmd_restore_backup = 'echo y | "' << openedge_directory << 'bin\prorest" ' << '"' << database_full_path << '.db" "' << bak_file_path << '" -verbose'
  # cmd_list.push(cmdDeleteDb)
  cmd_list.push(cmdRestoreFromStruct)
  cmd_list.push(cmdEnableLargeFiles)
  cmd_list.push(cmd_restore_backup)

  Dir.chdir(database_directory) do
    log_event("Database Directory: %s" % database_directory, false, false) 
    cmd_list.each do |cmd|
      log_event("CMD: %s" % cmd, false, false)

      stdout, stderr, status = Open3.capture3(cmd)    

      log_event("StdOut: %s" % stdout, false, false)

      if stderr != ""
        log_event("There was a problem restoring the backup with the following error: \n%s" % [stderr], true, false)
      end
    end
  end
end

# Run the database Scrubber utility.
#
# @param openedge_directory [String] the directory for OpenEdge.
# @param scrubber_file_path [String] the path to the scrubber utility.
# @param database_directory [String] the directory of the database to be scrubbed.
# @param database_file_name [String] the name of the database to be scrubbed.
# @param database_server_name [String] the name of the database server.
# @param broker_service_name [String] The service name of the broker process.
def run_progress_files(openedge_directory, scrubber_file_path, scrubber_parameters, database_directory, database_file_name, database_server_name, broker_service_name)

=begin
  _progres.exe paramaters:
    -p: filepath of the .p to be run
    -param: the paramaters passed to the .p or .r script
    -H: the hostname of the server the script is ran on
    -S: the Service Name of the broker process on the host machine
    -db: physical database file path
    -mmax: the max allocated memory for .r scripts (this will throw a warning if exceeded, but will not error out)
    -D: the number of compiled procedure directory entries (this will throw a warning if exceeded, but will not error out)
    -b: if flag is set, _progress.exe runs in 'batch-mode'
    -s: stack size in 1 kb units
=end

  database = database_directory + database_file_name + '.db'

  cmd = '"' << openedge_directory << 'bin\\_progres.exe" -p ' << scrubber_file_path << ' ' << scrubber_parameters << ' -H ' << database_server_name << ' -S ' << broker_service_name << ' -db ' << database << ' -mmax 8000 -U sysprogress -P docutap -debugalert -noinactiveidx' << ' -D 15000 -s 128 -b '

  Dir.chdir(database_directory) do
    log_event('Starting scrubber.', false, false)
    log_event("Scrubber Command: %s" % cmd, false, false)

    stdout, stderr, _status = Open3.capture3(cmd)

    log_event("Scrubber Standard Out: %s: " % stdout, false, false)
    log_event("Scrubber Standard Error: %s: " % stderr, false, false)
    log_event('Scrubber has completed.', false, false)
  end
end

# Deletes the file at the given path.
#
# @param file_path [String] The path to the file to be deleted.
def delete_file(file_path)
  cmd = "del #{file_path}"
  if File.exist?(file_path)
    _stdout, _stderr, _status = Open3.capture3(cmd)

    log_event("Deleted File: %s" % file_path, false)
  else
    log_event("The file at %s does not exist." % [file_path], true)
  end
end

# Outputs a given message to the log.
#
# @param message [String] the message to be logged.
# @param abort_script [Boolean] true to exit the Ruby script, false if not.
# @param add_section_break [Boolean] true to add a visual 'break' to the log, false if not.
def log_event(message, abort_script, add_section_break)
  if add_section_break
    $logger.info('************************************************************************************************************************')
  end

  if abort_script
    $logger.fatal(message.to_s)
    raise message.to_s
  else
    $logger.info(message.to_s)
  end
end

if ARGV.empty?
  puts "ERROR RUNNING SCRIPT: Please pass the configuration YAML file name as a command parameter."
else
  run(ARGV[0])
end