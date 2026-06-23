function Get-ADSIGroupMember {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [string]$Identity,

        [Parameter(Mandatory = $false)]
        [switch]$Recursive,

        [Parameter(Mandatory = $false)]
        [System.Management.Automation.PSCredential]$Credential
    )

    begin {
        $ServerList = @('zone1.abc.net','zone2.abc.net','zone3.abc.net','abc.net')

        #region --- Helper: DirectoryEntry factory ---
        function New-DirectoryEntry {
            param([string]$LdapPath, [System.Management.Automation.PSCredential]$Cred)
            if ($Cred) {
                return New-Object System.DirectoryServices.DirectoryEntry(
                    $LdapPath, $Cred.UserName, $Cred.GetNetworkCredential().Password
                )
            }
            return New-Object System.DirectoryServices.DirectoryEntry($LdapPath)
        }

        #region --- Helper: Build LDAP filter from identity type ---
        function Get-IdentityFilter {
            param([string]$Identity)

            # GUID
            if ($Identity -match '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$') {
                $guidBytes  = ([guid]$Identity).ToByteArray()
                $escapedHex = ($guidBytes | ForEach-Object { '\{0:x2}' -f $_ }) -join ''
                return "(&(objectClass=group)(objectGUID=$escapedHex))"
            }
            # Email
            if ($Identity -match '@') {
                return "(&(objectClass=group)(|(mail=$Identity)(userPrincipalName=$Identity)))"
            }
            # Distinguished Name
            if ($Identity -match '^CN=') {
                return "(&(objectClass=group)(distinguishedName=$Identity))"
            }
            # SamAccountName / name fallback
            return "(&(objectClass=group)(|(samAccountName=$Identity)(name=$Identity)(cn=$Identity)))"
        }

        #region --- Helper: Find any object by DN, trying preferred server first ---
        function Find-DirectoryEntryByDN {
            param(
                [string]$DN,
                [string]$PreferredServer,
                [System.Management.Automation.PSCredential]$Cred
            )
            # Build server attempt order: preferred first, then the rest
            $order = @($PreferredServer) + ($ServerList | Where-Object { $_ -ne $PreferredServer })

            foreach ($server in $order) {
                try {
                    $searcher = New-Object System.DirectoryServices.DirectorySearcher(
                        (New-DirectoryEntry -LdapPath "LDAP://$server" -Cred $Cred)
                    )
                    $searcher.Filter = "(distinguishedName=$DN)"
                    $searcher.PropertiesToLoad.AddRange(@(
                        'distinguishedname','name','objectclass',
                        'objectguid','samaccountname','objectsid','mail','displayname'
                    ))
                    $result = $searcher.FindOne()
                    if ($result) {
                        return @{ Result = $result; Server = $server }
                    }
                }
                catch { Write-Verbose "DN lookup failed on $server`: $_" }
            }
            return $null
        }

        #region --- Helper: Convert SearchResult to output object ---
        function ConvertTo-MemberObject {
            param(
                [System.DirectoryServices.SearchResult]$Result,
                [string]$ParentGroup,
                [string]$FoundOnServer
            )
            $p           = $Result.Properties
            $objectClass = ($p['objectclass'] | Select-Object -Last 1).ToString().ToLower()
            $objectType  = switch ($objectClass) {
                'user'          { 'User'     }
                'group'         { 'Group'    }
                'computer'      { 'Computer' }
                'inetorgperson' { 'User'     }
                default         { $objectClass }
            }

            [PSCustomObject]@{
                distinguishedName = if ($p['distinguishedname'].Count) { $p['distinguishedname'][0] } else { '' }
                name              = if ($p['name'].Count)              { $p['name'][0]              } else { '' }
                displayName       = if ($p['displayname'].Count)       { $p['displayname'][0]       } else { '' }
                objectClass       = $objectType
                objectGUID        = if ($p['objectguid'].Count)        { [guid]$p['objectguid'][0]  } else { [guid]::Empty }
                SamAccountName    = if ($p['samaccountname'].Count)    { $p['samaccountname'][0]    } else { '' }
                EmailAddress      = if ($p['mail'].Count)              { $p['mail'][0]              } else { '' }
                SID               = if ($p['objectsid'].Count) {
                                        (New-Object System.Security.Principal.SecurityIdentifier(
                                            $p['objectsid'][0], 0)).Value
                                    } else { '' }
                MemberOf          = $ParentGroup
                FoundOnServer     = $FoundOnServer
            }
        }

        #region --- Core: Page through group members safely using range retrieval ---
        # Safe for 2000+ members. Direct [ADSI] .member property truncates at 1500 silently.
        function Get-GroupMemberDNs {
            param(
                [string]$GroupDN,
                [string]$Server,
                [System.Management.Automation.PSCredential]$Cred
            )

            $allDNs     = [System.Collections.Generic.List[string]]::new()
            $rangeStart = 0
            $rangeSize  = 1000   # Conservative — works even if DC MaxValRange is lowered from default 1500
            $groupEntry = New-DirectoryEntry -LdapPath "LDAP://$Server/$GroupDN" -Cred $Cred

            do {
                $rangeEnd  = $rangeStart + $rangeSize - 1
                $rangeAttr = "member;range=$rangeStart-$rangeEnd"

                $searcher = New-Object System.DirectoryServices.DirectorySearcher($groupEntry)
                $searcher.PropertiesToLoad.AddRange(@('member', $rangeAttr))
                $searcher.Filter   = '(objectClass=group)'
                $searcher.PageSize = 1000

                $result = $searcher.FindOne()
                if (-not $result) { break }

                # Determine which attribute AD actually returned
                $returnedAttr = $result.Properties.PropertyNames |
                    Where-Object { $_ -eq 'member' -or $_ -like 'member;range=*' } |
                    Select-Object -First 1

                # No member attribute = empty group
                if (-not $returnedAttr) {
                    Write-Verbose "Group has no members: $GroupDN"
                    break
                }

                $memberDNs = @($result.Properties[$returnedAttr])

                foreach ($dn in $memberDNs) {
                    if (-not [string]::IsNullOrWhiteSpace($dn)) {
                        $allDNs.Add($dn)
                    }
                }

                Write-Verbose "Range $rangeStart-$rangeEnd : retrieved $($memberDNs.Count) DNs (total so far: $($allDNs.Count))"

                # 'member' (no range suffix) = all fit on one page. Done.
                if ($returnedAttr -eq 'member') { break }

                # range ending in '*' = last page. Done.
                if ($returnedAttr -match '\*$') { break }

                $rangeStart += $rangeSize

            } while ($true)

            return $allDNs
        }

        #region --- Recursive BFS expander ---
        function Expand-GroupRecursive {
            param(
                [string]$GroupDN,
                [string]$PreferredServer,
                [string]$GroupName,
                [System.Collections.Generic.HashSet[string]]$Visited,
                [System.Management.Automation.PSCredential]$Cred
            )

            if ($Visited.Contains($GroupDN)) { return }
            [void]$Visited.Add($GroupDN)

            # Get all member DNs safely via range paging
            $memberDNs = Get-GroupMemberDNs -GroupDN $GroupDN -Server $PreferredServer -Cred $Cred

            foreach ($memberDN in $memberDNs) {
                $found = Find-DirectoryEntryByDN -DN $memberDN -PreferredServer $PreferredServer -Cred $Cred
                if (-not $found) {
                    Write-Verbose "Could not resolve member DN: $memberDN"
                    continue
                }

                $objectClass = ($found.Result.Properties['objectclass'] | Select-Object -Last 1).ToString().ToLower()

                if ($objectClass -eq 'group') {
                    # Recurse into nested group
                    $nestedName = if ($found.Result.Properties['name'].Count) {
                        $found.Result.Properties['name'][0]
                    } else { $memberDN }

                    Expand-GroupRecursive -GroupDN $memberDN `
                                          -PreferredServer $found.Server `
                                          -GroupName $nestedName `
                                          -Visited $Visited `
                                          -Cred $Cred
                }
                else {
                    # Emit leaf member
                    ConvertTo-MemberObject -Result $found.Result `
                                           -ParentGroup $GroupName `
                                           -FoundOnServer $found.Server
                }
            }
        }

        $script:VisitedGroups = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::OrdinalIgnoreCase
        )
    }

    process {
        #region --- Step 1: Find group with auto-failover ---
        $ldapFilter  = Get-IdentityFilter -Identity $Identity
        $ldapRoot    = $null
        $defaultNC   = $null
        $groupResult = $null

        Write-Verbose "Identity filter: $ldapFilter"

        foreach ($server in $ServerList) {
            try {
                $parts = $server.Split('.')
                $nc    = ($parts | ForEach-Object { "DC=$_" }) -join ','
                $entry = New-DirectoryEntry -LdapPath "LDAP://$server/$nc" -Cred $Credential

                # Reachability probe
                $null = $entry.Name

                $searcher = New-Object System.DirectoryServices.DirectorySearcher($entry)
                $searcher.Filter   = $ldapFilter
                $searcher.PageSize = 1000
                $searcher.PropertiesToLoad.AddRange(@('distinguishedname','name','samaccountname'))

                $result = $searcher.FindOne()
                if ($result) {
                    $ldapRoot    = $server
                    $defaultNC   = $nc
                    $groupResult = $result
                    Write-Verbose "Group found on: $server"
                    break
                }
                else { Write-Verbose "Not found on $server, trying next..." }
            }
            catch { Write-Verbose "Server $server error: $_" }
        }

        if (-not $groupResult) {
            Write-Error "Group '$Identity' was not found on any server: $($ServerList -join ', ')"
            return
        }

        $groupDN   = $groupResult.Properties['distinguishedname'][0]
        $groupName = $groupResult.Properties['name'][0]

        Write-Verbose "Resolved: $groupName [$groupDN] via $ldapRoot"

        #region --- Step 2: Retrieve members ---
        if (-not $Recursive) {
            $memberDNs = Get-GroupMemberDNs -GroupDN $groupDN -Server $ldapRoot -Cred $Credential

            foreach ($memberDN in $memberDNs) {
                $found = Find-DirectoryEntryByDN -DN $memberDN -PreferredServer $ldapRoot -Cred $Credential
                if ($found) {
                    ConvertTo-MemberObject -Result $found.Result `
                                           -ParentGroup $groupName `
                                           -FoundOnServer $found.Server
                }
                else {
                    Write-Verbose "Could not resolve member DN: $memberDN"
                }
            }
        }
        else {
            Expand-GroupRecursive -GroupDN $groupDN `
                                  -PreferredServer $ldapRoot `
                                  -GroupName $groupName `
                                  -Visited $script:VisitedGroups `
                                  -Cred $Credential
        }
    }

    end {
        $script:VisitedGroups.Clear()
    }
}
