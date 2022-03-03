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
$probeIP = "PROBE"
$sensorPort = "PORT"
$sensorKey ="KEY"
#####  CONFIG END  #####

$jobs = Get-VBRJob

$jobsTable	= @()
$i = 1;
foreach($job in $jobs){

    switch($job.FindLastSession().Result){
        "Success" { $jobResultCode = 0 } # OK
        "Warning" { $jobResultCode = 1 } # Warning
        "Failed"  { $jobResultCode = 2 } # Error
        Default   { $jobResultcode = 9 } # Unknown
    }

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
       -URI ("http://" + $probeIP + ":" + $sensorPort + "/" + $sensorKey) `
       -ContentType "text/xml" `
       -Body $prtgresult `
       -usebasicparsing

       #-Body ("content="+[System.Web.HttpUtility]::UrlEncode.($prtgresult)) `
    #http://prtg.ts-man.ch:5055/637D334C-DCD5-49E3-94CA-CE12ABB184C3?content=<prtg><result><channel>MyChannel</channel><value>10</value></result><text>this%20is%20a%20message</text></prtg>   
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