# Automated Alpha Prep
This project is used to automate the DocuTAP PM/EMR Alpha process on a Windows 
server in both TierPoint and AWS. This assumes backups are arlready taken of the 
source database. Currently, this application will download and 
extract a database based on the config.yml file, scrub(anonymize) the database, 
and run any complimentary restore scripts. To execute the application, simply 
verify that Ruby is included in your Windows PATH and run the following command 
from the directory of restore.Backup.rb: 
**ruby restore_from_backup.rb**.

## Purpose
The purpose of this project is to increase the efficiency of the alpha prep
process. Prior to this application's creation, the alpha prep process would take 
roughly 30+ hours of manually work along with little consistency. This 
application was created in such a way to allow the replacement of the config.yml
with another config file (with the idea being to replace it with a Chef json 
file).  

## Requirements
- Ruby 2.3+
    - Ruby Window installer: https://rubyinstaller.org/downloads/
    - generally speaking 2.33 64bit should suffice
    - file utils is not needed for version 2.3 : https://github.com/ruby/fileutils/issues/2 
- Gems
    - fileutils: used for file operations
    - sys-filesystem: used for checking the size of a directory
- SiteId_config.yml
    - Before the application can be ran, a config.yml file must be configured. 
      The configurations for this file are denoted below.
      
## Pre-Conditions
This application does not accept any command line paramaters, however, it does 
contain a config.yml file that allows the application to be customized.

- Database Server Name:
    - The name of the database server, including the ".docutap.local".
    - Example: DT043-DB.docutap.local
- Broker Service Name:
    - The value to use for the _progres.exe "-S" option.
    - Example: 37235
        - This can be found by opening
          the D:\Progress\OpenEdge\properties\conmgr.properties file and 
          getting the "port" value from the
          "[servergroup.dt043-docutap.defaultconfiguration.4gl]" section
- Database Directory:
    - The directory to with the Progress database is to be restored to. The 
      application will automatically check whether there is enough storage space
      to extract from a backup. A backslash must be appended to the end of the 
      string. 
    - Example: 'D:\Docutap\DT043\Wrk\DB\'
- Database Name:
    - The name of the Progress database which is to be restored. (Note: This 
      does not include the filename extension which is typically .db)
    - Example: 'docutap'
- Database Structure Name:
    - The name of the Progress structure file name from which the database is to
      be restored. (Note: This does not include the filename extension which is 
      typically .st)
    - Example: 'docutap'
- OpenEdge Install Directory:
    - The full directory path to which Progress OpenEdge is installed.
    - Example: 'D:\Progress\OpenEdge\'
- AWS Database Server:
    - A boolean value to say whether the Progress database server is located in 
      AWS. This is used to determine where to pull the backups from.
    - Example: 'true'
- AWS Backup Site ID:
    - The Site ID (or Clinic ID) of the site.
    - Example: 'AL002'
- Backup Extract Location:
    - The location from which the Progress database full backup is to be
      extracted to before being restored. Currently, the application extracts 
      over a network to the specified location. This is a storage over 
      performance sacrifice.
    - Example: 'D:\Docutap\DT043\bkpextract\replication\'
- Backup Location:
    - For TierPoint sites only!
    - The location from which the Progress database full backup is to be 
      extracted from. This assumes the backup file at this location is 
      compressed as a .rar and follows the naming convention 
      **[backupdate]_[uniqueid]_full_s3.rar**. If there is more than one file 
      within the directory that follows this naming convention, it is not 
      guaranteed which will be extracted.
    - Example: '\\SFSDWDBBKP001\Progress E-M\FL027\AI\'
- Existing Database Backup Path
    - The path to an existing database backup file to be used for database restore.
    - Example: 'D:\Docutap\DT043\bkpextract\replication\20190504_221215_IN005_PMDBETV001-073_docutap_F.bak'
    - NOTE: If you want to download the latest .RAR file from S3, leave this empty.
- Database Poll Attempts: 
    - The number of times (int) the database will be polled to verify that it is
      not in use, and is ready to restore. The reason for this is that when a 
      shutdown command is initiated on a Progress database server, the database 
      server remains in use afterward for a short period of time (this is caused
      by Progress performing background processes after shutdown thereby locking
      the database). To mitigate this, a poll/sleep has been added to poll for 
      an **in-use** database. More information can be found at 
      https://stackoverflow.com/questions/42074119/backup-restore-fails-on-multi-user-mode-error
    - Example: '10'
- Progress AppServers: 
    - The appservers utilized by OpenEdge. These will be stopped and started 
      before and after the database is restored. This is parsed as a list.
    - Example: 'DT043-DashboardAS'
               'DT043-DtapAPI'
               'DT043-DtapAS'
               'DT043-DtapAS1'
               'DT043-SeamlessAS'
- Services:
    - The services to be stopped and started before and after the database is
      restored. This is parsed as a list.
    - Example: 'DocuTAP DT043 Messaging'
               'DocuTAP DT043 Relentless'
               'DocuTAP DT043 Seamless'
- Progress Databases: 
    - The databases utilized by OpenEdge. These will be stopped and started 
      before and after the database is restored. This is parsed as a list.
    - Example: 'DT043-docutap'
               'DocuTAP-RX'
- Scrubber: 
    - Database retore and scrub on Database server only
    - Database scrubber: \\10.240.4.201\Release_File01\Deploy\exe\Automated\5.13.0\Scripts
    - The scrubber to be ran post database restore. Currently, this is utilized 
      to anonymize the database prior to turning on any application features. 
      The full file path and the paramaters to be passed to the script must be 
      specified.
    - Example: File Path: 'D:\Deploy\Workspace\AutomatedAlpha\6.0_Scripts\StartScrubberCommandLine.r'
               Params: '-param "AWS|YES~ClearPropathPre|false~DisplayMessages|NO~MachineType|1~ScrubType|3~ManuallyEditControls|NO~AppPath|D:\Docutap\DT043\Wrk~SysOdbc|docutap"'
    - Might need seed files
    - Copy alpha prep script to server: example, DT043 - D:\Deploy\Workspace\AutomatedAlpha
    - Copy database scrubber to server: example, DT043 - D:\Deploy\Workspace\AutomatedAlpha\6.0_Scripts
    - Copy seed files to server: example, DT043 - D:\Docutap\DT043\Wrk\*.d
    - check scrubber log at dD\Docutap\DT043\wrk\db\scrubber.log
- Output Log File Path:
    - The directory to which the stdout log files can be written to. This 
      functionality exists in the code, but is not being utilized. 
    - Example: 'D:\Deploy\Workspace\AutomatedAlpha\DT043-BackupRestore.log'

## Running
- run ruby script (ruby "path\to\script\script_name.rb")
	- from CMD: ruby "D:\Deploy\Workspace\AutomatedAlpha\restoreFromBackup.rb"
- This runs from the db server
- Run Stop job from CLU to bring site down

## Post-Conditions
Upon successful execution of this application, the Progress database server will 
contain a restored and scrubbed database based on the settings in the 
config.yml. The application will provide command line output to stdout and 
stderr. The application will abort if certain conditions are met (not enough 
storage space to extract, can't find database restore file, etc.) and exit with 
a **(1)** return code.

## Notes
TODO:
    - Add pre/post restore scripts to be ran.
    - Add command line paramaters to be passed to override config file.
    - Add classes to contain config file settings.