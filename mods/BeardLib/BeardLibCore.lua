if not _G.BeardLib then
    _G.BeardLib = {}

    local self = BeardLib
	self._mod = nil
    self.Name = "BeardLib"
    self.Version = 2.2 --for compatibility checks
    self.ModPath = ModPath
    self.SavePath = SavePath
    self.sequence_mods = self.sequence_mods or {}

	function self:read_config(file, tbl)
		local file = io.open(ModPath..file)
		local config = ScriptSerializer:from_custom_xml(file:read("*all"))
		for i, var in pairs(config) do
			if type(var) == "string" then
				config[i] = string.gsub(var, "%$(%w+)%$", tbl or self)
			end
		end
		return config
	end

	self.config = self:read_config("Config.xml")
	local _hooks = self.config.hooks
	self.config.hooks = {}
	for _, hook in ipairs(_hooks) do
		self.config.hooks[hook.source] = hook.file
	end
	_hooks = nil
    self.managers = {}

    self.custom_mission_elements = {
        "MoveUnit",
        "TeleportPlayer",
        "Environment",
        "PushInstigator"
    }
    self.modules = {}

    self._updaters = {}
    self._paused_updaters = {}

	function self:init()
		self:LoadClasses()
		self:LoadModules()

		if not file.DirectoryExists(self.config.maps_dir) then
			os.execute("mkdir " .. self.config.maps_dir)
		end

		local languages = {}
		for i, file in pairs(file.GetFiles(self.config.localization_dir)) do
			local lang = path:GetFileNameWithoutExtension(file)
			table.insert(languages, {
				_meta = "localization",
				file = file, --path:GetFileName(file),
				language = lang
			})
		end
        languages.directory = path:GetFileNameWithoutExtension(self.config.localization_dir)
		LocalizationModule:new(self, languages)
		for k, manager in pairs(self.managers) do
			if manager.new then
				self.managers[k] = manager:new()
			end
		end
		--Load mod_overrides adds
		self:RegisterTweak()
	end

	function self:AddUpdater(id, clbk, pasued)
		self._updaters[id] = clbk
		if paused then
			self._paused_updaters[id] = clbk
		end
	end

	function self:RemoveUpdater(id)
		self._updaters[id] = nil
		self._paused_updaters[id] = nil
	end

	function self:LoadClasses()
		for _, clss in ipairs(self.config.classes) do
            local p = self.config.classes_dir .. clss.file
			local obj = loadstring( "--"..p.. "\n" .. io.open(p):read("*all"))()
			if clss.manager and obj then
				self.managers[clss.manager] = obj
			end
		end
	end

	function self:RegisterModule(key, module)
        if not key or type(key) ~= "string" then
            self:log("[ERROR] BeardLib:RegisterModule parameter #1, string expected got %s", key and type(key) or "nil")
        end

		if not self.modules[key] then
			self:log("Registered module with key %s", key)
			self.modules[key] = module
		else
			self:log("[ERROR] Module with key %s already exists", key)
		end
	end

	function self:LoadModules()
		local modules = file.GetFiles(self.config.modules_dir)
		if modules then
			for _, mdle in pairs(modules) do
				dofile(self.config.modules_dir .. mdle)
			end
		end
	end

	function self:RegisterTweak()
		TweakDataHelper:ModifyTweak({
			name_id = "bm_global_value_mod",
			desc_id = "menu_l_global_value_mod",
			color = Color(255, 59, 174, 254) / 255,
			dlc = false,
			chance = 1,
			value_multiplier = 1,
			durability_multiplier = 1,
			--drops = false,
			track = false,
			sort_number = -10,
			--category = "mod"
		}, "lootdrop", "global_values", "mod")

		TweakDataHelper:ModifyTweak({"mod"}, "lootdrop", "global_value_list_index")

		TweakDataHelper:ModifyTweak({
			free = true,
			content = {
				--loot_global_value = "mod",
				loot_drops = {},
				upgrades = {}
			}
		}, "dlc", "mod")
	end

	function self:log(str, ...)
		ModCore.log(self, str, ...)
	end

	-- kept for compatibility with mods designed for older BeardLib versions --
	function self:ReplaceScriptData(replacement, replacement_type, target_path, target_ext, options)
		options = type(options) == "table" and options or {}
		FileManager:ScriptReplaceFile(target_ext, target_path, replacement, table.merge(options, { type = replacement_type, mode = options.merge_mode }))
	end

	function self:DownloadMap(level_name, update_key, done_callback)
		local function done_map_download()
			BeardLib.managers.MapFramework:Load()
			BeardLib.managers.MapFramework:RegisterHooks()
			managers.job:_check_add_heat_to_jobs()
			managers.crimenet:find_online_games(Global.game_settings.search_friends_only)
			if done_callback then
				done_callback(true)
			end
		end
	    QuickMenuPlus:new(managers.localization:text("custom_map_alert"), managers.localization:text("custom_map_needs_download"), {{text = "Yes", callback = function()
        	local provider = ModAssetsModule._providers.modworkshop --temporarily will support only mws
		    dohttpreq(ModCore:GetRealFilePath(provider.download_info_url, tostring(update_key)), function(data, id)
				local ret, d_data = pcall(function() return json.decode(data) end)
				if ret then			
				    local download_url = ModCore:GetRealFilePath(provider.download_api_url, d_data[tostring(update_key)])
				    BeardLib:log("Downloading map from url: %s", download_url)					
				    local orig = DownloadProgressBoxGui._update
					function DownloadProgressBoxGui._update(o, this)
						orig(o, this)
						this._anim_data.download_amt_text:set_text(managers.localization:to_upper_text("custom_map_download_complete"))
						BlackMarketGui:make_fine_text(this._anim_data.download_amt_text)
						DownloadProgressBoxGui._update = orig
					end
					managers.system_menu:show_download_progress({
						title = managers.localization:text("base_mod_download_downloading_mod", {mod_name = level_name or "No Map Name"}),
						focus_button = 1,
						force = true,
						button_list = {{cancel_button = true, text = managers.localization:text("dialog_ok")}}
					})
				    dohttpreq(download_url, callback(ModAssetsModule, ModAssetsModule, "StoreDownloadedAssets", {install_directory = "Maps", done_callback = done_map_download}), LuaModUpdates.UpdateDownloadDialog)
				else
					QuickMenuPlus:new(managers.localization:text("mod_assets_error"), managers.localization:text("custom_map_failed_download"))
					BeardLib:log("Failed to parse the data received from Modworkshop(Invalid map?)")
				end
			end)
        end},{text = "No", is_cancel_button = true, callback = function()
        	if done_callback then
				done_callback(false)
			end
        end}}, {force = true})
	end

	function self:update(t, dt)
		for _, manager in pairs(self.managers) do
			if manager.update then
				manager:update(t, dt)
			end
		end
		for _, clbk in pairs(self._updaters) do
			clbk()
		end
	end

	function self:paused_update(t, dt)
		for _, manager in pairs(self.managers) do
			if manager.paused_update then
				manager:paused_update(t, dt)
			end
		end
		for _, clbk in pairs(self._paused_updaters) do
			clbk()
		end
	end
end

if RequiredScript then
    local requiredScript = RequiredScript:lower()
    if BeardLib.config.hooks[requiredScript] then
        dofile( BeardLib.config.hooks_dir .. BeardLib.config.hooks[requiredScript] )
    end
end
