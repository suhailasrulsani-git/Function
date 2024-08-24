function Get-AzureADRoleMembersRecursive {
    param (
        [string]$RoleObjectId,
        [string]$GroupObjectId = $null
    )

    # Get the members of the role or group
    $members = if ($GroupObjectId) {
        Get-AzureADGroupMember -ObjectId $GroupObjectId
    } else {
        Get-AzureADDirectoryRoleMember -ObjectId $RoleObjectId
    }

    foreach ($member in $members) {
        if ($member.ObjectType -eq "Group") {
            # If the member is a group, recurse into it
            Get-AzureADRoleMembersRecursive -RoleObjectId $RoleObjectId -GroupObjectId $member.ObjectId
        } else {
            # If the member is a user, output it
            $member
        }
    }
}

$roleObjectId = "0298a78e-59f2-4a95-845a-1b2e86b2cb86"
$allMembers = Get-AzureADRoleMembersRecursive -RoleObjectId $roleObjectId

# Output all members
$allMembers
