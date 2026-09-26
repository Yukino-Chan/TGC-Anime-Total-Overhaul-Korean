#requires -Version 5.1
$ErrorActionPreference='Stop'
$m=Import-Module (Join-Path $PSScriptRoot 'Online-Core.psm1') -Force -DisableNameChecking -PassThru
Add-Type @'
using System; using System.Net; using System.IO; using System.Text;
public class GhcrFixtureResponse : WebResponse {
 public HttpStatusCode StatusCode {get;set;}
 private WebHeaderCollection headers=new WebHeaderCollection();
 public override WebHeaderCollection Headers {get {return headers;}}
 public byte[] Body;
 public override long ContentLength {get {return Body.Length;}}
 public GhcrFixtureResponse(int status,string body) {StatusCode=(HttpStatusCode)status;Body=Encoding.UTF8.GetBytes(body);}
 public override Stream GetResponseStream(){return new MemoryStream(Body);}
}
public class GhcrFixtureRequest {
 public string Url,Method,UserAgent; public bool AllowAutoRedirect,UseDefaultCredentials,KeepAlive;
 public object Credentials; public int Timeout,ReadWriteTimeout,AutomaticDecompression;
 public System.Collections.Generic.Dictionary<string,string> Headers=new System.Collections.Generic.Dictionary<string,string>();
 private System.Collections.Generic.Queue<GhcrFixtureResponse> Responses;
 public GhcrFixtureRequest(Uri uri,System.Collections.Generic.Queue<GhcrFixtureResponse> responses){Url=uri.AbsoluteUri;Responses=responses;}
 public GhcrFixtureResponse GetResponse(){var r=Responses.Dequeue();if((int)r.StatusCode>=400)throw new WebException("fixture failure",null,WebExceptionStatus.ProtocolError,r);return r;}
}
'@
& $m {
    $script:requests=New-Object Collections.Generic.List[object]
    $script:responses=New-Object 'Collections.Generic.Queue[GhcrFixtureResponse]'
    function script:New-OnlineHttpRequest($Uri) {
        $r=[GhcrFixtureRequest]::new($Uri,$script:responses)
        $script:requests.Add($r)
        return $r
    }
    function Reset-Fixture { $script:requests.Clear();$script:responses.Clear();$script:GhcrPullToken=$null;$script:GhcrPullTokenExpiresUtc=[DateTime]::MinValue }
    function Response($Status,$Text,$Location='') {
        $r=[GhcrFixtureResponse]::new($Status,$Text)
        if ($Location) { $r.Headers['Location']=$Location }
        $script:responses.Enqueue($r)
    }
    function Require($Ok,$Name) { if(-not $Ok){throw "Failed: $Name"};$script:count++ }
    function Reject([scriptblock]$Body,$Name){$failed=$false;try{& $Body|Out-Null}catch{$failed=$true};Require $failed $Name}
    $script:count=0
    $repo='Yukino-Chan/TGC-Anime-Total-Overhaul-Korean'
    $blob='https://ghcr.io/v2/yukino-chan/tgcnv-patches/blobs/sha256:'+('a'*64)
    [void](Assert-GitHubAssetUrl $blob $repo)
    foreach($url in @($blob+'?x', $blob+'#x', $blob.Replace('sha256:a','sha256:A'),$blob.Replace('tgcnv-patches','else'),$blob.Replace('ghcr.io','ghcr.io:443'))) {
        Reject {Assert-GitHubAssetUrl $url $repo} 'canonical blob boundary'
    }
    Reject {Assert-GitHubAssetUrl $blob 'evil/repo'} 'wrong repository'
    Reject {Assert-GitHubAssetUrl $script:ChannelUrl 'evil/repo'} 'feed repository boundary'
    Reset-Fixture
    Response 200 '{"token":"anonymous-test-token"}'
    Response 307 '' 'https://pkg-containers.githubusercontent.com/test?temporary=1'
    Response 200 'payload'
    $r=Get-BoundedHttpResponse $blob -Repository $repo
    Require ($script:requests.Count -eq 3) 'token and redirect requests'
    Require (-not $script:requests[1].Headers.ContainsKey('Authorization')) 'anonymous token request'
    Require ($script:requests[0].Headers.Authorization -eq 'Bearer anonymous-test-token') 'initial blob auth'
    Require (-not $script:requests[2].Headers.ContainsKey('Authorization')) 'redirect strips authorization'
    $r.Response.Dispose()
    Response 200 'payload2'
    $r=Get-BoundedHttpResponse $blob -Repository $repo;$r.Response.Dispose()
    Require ($script:requests.Count -eq 4) 'token reuse'
    $script:GhcrPullTokenExpiresUtc=[DateTime]::UtcNow.AddSeconds(-1)
    Response 200 '{"access_token":"new-token"}';Response 200 'payload3'
    $r=Get-BoundedHttpResponse $blob -Repository $repo;$r.Response.Dispose()
    Require ($script:requests.Count -eq 6 -and $script:requests[4].Headers.Authorization -eq 'Bearer new-token') 'token expiry refresh'
    Reset-Fixture
    Response 200 '{"token":"first"}';Response 401 '';Response 200 '{"token":"retry"}';Response 200 'payload'
    $r=Get-BoundedHttpResponse $blob -Repository $repo;$r.Response.Dispose()
    Require ($script:requests.Count -eq 4) 'single 401 refresh'
    Reset-Fixture
    Response 200 '{"token":"first"}';Response 401 '';Response 200 '{"token":"retry"}';Response 401 ''
    Reject {Get-BoundedHttpResponse $blob -Repository $repo} 'repeated 401 stops'
    Require ($script:requests.Count -eq 4) '401 retry bounded'
    foreach($bad in @('https://evil.example/x','http://ghcr.io/x','https://ghcr.io/v2/another/blobs/sha256:aaaa')) {
        Reset-Fixture;Response 200 '{"token":"first"}';Response 307 '' $bad
        Reject {Get-BoundedHttpResponse $blob -Repository $repo} 'foreign redirect rejected'
    }
    Reset-Fixture;Response 302 '' 'https://evil.example/token'
    Reject {Get-BoundedHttpResponse $blob -Repository $repo} 'token redirect rejected'
    Reset-Fixture;Response 200 ('x'*65537)
    Reject {Get-BoundedHttpResponse $blob -Repository $repo} 'oversized token response'
    Write-Host "ALL PASSED $script:count GHCR transport checks"
}
