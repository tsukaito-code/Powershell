<# 
.NAME
    Set-NTFSPermissions.ps1
 
.AUTHOR
    Tsukaito

.SYNOPSIS
    Script set NTFS permissions for a folder.
 
.DESCRIPTION 
    Script set NTFS permissions for a folder. 
    It will get the original acces controll list (ACL), adds the permissions, remove inhitered permissions and save the new ACL.
  
.NOTES 
 
.COMPONENT 
    No powershell modules needed
 
.LINK 
    https://blue42.net/windows/changing-ntfs-security-permissions-using-powershell/#propagation-flags
  
.Parameter ParameterName 
 
#>
  
# Folder
$Folder = "C:\Data\Produktion"
 
# Get ACL From Folder
$acl = Get-Acl -Path $Folder
 
# Permission groups
$grp_modify = "acme\FS_Produktion_M"
$grp_read = "acme\FS_Produktion_R"


# Generate access tokens
 
# 1: group (with domain part)
# 2: permission
# 3: inheritance flag
# 4: propagation flag
# 5: allow or deny permission
# For flags 3 and 4 look at: https://blue42.net/windows/changing-ntfs-security-permissions-using-powershell/#propagation-flags
 
$mdRule = New-Object System.Security.AccessControl.FileSystemAccessRule($grp_modify,"Modify","ContainerInherit,ObjectInherit","None","Allow")
$roRule = New-Object System.Security.AccessControl.FileSystemAccessRule($grp_read,"ReadAndExecute","ContainerInherit,ObjectInherit","None","Allow")
 
# Disable/Enable inheritance (keep or delete inherited permissions)
# The first $true says we are blocking inheritance from the parent folder. The second parameter $false removes the current inherited permissions.
# OPTION 1: Block inheritance, keep inherited permissions and add the new
$acl.SetAccessRuleProtection($true, $true)
 
# OPTION 2: Block inheritance, remove inherited permissions and set only new
$acl.SetAccessRuleProtection($true, $false)
 
# Add Modify Rule to ACL Object
$acl.SetAccessRule($mdRule)
$acl.SetAccessRule($roRule)
 
# Save ACL-object to folder
Set-Acl -Path $folder -AclObject $acl