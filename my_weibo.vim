"=============================================================================
"
"     FileName: my_weibo.vim
"         Desc: 实现通过Vim发送新浪微博
"               在选择模式下按",at".
"               可以从这里获取到最新的版本:
"               https://github.com/wusuopu/weibo-vim-plugin
"
"               注意：运行该程序需要先安装pycurl，python-webkit，pygtk软件包。
"
"       Author: LongChangjin
"        Email: admin@longchangjin.cn
"
"      Created: 2012-11-30
"  Last Modify: 2012-12-02
"
"=============================================================================
if exists('g:loaded_my_weibo')
    finish
endif
let g:loaded_my_weibo = 1
python << EOF
#-*- coding:utf-8 -*-
import ConfigParser
import urlparse
import vim
import webbrowser
import StringIO
import json
from os import getenv
from os.path import exists
from urllib import urlencode

import pycurl
import webkit
import gobject

APP_KEY = '2282689712'
APP_SECRET = '7097d3c42cc0edc648f93807cff289a7'
APP_CALLBACK = 'http://app.xefan.com'

URL_AUTHORIZE = 'https://api.weibo.com/oauth2/authorize'
URL_GET_OPENID = 'https://api.weibo.com/oauth2/access_token'
URL_ADD_T = 'https://api.weibo.com/2/statuses/update.json'

def https_send(url, params=[], method='GET'):
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
        crl.setopt(crl.POSTFIELDS, urlencode(params))
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

class Config(object):
    def __init__(self):
        super(Config, self).__init__()
        self.config = ConfigParser.ConfigParser()
        self.config_file = "%s/%s" % (getenv('HOME'), '.vim_weibo')
        if not exists(self.config_file):
            open(self.config_file, 'wb').close()
        self.config.read(self.config_file)

        self.access_token = None
        self.username = None
        self.password = None
        self.get_all()
        
    def get_all(self):
        if not self.config.has_section("weibo"):
            self.access_token = None
            self.username = None
            self.password = None
        if self.config.has_option('weibo', 'access_token'):
            self.access_token = self.config.get('weibo', 'access_token')
        else:
            self.access_token = None
        if self.config.has_option('weibo', 's2'):
            self.username = self.config.get('weibo', 's2')
        else:
            self.username = None
        if self.config.has_option('weibo', 's1'):
            self.password = self.config.get('weibo', 's1')
        else:
            self.password = None
        
    def set_all(self):
        if not self.config.has_section('weibo'):
            self.config.add_section('weibo')
        if self.access_token:
            self.config.set('weibo', 'access_token', self.access_token)
        if self.username:
            self.config.set('weibo', 's2', self.username)
        if self.password:
            self.config.set('weibo', 's1', self.password)
        self.config.write(open(self.config_file, 'wb'))
        
    def clear(self):
        if not self.config.has_section('weibo'):
            self.config.add_section('weibo')
        self.config.set('weibo', 'access_token', '')
        self.config.set('weibo', 's2', '')
        self.config.set('weibo', 's1', '')
        self.config.write(open(self.config_file, 'wb'))
        
class Login(object):
    TIMEOUT_ERROR = 0
    LOGIN_ERROR = 1
    AUTHOR_ERROR = 2
    WEBBROWER_ERROR = 3
    UNKNOWN_ERROR = -1
    CALLBACK = 'app.xefan.com'

    def __init__(self, config):
        super(Login, self).__init__()
        self.LOGIN_CLICK = False
        self.AUTH_CLICK = False
        self.config = config
        self.code = None
        self.error_code = None
        
    def user_login(self):
        if not self.config.username or not self.config.password:
            self.login_in_webbrowser()
        else:
            self.login_with_webkit()
    
    def login_in_webbrowser(self):
        sina_weibo_url_auth = "%s?client_id=%s&redirect_uri=%s&response_type=code&forcelogin=true" % (
            URL_AUTHORIZE, APP_KEY, APP_CALLBACK)
        if not webbrowser.open(sina_weibo_url_auth):
            self.code = None
            self.error_code = self.WEBBROWER_ERROR
            return
        vim.command("let s:weibo_code = input('请输入授权后返回的网址或者code的值：', '')")
        code = vim.eval('s:weibo_code')
        if not code.startswith('http'):
            self.code = code
            return
        u = urlparse.urlparse(code)
        query = urlparse.parse_qs(u.query, True)
        if 'code' in query and query['code']:
            self.code = query['code'][0]
        else:
            self.code = None
            self.error_code = self.UNKNOWN_ERROR
    
    def login_with_webkit(self):
        view = webkit.WebView()
        view.open("%s?client_id=%s&redirect_uri=%s&response_type=code&forcelogin=true" % (
            URL_AUTHORIZE, APP_KEY, APP_CALLBACK))
        view.connect("notify::load-status", self.web_view_load_status)
        
        self.loop = gobject.MainLoop()
        gobject.timeout_add_seconds(60, self.webkit_timeout)
        self.loop.run()

    def web_view_load_status(self, web, status):
        '''web_view notify load-status callback'''
        state = web.get_property("load-status")
        url = web.get_property('uri')
        if state == webkit.LOAD_FINISHED:
            #print "load finished:", url
            if not url:
                return
            u = urlparse.urlparse(url)
            # 登陆
            if u.netloc == 'api.weibo.com' and u.path.startswith('/oauth2/authorize')\
                    and (u.params or u.query or u.fragment) and not self.LOGIN_CLICK:
                #print "execute_script: login"
                web.execute_script('var userId = document.getElementById("userId");')
                web.execute_script('userId.value = "%s"' % self.config.username)
                web.execute_script('var passwd = document.getElementById("passwd");')
                web.execute_script('passwd.value = "%s"' % self.config.password)
                web.execute_script('var btn = document.getElementsByClassName("WB_btn_login formbtn_01")[0];')
                web.execute_script('var e = document.createEvent("Event");')
                web.execute_script('e.initEvent("click", true, true);')
                web.execute_script('btn.dispatchEvent(e);')
                self.LOGIN_CLICK = True
                gobject.timeout_add_seconds(22, self.login_error)
            # 授权
            if u.netloc == 'api.weibo.com' and u.path.startswith('/oauth2/authorize')\
                    and u.params == '' and u.query == '' and u.fragment == '' and not self.AUTH_CLICK:
                #print "execute_script: authorize"
                web.execute_script('var btn = document.getElementsByClassName("WB_btn_oauth formbtn_01")[0];')
                web.execute_script('var e = document.createEvent("Event");')
                web.execute_script('e.initEvent("click", true, true);')
                web.execute_script('btn.dispatchEvent(e);')
                self.AUTH_CLICK = True
        elif state == webkit.LOAD_COMMITTED:
            u = urlparse.urlparse(url)
            if u.netloc == self.CALLBACK:
                web.stop_loading()
                #print "OK!", url
                query = urlparse.parse_qs(u.query)
                if 'code' in query:
                    self.code = query['code'][0]
                    #print "authorize succeed", query['code'][0]
                else:
                    self.error_code = self.AUTHOR_ERROR
                self.loop.quit()
        
    def login_error(self):
        if self.LOGIN_CLICK and not self.AUTH_CLICK:
            self.error_code = self.LOGIN_ERROR
            self.loop.quit()
        return False
        
    def webkit_timeout(self):
        if not self.AUTH_CLICK or not self.code:
            if not self.error_code:
                self.error_code = self.TIMEOUT_ERROR
            self.loop.quit()
        return False

class Author(object):
    def __init__(self, config, code=None):
        super(Author, self).__init__()
        self.config = config
        self.code = code
        self.error_code = None
        self.error = None
        
    def get_access_token(self):
        if not self.code:
            return False
        url_parts = '%s?client_id=%s&client_secret=%s&grant_type=authorization_code&code=%s&redirect_uri=%s' % (
            URL_GET_OPENID, APP_KEY, APP_SECRET, self.code, APP_CALLBACK)
        jdata = https_send(url_parts, [], 'POST')
        if jdata:
            print jdata
            if 'access_token' in jdata:
                self.config.access_token = str(jdata['access_token'])
                self.config.set_all()
                return True
            if 'error_code' in jdata:
                self.error_code = str(jdata['error_code'])
                self.error = jdata['error']
        return False

class Weibo(object):
    def __init__(self):
        super(Weibo, self).__init__()
        self.config = Config()
        self.login = Login(self.config)
        
    def clear(self):
        self.config.clear()
        
    def set_username(self, name):
        self.config.username = name
        self.config.set_all()
    
    def set_password(self, pswd):
        self.config.password = pswd
        self.config.set_all()
    
    def get_author(self):
        self.login.code = None
        self.login.user_login()
        if not self.login.code:
            if self.login.error_code == self.login.TIMEOUT_ERROR:
                print "用户认证错误： 连接超时"
            elif self.login.error_code == self.login.LOGIN_ERROR:
                print "用户认证错误： 用户名或密码错误"
            elif self.login.error_code == self.login.AUTHOR_ERROR:
                print "用户认证错误： 授权错误"
            elif self.login.error_code == self.login.WEBBROWER_ERROR:
                print "用户认证错误： 打开浏览器出错"
            elif self.login.error_code == self.login.UNKNOWN_ERROR:
                print "用户认证错误： 未知错误"
            return False
        return Author(self.config, self.login.code).get_access_token()
        
    def update(self, content):
        if not self.config.access_token:
            print 'access_token无效，尝试重新获取'
            if not self.get_author():
                print "重新获取access_token失败。发表失败! "
                return
        params = {
            'access_token': self.config.access_token,
            'status': content,
        }
        back = https_send(URL_ADD_T , params, 'POST')
        if back:
            if 'error_code' in back:
                print '发表失败! ret:%d, error:%s' % (back['error_code'], str(back['error']))
                if str(back['error_code']) == '21315 ' or str(back['error_code']) == '21327':
                        print 'access_token已过期，尝试重新获取'
                        if self.get_author():
                            print "重新获取access_token成功。请重新发表内容! "
            else:
                print '\n=============发表成功!====================='
        else:
            print '发表失败! 可能原因为: 网络有问题'

weibo = Weibo()
EOF
function! s:WeiboAdd(content)
python<<EOF
all_content = vim.eval('a:content')
weibo.update(all_content)
EOF
endfunction

function! WeiboRefresh()
python<<EOF
weibo.get_author()
EOF
endfunction

function! WeiboClear()
python<<EOF
weibo.clear()
EOF
endfunction

function! s:WeiboSetUsername(name)
python<<EOF
weibo.set_username(vim.eval('a:name'))
EOF
endfunction

function! s:WeiboSetPassword(pswd)
python<<EOF
weibo.set_password(vim.eval('a:pswd'))
EOF
endfunction

command! -nargs=1 -range WeiboAdd :call s:WeiboAdd(<f-args>)
command! -nargs=1 -range WeiboSetUsername :call s:WeiboSetUsername(<f-args>)
command! -nargs=1 -range WeiboSetPassword :call s:WeiboSetPassword(<f-args>)
command! -nargs=0 WeiboRefresh call WeiboRefresh()
command! -nargs=0 WeiboClear call WeiboClear()

vnoremap ,at "ty:WeiboAdd <C-R>t<CR>
nnoremap ,at :WeiboAdd
