if exists('g:loaded_weibo')
    finish
endif
let g:loaded_weibo = 1

" 新浪分配给vimer.cn的appid，用户不需要变更
let s:sina_weibo_app_key = '2282689712'
let s:sina_weibo_app_secret = '7097d3c42cc0edc648f93807cff289a7'
let s:sina_weibo_app_callback = 'http://app.xefan.com'

let s:sina_weibo_url_get_openid = 'https://api.weibo.com/oauth2/access_token'
let s:sina_weibo_url_add_t = 'https://api.weibo.com/2/statuses/update.json'

python << EOF
import urlparse
import json
import vim
import os
import ConfigParser
import webbrowser
import urllib
import StringIO
import pycurl

WEIBO_CONFIG = "%s/%s" % (os.getenv('HOME'), '.vim_weibo')
if not os.path.exists(WEIBO_CONFIG):
    open(WEIBO_CONFIG, 'wb').close()

def https_send(url, params, method='GET'):
    crl = pycurl.Curl()
    crl.setopt(pycurl.NOSIGNAL, 1)
    # set ssl
    crl.setopt(pycurl.SSL_VERIFYPEER, 0)
    crl.setopt(pycurl.SSL_VERIFYHOST, 0)
    crl.setopt(pycurl.SSLVERSION, 3)
     
    crl.setopt(pycurl.CONNECTTIMEOUT, 10)
    crl.setopt(pycurl.TIMEOUT, 300)
    crl.setopt(pycurl.HTTPPROXYTUNNEL,1)

    crl.fp = StringIO.StringIO()
     
    if isinstance(url, unicode):
        url = str(url)
    crl.setopt(pycurl.URL, url)
    if method == 'POST':
        crl.setopt(crl.POSTFIELDS, urllib.urlencode(params))
    crl.setopt(crl.WRITEFUNCTION, crl.fp.write)
    try:
        crl.perform()
    except Exception, e:
        print "网络错误", e
        return None
    crl.close()
    try:
        conn = crl.fp.getvalue()
        back = json.loads(conn)
        crl.fp.close()
        return back
    except Exception, e:
        return None

class Weibo():
    def __init__(self):
        self.config = ConfigParser.ConfigParser()
        self.config.read(WEIBO_CONFIG)
        self.access_token = self.read_config()

    def get_access_token(self):
        code = self.get_api_code()
        if not code:
            print "获取code错误！"
            return
        try:
            self.access_token = self.api_get_openid(code)
            self.write_config(self.access_token)
            # print "获取access_token:", self.access_token
        except Exception, e:
            print 'exception occur.msg[%s], traceback[%s]' % (str(e), __import__('traceback').format_exc())
            print '网络有问题'

    def read_config(self):
        if not self.config.has_section("weibo"):
            return None
        if self.config.has_option('weibo', 'access_token'):
            return self.config.get('weibo', 'access_token')
        else:
            return None

    def write_config(self, access_token):
        if not self.config.has_section('weibo'):
            self.config.add_section('weibo')
        self.config.set('weibo', 'access_token', access_token)
        self.config.write(open(WEIBO_CONFIG, 'wb'))

    def get_api_code(self):
        sina_weibo_url_auth = 'https://api.weibo.com/oauth2/authorize?client_id=%s&redirect_uri=%s&response_type=code' % (
            vim.eval('s:sina_weibo_app_key'), vim.eval('s:sina_weibo_app_callback'))
        if not webbrowser.open(sina_weibo_url_auth):
            print "打开网页失败！"
            return None
        vim.command("let s:weibo_code = input('请输入返回的网址或者code值：', '')")
        code = vim.eval('s:weibo_code')
        if not code.startswith('http'):
            return code
        u = urlparse.urlparse(code)
        query = urlparse.parse_qs(u.query, True)
        if 'code' in query and query['code']:
            return query['code'][0]
        else:
            return None
    
    def api_get_openid(self, code):
        client_id = vim.eval('s:sina_weibo_app_key')
        client_secret = vim.eval('s:sina_weibo_app_secret')
        grant_type = 'authorization_code'
        redirect_uri = vim.eval('s:sina_weibo_app_callback')
        url_base = vim.eval('s:sina_weibo_url_get_openid')
        url_parts = '%s?client_id=%s&client_secret=%s&grant_type=authorization_code&code=%s&redirect_uri=%s' % (
            url_base, client_id, client_secret, code, redirect_uri)
        jdata = https_send(url_parts, [], 'POST')
        if jdata and 'access_token' in jdata:
            return jdata['access_token']
        else:
            return ""

    def api_add_t(self, content):
        if not self.access_token:
            print 'access_token无效或者过期'
            return
        params = {
            'access_token': self.access_token,
            'status': content,
        }
        url_parts = vim.eval('s:sina_weibo_url_add_t')
        return https_send(url_parts, params, 'POST')

    def handle_add_t(self, content):
        try:
            jdata = self.api_add_t(content)
        except Exception, e:
            print 'exception occur.msg[%s], traceback[%s]' % (str(e), __import__('traceback').format_exc())
            print '发表失败! 可能原因为: 网络有问题'
            return

        if jdata and "error_code" in jdata:
            print '发表失败! ret:%d, error:%s' % (jdata['error_code'], str(jdata['error']))
        else:
            print '发表成功!'

weibo = Weibo()
EOF

function! s:AddT(content)
python<<EOF
if not weibo.access_token:
    weibo.get_access_token()
all_content = vim.eval('a:content')
weibo.handle_add_t(all_content)
EOF
endfunction

function! WeiboRefresh()
python<<EOF
weibo.get_access_token()
EOF
endfunction

command! -nargs=1 -range AddT :call s:AddT(<f-args>)
command! -nargs=0 WeiboRefresh call WeiboRefresh()

vnoremap ,at "ty:AddT <C-R>t<CR>
nnoremap ,at :AddT
