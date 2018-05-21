require 'sys/filesystem'
require 'yaml'
require 'open3'
require 'socket'

$logFilePath = "unknown"

# These steps are in order of when they should typically be performed.  Modify this section to only run certain steps.
$downloadAwsDatabaseBackup = false
$extractDatabaseBackup = false
$verifySpaceExistsForDatabaseRestore = false
$stopServices = false
$stopAppServers = false
$stopDatabases = false
$restoreDatabaseFromBackup = false
$startDatabases = false
$scrubDatabaseAndRunProgressFiles = false
$startAppServers = false
$startServices = false
$deleteDatabaseBackupFile = false
$deleteExtractedDatabaseFile = false

# Runs the application.
def run	
	config = YAML.load_file(File.expand_path('config.yml', File.dirname(__FILE__)))
	databaseDir = config["Database Directory"]
	databaseFileName = config["Database Name"]
	databaseFullPath = config["Database Directory"] + databaseFileName
	structureFullPath = databaseDir + config["Database Structure Name"]
	openEdgeDir = config["OpenEdge Install Directory"]
	isAWS = config["AWS Database Server"]
	awsSiteId = config["AWS Backup Site ID"]
	extractLocation = config["Backup Extract Location"]
	backupLocation = config["Backup Location"] #Only used for TierPoint sites.
	bakFileFolder = config["BAK File Path"]
	serviceList = config["Services"]
	appServerList = config["Progress AppServers"]
	databaseList = config["Progress Databases"]
	scrubberFilePath = config["Scrubber"]["File Path"]
	scrubberParams = config["Scrubber"]["Params"]
	databasePollAttempts = config["Database Poll Attempts"].to_i
	existingDbBackupPath = config["Existing Database Backup Path"]
	databaseSpace = getDriveSpace(databaseDir) # "getDriveSpace" causes an error on DT031.  I believe DT031 has a different version of the sys/filesystem Gem.
	extractLocationSpace = getDriveSpace(extractLocation) # "getDriveSpace" causes an error on DT031.  I believe DT031 has a different version of the sys/filesystem Gem.
	$logFilePath = config["Output Log File Path"]
		
	logEvent("Script - STARTING", false, true)
	
	if existingDbBackupPath.length > 0 then
		logEvent("Using existing Database backup to restore from.  File located at: %s" % existingDbBackupPath, false, true)
		
		bakFilePath = existingDbBackupPath
	else
		if isAWS then
			if $downloadAwsDatabaseBackup then
				logEvent("Retrieve AWS database backup file path and download the backup file - STARTING" , false, true)
			else 
				logEvent("Retrieve AWS database backup file path - STARTING", false, true)
			end
			
			fullBackupPath = getAwsDatabaseBackupPath($downloadAwsDatabaseBackup, awsSiteId, extractLocation, extractLocationSpace)
			
			if $downloadAwsDatabaseBackup then
				logEvent("Retrieve AWS database backup file path and download the backup file - COMPLETED" , false, false)
			else 
				logEvent("Retrieve AWS database backup file path - COMPLETED", false, false)
			end
		else 
			logEvent("Retrieve TierPoint database backup file path - STARTING", false, true)
			fullBackupPath = getTierPointDatbaseBackupPath(bakFilePath, backupLocation, extractedBackupSize, extractLocation, extractLocationSpace)
			logEvent("Retrieve TierPoint database backup file path - COMPLETED", false, false)
		end
		
		logEvent("fullBackupPath: %s" % fullBackupPath, false, false)
		
		logEvent("Retrieve database backup file size and file name - STARTING", false, true)
		extractedBackupSize, extractedFileName = getExtractedBackupSizeAndName(fullBackupPath, bakFileFolder)
		logEvent("Retrieve database backup file size and file name - COMPLETED", false, false)
	
		bakFilePath = extractLocation + extractedFileName
		
		logEvent("BAK File Name: %s" % bakFileFolder, false, false)
		logEvent("BAK File Path: %s" % bakFilePath, false, false)
		
		if $extractDatabaseBackup then 
			logEvent("Extract the database backup file - STARTING", false, true)
			extractDatabaseBackup(bakFilePath, extractedBackupSize, extractLocationSpace, extractLocation, fullBackupPath)
			logEvent("Extract the database backup file - COMPLETED", false, false)
		end
		
		if $verifySpaceExistsForDatabaseRestore then	
			logEvent("Verifying spaces exists for the database restore - STARTING", false, true)	
			sizeOk = verifySpaceExistsForDatabaseRestore(openEdgeDir, databaseFullPath, bakFilePath, databaseSpace)
			
			if sizeOk then
				logEvent("There is enough space to restore the database." , false, false)
			else
				#deleteFile(bakFilePath)
				logEvent("The database is too large to restore at %s location." % databaseFullPath, true, false)
			end
			logEvent("Verifying spaces exists for the database restore - COMPLETED", false, false)
		end
	end 	
	
	if $stopServices then
		logEvent("Stop services - STARTING", false, true)
		stopDocutapServices(serviceList)
		logEvent("Stop services - COMPLETED", false, false)
	end
	
	if $stopAppServers then
		logEvent("Stop app servers - STARTING", false, true)
		stopDocutapAppServers(openEdgeDir, appServerList)
		logEvent("Stop app servers - COMPLETED", false, false)
	end
	
	if $stopDatabases
		logEvent("Stop databases - STARTING", false, true)
		stopDocutapDatabases(openEdgeDir, databaseList)
		logEvent("Stop databases - COMPLETED", false, false)
	end
	
	if $restoreDatabaseFromBackup then
		logEvent("Restore database from backup file - STARTING", false, true)
		applyDbFromBackup(openEdgeDir, databaseDir, databaseFullPath, structureFullPath, bakFilePath, databasePollAttempts)
		logEvent("Restore database from backup file - COMPLETED", false, false)
	end
		
	if $startDatabases then
		logEvent("Start databases - STARTING", false, true)
		startDocutapDatabases(openEdgeDir, databaseList)
		logEvent("Start databases - COMPLETED", false, false)
	end
	
	if $scrubDatabaseAndRunProgressFiles then
		logEvent("Scrub database and run Progress files - STARTING", false, true)
		runProgressFiles(openEdgeDir, scrubberFilePath, scrubberParams, databaseDir, databaseFileName)
		logEvent("Scrub database and run Progress files - COMPLETED", false, false)
	end
	
	if $startAppServers then
		logEvent("Start app servers - STARTING", false, true)
		startDocutapAppServers(openEdgeDir, appServerList)
		logEvent("Start app servers - COMPLETED", false, false)
	end
	
	if $startServices then
		logEvent("Start services - STARTING", false, true)
		startDocutapServices(serviceList)
		logEvent("Start services - COMPLETED", false, false)
	end
	
	if $deleteDatabaseBackupFile then
		if isAWS then
			logEvent("Deleting database backup file copied from AWS S3 - STARTING", false, true)
			deleteFile(fullBackupPath)
			logEvent("Deleting database backup file copied from AWS S3 - COMPLETED", false, false)
		end
	end
	
	if $deleteExtractedDatabaseFile then
		logEvent("Deleting extracted database backup file - STARTING", false, true)
		deleteFile(bakFilePath)
		logEvent("Deleting extracted database backup file - COMPLETED", false, false)
	end

	logEvent("Script - COMPLETED", false, true)
end

# Gets the path to the compressed (rar) database backup file.  Downloads the compressed database backup file (rar) if requested.
# 
# @param downloadFromAws [Boolean] the compressed database backup file will be downloaded from AWS if set to true.
# @param awsSiteId [String] the DocuTAP site ID (clinic ID) to retrieve the backup for.
# @param extractLocation [String] the directory where the compressed database backup file may be copied to.
# @param extractLodationSpace [Number] The size in megabyes of the directory where the compressed database backup file may be copied to.
# @returns the path to the compressed database backup file.
def getAwsDatabaseBackupPath(downloadFromAws, awsSiteId, extractLocation, extractLocationSpace)
	cmdGetBackupRarName = 'aws s3 ls s3://fullbackups.docutap.com/PROGRESS/' + awsSiteId + '/ | sort | tail -n 1 | awk \'{print $4}\''
	stdout, stderr, status =  Open3.capture3(cmdGetBackupRarName) #RETURNS: 20171223_01340662_OH001_HSBKPWFS001_docutap_F.rar
	
	if !stderr.to_s.empty? then
		logEvent("Unable to retrieve the RAR file name from AWS S3.", true, false)
	end
	
	backupRarName = stdout.to_s.chomp 
	
	fullBackupPath = extractLocation + backupRarName
	
	#Check if RAR file has already been downloaded
	if downloadFromAws then
		if File.exist?(fullBackupPath) then
			logEvent("Backup RAR file %s already exists." % fullBackupPath, false, false)
		else
			logEvent("Backup RAR file %s does not exist." % fullBackupPath, false, false)
		
			#Get size of backup RAR file from S3.
			s3RarPath = 's3://fullbackups.docutap.com/PROGRESS/' + awsSiteId + '/' + backupRarName
			cmdGetRarFileProperties = 'aws s3 ls ' + s3RarPath + ' --summarize'
			stdout, stderr, status =  Open3.capture3(cmdGetRarFileProperties)
			if !stderr.to_s.empty? then
				logEvent("Unable to retrieve RAR file properties from AWS S3.", true, false)
			end
			
			rarSizeBytes = stdout.split(" ")[2].to_f 
			# 1048576 (1024 * 1024) is used to convert from bytes to megabytes
			rarSizeMB = rarSizeBytes / 1048576
			
			logEvent("Backup RAR file size: %s MB." % rarSizeMB, false, false)
			logEvent("Size of extraction location %s : %s MB" % [extractLocation , extractLocationSpace], false, false)

			#Determine if size of RAR file is too big for backup extraction location
			#Allow for 10% extra drive space
			if (rarSizeMB * 1.1) > extractLocationSpace then  
				logEvent("There is not enough room in the backup extraction location for the backup RAR file to be downloaded from AWS S3.", true, false)
			end
			
			logEvent("Copying RAR file from %s to %s" % [s3RarPath, extractLocation], false, false)
			cmdCopyRarFromS3 = 'aws s3 cp ' + s3RarPath + ' ' + extractLocation
			
			stdout, stderr, status =  Open3.capture3(cmdCopyRarFromS3)
			if !stderr.to_s.empty? then
				logEvent("An Error has Occurred \n ERROR: %s \n CMD: %s" % [stderr.to_s, cmdCopyRarFromS3], false, false)
				logEvent("Unable to copy backup RAR file from AWS S3 to local drive.", true, false)
			end
			logEvent("RAR backup file copied from S3", false, false)
		end
	end 
	
	return fullBackupPath
end

# Gets the UNC path for a TierPoint database backup.
# 
# @param bakFilePath [String] the local path to the database backup file.
# @param backupLocation [String] the UNC path to the remote directory where the database backup file is to be copied from.
# @param extractedBackupSize [Number] the size in megabytes of the database backup file.
# @param extractLocation [String] the directory where the database backup file is to be extracted.
# @param extractLocationSpace [Number] the size in megabytes of the directory where the database is to be extracted.
#EXAMPLE OUTPUT: \\hsbkpwfs001\NR\OH001\AI\blahblahblah_s3_full.rar
def getTierPointDatbaseBackupPath(bakFilePath, backupLocation, extractedBackupSize, extractLocation, extractLocationSpace)	
	fullBackupPath = backupLocation + getBackupFileName(backupLocation) # \\hsbkpwfs001\NR\OH001\AI\blahblahblah_s3_full.rar
	return fullBackupPath
end

def extractDatabaseBackup(bakFilePath, extractedBackupSize, extractLocationSpace, extractLocation, fullBackupPath)	
	if File.exist?(bakFilePath)
		logEvent("Extracted datbase backup file %s already exists. \n No need to extract." % bakFilePath, false, false)
	else
		logEvent("Extracted database backup file %s does not exist. \n Attempting to extract." % bakFilePath, false, false)
		if extractedBackupSize > extractLocationSpace 
			logEvent("The extracted backup is too large for the %s location." % extractLocation, true, false)
		else 
			logEvent("There is enough space to extract backup file.", false, false)
		end 
		extractRarToDirectory(fullBackupPath, extractLocation)
	end
end

# Compares the size of the database to the size of the database backup (bak) file 
# 	to determine whether there is enough space to restore the database backup.
#
# @param openEdgeDir [String] the directory location for OpenEdge.
# @param databaseFullPath [String] the directory of the database and the database name.
# @param bakFilePath [String] the path to the database backup file.
# @param databaseSpace [Number] The size of the docutap database in megabytes.
# @returns [Boolean] true if there is enough space to restore the database, otherwise false.
def verifySpaceExistsForDatabaseRestore(openEdgeDir, databaseFullPath, bakFilePath, databaseSpace)	
	sizeOk = true

	backupSpace = getBackupSizeOnDisk(openEdgeDir, databaseFullPath, (bakFilePath))

	logEvent("Backup Space: %s" % backupSpace, false, false)
	logEvent("Database Space: %s" % databaseSpace, false, false)
	if backupSpace > databaseSpace
		sizeOk = false;
	end
	
	return sizeOk
end

# Gets the size of the database backup.
#
# @param openEdgeDir [String] the directory location for OpenEdge.
# @param databaseFullPath [String] the directory of the database and the database name.
# @param extractFullPath [String] the path to the database backup (bak) file.
def getBackupSizeOnDisk(openEdgeDir, databaseFullPath, extractFullPath)
	logEvent("Open Edge Dir: %s" % openEdgeDir, false, false)
	logEvent("DB Full Path: %s" % databaseFullPath, false, false)
	logEvent("Extract Full Path: %s" % extractFullPath, false, false)
	if !File.exist?(extractFullPath)
		logEvent("The extracted backup at %s does not exist." % [extractFullPath], true, false)
	end	
	
	cmdBackupAreaSizes = '"' << openEdgeDir << 'bin\prorest" ' << '"' << databaseFullPath << '.db" "' << extractFullPath << '" -list'
	
	stdout, stderr, status =  Open3.capture3(cmdBackupAreaSizes)
	
	logEvent(stdout, false, false)
 	
	areaSizes = stdout.scan(/((?<=Size: )[^,\n]*(?=,))/)
	areaRecordsPerBlock = stdout.scan(/((?<=Records\/Block: )[^,\n]*(?=,))/)
	areaDetails = areaSizes.zip(areaRecordsPerBlock)
	dbSizeSum = 0
	valAs = 0
	valArpb = 0
	areaDetails.each do |ad|
		areaSize = 0
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
			areaSize = (valAs / valArpb) * 4096			
			dbSizeSum = dbSizeSum + areaSize
		end
	end
	return (dbSizeSum / 1048576)
end

# Gets the available space of a given drive.
#
# @param drive [String] the drive to retrieve the available drive space for.
# @returns [Number] the size (in megabytes) of free drive space.
def getDriveSpace(drive)
	stat = Sys::Filesystem.stat(drive)
	# 1048576 (1024 * 1024) is used to convert from bytes to megabytes
	mb_available = (stat.block_size * stat.blocks_available).to_f / 1048576
	return mb_available
end

# Gets the size and name of the extracted database backup (bak) file.
# 
# @param fullBackupPath [String] the directory where the backup file was extracted.
# @param bakFileFolder [String] the directory in the extracted location to search within.
# @returns [Number] the size of the database backup file and [String] the name of the database backup file.
def getExtractedBackupSizeAndName(fullBackupPath, bakFileFolder)
	logEvent("fullBackupPath: %s" % fullBackupPath, false, false)
	logEvent("bakFileFolder: %s" % bakFileFolder, false, false)

	cmd = '"C:\Program Files\WinRAR\UnRAR.exe" vt "'  + fullBackupPath + '"'
	stdout, stderr, status =  Open3.capture3(cmd)
	
	logEvent(stdout, false, false)
	logEvent("back file length: %s" % bakFileFolder.to_s.length, false, false)
	
	if bakFileFolder.to_s.length > 0 then
		fileName = stdout[(/(?<=(Name: ))#{Regexp.escape(bakFileFolder)}\w*.bak/)]
	else
		fileName = stdout[(/(?<=(Name: ))\w*.bak/)]
	end
	
	sizeMb = stdout[(/(?<=(Size: ))\d*/)].to_f / 1048576
	
	logEvent(fileName, false, false)
	logEvent(sizeMb, false, false)
	
	return sizeMb, fileName
end

# Gets the name of the compressed database backup file.
#
# @param backupPath [String] the directory to check for a compressed (RAR) database backup file in.
# @returns [String] the full path to the compressed database backup file.
def getBackupFileName(backupPath)
	if !Dir[backupPath].empty?
		logEvent("The directory at %s is empty" % [backupPath], true, false)
	else
		Dir.foreach(backupPath) do |item|
			if item.match(/.*(_full_s3.rar)/)
				return item
			end
		end
	end		
end

# Stop Windows services
# 
# @param serviceList [Array <String>] the names of the Windows services to be stopped.
def stopDocutapServices(serviceList)
	serviceList.each{ |service|
		logEvent("Stopping %s service." % [service] , false, false)
		
		output = `net stop "#{service}" 2>&1`
		
		logEvent(output, false, false)
	}
end

# Stop OpenEdge application servers.
# 
# @param openEdgeDir [String] the directory location of OpenEdge.
# @param appServerList [Array <String>] the names of app servers to be stopped in OpenEdge Explorer.	
def stopDocutapAppServers(openEdgeDir, appServerList)
	Dir.chdir("#{openEdgeDir}\\bin") do
		appServerList.each{ |appServer|
			logEvent("Stopping %s app server." % [appServer] , false, false)
			
			output = `asbman -name #{appServer} -stop 2>&1`
			
			logEvent(output, false, false)
		}
	end
end
		
# Stop OpenEdge databases.
#
# @param openEdgeDir [String] the directory location of OpenEdge.
# @param databaseList [Array <String>]	the names of databases to be stopped in OpenEdge Explorer.	
def stopDocutapDatabases(openEdgeDir, databaseList)
	Dir.chdir("#{openEdgeDir}\\bin") do
		databaseList.each{ |database|
			logEvent("Stopping %s app database." % [database] , false, false)
			
			output = `dbman -name #{database} -stop 2>&1`
			
			logEvent(output, false, false)
		}
	end
end

# Start Windows services
# 
# @param serviceList [Array <String>] the names of the Windows services to be started.
def startDocutapServices(serviceList)
	serviceList.each{ |service|
		logEvent("Starting %s service." % [service], false, false)
		
		output = `net start "#{service}" 2>&1`
		
		logEvent(output, false, false)
	}
end
	
# Start OpenEdge application servers.
# 
# @param openEdgeDir [String] the directory location of OpenEdge.
# @param appServerList [Array <String>] the names of app servers to be started in OpenEdge Explorer.
def startDocutapAppServers(openEdgeDir, appServerList)
	Dir.chdir("#{openEdgeDir}\\bin") do
		appServerList.each{ |appServer|
			logEvent("Starting %s appServer." % [appServer], false, false)
			
			output = `asbman -name #{appServer} -start 2>&1`
			
			logEvent(output, false, false)
		}
	end
end
		
# Start OpenEdge databases.
#
# @param openEdgeDir [String] the directory location of OpenEdge.
# @param databaseList [Array <String>]	the names of databases to be started in OpenEdge Explorer.
def startDocutapDatabases(openEdgeDir, databaseList)
	Dir.chdir("#{openEdgeDir}\\bin") do
		databaseList.each{ |database|
			logEvent("Starting %s database." % [database], false, false)
			
			output = `dbman -name #{database} -start 2>&1`
			
			logEvent(output, false, false)
		}
	end

end

# Extracts the compressed database backup file to a given directory.
#
# @param fullBackupPath [String] the path to the compressed database backup file (RAR).
# @param extractLocation [String] the directory to extract the database backup file to.
def extractRarToDirectory(fullBackupPath, extractLocation)
	cmd = '"C:\Program Files\WinRAR\unrar.exe" x "' << fullBackupPath << '" "' << extractLocation << '"'
	stdout, stderr, status = Open3.capture3(cmd)
	stdoutArr = stdout.split("\n")
end

# Restores the database from a backup.
#
# @param oeDir [String] the directory location for OpenEdge.
# @param databaseDir [String] the directory of the database to be restored.
# @param databaseFullPath [String] the directory of the database and the database name.
# @param dbStructFullPath [String] the database structure path.
# @param bakFilePath [String] the path to the database backup file.
# @param databasePollAttempts [String] the number of attempts to poll the database to see if it's shut down before giving up.
def applyDbFromBackup(oeDir, databaseDir, databaseFullPath, dbStructFullPath, bakFilePath, databasePollAttempts)	
=begin
		The following line enables large file processing for a database. According to the knowledge base articlee
		below, this should not cause issues for servers running versions greater than 9.1C of Progress. There
		is no command to disable large file processing for a database, and once enabled cannot run on Progress 
		versions prior to 9.1C.
		http://knowledgebase.progress.com/articles/Article/21184
=end	
	cmdList = []
	cmdCheckDbRunning = '"' << oeDir << 'bin\proutil" '<< '"' << databaseFullPath << '" -C holder'
	#cmdDeleteDb = 'echo y | "' << oeDir << 'bin\prodel" '<< '"' << databaseFullPath << '"'
	cmdRestoreFromStruct = '"' << oeDir << 'bin\prostrct" create ' << '"' << dbStructFullPath << '"'
	cmdEnableLargeFiles = '"' << oeDir << 'bin\proutil" ' << '"' << databaseFullPath << '"' << ' -C enablelargefiles'
	
	if !File.exist?(bakFilePath)
		logEvent("The extracted backup at %s does not exist." % bakFilePath, true, false)
	end	
	
	dbRunning = true
	dbPollAttempts = databasePollAttempts
	
	logEvent("Checking if DB is running.", false, false)
	logEvent("CMD: " + cmdCheckDbRunning, false, false)
	
	while dbRunning and dbPollAttempts > 0
		stdout, stderr, status = Open3.capture3(cmdCheckDbRunning)		
		
		dbInUse = stdout[(/\*\*/)]
		
		if !dbInUse
			dbRunning = false
			logEvent("DB is not running.", false, false)
		else
			logEvent("DB is running.", false, false)
			logEvent(stdout, false, false)
		end
		
		sleep(10)
		
		dbPollAttempts = dbPollAttempts - 1
		
		if dbPollAttempts == 0
			logEvent("The database failed to shutdown after %s attempts." % [databasePollAttempts], true, false)
		end
	end
	
	cmdRestoreBackup = 'echo y | "' << oeDir << 'bin\prorest" ' << '"' << databaseFullPath << '.db" "' << bakFilePath << '" -verbose'
	#cmdList.push(cmdDeleteDb)
	cmdList.push(cmdRestoreFromStruct)
	cmdList.push(cmdEnableLargeFiles)
	cmdList.push(cmdRestoreBackup)
	
	Dir.chdir(databaseDir) do
		logEvent("Database Directory: %s" % databaseDir, false, false) 
		cmdList.each { |cmd| 
			logEvent("CMD: %s" % cmd, false, false)
			
			stdout, stderr, status = Open3.capture3(cmd)		
			
			logEvent("StdOut: %s" % stdout, false, false)
			
			if stderr != ""
				logEvent("There was a problem restoring the backup with the following error: \n%s" % [stderr], true, false)
			end		
		}
	end
end

# Run the database Scrubber utility.
#
# @param openEdgeDir [String] the directory for OpenEdge.
# @param scrubberFilePath [String] the path to the scrubber utility.
# @param databaseDir [String] the directory of the database to be scrubbed.
# @param databaseFileName [String] the name of the database to be scrubbed.
def runProgressFiles(openEdgeDir, scrubberFilePath, scrubberParams, databaseDir, databaseFileName)

=begin
	_progres.exe paramaters:
		-p: filepath of the .p to be run
		-param: the paramaters passed to the .p or .r script
		-H: the hostname of the server the script is ran on
		-S: the Service Name of the broker process on the host machine
		-db: physical database file path
		-mmax: the max allocated memory for .r scripts (this will throw a warning if exceeded, but will not error out)
		-D: the number of compiled procedure directory entries (this will throw a warning if exceeded, but will not error out)
		-b: if flag is set, _progress.exe runs in "batch-mode"
		-s: stack size in 1 kb units
=end
	
	database = databaseDir + databaseFileName + '.db'
	localIp = IPSocket.getaddress(Socket.gethostname).to_s
	
	cmd = '"' << openEdgeDir << 'bin\\_progres.exe" -p ' << scrubberFilePath << ' ' << scrubberParams << ' -H ' << localIp << ' -S dtap-4gl' << ' -db ' << database << ' -mmax 8000 -U sysprogress -P docutap -debugalert -noinactiveidx' << ' -D 15000 -s 128 -b ' 
	
	Dir.chdir(databaseDir) do
		logEvent("Starting scrubber.", false, false)
		logEvent("Scrubber Command: %s" % cmd, false, false)
		
		stdout, stderr, status = Open3.capture3(cmd)
		
		logEvent("Scrubber Standard Out: %s: " % stdout, false, false)
		logEvent("Scrubber Standard Error: %s: " % stderr, false, false)
		logEvent("Scrubber has completed.", false, false)
	end	

end

# Deletes the file at the given path.
# 
# @param filePath [String] The path to the file to be deleted.
def deleteFile(filePath)
	cmd = "del #{filePath}"
	if File.exist?(filePath)
		stdout, stderr, status = Open3.capture3(cmd)
		
		logEvent("Deleted File: %s" % filePath, false)
	else
		logEvent("The file at %s does not exist." % [filePath], true)
	end	
end

# Outputs a given message to the log.
#
# @param message [String] the message to be logged.
# @param abortScript [Boolean] true to exit the Ruby script, false if not.
# @param addSectionBreak [Boolean] true to add a visual "break" to the log, false if not.
def logEvent(message, abortScript, addSectionBreak)
	File.open($logFilePath, 'a') do |f|
		$stderr = f
		$stdout = f
		
		currentTime = Time.new
	
		if addSectionBreak then
			puts "************************************************************************************************************************"
		end
		
		if abortScript then
			puts currentTime.inspect + " ABORT: " + message.to_s
		else 
			puts currentTime.inspect + " " + message.to_s
		end
	end
	
	if abortScript then
		abort("ABORT: %s" % message)
	end
end

run
