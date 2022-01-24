#-----------------------------------------------------------------------------------------------
# Balance number of VMs on VMware vSphere cluster (use for VDI)
# 
# Author: csilver42
#-----------------------------------------------------------------------------------------------
#  


#(Re-)set variables
$excludevms = @("","")
$vcenterserver = ""

###############################################################################
## Input vCenter-Server selection                                                      ##
###############################################################################
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$form = New-Object System.Windows.Forms.Form
$form.Text = 'vCenter-Server'
$form.Size = New-Object System.Drawing.Size(300,200)
$form.StartPosition = 'CenterScreen'

$okButton = New-Object System.Windows.Forms.Button
$okButton.Location = New-Object System.Drawing.Point(75,120)
$okButton.Size = New-Object System.Drawing.Size(75,23)
$okButton.Text = 'OK'
$okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
$form.AcceptButton = $okButton
$form.Controls.Add($okButton)

$cancelButton = New-Object System.Windows.Forms.Button
$cancelButton.Location = New-Object System.Drawing.Point(150,120)
$cancelButton.Size = New-Object System.Drawing.Size(75,23)
$cancelButton.Text = 'Cancel'
$cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
$form.CancelButton = $cancelButton
$form.Controls.Add($cancelButton)

$label = New-Object System.Windows.Forms.Label
$label.Location = New-Object System.Drawing.Point(10,20)
$label.Size = New-Object System.Drawing.Size(280,20)
$label.Text = 'Please enter vCenter Server (FQDN):'
$form.Controls.Add($label)

$textBox = New-Object System.Windows.Forms.TextBox
$textBox.Location = New-Object System.Drawing.Point(10,40)
$textBox.Size = New-Object System.Drawing.Size(260,20)
$textBox.Text = 'vCenter-Server FQDN' #Pre set your source
$form.Controls.Add($textBox)

$form.Topmost = $true

$form.Add_Shown({$textBox.Select()})
$result = $form.ShowDialog()


if ($result -eq [System.Windows.Forms.DialogResult]::OK)
	{
    $vcenterserver = $textBox.Text  
	}

if ($result -eq [System.Windows.Forms.DialogResult]::Cancel)
	{
	EXIT #End script
	}
	
###############################################################################
## load VMware Automation Core Snap In                                       ##
###############################################################################
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -DisplayDeprecationWarnings $false -Confirm:$false

$starttime = get-date
#Clear all connections
disconnect-viserver -server * -confirm:$false 
#Connect to VIServer
connect-viserver -server "$vcenterserver" 
$sourcehost = ""
$destinationhosts = ""
$VM = ""
$hosts = (Get-VMHost | Select-Object Name | Sort-Object Name)

###############################################################################
## Balance Hosts                                                             ##
###############################################################################


# Calculate average VMs per Host
$NumHosts = (get-vmhost | measure).count
$NumVMs = (get-vmhost | Get-VM | measure).count
$Limit = [math]::ceiling($NumVMs / $NumHosts)

if ($Limit -lt 2)
	{
	disconnect-viserver -server $vcenterserver -confirm:$false;
	EXIT #End script
	}

# Set DRS automation level to "manual" while migrating VMs
$Clusters = @(get-cluster | where-object {($_.DrsEnabled -eq "True")} | select-object Name,DrsAutomationLevel)
$ic = 0
while ($ic -lt $clusters.Count) {
	get-cluster -Name $clusters[$ic].Name | set-cluster -DrsAutomationLevel Manual -Confirm:$false
	$ic = $ic + 1
	}
	
# For each ESX host assigned more than 32 VMs migrate VMs
do {
                Foreach ($sourcehost in (Get-VMHost | Select @{N="Cluster";E={Get-Cluster -VMHost $_}}, Name, @{N="NumVM";E={($_ | Get-VM).Count}} | where { ($_.NumVM -gt $Limit)} | Sort-object -property NumVM -descending)){
    # Move the guest
                Start-Sleep -s 5;
                $targethost = (Get-VMHost | Select @{N="Cluster";E={Get-Cluster -VMHost $_}}, Name, @{N="NumVM";E={($_ | Get-VM).Count}} | Sort-object -property NumVM | Select -First 1).Name;
				Get-VMHost -Name $sourcehost.Name | Get-VM | Where { $_.PowerState -eq "poweredOn"} | Select -First 1 | Move-VM -Destination $targethost
                }
} until (@(Get-VMHost | Select @{N="Cluster";E={Get-Cluster -VMHost $_}}, Name, @{N="NumVM";E={($_ | Get-VM).Count}} | where { ($_.NumVM -gt $Limit)}).Count -eq 0)
 
 
# Set DRS automation level to previous value
$ic = 0
while ($ic -lt $clusters.Count) {
	get-cluster -Name $clusters[$ic].Name | set-cluster -DrsAutomationLevel $clusters[$iC].DrsAutomationLevel -Confirm:$false
	$ic = $ic + 1
	}
  
disconnect-viserver -server $vcenterserver -confirm:$false

