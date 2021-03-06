" based on an idea that bniemczyk@gmail.com had
" thanks to ccliver@gmail.org for his input
" thanks to Tim Pope <vimNOSPAM@tpope.info> for pointing out preview windows
"
" requires vim to be compiled w/ python support. I noticed that most of my
" python development consisted of copying code into the python interpreter
" FIXME: i deleted this line during some time
" required by copy&paste, I decided to make vim more friendly for that style
" of development. this is the result. I apologize for the hackiness.
"
" when a .py file is opened (determined by filetype), a buffer is created
"
" python-output
" this contains the output of all the code you've executed.
" by default this is shown in a splitscreened window
"
" Usage:
" Move the cursor to a line or hilight some text (visual mode)
" and hit '!' to execute in the python interpreter. it's output will
" be displayed in 'python-output'
"
" ! -- execute current selected row
" Ctrl+@ -- display repr for symbol under character
" Ctrl+_ -- display help for symbol under character
"
" Installation:
" If in posix, copy to ~/.vim/plugin/
" If in windows, copy to $USERPROFILE/vimfiles/plugin/
"
" basic knowledge of window management is required to use effectively. here's
" a quickref:
"
"   <C-w>s -- horizontal split
"   <C-w>v -- vertical split
"   <C-w>o -- hide all other windows
"   <C-w>q -- close current window
"   <C-w>{h,l,j,k} -- move to the window left,right,down,up from current one
"
" Configuration (via globals):
" string g:incpy#Program        -- name of subprogram (if empty, use vim's internal python)
" int    g:incpy#ProgramEcho    -- whether the program should echo all input
" int    g:incpy#ProgramFollow  -- go to the end of output when input is sent
" int    g:incpy#ProgramStrip   -- whether to strip leading indent
"
" string g:incpy#WindowName     -- the name of the output buffer that gets created.
" int    g:incpy#WindowFixed    -- don't allow automatic resizing of the window
" dict   g:incpy#WindowOptions  -- new window options
" int    g:incpy#WindowPreview  -- use preview windows
" string g:incpy#WindowPosition -- window position.  ['above', 'below', 'left', 'right']
" float  g:incpy#WindowRatio    -- window size on creation
"
" Todo:
"       the auto-popup of the buffer based on the filetype was pretty cool
"       if some of the Program output is parsed, it might be possible to
"           create a fold labelled by the first rw python code that
"           exec'd it
"       maybe exeecution of the contents of a register would be useful
"       verify everything is cool in the linux-world

if has("python")

" vim string manipulation for indents and things
function! s:count_indent(string)
    " count the beginning whitespace of a string
    let characters = 0
    for c in split(a:string,'\zs')
        if stridx(" \t",c) == -1
            break
        endif
        let characters += 1
    endfor
    return characters
endfunction

function! s:find_common_indent(lines)
    " find the smallest indent
    let smallestindent = -1
    for l in a:lines
        " skip lines that are all whitespace
        if strlen(l) == 0 || l =~ '^\s\+$'
            continue
        endif

        let spaces = s:count_indent(l)
        if smallestindent < 0 || spaces < smallestindent
            let smallestindent = spaces
        endif
    endfor
    return smallestindent
endfunction

function! s:strip_indentation(lines)
    let indentsize = s:find_common_indent(a:lines)

    " remove the indent
    let results = []
    let prevlength = 0
    for l in a:lines
        if strlen(l) == 0
            let row = repeat(" ",prevlength)
        else
            let row = strpart(l,indentsize)
            let prevlength = s:count_indent(row)
        endif
        let results += [row]
    endfor
    return results
endfunction

function! s:selected() range
    " really, vim? really??
    let oldvalue = getreg("")
    normal gvy
    let result = getreg("")
    call setreg("", oldvalue)
    return result
endfunction

"" private window management
function! s:windowselect(id)
    " select the requested windowid, return the previous window id
    let current = winnr()
    execute printf("%d wincmd w", a:id)
    return current
endfunction

function! s:windowtail(bufid)
    " tail the window with the requested bufid
    let last = s:windowselect(bufwinnr(a:bufid))
    if winnr() == bufwinnr(a:bufid)
        noautocmd normal gg
        noautocmd normal G
        call s:windowselect(last)

    " check which tabs the buffer is in
    else
        call s:windowselect(last)

        let tc = tabpagenr()
        for tn in range(tabpagenr('$'))
            if index(tabpagebuflist(tn+1), a:bufid) > -1
                execute printf("tabnext %d", tn)
                let tl = s:windowselect(bufwinnr(a:bufid))
                noautocmd normal gg
                noautocmd normal G
                call s:windowselect(tl)
            endif
        endfor
        execute printf("tabnext %d", tc)
    endif
endfunction

function! incpy#Start()
    python __incpy__.cache.start()
endfunction

function! incpy#Stop()
    python __incpy__.cache.stop()
endfunction

function! incpy#Restart()
    python __incpy__.cache.stop()
    python __incpy__.cache.start()
endfunction

" incpy methods
function! incpy#SetupPython(currentscriptpath)
    let m = substitute(a:currentscriptpath, "\\", "/", "g")

    " FIXME: use sys.meta_path

    " add the python path using the runtimepath directory that this script is contained in
    for p in split(&runtimepath,",")
        let p = substitute(p, "\\", "/", "g")
        if stridx(m, p, 0) == 0
            execute printf("python __import__('sys').path.append('%s/python')", p)
            return
        endif
    endfor

    " otherwise, look up from our current script's directory for a python sub-directory
    let p = finddir("python", m . ";")
    if isdirectory(p)
        execute printf("python __import__('sys').path.append('%s')", p)
        return
    endif

    throw printf("Unable to determine basepath from script %s", m)
endfunction

""" external interfaces
function! incpy#Execute(line)
    let module = escape("__import__('__builtin__')", "'\\")
    execute printf("python __incpy__.cache.communicate('%s')", escape(a:line, "'\\"))
    if g:incpy#ProgramFollow
        call s:windowtail(g:incpy#BufferId)
    endif
endfunction
function! incpy#Range(begin,end)
    let lines = getline(a:begin,a:end)
    if g:incpy#ProgramStrip
        let lines = s:strip_indentation(lines)

        " if last line starts with whitespace (indented), append a newline
        if len(lines) > 0 && lines[-1] =~ '^\s\+'
            let lines += [""]
        endif
    endif

    let code_s = join(map(lines, 'escape(v:val, "''\\")'), "\\n")
    execute printf("python __incpy__.cache.communicate('%s')", code_s)
    if g:incpy#ProgramFollow
        call s:windowtail(g:incpy#BufferId)
    endif
endfunction
function! incpy#Evaluate(expr)
    "execute printf("python __incpy__.cache.communicate('_=%s;print _')", escape(a:expr, "'\\"))
    "execute printf("python __incpy__.cache.communicate('sys.displayhook(%s)')", escape(a:expr, "'\\"))
    "execute printf("python __incpy__.cache.communicate('__builtin__._=%s;print __builtin__._')", escape(a:expr, "'\\"))
    let module = escape("__import__('__builtin__')", "'\\")
    execute printf("python __incpy__.cache.communicate('%s._=%s;print %s.repr(%s._)')", module, escape(a:expr, "'\\"), module, module)
    if g:incpy#ProgramFollow
        call s:windowtail(g:incpy#BufferId)
    endif
endfunction
function! incpy#Halp(expr)
    let LetMeSeeYouStripped = substitute(a:expr, '^[ \t\n]\+\|[ \t\n]\+$', '', 'g')
    let module = escape("__import__('__builtin__')", "'\\")
    execute printf("python try:__incpy__.cache.communicate('%s.help(%s)')\nexcept SyntaxError:__incpy__.cache.communicate('%s.help(\\'%s\\')')", module, escape(LetMeSeeYouStripped, "'\\"), module, escape(LetMeSeeYouStripped, "'\\"))
endfunction

" Create vim commands
function! incpy#MapCommands()
    command PyLine call incpy#Range(line("."),line("."))
    command PyBuffer call incpy#Range(0,line('$'))

    command -nargs=1 Py call incpy#Execute(<q-args>)
    command -range PyRange call incpy#Range(<line1>,<line2>)

    " python-specific commands
    command -nargs=1 PyEval call incpy#Evaluate(<q-args>)
    command -range PyEvalRange <line1>,<line2>call incpy#Evaluate(s:selected())
    command -nargs=1 PyHelp call incpy#Halp(<q-args>)
    command -range PyHelpRange <line1>,<line2>call incpy#Halp(s:selected())
endfunction

" Setup key mappings
function! incpy#MapKeys()
    nmap ! :PyLine<C-M>
    vmap ! :PyRange<C-M>

    " python-specific mappings
    nmap <C-@> :call incpy#Evaluate(expand("<cword>"))<C-M>
    vmap <C-@> :PyEvalRange<C-M>
    nmap  :call incpy#Halp(expand("<cword>"))<C-M>
    vmap <C-_> :PyHelpRange<C-M>
endfunction

" Setup default options
function! incpy#SetupOptions()
    let defopts = {}
    let defopts["Program"] = ""
    let defopts["ProgramEcho"] = 1
    let defopts["ProgramFollow"] = 1
    let defopts["ProgramStrip"] = 1
    let defopts["WindowName"] = "Scratch"
    let defopts["WindowRatio"] = 1.0/3
    let defopts["WindowPosition"] = "below"
    let defopts["WindowOptions"] = {"buftype":"nowrite", "noswapfile":[], "updatecount":0, "nobuflisted":[], "filetype":"python"}
    let defopts["WindowPreview"] = 0
    let defopts["WindowFixed"] = 0

    for o in keys(defopts)
        if ! exists("g:incpy#{o}")
            let g:incpy#{o} = defopts[o]
        endif
    endfor
endfunction

" Setup python interface
function! incpy#Setup()
    " Setup python interface

    python <<EOF

# create a pseudo-builtin module
__incpy__ = type(__builtins__)('__incpy__', 'Internal state module for vim-incpy')
__incpy__.sys,__incpy__.incpy = __import__('sys'),__import__('incpy')
__incpy__.vim,__incpy__.buffer,__incpy__.spawn = __incpy__.incpy.vim,__incpy__.incpy.buffer,__incpy__.incpy.spawn

# save initial state
__incpy__.state = tuple((getattr(__incpy__.sys,_) for _ in ('stdin','stdout','stderr')))
def log(data):
    _,out,_ = __incpy__.state
    out.write('incpy.vim : {:s}\n'.format(data))
__incpy__.log = log; del(log)

# interpreter classes
class interpreter(object):
    # options that are used for constructing the view
    view_options = ('buffer','opt','preview','tab')

    @classmethod
    def new(cls, **options):
        options.setdefault('buffer', None)
        return cls(**options)
    def __init__(self, **kwds):
        opt = dict(__incpy__.vim.gvars['incpy#WindowOptions'])
        opt.update(kwds.pop('opt',{}))
        kwds.setdefault('preview', __incpy__.vim.gvars['incpy#WindowPreview'])
        kwds.setdefault('tab', __incpy__.internal.tab.getCurrent())
        self.view = __incpy__.view(kwds.pop('buffer',None) or __incpy__.vim.gvars['incpy#WindowName'], opt, **kwds)
    def __del__(self):
        return self.detach()
    def write(self, data):
        """Writes data directly into view"""
        return self.view.write(data)
    def __repr__(self):
        if self.view.window > -1:
            return '<__incpy__.%s buffer:%d>'% (self.__class__.__name__, self.view.buffer.number)
        return '<__incpy__.%s buffer:%d hidden>'% (self.__class__.__name__, self.view.buffer.number)

    def attach(self):
        """Attaches interpreter to view"""
        raise NotImplementedError
    def detach(self):
        """Detaches interpreter from view"""
        raise NotImplementedError
    def communicate(self, command, silent=False):
        """Sends commands to interpreter"""
        raise NotImplementedError
    def start():
        """Starts the interpreter"""
        raise NotImplementedError
    def stop():
        """Stops the interpreter"""
        raise NotImplementedError
__incpy__.interpreter = interpreter; del(interpreter)

class interpreter_python_internal(__incpy__.interpreter):
    state = None
    def attach(self):
        sys = __incpy__.sys
        self.state = sys.stdin,sys.stdout,sys.stderr
        __incpy__.log('redirecting sys.{stdin,stdout,stderr} to %r'% self.view)
        _,sys.stdout,sys.stderr = None,self.view,self.view
    def detach(self):
        if self.state is None: return
        sys = __incpy__.sys
        __incpy__.log('restoring sys.{stdin,stdout,stderr} to %r'% (self.state,))
        sys.stdin,sys.stdout,sys.stderr = self.state
    def communicate(self, data, silent=False):
        if __incpy__.vim.gvars['incpy#ProgramEcho'] and not silent:
            self.view.write('\n'.join('## %s'% x for x in data.split('\n')) + '\n')
        exec data in globals()
    def start():
        __incpy__.log('python interpreter already started by host vim process')
    def stop():
        __incpy__.log('not allowed to stop internal python interpreter')
__incpy__.interpreter_python_internal = interpreter_python_internal; del(interpreter_python_internal)

# external interpreter (newline delimited)
class interpreter_external(__incpy__.interpreter):
    instance = None
    @classmethod
    def new(cls, command, **options):
        res = cls(**options)
        map(lambda n,d=options:d.pop(n,None), cls.view_options)
        res.command,res.options = command,options
        return res
    def attach(self):
        __incpy__.log("connecting i/o from %r to %r"% (self.command, self.view))
        self.instance = __incpy__.spawn(self.view.write, self.command, **self.options)
        __incpy__.log("started process -- %d (%x) -- %s"% (self.instance.id,self.instance.id,self.command))
    def detach(self):
        if not self.instance: return
        if not self.instance.running:
            __incpy__.log("refusing to stop already terminated process %r"% self.instance)
            return
        __incpy__.log("killing process %r"% self.instance)
        self.instance.stop()
        __incpy__.log('disconnecting i/o for %r from %r'% (self.instance,self.view))
        self.instance = None

    def communicate(self, data, silent=False):
        if __incpy__.vim.gvars['incpy#ProgramEcho'] and not silent:
            self.view.write(data + '\n')
        self.instance.write(data + "\n")
    def __repr__(self):
        res = super(__incpy__.interpreter_external, self).__repr__()
        if self.instance.running:
            return '{:s} {{{!r} {:s}}}'.format(res, self.instance, self.command)
        return '{:s} {{{!s}}}'.format(res, self.instance)
    def start():
        __incpy__.log("starting process %r"% self.instance)
        self.instance.start()
    def stop():
        __incpy__.log("stopping process %r"% self.instance)
        self.instance.stop()
__incpy__.interpreter_external = interpreter_external; del(interpreter_external)

# vim internal
class internal(object):
    """Commands that interface with vim directly"""
    class tab(object):
        """Internal vim commands for interacting with tabs"""
        goto = staticmethod(lambda n: __incpy__.vim.command('tabnext %d'% (n+1)))
        close = staticmethod(lambda n: __incpy__.vim.command('tabclose %d'% (n+1)))
        #def move(n, t):    # FIXME
        #    current = int(__incpy__.vim.eval('tabpagenr()'))
        #    _ = t if current == n else current if t > current else current+1
        #    __incpy__.vim.command('tabnext %d | tabmove %d | tabnext %d'% (n+1,t,_))

        getCurrent = staticmethod(lambda: int(__incpy__.vim.eval('tabpagenr()')) - 1)
        getCount = staticmethod(lambda: int(__incpy__.vim.eval('tabpagenr("$")')))
        getBuffers = staticmethod(lambda n: map(int,__incpy__.vim.eval('tabpagebuflist(%d)'% (n-1))))

        getWindowCurrent = staticmethod(lambda n: int(__incpy__.vim.eval('tabpagewinnr(%d)'% (n-1))))
        getWindowPrevious = staticmethod(lambda n: int(__incpy__.vim.eval('tabpagewinnr(%d, "#")'% (n-1))))
        getWindowCount = staticmethod(lambda n: int(__incpy__.vim.eval('tabpagewinnr(%d, "$")'% (n-1))))

    class buffer(object):
        """Internal vim commands for getting information about a buffer"""
        name = staticmethod(lambda id: str(__incpy__.vim.eval('bufname(%d)'% id)))
        number = staticmethod(lambda id: int(__incpy__.vim.eval('bufnr(%d)'% id)))
        window = staticmethod(lambda id: int(__incpy__.vim.eval('bufwinnr(%d)'% id)))

    class window(object):
        """Internal vim commands for doing things with a window"""

        # ui position conversion
        @staticmethod
        def positionToLocation(position):
            if position in ('left','above'):
                return 'leftabove'
            if position in ('right','below'):
                return 'rightbelow'
            raise ValueError, position
        @staticmethod
        def positionToSplit(position):
            if position in ('left','right'):
                return 'vsplit'
            if position in ('above','below'):
                return 'split'
            raise ValueError, position
        @staticmethod
        def optionsToCommandLine(options):
            result = []
            for k,v in options.iteritems():
                if type(v) in (int,long):
                    result.append('%s=%d'%(k,v))
                elif type(v) is str:
                    result.append('%s=%s'%(k,v))
                else:
                    result.append(k)
                continue
            return '\\ '.join(result)

        # window selection
        @staticmethod
        def current():
            '''return the current window'''
            return int(__incpy__.vim.eval('winnr()'))
        @staticmethod
        def select(window):
            '''Select the window with the specified id'''
            return (int(__incpy__.vim.eval('winnr()')),__incpy__.vim.command('%d wincmd w'% window))[0]
        @staticmethod
        def currentsize(position):
            if position in ('left','right'):
                return int(__incpy__.vim.eval('winwidth(0)'))
            if position in ('above','below'):
                return int(__incpy__.vim.eval('winheight(0)'))
            raise ValueError, position

        # properties
        @staticmethod
        def buffer(bufferid):
            '''Return the window according to the bufferid'''
            return int(__incpy__.vim.eval('winbufnr(%d)'% bufferid))

        # window actions
        @classmethod
        def create(cls, bufferid, position, size, options, preview=False):
            last = cls.current()
            if preview:
                if len(options) > 0:
                    __incpy__.vim.command("noautocmd silent %s pedit! +setlocal\\ %s %s"% (cls.positionToLocation(position), cls.optionsToCommandLine(options), __incpy__.internal.buffer.name(bufferid)))
                else:
                    __incpy__.vim.command("noautocmd silent %s pedit! %s"% (cls.positionToLocation(position), __incpy__.internal.buffer.name(bufferid)))
            else:
                if len(options) > 0:
                    __incpy__.vim.command("noautocmd silent %s %d%s! +setlocal\\ %s %s"% (cls.positionToLocation(position), size, cls.positionToSplit(position), cls.optionsToCommandLine(options), __incpy__.internal.buffer.name(bufferid)))
                else:
                    __incpy__.vim.command("noautocmd silent %s %d%s! %s"% (cls.positionToLocation(position), size, cls.positionToSplit(position), __incpy__.internal.buffer.name(bufferid)))

            res = cls.current()
            cls.select(last)
            if not bool(__incpy__.vim.gvars['incpy#WindowPreview']):
                wid = cls.buffer(bufferid)
                assert res == wid,'Newly created window is not pointing to buffer id : {!r} != {!r}'.format(wid, res)
            return res

        @classmethod
        def show(cls, bufferid, position, preview=False):
            last = cls.select( cls.buffer(bufferid) )
            if preview:
                __incpy__.vim.command("noautocmd silent %s pedit! %s"% (cls.positionToLocation(position), __incpy__.internal.buffer.name(bufferid)))
            else:
                __incpy__.vim.command("noautocmd silent %s %s! %s"% (cls.positionToLocation(position), cls.positionToSplit(position), __incpy__.internal.buffer.name(bufferid)))

            res = cls.current()
            cls.select(last)
            assert res == cls.buffer(bufferid)
            return res
        @classmethod
        def hide(cls, bufferid, preview=False):
            last = cls.select( cls.buffer(bufferid) )
            if preview:
                __incpy__.vim.command("noautocmd silent pclose!")
            else:
                __incpy__.vim.command("noautocmd silent close!")
            self.window = cls.buffer(bufferid)
            cls.select(last)

        # window state
        @classmethod
        def saveview(cls, bufferid):
            last = cls.select( cls.buffer(bufferid) )
            res = __incpy__.vim.eval('winsaveview()')
            cls.select(last)
            return res
        @classmethod
        def restview(cls, bufferid, state):
            do = __incpy__.vim.Function('winrestview')
            last = cls.select( cls.buffer(bufferid) )
            do(state)
            cls.select(last)
        @classmethod
        def savesize(cls, bufferid):
            last = cls.select( cls.buffer(bufferid) )
            w,h = map(__incpy__.vim.eval, ('winwidth(0)','winheight(0)'))
            cls.select(last)
            return { 'width':w, 'height':h }
        @classmethod
        def restsize(cls, bufferid, state):
            window = cls.buffer(bufferid)
            return 'vertical %d resize %d | %d resize %d'% (window, state['width'], window, state['height'])

__incpy__.internal = internal; del(internal)

# view -- window <-> buffer
class view(object):
    """This represents the window associated with a buffer."""

    def __init__(self, buffer, opt, preview, tab=None):
        """Create a view for the specified buffer.

        Buffer can be an existing id number, filename, or new name.
        """
        self.buffer = self.__get_buffer(buffer)
        self.options = opt
        self.preview = preview
        self.window = __incpy__.internal.window.buffer( self.buffer.number )
        # FIXME: creating a view in another tab is not supported yet

    def __get_buffer(self, target):
        if type(target) is int:
            return __incpy__.buffer.from_id(target)
        elif type(target) is str:
            try: return __incpy__.buffer.from_name(target)
            except: return __incpy__.buffer.new(target)
        raise __incpy__.incpy.error, "Unable to determine output buffer from parameter : %r"% target

    def write(self, data):
        """Write data directly into window contents (updating buffer)"""
        return self.buffer.write(data)

    def create(self, position, ratio):
        """Create window for buffer"""
        buf = self.buffer
        if __incpy__.internal.buffer.number(buf.number) == -1:
            raise Exception, "Buffer %d does not exist"% buf.number
        if 1.0 <= ratio < 0.0:
            raise Exception, "Specified ratio is out of bounds %r"% ratio

        current = __incpy__.internal.window.current()
        sz = __incpy__.internal.window.currentsize(position) * ratio
        result = __incpy__.internal.window.create(buf.number, position, sz, self.options, preview=self.preview)
        self.window = result
        return result

    def show(self, position):
        """Show window at the specified position"""
        buf = self.buffer
        if __incpy__.internal.buffer.number(buf.number) == -1:
            raise Exception, "Buffer %d does not exist"% buf.number
        if __incpy__.internal.buffer.window(buf.number) != -1:
            raise Exception, "Window for %d is already showing"% buf.number
        __incpy__.internal.window.show(buf.number, position, preview=self.preview)

    def hide(self):
        """Hide the window"""
        buf = self.buffer
        if __incpy__.internal.buffer.number(buf.number) == -1:
            raise Exception, "Buffer %d does not exist"% buf.number
        if __incpy__.internal.buffer.window(buf.number) == -1:
            raise Exception, "Window for %d is already hidden"% buf.number
        __incpy__.internal.window.hide(buf.number, preview=self.preview)

    def __repr__(self):
        if self.preview:
            return '<__incpy__.view buffer:%d "%s" preview>'% (self.window, self.buffer.name)
        return '<__incpy__.view buffer:%d "%s">'% (self.window, self.buffer.name)
__incpy__.view = view; del(view)

# spawn interpreter requested by user
_ = __incpy__.vim.gvars["incpy#Program"]
opt = {'winfixwidth':True,'winfixheight':True} if __incpy__.vim.gvars["incpy#WindowFixed"]>0 else {}
try:
    __incpy__.cache = __incpy__.interpreter_external.new(_, opt=opt) if len(_) > 0 else __incpy__.interpreter_python_internal.new(opt=opt)
except:
    __incpy__.log("Error instantiating interpreter: %s"% _)
    _ = __import__('sys').exc_info()
    _ = __import__('traceback').format_exception(*_)
    __incpy__.log('\n'.join(_))
    __incpy__.log("Falling back to default interpreter_python_internal")
    __incpy__.cache = __incpy__.interpreter_python_internal.new(opt=opt)
del(opt)

# create it's window, and store the buffer's id
_ = __incpy__.cache.view
__incpy__.vim.gvars['incpy#BufferId'] = _.buffer.number
_.create(__incpy__.vim.gvars['incpy#WindowPosition'], __incpy__.vim.gvars['incpy#WindowRatio'])

# delete our temp variable
del(_)

# import the user module silently to honor any user-specific configurations
__incpy__.cache.communicate('__import__("user")\n', silent=True)
EOF
endfunction

    let s:current_script=expand("<sfile>:p:h")
    call incpy#SetupOptions()
    call incpy#SetupPython(s:current_script)
    call incpy#Setup()
    call incpy#MapCommands()
    call incpy#MapKeys()

    autocmd VimEnter * python hasattr(__incpy__,'cache') and __incpy__.cache.attach()
    autocmd VimLeavePre * python hasattr(__incpy__,'cache') and __incpy__.cache.detach()

else
    echoerr "Vim compiled without python support. Unable to initialize plugin from ". expand("<sfile>")
endif
