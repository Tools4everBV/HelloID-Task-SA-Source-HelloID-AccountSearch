#region HelloID variables
# Variables to use in connecting to HelloID API
$HelloIDPortalBaseUrl = $portalBaseUrl
$HelloIDApiKey = $portalApiKey
$HelloIDApiSecret = $portalApiSecret

# Variables to use in general wildcard filter for HelloID Users
$HelloIDUserSearchFilter = "$($dataSource.searchUser)" # Contains filter on Firstname, Lastname, Username, Contact email - Set to $null if not needed
#endregion HelloID variables

# Set logging preferences
$VerbosePreference = "SilentlyContinue"
$InformationPreference = "Continue"
$WarningPreference = "Continue"

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

#region functions
function Resolve-HelloIDError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            ScriptLineNumber = $ErrorObject.InvocationInfo.ScriptLineNumber
            Line             = $ErrorObject.InvocationInfo.Line
            ErrorDetails     = $ErrorObject.Exception.Message
            FriendlyMessage  = $ErrorObject.Exception.Message
        }
        if (-not [string]::IsNullOrEmpty($ErrorObject.ErrorDetails.Message)) {
            $httpErrorObj.ErrorDetails = $ErrorObject.ErrorDetails.Message
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq "System.Net.WebException") {
            if ($null -ne $ErrorObject.Exception.Response) {
                $streamReaderResponse = [HelloID.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
                if (-not [string]::IsNullOrEmpty($streamReaderResponse)) {
                    $httpErrorObj.ErrorDetails = $streamReaderResponse
                }
            }
        }
        try {
            $errorDetailsObject = ($httpErrorObj.ErrorDetails | ConvertFrom-Json)
            # error message can be either in [resultMsg] or [message]
            if ([bool]($errorDetailsObject.PSobject.Properties.name -eq "resultMsg")) {
                $httpErrorObj.FriendlyMessage = $errorDetailsObject.resultMsg
            }
            elseif ([bool]($errorDetailsObject.PSobject.Properties.name -eq "message")) {
                $httpErrorObj.FriendlyMessage = $errorDetailsObject.message
            }
        }
        catch {
            $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails
        }
        Write-Output $httpErrorObj
    }
}

function Invoke-HelloIDRestMethod {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Method,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Uri,

        [object]
        $Body,

        [string]
        $ContentType = "application/json",

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]
        $Headers,

        [Parameter()]
        [Boolean]
        $UsePaging = $false,

        [Parameter()]
        [Int]
        $Skip = 0,

        [Parameter()]
        [Int]
        $Take = 1000,

        [Parameter()]
        [Int]
        $TimeoutSec = 60
    )

    process {
        try {
            $splatParams = @{
                Uri             = $Uri
                Headers         = $Headers
                Method          = $Method
                ContentType     = $ContentType
                TimeoutSec      = 60
                UseBasicParsing = $true
                Verbose         = $false
                ErrorAction     = "Stop"
            }

            if ($Body) {
                Write-Verbose "Adding body to request in utf8 byte encoding"
                $splatParams["Body"] = ([System.Text.Encoding]::UTF8.GetBytes($Body))
            }

            if ($UsePaging -eq $true) {
                $result = [System.Collections.ArrayList]@()
                $startUri = $splatParams.Uri
                do {
                    if ($startUri -match "\?") {
                        $splatParams["Uri"] = $startUri + "&take=$($take)&skip=$($skip)"
                    }
                    else {
                        $splatParams["Uri"] = $startUri + "?take=$($take)&skip=$($skip)"
                    }

                    $response = (Invoke-RestMethod @splatParams)
                    if ([bool]($response.PSobject.Properties.name -eq "data")) {
                        $response = $response.data
                    }
                    if ($response -is [array]) {
                        [void]$result.AddRange($response)
                    }
                    else {
                        [void]$result.Add($response)
                    }
        
                    $skip += $take
                } while (($response | Measure-Object).Count -eq $take)
            }
            else {
                $result = Invoke-RestMethod @splatParams
            }

            Write-Output $result
        }
        catch {
            $ex = $PSItem
            if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
                $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
                $errorObj = Resolve-HelloIDError -ErrorObject $ex
                $auditMessage = "Error $($actionMessage). Error: $($errorObj.FriendlyMessage)"
            }
            else {
                $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
            }
            
            # Required to write an error as the listing of permissions doesn't show auditlog
            throw $auditMessage
        }
    }
}
#endregion functions

try {
    #region Create HelloID authorization key
    $actionMessage = "creating HelloID authorization key"

    $helloIDCredentials = "$($HelloIDApiKey):$($HelloIDApiSecret)"
    $helloIDCredentialBytes = [System.Text.Encoding]::ASCII.GetBytes($helloIDCredentials)
    $helloIDBase64EncodedCredentials = [System.Convert]::ToBase64String($helloIDCredentialBytes)
    $helloIDAuthorizationKey = "Basic $helloIDBase64EncodedCredentials"

    Write-Verbose "Created HelloID authorization key. Result: $($helloIDAuthorizationKey | ConvertTo-Json)."
    #endregion Create HelloID authorization key

    #region Create HelloID authorization headers
    $actionMessage = "creating HelloID authorization headers"

    $helloIDHeaders = @{
        "authorization" = $helloIDAuthorizationKey
    }

    Write-Verbose "Created HelloID authorization headers. Result: $($helloIDHeaders | ConvertTo-Json)."
    #endregion Create HelloID authorization headers
    
    #region Get HelloID users
    # API docs: https://apidocs.helloid.com/docs/helloid/041932dd2ca73-get-all-users
    $actionMessage = "querying HelloID users"

    if ($HelloIDUserSearchFilter -ne "*") {
        $getHelloIDUsersUri = "$($HelloIDPortalBaseUrl)/api/v1/users?search=$HelloIDUserSearchFilter"
    }
    else {
        $getHelloIDUsersUri = "$($HelloIDPortalBaseUrl)/api/v1/users"
    }
    $getHelloIDUsersSplatParams = @{
        Uri       = $getHelloIDUsersUri
        Headers   = $helloIDHeaders
        Method    = "GET"
        UsePaging = $true
    }

    $helloIDUsers = Invoke-HelloIDRestMethod @getHelloIDUsersSplatParams

    Write-Information "Queried HelloID users. Result count: $(($helloIDUsers | Measure-Object).Count)."
    #endregion Get HelloID users

    #region Return results to HelloID
    if (($helloIDUsers | Measure-Object).Count -gt 0) {
        foreach ($helloIDUser in $helloIDUsers) {
            Write-Output $helloIDUser
        }
    }
    #endregion Return results to HelloID
}
catch {
    $ex = $PSItem

    $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
    Write-Warning "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"

    # Required to write an error as the listing of permissions doesn't show auditlog
    Write-Error "Error $($actionMessage). Error: $($ex.Exception.Message)"
}