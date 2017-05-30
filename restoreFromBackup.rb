require 'sys/filesystem'
require 'yaml'
require 'open3'
require 'socket'

def restoreBackup	
	config = YAML.load_file(File.expand_path('config.yml', File.dirname(__FILE__)))
	databaseDir = config["Database Directory"]
	databaseFileName = config["Database Name"]
	databaseFullPath = config["Database Directory"] + databaseFileName
	structureFullPath = databaseDir + config["Database Structure Name"]
	openEdgeDir = config["OpenEdge Install Directory"]
	isAWS = config["AWS Database Server"]
	extractLocation = config["Backup Extract Location"]
	backupLocation = config["Backup Location"]
	serviceList = config["Services"]
	appServerList = config["Progress AppServers"]
	databaseList = config["Progress Databases"]
	scrubberFilePath = config["Scrubber"]["File Path"]
	scrubberParams = config["Scrubber"]["Params"]
	databasePollAttempts = config["Database Poll Attempts"].to_i
	fullBackupPath = backupLocation + getBackupFileName(backupLocation)
	extractLocationSpace = getDriveSpace(extractLocation)
	databaseSpace = getDriveSpace(databaseDir)
	extractedBackupSize, extractedFileName = getExtractedBackupSizeAndName(fullBackupPath)
	
	if extractedBackupSize > extractLocationSpace 
		abort("ABORT: The extracted backup is too large for the %s location." % extractLocation)
	end 
	extractRarToDirectory(fullBackupPath, extractLocation)
	backupSpace = getBackupSizeOnDisk(openEdgeDir, databaseFullPath, (extractLocation + extractedFileName))
	if backupSpace > databaseSpace
		deleteExtractedBackup(extractLocation, extractedFileName)
		abort("ABORT: The database is too large to restore at %s location." % databaseFullPath)
	end
	success = false
	stopDocutapServices(serviceList)
	stopDocutapAppServers(openEdgeDir, appServerList)
	stopDocutapDatabases(openEdgeDir, databaseList)
	applyDbFromBackup(openEdgeDir, databaseDir, databaseFullPath, structureFullPath, extractLocation, extractedFileName, databasePollAttempts)
	deleteExtractedBackup(extractLocation, extractedFileName)
	startDocutapDatabases(openEdgeDir, databaseList)
	runProgressFiles(openEdgeDir, scrubberFilePath, scrubberParams, databaseDir, databaseFileName)
	startDocutapAppServers(openEdgeDir, appServerList)
	startDocutapServices(serviceList)
	success = true
	return success
end

def getBackupSizeOnDisk(openEdgeDir, databaseFullPath, extractFullPath)
	if !File.exist?(extractFullPath)
		abort("The extracted backup at %s does not exist." % [extractFullPath])
	end	
	cmdBackupAreaSizes = '"' << openEdgeDir << 'bin\prorest" ' << '"' << databaseFullPath << '.db" "' << extractFullPath << '" -list'
	stdout, stderr, status =  Open3.capture3(cmdBackupAreaSizes)
	print stdout
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

def getDriveSpace(drive)
	stat = Sys::Filesystem.stat(drive)
	# 1048576 (1024 * 1024) is used to convert from bytes to megabytes
	mb_available = (stat.block_size * stat.blocks_available).to_f / 1048576
	return mb_available
end

def getExtractedBackupSizeAndName(fullBackupPath)
	cmd = '"C:\Program Files\WinRAR\UnRAR.exe" vt "'  << fullBackupPath << '"'
	stdout, stderr, status =  Open3.capture3(cmd)
	arr = stdout.split("\n")
	arr.each do |line|
		puts line
	end
	fileName = stdout[(/(?<=(Name: ))\w*.bak/)]
	sizeMb = stdout[(/(?<=(Size: ))\d*/)].to_f / 1048576
	return sizeMb, fileName
end

def getBackupFileName(backupPath)
	if !Dir[backupPath].empty?
		abort("ABORT: The directory at %s is empty" % [backupPath])
	else
		Dir.foreach(backupPath) do |item|
			if item.match(/.*(_full_s3.rar)/)
				return item
			end
		end
	end		
end

def stopDocutapServices(serviceList)
	serviceList.each{ |service|
		puts "Stopping %s service." % [service]
		puts `net stop "#{service}"`
	}
end
	
def stopDocutapAppServers(openEdgeDir, appServerList)
	Dir.chdir("#{openEdgeDir}\\bin") do
		appServerList.each{ |appServer|
			puts `asbman -name #{appServer} -stop`
		}
	end
end
		
def stopDocutapDatabases(openEdgeDir, databaseList)
	Dir.chdir("#{openEdgeDir}\\bin") do
		databaseList.each{ |database|
			puts `dbman -name #{database} -stop`
		}
	end
end

def startDocutapServices(serviceList)
	serviceList.each{ |service|
		puts "Starting %s service." % [service]
		puts `net start "#{service}"`
	}
end
	
def startDocutapAppServers(openEdgeDir, appServerList)
	Dir.chdir("#{openEdgeDir}\\bin") do
		appServerList.each{ |appServer|
			puts " Starting %s appServer." % [appServer]
			puts `asbman -name #{appServer} -start`
		}
	end
end
		
def startDocutapDatabases(openEdgeDir, databaseList)
	Dir.chdir("#{openEdgeDir}\\bin") do
		databaseList.each{ |database|
			puts " Starting %s database." % [database]
			puts `dbman -name #{database} -start`
		}
	end

end

def extractRarToDirectory(fullBackupPath, extractLocation)
	cmd = '"C:\Program Files\WinRAR\unrar.exe" x "' << fullBackupPath << '" "' << extractLocation << '"'
	stdout, stderr, status = Open3.capture3(cmd)
	stdoutArr = stdout.split("\n")
end
	
def applyDbFromBackup(oeDir, databaseDir, databaseFullPath, dbStructFullPath, extractLocation, extractedFileName, databasePollAttempts)	
	extractFullPath = extractLocation + extractedFileName
=begin
		The following line enables large file processing for a database. According to the knowledge base articlee
		below, this should not cause issues for servers running versions greater than 9.1C of Progress. There
		is no command to disable large file processing for a database, and once enabled cannot run on Progress 
		versions prior to 9.1C.
		http://knowledgebase.progress.com/articles/Article/21184
=end	
	cmdList = []
	cmdCheckDbRunning = '"' << oeDir << 'bin\proutil" '<< '"' << databaseFullPath << '" -C holder'
	cmdDeleteDb = 'echo y | "' << oeDir << 'bin\prodel" '<< '"' << databaseFullPath << '"'
	cmdRestoreFromStruct = '"' << oeDir << 'bin\prostrct" create ' << '"' << dbStructFullPath << '"'
	
	cmdEnableLargeFiles = '"' << oeDir << 'bin\proutil" ' << '"' << databaseFullPath << '"' << ' -C enablelargefiles'
	if !File.exist?(extractFullPath)
		abort("The extracted backup at %s does not exist." % [extractFullPath])
	end	
	dbRunning = true
	dbPollAttempts = databasePollAttempts
	while dbRunning and dbPollAttempts > 0
		stdout, stderr, status = Open3.capture3(cmdCheckDbRunning)		
		dbInUse = stdout[(/\*\*/)]
		if !dbInUse
			dbRunning = false
		end
		sleep(10)
		dbPollAttempts = dbPollAttempts - 1
		if dbPollAttempts == 0
			abort("The database failed to shutdown after %s attempts." % [databasePollAttempts])
		end
	end
	
	cmdRestoreBackup = 'echo y | "' << oeDir << 'bin\prorest" ' << '"' << databaseFullPath << '.db" "' << extractFullPath << '" -verbose'
	cmdList.push(cmdDeleteDb)
	cmdList.push(cmdRestoreFromStruct)
	cmdList.push(cmdEnableLargeFiles)
	cmdList.push(cmdRestoreBackup)
	
	Dir.chdir(databaseDir) do
		puts databaseDir
		cmdList.each { |cmd| 
			puts cmd
			stdout, stderr, status = Open3.capture3(cmd)		
			puts stdout
			if stderr != ""
				abort("ABORT: There was a problem restoring the backup with the following error: \n%s" % [stderr])
			end		
		}
	end
	puts "BACKUP RESTORE COMPLETE"
end

def createLogFile(logFilePath, logFileName)
	today = Time.now
	year = today.year.to_s
	month = today.month.to_s
	day = today.day.to_s
	logFilePath = logFilePath << year <<'\\' << month
	if !File.directory?(logFilePath)
		`md #{logFilePath}`
	end
		
	fullLogFilePath = logFilePath << '\\' << day << '_%s.txt' % [logFileName]
	File.new(fullLogFilePath,'a')
	return fullLogFilePath
end

def writeToLogFiles(stdout, stderr, status, logMessage, outputLogFilePath, errorLogFilePath)
	File.open(outputLogFilePath,'a') do |f|
		f.puts logMessage
		f.puts stdout
	end
	if !status.success?
		File.open(errorLogFilePath,'a') do |f|
			f.puts "==============FAILED WITH ERROR CODE: %s ==============" % [status]
			f.puts stderr
		end
	end
end

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
		puts "Starting scrubber."	
		print cmd
		stdout, stderr, status = Open3.capture3(cmd)
		puts stdout
		puts stderr
		puts "Scrubber has completed."
	end	

end

def deleteExtractedBackup(extractLocation, extractedFileName)
	extractFullPath = extractLocation << extractedFileName
	cmd = "del #{extractFullPath}"
	if File.exist?(extractFullPath)
		stdout, stderr, status = Open3.capture3(cmd)
	else
		abort("The extracted backup at %s does not exist." % [extractFullPath])
	end	
end

restoreBackup
