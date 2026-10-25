# 유선 어댑터 Wake-on-LAN 설정 (관리자 PowerShell에서 실행)
#   powershell -ExecutionPolicy Bypass -File agent\setup_wol.ps1
$ErrorActionPreference = 'Stop'

$nic = Get-NetAdapter -Physical | Where-Object { $_.PhysicalMediaType -eq '802.3' } | Select-Object -First 1
if (-not $nic) { throw '유선(이더넷) 어댑터를 찾지 못했습니다. 랜선 연결 상태를 확인하세요.' }
Write-Host "어댑터: $($nic.Name) / $($nic.InterfaceDescription) / MAC $($nic.MacAddress)"

# 1) 어댑터 전원 관리: Magic Packet 깨우기 허용, 절전용 전원 차단 해제
Set-NetAdapterPowerManagement -Name $nic.Name -WakeOnMagicPacket Enabled -ErrorAction Continue
Set-NetAdapterPowerManagement -Name $nic.Name -AllowComputerToTurnOffDevice Disabled -ErrorAction Continue

# 2) 고급 속성 (드라이버마다 이름이 다름: 일치하는 항목만 사용)
Get-NetAdapterAdvancedProperty -Name $nic.Name |
    Where-Object { $_.DisplayName -match 'Magic Packet|매직 패킷|Shutdown Wake|Wake on' } |
    ForEach-Object {
        Write-Host "고급 속성: $($_.DisplayName) = $($_.DisplayValue)"
        if ($_.DisplayName -match 'Magic Packet|매직 패킷' -and $_.DisplayValue -notmatch 'Enabled|사용') {
            Set-NetAdapterAdvancedProperty -Name $nic.Name -DisplayName $_.DisplayName -DisplayValue 'Enabled' -ErrorAction Continue
        }
    }

# 3) 빠른 시작 끄기 (최대 절전 기능 자체는 유지)
powercfg /h on
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled -Value 0

# 4) 결과 확인
Write-Host "`n--- 깨우기 허용 장치 (여기에 유선 어댑터가 보여야 함) ---"
powercfg /devicequery wake_armed
Write-Host "`n공유기 WOL 등록용 MAC: $($nic.MacAddress)"
Write-Host 'BIOS(F2)에서 Wake on LAN 항목이 있으면 Enabled로 바꾸세요.'
