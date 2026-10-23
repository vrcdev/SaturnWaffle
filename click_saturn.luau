-- saturnwaffle // openCoR
local players = game:GetService("Players")
local run     = game:GetService("RunService")
local uis     = game:GetService("UserInputService")
local rs      = game:GetService("ReplicatedStorage")
local rf      = game:GetService("ReplicatedFirst")
local stats   = game:GetService("Stats")
local lp      = players.LocalPlayer

local function flag(k, d) return Library.Flags[k] ~= nil and Library.Flags[k] or d end
local function flipCam(cf)
	local cam = workspace.CurrentCamera
	local old = cam.CFrame
	cam.CFrame = cf
	return function() cam.CFrame = old end
end
local function lerp(a, b, t) return a + (b - a) * t end

---------------------------------------------------------------- modules

local function findmod(name)
	for _, d in ipairs(rf:GetDescendants()) do
		if d.Name == name and d:IsA("ModuleScript") then return d end
	end
end
local function reqmod(name)
	local m = findmod(name)
	if not m then return nil end
	local ok, t = pcall(require, m)
	return ok and t or nil
end

local M = {
	firearm    = reqmod("FirearmObject"),
	repI       = reqmod("ReplicationInterface"),
	repObj     = reqmod("ReplicationObject"),
	teams      = reqmod("TeamsInterfaceClient"),
	weaponI    = reqmod("WeaponInterface"),
	cameraI    = reqmod("CameraInterface"),
	playerCam  = reqmod("PlayerCameraObject"),
	hitDet     = reqmod("HitDetectionInterface"),
	netClient  = reqmod("NetworkClient"),
	charI      = reqmod("CharacterInterface"),
	adminCfg   = reqmod("MenuAdminConfig"),
}
local function getFirearm()
	if not M.weaponI then return nil end
	local ok, fo = pcall(M.weaponI.getFirearmObject)
	return ok and fo or nil
end
local function getCamObj()
	if not M.cameraI then return nil end
	local ok, c = pcall(M.cameraI.getCameraObject)
	return ok and c or nil
end

---------------------------------------------------------------- flags

Library.Flags.aim_on         = Library.Flags.aim_on         or false
Library.Flags.aim_part       = Library.Flags.aim_part       or "head"
Library.Flags.aim_fov        = Library.Flags.aim_fov        or 150
Library.Flags.aim_chance     = Library.Flags.aim_chance     or 100
Library.Flags.aim_wallcheck  = Library.Flags.aim_wallcheck  or true
Library.Flags.aim_maxdist    = Library.Flags.aim_maxdist    or 500
Library.Flags.aim_team       = Library.Flags.aim_team       or true
Library.Flags.aim_dummies    = Library.Flags.aim_dummies    or false
Library.Flags.cam_aim        = Library.Flags.cam_aim        or false
Library.Flags.cam_key        = Library.Flags.cam_key        or "M2"
Library.Flags.cam_smooth     = Library.Flags.cam_smooth     or 0.25
Library.Flags.esp_on         = Library.Flags.esp_on         or false
Library.Flags.esp_name       = Library.Flags.esp_name       or true
Library.Flags.esp_box        = Library.Flags.esp_box        or true
Library.Flags.esp_health     = Library.Flags.esp_health     or true
Library.Flags.esp_dist       = Library.Flags.esp_dist       or true
Library.Flags.esp_teamcheck  = Library.Flags.esp_teamcheck  or false
Library.Flags.esp_visible_only = Library.Flags.esp_visible_only or false
Library.Flags.esp_skeleton   = Library.Flags.esp_skeleton   or false
Library.Flags.esp_chams      = Library.Flags.esp_chams      or false
Library.Flags.esp_max        = Library.Flags.esp_max        or 2000
Library.Flags.rf_on          = Library.Flags.rf_on          or false
Library.Flags.rf_mult        = Library.Flags.rf_mult        or 1
Library.Flags.no_spread      = Library.Flags.no_spread      or false
Library.Flags.no_recoil      = Library.Flags.no_recoil      or false
Library.Flags.inf_ammo       = Library.Flags.inf_ammo       or false
Library.Flags.fast_reload    = Library.Flags.fast_reload    or false
Library.Flags.fr_mult        = Library.Flags.fr_mult        or 0.5
Library.Flags.auto_deploy    = Library.Flags.auto_deploy    or false
Library.Flags.shot_debug     = Library.Flags.shot_debug     or false
Library.Flags.sens_mult      = Library.Flags.sens_mult      or 1

---------------------------------------------------------------- targeting

local mouse = lp:GetMouse()
local function wts(p)
	local v, on = workspace.CurrentCamera:WorldToViewportPoint(p)
	return Vector2.new(v.X, v.Y), on, v.Z
end

local function getRepEntry(p)
	if not M.repI then return nil end
	local ok, ro = pcall(M.repI.getReplicationObject, p)
	return ok and ro or nil
end

local function enemyChar(p)
	-- engine model first, workspace fallback
	local ro = getRepEntry(p)
	if ro then
		local ok, m = pcall(M.repI.getCharacterModel, ro)
		if ok and m then return m end
		local tpo = rawget(ro, "_thirdPersonObject")
		if type(tpo) == "table" then
			for k, v in pairs(tpo) do
				if typeof(v) == "Instance" and v:IsA("Model") then return v end
			end
		end
	end
	local chars = workspace:FindFirstChild("Characters")
	if chars then
		local m = chars:FindFirstChild(p.Name)
		if m then return m end
	end
	return p.Character
end

local BONE_SET = {"Head", "UpperTorso", "LowerTorso", "RootPart",
	"LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand",
	"LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot"}

local function aimPart(p, which)
	local mdl = enemyChar(p)
	if not mdl then return nil end
	if which == "head" then
		return mdl:FindFirstChild("Head") or mdl:FindFirstChild("UpperTorso") or mdl:FindFirstChildWhichIsA("BasePart")
	elseif which == "torso" then
		return mdl:FindFirstChild("UpperTorso") or mdl:FindFirstChild("LowerTorso") or mdl:FindFirstChild("RootPart")
			or mdl:FindFirstChild("Head") or mdl:FindFirstChildWhichIsA("BasePart")
	elseif which == "root" then
		return mdl:FindFirstChild("RootPart") or mdl:FindFirstChild("LowerTorso") or mdl:FindFirstChildWhichIsA("BasePart")
	elseif which == "closest" then
		local m2 = Vector2.new(mouse.X, mouse.Y)
		local best, bd = nil, 1/0
		for _, d in ipairs(mdl:GetDescendants()) do
			if d:IsA("BasePart") then
				local s, on, z = wts(d.Position)
				if on and z > 0 then
					local dd = (s - m2).Magnitude
					if dd < bd then bd, best = dd, d end
				end
			end
		end
		return best
	end
	return mdl:FindFirstChild("Head") or mdl:FindFirstChildWhichIsA("BasePart")
end

local function friendly(p)
	if not M.teams then return false end
	local ok, r = pcall(M.teams.isPlayerFriendly, p)
	return ok and r or false
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local function visible(part)
	local cam = workspace.CurrentCamera
	local fo = getFirearm()
	local ignore = {lp.Character}
	local chars = workspace:FindFirstChild("Characters")
	if chars then ignore[#ignore+1] = chars end
	local tp = part.Parent
	rayParams.FilterDescendantsInstances = ignore
	local h = workspace:Raycast(cam.CFrame.Position, (part.Position - cam.CFrame.Position), rayParams)
	return not h or h.Instance:IsDescendantOf(tp)
end

local function pickTarget()
	local cam = workspace.CurrentCamera
	local m2 = Vector2.new(mouse.X, mouse.Y)
	local fov = flag("aim_fov", 150)
	local maxd = flag("aim_maxdist", 500)
	local which = flag("aim_part", "head")
	local best, bd = nil, 1/0
	for _, p in ipairs(players:GetPlayers()) do
		if p ~= lp then
			if flag("aim_team", true) and friendly(p) then continue end
			local ro = getRepEntry(p)
			if ro and (ro._health or 0) <= 0 then continue end
			local part = aimPart(p, which)
			if not part and ro and ro._position then
				local s, on, z = wts(ro._position)
				if on and z > 0 and z < maxd then
					local d2 = (s - m2).Magnitude
					if d2 < fov and d2 < bd then bd, best = d2, {pos = ro._position, plr = p} end
				end
			elseif part then
				local s, on, z = wts(part.Position)
				if on and z > 0 and z < maxd then
					local d2 = (s - m2).Magnitude
					if d2 < fov and d2 < bd and (not flag("aim_wallcheck", true) or visible(part)) then
						bd, best = d2, {part = part, plr = p}
					end
				end
			end
		end
	end
	return best
end

---------------------------------------------------------------- firearm patches (rapid fire / spread / reload)

local patchedFO = setmetatable({}, {__mode = "k"}) -- fo -> {field = orig}

local function zeroTableNums(t)
	for k, v in pairs(t) do
		if type(v) == "number" then t[k] = 0
		elseif type(v) == "table" then zeroTableNums(v) end
	end
end
local function scaleTableNums(t, mult)
	for k, v in pairs(t) do
		if type(v) == "number" then t[k] = v * mult
		elseif type(v) == "table" then scaleTableNums(v, mult) end
	end
end

local function patchFirearm(fo)
	if not fo or type(fo._data) ~= "table" then return end
	local st = fo._data.stats
	if not st then return end
	local rec = patchedFO[fo] or {}
	patchedFO[fo] = rec
	-- rapid fire: Firerate is RPM, higher = faster
	if type(st.Firerate) == "number" then
		rec.Firerate = rec.Firerate or st.Firerate
		st.Firerate = flag("rf_on", false) and rec.Firerate * flag("rf_mult", 1) or rec.Firerate
	end
	-- no spread
	if type(st.Spread) == "table" then
		if flag("no_spread", false) and not rec._spread then
			rec._spread = {}
			for k, v in pairs(st.Spread) do rec._spread[k] = v end
			zeroTableNums(st.Spread)
		elseif not flag("no_spread", false) and rec._spread then
			for k, v in pairs(rec._spread) do st.Spread[k] = v end
			rec._spread = nil
		end
	end
	-- no recoil: zero every spring parameter table
	if type(fo._data.recoil) == "table" then
		if flag("no_recoil", false) and not rec._recoil then
			rec._recoil = {}
			local function grab(t, acc)
				for k, v in pairs(t) do
					if type(v) == "number" then acc[k] = v
					elseif type(v) == "table" then local a = {} grab(v, a) acc[k] = a end
				end
			end
			grab(fo._data.recoil, rec._recoil)
			zeroTableNums(fo._data.recoil)
		elseif not flag("no_recoil", false) and rec._recoil then
			local function put(t, acc)
				for k, v in pairs(acc) do
					if type(v) == "number" then t[k] = v
					elseif type(v) == "table" and type(t[k]) == "table" then put(t[k], v) end
				end
			end
			put(fo._data.recoil, rec._recoil)
			rec._recoil = nil
		end
	end
	-- fast reload: scale Animation Times + cancel
	if type(st["Animation Times"]) == "table" then
		if flag("fast_reload", false) and not rec._animT then
			rec._animT = {}
			local function grab(t, acc)
				for k, v in pairs(t) do
					if type(v) == "number" then acc[k] = v
					elseif type(v) == "table" then local a = {} grab(v, a) acc[k] = a end
				end
			end
			grab(st["Animation Times"], rec._animT)
			scaleTableNums(st["Animation Times"], flag("fr_mult", 0.5))
		elseif not flag("fast_reload", false) and rec._animT then
			local function put(t, acc)
				for k, v in pairs(acc) do
					if type(v) == "number" then t[k] = v
					elseif type(v) == "table" and type(t[k]) == "table" then put(t[k], v) end
				end
			end
			put(st["Animation Times"], rec._animT)
			rec._animT = nil
		end
	end
	if flag("fast_reload", false) then
		rec._cancelReloadTime = rec._cancelReloadTime or fo._cancelReloadTime
		fo._cancelReloadTime = (rec._cancelReloadTime or 0.2) * flag("fr_mult", 0.5)
	else
		if rec._cancelReloadTime then fo._cancelReloadTime = rec._cancelReloadTime rec._cancelReloadTime = nil end
	end
end

---------------------------------------------------------------- shot hook (silent aim)

local lastShot = nil
if M.firearm and type(M.firearm.shoot) == "function" then
	local origShoot = M.firearm.shoot
	M.firearm.shoot = function(self, ...)
		local tgt = nil
		if flag("aim_on", false) and math.random(1, 100) <= flag("aim_chance", 100) then
			tgt = pickTarget()
		end
		if tgt then
			local hitPos = tgt.part and tgt.part.Position or tgt.pos
			if flag("shot_debug", false) then warn("[sw] lock ->", tgt.plr and tgt.plr.Name, hitPos) end
			local cam = workspace.CurrentCamera
			local undo = flipCam(CFrame.lookAt(cam.CFrame.Position, hitPos))
			local ok, err = pcall(origShoot, self, ...)
			undo()
			lastShot = {t = tick(), pos = hitPos}
			if not ok then warn("[sw] shoot err:", err) end
			return
		end
		return origShoot(self, ...)
	end
end

---------------------------------------------------------------- recoil hooks (camera-side shove)

if M.playerCam then
	local function wrapImpulse(fname)
		local orig = M.playerCam[fname]
		if type(orig) ~= "function" then return end
		M.playerCam[fname] = function(self, a, ...)
			if flag("no_recoil", false) then
				if type(a) == "number" then a = a * 0 end
				if typeof(a) == "Vector3" then a = Vector3.zero end
			end
			return orig(self, a, ...)
		end
	end
	for _, n in ipairs({"shove", "applyImpulse", "setBodyRecoil", "setHeadRecoil"}) do wrapImpulse(n) end
end

---------------------------------------------------------------- esp

local espPool = {}
local function espFor(p)
	local e = espPool[p]
	if e then return e end
	e = {}
	local function dr(t) local d = Drawing.new(t) d.Visible = false return d end
	e.box    = dr("Square")
	e.name   = dr("Text")   e.name.Center = true e.name.Outline = true e.name.Size = 13
	e.health = dr("Text")   e.health.Center = true e.health.Outline = true e.health.Size = 12
	e.dist   = dr("Text")   e.dist.Center = true e.dist.Outline = true e.dist.Size = 12
	e.bones  = {}
	for i = 1, 14 do e.bones[i] = dr("Line") end
	espPool[p] = e
	return e
end
local function hideEsp(e)
	e.box.Visible = false e.name.Visible = false e.health.Visible = false e.dist.Visible = false
	for _, l in ipairs(e.bones) do l.Visible = false end
end
players.PlayerRemoving:Connect(function(p) local e = espPool[p] if e then hideEsp(e) end end)

local SKELETON = {
	{"Head","UpperTorso"},{"UpperTorso","LowerTorso"},{"LowerTorso","RootPart"},
	{"UpperTorso","LeftUpperArm"},{"LeftUpperArm","LeftLowerArm"},{"LeftLowerArm","LeftHand"},
	{"UpperTorso","RightUpperArm"},{"RightUpperArm","RightLowerArm"},{"RightLowerArm","RightHand"},
	{"LowerTorso","LeftUpperLeg"},{"LeftUpperLeg","LeftLowerLeg"},{"LeftLowerLeg","LeftFoot"},
	{"LowerTorso","RightUpperLeg"},{"RightUpperLeg","RightLowerLeg"},{"RightLowerLeg","RightFoot"},
}

local chams = {}
local chamsParent = nil
pcall(function() chamsParent = gethui and gethui() end)
if not chamsParent then pcall(function() chamsParent = game:GetService("CoreGui") end) end
local function chamsFor(mdl)
	if chams[mdl] then return chams[mdl] end
	local ok, h = pcall(Instance.new, "Highlight")
	if not ok then return nil end
	h.FillTransparency = 0.5 h.OutlineTransparency = 0
	h.Adornee = mdl h.Parent = chamsParent
	chams[mdl] = h
	return h
end

---------------------------------------------------------------- camera aim key tracking

local camHeld = false
uis.InputBegan:Connect(function(i, gpe)
	if gpe then return end
	local k = flag("cam_key", "M2")
	if k == "M2" and i.UserInputType == Enum.UserInputType.MouseButton2 then camHeld = true end
	if k == "M1" and i.UserInputType == Enum.UserInputType.MouseButton1 then camHeld = true end
	if i.KeyCode ~= Enum.KeyCode.Unknown and i.KeyCode.Name == k then camHeld = true end
end)
uis.InputEnded:Connect(function(i)
	local k = flag("cam_key", "M2")
	if k == "M2" and i.UserInputType == Enum.UserInputType.MouseButton2 then camHeld = false end
	if k == "M1" and i.UserInputType == Enum.UserInputType.MouseButton1 then camHeld = false end
	if i.KeyCode ~= Enum.KeyCode.Unknown and i.KeyCode.Name == k then camHeld = false end
end)

---------------------------------------------------------------- main loop

local fovCircle = Drawing.new("Circle")
fovCircle.Thickness = 1 fovCircle.Filled = false fovCircle.Visible = false fovCircle.Color = Color3.new(1,1,1)

local maintT = 0
run.RenderStepped:Connect(function(dt)
	local cam = workspace.CurrentCamera
	local m2 = Vector2.new(mouse.X, mouse.Y)
	fovCircle.Visible = flag("aim_on", false)
	fovCircle.Radius = flag("aim_fov", 150)
	fovCircle.Position = m2

	-- firearm patches + inf ammo
	local fo = getFirearm()
	if fo then
		patchFirearm(fo)
		if flag("inf_ammo", false) then
			local st = fo._data and fo._data.stats
			if st then
				fo._curMag = st["Magazine Size"] or fo._curMag
				fo._curSpare = st["Ammo Pool"] or fo._curSpare
			end
		end
	end

	-- camera aim
	if flag("cam_aim", false) and camHeld then
		local tgt = pickTarget()
		if tgt then
			local hitPos = tgt.part and tgt.part.Position or tgt.pos
			local want = CFrame.lookAt(cam.CFrame.Position, hitPos)
			local sm = flag("cam_smooth", 0.25)
			local co = getCamObj()
			if co and type(co.setCFrame) == "function" then
				pcall(function()
					co:setCFrame(co.current and co.current.CFrame and co.current.CFrame:Lerp(want, sm) or want)
				end)
			end
			cam.CFrame = cam.CFrame:Lerp(want, sm)
		end
	end

	-- esp
	if flag("esp_on", false) then
		for _, p in ipairs(players:GetPlayers()) do
			if p == lp then continue end
			local e = espFor(p)
			if flag("esp_teamcheck", false) and friendly(p) then hideEsp(e) continue end
			local ro = getRepEntry(p)
			local mdl = enemyChar(p)
			local pos = ro and ro._position
			local hp  = ro and ro._health
			if not pos and mdl then
				local r = mdl:FindFirstChild("RootPart") or mdl:FindFirstChildWhichIsA("BasePart")
				pos = r and r.Position
			end
			if not pos then hideEsp(e) continue end
			local sp, on, z = wts(pos)
			local maxd = flag("esp_max", 2000)
			if not on or z > maxd or z <= 0 then hideEsp(e) continue end
			if flag("esp_visible_only", false) and mdl then
				local head = mdl:FindFirstChild("Head") or mdl:FindFirstChildWhichIsA("BasePart")
				if head and not visible(head) then hideEsp(e) continue end
			end
			local col = friendly(p) and Color3.new(0.4,1,0.4) or Color3.new(1,0.35,0.35)
			local scale = math.clamp(1200 / z, 0.3, 6)
			local w, h = 34 * scale, 52 * scale
			if flag("esp_box", true) then
				e.box.Visible = true e.box.Color = col
				e.box.Size = Vector2.new(w, h)
				e.box.Position = Vector2.new(sp.X - w/2, sp.Y - h*0.6)
			else e.box.Visible = false end
			if flag("esp_name", true) then
				e.name.Visible = true e.name.Color = col
				e.name.Text = p.Name
				e.name.Position = Vector2.new(sp.X, sp.Y - h*0.6 - 14)
			else e.name.Visible = false end
			if flag("esp_health", true) and hp then
				e.health.Visible = true
				e.health.Color = hp <= 0 and Color3.new(0.4,0.4,0.4) or Color3.new(1 - hp/150, math.clamp(hp/120,0,1), 0.2)
				e.health.Text = string.format("%d", math.floor(hp + 0.5))
				e.health.Position = Vector2.new(sp.X + w/2 + 12, sp.Y - h*0.3)
			else e.health.Visible = false end
			if flag("esp_dist", true) then
				e.dist.Visible = true e.dist.Color = col
				e.dist.Text = string.format("[%dm]", math.floor(z))
				e.dist.Position = Vector2.new(sp.X, sp.Y + h*0.4)
			else e.dist.Visible = false end
			-- skeleton
			if flag("esp_skeleton", false) and mdl then
				for i, bone in ipairs(SKELETON) do
					local l = e.bones[i]
					local a = mdl:FindFirstChild(bone[1])
					local b = mdl:FindFirstChild(bone[2])
					if a and b then
						local sa, oa = wts(a.Position)
						local sb, ob = wts(b.Position)
						if oa and ob then
							l.Visible = true l.Color = col
							l.From = sa l.To = sb
						else l.Visible = false end
					else l.Visible = false end
				end
			else for _, l in ipairs(e.bones) do l.Visible = false end end
			-- chams
			if flag("esp_chams", false) and mdl then
				local hi = chamsFor(mdl)
				if hi then hi.FillColor = col hi.Adornee = mdl end
			end
		end
	else
		for _, e in pairs(espPool) do hideEsp(e) end
		for mdl, h in pairs(chams) do h.Enabled = false end
	end
	if flag("esp_chams", false) == false then
		for mdl, h in pairs(chams) do pcall(function() h:Destroy() end) chams[mdl] = nil end
	end

	-- maintenance
	maintT = maintT + dt
	if maintT > 2 then
		maintT = 0
		if flag("auto_deploy", false) and M.charI and M.charI.deployed == false then
			pcall(function() M.netClient.send("repDeploy") end)
		end
	end
end)

---------------------------------------------------------------- ui

local Window = Library.Window("waffle // saturn", Vector2.new(540, 620))
pcall(function() Window.Watermark("waffle") end)
pcall(function() Window.ChangeAnime("Astolfo") end)
pcall(function() Window.ToggleAnime(false) end)

local combat = Window:Tab("combat")
local aimSec = combat:Section("silent aim", "Left")
aimSec:Toggle({Title = "enabled", Flag = "aim_on", Default = false})
aimSec:Dropdown({Title = "aim part", Flag = "aim_part", List = {"head","torso","root","closest"}, Default = "head"})
aimSec:Slider({Title = "fov", Flag = "aim_fov", Min = 20, Max = 600, Default = 150, Decimals = 1})
aimSec:Slider({Title = "hit chance", Flag = "aim_chance", Min = 1, Max = 100, Default = 100, Decimals = 1})
aimSec:Slider({Title = "max dist", Flag = "aim_maxdist", Min = 50, Max = 2000, Default = 500, Decimals = 1})
aimSec:Toggle({Title = "wall check", Flag = "aim_wallcheck", Default = true})
aimSec:Toggle({Title = "team check", Flag = "aim_team", Default = true})
aimSec:Toggle({Title = "shot debug", Flag = "shot_debug", Default = false})

local camSec = combat:Section("camera aim", "Right")
camSec:Toggle({Title = "enabled (hold key)", Flag = "cam_aim", Default = false})
camSec:Dropdown({Title = "key", Flag = "cam_key", List = {"M2","M1","Q","E","X","CapsLock"}, Default = "M2"})
camSec:Slider({Title = "smoothing", Flag = "cam_smooth", Min = 0.05, Max = 1, Default = 0.25, Decimals = 100})

local gunTab = Window:Tab("weapon")
local gunSec = gunTab:Section("firearm", "Left")
gunSec:Toggle({Title = "rapid fire", Flag = "rf_on", Default = false})
gunSec:Slider({Title = "fire rate mult", Flag = "rf_mult", Min = 1, Max = 4, Default = 1, Decimals = 100})
gunSec:Toggle({Title = "no spread", Flag = "no_spread", Default = false})
gunSec:Toggle({Title = "no recoil", Flag = "no_recoil", Default = false})
gunSec:Toggle({Title = "infinite ammo", Flag = "inf_ammo", Default = false})
gunSec:Toggle({Title = "fast reload", Flag = "fast_reload", Default = false})
gunSec:Slider({Title = "reload mult", Flag = "fr_mult", Min = 0.05, Max = 1, Default = 0.5, Decimals = 100})

local miscSec = gunTab:Section("deploy", "Right")
miscSec:Toggle({Title = "auto deploy", Flag = "auto_deploy", Default = false})
miscSec:Button({Title = "deploy now", Callback = function()
	if M.netClient then
		local ok, err = pcall(M.netClient.send, "repDeploy")
		warn("[sw] repDeploy ->", ok, err)
	end
end})
miscSec:Button({Title = "dump firearm", Callback = function()
	local fo = getFirearm()
	if not fo then warn("[sw] no firearm") return end
	local out = {}
	for k, v in pairs(fo._data and fo._data.stats or {}) do out[#out+1] = tostring(k).."="..tostring(v) end
	warn("[sw] stats: "..table.concat(out, " | "))
end})

local vis = Window:Tab("visuals")
local espSec = vis:Section("esp", "Left")
espSec:Toggle({Title = "enabled", Flag = "esp_on", Default = false})
espSec:Toggle({Title = "names", Flag = "esp_name", Default = true})
espSec:Toggle({Title = "boxes", Flag = "esp_box", Default = true})
espSec:Toggle({Title = "health", Flag = "esp_health", Default = true})
espSec:Toggle({Title = "distance", Flag = "esp_dist", Default = true})
espSec:Toggle({Title = "skeleton", Flag = "esp_skeleton", Default = false})
espSec:Toggle({Title = "chams", Flag = "esp_chams", Default = false})
espSec:Toggle({Title = "hide friendly", Flag = "esp_teamcheck", Default = false})
espSec:Toggle({Title = "visible only", Flag = "esp_visible_only", Default = false})
espSec:Slider({Title = "max dist", Flag = "esp_max", Min = 100, Max = 5000, Default = 2000, Decimals = 1})

Window:AddSettingsTab()
warn(string.format("[sw] up — modules: %d | firearm: %s", (function() local n=0 for k,v in pairs(M) do if v then n=n+1 end end return n end)(), tostring(getFirearm() ~= nil)))
