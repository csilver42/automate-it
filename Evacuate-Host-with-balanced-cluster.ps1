#-----------------------------------------------------------------------------------------------
# Evacuate VMs from ESXi host to get a balanced cluster without DRS )
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
$textBox.Text = 'vCenter server FQDN' #Pre set your source
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
## Input host selection                                                      ##
###############################################################################
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Select a host'
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
$label.Text = 'Please select a host to evacuate:'
$form.Controls.Add($label)

$listBox = New-Object System.Windows.Forms.ListBox
$listBox.Location = New-Object System.Drawing.Point(10,40)
$listBox.Size = New-Object System.Drawing.Size(260,20)
$listBox.Height = 80

foreach ($hosts in $hosts)
        {
        [void] $listBox.Items.Add($hosts.name)
        }

$form.Controls.Add($listBox)

$form.Topmost = $true

$result = $form.ShowDialog()

if ($result -eq [System.Windows.Forms.DialogResult]::OK)
	{
    $sourcehost = $listBox.SelectedItem
	$destinationhosts = (Get-VMHost | Select-Object Name | Where {($_.Name -ne "$sourcehost") -and ($_.ConnectionState -eq "Connected")} | Sort-Object Name)
	}
if ($result -eq [System.Windows.Forms.DialogResult]::Cancel)
	{
	disconnect-viserver -server $vcenterserver -confirm:$false
	EXIT #End script
	}
	
###############################################################################
## Output                                                                    ##
###############################################################################

# Set DRS automation level to "manual" while migrating VMs
$Clusters = @(get-cluster | where-object {($_.DrsEnabled -eq "True")} | select-object Name,DrsAutomationLevel)
$ic = 0
while ($ic -lt $clusters.Count) {
	get-cluster -Name $clusters[$ic].Name | set-cluster -DrsAutomationLevel Manual -Confirm:$false
	$ic = $ic + 1
	}


# For each of the online VMs on the ESX host
do {
                Foreach ($VM in (Get-VM | Where { $_.PowerState -eq "poweredOn" -and $_.VMHost -like "*$sourcehost*" -and $excludevms -notcontains $_.Name } | Sort-Object -Property MemoryGB -descending)){
    # Move the guest
                Start-Sleep -s 5
                $targethost = (Get-VMHost | Where { ($_.Name -ne "$sourcehost") -and ($_.ConnectionState -eq "Connected")} | Select Name,@{N='MemoryFreeGB';E={[math]::Round(($_.MemoryTotalGB - $_.MemoryUsageGB),2)}} | Sort-Object MemoryFreeGB -descending| select-object -first 1)
                $VM | Move-VM -Destination $targethost.Name
                }
} until (@(Get-VM | Where { $_.PowerState -eq "poweredOn" -and $_.VMHost -like "*$sourcehost*" -and $excludevms -notcontains $_.Name }).Count -eq 0)
 
# For each of the offline VMs on the ESX host
do {
                $i=0
                Foreach ($VM in (Get-VM | Where { $_.PowerState -eq "poweredOff" -and $_.VMHost -like "*$sourcehost*" -and $excludevms -notcontains $_.Name })){
    # Move the guest
    if ($i -ne ($destinationhosts.length)){
                               $destinationhosts.Name[$i]
                               $VM | Move-VM -Destination $destinationhosts.Name[$i]
                               $i = $i + 1
                               }
                }
} until (@(Get-VM | Where { $_.PowerState -eq "poweredOff" -and $_.VMHost -like "*$sourcehost*" -and $excludevms -notcontains $_.Name }).Count -eq 0)

If (@(Get-VM | Where { $_.PowerState -eq "poweredOn" -and $_.VMHost -like "*$sourcehost*" -and $excludevms -notcontains $_.Name}).Count -eq 0) {
                Set-VMHost -VMhost $sourcehost -State "Maintenance" }
                
  
# Set DRS automation level to previous value
$ic = 0
while ($ic -lt $clusters.Count) {
	get-cluster -Name $clusters[$ic].Name | set-cluster -DrsAutomationLevel $clusters[$iC].DrsAutomationLevel -Confirm:$false
	$ic = $ic + 1
	}
  
disconnect-viserver -server $vcenterserver -confirm:$false
