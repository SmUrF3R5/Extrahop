    

#Requires -Modules ActiveDirectory

#   Backup your current triggers before running this one!

#   Update-ADScriptTrigger
#   By: SmuRf3R5

<#
    Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation 
    files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, 
    modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software 
    is furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES 
    OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE 
    LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR 
    IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#>

<#
    This script will update the Active Direcotry module trigger provided by Extrahop. First it will attempt to locate the trigger by
    $TriggerName = "Active Directory" 

    The priv_names list will be updated with a current list of 
        
        Domain Admins, 
        Enterprise Admins, 
        Account Operators, 
        Backup Administrors, 
        Schema Admins 
        or any other SAMAccountName that still has the 'AdminCount' attribute set to 1
    
    Source:
    https://docs.microsoft.com/en-us/windows-server/identity/ad-ds/plan/security-best-practices/appendix-c--protected-accounts-and-groups-in-active-directory
#>

<#  
    API Information can be found here:
    Settings | Administrative | API Access | Extrahop API Explorer link

    Put your API key in the upper right box API_Key
    then find the Trigger category /triggers
    https://YOUR_APPLIANCE_URL/api/v1/explore/#!/Trigger/getAll
#>

# Change to SilentlyContinue to disable verbose logging
#$VerbosePreference = " Continue" 

# Found here https://YOUR_APPLIANCE_URL/admin/api/
$APIKey = "YOUR_API_HERE" 
$ExtraHopURI = "https://YOUR_APPLIANCE_URL/api/v1/triggers"
$TriggerName = 'Active Directory'

# By Default powershell uses 1.0
# The extrahop site appears to require tls 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Format a header for the extrahop rest request
$Headers = @{
                Accept = 'application/json'
                Authorization = 'ExtraHop apikey=' + $APIKey
            }
try 
{
    # Find Active Directory Trigger
    Write-Verbose "Searching for TriggerMame: $TriggerName"
    
    $trigger = Invoke-RestMethod -UseBasicParsing -uri $ExtraHopURI -Method Get -Headers $Headers -Body $Body -ErrorAction Stop
    $TriggerID  = ($trigger | Where-Object{$_.name -eq $TriggerName}).id
    
    Write-Verbose "Trigger ID: $TriggerID"

    try
    {
        # Get the script
        Write-Verbose "Attempting to get current script from extrahop appliance..."
        $Existing_Script = Invoke-RestMethod -UseBasicParsing -uri ($ExtraHopURI + "/" + $TriggerID) -Method Get -Headers $Headers -Body $Body -ErrorAction Stop

        # Backup Existing Script
        $Existing_Script.script | Out-File "$PSScriptRoot\ADScriptTrigger.js"

        # Preserve default values that were is original script
        $ExtraHopDefaultValues = ("const priv_names = [
            'admin',
            'administrator',
            'root',
            'sa',
            'sys',
            'sysman',
            'sysadmin',
            'informix',
            'db2admin',
            'postgres'`n`n
            // Company Specific Admin Accounts`n`n`n")

        # Get the list of current  Privileged accounts in Active Directory {AdminCOunt -eq 1}
        Write-Verbose "Getting list of  Privileged Users..."
        $UpdatedPrivNames = (((get-aduser -Filter {AdminCount -eq 1} -Properties AdminCount).SamAccountName.toLower() ) -replace ('\A',"`t,'") -replace ('\z', "'") | Sort-Object | out-string )
        Write-Verbose " Privileged Users retrieved!"        

        # Debug to display what was captured and formated
        #$ExtrahopDefaultValues + $UpdatedPrivNames + "`n`t//Upadted $(get-date)`n];"

        # Update Script in Memmory $Existing_Script
        $UpdatedScript = $Existing_Script.script -replace 'const priv_names = \[[\u0000-\uFFFF]*?];' , $($ExtrahopDefaultValues + $UpdatedPrivNames + "`n`t//Upadted $(get-date)`n];")

        # Generate PATCH update body and convert to JSON
        $UpdatedBody = @{   
                            apply_all = $false
                            debug = $false
                            disabled = $false                        
                            script = $UpdatedScript
                        }  | ConvertTo-Json 
        
        # For debug purposes. Saves the JSON file to the scriptroot directory
        #$UpdatedBody | ConvertTo-Json | Out-File "$PSScriptRoot\UpdatedJson.json"

        Write-Verbose "Updating Trigger"
        $UpdateTrigger =  Invoke-RestMethod -UseBasicParsing -uri ($ExtraHopURI + "/" + $TriggerID) -Method Patch -Headers $Headers -Body $UpdatedBody -ErrorAction Stop     

        Write-Verbose "Script completed!"

    }
    catch [exception]
    {
        Write-warning $_.exception
        Write-Verbose "Return: 1"
        return 1;
    }

}
catch 
{
    Write-Warning $_.exception.message 
    Write-Verbose "Return: 1"
    return 1;
}

Write-Verbose "Return: 0"
return 0;
