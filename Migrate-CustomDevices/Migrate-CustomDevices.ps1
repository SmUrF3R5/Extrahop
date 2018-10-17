$VerbosePreference="Continue"

#region Config
#Existing Appliance
$sourceHostfqdn      = "SOURCE_DEVICE.something.local"
$SourceApiKey        = "SOURCE_API_KEY"
#New Appliance
$DestinationHostfqdn = "DESTINATION_DEVICE.something.local"
$DestinationApiKey   = "DESTINATION_API_KEY"
#endregion

$SourceAuthHeader = @{
    Accept='application/json'
    Authorization = "ExtraHop apikey=$SourceApiKey"
}
$DestinationAuthHeader = @{
    Accept='application/json'
    Authorization = "ExtraHop apikey=$DestinationApiKey"
}

# This is used to accept the default self signed cert
add-type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy       
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12


# find the device group
Write-Verbose "*** Get all custom devices"
$CustomDevices = Invoke-RestMethod -uri "https://$sourceHostfqdn/api/v1/customdevices" -Method Get -Headers $Headers

#$CustomDevices | ft

if($CustomDevices){
    foreach ($device in $CustomDevices)
    {
        Write-Verbose "###################   $( $device.name)   ###################"
        $device
        try{
            Write-Verbose "*** Get custom device detail"
            $DeviceDetail =  Invoke-RestMethod -UseBasicParsing -uri "https://$sourceHostfqdn/api/v1/customdevices/$($device.id)" -Method Get -Headers $SourceAuthHeader -ErrorAction Stop
            Write-Verbose "DeviceDetail"
            $DeviceDetail   

            # Create New Device Body
            $NewCustomDeviceBody=@{
                author       = $device.author
                description  = $device.description
                disabled     = $device.disabled
                extrahop_id  = $device.name.Trim()
                name         = $device.name.Trim()
            } | ConvertTo-Json

            write-verbose "NewCustomDeviceBody"
            $NewCustomDeviceBody

            try{
                Write-Verbose "*** Create New Custom Device"
                $NewCustomDevice = Invoke-RestMethod -uri "https://$DestinationHostfqdn/api/v1/customdevices" -Method post -Headers $DestinationAuthHeader -Body $NewCustomDeviceBody -ErrorAction Stop

                Start-Sleep -Seconds 4               
                try{
                    Write-Verbose "*** Get new custom Device ID" 
                    $SearchIds = Invoke-RestMethod -uri "https://$DestinationHostfqdn/api/v1/customdevices" -Method Get -Headers $DestinationAuthHeader -ErrorAction Stop 
                    $NewID = ($SearchIds | where{$_.name -eq $device.name}).id
                    # Custom Device Criteria
                    $NewCriteriaBody = $DeviceDetail.Criteria
                    if($NewCriteriaBody){
                        #$NewCriteriaBody | select ipaddr
                        foreach ($item in $NewCriteriaBody | select ipaddr)
                        {
                            write-verbose " New Item Criteria"
                            $item 
                            $criteriaBody = @{
                                ipaddr = $item.ipaddr
                                custom_device_id = $newID
                            } | ConvertTo-Json

                            try{
                                Write-Verbose "*** Create new Criteria"
                                Invoke-RestMethod -uri "https://$DestinationHostfqdn/api/v1/customdevices/$NewID/criteria" -Method post -Headers $DestinationAuthHeader -Body $criteriaBody -ErrorAction Stop 
                            }
                            catch
                            {
                                Write-Warning "NewCriteria Exception"
                                Write-Error $_.exception
                                $NewID = $null
                                break;
                            }
                        }
                    }                    
                    Else{ 
                        Write-Verbose "No criteria defined for $($device.name) on [$sourceHostfqdn]" 
                    }
                }
                #Get new custom device exception
                catch{
                    Write-Warning "Get new custom device exception"
                    Write-Error $_.exception
                    $newID = $null
                }
            }
            # New Custom Device Exception
            catch{
                Write-Warning "New Custom Device Exception"
                Write-Error $_.Exception
            }
        }        
        #Device Detail Exception
        Catch{
            Write-Warning "Device Detail Exception"
            write-error $_.Exception    
        }      

      $newID = $null     

    }
}
