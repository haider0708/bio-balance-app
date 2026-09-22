"""Bounded operator HTTP client. Credentials stay in memory; no redirect/token leakage."""
import base64, hashlib, hmac, json, os, pathlib, struct, time, urllib.request, urllib.error, urllib.parse


def save_json(path, value):
    path = pathlib.Path(path)
    data = (json.dumps(value, ensure_ascii=False, indent=2) + '\n').encode()
    temporary = path.with_suffix(path.suffix + '.tmp')
    fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, 'wb') as stream:
        stream.write(data); stream.flush(); os.fsync(stream.fileno())
    os.replace(temporary, path)
    directory = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
    try: os.fsync(directory)
    finally: os.close(directory)


class ApiError(RuntimeError):
    def __init__(self, status, code):
        super().__init__(f'HTTP {status}: {code}')
        self.status, self.code = status, code


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs): return None


class Client:
    def __init__(self, base_url, credentials, state_dir):
        url = urllib.parse.urlsplit(base_url)
        if (url.scheme != 'https' and not (url.scheme == 'http' and url.hostname in {'127.0.0.1','localhost'})) or url.username or url.query or url.fragment or url.path not in {'','/'}:
            raise ValueError('HTTPS origin required')
        self.base = base_url.rstrip('/'); self.token = None
        self.opener = urllib.request.build_opener(NoRedirect())
        request = {'email':credentials['email'], 'password':credentials['password']}
        if credentials.get('totpUri'):
            params=urllib.parse.parse_qs(urllib.parse.urlsplit(credentials['totpUri']).query)
            step_file=pathlib.Path(state_dir)/'last-login-step'
            previous=int(step_file.read_text()) if step_file.exists() else -1
            delay=(previous+1)*30-time.time()+0.2
            if delay > 31: raise ValueError('Unexpected login clock')
            if delay>0:time.sleep(delay)
            step=int(time.time()//30); key=params['secret'][0]
            digest=hmac.new(base64.b32decode(key+'='*(-len(key)%8)),struct.pack('>Q',step),hashlib.sha1).digest();offset=digest[-1]&15
            request['otp']=str((struct.unpack('>I',digest[offset:offset+4])[0]&0x7fffffff)%1000000).zfill(6)
            save_json(step_file,step)
        self.token=self.call('POST','/v1/identity/login',request,expected=201)['token']

    def call(self, method, route, data=None, expected=200, headers=None, raw=False):
        if not route.startswith('/v1/') and route!='/health':raise ValueError('Invalid API route')
        outgoing={'User-Agent':'BioBalance-Deployment/1.0',**(headers or {})}
        if self.token:outgoing['Authorization']='Bearer '+self.token
        if isinstance(data, dict):
            data=json.dumps(data,ensure_ascii=False,separators=(',',':')).encode();outgoing['Content-Type']='application/json'
        req=urllib.request.Request(self.base+route,data=data,headers=outgoing,method=method)
        try:response=self.opener.open(req,timeout=40)
        except urllib.error.HTTPError as error:response=error
        with response:
            body=response.read(12*1024*1024+1)
            if len(body)>12*1024*1024:raise ValueError('Oversized API response')
            parsed=None
            if 'application/json' in response.headers.get('Content-Type',''):
                parsed=json.loads(body)
            if response.status!=expected:
                raise ApiError(response.status,parsed.get('code','unexpected_response') if isinstance(parsed,dict) else 'unexpected_response')
            return body if raw else parsed

    def close(self):
        if self.token:
            try:self.call('POST','/v1/identity/logout',expected=201)
            finally:self.token=None
