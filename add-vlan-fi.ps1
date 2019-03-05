param(
	[Parameter(Mandatory = $True, HelpMessage = "UCSM")]
    [string]$Ucsm,
	[Parameter(Mandatory = $false, HelpMessage = "Skip Errors")]
    [string]$SkipError,
    [Parameter(Mandatory = $false, HelpMessage = "VLANs")]
    [string]$vlans
)

$TABLE_ROW_SEP = ','
$TABLE_COL_SEP = '~'
$TABLE_COL_VLANNAME = 0
$TABLE_COL_VLANID = 1

# CONSTANTS

$BASE_DIR     = ($pwd.path -split '\\WFA')[0] + '\WFA\'
$MODULES_DIR  = $BASE_DIR + 'PoSH\Modules\Cisco.UCSManager\'

# HOUSEKEEPING

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

#Change directory to the script root
cd $PSScriptRoot

#Do not show errors in script
$ErrorActionPreference = "SilentlyContinue"
#$ErrorActionPreference = "Stop"
#$ErrorActionPreference = "Continue"
#$ErrorActionPreference = "Inquire"

#Verify PowerShell Version for script support
Write-Output $('Checking for proper PowerShell version')
$PSVersion = $psversiontable.psversion
$PSMinimum = $PSVersion.Major
if ($PSMinimum -ge "3")
	{
		Write-Output $('	Your version of PowerShell is valid for this script.')
		Write-Output $('		You are running version $PSVersion')
	}
else
	{
		Write-Output $('	This script requires PowerShell version 3 or above')
		Write-Output $('		You are running version $PSVersion')
		Write-Output $('	Please update your system and try again.')
		Write-Output $('	You can download PowerShell updates here:')
		Write-Output $('		http://search.microsoft.com/en-us/DownloadResults.aspx?rf=sp&q=powershell+4.0+download')
		Write-Output $('	If you are running a version of Windows before 7 or Server 2008R2 you need to update to be supported')
		Write-Output $('			Exiting...')
		Disconnect-Ucs
		exit
	}

#Load the UCS PowerTool
Write-Output $('Checking Cisco PowerTool')
$PowerToolLoaded = $null
$Modules = Get-Module
$PowerToolLoaded = $modules.name
if ( -not ($Modules -like "Cisco.UCSManager"))
	{
		Write-Output $('	Loading Module: Cisco UCS PowerTool Module')
		Import-Module Cisco.UCSManager
		$Modules = Get-Module
		if ( -not ($Modules -like "cisco.UCSManager"))
			{
				Write-Output $('	Cisco UCS PowerTool Module did not load.  Please correct his issue and try again')
				Write-Output $('		Exiting...')
				exit
			}
		else
			{
				$PTVersion = (Get-Module CiscoUcsPs).Version
				Write-Output $('		PowerTool version $PTVersion is now Loaded')
			}
	}
else
	{
		$PTVersion = (Get-Module Cisco.UCSManager).Version
		Write-Output $('	PowerTool version $PTVersion is already Loaded')
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
		Write-Output $('You didnt enter anything')
		Write-Output $('	Exiting...')
		Disconnect-Ucs
		exit
	}

#Make sure we are disconnected from all UCS Systems
Disconnect-Ucs

#Test that UCSM(s) are IP Reachable via Ping
Write-Output $('Testing PING access to UCSM')
foreach ($ucs in $myucs)
	{
		$ping = new-object system.net.networkinformation.ping
		$results = $ping.send($ucs)
		if ($results.Status -ne "Success")
			{
				Write-Output $('	Can not access UCSM $ucs by Ping')
				Write-Output $('		It is possible that a firewall is blocking ICMP (PING) Access.  Would you like to try to log in anyway?')
				if ($SKIPERROR)
					{
						$Try = "y"
					}
				else
					{
						$Try = Read-Host "Would you like to try to log in anyway? (Y/N)"
					}				if ($Try -ieq "y")
					{
						Write-Output $('				Will try to log in anyway!')
					}
				elseif ($Try -ieq "n")
					{
						Write-Output $('You have chosen to exit')
						Write-Output $('	Exiting...')
						Disconnect-Ucs
						exit
					}
				else
					{
						Write-Output $('You have provided invalid input')
						Write-Output $('	Exiting...')
						Disconnect-Ucs
						exit
					}			
			}
		else
			{
				Write-Output $('	Successful access to $ucs by Ping')
			}
	}

#Log into the UCS System(s)
$multilogin = Set-UcsPowerToolConfiguration -SupportMultipleDefaultUcs $true
Write-Output $('Logging into UCS')
#Verify PowerShell Version to pick prompt type
$PSVersion = $psversiontable.psversion
$PSMinimum = $PSVersion.Major
foreach ($myucslist in $myucs)
	{
		Write-Output $('		Logging into: $myucslist')
		$myCon = $null
        $cred = Get-WFACredentials -Host $myucslist
		$myCon = Connect-Ucs $myucslist -Credential $cred
		if (($mycon).Name -ne ($myucslist)) 
			{
				#Exit Script
				Write-Output $('			Error Logging into this UCS domain')
				if ($myucs.count -le 1)
					{
						$continue = "n"
					}
				else
					{
						$continue = Read-Host "Continue without this UCS domain (Y/N)"
					}
				if ($continue -ieq "n")
					{
						Write-Output $('				You have chosen to exit...')
						Write-Output $('Exiting Script...')
						Disconnect-Ucs
						exit
					}
				else
					{
						Write-Output $('				Continuing...')
					}
			}
		else
			{
				Write-Output $('			Login Successful')
			}
		Start-Sleep 1
	}
$myCon = (Get-UcsPSSession | measure).Count
if ($myCon -eq 0)
	{
		Write-Output $('You are not logged into any UCSM systems')
		Write-Output $('	Exiting...')
		Disconnect-Ucs
		exit
	}

if ($vlans) {
	$VLANCloud = Get-UcsLanCloud
		if (!$VLANCloud)
			{
				Write-Output $('Could not access VLAN Cloud')
				Write-Output $('	Exiting...')
				exit
			}
		else
			{
				Write-Output $('Validating VLAN Names and Numbers')
				#Get VLANs within FIs and separate names and IDs into two arrays
                $ExistingVlans = Get-UcsVlan -Cloud ethlan
                $ExistingVlanNames = @()
                $ExistingVlanNames += $ExistingVlans.Name
                $ExistingVlanIds = @()
                $ExistingVlanIds += $ExistingVlans.Id

                Start-UcsTransaction
                $vlans -split "${TABLE_ROW_SEP}" | % {
                    $vlan = $_
                    $cols = @()
                    $cols = $vlan -split "${TABLE_COL_SEP}"
                    $CharacterTest = [regex]"^[A-Za-z0-9_:.-]*$"
	                #Validate VLAN name convention
                    if ((($cols[$TABLE_COL_VLANNAME]).Length -le 32) -and (($CharacterTest.Match($cols[$TABLE_COL_VLANNAME]).Success)))
	                {
                        #Validate VLAN ID convention
                        if (([int]$cols[$TABLE_COL_VLANID] -le 3967) -or ($cols[$TABLE_COL_VLANID] -match "^404[8-9]") -or ($cols[$TABLE_COL_VLANID] -match "^40[5-8][0-9]") -or ($cols[$TABLE_COL_VLANID] -match "^409[0-3]"))
		                {
                            #Check if VLAN ID already exists on FI
                            if ($ExistingVlanIds -contains $cols[$TABLE_COL_VLANID]) {
                                Write-Output $('	VLAN ID already exists: ' + $cols[$TABLE_COL_VLANID])
	                            Write-Output $('	Please correct this issue and try again')
                            }
                            else 
                            {
                                #Check if VLAN name exists on FI
                                if ($ExistingVlanNames -contains $cols[$TABLE_COL_VLANNAME]) 
                                {
                                    Write-Output $('	VLAN Name already exists: ' + $cols[$TABLE_COL_VLANNAME])
                                    Write-Output $('	Please correct this issue and try again')
                                }
                                else 
                                {
                                    #Add VLAN if it passes all checks
                                    Write-Output $('Adding VLAN' + $cols[$TABLE_COL_VLANNAME] + ':' + $cols[$TABLE_COL_VLANID])
                                    $VLANCloud | Add-UcsVlan -Id $cols[$TABLE_COL_VLANID] -Name $cols[$TABLE_COL_VLANNAME]
                                }       
                            }
		                }
		                else
		                {
			                Write-Output $('Invalid entry in VLAN Number:' + $cols[$TABLE_COL_VLANID])
			                Write-Output $('	Please correct this error and try again')
		                }
	                }
	                else
	                {
		                Write-Output $('Invalid entry in VLAN Name:' + $cols[$TABLE_COL_VLANNAME])
		                Write-Output $('Please correct this error and try again')
	                }        
                }
                Complete-UcsTransaction

				Write-Output $('Done adding VLANs')
			}
}

#Disconnect from UCSM(s)
Disconnect-Ucs

#Exit the Script
Write-Output $('Script Complete')
exit
