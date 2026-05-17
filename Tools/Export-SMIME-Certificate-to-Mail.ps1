<#
.SYNOPSIS
    This script exports an S/MIME certificate with a private key and sends it as an email attachment.
.DESCRIPTION
    This script prompts the user to select an S/MIME certificate, exports it with the private key to a PFX file,
    and then sends an email with the exported PFX file as an attachment. The user is prompted to enter a password
    for the private key. After sending the email, the script deletes the PFX file.
.NOTES
    File Name: Export-SMIMECertificate.ps1
    Author   : Tsukaito
    Date     : 2024-03-24
 
    Version History:
    1.0 - [2024-03-24] - Initial version.
    1.1 - [2024-04-01] - Only certificate for Encryption and language specific settings 
 
    Prerequisites:
    - This script requires Windows PowerShell.
    - The user running the script must have permission to access the S/MIME certificate.
    - The script relies on the user having access to Outlook for sending emails.
    - The user must enter a password for certificate export
#>
 
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
 
# Create a new instance of Windows Form
$form = New-Object System.Windows.Forms.Form
$form.Text = "S/MIME Certificate Exporter"
$form.Size = New-Object System.Drawing.Size(500,300)
$form.StartPosition = "CenterScreen"
 
# Create a label for certificate selection
$labelCert = New-Object System.Windows.Forms.Label
$labelCert.Location = New-Object System.Drawing.Point(10,20)
$labelCert.Size = New-Object System.Drawing.Size(460,20)
$labelCert.Text = "Select the S/MIME certificate to export:"
$form.Controls.Add($labelCert)
 
# Create a dropdown list (ComboBox) for certificates
$comboBoxCert = New-Object System.Windows.Forms.ComboBox
$comboBoxCert.Location = New-Object System.Drawing.Point(10,40)
$comboBoxCert.Size = New-Object System.Drawing.Size(460,20)
$form.Controls.Add($comboBoxCert)
 
# Create a label for password
$labelPass = New-Object System.Windows.Forms.Label
$labelPass.Location = New-Object System.Drawing.Point(10,80)
$labelPass.Size = New-Object System.Drawing.Size(460,20)
$labelPass.Text = "Enter password for private key:"
$form.Controls.Add($labelPass)
 
# Create a textbox for password
$textBoxPass = New-Object System.Windows.Forms.TextBox
$textBoxPass.Location = New-Object System.Drawing.Point(10,100)
$textBoxPass.Size = New-Object System.Drawing.Size(460,20)
$textBoxPass.PasswordChar = "*"
$form.Controls.Add($textBoxPass)
 
# Get OS language for certificate oid friendly name
 
if((Get-WinSystemLocale).Name -eq "de-dE"){
 
    $OIDFriendlyName = 'Schlüsselverwendung'
 
} else{
 
    $OIDFriendlyName = 'KeyUsage'
 
}
 
# Get certificates for "secure email configuration"
$certificates = Get-ChildItem -Path cert:\CurrentUser\My | ?{$_.EnhancedKeyUsageList -like "*1.3.6.1.5.5.7.3.4*"}
# Get only certificates for de/encryption
$certificates = $certificates | Where-Object{ $_.Extensions | Where-Object{ ($_.Oid.FriendlyName -eq $OIDFriendlyName ) -and ($_.Format(0) -like "*(20)*") }}
 
# Populate the ComboBox with S/MIME certificate subjects
foreach ($cert in $certificates) {
    $comboBoxCert.Items.Add($cert.Thumbprint)
}
 
# Create an export button
$buttonExport = New-Object System.Windows.Forms.Button
$buttonExport.Location = New-Object System.Drawing.Point(150,140)
$buttonExport.Size = New-Object System.Drawing.Size(200,60)
$buttonExport.Text = "Send S/MIME Certificate via Outlook Mail"
$buttonExport.Add_Click({
    $selectedThumbprint = $comboBoxCert.SelectedItem
    if ([string]::IsNullOrWhiteSpace($selectedThumbprint)) {
        [System.Windows.Forms.MessageBox]::Show("Please select your S/MIME certificate.", "Error", 
        [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        return
    }
 
    # Get the selected certificate
    $cert = $certificates | Where-Object {$_.Thumbprint -eq $selectedThumbprint}
 
    # Export the S/MIME certificate with private key
    $exportPath = $env:TEMP + "\"+ $cert.Thumbprint + ".pfx"
    $password = $textBoxPass.Text
 
    if ([string]::IsNullOrWhiteSpace($password)) {
        [System.Windows.Forms.MessageBox]::Show("Please enter a password for the certificate.", "Error", 
        [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        return
    }
 
    try {
        Export-PfxCertificate -Cert $cert -FilePath $exportPath -Password (ConvertTo-SecureString -String $password -AsPlainText -Force)
        [System.Windows.Forms.MessageBox]::Show("S/MIME Certificate exported successfully.", "Success", 
        [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Error exporting S/MIME certificate with private key: $_", "Error",
        [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        return
    }
 
    # Create a new Outlook application object
    $outlook = New-Object -ComObject Outlook.Application
 
    # Create a new mail item
    $mail = $outlook.CreateItem(0)
 
    # Set email properties
    $mail.Subject = "S/MIME Certificate"
    $mail.Body = "Please find the S/MIME certificate attached."
 
    # Attach the certificate file
    $attachment = $exportPath
    $mail.Attachments.Add($attachment)
 
    # Display the mail item
    $mail.Display()
 
    # Delete the PFX file after sending the email
    Remove-Item -Path $attachment -Force
 
})
$form.Controls.Add($buttonExport)
 
# Show the form
$form.ShowDialog() | Out-Null