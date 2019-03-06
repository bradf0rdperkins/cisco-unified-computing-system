param(
	[Parameter(Mandatory = $True, HelpMessage = "UCSM")]
    [string]$Ucsm,
	[Parameter(Mandatory = $True, HelpMessage = "Backup Folder")]
    [string]$Folder,
	[Parameter(Mandatory = $false, HelpMessage = "Skip Errors")]
    [string]$SkipError,
    	[Parameter(Mandatory = $false, HelpMessage = "Config Logical")]
    [bool]$configLogical,
    	[Parameter(Mandatory = $false, HelpMessage = "Config All")]
    [bool]$configAll,
    	[Parameter(Mandatory = $false, HelpMessage = "Config System")]
    [bool]$configSystem,
    	[Parameter(Mandatory = $false, HelpMessage = "Full State")]
    [bool]$fullState
)

$TABLE_ROW_SEP = ','
$TABLE_COL_SEP = '~'
$TABLE_COL_DOMAINNAME = 0
$TABLE_COL_DOMAINIP = 1

# CONSTANTS

$BASE_DIR     = ($pwd.path -split '\\WFA')[0] + '\WFA\'
$MODULES_DIR  = $BASE_DIR + 'PoSH\Modules\Cisco.UCSManager\'
$limit = (Get-Date).AddDays(-60)

$required_modules = @(
  "Cisco.UCSManager.psd1"
)

$required_modules | % {
  Try{
	 Import-Module $(${modules_dir} + "\" + $_)
  }
  Catch{
	 Throw ("Failed to load required module: " + $_)
  }
}

#Tell the user what the script does
Write-Output $("This script allows you to backup a single or multiple UCS domains.")
Write-Output $("It will create each type of backup available on UCS.")

#Change directory to the script root
cd $PSScriptRoot

#Select folder to save files to
if ($FOLDER)
	{
        $TestPath = Test-Path $FOLDER
	    if ($TestPath -eq $true) {
		    #Hold for future options
	    }
	    else {
		    Write-Output $($Folder + ": The folder you specified either does not exist or you do not have access to it")
		    Write-Output $("	Exiting...")
		    Disconnect-Ucs
		    exit				
	    }
         
	}
else
	{
		$FOLDER = $PSScriptRoot
	}
Write-Output $("The files will be saved to folder: $FOLDER")

#Do not show errors in script
$ErrorActionPreference = "SilentlyContinue"
#$ErrorActionPreference = "Stop"
#$ErrorActionPreference = "Continue"
#$ErrorActionPreference = "Inquire"

#Verify PowerShell Version for script support
Write-Output $("Checking for proper PowerShell version")
$PSVersion = $psversiontable.psversion
$PSMinimum = $PSVersion.Major
if ($PSMinimum -ge "3")
	{
		Write-Output $("	Your version of PowerShell is valid for this script.")
		Write-Output $("		You are running version $PSVersion")
	}
else
	{
		Write-Output $("	This script requires PowerShell version 3 or above")
		Write-Output $("		You are running version $PSVersion")
		Write-Output $("	Please update your system and try again.")
		Write-Output $("	You can download PowerShell updates here:")
		Write-Output $("		http://search.microsoft.com/en-us/DownloadResults.aspx?rf=sp&q=powershell+4.0+download")
		Write-Output $("	If you are running a version of Windows before 7 or Server 2008R2 you need to update to be supported")
		Write-Output $("			Exiting...")
		Disconnect-Ucs
		exit
	}

#Load the UCS PowerTool
Write-Output $("Checking Cisco PowerTool")
$PowerToolLoaded = $null
$Modules = Get-Module
$PowerToolLoaded = $modules.name
if ( -not ($Modules -like "Cisco.UCSManager"))
	{
		Write-Output $("	Loading Module: Cisco UCS PowerTool Module")
		Import-Module Cisco.UCSManager
		$Modules = Get-Module
		if ( -not ($Modules -like "cisco.UCSManager"))
			{
				Write-Output $("	Cisco UCS PowerTool Module did not load.  Please correct his issue and try again")
				Write-Output $("		Exiting...")
				exit
			}
		else
			{
				$PTVersion = (Get-Module CiscoUcsPs).Version
				Write-Output $("		PowerTool version $PTVersion is now Loaded")
			}
	}
else
	{
		$PTVersion = (Get-Module Cisco.UCSManager).Version
		Write-Output $("	PowerTool version $PTVersion is already Loaded")
	}

#Select UCS Domain(s) for login
if ($UCSM -ne "")
	{
		$myucs = $UCSM
	}
else
	{
		$myucs = Read-Host "Enter UCS system IP or Hostname or a list of systems separated by commas"
	}
[array]$myucs = ($myucs.split(",")).trim()
if ($myucs.count -eq 0)
	{
		Write-Output $("You didn't enter anything")
		Write-Output $("	Exiting...")
		Disconnect-Ucs
		exit
	}

#Make sure we are disconnected from all UCS Systems
Disconnect-Ucs

#Test that UCSM(s) are IP Reachable via Ping
Write-Output $("Testing PING access to UCSM")
$myucs -split "${TABLE_ROW_SEP}" | % {
    $ucsdomain = $_
    $colsUCS = @()
    $colsUCS = $ucsdomain -split "${TABLE_COL_SEP}"
	$ping = new-object system.net.networkinformation.ping
	$results = $ping.send($colsUCS[$TABLE_COL_DOMAINIP])
	if ($results.Status -ne "Success")
		{
			Write-Output $("	Can not access UCSM $colsUCS[$TABLE_COL_DOMAINIP] by Ping")
			Write-Output $("		It is possible that a firewall is blocking ICMP (PING) Access.  Would you like to try to log in anyway?")
			if ($SKIPERROR)
				{
					$Try = "y"
				}
			else
				{
					$Try = Read-Host "Would you like to try to log in anyway? (Y/N)"
				}
			if ($Try -ieq "y")
				{
					Write-Output $("				Will try to log in anyway!")
				}
			elseif ($Try -ieq "n")
				{
					Write-Output $("You have chosen to exit")
					Write-Output $("	Exiting...")
					Disconnect-Ucs
					exit
				}
			else
				{
					Write-Output $("You have provided invalid input")
					Write-Output $("	Exiting...")
					Disconnect-Ucs
					exit
				}			
		}
	else
		{
			Write-Output $("	Successful access to $colsUCS[$TABLE_COL_DOMAINIP] by Ping")
		}
}

#Log into the UCS System(s)
$multilogin = Set-UcsPowerToolConfiguration -SupportMultipleDefaultUcs $true
Write-Output $("Logging into UCS")
#Verify PowerShell Version to pick prompt type
$PSVersion = $psversiontable.psversion
$PSMinimum = $PSVersion.Major

$myucs -split "${TABLE_ROW_SEP}" | % {
    $ucsdomain = $_
    $colsUCS = @()
    $colsUCS = $ucsdomain -split "${TABLE_COL_SEP}"
    $cred = Get-WFACredentials -Host $colsUCS[$TABLE_COL_DOMAINIP]
	Write-Output $("		Logging into: $myucslist")
	$myCon = $null
	$myCon = Connect-Ucs $colsUCS[$TABLE_COL_DOMAINIP] -Credential $cred
	if (($mycon).Name -ne ($colsUCS[$TABLE_COL_DOMAINIP])) 
		{
			#Exit Script
			Write-Output $("			Error Logging into this UCS domain")
			if ($myucs.count -le 1)
				{
					$continue = "n"
				}
			else
				{
					if ($SKIPERROR)
						{
							$continue = "y"
						}
					else
						{
							$continue = Read-Host "Continue without this UCS domain (Y/N)"
						}
				}
			if ($continue -ieq "n")
				{
					Write-Output $("				You have chosen to exit...")
					Write-Output $("Exiting Script...")
					Disconnect-Ucs
					exit
				}
			else
				{
					Write-Output $("				Continuing...")
				}
		}
	else
		{
			Write-Output $("			Login Successful")
		}
	sleep 1
}
$myCon = (Get-UcsPSSession | measure).Count
if ($myCon -eq 0)
	{
		Write-Output $("You are not logged into any UCSM systems")
		Write-Output $("	Exiting...")
		Disconnect-Ucs
		exit
	}

#Function that removes existing backup configs, creates a new one and then removes it when complete
Function UCSBackup ($UCStoBackup, $UCSbackupType)
	{
		$UcsName = (Get-UcsTopSystem | where {$_.Address -eq $UCStoBackup}).Ucs
		Write-Output $("Removing any previous UCSM Backup configurations from UCS: $UcsName($UcsDomain)")
		try{
            $DontShow = Get-UcsMgmtBackup | Remove-UcsMgmtBackup -Ucs $UcsName -Force
		}
        catch
        {
            Write-Output $($_)
        }
        Write-Output $("	Complete")
		
		Write-Output $("Backing up UCS: $UcsName($UCStoBackup), Backup Type: $UCSbackupType")
		$Date = Get-Date
		$DateFormat = [string]$Date.Month+"-"+[string]$Date.Day+"-"+[string]$Date.Year+"_"+[string]$Date.Hour+"-"+[string]$Date.Minute+"-"+[string]$Date.Second
		$BackupFile = $FOLDER+"\UCSMBackup_"+$UcsName+"_"+$UCSbackupType+"_"+$DateFormat+".xml"
		Try
			{
				$DontShow = Backup-Ucs -PreservePooledValues -Type $UCSbackupType -Ucs $UcsName -PathPattern $BackupFile -ErrorAction Stop
			}
		Catch
			{
                Write-Output $($_)
				Write-Output $("	***WARNING*** Error creating backup: $BackupFile")
				Write-Output $("		NOTE: This is normal behavior for a full-state backup on a UCS Emulator")
			}
		Finally
			{
				if (Test-Path $BackupFile)
					{
						Write-Output $("	Complete - "+ $BackupFile)
					}
			}

		Write-Output $("Removing backup job from UCS: $UcsName($UCStoBackup)")
		$Hostname = ((Get-WmiObject -Class Win32_ComputerSystem).Name).ToLower()
		$dontshow = Start-UcsTransaction
			$mo = Get-UcsMgmtBackup -Hostname $Hostname | Remove-UcsMgmtBackup -Force
		$dontshow = Complete-UcsTransaction -Force
		Write-Output $("	Complete")
	}

#Main part of script which calls the backup function for a UCS domain and a backup type
$UcsHandle = Get-UcsStatus | select -Property VirtualIpv4Address
foreach ($UcsDomain in $UcsHandle.VirtualIpv4Address)
	{
        if($configAll){UCSBackup $UcsDomain "config-all"}
        if($configLogical){UCSBackup $UcsDomain "config-logical"}
        if($configSystem){UCSBackup $UcsDomain "config-system"}
	if($fullState){UCSBackup $UcsDomain "full-state"}
	}

#Disconnect from UCSM(s)
Disconnect-Ucs

Get-ChildItem -Path $Folder -Recurse -Force | Where-Object { !$_.PSIsContainer -and $_.CreationTime -lt $limit } | Remove-Item -Force
Write-Output $("Deleting backups older than 60 days")

#Exit the Script
Write-Output $("Script Complete")
