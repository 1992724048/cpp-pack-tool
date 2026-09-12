/// prelude 片段键的固定输出顺序（spec §4.1）。
///
/// 生成器仅输出已注册的键。`crc32` 与 `vars` 为动态内容键，不在
/// [preludeLibrary] 中：`crc32` 由注册方传入 [crc32Prelude]，`vars` 由
/// M4.3 的变量初始化块提供。
const List<String> preludeOrder = <String>[
  'ConvertFrom-CnpHex',
  'Find-CnpTool',
  'Get-CnpFileHash',
  'Invoke-CnpAesTransform',
  'Invoke-CnpSignFile',
  'crc32',
  'vars',
];

/// 5 个辅助函数的完整 PS 5.1 源码（键 → 片段文本）。
///
/// 片段无尾部换行、位于列 0；生成器按 [preludeOrder] 过滤并以空行分隔。
const Map<String, String> preludeLibrary = <String, String>{
  'ConvertFrom-CnpHex': _convertFromCnpHex,
  'Find-CnpTool': _findCnpTool,
  'Get-CnpFileHash': _getCnpFileHash,
  'Invoke-CnpAesTransform': _invokeCnpAesTransform,
  'Invoke-CnpSignFile': _invokeCnpSignFile,
};

/// CRC32 `Add-Type` 注入块（键 `crc32`）。
///
/// PS 5.1 无内置 CRC32（无 `System.IO.Hashing`），经 C# 表法注入
/// `CnpCrc32` 类型（多项式 `0xEDB88320`，8KB 缓冲流式读取）。
/// `PSTypeName` 守卫避免同一进程内重复注入；Add-Type 使用 C# 5 编译器，
/// 代码须保持 C# 5 语法（无字符串插值、表达式体成员等新特性）。
const String crc32Prelude = r'''if ($null -eq ([System.Management.Automation.PSTypeName]'CnpCrc32').Type) {
    Add-Type -TypeDefinition @'
using System.IO;

public static class CnpCrc32
{
    private static readonly uint[] Table = CreateTable();

    private static uint[] CreateTable()
    {
        uint[] table = new uint[256];
        for (int index = 0; index < table.Length; index++)
        {
            uint value = (uint)index;
            for (int bit = 0; bit < 8; bit++)
            {
                if ((value & 1) == 1)
                {
                    value = (value >> 1) ^ 0xEDB88320u;
                }
                else
                {
                    value = value >> 1;
                }
            }
            table[index] = value;
        }
        return table;
    }

    public static uint Hash(Stream stream)
    {
        uint crc = 0xFFFFFFFFu;
        byte[] buffer = new byte[8192];
        int count = stream.Read(buffer, 0, buffer.Length);
        while (count > 0)
        {
            for (int index = 0; index < count; index++)
            {
                crc = Table[(int)((crc ^ buffer[index]) & 0xFF)] ^ (crc >> 8);
            }
            count = stream.Read(buffer, 0, buffer.Length);
        }
        return crc ^ 0xFFFFFFFFu;
    }
}
'@
}''';

const String _convertFromCnpHex = r'''function ConvertFrom-CnpHex {
    param([string]$Hex)
    $normalized = $Hex -replace '\s', '' -replace '-', ''
    if ($normalized.Length % 2 -ne 0) {
        throw '十六进制字符串长度必须为偶数'
    }
    if ($normalized -notmatch '^[0-9A-Fa-f]*$') {
        throw '十六进制字符串包含非法字符'
    }
    $result = New-Object byte[] ($normalized.Length / 2)
    for ($index = 0; $index -lt $result.Length; $index++) {
        $result[$index] = [Convert]::ToByte($normalized.Substring($index * 2, 2), 16)
    }
    return ,$result
}''';

const String _findCnpTool = r'''function Find-CnpTool {
    param([string]$Name, [string[]]$Candidates)
    $command = Get-Command -Name $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $command) {
        return $command.Source
    }
    foreach ($candidate in $Candidates) {
        $expanded = [Environment]::ExpandEnvironmentVariables($candidate)
        if (Test-Path -LiteralPath $expanded -PathType Leaf) {
            return $expanded
        }
    }
    return $null
}''';

const String _getCnpFileHash = r'''function Get-CnpFileHash {
    param([string]$Path, [string]$Algorithm)
    if ($Algorithm -eq 'crc32') {
        $stream = [IO.File]::OpenRead($Path)
        try {
            return '{0:x8}' -f [CnpCrc32]::Hash($stream)
        } finally {
            $stream.Dispose()
        }
    }
    return (Get-FileHash -LiteralPath $Path -Algorithm $Algorithm).Hash.ToLowerInvariant()
}''';

const String _invokeCnpAesTransform = r'''function Invoke-CnpAesTransform {
    param([string]$Mode, [string]$Source, [string]$Destination, [string]$Password)
    $modeValue = $Mode.ToLowerInvariant()
    if ($modeValue -ne 'encrypt' -and $modeValue -ne 'decrypt') {
        throw "未知的 AES 模式「$Mode」"
    }
    $aes = [System.Security.Cryptography.Aes]::Create()
    $input = $null
    $output = $null
    $derive = $null
    $stream = $null
    try {
        $aes.KeySize = 256
        $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
        $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
        if ($modeValue -eq 'encrypt') {
            $salt = New-Object byte[] 16
            $iv = New-Object byte[] 16
            $random = [System.Security.Cryptography.RandomNumberGenerator]::Create()
            try {
                $random.GetBytes($salt)
                $random.GetBytes($iv)
            } finally {
                $random.Dispose()
            }
            # 三参构造的 PRF 为 HMACSHA1（PBKDF2-SHA1，10000 次迭代）
            $derive = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($Password, $salt, 10000)
            $aes.Key = $derive.GetBytes(32)
            $aes.IV = $iv
            $input = [IO.File]::OpenRead($Source)
            $output = [IO.File]::Create($Destination)
            $output.Write($salt, 0, $salt.Length)
            $output.Write($iv, 0, $iv.Length)
            $stream = New-Object System.Security.Cryptography.CryptoStream($output, $aes.CreateEncryptor(), [System.Security.Cryptography.CryptoStreamMode]::Write)
            $input.CopyTo($stream)
        } else {
            $input = [IO.File]::OpenRead($Source)
            $header = New-Object byte[] 32
            $offset = 0
            while ($offset -lt $header.Length) {
                $count = $input.Read($header, $offset, $header.Length - $offset)
                if ($count -le 0) {
                    throw '加密文件不完整：缺少 salt/iv 头'
                }
                $offset += $count
            }
            $salt = New-Object byte[] 16
            $iv = New-Object byte[] 16
            [Array]::Copy($header, 0, $salt, 0, 16)
            [Array]::Copy($header, 16, $iv, 0, 16)
            $derive = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($Password, $salt, 10000)
            $aes.Key = $derive.GetBytes(32)
            $aes.IV = $iv
            $output = [IO.File]::Create($Destination)
            $stream = New-Object System.Security.Cryptography.CryptoStream($input, $aes.CreateDecryptor(), [System.Security.Cryptography.CryptoStreamMode]::Read)
            $stream.CopyTo($output)
        }
    } finally {
        if ($null -ne $stream) { $stream.Dispose() }
        if ($null -ne $input) { $input.Dispose() }
        if ($null -ne $output) { $output.Dispose() }
        if ($null -ne $derive) { $derive.Dispose() }
        $aes.Dispose()
    }
}''';

const String _invokeCnpSignFile = r'''function Invoke-CnpSignFile {
    param([string]$Path, [string]$PfxPath, [string]$Thumbprint, [string]$Password, [string]$TimestampServer)
    if (-not $PfxPath -and -not $Thumbprint) {
        throw '必须提供 pfxPath 或 thumbprint 之一'
    }
    $signtool = Get-ChildItem -Path "${env:ProgramFiles(x86)}\Windows Kits\10\bin\*\x64\signtool.exe" -ErrorAction SilentlyContinue | Sort-Object -Property FullName -Descending | Select-Object -First 1
    if ($null -ne $signtool) {
        $arguments = @('sign', '/fd', 'SHA256')
        if ($PfxPath) {
            $arguments += @('/f', $PfxPath)
            if ($Password) {
                $arguments += @('/p', $Password)
            }
        } else {
            $arguments += @('/sha1', $Thumbprint)
        }
        if ($TimestampServer) {
            $arguments += @('/tr', $TimestampServer, '/td', 'SHA256')
        }
        $arguments += $Path
        & $signtool.FullName @arguments
        if ($LASTEXITCODE -ne 0) {
            throw "signtool 签名失败，退出码 $LASTEXITCODE"
        }
        return
    }
    if ($PfxPath) {
        if ($Password) {
            $certificate = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($PfxPath, $Password)
        } else {
            $certificate = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($PfxPath)
        }
    } else {
        $certificate = Get-ChildItem -Path Cert:\CurrentUser\My | Where-Object { $_.Thumbprint -eq $Thumbprint } | Select-Object -First 1
        if ($null -eq $certificate) {
            throw "未在 Cert:\CurrentUser\My 中找到指纹「$Thumbprint」的证书"
        }
    }
    try {
        $parameters = @{
            FilePath = $Path
            Certificate = $certificate
            HashAlgorithm = 'SHA256'
        }
        if ($TimestampServer) {
            $parameters.TimestampServer = $TimestampServer
        }
        $signature = Set-AuthenticodeSignature @parameters
        if ($signature.Status -eq 'NotSigned' -or $signature.Status -eq 'NotSupportedFileFormat') {
            throw "签名失败：$($signature.StatusMessage)"
        }
    } finally {
        if ($PfxPath) {
            $certificate.Dispose()
        }
    }
}''';
