Add-Type -AssemblyName System.Windows.Forms
$f = New-Object System.Windows.Forms.Form
$f.Text = 'DeepSeek Harness'
$f.Size = New-Object System.Drawing.Size(300, 160)
$f.Add_FormClosed({ [System.Windows.Forms.Application]::Exit() })
$f.Show()
[System.Windows.Forms.Application]::Run($f)
