<#

    .SYNOPSIS
    PRTG push Veeam all Job Status
    
    .DESCRIPTION
    Advanced Sensor will report Result of all jobs
    
    .EXAMPLE
    veeam_allJob.ps1

    .EXAMPLE
    veeam_allJob.ps1 -DryRun

    .NOTES
    ┌─────────────────────────────────────────────────────────────────────────────────────────────┐ 
    │ ORIGIN STORY                                                                                │ 
    ├─────────────────────────────────────────────────────────────────────────────────────────────┤ 
    │   DATE        : 2022.03.03                                                                  |
    │   AUTHOR      : TS-Management GmbH, Stefan Müller                                           | 
    │   DESCRIPTION : PRTG Push Veeam Backup State                                                |
    └─────────────────────────────────────────────────────────────────────────────────────────────┘

    .Link
    https://ts-man.ch
#>
[cmdletbinding()]
param(
	[Parameter(Position=1, Mandatory=$false)]
		[switch]$DryRun = $false
)

##### COFNIG START #####
$probeIP = "PROBE"      #include http:// or https://
$sensorPort = "PORT"
$sensorKey ="KEY"
#####  CONFIG END  #####

#Make sure PSModulePath includes Veeam Console
$MyModulePath = "C:\Program Files\Veeam\Backup and Replication\Console\"
$env:PSModulePath = $env:PSModulePath + "$([System.IO.Path]::PathSeparator)$MyModulePath"
if ($Modules = Get-Module -ListAvailable -Name Veeam.Backup.PowerShell){
    try {
        $Modules | Import-Module -WarningAction SilentlyContinue
    }catch{
        throw "Failed to load Veeam Modules"
    }
}


# check if veeam powershell snapin is loaded. if not, load it
if( (Get-PSSnapin -Name veeampssnapin -ErrorAction SilentlyContinue) -eq $nul){
    Add-PSSnapin veeampssnapin -ErrorAction SilentlyContinue
}

# if the script is run at the end of a job, the status is unknown. Therefore a delay is needed.
#sleep -Seconds 90

$jobs = Get-VBRJob

$jobsTable	= @()
$i = 1;
foreach($job in $jobs){
    Write-Verbose $job.Name
    Write-Verbose $job.FindLastSession().Result
    write-Verbose $job.GetLastState()
    
    switch($job.FindLastSession().Result){
        "Success" { $jobResultCode = 0 } # OK
        "Warning" { $jobResultCode = 1 } # Warning
        "Failed"  { $jobResultCode = 2 } # Error
        Default   { $jobResultcode = 9 } # Unknown
    }

    if($jobResultCode -eq 9){
        if($job.GetLastState() -eq "Working"){
            $jobResultCode = 8
        }elseif($job.GetLastState() -eq "Stopping"){
            $jobResultCode = 7
        }elseif($job.GetLastState() -eq "Postprocessing"){
            $jobResultCode = 6
        }
    }
    
    Write-Verbose "========================"
    
    $jobObject = [PSCustomObject]@{
        "ID"         = $i
        "Name"       = $job.Name
        "Result"     = $jobResultCode
        "Repository" = $job.GetBackupTargetRepository().Name
    }
    $i++
    $jobsTable += $jobObject
}


$jobsTable | Format-Table * -Autosize

### PRTG XML Header ###
$prtgresult = @"
<?xml version="1.0" encoding="UTF-8" ?>
<prtg>
  <text></text>

"@


### PRTG XML Content ###
foreach($jobRow in $jobsTable){
    $jobID = $jobRow.ID
    $jobName = $jobRow.Name
    $jobResult = $jobRow.Result
    $jobRepository = $jobRow.Repository


$prtgresult += @"
  <result>
    <channel>$jobName</channel>
    <unit>Custom</unit>
    <value>$jobResult</value>
    <showChart>1</showChart>
    <showTable>1</showTable>
    <ValueLookup>ts.veeam.jobstatus.push</ValueLookup>
  </result>

"@
}



### PRTG XML Footer ###
$prtgresult += @"

</prtg>
"@


### Push to PRTG ###
function sendPush(){
    Add-Type -AssemblyName system.web

    write-host "result"-ForegroundColor Green
    write-host $prtgresult 

    #$Answer = Invoke-WebRequest -Uri $NETXNUA -Method Post -Body $RequestBody -ContentType $ContentType -UseBasicParsing
    $answer = Invoke-WebRequest `
       -method POST `
       -URI ($probeIP + ":" + $sensorPort + "/" + $sensorKey) `
       -ContentType "text/xml" `
       -Body $prtgresult `
       -usebasicparsing

    # Get Cert Thumbprint and expiration for debug
    $servicePoint = [System.Net.ServicePointManager]::FindServicePoint($probeIP + ":" + $sensorPort)
    write-verbose "CERT INFO"
    write-verbose $servicePoint.Certificate.GetCertHashString()
    write-verbose $servicePoint.Certificate.GetExpirationDateString()
    
    if ($answer.statuscode -ne 200) {
       write-warning "Request to PRTG failed"
       write-host "answer: " $answer.statuscode
       exit 1
    }
    else {
       $answer.content
    }
}

if($DryRun){
    write-host $prtgresult
}else{
    sendPush
}