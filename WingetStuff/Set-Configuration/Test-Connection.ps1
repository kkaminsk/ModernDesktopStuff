$h = @{ 'User-Agent'='Set-Configuration-PS/1.0'; 'Accept'='application/vnd.github+json' }
$u = 'https://api.github.com/repos/kkaminsk/ModernDesktopStuff/contents/WingetStuff/Config_YAML_Examples?ref=main'
$r = Invoke-RestMethod -Uri $u -Headers $h
$r | Format-Table name,type,download_url