$port = 5500
$prefix = "http://localhost:$port/"
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($prefix)
$listener.Start()
Write-Host "Secure GoldNow Server running at $prefix"

# 서버 측 환경에만 안전하게 보관되는 API Key (클라이언트 브라우저로 노출되지 않음)
$env:SECURE_METAL_KEY = "b6b83b2b264f46ddd1615219f2758e6f"

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response
        
        # CORS 헤더
        $response.Headers.Add("Access-Control-Allow-Origin", "*")
        $response.Headers.Add("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        $response.Headers.Add("Access-Control-Allow-Headers", "Content-Type")

        if ($request.HttpMethod -eq "OPTIONS") {
            $response.StatusCode = 200
            $response.Close()
            continue
        }

        $urlPath = $request.Url.AbsolutePath

        # 1. 안전한 서버 프록시: 최신 시세 API (/api/latest)
        if ($urlPath -eq "/api/latest") {
            try {
                $apiKey = $env:SECURE_METAL_KEY
                $apiUrl = "https://api.metalpriceapi.com/v1/latest?api_key=$apiKey&base=USD&currencies=KRW,XAU,XAG,XPT,XPD"
                $apiRes = Invoke-RestMethod -Uri $apiUrl -Method Get -TimeoutSec 10
                $jsonStr = $apiRes | ConvertTo-Json -Depth 5 -Compress
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($jsonStr)
                $response.ContentType = "application/json; charset=utf-8"
                $response.ContentLength64 = $bytes.Length
                $response.OutputStream.Write($bytes, 0, $bytes.Length)
            } catch {
                $errorJson = '{"success":false,"message":"Proxy request failed"}'
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($errorJson)
                $response.StatusCode = 500
                $response.ContentType = "application/json; charset=utf-8"
                $response.ContentLength64 = $bytes.Length
                $response.OutputStream.Write($bytes, 0, $bytes.Length)
            }
            $response.Close()
            continue
        }

        # 2. 안전한 서버 프록시: 과거 시세 API (/api/timeframe)
        if ($urlPath -eq "/api/timeframe") {
            try {
                $apiKey = $env:SECURE_METAL_KEY
                $query = $request.Url.Query.TrimStart('?')
                $apiUrl = "https://api.metalpriceapi.com/v1/timeframe?api_key=$apiKey&$query"
                $apiRes = Invoke-RestMethod -Uri $apiUrl -Method Get -TimeoutSec 10
                $jsonStr = $apiRes | ConvertTo-Json -Depth 5 -Compress
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($jsonStr)
                $response.ContentType = "application/json; charset=utf-8"
                $response.ContentLength64 = $bytes.Length
                $response.OutputStream.Write($bytes, 0, $bytes.Length)
            } catch {
                $errorJson = '{"success":false,"message":"Proxy timeframe failed"}'
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($errorJson)
                $response.StatusCode = 500
                $response.ContentType = "application/json; charset=utf-8"
                $response.ContentLength64 = $bytes.Length
                $response.OutputStream.Write($bytes, 0, $bytes.Length)
            }
            $response.Close()
            continue
        }

        # 3. 정적 웹 파일 서빙 (HTML, CSS, JS)
        $localPath = $urlPath.TrimStart('/')
        if ([string]::IsNullOrEmpty($localPath)) { $localPath = 'index.html' }
        $filePath = Join-Path $PSScriptRoot $localPath
        if (Test-Path $filePath) {
            $bytes = [System.IO.File]::ReadAllBytes($filePath)
            $ext = [System.IO.Path]::GetExtension($filePath).ToLower()
            if ($ext -eq '.html') { $response.ContentType = 'text/html; charset=utf-8' }
            elseif ($ext -eq '.css') { $response.ContentType = 'text/css; charset=utf-8' }
            elseif ($ext -eq '.js') { $response.ContentType = 'application/javascript; charset=utf-8' }
            elseif ($ext -eq '.json') { $response.ContentType = 'application/json; charset=utf-8' }
            $response.ContentLength64 = $bytes.Length
            $response.OutputStream.Write($bytes, 0, $bytes.Length)
        } else {
            $response.StatusCode = 404
        }
        $response.Close()
    }
} finally {
    $listener.Stop()
}
