-- [LuaJIT 2.1 호환 shim]
-- 이 코드베이스는 LuaJIT 2.0 시절에 작성되어 Lua 5.0 때 이름들을 그대로 쓴다.
-- LuaJIT 2.1 은 그 별칭들을 제거했다. 없을 때만 되살린다 (Lua 5.1 이나 LuaJIT 2.0 에서는 no-op).
--
-- 이게 없으면:
--   * base64.lua 의 to_base64() 가 math.mod 에서 죽는다
--     -> 엔진이 에디터의 'flst'(파일 체크섬 목록) 요청에 응답하지 못하고
--        'ulst' 를 보내지 않아 테스트 실행이 통째로 멈춘다. (증상: 실행해도 아무 일도 안 남)
--   * PiniAPI 의 터치 처리와 vendored cocos lua 프레임워크가 table.getn 에서 죽는다.
if math.mod == nil then math.mod = math.fmod end
if table.getn == nil then table.getn = function(t) return #t end end
if table.setn == nil then table.setn = function(t, n) end end
if string.gfind == nil then string.gfind = string.gmatch end

local fileUtil = cc.FileUtils:getInstance()
fileUtil:addSearchPath("src")
fileUtil:addSearchPath("res")

local basexx = require("basexx")
socket = require("socket")

PROJ_TITLE = "pini remote"
IS_RELEASE = nil

CC_USE_DEPRECATED_API = true
require "cocos.init"
require "json"
local Utils = require("plua.utils")

WIN_WIDTH = 0
WIN_HEIGHT = 0

fileUtil:addSearchPath(fileUtil:getWritablePath())
fileUtil:addSearchPath(fileUtil:getWritablePath().."scene")
fileUtil:addSearchPath(fileUtil:getWritablePath().."module")
fileUtil:addSearchPath(fileUtil:getWritablePath().."image")
fileUtil:addSearchPath(fileUtil:getWritablePath().."sound")
fileUtil:addSearchPath(fileUtil:getWritablePath().."font")
fileUtil:setPopupNotify(false)

local ROOT_PATH = fileUtil:getWritablePath()

-- 씬 파일 이름은 에디터가 "원본 파일명을 base64" 로 만든다.
-- 그런데 base64 하기 전의 인코딩 기준이 시기마다 달랐다:
--   py2/윈도우 에디터 = cp949,  py3 포팅 이후 = utf-8
-- 그래서 같은 "메인.lnx" 라도 lnx_uN7Azg__(cp949) / lnx_66mU7J24(utf-8) 로 이름이 다르다.
-- 예전 코드는 cp949 쪽 이름을 하드코딩해 둬서, py3 에디터가 만든 프로젝트에서는
-- 씬을 영영 찾지 못하고 검은 화면만 나왔다. 실제로 존재하는 쪽을 골라 쓴다.
local function resolveSceneName(candidates)
	for _, name in ipairs(candidates) do
		if fileUtil:isFileExist(ROOT_PATH..name..".lua") then
			return name
		end
	end
	return nil
end

local MAIN_SCENE = {
	"scene/lnx_66mU7J24",        -- utf-8 "메인"
	"scene/lnx_uN7Azg__",        -- cp949 "메인"
}
local PREMAIN_SCENE = {
	"scene/lnx_7ZSE66as66mU7J24", -- utf-8 "프리메인"
	"scene/lnx_x8G4rrjewM4_",     -- cp949 "프리메인"
}

local md5 = require("md5")
require "base64"
require "trycatch"
require "utils"

cclog = function(...)
	print(string.format(...))
end

print(fileUtil:getWritablePath())
print(fileUtil:getWritablePath())
print(fileUtil:getWritablePath())

-- for CCLuaEngine traceback
function __G__TRACKBACK__(msg)
	cclog("----------------------------------------")
	cclog("LUA ERROR: " .. tostring(msg) .. "\n")
	cclog(debug.traceback())
	cclog("----------------------------------------")

--[[
	str = ""
	str = str.."----------------------------------------"
	str = str.."LUA ERROR: " .. tostring(msg) .. "\n"
	str = str..debug.traceback()
	str = str.."----------------------------------------"

	local scene = cc.Director:getInstance():getRunningScene()
	scene:addChild(layer , 999)

	local layer = cc.Node()
	local text = cc.LabelTTF:create(str, "Arial", 15)
	text:setAnchorPoint(cc.p(0,0))

	layer:addChild(text)
]]
	return msg
end

local consoleBack = nil
local downloadSlide = nil
local function console(text)
	-- print(text)
	if text:len()>50 then
		text = text:sub(1,50)
	end
	if consoleBack then
		if consoleBack.ttf == nil then
			consoleBack.ttf = cc.LabelTTF:create(pStrTitle, "Arial", 15)
			consoleBack.ttf:setAnchorPoint(cc.p(0,0))
			consoleBack.ttf:setVerticalAlignment(2)
			consoleBack.ttf:setHorizontalAlignment(0)
			consoleBack.ttf.text = {}
			consoleBack:addChild(consoleBack.ttf)
		end

		table.insert(consoleBack.ttf.text,text)
		while(1) do
			consoleBack.ttf:setString(table.concat(consoleBack.ttf.text,"\n"))
			if consoleBack.ttf:getContentSize().height > consoleBack:getContentSize().height then
				table.remove(consoleBack.ttf.text, 1)
			else
				break
			end
		end
	end
end

function InitCocos2d(width,height,fullscreen)
	local director = cc.Director:getInstance()
	local glview = director:getOpenGLView()
	if nil == glview then
		if fullscreen then
			glview = cc.GLViewImpl:createWithFullScreen(PROJ_TITLE)
		else
			if width == nil or height == nil then
				glview = cc.GLViewImpl:create(PROJ_TITLE)
			else
				glview = cc.GLViewImpl:createWithRect(PROJ_TITLE,cc.rect(0,0,width,height))
			end
		end
		director:setOpenGLView(glview)
	end

	Utils.SET_WINDOW_TITLE(PROJ_TITLE)

	if width == nil or height == nil then
	else
		glview:setDesignResolutionSize(width , height, cc.ResolutionPolicy.EXACT_FIT)
	end

	if width == nil or height == nil then
		local s = cc.Director:getInstance():getVisibleSize()
		WIN_WIDTH = s.width
		WIN_HEIGHT = s.height
	else
		WIN_WIDTH = width
		WIN_HEIGHT = height
	end
	director:setDisplayStats(false)
	director:setAnimationInterval(1.0 / 60)
end

function ScreenReSize(width,height)
	local director = cc.Director:getInstance()
	local glview = director:getOpenGLView()
	if glview then
		local targetPlatform = cc.Application:getInstance():getTargetPlatform()
		
		if targetPlatform == kTargetWindows then
			glview:setFrameSize(width , height)
		end
		glview:setDesignResolutionSize(width , height, cc.ResolutionPolicy.EXACT_FIT)
	end

	WIN_WIDTH = width
	WIN_HEIGHT = height
end

local function LanX_start(start,line)
	try{
		function()
			package.preload["ProjectInfo"] = nil
			local proj = require("ProjectInfo")

			ScreenReSize(proj.width,proj.height)
			package.loaded["FILEMANS"] = nil
			package.loaded["IMGMANS"] = nil
			require('FILEMANS')
			require('IMGMANS')

			XVM = require("LXVM")
			XVM:init()

			_G.AnimMgr = require("AnimMgr")
			_G.AnimMgr:init(XVM)

			local ROOT_PATH = fileUtil:getWritablePath()
			local UDPath = ROOT_PATH.."/UserDefault.data"
			local USPath = ROOT_PATH.."/UserSettings.data"
			
			local f = Utils.FILE_LoadString(UDPath)
			local SAVEVAR_CHUNK = {}
			local SAVEVAR_DIRTY = false
			if f then
				local all = {}
				try{function()
					all = json.decode(f)
				end,
				catch {function(error)end}
				}
				for k,v in pairs(all) do
					_LNXG = _LNXG or {}
					_LNXG[k] = v
					if type(v) == "number" then
						Utils.SAVEVAR_SET_NUMBER(k,v)
					else
						Utils.SAVEVAR_SET_STRING(k,tostring(v))
					end
				end
				SAVEVAR_CHUNK = all
			end

			XVM.VarSave = function(self,key,val)
				-- local f = Utils.FILE_LoadString(UDPath)
				-- local all = {}
				-- if f then
				-- 	try{function()
				-- 		all = json.decode(f)
				-- 	end,
				-- 	catch {function(error)end}
				-- 	}
				-- end
				if SAVEVAR_CHUNK[key] ~= val then
					if type(val) == "number" then
						Utils.SAVEVAR_SET_NUMBER(key,val)
					else
						Utils.SAVEVAR_SET_STRING(key,tostring(val))
					end
					SAVEVAR_CHUNK[key] = val
					SAVEVAR_DIRTY = true
				end
			end

			XVM.VarFlush = function(self)
				if SAVEVAR_DIRTY then
					Utils.SAVEVAR_FLUSH()
					SAVEVAR_DIRTY = false;
				end
			end

			XVM.SettingSave = function(self,key,val)
				local f = Utils.FILE_LoadString(USPath)
				local all = {}
				if f then
					try{function()
						all = json.decode(f)
					end,
					catch {function(error)end}
					}
				end
				all[key] = val
				Utils.FILE_SaveString(USPath, json.encode(all))
			end

			if pini then
				pini:Clear()
			end

			if line and line > 1 then
				local fname = ROOT_PATH..start..".lua"

				local _in = io.open(fname, "r")
				local fdata = _in:read("*all")
				_in:close()

				local matched = nil
				local s_line = line
				while matched == nil do
					matched = (string.match(fdata, "lc:[0-9]* | ln:"..tostring(line)))
					line = line + 1

					if line > s_line + 10000 then
						line = 0
						break
					end
				end
				
				if matched then
					matched = string.match(matched, ":[0-9]*")
					matched = string.sub(matched, 2)
					line = tonumber(matched)
				end
			end

			require("PiniLib")()
			XVM:Awake()
			XVM:call("libdef.lnx")
			-- "프리메인.lnx" — 있으면 본편보다 먼저 실행되는 선택 사항 씬이다.
			-- 파일명은 에디터가 base64 로 만드는데, 인코딩 기준이 시기마다 달랐다:
			-- py2/윈도우 시절엔 cp949, py3 포팅 후엔 utf-8. 그래서 이름을 하나로 하드코딩하면
			-- 한쪽에서는 절대 못 찾는다. 게다가 존재 여부를 확인하지 않고 호출하고 있어서,
			-- 파일이 없으면(샘플 프로젝트를 포함해 대부분이 그렇다) require 가 예외를 던지고
			-- 이 try 블록이 통째로 중단돼 **본편 씬이 아예 시작되지 않았다** (증상: 검은 화면).
			-- 두 이름을 모두 확인하고, 없으면 조용히 건너뛴다.
			local premain = resolveSceneName(PREMAIN_SCENE)
			if premain then
				XVM:call(premain)
			end
			if line == 0 then line = 1 end

			socket.select(nil, nil, 0.5)
			XVM:call(start,line)

			consoleBack = nil
		end,
		catch {
			function(error)
				console("저장된 메인 씬이 없습니다 : \""..start.."\"")
				print(error)
		end
		}
	}
end


local function makeBtn(pStrTitle,callback)
	-- Creates and return a button with a default background and title color. 
	local pBackgroundButton = cc.Scale9Sprite:create("extensions/button.png")
	local pBackgroundHighlightedButton = cc.Scale9Sprite:create("extensions/buttonHighlighted.png")

	pTitleButton = cc.Label:createWithSystemFont(pStrTitle, "Marker Felt", 30)
	pTitleButton:setColor(cc.c3b(159, 168, 176))

	local pButton = cc.ControlButton:create(pTitleButton, pBackgroundButton)
	pButton:setBackgroundSpriteForState(pBackgroundHighlightedButton, cc.CONTROL_STATE_HIGH_LIGHTED )
	pButton:setTitleColorForState(cc.c3b(255,255,255), cc.CONTROL_STATE_HIGH_LIGHTED )

	pButton:registerControlEventHandler(callback,cc.CONTROL_EVENTTYPE_TOUCH_UP_INSIDE)
	return pButton
end

local function makeSlide(x,y)
	local pSlider = cc.ControlSlider:create("extensions/sliderTrack.png","extensions/sliderProgress.png" ,"extensions/sliderThumb.png")
	pSlider:setAnchorPoint(cc.p(0.5, 1.0))
	pSlider:setMinimumValue(0.0)
	pSlider:setMaximumValue(100.0)
	pSlider:setPosition(cc.p(x,y))
	pSlider:setEnabled(false)
	pSlider:setTag(1)

	return pSlider
end

local function initRemoteScene(width,height)
	local pScene = cc.Scene:create()
	local pLayer = cc.Layer:create()

	local pBackground = cc.Sprite:create("extensions/background.png")
	pBackground:setPosition(width/2,height/2)
	pLayer:addChild(pBackground)

	cs = pBackground:getContentSize()
	pBackground:setScale(width/cs.width,height/cs.height)

	local pRibbon = cc.Scale9Sprite:create("extensions/ribbon.png", cc.rect(1, 1, 48, 55))
	pRibbon:setContentSize(cc.size(width, 57))
	pRibbon:setPosition(cc.p(width/2, height-pRibbon:getContentSize().height / 2.0))
	pLayer:addChild(pRibbon)

	--Add the title
	pSceneTitleLabel = cc.Label:createWithSystemFont("Title", "Arial", 12)
	pSceneTitleLabel:setPosition(cc.p (width/2, height - pSceneTitleLabel:getContentSize().height / 2 - 5))
	pLayer:addChild(pSceneTitleLabel, 1)
	pSceneTitleLabel:setString("피니엔진 리모트")

	--CONSOLE
	local pBackgroundButton = cc.Scale9Sprite:create("extensions/buttonBackground.png")
	pBackgroundButton:setContentSize(cc.size(width-100, 300))
	pBackgroundButton:setAnchorPoint(cc.p(0.5,1))
	pBackgroundButton:setPosition(cc.p(width/2, height-50))
	pLayer:addChild(pBackgroundButton)

	consoleBack = pBackgroundButton

	--BUTTONS
	pButton = makeBtn("저장된 파일 실행하기",function() LanX_start(resolveSceneName(MAIN_SCENE) or MAIN_SCENE[1]) end)
	pButton:setPosition(cc.p (width/2, height/2-100))
	pLayer:addChild(pButton)

	pButton = makeBtn("크래시파일 리포트",function() console("해당 기능은 아직 지원하지 않습니다.") end)
	pButton:setPosition(cc.p (width/2, height/2-150))
	pLayer:addChild(pButton)

	pSlider = makeSlide(width/2, height/2-180)
	pLayer:addChild(pSlider)

	downloadSlide = pSlider

	pScene:addChild(pLayer)
	pScene.pLayer = pLayer
	if cc.Director:getInstance():getRunningScene() then
		cc.Director:getInstance():replaceScene(pScene)
	else
		cc.Director:getInstance():runWithScene(pScene)
	end

	return pScene
end

local function main()
	collectgarbage("collect")
	collectgarbage("setpause", 100)
	collectgarbage("setstepmul", 5000)

	local ROOT_PATH = fileUtil:getWritablePath()
	try{
	function()
		PROJ_TITLE = require("_export_execute_")
		IS_RELEASE = true

		_FULLSCREEN = require("ProjectInfo")["fullscreen"]

		try{
		function()
			local USPath = ROOT_PATH.."/UserSettings.data"

			local f = Utils.FILE_LoadString(USPath)
			if f then
				local all = {}
				try{function()
					all = json.decode(f)
				end,
				catch {function(error)end}
				}
				for k,v in pairs(all) do
					if k == "fullscreen" then
						_FULLSCREEN = v
						break
					end
				end
			end
		end,
		catch {
		function(error)end
		}}

	end,
	catch {
	function(error)end
	}}

	local targetPlatform = cc.Application:getInstance():getTargetPlatform()
	local scene
	if kTargetWindows == targetPlatform then
		if _FULLSCREEN then
			InitCocos2d(nil,nil,_FULLSCREEN)
		else
			InitCocos2d(800,600,_FULLSCREEN)
		end
		scene=initRemoteScene(800,600)
	else
		InitCocos2d()
		size = cc.Director:getInstance():getOpenGLView():getFrameSize()
		scene= initRemoteScene(size.width,size.height)
	end

	local listener = cc.EventListenerTouchOneByOne:create()
	listener:registerScriptHandler(function (touch, event)
		local location = touch:getLocation()
		console(tostring(location.x).." / "..tostring(location.y))
	end,cc.Handler.EVENT_TOUCH_BEGAN )

	local eventDispatcher = scene:getEventDispatcher()
	eventDispatcher:addEventListenerWithSceneGraphPriority(listener, scene)

	try{
	function()
		require("_export_execute_")
		LanX_start(resolveSceneName(MAIN_SCENE) or MAIN_SCENE[1]) -- "메인.lnx"
	end,
	catch {
	function(error)
		print (error)
		console(tostring(kTargetWindows == targetPlatform))

		co = coroutine.create(
		function ()
			console("리모트 실행")
			
			function newset()
				local reverse = {}
				local set = {}
				return setmetatable(set, {__index = {
					insert = function(set, value)
						if not reverse[value] then
							table.insert(set, value)
							reverse[value] = #set
						end
					end,
					remove = function(set, value)
						local index = reverse[value]
						if index then
							reverse[value] = nil
							local top = table.remove(set)
							if top ~= value then
								reverse[top] = index
								set[index] = top
							end
						end
					end,
					find = function(set,value)
						local index = reverse[value]
						return index
					end
				}})
			end

			set = newset()

			local server = assert(socket.bind("*", 45674))
			local ip, port = server:getsockname()
			local clients = {}

			--console("아이피 할당 : "..socket.dns.toip(socket.dns.gethostname()))

			local recv_error = nil
			local function recv(socket,size)
				data, recv_error = socket:receive(size)
				if recv_error then
					--send(socket,"lost","c")
					--socket:close()
					console("리시브드 코드 : "..recv_error)

					local idx = set:find(socket)
					console("연결 종료\n")

					clients[idx] = 0
					socket:close()
					set:remove(socket)

					recv_error = nil
					return nil
				end
				return data
			end

			local function send(socket,order,payload)
				local size = tostring(#payload)
				console("<<"..order.."<<"..size.."<<"..payload)
				for i=#size,11-1,1 do
					size = size.." "
				end

				socket:settimeout(nil)
				socket:send(order)
				socket:send(size)
				socket:send(payload)
			end

			local function recvedInt(str,c)
				local buffer = ""
				for i=1,c,1 do
					local t = str:byte(i)
					if t >= 48 and t <= 57 then
						local c = string.char(t)
						buffer = buffer..c
					else
						break
					end
				end
				return tonumber(buffer)
			end

			local updateListMax = 0
			local updateListCount = 0
			console("리모트 서버 정상 작동")
			set:insert(server)
			while 1 do
				local readable, _, error = socket.select(set, nil,0)
				for _, input in ipairs(readable) do
					if input == server then 
						local new = input:accept()
						if new then
							new:settimeout(1)
							set:insert(new)

							clients[set:find(new)] = 0
							console("툴과 연결됨")

						else
						end
					else
						local line, error;
						local idx = set:find(input)

						console(">> 데이터 수신")
						if clients[idx] == 0 then
							console("명령 해석 중")
							header = recv(input,4)
							console("해더 입력 완료")
							if header then 
								size = recv(input,11)
								size = tostring(size)
								size = recvedInt(size,11)
								
								clients[idx] = {header,size,0}
								console("ok!")
							else
								console("정상 연결 해제.")
							end
						else 
							order = clients[idx][1]
							console("명령 인자 : "..order)
							print("order >> "..order)
							if order == "tran" then
								s1 = tonumber(recv(input,4))
								fileDist = recv(input,s1)
								s2 = tonumber(recv(input,4))
								fileName = recv(input,s2)
								fileData = recv(input,clients[idx][2]-s1-s2-4-4)

								local fullpath = ROOT_PATH..fileDist.."/"..fileName
								--print("Directory!",fileUtil:isDirectoryExist(ROOT_PATH..fileDist))
								if not fileUtil:isDirectoryExist(ROOT_PATH..fileDist) then
									if not fileUtil:createDirectory(ROOT_PATH..fileDist) then
										print("Failed fileUtil:createDirectory",ROOT_PATH..fileDist)
									end
								end
								--print("Directory!",fileUtil:isDirectoryExist(ROOT_PATH..fileDist))

								console(fullpath)

								file = fileName:StripExtension()
								if package.loaded[file] then
									package.loaded[file] = nil
								end

								local out = io.open(fullpath, "wb")
								local t = {}
								out:write(fileData)
								out:close()

								updateListCount = updateListCount+1
								downloadSlide:setValue((updateListCount/updateListMax)*100)
							elseif order == "flst" then
								if consoleBack == nil then
									size = cc.Director:getInstance():getOpenGLView():getFrameSize()
									initRemoteScene(size.width,size.height)
								end

								payload = recv(input,clients[idx][2])
								function readAll(file)
									local f = io.open(file, "rb")
									if f then
										local content = f:read("*all")
										f:close()
										return content
									end
									return nil
								end

								local fileList = json.decode(payload)
								local updateList = {}
								for k,v in pairs(fileList)do
									k = k:gsub("\\","/")
									local fullpath = ROOT_PATH .. k
									local data = readAll(fullpath)
									local needUpdate = true
									if data then
										local hex = md5.sumhexa(data)
										local checksum = to_base64(hex)
										if checksum == v then
											needUpdate = false
										else
										end
									end
									if needUpdate then
										table.insert(updateList,k)
									end
								end
								--print(json.encode(updateList))
								updateListCount = 0
								updateListMax = #updateList
								send(input,"ulst",json.encode(updateList))
							elseif order == "ufin" then
								-- 4바이트 고정 필드라 뒤가 공백(또는 예전 클라이언트의 NUL)로 채워져 온다.
								-- LuaJIT 2.1 의 tonumber 는 NUL 이 섞이면 nil 을 돌려주기 때문에
								-- 그대로 쓰면 바로 아래 문자열 연결에서 죽고 씬이 시작되지 않는다(검은 화면).
								-- 패딩을 걷어내고, 그래도 숫자가 아니면 0 으로 본다.
								startLine = tonumber((recv(input,4):gsub("[%z%s]+$",""))) or 0
								startScene = recv(input,clients[idx][2]-4)
								console("업데이트 완료!")
								console("startLine="..startLine)
								console("===========================================")
								console("씬 실행 "..startScene)
								LanX_start(startScene:gsub("%.lua",""),startLine)
							
								send(input,"ufin","finish")
							
							elseif order == "PATH" then
								recv(input,clients[idx][2])
								send(input,"PATH",ROOT_PATH)
							else
								recv(input,clients[idx][2])
								console("가비지 size:"..clients[idx][2])
							end

							clients[idx] = 0
						end

						if recv_error then
							console("Removing client from set\n")
							clients[idx] = 0
							input:close()
							set:remove(input)
							recv_error = nil
						else
							--??
						end
					end
				end
				coroutine.yield()
			end
		end)

		local udp_dt = 0;
		Utils = require("plua.utils")
		broadcast = Utils.GetBroadcastAddr()

		local platformCode = "UNK"
		if targetPlatform == kTargetWindows then
			platformCode = "WIN"
		elseif targetPlatform == kTargetMacOS then
			platformCode = "MAC"
		elseif targetPlatform == kTargetAndroid then
			platformCode = "AND"
		elseif targetPlatform == kTargetIphone then
			platformCode = "IPH"
		elseif targetPlatform == kTargetIpad then
			platformCode = "IPA"
		end

		local udp_ping = socket.udp()
		udp_ping:setsockname("*", 0)
		udp_ping:settimeout(10)
		udp_ping:setoption('broadcast',true)
		local function networkUpdate(tick)
			udp_dt = udp_dt + tick
			if udp_dt > 1.5 then
				udp_ping:sendto(platformCode, broadcast, 45675)
				udp_dt = 0
			end
			coroutine.resume(co)
		end
		
		local scheduler = cc.Director:getInstance():getScheduler()
		schedulerEntry = scheduler:scheduleScriptFunc(networkUpdate, 0.1, false)
	end}
	}
end

local status, msg = xpcall(main, __G__TRACKBACK__)
if not status then
	error(msg)
end