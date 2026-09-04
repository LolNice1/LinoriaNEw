local InputService = game:GetService('UserInputService');
local TextService = game:GetService('TextService');
local CoreGui = gethui and gethui() or cloneref(game:GetService('CoreGui'));
local Teams = game:GetService('Teams');
local Players = game:GetService('Players');
local RunService = game:GetService('RunService')
local TweenService = game:GetService('TweenService');
local RenderStepped = RunService.RenderStepped;
local LocalPlayer = Players.LocalPlayer;
local Mouse = cloneref(LocalPlayer:GetMouse());

local ProtectGui = protectgui or (syn and syn.protect_gui) or (function() end);

local ScreenGui = Instance.new('ScreenGui');
ProtectGui(ScreenGui);

ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Global;
ScreenGui.Parent = CoreGui;
ScreenGui.DisplayOrder = 20;
-- Do not set this to true: Mouse.X/Y and AbsolutePosition are both
-- inset-excluded, and the overlays below are positioned straight from them.
ScreenGui.IgnoreGuiInset = false;

local Toggles = {};
local Options = {};

getgenv().Toggles = Toggles;
getgenv().Options = Options;

local Library = {
	Registry = {};
	RegistryMap = {};

	HudRegistry = {};

	FontColor = Color3.fromRGB(255, 255, 255);
	MainColor = Color3.fromRGB(28, 28, 28);
	BackgroundColor = Color3.fromRGB(20, 20, 20);
	AccentColor = Color3.fromRGB(213, 60, 222);
	OutlineColor = Color3.fromRGB(50, 50, 50);
	RiskColor = Color3.fromRGB(255, 50, 50),

	Black = Color3.new(0, 0, 0);
	Font = Enum.Font.Arial,

	-- Screen dim drawn behind the window while the menu is open.
	-- 0 = no dim, 1 = fully opaque. Point a slider at
	-- Library:SetBackgroundBrightness(Value) to expose it to the user.
	BackgroundBrightness = 0.45;
	BackgroundDimColor = Color3.fromRGB(8, 8, 8);

	-- Custom cursor. Live-toggleable by consumer scripts through
	-- Library:SetCustomCursor(Bool).
	CustomCursor = true;
	CustomCursorImage = 'rbxassetid://4292970642';

	-- Tab switch transition. Set TabAnimationTime to 0 to disable it.
	TabAnimationTime = 0.22;
	TabAnimationOffset = 10;

	-- Width of the vertical tab strip on the left of the window.
	TabStripWidth = 132;


	-- Slider fill easing. Higher is snappier, 0 disables the lerp entirely.
	SliderLerpSpeed = 16;

	-- Dropdown open / close animation length. 0 disables it.
	DropdownAnimationTime = 0.16;

	-- Functions run whenever the menu is opened or closed. Popout panels use
	-- this so they hide and come back with the menu they belong to.
	MenuToggledCallbacks = {};

	-- Nil makes the toggle checkmark pick black or white automatically,
	-- based on how bright the fill sitting behind it is.
	CheckmarkColor = nil;

	-- Fade length shared by the menu and the background dim.
	MenuFadeTime = 0.2;

	-- Height in pixels of the logo shown under the search box.
	WindowImageSize = 58;

	-- Heading of the on-screen keybind list.
	KeybindListTitle = 'Keybinds';

	-- Falling-dot overlay drawn over the dim while the menu is open.
	-- Library:SetSnow(Bool) flips it at runtime.
	SnowEnabled = true;
	SnowCount = 90;
	SnowSpeed = 34;
	SnowDrift = 16;
	SnowSizeMin = 1;
	SnowSizeMax = 3;
	SnowColor = Color3.fromRGB(255, 255, 255);
	SnowTransparency = 0.35;

	OpenedFrames = {};
	DependencyBoxes = {};

	NotificationStyle = {
		Transparency = 0;
		BarSide = "Left"; -- { "Left", "Right", "Bottom", "Top" };
		Alignment = "Left"; -- { "Left", "Center", "Right" };
		Y = 0.1;
		X= 0;
	};

	KeypickerListVisible = true;
	KeypickerListMode = "All"; --[[
		{
			"Active",
			"Toggled",
			"All"
		};
	]]

	Signals = {};
	ScreenGui = ScreenGui;

	-- Color pickers currently running in rainbow mode.
	RainbowPickers = {};

	-- Lookups filled in by CreateWindow / AddTab / AddGroupbox so the search box
	-- can work out which tab and groupbox any indexed element lives in.
	SearchIndex = {};
	TabLookup = {};
	SubTabLookup = {};
	GroupboxLookup = {};
};

local _UI_IS_VISIBLE = false;

local RainbowStep = 0
local Hue = 0

table.insert(Library.Signals, RenderStepped:Connect(function(Delta)
	RainbowStep = RainbowStep + Delta

	if RainbowStep >= (1 / 60) then
		RainbowStep = 0

		Hue = Hue + (1 / 400);

		if Hue > 1 then
			Hue = 0;
		end;

		Library.CurrentRainbowHue = Hue;
		Library.CurrentRainbowColor = Color3.fromHSV(Hue, 0.8, 1);

		-- Push the new hue into every color picker with rainbow mode on.
		for Picker in next, Library.RainbowPickers do
			if Picker.Rainbow and Picker.SetValueRGB then
				Picker:SetValueRGB(Library.CurrentRainbowColor, Picker.Transparency);
			else
				Library.RainbowPickers[Picker] = nil;
			end;
		end;
	end
end))

-- < Slider fill easing >
-- Every slider registers its fill frame here and one shared render loop walks
-- each one toward its target width, so dragging reads as a smooth bar instead
-- of a hard snap. One connection total rather than one per slider.
local SliderFills = {};

table.insert(Library.Signals, RenderStepped:Connect(function(Delta)
	local Speed = tonumber(Library.SliderLerpSpeed) or 0;

	for Fill, Data in next, SliderFills do
		if not Fill.Parent then
			SliderFills[Fill] = nil;
			continue;
		end;

		if Speed <= 0 or math.abs(Data.Target - Data.Current) <= 0.4 then
			Data.Current = Data.Target;
		else
			Data.Current = Data.Current + ((Data.Target - Data.Current) * (1 - math.exp(-Speed * Delta)));
		end;

		local Rounded = math.round(Data.Current);

		if Rounded ~= Data.Last then
			Data.Last = Rounded;
			Fill.Size = UDim2.new(0, Rounded, 1, 0);

			if Data.OnStep then
				Data.OnStep(Rounded);
			end;
		end;
	end;
end));

---Point a slider fill at a new width.
---@param Fill Frame
---@param Target number width in pixels
---@param Instant boolean? skip the easing, used by the build and resize paths
---@param OnStep function? called with the eased width whenever it changes
function Library:SetSliderFill(Fill, Target, Instant, OnStep)
	local Data = SliderFills[Fill];

	if not Data then
		Data = { Current = Target; Target = Target; };
		SliderFills[Fill] = Data;
	end;

	Data.Target = Target;
	Data.OnStep = OnStep;

	if Instant then
		Data.Current = Target;
		Data.Last = nil;
	end;
end;

local function GetPlayersString()
	local PlayerList = Players:GetPlayers();

	for i = 1, #PlayerList do
		PlayerList[i] = PlayerList[i].Name;
	end;

	table.sort(PlayerList, function(str1, str2) return str1 < str2 end);

	return PlayerList;
end;

local function GetTeamsString()
	local TeamList = Teams:GetTeams();

	for i = 1, #TeamList do
		TeamList[i] = TeamList[i].Name;
	end;

	table.sort(TeamList, function(str1, str2) return str1 < str2 end);

	return TeamList;
end;

function Library:SafeCallback(f, ...)
	if (not f) then
		return;
	end;

	if not Library.NotifyOnError then
		return f(...);
	end;

	local success, event = pcall(f, ...);

	if not success then
		local _, i = event:find(":%d+: ");

		if not i then
			return Library:Notify(event);
		end;

		return Library:Notify(event:sub(i + 1), 3);
	end;
end;

function Library:AttemptSave()
	if Library.SaveManager then
		Library.SaveManager:Save();
	end;
end;

function Library:Create(Class, Properties)
	local _Instance = Class;

	if type(Class) == 'string' then
		_Instance = Instance.new(Class);
	end;

	for Property, Value in next, Properties do
		_Instance[Property] = Value;
	end;

	return _Instance;
end;

function Library:ApplyTextStroke(Inst)
	Inst.TextStrokeTransparency = 1;

	Library:Create('UIStroke', {
		Color = Color3.new(0, 0, 0);
		Thickness = 1;
		LineJoinMode = Enum.LineJoinMode.Miter;
		Parent = Inst;
	});
end;

function Library:CreateLabel(Properties, IsHud)
	local _Instance = Library:Create('TextLabel', {
		BackgroundTransparency = 1;
		Font = Library.Font;
		TextColor3 = Library.FontColor;
		TextSize = 16;
		TextStrokeTransparency = 0;
	});

	Library:ApplyTextStroke(_Instance);

	Library:AddToRegistry(_Instance, {
		TextColor3 = 'FontColor';
	}, IsHud);

	return Library:Create(_Instance, Properties);
end;

function Library:MakeDraggable(Instance, Cutoff)
	Instance.Active = true;

	Instance.InputBegan:Connect(function(Input)
		if Input.UserInputType == Enum.UserInputType.MouseButton1 then
			local ObjPos = Vector2.new(
				Mouse.X - Instance.AbsolutePosition.X,
				Mouse.Y - Instance.AbsolutePosition.Y
			);

			if ObjPos.Y > (Cutoff or 40) then
				return;
			end;

			while InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) do
				Instance.Position = UDim2.new(
					0,
					Mouse.X - ObjPos.X + (Instance.Size.X.Offset * Instance.AnchorPoint.X),
					0,
					Mouse.Y - ObjPos.Y + (Instance.Size.Y.Offset * Instance.AnchorPoint.Y)
				);

				RenderStepped:Wait();
			end;
		end;
	end)
end;

local DraggingGui = Instance.new("ScreenGui", gethui());
function Library:MakeDraggableOutline(Instance, Cutoff)
	Instance.Active = true;

	Instance.InputBegan:Connect(function(Input)
		if Input.UserInputType == Enum.UserInputType.MouseButton1 then
			local ObjPos = Vector2.new(
				Mouse.X - Instance.AbsolutePosition.X,
				Mouse.Y - Instance.AbsolutePosition.Y
			);

			if ObjPos.Y > (Cutoff or 40) then
				return;
			end;

			local frame = Library:Create("Frame", {
				Parent = DraggingGui;
				AnchorPoint = Instance.AnchorPoint;
				BackgroundTransparency = 1;
				Size = Instance.Size;
				Position = Instance.Position;
			});
			local uistroke = Library:Create("UIStroke", {
				Parent = frame;
				Color = Library.AccentColor or Color3.new(0, 0, 0);
			});

			while InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) do
				frame.Position = UDim2.new(
					0,
					Mouse.X - ObjPos.X + (Instance.Size.X.Offset * Instance.AnchorPoint.X),
					0,
					Mouse.Y - ObjPos.Y + (Instance.Size.Y.Offset * Instance.AnchorPoint.Y)
				);
				uistroke.Color = Library.AccentColor or Color3.new(0, 0, 0);
				RenderStepped:Wait();
			end;
			Instance.Position = UDim2.new(
				0,
				Mouse.X - ObjPos.X + (Instance.Size.X.Offset * Instance.AnchorPoint.X),
				0,
				Mouse.Y - ObjPos.Y + (Instance.Size.Y.Offset * Instance.AnchorPoint.Y)
			);
			frame:Destroy();
		end;
	end)
end;
function Library:AddToolTip(InfoStr, HoverInstance)
	local X, Y = Library:GetTextBounds(InfoStr, Library.Font, 14);
	local Tooltip = Library:Create('Frame', {
		BackgroundColor3 = Library.MainColor,
		BorderColor3 = Library.OutlineColor,

		Size = UDim2.fromOffset(X + 5, Y + 4),
		ZIndex = 100,
		Parent = Library.ScreenGui,

		Visible = false,
	})

	local Label = Library:CreateLabel({
		Position = UDim2.fromOffset(3, 1),
		Size = UDim2.fromOffset(X, Y);
		TextSize = 14;
		Text = InfoStr,
		TextColor3 = Library.FontColor,
		TextXAlignment = Enum.TextXAlignment.Left;
		ZIndex = Tooltip.ZIndex + 1,

		Parent = Tooltip;
	});

	Library:AddToRegistry(Tooltip, {
		BackgroundColor3 = 'MainColor';
		BorderColor3 = 'OutlineColor';
	});

	Library:AddToRegistry(Label, {
		TextColor3 = 'FontColor',
	});

	local IsHovering = false

	HoverInstance.MouseEnter:Connect(function()
		if Library:MouseIsOverOpenedFrame() then
			return
		end

		IsHovering = true

		Tooltip.Position = UDim2.fromOffset(Mouse.X + 15, Mouse.Y + 12)
		Tooltip.Visible = true

		while IsHovering do
			RunService.Heartbeat:Wait()
			Tooltip.Position = UDim2.fromOffset(Mouse.X + 15, Mouse.Y + 12)
		end
	end)

	HoverInstance.MouseLeave:Connect(function()
		IsHovering = false
		Tooltip.Visible = false
	end)
end

function Library:OnHighlight(HighlightInstance, Instance, Properties, PropertiesDefault)
	HighlightInstance.MouseEnter:Connect(function()
		local Reg = Library.RegistryMap[Instance];

		for Property, ColorIdx in next, Properties do
			Instance[Property] = Library[ColorIdx] or ColorIdx;

			if Reg and Reg.Properties[Property] then
				Reg.Properties[Property] = ColorIdx;
			end;
		end;
	end)

	HighlightInstance.MouseLeave:Connect(function()
		local Reg = Library.RegistryMap[Instance];

		for Property, ColorIdx in next, PropertiesDefault do
			Instance[Property] = Library[ColorIdx] or ColorIdx;

			if Reg and Reg.Properties[Property] then
				Reg.Properties[Property] = ColorIdx;
			end;
		end;
	end)
end;

function Library:MouseIsOverOpenedFrame()
	for Frame, _ in next, Library.OpenedFrames do
		local AbsPos, AbsSize = Frame.AbsolutePosition, Frame.AbsoluteSize;

		if Mouse.X >= AbsPos.X and Mouse.X <= AbsPos.X + AbsSize.X
			and Mouse.Y >= AbsPos.Y and Mouse.Y <= AbsPos.Y + AbsSize.Y then

			return true;
		end;
	end;
end;

function Library:IsMouseOverFrame(Frame)
	local AbsPos, AbsSize = Frame.AbsolutePosition, Frame.AbsoluteSize;

	if Mouse.X >= AbsPos.X and Mouse.X <= AbsPos.X + AbsSize.X
		and Mouse.Y >= AbsPos.Y and Mouse.Y <= AbsPos.Y + AbsSize.Y then

		return true;
	end;
end;

---Whether the menu is currently on screen.
---@return boolean
function Library:IsMenuOpen()
	return _UI_IS_VISIBLE == true;
end;

---Run a function whenever the menu is opened or closed. Called with the new
---visibility.
---@param Func function
---@return function
function Library:OnMenuToggled(Func)
	table.insert(Library.MenuToggledCallbacks, Func);
	return Func;
end;

function Library:UpdateDependencyBoxes()
	for _, Depbox in next, Library.DependencyBoxes do
		Depbox:Update();
	end;
end;

function Library:MapValue(Value, MinA, MaxA, MinB, MaxB)
	return (1 - ((Value - MinA) / (MaxA - MinA))) * MinB + ((Value - MinA) / (MaxA - MinA)) * MaxB;
end;

function Library:GetTextBounds(Text, Font, Size, Resolution)
	local Bounds = TextService:GetTextSize(Text, Size, Font, Resolution or Vector2.new(1920, 1080))
	return Bounds.X, Bounds.Y
end;

function Library:GetDarkerColor(Color)
	local H, S, V = Color3.toHSV(Color);
	return Color3.fromHSV(H, S, V / 1.5);
end;
Library.AccentColorDark = Library:GetDarkerColor(Library.AccentColor);

function Library:AddToRegistry(Instance, Properties, IsHud)
	local Idx = #Library.Registry + 1;
	local Data = {
		Instance = Instance;
		Properties = Properties;
		Idx = Idx;
	};

	table.insert(Library.Registry, Data);
	Library.RegistryMap[Instance] = Data;

	if IsHud then
		table.insert(Library.HudRegistry, Data);
	end;
end;

function Library:RemoveFromRegistry(Instance)
	local Data = Library.RegistryMap[Instance];

	if Data then
		for Idx = #Library.Registry, 1, -1 do
			if Library.Registry[Idx] == Data then
				table.remove(Library.Registry, Idx);
			end;
		end;

		for Idx = #Library.HudRegistry, 1, -1 do
			if Library.HudRegistry[Idx] == Data then
				table.remove(Library.HudRegistry, Idx);
			end;
		end;

		Library.RegistryMap[Instance] = nil;
	end;
end;

function Library:UpdateColorsUsingRegistry()
	-- TODO: Could have an 'active' list of objects
	-- where the active list only contains Visible objects.

	-- IMPL: Could setup .Changed events on the AddToRegistry function
	-- that listens for the 'Visible' propert being changed.
	-- Visible: true => Add to active list, and call UpdateColors function
	-- Visible: false => Remove from active list.

	-- The above would be especially efficient for a rainbow menu color or live color-changing.

	for Idx, Object in next, Library.Registry do
		for Property, ColorIdx in next, Object.Properties do
			if type(ColorIdx) == 'string' then
				Object.Instance[Property] = Library[ColorIdx];
			elseif type(ColorIdx) == 'function' then
				Object.Instance[Property] = ColorIdx()
			end
		end;
	end;

	-- RichText colours are baked into the string, so they cannot ride the
	-- registry and have to be rebuilt whenever the accent changes.
	if Library.RefreshWindowTitle then
		pcall(Library.RefreshWindowTitle);
	end;

	if Library.RefreshKeybindList then
		pcall(Library.RefreshKeybindList);
	end;

	if Library.RefreshWatermark then
		pcall(Library.RefreshWatermark);
	end;
end;

function Library:GiveSignal(Signal)
	-- Only used for signals not attached to library instances, as those should be cleaned up on object destruction by Roblox
	table.insert(Library.Signals, Signal)
end

function Library:Unload()
	-- Hand the game its cursor back before the render loop is torn down,
	-- otherwise MouseIconEnabled stays false with nothing drawing a cursor.
	if Library.RestoreCursor then
		pcall(Library.RestoreCursor, Library);
	end

	-- Tear the snow render loop down before the signal sweep, otherwise the
	-- RenderStepped connection outlives the frames it is animating.
	if Library.ClearSnow then
		pcall(Library.ClearSnow, Library);
	end

	-- Unload all of the signals
	for Idx = #Library.Signals, 1, -1 do
		local Connection = table.remove(Library.Signals, Idx)
		Connection:Disconnect()
	end

	-- Call our unload callback, maybe to undo some hooks etc
	if Library.OnUnload then
		Library.OnUnload()
	end

	ScreenGui:Destroy()
end

function Library:OnUnload(Callback)
	Library.OnUnload = Callback
end

local GuiService = game:GetService('GuiService');

---Turn a bare asset id (number or digit string) into a usable content string.
---@param Image string | number
---@return string
function Library:ResolveImage(Image)
	if type(Image) == 'number' then
		return 'rbxassetid://' .. Image;
	end;

	if type(Image) ~= 'string' or Image == '' then
		return '';
	end;

	if string.match(Image, '^%d+$') then
		return 'rbxassetid://' .. Image;
	end;

	return Image;
end;

---Black or white, whichever stays readable on top of Color.
---@param Color Color3
---@return Color3
function Library:GetContrastColor(Color)
	local Luminance = (0.299 * Color.R) + (0.587 * Color.G) + (0.114 * Color.B);
	return Luminance > 0.55 and Color3.new(0, 0, 0) or Color3.fromRGB(255, 255, 255);
end;

---Hex string without the leading hash, for RichText font colour tags.
---Written out by hand rather than Color3:ToHex so older clients still work.
---@param Color Color3
---@return string
function Library:ColorToHex(Color)
	return string.format(
		'%02X%02X%02X',
		math.floor((Color.R * 255) + 0.5),
		math.floor((Color.G * 255) + 0.5),
		math.floor((Color.B * 255) + 0.5)
	);
end;

---Neutralise markup in text that is about to be dropped into a RichText label.
---@param Text string
---@return string
function Library:EscapeRichText(Text)
	Text = tostring(Text or '');
	Text = string.gsub(Text, '&', '&amp;');
	Text = string.gsub(Text, '<', '&lt;');
	Text = string.gsub(Text, '>', '&gt;');
	Text = string.gsub(Text, '"', '&quot;');
	Text = string.gsub(Text, "'", '&apos;');
	return Text;
end;

---Wrap Text in a RichText colour tag.
---@param Text string
---@param Color Color3
---@return string
function Library:ColorRichText(Text, Color)
	return string.format('<font color="#%s">%s</font>', Library:ColorToHex(Color), Library:EscapeRichText(Text));
end;

-- < Background brightness >
-- Full screen dim that sits behind the window (ZIndex 0) so the menu reads
-- clearly against a busy game. Oversized on Y so it also covers the topbar
-- inset, which the ScreenGui itself does not reach.
-- Tracked so a rapid toggle off/on does not leave two fades fighting.
local DimTween = nil;

Library.BackgroundDim = Library:Create('Frame', {
	Name = 'BackgroundDim';
	BackgroundColor3 = Library.BackgroundDimColor;
	BackgroundTransparency = 1;
	BorderSizePixel = 0;
	Position = UDim2.fromOffset(0, -80);
	Size = UDim2.new(1, 0, 1, 160);
	Visible = false;
	ZIndex = 0;
	Parent = ScreenGui;
});

---Repaint / refade the dim from the current Library state.
---@param Instant boolean? skip the tween
function Library:UpdateBackgroundDim(Instant)
	local Dim = Library.BackgroundDim;

	if not Dim then
		return;
	end;

	local Brightness = math.clamp(tonumber(Library.BackgroundBrightness) or 0, 0, 1);
	local Shown = _UI_IS_VISIBLE and Brightness > 0;
	local Target = Shown and (1 - Brightness) or 1;

	Dim.BackgroundColor3 = Library.BackgroundDimColor;

	if Shown then
		Dim.Visible = true;
	end;

	local FadeTime = Library.MenuFadeTime or 0.2;

	-- Dropped unconditionally: a slider driving this while the menu fade is
	-- still running would otherwise be overwritten frame by frame.
	if DimTween then
		DimTween:Cancel();
		DimTween = nil;
	end;

	if Instant or FadeTime <= 0 then
		Dim.BackgroundTransparency = Target;
		Dim.Visible = Shown;
		return;
	end;

	DimTween = TweenService:Create(Dim, TweenInfo.new(FadeTime, Enum.EasingStyle.Linear), {
		BackgroundTransparency = Target;
	});

	DimTween.Completed:Connect(function(State)
		if State ~= Enum.PlaybackState.Completed then
			return;
		end;

		Dim.Visible = _UI_IS_VISIBLE and (tonumber(Library.BackgroundBrightness) or 0) > 0;
	end);

	DimTween:Play();
end;

---Set how strongly the screen behind the menu is dimmed. 0 = off, 1 = solid.
---@param Value number
function Library:SetBackgroundBrightness(Value)
	Library.BackgroundBrightness = math.clamp(tonumber(Value) or 0, 0, 1);
	Library:UpdateBackgroundDim(true);
end;

---Recolor the dim. Near black by default.
---@param Color Color3
function Library:SetBackgroundDimColor(Color)
	Library.BackgroundDimColor = Color;
	Library:UpdateBackgroundDim(true);
end;

-- < Snow >
-- Falling dots over the dim. Created after BackgroundDim so that, on an equal
-- ZIndex, tree order puts the flakes above the dim while both stay under the
-- window at ZIndex 1. Pooled and driven by one RenderStepped connection.
local SnowFlakes = { };
local SnowConnection = nil;

Library.SnowHolder = Library:Create('Frame', {
	Name = 'SnowHolder';
	BackgroundTransparency = 1;
	BorderSizePixel = 0;
	Position = UDim2.fromOffset(0, -80);
	Size = UDim2.new(1, 0, 1, 160);
	ClipsDescendants = true;
	Visible = false;
	ZIndex = 0;
	Parent = ScreenGui;
});

---Randomise one flake. Called on spawn and every time one is recycled.
---@param Flake table
---@param Height number viewport height in pixels
---@param FromTop boolean start it above the top edge instead of anywhere on screen
local function resetSnowFlake(Flake, Height, FromTop)
	local SizeMin = math.max(tonumber(Library.SnowSizeMin) or 1, 1);
	local SizeMax = math.max(tonumber(Library.SnowSizeMax) or 3, SizeMin);
	local Diameter = math.random(SizeMin, SizeMax);

	Flake.x = math.random() * 100;
	Flake.y = FromTop and -(math.random(4, 60)) or (math.random() * math.max(Height, 1));
	Flake.size = Diameter;
	Flake.speed = 0.45 + (math.random() * 0.95);
	Flake.drift = (math.random() * 2) - 1;
	Flake.phase = math.random() * 6.28318;
	Flake.wobble = 0.6 + (math.random() * 1.4);
	Flake.alpha = 0.15 + (math.random() * 0.45);

	Flake.instance.Size = UDim2.fromOffset(Diameter, Diameter);
end;

---Grow or shrink the pool to match Library.SnowCount.
local function syncSnowPool()
	local Target = math.clamp(math.floor(tonumber(Library.SnowCount) or 0), 0, 400);
	local Height = math.max(Library.SnowHolder.AbsoluteSize.Y, 1);

	while #SnowFlakes > Target do
		local Flake = table.remove(SnowFlakes);
		Flake.instance:Destroy();
	end;

	while #SnowFlakes < Target do
		local Dot = Library:Create('Frame', {
			Name = 'Flake';
			BackgroundColor3 = Library.SnowColor;
			BorderSizePixel = 0;
			Size = UDim2.fromOffset(2, 2);
			ZIndex = 0;
			Parent = Library.SnowHolder;
		});

		Library:Create('UICorner', {
			CornerRadius = UDim.new(1, 0);
			Parent = Dot;
		});

		local Flake = { instance = Dot };
		resetSnowFlake(Flake, Height, false);
		table.insert(SnowFlakes, Flake);
	end;
end;

---One frame of fall. Positions are kept as percent on X and pixels on Y so a
---window resize never bunches the flakes into a column.
---@param Delta number
local function stepSnow(Delta)
	local Holder = Library.SnowHolder;
	local Height = Holder.AbsoluteSize.Y;

	if Height <= 0 then
		return;
	end;

	local Speed = tonumber(Library.SnowSpeed) or 34;
	local Drift = tonumber(Library.SnowDrift) or 16;
	local Clock = os.clock();

	for _, Flake in next, SnowFlakes do
		Flake.y = Flake.y + (Speed * Flake.speed * Delta);

		if Flake.y > Height + 8 then
			resetSnowFlake(Flake, Height, true);
		end;

		local Sway = math.sin((Clock * Flake.wobble) + Flake.phase) * Drift * Flake.drift;

		Flake.instance.Position = UDim2.new(Flake.x / 100, Sway, 0, Flake.y);
		Flake.instance.BackgroundColor3 = Library.SnowColor;
		Flake.instance.BackgroundTransparency = math.clamp((tonumber(Library.SnowTransparency) or 0.35) + Flake.alpha, 0, 1);
	end;
end;

---Show or hide the overlay from the current Library state and keep exactly one
---RenderStepped connection alive.
function Library:UpdateSnow()
	local Holder = Library.SnowHolder;

	if not Holder then
		return;
	end;

	local Shown = _UI_IS_VISIBLE and Library.SnowEnabled == true and (tonumber(Library.SnowCount) or 0) > 0;

	Holder.Visible = Shown;

	if not Shown then
		if SnowConnection then
			SnowConnection:Disconnect();
			SnowConnection = nil;
		end;

		return;
	end;

	syncSnowPool();

	if not SnowConnection then
		SnowConnection = RenderStepped:Connect(stepSnow);
	end;
end;

---@param Bool boolean
function Library:SetSnow(Bool)
	Library.SnowEnabled = (not not Bool);
	Library:UpdateSnow();
end;

---@param Count number flakes on screen, clamped to 400
function Library:SetSnowCount(Count)
	Library.SnowCount = math.clamp(math.floor(tonumber(Count) or 0), 0, 400);
	Library:UpdateSnow();
end;

---@param Speed number pixels per second at the base rate
function Library:SetSnowSpeed(Speed)
	Library.SnowSpeed = math.max(tonumber(Speed) or 0, 0);
end;

---@param Color Color3
function Library:SetSnowColor(Color)
	Library.SnowColor = Color;
end;

---@param Value number 0 = solid, 1 = invisible
function Library:SetSnowTransparency(Value)
	Library.SnowTransparency = math.clamp(tonumber(Value) or 0, 0, 1);
end;

---Drop every flake and stop the loop. Called from Library:Unload.
function Library:ClearSnow()
	if SnowConnection then
		SnowConnection:Disconnect();
		SnowConnection = nil;
	end;

	for _, Flake in next, SnowFlakes do
		Flake.instance:Destroy();
	end;

	table.clear(SnowFlakes);

	if Library.SnowHolder then
		Library.SnowHolder.Visible = false;
	end;
end;

-- < Custom cursor >
-- Drawn every frame while the menu is open and Library.CustomCursor is set, so
-- flipping the flag at runtime takes effect immediately.
local CursorOutline = Library:Create('ImageLabel', {
	Name = 'CursorOutline';
	Image = Library:ResolveImage(Library.CustomCursorImage);
	ImageColor3 = Color3.new(0, 0, 0);
	BackgroundTransparency = 1;
	Size = UDim2.fromOffset(19, 19);
	Rotation = -45;
	Visible = false;
	ZIndex = 99;
	Parent = ScreenGui;
});

local CursorImage = Library:Create('ImageLabel', {
	Name = 'Cursor';
	Image = Library:ResolveImage(Library.CustomCursorImage);
	BackgroundTransparency = 1;
	Size = UDim2.fromOffset(17, 17);
	Rotation = -45;
	Visible = false;
	ZIndex = 100;
	Parent = ScreenGui;
});

Library.Cursor = CursorImage;
Library.CursorOutline = CursorOutline;

-- Remembered so the game's own cursor can be handed back untouched.
local SystemCursorState = nil;

---Give the game its cursor back and hide ours.
function Library:RestoreCursor()
	if SystemCursorState ~= nil then
		InputService.MouseIconEnabled = SystemCursorState;
		SystemCursorState = nil;
	end;

	CursorImage.Visible = false;
	CursorOutline.Visible = false;
end;

Library:GiveSignal(RenderStepped:Connect(function()
	if not (_UI_IS_VISIBLE and Library.CustomCursor) then
		if SystemCursorState ~= nil or CursorImage.Visible then
			Library:RestoreCursor();
		end;

		return;
	end;

	if SystemCursorState == nil then
		SystemCursorState = InputService.MouseIconEnabled;
	end;

	InputService.MouseIconEnabled = false;

	local Location = InputService:GetMouseLocation();
	local Point = UDim2.fromOffset(Location.X, Location.Y - GuiService:GetGuiInset().Y - 1);
	local Image = Library:ResolveImage(Library.CustomCursorImage);

	if CursorImage.Image ~= Image then
		CursorImage.Image = Image;
		CursorOutline.Image = Image;
	end;

	CursorImage.ImageColor3 = Library.AccentColor;
	CursorImage.Position = Point;
	CursorOutline.Position = Point - UDim2.fromOffset(1, 1);

	CursorImage.Visible = true;
	CursorOutline.Visible = true;
end));

---Toggle the custom cursor. Scripts wire this to a toggle.
---@param Bool boolean
function Library:SetCustomCursor(Bool)
	Library.CustomCursor = (not not Bool);

	if not Library.CustomCursor then
		Library:RestoreCursor();
	end;
end;

---Swap the cursor art. Accepts a bare id or a full content string.
---@param Image string | number
function Library:SetCustomCursorImage(Image)
	Library.CustomCursorImage = Image;

	local Resolved = Library:ResolveImage(Image);
	CursorImage.Image = Resolved;
	CursorOutline.Image = Resolved;
end;

local _callbacks = { };
function Library:BindToInput(key, callback) -- adding so there isnt 869 quintillion connections
	_callbacks[key] = _callbacks[key] or { };
	table.insert(_callbacks[key], callback);
end;

Library:GiveSignal(InputService.InputBegan:Connect(function(input, ...)
	if (not _UI_IS_VISIBLE) then
		return;
	end;
	local callbacks = _callbacks[input.KeyCode] or _callbacks[input.UserInputType];
	if (callbacks) then
		for _, callback in pairs(callbacks) do
			task.spawn(callback, input, ...);
		end;
	end;
end));

function Library:AddContextMenu(DisplayFrame, hitbox)
	local ContextMenu = { Visible = false; }
	ContextMenu.Options = {}
	ContextMenu.Container = Library:Create('Frame', {
		BorderColor3 = Color3.new(),
		ZIndex = 14,

		Visible = false,
		Parent = ScreenGui
	})

	ContextMenu.Inner = Library:Create('Frame', {
		BackgroundColor3 = Library.BackgroundColor;
		BorderColor3 = Library.OutlineColor;
		BorderMode = Enum.BorderMode.Inset;
		Size = UDim2.fromScale(1, 1);
		ZIndex = 15;
		Parent = ContextMenu.Container;
	});

	Library:Create('UIListLayout', {
		Name = 'Layout',
		HorizontalAlignment = Enum.HorizontalAlignment.Left;
		FillDirection = Enum.FillDirection.Vertical;
		SortOrder = Enum.SortOrder.LayoutOrder;
		Parent = ContextMenu.Inner;
	});

	Library:Create('UIPadding', {
		Name = 'Padding',
		PaddingLeft = UDim.new(0, 0),
		Parent = ContextMenu.Inner,
	});

	local function updateMenuPosition()
		ContextMenu.Container.Position = UDim2.fromOffset(
			(DisplayFrame.AbsolutePosition.X + DisplayFrame.AbsoluteSize.X) + 4,
			DisplayFrame.AbsolutePosition.Y + 1
		)
	end

	local function updateMenuSize()
		local menuWidth = 60
		for i, label in next, ContextMenu.Inner:GetChildren() do
			if label:IsA('TextLabel') then
				menuWidth = math.max(menuWidth, label.TextBounds.X)
			end
		end

		ContextMenu.Container.Size = UDim2.fromOffset(
			menuWidth + 8,
			ContextMenu.Inner.Layout.AbsoluteContentSize.Y + 4
		)
	end

	local _visible = false;
	--DisplayFrame:GetPropertyChangedSignal('AbsolutePosition'):Connect(updateMenuPosition)
	--ContextMenu.Inner.Layout:GetPropertyChangedSignal('AbsoluteContentSize'):Connect(updateMenuSize);

	(hitbox or DisplayFrame).InputBegan:Connect(function(Input)
		if Input.UserInputType == Enum.UserInputType.MouseButton1 and not Library:MouseIsOverOpenedFrame() then
			return ContextMenu:Hide();
		elseif Input.UserInputType == Enum.UserInputType.MouseButton2 and not Library:MouseIsOverOpenedFrame() then
			return ContextMenu:Show();
		end
	end);

	Library:BindToInput(Enum.UserInputType.MouseButton1, function()
		if _visible and not Library:IsMouseOverFrame(ContextMenu.Container) then
			ContextMenu:Hide()
		end;
	end);
	Library:BindToInput(Enum.UserInputType.MouseButton2, function()
		if _visible and not Library:IsMouseOverFrame(ContextMenu.Container) and not Library:IsMouseOverFrame(DisplayFrame) then
			ContextMenu:Hide()
		end;
	end);

	task.spawn(updateMenuPosition)
	task.spawn(updateMenuSize)

	Library:AddToRegistry(ContextMenu.Inner, {
		BackgroundColor3 = 'BackgroundColor';
		BorderColor3 = 'OutlineColor';
	});

	function ContextMenu:Show()
		updateMenuPosition();
		updateMenuSize();
		_visible = true;
		
		for Frame, Val in next, Library.OpenedFrames do
			if Frame.Name == 'Color' then
				Frame.Visible = false;
				Library.OpenedFrames[Frame] = nil;
			end;
		end;
		
		self.Container.Visible = true
		Library.OpenedFrames[ContextMenu.Container] = true;
	end

	function ContextMenu:Hide()
		_visible = false;
		self.Container.Visible = false
		task.wait();
		Library.OpenedFrames[ContextMenu.Container] = nil;
	end

	function ContextMenu:AddOption(Str, Callback)
		if type(Callback) ~= 'function' then
			Callback = function() end
		end

		local Button = Library:CreateLabel({
			Active = false;
			Size = UDim2.new(1, 0, 0, 15);
			TextSize = 13;
			Text = Str;
			ZIndex = 16;
			Parent = self.Inner;
			TextXAlignment = Enum.TextXAlignment.Center,
		});

		Library:OnHighlight(Button, Button, 
			{ TextColor3 = 'AccentColor' },
			{ TextColor3 = 'FontColor' }
		);

		Button.InputBegan:Connect(function(Input)
			if Input.UserInputType ~= Enum.UserInputType.MouseButton1 then
				return
			end
			Callback()
		end)
		return Button;
	end
	return ContextMenu;
end;

Library:GiveSignal(ScreenGui.DescendantRemoving:Connect(function(Instance)
	if _UI_IS_VISIBLE and Library.RegistryMap[Instance] then
		Library:RemoveFromRegistry(Instance);
	end;
end))

local BaseAddons = {};

do
	local Funcs = {};

	function Funcs:AddColorPicker(Idx, Info)
		local ToggleParent = self;
		local ToggleLabel = self.TextLabel;
		-- local Container = self.Container;

		assert(Info.Default, 'AddColorPicker: Missing default value.');

		local ColorPicker = {
			Value = Info.Default;
			Transparency = Info.Transparency or 0;
			Rainbow = not not Info.Rainbow;
			Type = 'ColorPicker';
			Title = type(Info.Title) == 'string' and Info.Title or 'Color picker',
			HasTransparency = not not Info.Transparency;
			Callback = Info.Callback or function(Color) end;
			Parent = ToggleParent;
			Idx = Idx;
		};

		function ColorPicker:SetHSVFromRGB(Color)
			local H, S, V = Color3.toHSV(Color);

			ColorPicker.Hue = H;
			ColorPicker.Sat = S;
			ColorPicker.Vib = V;
		end;

		ColorPicker:SetHSVFromRGB(ColorPicker.Value);

		local DisplayFrame = Library:Create('Frame', {
			BackgroundColor3 = ColorPicker.Value;
			BorderColor3 = Library:GetDarkerColor(ColorPicker.Value);
			BorderMode = Enum.BorderMode.Inset;
			Size = UDim2.new(0, 28, 0, 14);
			ZIndex = 6;
			Parent = ToggleLabel;
		});

		-- Transparency image taken from https://github.com/matas3535/SplixPrivateDrawingLibrary/blob/main/Library.lua cus i'm lazy
		local CheckerFrame = Library:Create('ImageLabel', {
			BorderSizePixel = 0;
			Size = UDim2.new(0, 27, 0, 13);
			ZIndex = 5;
			Image = 'http://www.roblox.com/asset/?id=12977615774';
			Visible = not not Info.Transparency;
			Parent = DisplayFrame;
		});

		-- 1/16/23
		-- Rewrote this to be placed inside the Library ScreenGui
		-- There was some issue which caused RelativeOffset to be way off
		-- Thus the color picker would never show

		local PickerFrameOuter = Library:Create('Frame', {
			Name = 'Color';
			BackgroundColor3 = Color3.new(1, 1, 1);
			BorderColor3 = Color3.new(0, 0, 0);
			Position = UDim2.fromOffset(DisplayFrame.AbsolutePosition.X, DisplayFrame.AbsolutePosition.Y + 18),
			Size = UDim2.fromOffset(230, Info.Transparency and 289 or 271);
			Visible = false;
			ZIndex = 15;
			Parent = ScreenGui,
		});

		DisplayFrame:GetPropertyChangedSignal('AbsolutePosition'):Connect(function()
			PickerFrameOuter.Position = UDim2.fromOffset(DisplayFrame.AbsolutePosition.X, DisplayFrame.AbsolutePosition.Y + 18);
		end)

		local PickerFrameInner = Library:Create('Frame', {
			BackgroundColor3 = Library.BackgroundColor;
			BorderColor3 = Library.OutlineColor;
			BorderMode = Enum.BorderMode.Inset;
			Size = UDim2.new(1, 0, 1, 0);
			ZIndex = 16;
			Parent = PickerFrameOuter;
		});

		local Highlight = Library:Create('Frame', {
			BackgroundColor3 = Library.AccentColor;
			BorderSizePixel = 0;
			Size = UDim2.new(1, 0, 0, 2);
			ZIndex = 17;
			Parent = PickerFrameInner;
		});

		local SatVibMapOuter = Library:Create('Frame', {
			BorderColor3 = Color3.new(0, 0, 0);
			Position = UDim2.new(0, 4, 0, 25);
			Size = UDim2.new(0, 200, 0, 200);
			ZIndex = 17;
			Parent = PickerFrameInner;
		});

		local SatVibMapInner = Library:Create('Frame', {
			BackgroundColor3 = Library.BackgroundColor;
			BorderColor3 = Library.OutlineColor;
			BorderMode = Enum.BorderMode.Inset;
			Size = UDim2.new(1, 0, 1, 0);
			ZIndex = 18;
			Parent = SatVibMapOuter;
		});

		local SatVibMap = Library:Create('ImageLabel', {
			BorderSizePixel = 0;
			Size = UDim2.new(1, 0, 1, 0);
			ZIndex = 18;
			Image = 'rbxassetid://4155801252';
			Parent = SatVibMapInner;
		});

		local CursorOuter = Library:Create('ImageLabel', {
			AnchorPoint = Vector2.new(0.5, 0.5);
			Size = UDim2.new(0, 6, 0, 6);
			BackgroundTransparency = 1;
			Image = 'http://www.roblox.com/asset/?id=9619665977';
			ImageColor3 = Color3.new(0, 0, 0);
			ZIndex = 19;
			Parent = SatVibMap;
		});

		local CursorInner = Library:Create('ImageLabel', {
			Size = UDim2.new(0, CursorOuter.Size.X.Offset - 2, 0, CursorOuter.Size.Y.Offset - 2);
			Position = UDim2.new(0, 1, 0, 1);
			BackgroundTransparency = 1;
			Image = 'http://www.roblox.com/asset/?id=9619665977';
			ZIndex = 20;
			Parent = CursorOuter;
		})

		local HueSelectorOuter = Library:Create('Frame', {
			BorderColor3 = Color3.new(0, 0, 0);
			Position = UDim2.new(0, 208, 0, 25);
			Size = UDim2.new(0, 15, 0, 200);
			ZIndex = 17;
			Parent = PickerFrameInner;
		});

		local HueSelectorInner = Library:Create('Frame', {
			BackgroundColor3 = Color3.new(1, 1, 1);
			BorderSizePixel = 0;
			Size = UDim2.new(1, 0, 1, 0);
			ZIndex = 18;
			Parent = HueSelectorOuter;
		});

		local HueCursor = Library:Create('Frame', { 
			BackgroundColor3 = Color3.new(1, 1, 1);
			AnchorPoint = Vector2.new(0, 0.5);
			BorderColor3 = Color3.new(0, 0, 0);
			Size = UDim2.new(1, 0, 0, 1);
			ZIndex = 18;
			Parent = HueSelectorInner;
		});

		local HueBoxOuter = Library:Create('Frame', {
			BorderColor3 = Color3.new(0, 0, 0);
			Position = UDim2.fromOffset(4, 228),
			Size = UDim2.new(0.5, -6, 0, 20),
			ZIndex = 18,
			Parent = PickerFrameInner;
		});

		local HueBoxInner = Library:Create('Frame', {
			BackgroundColor3 = Library.MainColor;
			BorderColor3 = Library.OutlineColor;
			BorderMode = Enum.BorderMode.Inset;
			Size = UDim2.new(1, 0, 1, 0);
			ZIndex = 18,
			Parent = HueBoxOuter;
		});

		Library:Create('UIGradient', {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(212, 212, 212))
			});
			Rotation = 90;
			Parent = HueBoxInner;
		});

		local HueBox = Library:Create('TextBox', {
			BackgroundTransparency = 1;
			Position = UDim2.new(0, 5, 0, 0);
			Size = UDim2.new(1, -5, 1, 0);
			Font = Library.Font;
			PlaceholderColor3 = Color3.fromRGB(190, 190, 190);
			PlaceholderText = 'Hex color',
			Text = '#FFFFFF',
			TextColor3 = Library.FontColor;
			TextSize = 14;
			TextStrokeTransparency = 0;
			TextXAlignment = Enum.TextXAlignment.Left;
			ZIndex = 20,
			Parent = HueBoxInner;
		});

		Library:ApplyTextStroke(HueBox);

		local RgbBoxBase = Library:Create(HueBoxOuter:Clone(), {
			Position = UDim2.new(0.5, 2, 0, 228),
			Size = UDim2.new(0.5, -6, 0, 20),
			Parent = PickerFrameInner
		});

		local RgbBox = Library:Create(RgbBoxBase.Frame:FindFirstChild('TextBox'), {
			Text = '255, 255, 255',
			PlaceholderText = 'RGB color',
			TextColor3 = Library.FontColor
		});

		local TransparencyBoxOuter, TransparencyBoxInner, TransparencyCursor;

		if Info.Transparency then 
			TransparencyBoxOuter = Library:Create('Frame', {
				BorderColor3 = Color3.new(0, 0, 0);
				Position = UDim2.fromOffset(4, 251);
				Size = UDim2.new(1, -8, 0, 15);
				ZIndex = 19;
				Parent = PickerFrameInner;
			});

			TransparencyBoxInner = Library:Create('Frame', {
				BackgroundColor3 = ColorPicker.Value;
				BorderColor3 = Library.OutlineColor;
				BorderMode = Enum.BorderMode.Inset;
				Size = UDim2.new(1, 0, 1, 0);
				ZIndex = 19;
				Parent = TransparencyBoxOuter;
			});

			Library:AddToRegistry(TransparencyBoxInner, { BorderColor3 = 'OutlineColor' });

			Library:Create('ImageLabel', {
				BackgroundTransparency = 1;
				Size = UDim2.new(1, 0, 1, 0);
				Image = 'http://www.roblox.com/asset/?id=12978095818';
				ZIndex = 20;
				Parent = TransparencyBoxInner;
			});

			TransparencyCursor = Library:Create('Frame', { 
				BackgroundColor3 = Color3.new(1, 1, 1);
				AnchorPoint = Vector2.new(0.5, 0);
				BorderColor3 = Color3.new(0, 0, 0);
				Size = UDim2.new(0, 1, 1, 0);
				ZIndex = 21;
				Parent = TransparencyBoxInner;
			});
		end;

		local DisplayLabel = Library:CreateLabel({
			Size = UDim2.new(1, 0, 0, 14);
			Position = UDim2.fromOffset(5, 5);
			TextXAlignment = Enum.TextXAlignment.Left;
			TextSize = 14;
			Text = ColorPicker.Title,--Info.Default;
			TextWrapped = false;
			ZIndex = 16;
			Parent = PickerFrameInner;
		});

		-- Rainbow row sits below the transparency bar when there is one.
		local RainbowY = Info.Transparency and 269 or 251;

		local RainbowOuter = Library:Create('Frame', {
			BackgroundColor3 = Color3.new(0, 0, 0);
			BorderColor3 = Color3.new(0, 0, 0);
			Position = UDim2.fromOffset(5, RainbowY);
			Size = UDim2.new(0, 13, 0, 13);
			ZIndex = 19;
			Parent = PickerFrameInner;
		});

		Library:AddToRegistry(RainbowOuter, { BorderColor3 = 'Black'; });

		local RainbowInner = Library:Create('Frame', {
			BackgroundColor3 = Library.MainColor;
			BorderColor3 = Library.OutlineColor;
			BorderMode = Enum.BorderMode.Inset;
			Size = UDim2.new(1, 0, 1, 0);
			ZIndex = 20;
			Parent = RainbowOuter;
		});

		Library:AddToRegistry(RainbowInner, {
			BackgroundColor3 = 'MainColor';
			BorderColor3 = 'OutlineColor';
		});

		local RainbowLabel = Library:CreateLabel({
			Position = UDim2.fromOffset(23, RainbowY - 1);
			Size = UDim2.new(1, -27, 0, 14);
			TextSize = 14;
			Text = 'Rainbow';
			TextXAlignment = Enum.TextXAlignment.Left;
			ZIndex = 20;
			Parent = PickerFrameInner;
		});

		-- One hitbox covering the box and its label.
		local RainbowRegion = Library:Create('Frame', {
			BackgroundTransparency = 1;
			Position = UDim2.fromOffset(4, RainbowY - 1);
			Size = UDim2.new(0, 100, 0, 15);
			ZIndex = 21;
			Parent = PickerFrameInner;
		});

		Library:OnHighlight(RainbowRegion, RainbowOuter,
			{ BorderColor3 = 'AccentColor' },
			{ BorderColor3 = 'Black' }
		);

		---Turn rainbow cycling on or off for this picker.
		---@param Bool boolean
		function ColorPicker:SetRainbow(Bool)
			ColorPicker.Rainbow = not not Bool;

			RainbowInner.BackgroundColor3 = ColorPicker.Rainbow and Library.AccentColor or Library.MainColor;
			RainbowInner.BorderColor3 = ColorPicker.Rainbow and Library.AccentColorDark or Library.OutlineColor;

			local Reg = Library.RegistryMap[RainbowInner];
			if Reg then
				Reg.Properties.BackgroundColor3 = ColorPicker.Rainbow and 'AccentColor' or 'MainColor';
				Reg.Properties.BorderColor3 = ColorPicker.Rainbow and 'AccentColorDark' or 'OutlineColor';
			end;

			if ColorPicker.Rainbow then
				Library.RainbowPickers[ColorPicker] = true;
			else
				Library.RainbowPickers[ColorPicker] = nil;
			end;
		end;

		RainbowRegion.InputBegan:Connect(function(Input)
			if Input.UserInputType == Enum.UserInputType.MouseButton1 then
				ColorPicker:SetRainbow(not ColorPicker.Rainbow);
				Library:AttemptSave();
			end;
		end);

		local ContextMenu = Library:AddContextMenu(DisplayFrame);
		ContextMenu:AddOption('Make gradient', function()
			local colorpickers = { };
			for _, addon in ToggleParent.Addons do
				if (addon.Type == "ColorPicker") then
					table.insert(colorpickers, addon);
				end;
			end;
			if (#colorpickers < 3) then
				ContextMenu:Hide();
				return Library:Notify('not enough colors for a gradient.', 2);
			end;
			
			local start, finish = colorpickers[1].Value, colorpickers[#colorpickers].Value;
			
			for i = 2, #colorpickers - 1 do
				local addon = colorpickers[i];
				addon:SetValueRGB(start:Lerp(finish, i/#colorpickers), addon.Transparency);
			end;
			
			Library:Notify('created gradient!', 2);
			ContextMenu:Hide();
		end)
		ContextMenu:AddOption('Match color', function()
			local colorpickers = { };
			for _, addon in ToggleParent.Addons do
				if (addon.Type == "ColorPicker") then
					table.insert(colorpickers, addon);
				end;
			end;
			for _, addon in colorpickers do
				addon:SetValueRGB(ColorPicker.Value, addon.Transparency);
			end;
			Library:Notify('matched all colors!', 2);
			ContextMenu:Hide();
		end)
		ContextMenu:AddOption('Copy color', function()
			Library.ColorClipboard = ColorPicker;--.Value
			Library:Notify('Copied color!', 2)
			ContextMenu:Hide();
		end)

		ContextMenu:AddOption('Paste color', function()
			if not Library.ColorClipboard then
				return Library:Notify('You have not copied a color!', 2)
			end
			ColorPicker:SetValueRGB(Library.ColorClipboard.Value, Library.ColorClipboard.Transparency);
			ContextMenu:Hide();
		end)

		--[[ContextMenu:AddOption('Copy HEX', function()
			pcall(setclipboard, ColorPicker.Value:ToHex())
			Library:Notify('Copied hex code to clipboard!', 2)
		end)

		ContextMenu:AddOption('Copy RGB', function()
			pcall(setclipboard, table.concat({ math.floor(ColorPicker.Value.R * 255), math.floor(ColorPicker.Value.G * 255), math.floor(ColorPicker.Value.B * 255) }, ', '))
			Library:Notify('Copied RGB values to clipboard!', 2)
		end)]]
		ContextMenu:AddOption('Copy Flag', function()
			pcall(setclipboard, ColorPicker.Idx)
			task.wait(); Library:Notify('Copied flag to clipboard!', 2);
			ContextMenu:Hide();
		end);
		Library:AddToRegistry(PickerFrameInner, { BackgroundColor3 = 'BackgroundColor'; BorderColor3 = 'OutlineColor'; });
		Library:AddToRegistry(Highlight, { BackgroundColor3 = 'AccentColor'; });
		Library:AddToRegistry(SatVibMapInner, { BackgroundColor3 = 'BackgroundColor'; BorderColor3 = 'OutlineColor'; });

		Library:AddToRegistry(HueBoxInner, { BackgroundColor3 = 'MainColor'; BorderColor3 = 'OutlineColor'; });
		Library:AddToRegistry(RgbBoxBase.Frame, { BackgroundColor3 = 'MainColor'; BorderColor3 = 'OutlineColor'; });
		Library:AddToRegistry(RgbBox, { TextColor3 = 'FontColor', });
		Library:AddToRegistry(HueBox, { TextColor3 = 'FontColor', });

		local SequenceTable = {};

		for Hue = 0, 1, 0.1 do
			table.insert(SequenceTable, ColorSequenceKeypoint.new(Hue, Color3.fromHSV(Hue, 1, 1)));
		end;

		local HueSelectorGradient = Library:Create('UIGradient', {
			Color = ColorSequence.new(SequenceTable);
			Rotation = 90;
			Parent = HueSelectorInner;
		});

		HueBox.FocusLost:Connect(function(enter)
			if enter then
				local success, result = pcall(Color3.fromHex, HueBox.Text)
				if success and typeof(result) == 'Color3' then
					ColorPicker.Hue, ColorPicker.Sat, ColorPicker.Vib = Color3.toHSV(result)
				end
			end

			ColorPicker:Display()
		end)

		RgbBox.FocusLost:Connect(function(enter)
			if enter then
				local r, g, b = RgbBox.Text:match('(%d+),%s*(%d+),%s*(%d+)')
				if r and g and b then
					ColorPicker.Hue, ColorPicker.Sat, ColorPicker.Vib = Color3.toHSV(Color3.fromRGB(r, g, b))
				end
			end

			ColorPicker:Display()
		end)

		function ColorPicker:Display()
			ColorPicker.Value = Color3.fromHSV(ColorPicker.Hue, ColorPicker.Sat, ColorPicker.Vib);
			SatVibMap.BackgroundColor3 = Color3.fromHSV(ColorPicker.Hue, 1, 1);

			Library:Create(DisplayFrame, {
				BackgroundColor3 = ColorPicker.Value;
				BackgroundTransparency = ColorPicker.Transparency;
				BorderColor3 = Library:GetDarkerColor(ColorPicker.Value);
			});

			if TransparencyBoxInner then
				TransparencyBoxInner.BackgroundColor3 = ColorPicker.Value;
				TransparencyCursor.Position = UDim2.new(1 - ColorPicker.Transparency, 0, 0, 0);
			end;

			CursorOuter.Position = UDim2.new(ColorPicker.Sat, 0, 1 - ColorPicker.Vib, 0);
			HueCursor.Position = UDim2.new(0, 0, ColorPicker.Hue, 0);

			if not HueBox:IsFocused() then
				HueBox.Text = '#' .. ColorPicker.Value:ToHex()
			end;

			if not RgbBox:IsFocused() then
				RgbBox.Text = table.concat({ math.floor(ColorPicker.Value.R * 255), math.floor(ColorPicker.Value.G * 255), math.floor(ColorPicker.Value.B * 255) }, ', ')
			end;

			Library:SafeCallback(ColorPicker.Callback, ColorPicker.Value);
			Library:SafeCallback(ColorPicker.Changed, ColorPicker.Value);
		end;

		function ColorPicker:OnChanged(Func)
			ColorPicker.Changed = Func;
			Func(ColorPicker.Value)
		end;

		local _visible = false;
		function ColorPicker:Show()
			_visible = true;
			for Frame, Val in next, Library.OpenedFrames do
				if Frame.Name == 'Color' then
					Frame.Visible = false;
					Library.OpenedFrames[Frame] = nil;
				end;
			end;

			PickerFrameOuter.Visible = true;
			Library.OpenedFrames[PickerFrameOuter] = true;
		end;

		function ColorPicker:Hide()
			_visible = false;
			PickerFrameOuter.Visible = false;
			Library.OpenedFrames[PickerFrameOuter] = nil;
		end;

		function ColorPicker:SetValue(HSV, Transparency, Rainbow)
			local Color = Color3.fromHSV(HSV[1], HSV[2], HSV[3]);

			ColorPicker.Transparency = Transparency or 0;
			if Rainbow ~= nil then
				ColorPicker:SetRainbow(Rainbow);
			end;
			ColorPicker:SetHSVFromRGB(Color);
			ColorPicker:Display();
		end;

		function ColorPicker:Remove()
			Library.RainbowPickers[ColorPicker] = nil;
			Options[Idx] = nil;
			table.clear(ColorPicker);
		end;

		function ColorPicker:SetValueRGB(Color, Transparency, Rainbow)
			ColorPicker.Transparency = Transparency or 0;
			if Rainbow ~= nil then
				ColorPicker:SetRainbow(Rainbow);
			end;
			ColorPicker:SetHSVFromRGB(Color);
			ColorPicker:Display();
		end;

		SatVibMap.InputBegan:Connect(function(Input)
			if Input.UserInputType == Enum.UserInputType.MouseButton1 then
				if ColorPicker.Rainbow then
					ColorPicker:SetRainbow(false);
				end;

				while InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) do
					local MinX = SatVibMap.AbsolutePosition.X;
					local MaxX = MinX + SatVibMap.AbsoluteSize.X;
					local MouseX = math.clamp(Mouse.X, MinX, MaxX);

					local MinY = SatVibMap.AbsolutePosition.Y;
					local MaxY = MinY + SatVibMap.AbsoluteSize.Y;
					local MouseY = math.clamp(Mouse.Y, MinY, MaxY);

					ColorPicker.Sat = (MouseX - MinX) / (MaxX - MinX);
					ColorPicker.Vib = 1 - ((MouseY - MinY) / (MaxY - MinY));
					ColorPicker:Display();

					RenderStepped:Wait();
				end;

				Library:AttemptSave();
			end;
		end);

		HueSelectorInner.InputBegan:Connect(function(Input)
			if Input.UserInputType == Enum.UserInputType.MouseButton1 then
				if ColorPicker.Rainbow then
					ColorPicker:SetRainbow(false);
				end;

				while InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) do
					local MinY = HueSelectorInner.AbsolutePosition.Y;
					local MaxY = MinY + HueSelectorInner.AbsoluteSize.Y;
					local MouseY = math.clamp(Mouse.Y, MinY, MaxY);

					ColorPicker.Hue = ((MouseY - MinY) / (MaxY - MinY));
					ColorPicker:Display();

					RenderStepped:Wait();
				end;

				Library:AttemptSave();
			end;
		end);

		DisplayFrame.InputBegan:Connect(function(Input)
			if Input.UserInputType == Enum.UserInputType.MouseButton1 and not Library:MouseIsOverOpenedFrame() then
				if PickerFrameOuter.Visible then
					ColorPicker:Hide()
				else
					--ContextMenu:Hide()
					ColorPicker:Show()
				end;
			elseif Input.UserInputType == Enum.UserInputType.MouseButton2 and not Library:MouseIsOverOpenedFrame() then
				--ContextMenu:Show()
				ColorPicker:Hide()
			end
		end);

		if TransparencyBoxInner then
			TransparencyBoxInner.InputBegan:Connect(function(Input)
				if Input.UserInputType == Enum.UserInputType.MouseButton1 then
					while InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) do
						local MinX = TransparencyBoxInner.AbsolutePosition.X;
						local MaxX = MinX + TransparencyBoxInner.AbsoluteSize.X;
						local MouseX = math.clamp(Mouse.X, MinX, MaxX);

						ColorPicker.Transparency = 1 - ((MouseX - MinX) / (MaxX - MinX));

						ColorPicker:Display();

						RenderStepped:Wait();
					end;

					Library:AttemptSave();
				end;
			end);
		end;

		local handle = function()
			if (not _visible) then
				return;
			end;
			local AbsPos, AbsSize = PickerFrameOuter.AbsolutePosition, PickerFrameOuter.AbsoluteSize;
			if (Mouse.X < AbsPos.X or Mouse.X > AbsPos.X + AbsSize.X or Mouse.Y < (AbsPos.Y - 20 - 1) or Mouse.Y > AbsPos.Y + AbsSize.Y) then
				ColorPicker:Hide();
			end;
		end
		for _, key in { Enum.UserInputType.MouseButton1, Enum.UserInputType.MouseButton2 } do
			Library:BindToInput(key, handle);
		end;

		ColorPicker:SetRainbow(ColorPicker.Rainbow);
		ColorPicker:Display();
		ColorPicker.DisplayFrame = DisplayFrame

		Options[Idx] = ColorPicker;

		self.Addons = self.Addons or { };
		table.insert(self.Addons, ColorPicker);

		if (self.ToggleRegion) then
			self.ColorPickerCount += 1;
			if (self.ColorPickerCount > 2) then
				self.ToggleRegion.Size -= UDim2.new(0,32,0,0);
			end
		end
		return self;
	end;

	function Funcs:AddKeyPicker(Idx, Info)
		local ParentObj = self;
		local ToggleLabel = self.TextLabel;
		local Container = self.Container;

		assert(Info.Default, 'AddKeyPicker: Missing default value.');

		local KeyPicker = {
			Value = Info.Default;
			Toggled = false;
			Mode = Info.Mode or 'Toggle'; -- Always, Toggle, Hold
			Type = 'KeyPicker';
			Callback = Info.Callback or function(Value) end;
			ChangedCallback = Info.ChangedCallback or function(New) end;
			NoUI = Info.NoUI;--Info.NoUI;
			SyncToggleState = Info.SyncToggleState or false;
			Parent = ParentObj;
			Connections = { };
			Idx = Idx;
		};

		-- Sync pickers only ever run in Toggle, since that is the one mode that
		-- can drive the parent toggle.
		if KeyPicker.SyncToggleState then
			Info.Modes = Info.Modes or { 'Toggle' }
			Info.Mode = Info.Mode or 'Toggle'
			KeyPicker.Mode = Info.Mode
		end

		local PickOuter = Library:Create('Frame', {
			BackgroundColor3 = Color3.new(0, 0, 0);
			BorderColor3 = Color3.new(0, 0, 0);
			Size = UDim2.new(0, 28, 0, 15);
			ZIndex = 6;
			Parent = ToggleLabel;
		});

		local PickInner = Library:Create('Frame', {
			BackgroundColor3 = Library.BackgroundColor;
			BorderColor3 = Library.OutlineColor;
			BorderMode = Enum.BorderMode.Inset;
			Size = UDim2.new(1, 0, 1, 0);
			ZIndex = 7;
			Parent = PickOuter;
		});

		Library:AddToRegistry(PickInner, {
			BackgroundColor3 = 'BackgroundColor';
			BorderColor3 = 'OutlineColor';
		});

		local DisplayLabel = Library:CreateLabel({
			Size = UDim2.new(1, 0, 1, 0);
			TextSize = 13;
			Text = Info.Default;
			TextWrapped = true;
			ZIndex = 8;
			Parent = PickInner;
		});

		local ModeSelectOuter = Library:Create('Frame', {
			BorderColor3 = Color3.new(0, 0, 0);
			Position = UDim2.fromOffset(ToggleLabel.AbsolutePosition.X + ToggleLabel.AbsoluteSize.X + 4, ToggleLabel.AbsolutePosition.Y + 1);
			Size = UDim2.new(0, 60, 0, 45 + 2);
			Visible = false;
			ZIndex = 14;
			Parent = ScreenGui;
		});

		ToggleLabel:GetPropertyChangedSignal('AbsolutePosition'):Connect(function()
			ModeSelectOuter.Position = UDim2.fromOffset(ToggleLabel.AbsolutePosition.X + ToggleLabel.AbsoluteSize.X + 4, ToggleLabel.AbsolutePosition.Y + 1);
		end);

		local ModeSelectInner = Library:Create('Frame', {
			BackgroundColor3 = Library.BackgroundColor;
			BorderColor3 = Library.OutlineColor;
			BorderMode = Enum.BorderMode.Inset;
			Size = UDim2.new(1, 0, 1, 0);
			ZIndex = 15;
			Parent = ModeSelectOuter;
		});

		Library:AddToRegistry(ModeSelectInner, {
			BackgroundColor3 = 'BackgroundColor';
			BorderColor3 = 'OutlineColor';
		});

		Library:Create('UIListLayout', {
			FillDirection = Enum.FillDirection.Vertical;
			SortOrder = Enum.SortOrder.LayoutOrder;
			Parent = ModeSelectInner;
		});

		local ContainerLabel = Library:CreateLabel({
			TextXAlignment = Enum.TextXAlignment.Left;
			Size = UDim2.new(1, 0, 0, 18);
			TextSize = 13;
			RichText = true;
			Visible = false;
			ZIndex = 110;
			Parent = Library.KeybindContainer;
		},  true);

		-- Only Toggle is offered by default. Hold and Always still work at
		-- runtime, but a script has to ask for them via Info.Modes.
		local Modes = Info.Modes or { 'Toggle' };
		local ModeButtons = {};

		--[[for Idx, Mode in next, Modes do
			local ModeButton = {};

			local Label = Library:CreateLabel({
				Active = false;
				Size = UDim2.new(1, 0, 0, 15);
				TextSize = 13;
				Text = Mode;
				ZIndex = 16;
				Parent = ModeSelectInner;
			});

			function ModeButton:Select()
				for _, Button in next, ModeButtons do
					Button:Deselect();
				end;

				KeyPicker.Mode = Mode;

				Label.TextColor3 = Library.AccentColor;
				Library.RegistryMap[Label].Properties.TextColor3 = 'AccentColor';

				ModeSelectOuter.Visible = false;
			end;

			function ModeButton:Deselect()
				KeyPicker.Mode = nil;

				Label.TextColor3 = Library.FontColor;
				Library.RegistryMap[Label].Properties.TextColor3 = 'FontColor';
			end;

			Label.InputBegan:Connect(function(Input)
				if Input.UserInputType == Enum.UserInputType.MouseButton1 then
					ModeButton:Select();
					Library:AttemptSave();
				end;
			end);

			if Mode == KeyPicker.Mode then
				ModeButton:Select();
			end;

			ModeButtons[Mode] = ModeButton;
		end;]]

		local contextmenu = Library:AddContextMenu(PickOuter);

		local buttons = { };
		for index, mode in Modes do
			local button;
			button = contextmenu:AddOption(mode, function()
				KeyPicker.Mode = mode;
				button.TextColor3 = Library.AccentColor;
				for mode, _button in buttons do
					if (_button ~= button) then
						_button.TextColor3 = mode == KeyPicker.Mode and Library.AccentColor or Library.FontColor;
					end;
				end;
				Library:AttemptSave();
				--Library.RegistryMap[Label].Properties.TextColor3 = 'AccentColor';
				--ModeSelectOuter.Visible = false;
			end);
			button:GetPropertyChangedSignal("TextColor3"):Connect(function()
				if (mode == KeyPicker.Mode) then
					button.TextColor3 = Library.AccentColor;
				else
					button.TextColor3 = Library.FontColor;
				end;
			end);
			buttons[mode] = button;
		end;

		-- Clears the bind without touching the mode, so re-picking a key keeps
		-- whatever mode the picker was already in.
		contextmenu:AddOption('Unbind Key', function()
			KeyPicker.Toggled = false;
			KeyPicker.Override = false;
			KeyPicker:SetValue({ 'None', KeyPicker.Mode });

			Library:SafeCallback(KeyPicker.ChangedCallback, 'None');
			Library:SafeCallback(KeyPicker.Changed, 'None');
			Library:AttemptSave();
			contextmenu:Hide();
		end)

		contextmenu:AddOption('Copy Flag', function()
			pcall(setclipboard, KeyPicker.Idx)
			task.wait(); Library:Notify('Copied flag to clipboard!', 2);
			contextmenu:Hide();
		end)

		for mode, button in buttons do
			button.TextColor3 = mode == KeyPicker.Mode and Library.AccentColor or Library.FontColor;
		end;
		-- Key, name and mode each get their own colour inside one label. An
		-- inactive row dims instead of vanishing, so the list stays stable.
		local update = function(State)
			local mode = KeyPicker.Mode;
			mode = mode ~= "Always" and KeyPicker.Override and "Override" or mode;

			local KeyColor = State and Library.AccentColor or Library:GetDarkerColor(Library.AccentColor);
			local NameColor = State and Library.FontColor or Library:GetDarkerColor(Library.FontColor);

			ContainerLabel.Text = table.concat({
				Library:ColorRichText('[' .. tostring(KeyPicker.Value) .. ']', KeyColor),
				Library:ColorRichText(tostring(Info.Text), NameColor),
				Library:ColorRichText(tostring(mode), Color3.fromRGB(125, 125, 125)),
			}, ' ');

			ContainerLabel.Visible = true;
			ContainerLabel.TextColor3 = Library.FontColor;

			Library.RegistryMap[ContainerLabel].Properties.TextColor3 = 'FontColor';
		end;

		function KeyPicker:Update()
			if not KeyPicker.NoUI then
				local mode = Library.KeypickerListMode;
				local State = KeyPicker:GetState();

				if (mode == "Active" and KeyPicker.Parent.Type == "Toggle" and (not State or not KeyPicker.Parent.Value)) then
					ContainerLabel.Visible = false;
				elseif (mode == "Toggled" and KeyPicker.Parent.Type == "Toggle" and not KeyPicker.Parent.Value) then
					ContainerLabel.Visible = false;
				else
					update(State);
				end;
			else
				ContainerLabel.Visible = false;
			end;

			local YSize = 0
			local XSize = 0

			for _, Label in next, Library.KeybindContainer:GetChildren() do
				if Label:IsA('TextLabel') and Label.Visible then
					YSize = YSize + 18;
					if (Label.TextBounds.X > XSize) then
						XSize = Label.TextBounds.X
					end
				end;
			end;

			Library.KeybindFrame.Size = UDim2.new(0, math.max(XSize + 24, 190), 0, YSize + 28)

			Library.KeybindFrame.Visible = Library.KeypickerListVisible and (YSize ~= 0);
		end;

		function KeyPicker:OverrideState(v)
			self.Override = v;
			KeyPicker.Toggled = false;
			KeyPicker:Update();
		end;

		local IsMouseButtonPressed, IsKeyDown = InputService.IsMouseButtonPressed, InputService.IsKeyDown;

		local mb1, mb2 = Enum.UserInputType.MouseButton1, Enum.UserInputType.MouseButton2;
		local enum_keycode = Enum.KeyCode;
		function KeyPicker:GetState()
			local mode = KeyPicker.Mode;
			if mode == 'Always' then
				return true;
			end;
			local Key = KeyPicker.Value;
			if Key == 'None' then
				return false;
			end

			local value = nil;
			if (mode  == 'Hold') then
				if (Key == 'MB1' or Key == 'MB2') then
					value = Key == 'MB1' and IsMouseButtonPressed(InputService, mb1) or Key == 'MB2' and IsMouseButtonPressed(InputService, mb2);
				else
					value = IsKeyDown(InputService, enum_keycode[Key]);
				end;
			else
				value = KeyPicker.Toggled;
			end;
			if (value and self.Override) then
				KeyPicker:OverrideState(false);
			end;
			return value or self.Override;
		end;

		function KeyPicker:SetValue(Data)
			local Key, Mode = Data[1], Data[2];

			-- An old config can hold a mode this picker no longer offers, which
			-- would leave the bind stuck with no menu entry to change it back.
			if type(Mode) ~= 'string' or not table.find(Modes, Mode) then
				Mode = Modes[1] or 'Toggle';
			end;

			DisplayLabel.Text = Key;
			KeyPicker.Value, KeyPicker.Mode = Key, Mode;
			for mode, button in buttons do
				button.TextColor3 = mode == KeyPicker.Mode and Library.AccentColor or Library.FontColor;
			end;
			KeyPicker:Update();
		end;

		function KeyPicker:OnClick(Callback)
			KeyPicker.Clicked = Callback
		end

		function KeyPicker:OnChanged(Callback)
			KeyPicker.Changed = Callback
			Callback(KeyPicker.Value)
		end

		if ParentObj.Addons then
			table.insert(ParentObj.Addons, KeyPicker)
		end

		function KeyPicker:DoClick()
			if (KeyPicker.Override) then
				KeyPicker.Override = false;
				KeyPicker.Toggled = false;
			end;
			if ParentObj.Type == 'Toggle' and KeyPicker.SyncToggleState then
				ParentObj:SetValue(not ParentObj.Value)
			end

			Library:SafeCallback(KeyPicker.Callback, KeyPicker.Toggled)
			Library:SafeCallback(KeyPicker.Clicked, KeyPicker.Toggled)
		end

		function KeyPicker:SetupConnection(c)
			table.insert(self.Connections, c);
			Library:GiveSignal(c);
		end;

		function KeyPicker:Remove()
			Options[Idx] = nil;

			for _, connection in KeyPicker.Connections do
				connection:Disconnect();
			end;

			table.clear(KeyPicker);
			PickOuter:Destroy();
			ContainerLabel:Destroy();
		end;

		local Picking = false;

		PickOuter.InputBegan:Connect(function(Input)
			if Input.UserInputType == Enum.UserInputType.MouseButton1 and not Library:MouseIsOverOpenedFrame() then
				Picking = true;

				DisplayLabel.Text = '';

				local Break;
				local Text = '';

				task.spawn(function()
					while (not Break) do
						if Text == '...' then
							Text = '';
						end;

						Text = Text .. '.';
						DisplayLabel.Text = Text;

						wait(0.4);
					end;
				end);

				wait(0.2);

				local Event;
				Event = InputService.InputBegan:Connect(function(Input)
					local Key;

					if Input.UserInputType == Enum.UserInputType.Keyboard then
						Key = Input.KeyCode == Enum.KeyCode.Escape and "..." or Input.KeyCode.Name;
					elseif Input.UserInputType == Enum.UserInputType.MouseButton1 then
						Key = 'MB1';
					elseif Input.UserInputType == Enum.UserInputType.MouseButton2 then
						Key = 'MB2';
					end;

					Break = true;
					Picking = false;

					DisplayLabel.Text = Key;
					KeyPicker.Value = Key;

					Library:SafeCallback(KeyPicker.ChangedCallback, Input.KeyCode or Input.UserInputType)
					Library:SafeCallback(KeyPicker.Changed, Input.KeyCode or Input.UserInputType)

					Library:AttemptSave();

					Event:Disconnect();
				end);
				--elseif Input.UserInputType == Enum.UserInputType.MouseButton2 and not Library:MouseIsOverOpenedFrame() then
				--ModeSelectOuter.Visible = true;
			end;
		end);

		KeyPicker:SetupConnection(InputService.InputBegan:Connect(function(Input, Processed)
			if (not Picking and not Processed) then
				if KeyPicker.Mode == 'Toggle' then
					local Key = KeyPicker.Value;

					if Key == 'MB1' or Key == 'MB2' then
						if Key == 'MB1' and Input.UserInputType == Enum.UserInputType.MouseButton1
							or Key == 'MB2' and Input.UserInputType == Enum.UserInputType.MouseButton2 then
							KeyPicker.Toggled = not KeyPicker.Toggled
							KeyPicker:DoClick()
						end;
					elseif Input.UserInputType == Enum.UserInputType.Keyboard then
						if Input.KeyCode.Name == Key then
							KeyPicker.Toggled = not KeyPicker.Toggled;
							KeyPicker:DoClick()
						end;
					end;
				end;
				KeyPicker:Update();
			end;
			--if Input.UserInputType == Enum.UserInputType.MouseButton1 then
			--	local AbsPos, AbsSize = ModeSelectOuter.AbsolutePosition, ModeSelectOuter.AbsoluteSize;

			--	if Mouse.X < AbsPos.X or Mouse.X > AbsPos.X + AbsSize.X
			--		or Mouse.Y < (AbsPos.Y - 20 - 1) or Mouse.Y > AbsPos.Y + AbsSize.Y then

			--		ModeSelectOuter.Visible = false;
			--	end;
			--end;
		end))

		KeyPicker:SetupConnection(InputService.InputEnded:Connect(function(Input)
			if (not Picking) then
				KeyPicker:Update();
			end;
		end))

		KeyPicker:Update();

		Options[Idx] = KeyPicker;

		return self;
	end;

	BaseAddons.__index = Funcs;
	BaseAddons.__namecall = function(Table, Key, ...)
		return Funcs[Key](...);
	end;
end;

local BaseGroupbox = {};

do
	local Funcs = {};

	function Funcs:AddBlank(Size)
		local Groupbox = self;
		local Container = Groupbox.Container;

		return Library:Create('Frame', {
			BackgroundTransparency = 1;
			Size = UDim2.new(1, 0, 0, Size);
			ZIndex = 1;
			Parent = Container;
		});
	end;

	function Funcs:AddLabel(Text, DoesWrap)
		local Label = {
			Type = "Label";	
		};

		local Groupbox = self;
		local Container = Groupbox.Container;

		local TextLabel = Library:CreateLabel({
			Size = UDim2.new(1, -4, 0, 15);
			TextSize = 14;
			Text = Text;
			TextWrapped = DoesWrap or false,
			TextXAlignment = Enum.TextXAlignment.Left;
			RichText = true,
			ZIndex = 5;
			Parent = Container;
		});

		if DoesWrap then
			local Y = select(2, Library:GetTextBounds(Text, Library.Font, 14, Vector2.new(TextLabel.AbsoluteSize.X, math.huge)))
			TextLabel.Size = UDim2.new(1, -4, 0, Y)
		else
			Library:Create('UIListLayout', {
				Padding = UDim.new(0, 4);
				FillDirection = Enum.FillDirection.Horizontal;
				HorizontalAlignment = Enum.HorizontalAlignment.Right;
				SortOrder = Enum.SortOrder.LayoutOrder;
				Parent = TextLabel;
			});
		end

		Label.TextLabel = TextLabel;
		Label.Container = Container;

		function Label:SetText(Text)
			TextLabel.Text = Text

			if DoesWrap then
				local Y = select(2, Library:GetTextBounds(Text, Library.Font, 14, Vector2.new(TextLabel.AbsoluteSize.X, math.huge)))
				TextLabel.Size = UDim2.new(1, -4, 0, Y)
			end

			Groupbox:Resize();

			return Label;
		end

		---Recolor the label. Pass a Color3 for a fixed colour, or a Library
		---colour name ('AccentColor', 'FontColor', 'RiskColor') to have it track
		---the theme. Returns the label so calls chain.
		---@param Color Color3 | string
		---@return table
		function Label:SetColor(Color)
			local Reg = Library.RegistryMap[TextLabel];

			if type(Color) == 'string' then
				-- Theme key, so hand it back to the registry and let the picker
				-- drive it from here on.
				if Reg then
					Reg.Properties.TextColor3 = Color;
				end;

				TextLabel.TextColor3 = Library[Color] or Library.FontColor;
				return Label;
			end;

			if typeof(Color) ~= 'Color3' then
				return Label;
			end;

			-- Fixed colour, so drop it out of the registry or the next theme
			-- repaint would paint straight over it.
			if Reg then
				Reg.Properties.TextColor3 = nil;
			end;

			TextLabel.TextColor3 = Color;
			return Label;
		end;

		---Groupbox:AddLabel('text'):FromRGB(255, 0, 0)
		---@param R number 0-255
		---@param G number 0-255
		---@param B number 0-255
		---@return table
		function Label:FromRGB(R, G, B)
			return Label:SetColor(Color3.fromRGB(R or 255, G or 255, B or 255));
		end;

		---Same, from a hex string. '#ff0000' and 'ff0000' both work.
		---@param Hex string
		---@return table
		function Label:FromHex(Hex)
			if type(Hex) ~= 'string' then
				return Label;
			end;

			if Hex:sub(1, 1) ~= '#' then
				Hex = '#' .. Hex;
			end;

			local Ok, Color = pcall(Color3.fromHex, Hex);
			return Ok and Label:SetColor(Color) or Label;
		end;

		---Paint the label with whatever the accent picker is set to, live.
		---@return table
		function Label:FromAccent()
			return Label:SetColor('AccentColor');
		end;
		local Blanks = { };
		function Label:Remove()
			for _, blank in Blanks do
				blank:Destroy();
			end;
			TextLabel:Destroy();
			table.clear(Label);
			Groupbox:Resize();
		end;

		if (not DoesWrap) then
			setmetatable(Label, BaseAddons);
		end

		table.insert(Blanks, Groupbox:AddBlank(5));
		Groupbox:Resize();

		return Label;
	end;

	function Funcs:AddButton(...)
		-- TODO: Eventually redo this
		local Button = {
		};
		local function ProcessButtonParams(Class, Obj, ...)
			local Props = select(1, ...)
			if type(Props) == 'table' then
				Obj.Text = Props.Text
				Obj.Func = Props.Func
				Obj.DoubleClick = Props.DoubleClick
				Obj.Tooltip = Props.Tooltip
			else
				Obj.Text = select(1, ...)
				Obj.Func = select(2, ...)
			end

			assert(type(Obj.Func) == 'function', 'AddButton: `Func` callback is missing.');
		end

		ProcessButtonParams('Button', Button, ...)

		local Groupbox = self;
		local Container = Groupbox.Container;

		local function CreateBaseButton(Button)
			local Outer = Library:Create('Frame', {
				BackgroundColor3 = Color3.new(0, 0, 0);
				BorderColor3 = Color3.new(0, 0, 0);
				Size = UDim2.new(1, -4, 0, 20);
				ZIndex = 5;
			});

			local Inner = Library:Create('Frame', {
				BackgroundColor3 = Library.MainColor;
				BorderColor3 = Library.OutlineColor;
				BorderMode = Enum.BorderMode.Inset;
				Size = UDim2.new(1, 0, 1, 0);
				ZIndex = 6;
				Parent = Outer;
			});

			local Label = Library:CreateLabel({
				Size = UDim2.new(1, 0, 1, 0);
				TextSize = 14;
				Text = Button.Text;
				ZIndex = 6;
				Parent = Inner;
			});

			Library:Create('UIGradient', {
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
					ColorSequenceKeypoint.new(1, Color3.fromRGB(212, 212, 212))
				});
				Rotation = 90;
				Parent = Inner;
			});

			Library:AddToRegistry(Outer, {
				BorderColor3 = 'Black';
			});

			Library:AddToRegistry(Inner, {
				BackgroundColor3 = 'MainColor';
				BorderColor3 = 'OutlineColor';
			});

			Library:OnHighlight(Outer, Outer,
				{ BorderColor3 = 'AccentColor' },
				{ BorderColor3 = 'Black' }
			);

			return Outer, Inner, Label
		end

		local function InitEvents(Button)
			local function WaitForEvent(event, timeout, validator)
				local bindable = Instance.new('BindableEvent')
				local connection = event:Once(function(...)

					if type(validator) == 'function' and validator(...) then
						bindable:Fire(true)
					else
						bindable:Fire(false)
					end
				end)
				task.delay(timeout, function()
					connection:disconnect()
					bindable:Fire(false)
				end)
				return bindable.Event:Wait()
			end

			local function ValidateClick(Input)
				if Library:MouseIsOverOpenedFrame() then
					return false
				end

				if Input.UserInputType ~= Enum.UserInputType.MouseButton1 then
					return false
				end

				return true
			end

			Button.Outer.InputBegan:Connect(function(Input)
				if not ValidateClick(Input) then return end
				if Button.Locked then return end

				if Button.DoubleClick then
					Library:RemoveFromRegistry(Button.Label)
					Library:AddToRegistry(Button.Label, { TextColor3 = 'AccentColor' })

					Button.Label.TextColor3 = Library.AccentColor
					Button.Label.Text = 'Are you sure?'
					Button.Locked = true

					local clicked = WaitForEvent(Button.Outer.InputBegan, 0.5, ValidateClick)

					Library:RemoveFromRegistry(Button.Label)
					Library:AddToRegistry(Button.Label, { TextColor3 = 'FontColor' })

					Button.Label.TextColor3 = Library.FontColor
					Button.Label.Text = Button.Text
					task.defer(rawset, Button, 'Locked', false)

					if clicked then
						Library:SafeCallback(Button.Func)
					end

					return
				end

				Library:SafeCallback(Button.Func);
			end)
		end

		Button.Outer, Button.Inner, Button.Label = CreateBaseButton(Button)
		Button.Outer.Parent = Container

		InitEvents(Button)

		function Button:AddTooltip(tooltip)
			if type(tooltip) == 'string' then
				Library:AddToolTip(tooltip, self.Outer)
			end
			return self
		end

		function Button:AddButton(...)
			local SubButton = {}

			ProcessButtonParams('SubButton', SubButton, ...)

			self.Outer.Size = UDim2.new(0.5, -2, 0, 20)

			SubButton.Outer, SubButton.Inner, SubButton.Label = CreateBaseButton(SubButton)

			SubButton.Outer.Position = UDim2.new(1, 3, 0, 0)
			SubButton.Outer.Size = UDim2.fromOffset(self.Outer.AbsoluteSize.X - 3, self.Outer.AbsoluteSize.Y)
			SubButton.Outer.Parent = self.Outer

			function SubButton:AddTooltip(tooltip)
				if type(tooltip) == 'string' then
					Library:AddToolTip(tooltip, self.Outer)
				end
				return SubButton
			end

			if type(SubButton.Tooltip) == 'string' then
				SubButton:AddTooltip(SubButton.Tooltip)
			end

			InitEvents(SubButton)
			return SubButton
		end


		local Blanks = { };
		function Button:Remove()
			for _, blank in Blanks do
				blank:Destroy();
			end;
			Button.Outer:Destroy();
			table.clear(Button);
			Groupbox:Resize();
		end;

		if type(Button.Tooltip) == 'string' then
			Button:AddTooltip(Button.Tooltip)
		end

		table.insert(Blanks, Groupbox:AddBlank(5));
		Groupbox:Resize();

		return Button;
	end;

	function Funcs:AddFrame()
		local Outer = Library:Create('Frame', {
			BackgroundColor3 = Color3.new(0, 0, 0);
			BorderColor3 = Color3.new(0, 0, 0);
			Size = UDim2.new(1, -4, 0, 100);
			ZIndex = 5;
			Parent = self.Container;
		});

		local Inner = Library:Create('Frame', {
			BackgroundColor3 = Library.MainColor;
			BorderColor3 = Library.OutlineColor;
			BorderMode = Enum.BorderMode.Inset;
			Size = UDim2.new(1, 0, 1, 0);
			ZIndex = 6;
			Parent = Outer;
		});

		Library:Create('UIGradient', {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(212, 212, 212))
			});
			Rotation = 90;
			Parent = Inner;
		});

		Library:AddToRegistry(Outer, {
			BorderColor3 = 'Black';
		});

		Library:AddToRegistry(Inner, {
			BackgroundColor3 = 'MainColor';
			BorderColor3 = 'OutlineColor';
		});

		Library:OnHighlight(Outer, Outer,
			{ BorderColor3 = 'AccentColor' },
			{ BorderColor3 = 'Black' }
		);

		local Frame = { };
		function Frame:SetSize(y)
			Outer.Size = UDim2.new(1, -4, 0, y);
		end;
		function Frame:GetOuter()
			return Outer;
		end;
		function Frame:GetInner()
			return Inner;
		end;
		function Frame:GetSize()
			return Inner.AbsoluteSize;
		end;

		local Blanks = { };
		table.insert(Blanks, self:AddBlank(5));
		self:Resize();
		return Frame;
	end;

	function Funcs:AddDivider()
		local Groupbox = self;
		local Container = self.Container

		local Divider = {
			Type = 'Divider',
		}

		Groupbox:AddBlank(2);
		local DividerOuter = Library:Create('Frame', {
			BackgroundColor3 = Color3.new(0, 0, 0);
			BorderColor3 = Color3.new(0, 0, 0);
			Size = UDim2.new(1, -4, 0, 5);
			ZIndex = 5;
			Parent = Container;
		});

		local DividerInner = Library:Create('Frame', {
			BackgroundColor3 = Library.MainColor;
			BorderColor3 = Library.OutlineColor;
			BorderMode = Enum.BorderMode.Inset;
			Size = UDim2.new(1, 0, 1, 0);
			ZIndex = 6;
			Parent = DividerOuter;
		});

		Library:AddToRegistry(DividerOuter, {
			BorderColor3 = 'Black';
		});

		Library:AddToRegistry(DividerInner, {
			BackgroundColor3 = 'MainColor';
			BorderColor3 = 'OutlineColor';
		});

		Groupbox:AddBlank(9);
		Groupbox:Resize();
	end

	function Funcs:AddInput(Idx, Info)
		assert(Info.Text, 'AddInput: Missing `Text` string.')

		local Blanks = { };
		local Textbox = {
			Value = Info.Default or '';
			Numeric = Info.Numeric or false;
			Finished = Info.Finished or false;
			Type = 'Input';
			Callback = Info.Callback or function(Value) end;
			Idx = Idx;
		};

		local Groupbox = self;
		local Container = Groupbox.Container;

		local InputLabel = Library:CreateLabel({
			Size = UDim2.new(1, 0, 0, 15);
			TextSize = 14;
			Text = Info.Text;
			TextXAlignment = Enum.TextXAlignment.Left;
			ZIndex = 5;
			Parent = Container;
		});

		table.insert(Blanks, Groupbox:AddBlank(1));

		local TextBoxOuter = Library:Create('Frame', {
			BackgroundColor3 = Color3.new(0, 0, 0);
			BorderColor3 = Color3.new(0, 0, 0);
			Size = UDim2.new(1, -4, 0, 20);
			ZIndex = 5;
			Parent = Container;
		});

		local TextBoxInner = Library:Create('Frame', {
			BackgroundColor3 = Library.MainColor;
			BorderColor3 = Library.OutlineColor;
			BorderMode = Enum.BorderMode.Inset;
			Size = UDim2.new(1, 0, 1, 0);
			ZIndex = 6;
			Parent = TextBoxOuter;
		});

		Library:AddToRegistry(TextBoxInner, {
			BackgroundColor3 = 'MainColor';
			BorderColor3 = 'OutlineColor';
		});

		Library:OnHighlight(TextBoxOuter, TextBoxOuter,
			{ BorderColor3 = 'AccentColor' },
			{ BorderColor3 = 'Black' }
		);

		if type(Info.Tooltip) == 'string' then
			Library:AddToolTip(Info.Tooltip, TextBoxOuter)
		end

		Library:Create('UIGradient', {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(212, 212, 212))
			});
			Rotation = 90;
			Parent = TextBoxInner;
		});

		local Container = Library:Create('Frame', {
			BackgroundTransparency = 1;
			ClipsDescendants = true;

			Position = UDim2.new(0, 5, 0, 0);
			Size = UDim2.new(1, -5, 1, 0);

			ZIndex = 7;
			Parent = TextBoxInner;
		})

		local Box = Library:Create('TextBox', {
			BackgroundTransparency = 1;

			Position = UDim2.fromOffset(0, 0),
			Size = UDim2.fromScale(5, 1),

			Font = Library.Font;
			PlaceholderColor3 = Color3.fromRGB(190, 190, 190);
			PlaceholderText = Info.Placeholder or '';

			ClearTextOnFocus = Info.Clear or false;
			Text = Info.Default or '';
			TextColor3 = Library.FontColor;
			TextSize = 14;
			TextStrokeTransparency = 0;
			TextXAlignment = Enum.TextXAlignment.Left;

			ZIndex = 7;
			Parent = Container;
		});

		Library:ApplyTextStroke(Box);

		function Textbox:SetValue(Text)
			if Info.MaxLength and #Text > Info.MaxLength then
				Text = Text:sub(1, Info.MaxLength);
			end;

			if Textbox.Numeric then
				if (not tonumber(Text)) and Text:len() > 0 then
					Text = Textbox.Value
				end
			end

			Textbox.Value = Text;
			Box.Text = Text;

			Library:SafeCallback(Textbox.Callback, Textbox.Value);
			Library:SafeCallback(Textbox.Changed, Textbox.Value);
		end;

		function Textbox:Remove()
			for _, blank in Blanks do
				blank:Destroy();
			end;
			Options[Idx] = nil;
			TextBoxOuter:Destroy();
			table.clear(Textbox);
			Groupbox:Resize();
		end;

		if Textbox.Finished then
			Box.FocusLost:Connect(function(enter)
				if not enter then return end

				Textbox:SetValue(Box.Text);
				Library:AttemptSave();
			end)
		else
			Box:GetPropertyChangedSignal('Text'):Connect(function()
				Textbox:SetValue(Box.Text);
				Library:AttemptSave();
			end);
		end

		-- https://devforum.roblox.com/t/how-to-make-textboxes-follow-current-cursor-position/1368429/6
		-- thank you nicemike40 :)

		local function Update()
			local PADDING = 2
			local reveal = Container.AbsoluteSize.X

			if not Box:IsFocused() or Box.TextBounds.X <= reveal - 2 * PADDING then
				-- we aren't focused, or we fit so be normal
				Box.Position = UDim2.new(0, PADDING, 0, 0)
			else
				-- we are focused and don't fit, so adjust position
				local cursor = Box.CursorPosition
				if cursor ~= -1 then
					-- calculate pixel width of text from start to cursor
					local subtext = string.sub(Box.Text, 1, cursor-1)
					local width = TextService:GetTextSize(subtext, Box.TextSize, Box.Font, Vector2.new(math.huge, math.huge)).X

					-- check if we're inside the box with the cursor
					local currentCursorPos = Box.Position.X.Offset + width

					-- adjust if necessary
					if currentCursorPos < PADDING then
						Box.Position = UDim2.fromOffset(PADDING-width, 0)
					elseif currentCursorPos > reveal - PADDING - 1 then
						Box.Position = UDim2.fromOffset(reveal-width-PADDING-1, 0)
					end
				end
			end
		end

		task.spawn(Update)

		Box:GetPropertyChangedSignal('Text'):Connect(Update)
		Box:GetPropertyChangedSignal('CursorPosition'):Connect(Update)
		Box.FocusLost:Connect(Update)
		Box.Focused:Connect(Update)

		local contextmenu = Library:AddContextMenu(TextBoxOuter);
		contextmenu:AddOption('Copy Flag', function()
			pcall(setclipboard, Textbox.Idx);
			task.wait(); Library:Notify('Copied flag to clipboard!', 2);
			contextmenu:Hide();
		end);

		Library:AddToRegistry(Box, {
			TextColor3 = 'FontColor';
		});

		function Textbox:OnChanged(Func)
			Textbox.Changed = Func;
			Func(Textbox.Value);
		end;

		table.insert(Blanks, Groupbox:AddBlank(5));
		Groupbox:Resize();

		Options[Idx] = Textbox;

		return Textbox;
	end;

	function Funcs:AddToggle(Idx, Info)
		assert(Info.Text, 'AddInput: Missing `Text` string.')

		local Blanks = { };
		local Toggle = {
			Value = Info.Default or false;
			Type = 'Toggle';

			Callback = Info.Callback or function(Value) end;
			Addons = {},
			Risky = Info.Risky,
			Idx = Idx;
		};

		local Groupbox = self;
		local Container = Groupbox.Container;

		-- Row wrapper spans the whole groupbox so anything right-aligned inside
		-- it (keypickers, colorpickers) tracks the real edge instead of a
		-- hardcoded label width, which is what made them drift on resize.
		local ToggleOuter = Library:Create('Frame', {
			BackgroundTransparency = 1;
			BorderSizePixel = 0;
			Size = UDim2.new(1, -4, 0, 13);
			ZIndex = 5;
			Parent = Container;
		});

		local ToggleBox = Library:Create('Frame', {
			BackgroundColor3 = Color3.new(0, 0, 0);
			BorderColor3 = Color3.new(0, 0, 0);
			Size = UDim2.new(0, 13, 0, 13);
			ZIndex = 5;
			Parent = ToggleOuter;
		});

		Library:AddToRegistry(ToggleBox, {
			BorderColor3 = 'Black';
		});

		local ToggleInner = Library:Create('Frame', {
			BackgroundColor3 = Library.MainColor;
			BorderColor3 = Library.OutlineColor;
			BorderMode = Enum.BorderMode.Inset;
			Size = UDim2.new(1, 0, 1, 0);
			ZIndex = 6;
			Parent = ToggleBox;
		});

		Library:AddToRegistry(ToggleInner, {
			BackgroundColor3 = 'MainColor';
			BorderColor3 = 'OutlineColor';
		});

		-- Checkmark: two rotated bars meeting at a shared vertex near (5, 9),
		-- drawn twice so a 1px offset copy shades it and it stays readable on a
		-- light or a dark accent. No glyph and no asset, so it cannot fail to load.
		local Checkmark = Library:Create('Frame', {
			Name = 'Checkmark';
			BackgroundTransparency = 1;
			Size = UDim2.new(1, 0, 1, 0);
			Visible = false;
			ZIndex = 7;
			Parent = ToggleInner;
		});

		local function createCheckBar(x, y, length, rotation, transparency, zindex)
			return Library:Create('Frame', {
				BorderSizePixel = 0;
				AnchorPoint = Vector2.new(0.5, 0.5);
				Position = UDim2.fromOffset(x, y);
				Size = UDim2.fromOffset(2, length);
				Rotation = rotation;
				BackgroundTransparency = transparency;
				ZIndex = zindex;
				Parent = Checkmark;
			});
		end;

		local CheckShadeShort = createCheckBar(4, 8, 5, -45, 0.5, 7);
		local CheckShadeLong = createCheckBar(9, 7, 8, 45, 0.5, 7);
		local CheckShort = createCheckBar(3, 7, 5, -45, 0, 8);
		local CheckLong = createCheckBar(8, 6, 8, 45, 0, 8);

		local ToggleLabel = Library:CreateLabel({
			Size = UDim2.new(1, -19, 1, 0);
			Position = UDim2.new(0, 19, 0, 0);
			TextSize = 14;
			Text = Info.Text;
			TextXAlignment = Enum.TextXAlignment.Left;
			ZIndex = 6;
			Parent = ToggleOuter;
		});

		Library:Create('UIListLayout', {
			Padding = UDim.new(0, 4);
			FillDirection = Enum.FillDirection.Horizontal;
			HorizontalAlignment = Enum.HorizontalAlignment.Right;
			SortOrder = Enum.SortOrder.LayoutOrder;
			Parent = ToggleLabel;
		});

		local ToggleRegion = Library:Create('Frame', {
			BackgroundTransparency = 1;
			Size = UDim2.new(0, 170, 1, 0);
			ZIndex = 8;
			Parent = ToggleOuter;
		});

		Library:OnHighlight(ToggleRegion, ToggleBox,
			{ BorderColor3 = 'AccentColor' },
			{ BorderColor3 = 'Black' }
		);

		function Toggle:UpdateColors()
			Toggle:Display();
		end;

		if type(Info.Tooltip) == 'string' then
			Library:AddToolTip(Info.Tooltip, ToggleRegion)
		end

		function Toggle:Display()
			ToggleInner.BackgroundColor3 = Toggle.Value and Library.AccentColor or Library.MainColor;
			ToggleInner.BorderColor3 = Toggle.Value and Library.AccentColorDark or Library.OutlineColor;

			Library.RegistryMap[ToggleInner].Properties.BackgroundColor3 = Toggle.Value and 'AccentColor' or 'MainColor';
			Library.RegistryMap[ToggleInner].Properties.BorderColor3 = Toggle.Value and 'AccentColorDark' or 'OutlineColor';

			-- Picked against the fill behind it so the tick never disappears on
			-- a light accent. Library.CheckmarkColor overrides it outright.
			local Tick = Library.CheckmarkColor or Library:GetContrastColor(Library.AccentColor);
			local Shade = Library:GetContrastColor(Tick);

			CheckShort.BackgroundColor3 = Tick;
			CheckLong.BackgroundColor3 = Tick;
			CheckShadeShort.BackgroundColor3 = Shade;
			CheckShadeLong.BackgroundColor3 = Shade;
			Checkmark.Visible = Toggle.Value;
		end;

		function Toggle:OnChanged(Func)
			Toggle.Changed = Func;
			Func(Toggle.Value);
		end;

		function Toggle:SetValue(Bool)
			Bool = (not not Bool);

			Toggle.Value = Bool;
			Toggle:Display();

			for _, Addon in next, Toggle.Addons do
				if Addon.Type == 'KeyPicker' then
					if (Addon.SyncToggleState) then
						Addon.Toggled = Bool
					end;
					Addon:Update()
				end
			end

			Library:SafeCallback(Toggle.Callback, Toggle.Value);
			Library:SafeCallback(Toggle.Changed, Toggle.Value);
			Library:UpdateDependencyBoxes();
		end;

		function Toggle:Remove()
			for _, blank in Blanks do
				blank:Destroy();
			end;
			Toggles[Idx] = nil;
			ToggleOuter:Destroy();
			table.clear(Toggle);
			Groupbox:Resize();
		end;

		ToggleRegion.InputBegan:Connect(function(Input)
			if Input.UserInputType == Enum.UserInputType.MouseButton1 and not Library:MouseIsOverOpenedFrame() then
				Toggle:SetValue(not Toggle.Value) -- Why was it not like this from the start?
				Library:AttemptSave();
			end;
		end);

		local contextmenu = Library:AddContextMenu(ToggleBox, ToggleRegion);
		contextmenu:AddOption('Copy Flag', function()
			pcall(setclipboard, Toggle.Idx);
			task.wait(); Library:Notify('Copied flag to clipboard!', 2);
			contextmenu:Hide();
		end);

		if Toggle.Risky then
			Library:RemoveFromRegistry(ToggleLabel)
			ToggleLabel.TextColor3 = Library.RiskColor
			Library:AddToRegistry(ToggleLabel, { TextColor3 = 'RiskColor' })
		end

		Toggle:Display();
		table.insert(Blanks, Groupbox:AddBlank(Info.BlankSize or 5 + 2));
		Groupbox:Resize();

		Toggle.ColorPickerCount = 0;
		Toggle.ToggleRegion = ToggleRegion;
		Toggle.TextLabel = ToggleLabel;
		Toggle.Container = Container;
		setmetatable(Toggle, BaseAddons);

		Toggles[Idx] = Toggle;

		Library:UpdateDependencyBoxes();

		return Toggle;
	end;

	function Funcs:AddSlider(Idx, Info, SliderParent)
		assert(Info.Default, 'AddSlider: Missing default value.');
		assert(Info.Text, 'AddSlider: Missing slider text.');
		assert(Info.Min, 'AddSlider: Missing minimum value.');
		assert(Info.Max, 'AddSlider: Missing maximum value.');
		assert(Info.Rounding, 'AddSlider: Missing rounding value.');

		local Blanks = { };
		local Slider = {
			Value = Info.Default;
			Min = Info.Min;
			Max = Info.Max;
			Rounding = Info.Rounding;
			MaxSize = 232;--SliderParent and 232/2 - 3 or 232;
			Type = 'Slider';
			Callback = Info.Callback or function(Value) end;
			Increment = Info.Increment;
			Idx = Idx;
		};

		Slider.Parent = SliderParent;

		local Groupbox = self;
		local Container = SliderParent and SliderParent.Outer or Groupbox.Container;

		if not Info.Compact then
			local label = Library:CreateLabel({
				Size = UDim2.new(1, 0, 0, 10);
				Position = SliderParent and UDim2.new(1,4,0,-12) or UDim2.new();
				TextSize = 14;
				Text = Info.Text;
				TextXAlignment = Enum.TextXAlignment.Left;
				TextYAlignment = Enum.TextYAlignment.Bottom;
				ZIndex = 5;
				Parent = Container;
			});
			table.insert(Blanks, label);
			table.insert(Blanks, Groupbox:AddBlank(3));
		end;

		local SliderOuter = Library:Create('Frame', {
			BackgroundColor3 = Color3.new(0, 0, 0);
			BorderColor3 = Color3.new(0, 0, 0);
			--Position = UDim2.fromScale(Groupbox.SliderParent and .5 or 0,0);
			Size = UDim2.new(1,0,0,13);
			ZIndex = 5;
			Parent = Container;
		});

		Slider.Outer = SliderOuter;

		Library:AddToRegistry(SliderOuter, {
			BorderColor3 = 'Black';
		});

		local SliderInner = Library:Create('Frame', {
			BackgroundColor3 = Library.MainColor;
			BorderColor3 = Library.OutlineColor;
			BorderMode = Enum.BorderMode.Inset;
			Size = UDim2.new(1, 0, 1, 0);
			ZIndex = 6;
			Parent = SliderOuter;
		});

		Library:AddToRegistry(SliderInner, {
			BackgroundColor3 = 'MainColor';
			BorderColor3 = 'OutlineColor';
		});

		local Fill = Library:Create('Frame', {
			BackgroundColor3 = Library.AccentColor;
			BorderColor3 = Library.AccentColorDark;
			Size = UDim2.new(0, 0, 1, 0);
			ZIndex = 7;
			Parent = SliderInner;
		});

		Library:AddToRegistry(Fill, {
			BackgroundColor3 = 'AccentColor';
			BorderColor3 = 'AccentColorDark';
		});

		local HideBorderRight = Library:Create('Frame', {
			BackgroundColor3 = Library.AccentColor;
			BorderSizePixel = 0;
			Position = UDim2.new(1, 0, 0, 0);
			Size = UDim2.new(0, 1, 1, 0);
			ZIndex = 8;
			Parent = Fill;
		});

		Library:AddToRegistry(HideBorderRight, {
			BackgroundColor3 = 'AccentColor';
		});

		local DisplayLabel = Library:CreateLabel({
			Size = UDim2.new(1, 0, 1, 0);
			TextSize = 14;
			Text = 'Infinite';
			ZIndex = 9;
			Parent = SliderInner;
		});

		Library:OnHighlight(SliderOuter, SliderOuter,
			{ BorderColor3 = 'AccentColor' },
			{ BorderColor3 = 'Black' }
		);

		if type(Info.Tooltip) == 'string' then
			Library:AddToolTip(Info.Tooltip, SliderOuter)
		end

		local get_count = function()
			local parent, count = Slider, 1;
			repeat
				parent = parent.Parent or nil;
				if (parent) then
					count += 1;
				end
			until not parent;
			return count;
		end;

		function Slider:UpdateColors()
			Fill.BackgroundColor3 = Library.AccentColor;
			Fill.BorderColor3 = Library.AccentColorDark;
		end;

		---Repaint the label and hand the fill its new target width.
		---@param Instant boolean? skip the lerp, used by the build and resize paths
		function Slider:Display(Instant)
			local Suffix = Info.Suffix or '';

			if Info.Compact then
				DisplayLabel.Text = Info.Text .. ': ' .. Slider.Value .. Suffix
			elseif Info.HideMax then
				DisplayLabel.Text = string.format('%s', Slider.Value .. Suffix)
			else
				DisplayLabel.Text = string.format('%s/%s', Slider.Value .. Suffix, Slider.Max .. Suffix);
			end

			local X = math.ceil(Library:MapValue(Slider.Value, Slider.Min, Slider.Max, 0, Slider.MaxSize));

			-- The bar itself is eased by the shared render loop, so the visible
			-- width trails the value instead of jumping to it.
			Library:SetSliderFill(Fill, X, Instant, function(Shown)
				HideBorderRight.Visible = not (Shown >= Slider.MaxSize or Shown <= 0);
			end);
		end;

		function Slider:OnChanged(Func)
			Slider.Changed = Func;
			Func(Slider.Value);
		end;

		local function Round(Value)
			if (Slider.Increment) then
				return math.round(Value / Slider.Increment) * Slider.Increment;
			elseif Slider.Rounding == 0 then
				return math.floor(Value);
			end;

			return tonumber(string.format('%.' .. Slider.Rounding .. 'f', Value))
		end;

		function Slider:GetValueFromXOffset(X)
			return Round(Library:MapValue(X, 0, Slider.MaxSize, Slider.Min, Slider.Max));
		end;

		function Slider:Remove()
			for _, blank in Blanks do
				blank:Destroy();
			end;
			Options[Idx] = nil;
			SliderOuter:Destroy();
			table.clear(Slider);
			Groupbox:Resize();
		end;

		function Slider:SetValue(Str)
			local Num = tonumber(Str);

			if (not Num) then
				return;
			end;

			Num = math.clamp(Num, Slider.Min, Slider.Max);

			Slider.Value = Num;
			Slider:Display();

			Library:SafeCallback(Slider.Callback, Slider.Value);
			Library:SafeCallback(Slider.Changed, Slider.Value);
		end;

		if (get_count() < 3) then
			function Slider:AddSlider(idx, info)
				Slider:Display(true);
				return Funcs.AddSlider(Groupbox, idx, info, Slider);
			end;
		end

		SliderInner.InputBegan:Connect(function(Input)
			if Input.UserInputType == Enum.UserInputType.MouseButton1 and not Library:MouseIsOverOpenedFrame() then
				local mPos = Mouse.X;
				local gPos = Fill.Size.X.Offset;
				local Diff = mPos - (Fill.AbsolutePosition.X + gPos);

				while InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) do
					local nMPos = Mouse.X;
					local nX = math.clamp(gPos + (nMPos - mPos) + Diff, 0, Slider.MaxSize);

					local nValue = Slider:GetValueFromXOffset(nX);
					local OldValue = Slider.Value;
					Slider.Value = nValue;

					Slider:Display();

					if nValue ~= OldValue then
						Library:SafeCallback(Slider.Callback, Slider.Value);
						Library:SafeCallback(Slider.Changed, Slider.Value);
					end;

					RenderStepped:Wait();
				end;

				Library:AttemptSave();
			end;
		end);

		local contextmenu = Library:AddContextMenu(SliderInner);
		contextmenu:AddOption('Copy Flag', function()
			pcall(setclipboard, Slider.Idx);
			task.wait(); Library:Notify('Copied flag to clipboard!', 2);
			contextmenu:Hide();
		end);

		Slider:Display(true);

		local size = get_count();
		local get_slider = function(count)
			local slider = Slider;
			for i=1,count-1 do
				slider = slider.Parent;
			end;
			return slider;
		end;

		-- Sliders are laid out in scale rather than the pixel widths they were
		-- built at, so a row always ends flush with the right edge of the
		-- groupbox no matter how the window is resized. -4 matches what
		-- dropdowns and buttons use, and 2px sits between stacked sliders.
		local GAP = 2;
		local EDGE = 4;

		local RootShare = 1 / size;
		local RootTrim = (EDGE + (GAP * (size - 1))) / size;

		for i = size, 1, -1 do
			local slider = get_slider(i);

			if i == size then
				-- Root sits straight in the groupbox container.
				slider.Outer.Size = UDim2.new(RootShare, -RootTrim, 0, 13);
			else
				-- Nested sliders live inside their parent's frame, so matching
				-- the parent's width keeps every column equal.
				slider.Outer.Size = UDim2.new(1, 0, 0, 13);
				slider.Outer.Position = UDim2.new(1, GAP, 0, 0);
			end;

			slider.MaxSize = math.max(slider.Outer.AbsoluteSize.X - 2, 1);
			slider:Display(true);
		end;

		-- Scale sizing means the frame width changes on its own when the window
		-- is dragged, so the value mapping has to be rebuilt from the new width.
		SliderOuter:GetPropertyChangedSignal('AbsoluteSize'):Connect(function()
			if not Slider.Display then
				return;
			end;

			local Width = math.max(SliderOuter.AbsoluteSize.X - 2, 1);

			if Width == Slider.MaxSize then
				return;
			end;

			Slider.MaxSize = Width;
			Slider:Display(true);
		end);

		if (not SliderParent) then
			table.insert(Blanks, Groupbox:AddBlank(Info.BlankSize or 6));
			Groupbox:Resize();
		end;
		Options[Idx] = Slider;

		return Slider;
	end;

	function Funcs:AddDropdown(Idx, Info)
		if Info.SpecialType == 'Player' then
			Info.Values = GetPlayersString();
			Info.AllowNull = true;
		elseif Info.SpecialType == 'Team' then
			Info.Values = GetTeamsString();
			Info.AllowNull = true;
		end;

		assert(Info.Values, 'AddDropdown: Missing dropdown value list.');
		assert(Info.AllowNull or Info.Default, 'AddDropdown: Missing default value. Pass `AllowNull` as true if this was intentional.')

		if (not Info.Text) then
			Info.Compact = true;
		end;

		local Blanks = { };
		local Dropdown = {
			Illegal = Info.Illegal;
			Values = Info.Values;
			Value = Info.Multi and {};
			Multi = Info.Multi;
			Type = 'Dropdown';
			SpecialType = Info.SpecialType; -- can be either 'Player' or 'Team'
			Callback = Info.Callback or function(Value) end;
			Idx = Idx;
		};

		local Groupbox = self;
		local Container = Groupbox.Container;

		local RelativeOffset = 0;

		if not Info.Compact then
			local DropdownLabel = Library:CreateLabel({
				Size = UDim2.new(1, 0, 0, 10);
				TextSize = 14;
				Text = Info.Text;
				TextXAlignment = Enum.TextXAlignment.Left;
				TextYAlignment = Enum.TextYAlignment.Bottom;
				ZIndex = 5;
				Parent = Container;
			});

			table.insert(Blanks, DropdownLabel);
			table.insert(Blanks, Groupbox:AddBlank(3));
		end

		for _, Element in next, Container:GetChildren() do
			if not Element:IsA('UIListLayout') then
				RelativeOffset = RelativeOffset + Element.Size.Y.Offset;
			end;
		end;

		local DropdownOuter = Library:Create('Frame', {
			BackgroundColor3 = Color3.new(0, 0, 0);
			BorderColor3 = Color3.new(0, 0, 0);
			Size = UDim2.new(1, -4, 0, 20);
			ZIndex = 5;
			Parent = Container;
		});

		Library:AddToRegistry(DropdownOuter, {
			BorderColor3 = 'Black';
		});

		local DropdownInner = Library:Create('Frame', {
			BackgroundColor3 = Library.MainColor;
			BorderColor3 = Library.OutlineColor;
			BorderMode = Enum.BorderMode.Inset;
			Size = UDim2.new(1, 0, 1, 0);
			ZIndex = 6;
			Parent = DropdownOuter;
		});

		Library:AddToRegistry(DropdownInner, {
			BackgroundColor3 = 'MainColor';
			BorderColor3 = 'OutlineColor';
		});

		Library:Create('UIGradient', {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(212, 212, 212))
			});
			Rotation = 90;
			Parent = DropdownInner;
		});

		local DropdownArrow = Library:Create('ImageLabel', {
			AnchorPoint = Vector2.new(0, 0.5);
			BackgroundTransparency = 1;
			Position = UDim2.new(1, -16, 0.5, 0);
			Size = UDim2.new(0, 12, 0, 12);
			Image = 'http://www.roblox.com/asset/?id=6282522798';
			ZIndex = 8;
			Parent = DropdownInner;
		});

		local ItemList = Library:CreateLabel({
			Position = UDim2.new(0, 5, 0, 0);
			Size = UDim2.new(1, -5, 1, 0);
			TextSize = 14;
			Text = '--';
			TextXAlignment = Enum.TextXAlignment.Left;
			TextWrapped = true;
			ZIndex = 7;
			Parent = DropdownInner;
		});

		Library:OnHighlight(DropdownOuter, DropdownOuter,
			{ BorderColor3 = 'AccentColor' },
			{ BorderColor3 = 'Black' }
		);

		if type(Info.Tooltip) == 'string' then
			Library:AddToolTip(Info.Tooltip, DropdownOuter)
		end

		local MAX_DROPDOWN_ITEMS = 8;

		-- Declared up here so the size helpers below can tell an open list from a
		-- closed one while the reveal animation is running.
		local _visible = false;

		local ListOuter = Library:Create('Frame', {
			BackgroundColor3 = Color3.new(0, 0, 0);
			BorderColor3 = Color3.new(0, 0, 0);
			ClipsDescendants = true;
			ZIndex = 20;
			Visible = false;
			Parent = ScreenGui;
		});

		-- Full height the list wants once it is open. The frame itself is grown
		-- into this, so it has to be tracked separately from the live size.
		local ListTargetY = MAX_DROPDOWN_ITEMS * 20 + 2;
		local ListTween = nil;

		local function RecalculateListPosition()
			ListOuter.Position = UDim2.fromOffset(DropdownOuter.AbsolutePosition.X, DropdownOuter.AbsolutePosition.Y + DropdownOuter.Size.Y.Offset + 1);
		end;

		local function RecalculateListSize(YSize)
			ListTargetY = YSize or (MAX_DROPDOWN_ITEMS * 20 + 2);
			ListOuter.Size = UDim2.fromOffset(DropdownOuter.AbsoluteSize.X, _visible and ListTargetY or 0);
		end;

		RecalculateListPosition();
		RecalculateListSize();

		DropdownOuter:GetPropertyChangedSignal('AbsolutePosition'):Connect(RecalculateListPosition);

		local ListInner = Library:Create('Frame', {
			BackgroundColor3 = Library.MainColor;
			BorderColor3 = Library.OutlineColor;
			BorderMode = Enum.BorderMode.Inset;
			BorderSizePixel = 0;
			Size = UDim2.new(1, 0, 1, 0);
			ZIndex = 21;
			Parent = ListOuter;
		});

		Library:AddToRegistry(ListInner, {
			BackgroundColor3 = 'MainColor';
			BorderColor3 = 'OutlineColor';
		});

		local Scrolling = Library:Create('ScrollingFrame', {
			BackgroundTransparency = 1;
			BorderSizePixel = 0;
			CanvasSize = UDim2.new(0, 0, 0, 0);
			Size = UDim2.new(1, 0, 1, 0);
			ZIndex = 21;
			Parent = ListInner;

			TopImage = 'rbxasset://textures/ui/Scroll/scroll-middle.png',
			BottomImage = 'rbxasset://textures/ui/Scroll/scroll-middle.png',

			ScrollBarThickness = 3,
			ScrollBarImageColor3 = Library.AccentColor,
		});

		Library:AddToRegistry(Scrolling, {
			ScrollBarImageColor3 = 'AccentColor'
		})

		Library:Create('UIListLayout', {
			Padding = UDim.new(0, 0);
			FillDirection = Enum.FillDirection.Vertical;
			SortOrder = Enum.SortOrder.LayoutOrder;
			Parent = Scrolling;
		});

		function Dropdown:Display()
			local Values = Dropdown.Values;
			local Str = '';

			if Info.Multi then
				for Idx, Value in next, Values do
					if Dropdown.Value[Value] then
						Str = Str .. Value .. ', ';
					end;
				end;

				Str = Str:sub(1, #Str - 2);
			else
				Str = Dropdown.Value or '';
			end;

			ItemList.Text = (Str == '' and '--' or Str);
		end;

		function Dropdown:GetActiveValues()
			if Info.Multi then
				local T = {};

				for Value, Bool in next, Dropdown.Value do
					table.insert(T, Value);
				end;

				return T;
			else
				return Dropdown.Value and 1 or 0;
			end;
		end;

		function Dropdown:BuildDropdownList()
			local Values = Dropdown.Values;
			local Buttons = {};

			for _, Element in next, Scrolling:GetChildren() do
				if not Element:IsA('UIListLayout') then
					Element:Destroy();
				end;
			end;

			local Count = 0;

			for Idx, Value in next, Values do
				local Table = {};

				Count = Count + 1;

				local Button = Library:Create('Frame', {
					BackgroundColor3 = Library.MainColor;
					BorderColor3 = Library.OutlineColor;
					BorderMode = Enum.BorderMode.Middle;
					Size = UDim2.new(1, -1, 0, 20);
					ZIndex = 23;
					Active = true,
					Parent = Scrolling;
				});

				Library:AddToRegistry(Button, {
					BackgroundColor3 = 'MainColor';
					BorderColor3 = 'OutlineColor';
				});

				local ButtonLabel = Library:CreateLabel({
					Active = false;
					Size = UDim2.new(1, -6, 1, 0);
					Position = UDim2.new(0, 6, 0, 0);
					TextSize = 14;
					Text = Value;
					TextXAlignment = Enum.TextXAlignment.Left;
					ZIndex = 25;
					Parent = Button;
				});

				Library:OnHighlight(Button, Button,
					{ BorderColor3 = 'AccentColor', ZIndex = 24 },
					{ BorderColor3 = 'OutlineColor', ZIndex = 23 }
				);

				local Selected;

				if Info.Multi then
					Selected = Dropdown.Value[Value];
				else
					Selected = Dropdown.Value == Value;
				end;

				function Table:UpdateButton()
					if Info.Multi then
						Selected = Dropdown.Value[Value];
					else
						Selected = Dropdown.Value == Value;
					end;

					ButtonLabel.TextColor3 = Selected and Library.AccentColor or Library.FontColor;
					Library.RegistryMap[ButtonLabel].Properties.TextColor3 = Selected and 'AccentColor' or 'FontColor';
				end;

				ButtonLabel.InputBegan:Connect(function(Input)
					if Input.UserInputType == Enum.UserInputType.MouseButton1 then
						local Try = not Selected;

						if Dropdown:GetActiveValues() == 1 and (not Try) and (not Info.AllowNull) then
						else
							if Info.Multi then
								Selected = Try;

								if Selected then
									Dropdown.Value[Value] = true;
								else
									Dropdown.Value[Value] = nil;
								end;
							else
								Selected = Try;

								if Selected then
									Dropdown.Value = Value;
								else
									Dropdown.Value = nil;
								end;

								for _, OtherButton in next, Buttons do
									OtherButton:UpdateButton();
								end;
							end;

							Table:UpdateButton();
							Dropdown:Display();

							Library:SafeCallback(Dropdown.Callback, Dropdown.Value);
							Library:SafeCallback(Dropdown.Changed, Dropdown.Value);

							Library:AttemptSave();
						end;
					end;
				end);

				Table:UpdateButton();
				Dropdown:Display();

				Buttons[Button] = Table;
			end;

			Scrolling.CanvasSize = UDim2.fromOffset(0, (Count * 20) + 1);

			local Y = math.clamp(Count * 20, 0, MAX_DROPDOWN_ITEMS * 20) + 1;
			RecalculateListSize(Y);
		end;

		function Dropdown:SetValues(NewValues)
			if NewValues then
				Dropdown.Values = NewValues;
			end;

			Dropdown:BuildDropdownList();
		end;

		---Grow or collapse the list, spinning the arrow with it. The frame is
		---only hidden once the collapse finishes so the animation stays visible.
		---@param Open boolean
		local function AnimateList(Open)
			if ListTween then
				ListTween:Cancel();
				ListTween = nil;
			end;

			local Time = tonumber(Library.DropdownAnimationTime) or 0;
			local Goal = UDim2.fromOffset(DropdownOuter.AbsoluteSize.X, Open and ListTargetY or 0);

			if Time <= 0 then
				ListOuter.Size = Goal;
				DropdownArrow.Rotation = Open and 180 or 0;
				ListOuter.Visible = Open;
				return;
			end;

			local Style = TweenInfo.new(Time, Enum.EasingStyle.Quint, Enum.EasingDirection.Out);

			TweenService:Create(DropdownArrow, Style, { Rotation = Open and 180 or 0 }):Play();

			ListTween = TweenService:Create(ListOuter, Style, { Size = Goal });

			ListTween.Completed:Connect(function(State)
				if State == Enum.PlaybackState.Completed and (not _visible) then
					ListOuter.Visible = false;
				end;
			end);

			ListTween:Play();
		end;

		function Dropdown:OpenDropdown()
			_visible = true;
			ListOuter.Size = UDim2.fromOffset(DropdownOuter.AbsoluteSize.X, 0);
			ListOuter.Visible = true;
			Library.OpenedFrames[ListOuter] = true;
			AnimateList(true);
		end;

		function Dropdown:CloseDropdown()
			_visible = false;
			Library.OpenedFrames[ListOuter] = nil;
			AnimateList(false);
		end;

		function Dropdown:OnChanged(Func)
			Dropdown.Changed = Func;
			Func(Dropdown.Value);
		end;

		function Dropdown:SetValue(Val)
			if Dropdown.Multi then
				local nTable = {};

				if (type(Val) == "string") then
					Val = {[Val] = true};
				end;

				for Value, Bool in next, Val do
					if Dropdown.Illegal or table.find(Dropdown.Values, Value) then
						nTable[Value] = true
					end;
				end;

				Dropdown.Value = nTable;
			else
				if (not Val) then
					Dropdown.Value = nil;
				elseif Dropdown.Illegal or table.find(Dropdown.Values, Val) then
					Dropdown.Value = Val;
				end;
			end;

			Dropdown:BuildDropdownList();

			Library:SafeCallback(Dropdown.Callback, Dropdown.Value);
			Library:SafeCallback(Dropdown.Changed, Dropdown.Value);
		end;

		function Dropdown:Remove()
			for _, blank in Blanks do
				blank:Destroy();
			end;
			Options[Idx] = nil;
			DropdownOuter:Destroy();
			table.clear(Dropdown);
		end;

		DropdownOuter.InputBegan:Connect(function(Input)
			if Input.UserInputType == Enum.UserInputType.MouseButton1 and not Library:MouseIsOverOpenedFrame() then
				-- Tracked state rather than .Visible, which is still true while
				-- the collapse animation plays out.
				if _visible then
					Dropdown:CloseDropdown();
				else
					Dropdown:OpenDropdown();
				end;
			end;
		end);

		Library:BindToInput(Enum.UserInputType.MouseButton1, function()
			if (not _visible) then
				return;
			end;
			local AbsPos, AbsSize = ListOuter.AbsolutePosition, ListOuter.AbsoluteSize;
			if Mouse.X < AbsPos.X or Mouse.X > AbsPos.X + AbsSize.X
				or Mouse.Y < (AbsPos.Y - 20 - 1) or Mouse.Y > AbsPos.Y + AbsSize.Y then

				Dropdown:CloseDropdown();
			end;
		end);

		local contextmenu = Library:AddContextMenu(DropdownOuter);
		contextmenu:AddOption('Copy Flag', function()
			pcall(setclipboard, Dropdown.Idx);
			task.wait(); Library:Notify('Copied flag to clipboard!', 2);
			contextmenu:Hide();
		end);

		Dropdown:BuildDropdownList();
		Dropdown:Display();

		local Defaults = {}

		if type(Info.Default) == 'string' then
			local Idx = table.find(Dropdown.Values, Info.Default)
			if Idx then
				table.insert(Defaults, Idx)
			end
		elseif type(Info.Default) == 'table' then
			for _, Value in next, Info.Default do
				local Idx = table.find(Dropdown.Values, Value)
				if Idx then
					table.insert(Defaults, Idx)
				end
			end
		elseif type(Info.Default) == 'number' and Dropdown.Values[Info.Default] ~= nil then
			table.insert(Defaults, Info.Default)
		end

		if next(Defaults) then
			for i = 1, #Defaults do
				local Index = Defaults[i]
				if Info.Multi then
					Dropdown.Value[Dropdown.Values[Index]] = true
				else
					Dropdown.Value = Dropdown.Values[Index];
				end

				if (not Info.Multi) then break end
			end

			Dropdown:BuildDropdownList();
			Dropdown:Display();
		end

		table.insert(Blanks, Groupbox:AddBlank(Info.BlankSize or 5));
		Groupbox:Resize();

		Options[Idx] = Dropdown;

		return Dropdown;
	end;

	function Funcs:AddDependencyBox()
		local Depbox = {
			Dependencies = {};
		};

		local Groupbox = self;
		local Container = Groupbox.Container;

		local Holder = Library:Create('Frame', {
			BackgroundTransparency = 1;
			Size = UDim2.new(1, 0, 0, 0);
			Visible = false;
			Parent = Container;
		});

		local Frame = Library:Create('Frame', {
			BackgroundTransparency = 1;
			Size = UDim2.new(1, 0, 1, 0);
			Visible = true;
			Parent = Holder;
		});

		local Layout = Library:Create('UIListLayout', {
			FillDirection = Enum.FillDirection.Vertical;
			SortOrder = Enum.SortOrder.LayoutOrder;
			Parent = Frame;
		});

		function Depbox:Resize()
			Holder.Size = UDim2.new(1, 0, 0, Layout.AbsoluteContentSize.Y);
			Groupbox:Resize();
		end;

		Layout:GetPropertyChangedSignal('AbsoluteContentSize'):Connect(function()
			Depbox:Resize();
		end);

		Holder:GetPropertyChangedSignal('Visible'):Connect(function()
			Depbox:Resize();
		end);

		function Depbox:Update()
			for _, Dependency in next, Depbox.Dependencies do
				local Elem = Dependency[1];
				local Value = Dependency[2];

				if Elem.Type == 'Toggle' and Elem.Value ~= Value then
					Holder.Visible = false;
					Depbox:Resize();
					return;
				end;
			end;

			Holder.Visible = true;
			Depbox:Resize();
		end;

		function Depbox:SetupDependencies(Dependencies)
			for _, Dependency in next, Dependencies do
				assert(type(Dependency) == 'table', 'SetupDependencies: Dependency is not of type `table`.');
				assert(Dependency[1], 'SetupDependencies: Dependency is missing element argument.');
				assert(Dependency[2] ~= nil, 'SetupDependencies: Dependency is missing value argument.');
			end;

			Depbox.Dependencies = Dependencies;
			Depbox:Update();
		end;

		function Depbox:Remove()
			Holder:Destroy();
			table.remove(Library.DependencyBoxes, table.find(Library.DependencyBoxes, Depbox));
			table.clear(Depbox);
			Groupbox:Resize();
		end;

		Depbox.Container = Frame;

		setmetatable(Depbox, BaseGroupbox);

		table.insert(Library.DependencyBoxes, Depbox);

		return Depbox;
	end;

	-- Which Add* functions produce something worth searching for, and which
	-- argument carries the display text.
	local SearchableFuncs = {
		AddToggle = 2;
		AddSlider = 2;
		AddDropdown = 2;
		AddInput = 2;
		AddLabel = 1;
		AddButton = 1;
	};

	for FuncName, TextArg in next, SearchableFuncs do
		local Original = Funcs[FuncName];

		if Original then
			Funcs[FuncName] = function(Groupbox, ...)
				local Container = type(Groupbox) == 'table' and Groupbox.Container or nil;

				-- Snapshot the container so we can tell which frames this call added.
				local Before = {};
				if Container then
					for _, Child in next, Container:GetChildren() do
						Before[Child] = true;
					end;
				end;

				local Result = Original(Groupbox, ...);

				if Container then
					local Arg = select(TextArg, ...);
					local Text;

					if type(Arg) == 'table' then
						Text = Arg.Text or Arg.Title;
					elseif type(Arg) == 'string' then
						Text = Arg;
					end;

					if (not Text) and type(Result) == 'table' and type(Result.Text) == 'string' then
						Text = Result.Text;
					end;

					if type(Text) == 'string' and Text ~= '' then
						local Instances = {};

						for _, Child in next, Container:GetChildren() do
							if (not Before[Child]) and (not Child:IsA('UIListLayout')) then
								table.insert(Instances, Child);
							end;
						end;

						table.insert(Library.SearchIndex, {
							Name = Text;
							Type = (type(Result) == 'table' and Result.Type) or string.sub(FuncName, 4);
							Idx = type(Result) == 'table' and Result.Idx or nil;
							Instances = Instances;
							Container = Container;
						});
					end;
				end;

				return Result;
			end;
		end;
	end;

	BaseGroupbox.__index = Funcs;
	BaseGroupbox.__namecall = function(Table, Key, ...)
		return Funcs[Key](...);
	end;
end;

-- < Create other UI elements >
do
	local ns_init = Library.NotificationStyle or {};
	local align_map = { Left = 0, Center = 0.5, Right = 1 };
	local anchor_x = align_map[ns_init.Alignment] or 0;
	local anchor_y = ((ns_init.Y or 0) < 0.5) and 0 or 1;

	Library.NotificationAreaHolder = Library:Create('Frame', {
		BackgroundTransparency = 1;
		AnchorPoint = Vector2.new(anchor_x, anchor_y);
		Position = UDim2.new(ns_init.X or 0, 0, ns_init.Y or 0, 0);
		Size = UDim2.new(0, 200, 0, 200);
		ZIndex = 100;
		Parent = ScreenGui;
	});

	Library.NotificationArea = Library:Create('Frame', {
		BackgroundTransparency = 1;
		Position = UDim2.new(0, 0, 0, 1);
		Size = UDim2.new(1, 0, 1, 0);
		ZIndex = 100;
		Parent = Library.NotificationAreaHolder;
	});

	local listLayout = Library:Create('UIListLayout', {
		Padding = UDim.new(0, 4);
		FillDirection = Enum.FillDirection.Vertical;
		SortOrder = Enum.SortOrder.LayoutOrder;
		Parent = Library.NotificationArea;
	});
	Library.NotificationListLayout = listLayout;
	listLayout.VerticalAlignment = (anchor_y == 0) and Enum.VerticalAlignment.Top or Enum.VerticalAlignment.Bottom;

	local WatermarkOuter = Library:Create('Frame', {
		BorderColor3 = Color3.new(0, 0, 0);
		Position = UDim2.new(0, 100, 0, -25);
		Size = UDim2.new(0, 213, 0, 22);
		ZIndex = 200;
		Visible = false;
		Parent = ScreenGui;
	});

	local WatermarkInner = Library:Create('Frame', {
		BackgroundColor3 = Library.MainColor;
		BorderColor3 = Library.AccentColor;
		BorderMode = Enum.BorderMode.Inset;
		Size = UDim2.new(1, 0, 1, 0);
		ZIndex = 201;
		Parent = WatermarkOuter;
	});

	Library:AddToRegistry(WatermarkInner, {
		BorderColor3 = 'AccentColor';
	});

	local InnerFrame = Library:Create('Frame', {
		BackgroundColor3 = Color3.new(1, 1, 1);
		BorderSizePixel = 0;
		Position = UDim2.new(0, 1, 0, 1);
		Size = UDim2.new(1, -2, 1, -2);
		ZIndex = 202;
		Parent = WatermarkInner;
	});

	local Gradient = Library:Create('UIGradient', {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Library:GetDarkerColor(Library.MainColor)),
			ColorSequenceKeypoint.new(1, Library.MainColor),
		});
		Rotation = -90;
		Parent = InnerFrame;
	});

	Library:AddToRegistry(Gradient, {
		Color = function()
			return ColorSequence.new({
				ColorSequenceKeypoint.new(0, Library:GetDarkerColor(Library.MainColor)),
				ColorSequenceKeypoint.new(1, Library.MainColor),
			});
		end
	});

	-- Accent bar down the left edge, so the watermark reads as a status strip
	-- rather than a floating box of text.
	local WatermarkAccent = Library:Create('Frame', {
		BackgroundColor3 = Library.AccentColor;
		BorderSizePixel = 0;
		Size = UDim2.new(0, 2, 1, 0);
		ZIndex = 203;
		Parent = InnerFrame;
	});

	Library:AddToRegistry(WatermarkAccent, {
		BackgroundColor3 = 'AccentColor';
	}, true);

	-- Underline that fades out toward the right, purely decorative.
	local WatermarkUnderline = Library:Create('Frame', {
		BackgroundColor3 = Library.AccentColor;
		BorderSizePixel = 0;
		Position = UDim2.new(0, 2, 1, -1);
		Size = UDim2.new(1, -2, 0, 1);
		ZIndex = 203;
		Parent = InnerFrame;
	});

	Library:Create('UIGradient', {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0);
			NumberSequenceKeypoint.new(1, 1);
		});
		Parent = WatermarkUnderline;
	});

	Library:AddToRegistry(WatermarkUnderline, {
		BackgroundColor3 = 'AccentColor';
	}, true);

	local WatermarkLabel = Library:CreateLabel({
		Position = UDim2.new(0, 9, 0, 0);
		Size = UDim2.new(1, -12, 1, 0);
		TextSize = 14;
		RichText = true;
		TextXAlignment = Enum.TextXAlignment.Left;
		ZIndex = 204;
		Parent = InnerFrame;
	});

	Library.Watermark = WatermarkOuter;
	Library.WatermarkText = WatermarkLabel;
	Library.WatermarkAccent = WatermarkAccent;
	Library:MakeDraggable(Library.Watermark);



	-- < Keybind list >
	-- Reworked: accent bar and a centred heading over an accent divider, with
	-- one RichText row per bind so the key, the name and the mode can each carry
	-- their own colour inside a single measurable TextLabel.
	local KeybindOuter = Library:Create('Frame', {
		AnchorPoint = Vector2.new(0, 0.5);
		BorderColor3 = Color3.new(0, 0, 0);
		Position = UDim2.new(0, 10, 0.5, 0);
		Size = UDim2.new(0, 190, 0, 28);
		Visible = false;
		ZIndex = 100;
		Parent = ScreenGui;
	});

	local KeybindInner = Library:Create('Frame', {
		BackgroundColor3 = Library.MainColor;
		BorderColor3 = Library.OutlineColor;
		BorderMode = Enum.BorderMode.Inset;
		Size = UDim2.new(1, 0, 1, 0);
		ZIndex = 101;
		Parent = KeybindOuter;
	});

	Library:AddToRegistry(KeybindInner, {
		BackgroundColor3 = 'MainColor';
		BorderColor3 = 'OutlineColor';
	}, true);

	Library:AddToRegistry(KeybindOuter, {
		BackgroundColor3 = 'MainColor';
	}, true);

	-- Vertical sheen so the panel does not read as one flat block.
	Library:Create('UIGradient', {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(214, 214, 214)),
		});
		Rotation = 90;
		Parent = KeybindInner;
	});

	local ColorFrame = Library:Create('Frame', {
		BackgroundColor3 = Library.AccentColor;
		BorderSizePixel = 0;
		Size = UDim2.new(1, 0, 0, 2);
		ZIndex = 102;
		Parent = KeybindInner;
	});

	Library:AddToRegistry(ColorFrame, {
		BackgroundColor3 = 'AccentColor';
	}, true);

	Library:Create('UIGradient', {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(170, 170, 170)),
			ColorSequenceKeypoint.new(1, Color3.new(1, 1, 1)),
		});
		Parent = ColorFrame;
	});

	local KeybindLabel = Library:CreateLabel({
		Size = UDim2.new(1, -12, 0, 18);
		Position = UDim2.fromOffset(6, 3),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = 14;

		Text = Library.KeybindListTitle or 'Keybinds';
		ZIndex = 104;
		Parent = KeybindInner;
	});

	-- Separates the heading from the rows.
	local KeybindDivider = Library:Create('Frame', {
		BackgroundColor3 = Library.AccentColor;
		BackgroundTransparency = 0.45;
		BorderSizePixel = 0;
		Position = UDim2.new(0, 6, 0, 21);
		Size = UDim2.new(1, -12, 0, 1);
		ZIndex = 103;
		Parent = KeybindInner;
	});

	Library:AddToRegistry(KeybindDivider, {
		BackgroundColor3 = 'AccentColor';
	}, true);

	local KeybindContainer = Library:Create('Frame', {
		BackgroundTransparency = 1;
		Size = UDim2.new(1, 0, 1, -24);
		Position = UDim2.new(0, 0, 0, 24);
		ZIndex = 1;
		Parent = KeybindInner;
	});

	Library:Create('UIListLayout', {
		FillDirection = Enum.FillDirection.Vertical;
		SortOrder = Enum.SortOrder.LayoutOrder;
		Parent = KeybindContainer;
	});

	Library:Create('UIPadding', {
		PaddingLeft = UDim.new(0, 7),
		PaddingRight = UDim.new(0, 7),
		Parent = KeybindContainer,
	})

	Library.KeybindFrame = KeybindOuter;
	Library.KeybindContainer = KeybindContainer;
	Library.KeybindTitleLabel = KeybindLabel;
	Library:MakeDraggable(KeybindOuter);
end;

---Heading of the keybind list.
---@param Text string
function Library:SetKeybindListTitle(Text)
	Library.KeybindListTitle = tostring(Text or 'Keybinds');

	if Library.KeybindTitleLabel then
		Library.KeybindTitleLabel.Text = Library.KeybindListTitle;
	end;
end;

---Rebuild every keybind row. Row colours are baked into RichText, so they
---cannot ride the registry and need redoing when the accent moves.
function Library:RefreshKeybindList()
	for _, Option in next, Options do
		if type(Option) == 'table' and Option.Type == 'KeyPicker' and Option.Update then
			pcall(Option.Update, Option);
		end;
	end;
end;

function Library:SetWatermarkVisibility(Bool)
	Library.Watermark.Visible = Bool;
end;

---Set the watermark text. Pipes act as segment dividers and get the accent
---colour, so "orange.gg | user | 240 fps" renders like an external overlay.
---Pass Raw = true to hand RichText markup through untouched.
---@param Text string
---@param Raw boolean|nil
function Library:SetWatermark(Text, Raw)
	Library.WatermarkRawText = tostring(Text or '');
	Library.WatermarkIsRaw = Raw == true;

	Library:RefreshWatermark();
	Library:SetWatermarkVisibility(true);
end;

---Rebuild the watermark markup from the stored plain text. Called again on
---accent changes because RichText colours are baked into the string and so
---cannot ride the registry.
function Library:RefreshWatermark()
	local Plain = Library.WatermarkRawText;

	if type(Plain) ~= 'string' or not Library.WatermarkText then
		return;
	end;

	local X, Y = Library:GetTextBounds(Plain, Library.Font, 14);
	Library.Watermark.Size = UDim2.new(0, X + 20, 0, (Y * 1.5) + 5);

	if Library.WatermarkIsRaw then
		Library.WatermarkText.Text = Plain;
		return;
	end;

	local Divider = Library:ColorRichText('|', Library.AccentColor);
	local Built = { };

	for Segment in string.gmatch(Plain .. '|', '([^|]*)|') do
		table.insert(Built, Library:ColorRichText(Segment, Library.FontColor));
	end;

	Library.WatermarkText.Text = table.concat(Built, Divider);
end;

local NotifySettings = {
	BarPosition = {
		["Top"] = UDim2.new(0, -1, 0, 0);
		["Left"] = UDim2.new(0, -1, 0, -1);
		["Right"] = UDim2.new(1, -2, 0, -1);
		["Bottom"] = UDim2.new(0, -1, 1, -2);
	};
	BarSize = {
		["Top"] = UDim2.new(1, 3, 0, 2);
		["Left"] = UDim2.new(0, 3, 1, 2);
		["Right"] = UDim2.new(0, 3, 1, 2);
		["Bottom"] = UDim2.new(1, 3, 0, 2);
	};
};

local NotificationStyle = Library.NotificationStyle;

local _char, _max = string.char, math.max;


local get_notification_colors = function()
	local callback = NotificationStyle.OverrideColor;
	if (callback) then
		return callback();
	end;
	return Library.MainColor, Library.AccentColor, Library.OutlineColor, Library.FontColor;
end;

local notification_clone;
do
	local NotifyOuter = Library:Create('Frame', {
		--Transparency = transparency;
		--BackgroundColor3 = main;
		BorderColor3 = Color3.new(0, 0, 0);
		Position = UDim2.new(0, 100, 0, 10);
		--Size = UDim2.new(0, 0, 0, YSize);
		ClipsDescendants = true;
		ZIndex = 100;
		--Parent = Library.NotificationArea;
		--Name = _char(256 - _max(1, #Text % 256)); -- so it filters by text length if thats on
	});

	local NotifyInner = Library:Create('Frame', {
		--BackgroundColor3 = main;
		--BorderColor3 = outline;
		BorderMode = Enum.BorderMode.Inset;
		Size = UDim2.new(1, 0, 1, 0);
		ZIndex = 101;
		Parent = NotifyOuter;
		--Transparency = transparency;
		Name = "inner";
	});

	--Library:AddToRegistry(NotifyInner, {
	--	BackgroundColor3 = 'MainColor';
	--	BorderColor3 = 'OutlineColor';
	--}, true);

	local InnerFrame = Library:Create('Frame', {
		BackgroundColor3 = Color3.new(1, 1, 1);
		BorderSizePixel = 0;
		Position = UDim2.new(0, 1, 0, 1);
		Size = UDim2.new(1, -2, 1, -2);
		ZIndex = 102;
		Parent = NotifyInner;
		Name = "inner";
	});

	local Gradient = Library:Create('UIGradient', {
		--Color = ColorSequence.new({
		--	ColorSequenceKeypoint.new(0, Library:GetDarkerColor(Library.MainColor)),
		--	ColorSequenceKeypoint.new(1, Library.MainColor),
		--});
		Rotation = -90;
		Parent = InnerFrame;
	});



	--Library:AddToRegistry(Gradient, {
	--	Color = function()
	--		return ColorSequence.new({
	--			ColorSequenceKeypoint.new(0, Library:GetDarkerColor(Library.MainColor)),
	--			ColorSequenceKeypoint.new(1, Library.MainColor),
	--		});
	--	end
	--});

	local NotifyLabel = Library:CreateLabel({
		Position = UDim2.new(0, 4, 0, 0);
		Size = UDim2.new(1, -4, 1, 0);
		--Text = Text;
		TextXAlignment = Enum.TextXAlignment.Left;
		TextSize = 14;
		ZIndex = 103;
		Name = "label";
		Parent = InnerFrame;
	});



	local LeftColor = Library:Create('Frame', {
		--BackgroundColor3 = accent;
		BorderSizePixel = 0;
		--Position = NotifySettings.BarPosition[NotificationStyle.BarSide];
		-- = NotifySettings.BarSize[NotificationStyle.BarSide] or UDim2.new(0, 3, 1, 2);
		ZIndex = 104;
		Name = "bar";
		Parent = NotifyOuter;
	});

	--Library:AddToRegistry(LeftColor, {
	--	BackgroundColor3 = 'AccentColor';
	--}, true);

	notification_clone = NotifyOuter;
end;


function Library:CreatePopout(Config)
	if type(Config.Title) ~= 'string' then Config.Title = 'No title' end;

	if typeof(Config.Position) ~= 'UDim2' then Config.Position = UDim2.fromOffset(175, 50) end;

	-- Size comes in as a Vector2 normally, but a UDim2 or nothing at all has to
	-- survive too, since Resize below reads Config.Size.X straight back out.
	if typeof(Config.Size) == 'UDim2' then
		Config.Size = Vector2.new(Config.Size.X.Offset, Config.Size.Y.Offset);
	elseif typeof(Config.Size) ~= 'Vector2' then
		Config.Size = Vector2.new(300, 200);
	end;

	if type(Config.AutoShow) ~= 'boolean' then
		Config.AutoShow = false;
	end;

	if Config.Center then
		Config.AnchorPoint = Vector2.new(0.5, 0.5);
		Config.Position = UDim2.fromScale(0.5, 0.5);
	end;

	local Window = { };

	local Outer = Library:Create('Frame', {
		AnchorPoint = Config.AnchorPoint,
		BackgroundColor3 = Color3.new(0, 0, 0);
		BorderSizePixel = 0;
		Position = Config.Position,
		Size = UDim2.fromOffset(Config.Size.X, Config.Size.Y),
		Visible = Config.AutoShow;
		ZIndex = 1;
		Parent = ScreenGui;
	});

	Library:MakeDraggableOutline(Outer, 25);

	local Inner = Library:Create('Frame', {
		BackgroundColor3 = Library.MainColor;
		BorderColor3 = Library.OutlineColor;
		BorderMode = Enum.BorderMode.Inset;
		Position = UDim2.new(0, 1, 0, 1);
		Size = UDim2.new(1, -2, 1, -2);
		ZIndex = 1;
		Parent = Outer;
	});

	Library:AddToRegistry(Inner, {
		BackgroundColor3 = 'MainColor';
		BorderColor3 = 'OutlineColor';
	});

	local WindowLabel = Library:CreateLabel({
		Position = UDim2.new(0, 0, 0, 0);
		Size = UDim2.new(1, 0, 0, 25);
		Text = Config.Title or '';
		TextXAlignment = Enum.TextXAlignment.Center;
		ZIndex = 1;
		Parent = Inner;
	});

	local VersionLabel = Library:CreateLabel({
		Position = UDim2.new(0, -8, 0, 0);
		Size = UDim2.new(1, 0, 0, 25);
		Text = Config.Version or '';
		RichText = true;
		TextXAlignment = Enum.TextXAlignment.Right;
		ZIndex = 1;
		Parent = Inner;
	});

	local MainSectionOuter = Library:Create('Frame', {
		BackgroundColor3 = Library.BackgroundColor;
		BorderColor3 = Library.OutlineColor;
		Position = UDim2.new(0, 8, 0, 25);
		Size = UDim2.new(1, -16, 1, -33);
		ZIndex = 1;
		Parent = Inner;
	});

	Library:AddToRegistry(MainSectionOuter, {
		BackgroundColor3 = 'BackgroundColor';
		BorderColor3 = 'OutlineColor';
	});

	local MainSectionInner = Library:Create('Frame', {
		BackgroundColor3 = Library.BackgroundColor;
		BorderColor3 = Color3.new(0, 0, 0);
		BorderMode = Enum.BorderMode.Inset;
		Position = UDim2.new(0, 0, 0, 0);
		Size = UDim2.new(1, 0, 1, 0);
		ZIndex = 1;
		Parent = MainSectionOuter;
	});

	Library:AddToRegistry(MainSectionInner, {
		BackgroundColor3 = 'BackgroundColor';
	});

	local BackgroundFrame = Library:Create('Frame', {
		BackgroundColor3 = Library.BackgroundColor;--MainColor;
		BorderColor3 = Library.OutlineColor;
		Position = UDim2.new(0, 8, 0, 8);
		Size = UDim2.new(1, -16, 1, -16);
		ZIndex = 2;
		Visible = true;
		Parent = MainSectionInner;
	});

	local TabContainer = Library:Create("Frame", {
		BackgroundTransparency = 1;
		Parent = BackgroundFrame;
		Size = UDim2.fromScale(1, 1);
		Position = UDim2.fromOffset(2, 2);
	});

	Library:Create('UIListLayout', {
		Padding = UDim.new(0, 0);
		FillDirection = Enum.FillDirection.Vertical;
		SortOrder = Enum.SortOrder.LayoutOrder;
		HorizontalAlignment = Enum.HorizontalAlignment.Left;
		Parent = TabContainer;
	});

	Library:AddToRegistry(BackgroundFrame, {
		BackgroundColor3 = 'BackgroundColor';
		BorderColor3 = 'OutlineColor';
	});

	Library:AddToRegistry(TabContainer, {
		BackgroundColor3 = 'MainColor';
		BorderColor3 = 'OutlineColor';
	});

	Window.Holder = Outer;
	Window.Container = TabContainer;

	function Window:Resize()
		local Size = 0;

		for _, Element in next, TabContainer:GetChildren() do
			if (not Element:IsA('UIListLayout')) and Element.Visible then
				Size += Element.AbsoluteSize.Y;
			end;
		end;
		Outer.Size = UDim2.fromOffset(Config.Size.X, 16 + Size + (TabContainer.AbsolutePosition.Y - Outer.AbsolutePosition.Y));--(1, 0, 0, 20 + Size + 2 + 2);
	end;

	function Window:Toggle()
		Outer.Visible = not Outer.Visible;
	end;

	function Window:GetSize()
		return TabContainer.AbsoluteSize;
	end;

	TabContainer:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		task.wait();
		Window:Resize();
	end);

	Window:Resize();

	setmetatable(Window, BaseGroupbox);

	return Window;
end;


local udim2_new, colorsequence_new, colorsequencekeypoint_new = UDim2.new, ColorSequence.new, ColorSequenceKeypoint.new;
function Library:Notify(Text, Time)
	local XSize, YSize = Library:GetTextBounds(Text, Library.Font, 14);

	YSize = YSize + 7;

	local ns = Library.NotificationStyle or {};
	local transparency = ns.Transparency or 0;
	local main, accent, outline, font = get_notification_colors();

	local NotifyOuter = notification_clone:Clone();
	NotifyOuter.BackgroundColor3 = main;
	NotifyOuter.Name = _char(256 - _max(1, #Text % 256));
	NotifyOuter.Size = udim2_new(0, 0, 0, YSize);
	NotifyOuter.Transparency = transparency;

	local NotifyInner = NotifyOuter.inner;
	NotifyInner.BackgroundColor3 = main;
	NotifyInner.BorderColor3 = outline;
	NotifyInner.Transparency = transparency;

	local InnerFrame = NotifyInner.inner;
	InnerFrame.Transparency = transparency;

	local Gradient = InnerFrame.UIGradient;
	Gradient.Color = colorsequence_new({
		colorsequencekeypoint_new(0, Library:GetDarkerColor(main)),
		colorsequencekeypoint_new(1, main),
	});

	local NotifyLabel = InnerFrame.label;
	NotifyLabel.Text = Text;
	NotifyLabel.TextColor3 = font;

	local LeftColor = NotifyOuter.bar;
	LeftColor.BackgroundColor3 = accent;
	local side = (ns.BarSide or "Left");
	LeftColor.Size = NotifySettings.BarSize[side] or udim2_new(0, 3, 1, 2);
	LeftColor.Position = NotifySettings.BarPosition[side];

	local align_map = { Left = 0, Center = 0.5, Right = 1 };
	local anchor_x = align_map[ns.Alignment] or 0;
	local anchor_y = ((ns.Y or 0) < 0.5) and 0 or 1;
	Library.NotificationAreaHolder.AnchorPoint = Vector2.new(anchor_x, anchor_y);
	Library.NotificationAreaHolder.Position = UDim2.new((ns.X or 0), 0, (ns.Y or 0), 0);
	if Library.NotificationListLayout then
	    Library.NotificationListLayout.VerticalAlignment = (anchor_y == 0) and Enum.VerticalAlignment.Top or Enum.VerticalAlignment.Bottom;
	end

	local wrapper = Library:Create('Frame', {
		BackgroundTransparency = 1;
		BorderSizePixel = 0;
		Size = UDim2.new(1, 0, 0, YSize);
		ZIndex = NotifyOuter.ZIndex;
		Parent = Library.NotificationArea;
	});

	NotifyOuter.AnchorPoint = Vector2.new(anchor_x, 0);
	NotifyOuter.Position = UDim2.new(anchor_x, 0, 0, 0);
	NotifyOuter.Size = UDim2.new(0, 0, 0, YSize);
	NotifyOuter.Parent = wrapper;

	local targetSize = UDim2.new(0, XSize + 8 + 4, 0, YSize);
	TweenService:Create(NotifyOuter, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = targetSize }):Play();

	task.spawn(function()
	    wait(Time or 5);

	    TweenService:Create(NotifyOuter, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.new(0, 0, 0, YSize) }):Play();

	    wait(0.4);
	    wrapper:Destroy();
	end)
end;

function Library:CreateWindow(...)
	local Arguments = { ... }
	local Config = { AnchorPoint = Vector2.zero }

	if type(...) == 'table' then
		Config = ...;
	else
		Config.Title = Arguments[1]
		Config.AutoShow = Arguments[2] or false;
	end
	_UI_IS_VISIBLE = Config.AutoShow;
	if type(Config.Title) ~= 'string' then Config.Title = 'No title' end
	if type(Config.TabPadding) ~= 'number' then Config.TabPadding = 0 end
	if type(Config.MenuFadeTime) ~= 'number' then Config.MenuFadeTime = 0.2 end
	
	if typeof(Config.Position) ~= 'UDim2' then Config.Position = UDim2.fromOffset(175, 50) end
	if typeof(Config.Size) ~= 'UDim2' then Config.Size = UDim2.fromOffset(760, 640) end
	if typeof(Config.MinSize) ~= 'Vector2' then Config.MinSize = Vector2.new(460, 360) end

	if Config.Center then
		Config.AnchorPoint = Vector2.new(0.5, 0.5)
		Config.Position = UDim2.fromScale(0.5, 0.5)
	end

	-- Cosmetic config picked up before anything is built, so CustomCursor = false
	-- takes effect without the cursor ever flashing on.
	if type(Config.CustomCursorImage) == 'string' or type(Config.CustomCursorImage) == 'number' then
		Library:SetCustomCursorImage(Config.CustomCursorImage);
	end;

	if type(Config.CustomCursor) == 'boolean' then
		Library:SetCustomCursor(Config.CustomCursor);
	end;

	if type(Config.BackgroundBrightness) == 'number' then
		Library.BackgroundBrightness = math.clamp(Config.BackgroundBrightness, 0, 1);
	end;

	if typeof(Config.BackgroundDimColor) == 'Color3' then
		Library.BackgroundDimColor = Config.BackgroundDimColor;
	end;

	if type(Config.Snow) == 'boolean' then
		Library.SnowEnabled = Config.Snow;
	end;

	if type(Config.SnowCount) == 'number' then
		Library.SnowCount = math.clamp(math.floor(Config.SnowCount), 0, 400);
	end;

	if typeof(Config.SnowColor) == 'Color3' then
		Library.SnowColor = Config.SnowColor;
	end;


	Library.UISize = Config.Size;

	-- Width of the vertical tab strip. Config wins, otherwise the library default.
	local StripWidth = type(Config.TabStripWidth) == 'number' and Config.TabStripWidth or Library.TabStripWidth;

	local Window = {
		Tabs = {};
	};

	local Outer = Library:Create('Frame', {
		AnchorPoint = Config.AnchorPoint,
		BackgroundColor3 = Color3.new(0, 0, 0);
		BorderSizePixel = 0;
		Position = Config.Position,
		Size = Config.Size,
		Visible = false;
		ZIndex = 1;
		Parent = ScreenGui;
	});

	Library:MakeDraggableOutline(Outer, 25);

	local Inner = Library:Create('Frame', {
		BackgroundColor3 = Library.MainColor;
		BorderColor3 = Library.OutlineColor;
		BorderMode = Enum.BorderMode.Inset;
		Position = UDim2.new(0, 1, 0, 1);
		Size = UDim2.new(1, -2, 1, -2);
		ZIndex = 1;
		Parent = Outer;
	});

	Library:AddToRegistry(Inner, {
		BackgroundColor3 = 'MainColor';
		BorderColor3 = 'OutlineColor';
	});

	-- < Title bar >
	-- The logo no longer lives up here; it is parented into the sidebar under
	-- the search box further down. The bar is text only.
	local ImageHeight = math.max(tonumber(Config.ImageSize) or tonumber(Library.WindowImageSize) or 58, 0);

	local WindowImage = Library:Create('ImageLabel', {
		Name = 'WindowImage';
		BackgroundTransparency = 1;
		Image = Library:ResolveImage(Config.Image or Config.ImageId or Config.Logo);
		ScaleType = Enum.ScaleType.Fit;
		Position = UDim2.new(0, 8, 0, 35);
		Size = UDim2.new(0, StripWidth, 0, ImageHeight);
		Visible = false;
		ZIndex = 3;
		Parent = Inner;
	});

	local WindowLabel = Library:CreateLabel({
		Position = UDim2.new(0, 9, 0, 0);
		Size = UDim2.new(1, -18, 0, 25);
		Text = Config.Title or '';
		RichText = true;
		TextXAlignment = Enum.TextXAlignment.Left;
		ZIndex = 1;
		Parent = Inner;
	});

	Library.WindowTitle = Config.Title or '';
	Library.WindowColoredTitle = type(Config.ColoredTitle) == 'string' and Config.ColoredTitle or '';

	---Rebuild the heading. Whatever sits in ColoredTitle is appended in the
	---accent colour, so Title = 'Orange' + ColoredTitle = '.gg' reads Orange.gg
	---with the suffix tracking the accent picker.
	local function LayoutTitleBar()
		local Base = Library:EscapeRichText(Library.WindowTitle or '');
		local Suffix = Library.WindowColoredTitle or '';

		if Suffix ~= '' then
			WindowLabel.Text = Base .. Library:ColorRichText(Suffix, Library.AccentColor);
		else
			WindowLabel.Text = Base;
		end;
	end;

	Library.RefreshWindowTitle = LayoutTitleBar;

	LayoutTitleBar();

	--local VersionLabel = Library:CreateLabel({
	--	Position = UDim2.new(0, -8, 0, 0);
	--	Size = UDim2.new(1, 0, 0, 25);
	--	Text = Config.Version or '';
	--	TextColor3 = Config.VersionColor;
	--	RichText = true;
	--	TextXAlignment = Enum.TextXAlignment.Right;
	--	ZIndex = 1;
	--	Parent = Inner;
	--});

	local VersionLabel = Library:Create('TextLabel', {
		BackgroundTransparency = 1;
		Position = UDim2.new(0, -8, 0, 0);
		Size = UDim2.new(1, 0, 0, 25);
		Text = Config.Version or '';
		TextColor3 = Config.VersionColor or Library.FontColor;
		RichText = true;
		Font = Library.Font;
		TextSize = 14;
		TextXAlignment = Enum.TextXAlignment.Right;
		ZIndex = 1;
		Parent = Inner;
	});

	local MainSectionOuter = Library:Create('Frame', {
		BackgroundColor3 = Library.BackgroundColor;
		BorderColor3 = Library.OutlineColor;
		Position = UDim2.new(0, 8, 0, 25);
		Size = UDim2.new(1, -16, 1, -33);
		ZIndex = 1;
		Parent = Inner;
	});

	Library:AddToRegistry(MainSectionOuter, {
		BackgroundColor3 = 'BackgroundColor';
		BorderColor3 = 'OutlineColor';
	});

	local MainSectionInner = Library:Create('Frame', {
		BackgroundColor3 = Library.BackgroundColor;
		BorderColor3 = Color3.new(0, 0, 0);
		BorderMode = Enum.BorderMode.Inset;
		Position = UDim2.new(0, 0, 0, 0);
		Size = UDim2.new(1, 0, 1, 0);
		ZIndex = 1;
		Parent = MainSectionOuter;
	});

	Library:AddToRegistry(MainSectionInner, {
		BackgroundColor3 = 'BackgroundColor';
	});

	-- Search shares the sidebar width and sits above the tab list.
	local SearchWidth = 0;
	if Config.Search ~= false then
		SearchWidth = StripWidth;
	end;

	-- Vertical strip down the left of the window. Scrolls on Y so a long tab
	-- list can never run past the bottom edge. When a logo is set it takes the
	-- slot between the search box and the first tab.
	WindowImage.Parent = MainSectionInner;

	local TabTop = SearchWidth > 0 and 35 or 8;

	if WindowImage.Image ~= '' and ImageHeight > 0 then
		TabTop = TabTop + ImageHeight + 8;
	end;

	local TabArea = Library:Create('ScrollingFrame', {
		BackgroundTransparency = 1;
		BorderSizePixel = 0;
		Position = UDim2.new(0, 8, 0, TabTop);
		Size = UDim2.new(0, StripWidth, 1, -(TabTop + 8));
		CanvasSize = UDim2.new(0, 0, 0, 0);
		ScrollingDirection = Enum.ScrollingDirection.Y;
		ScrollBarThickness = 0;
		ScrollBarImageTransparency = 1;
		ElasticBehavior = Enum.ElasticBehavior.Never;
		ClipsDescendants = true;
		ZIndex = 1;
		Parent = MainSectionInner;
	});

	local TabListLayout = Library:Create('UIListLayout', {
		Padding = UDim.new(0, math.max(Config.TabPadding, 2));
		FillDirection = Enum.FillDirection.Vertical;
		SortOrder = Enum.SortOrder.LayoutOrder;
		Parent = TabArea;
	});

	-- Keep the scrollable height matched to the buttons actually present.
	TabListLayout:GetPropertyChangedSignal('AbsoluteContentSize'):Connect(function()
		TabArea.CanvasSize = UDim2.fromOffset(0, TabListLayout.AbsoluteContentSize.Y);
	end);

	-- Accent strip capping the tab list, matching the bar that sits on top of
	-- every groupbox. Re-seated by LayoutSidebar whenever the logo changes.
	local TabHighlight = Library:Create('Frame', {
		Name = 'TabHighlight';
		BackgroundColor3 = Library.AccentColor;
		BorderSizePixel = 0;
		Position = UDim2.new(0, 8, 0, TabTop - 4);
		Size = UDim2.new(0, StripWidth, 0, 2);
		ZIndex = 3;
		Parent = MainSectionInner;
	});

	Library:AddToRegistry(TabHighlight, {
		BackgroundColor3 = 'AccentColor';
	});

	---Re-place the logo and re-seat the tab list beneath it. Needed whenever the
	---image or its height changes after the window is already built.
	local function LayoutSidebar()
		local Shown = WindowImage.Image ~= '' and ImageHeight > 0;
		local Top = SearchWidth > 0 and 35 or 8;

		WindowImage.Visible = Shown;
		WindowImage.Position = UDim2.new(0, 8, 0, Top);
		WindowImage.Size = UDim2.new(0, StripWidth, 0, ImageHeight);

		if Shown then
			Top = Top + ImageHeight + 8;
		end;

		TabTop = Top;
		TabArea.Position = UDim2.new(0, 8, 0, Top);
		TabArea.Size = UDim2.new(0, StripWidth, 1, -(Top + 8));

		TabHighlight.Position = UDim2.new(0, 8, 0, Top - 4);
		TabHighlight.Size = UDim2.new(0, StripWidth, 0, 2);
	end;

	LayoutSidebar();

	-- Clipped so the tab intro animation slides in from underneath the edge.
	local TabContainer = Library:Create('Frame', {
		BackgroundColor3 = Library.MainColor;
		BorderColor3 = Library.OutlineColor;
		Position = UDim2.new(0, StripWidth + 16, 0, 8);
		Size = UDim2.new(1, -(StripWidth + 24), 1, -16);
		ClipsDescendants = true;
		ZIndex = 2;
		Parent = MainSectionInner;
	});


	Library:AddToRegistry(TabContainer, {
		BackgroundColor3 = 'MainColor';
		BorderColor3 = 'OutlineColor';
	});

	-- < Element search >
	-- Filters the index built by the Funcs wrapper and jumps to whatever is picked.
	if SearchWidth > 0 then
		local SearchOuter = Library:Create('Frame', {
			BackgroundColor3 = Color3.new(0, 0, 0);
			BorderColor3 = Color3.new(0, 0, 0);
			Position = UDim2.new(0, 8, 0, 8);
			Size = UDim2.new(0, SearchWidth, 0, 21);
			ZIndex = 1;
			Parent = MainSectionInner;
		});

		Library:AddToRegistry(SearchOuter, { BorderColor3 = 'Black'; });

		local SearchInner = Library:Create('Frame', {
			BackgroundColor3 = Library.MainColor;
			BorderColor3 = Library.OutlineColor;
			BorderMode = Enum.BorderMode.Inset;
			Size = UDim2.new(1, 0, 1, 0);
			ZIndex = 2;
			Parent = SearchOuter;
		});

		Library:AddToRegistry(SearchInner, {
			BackgroundColor3 = 'MainColor';
			BorderColor3 = 'OutlineColor';
		});

		Library:Create('UIGradient', {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(212, 212, 212))
			});
			Rotation = 90;
			Parent = SearchInner;
		});

		local SearchBox = Library:Create('TextBox', {
			BackgroundTransparency = 1;
			Position = UDim2.new(0, 5, 0, 0);
			Size = UDim2.new(1, -8, 1, 0);
			Font = Library.Font;
			PlaceholderColor3 = Color3.fromRGB(190, 190, 190);
			PlaceholderText = 'Search...';
			Text = '';
			TextColor3 = Library.FontColor;
			TextSize = 14;
			TextXAlignment = Enum.TextXAlignment.Left;
			ClearTextOnFocus = false;
			ZIndex = 3;
			Parent = SearchInner;
		});

		Library:ApplyTextStroke(SearchBox);
		Library:AddToRegistry(SearchBox, { TextColor3 = 'FontColor'; });

		Library:OnHighlight(SearchOuter, SearchOuter,
			{ BorderColor3 = 'AccentColor' },
			{ BorderColor3 = 'Black' }
		);

		-- Results sit directly in the ScreenGui so nothing clips or covers them.
		local ResultsWidth = math.max(SearchWidth, 210);
		local RowHeight = 18;

		local ResultsOuter = Library:Create('Frame', {
			Name = 'SearchResults';
			BackgroundColor3 = Color3.new(0, 0, 0);
			BorderColor3 = Color3.new(0, 0, 0);
			Size = UDim2.fromOffset(ResultsWidth, 20);
			Visible = false;
			ZIndex = 30;
			Parent = ScreenGui;
		});

		local ResultsInner = Library:Create('Frame', {
			BackgroundColor3 = Library.BackgroundColor;
			BorderColor3 = Library.OutlineColor;
			BorderMode = Enum.BorderMode.Inset;
			Size = UDim2.new(1, 0, 1, 0);
			ZIndex = 31;
			Parent = ResultsOuter;
		});

		Library:AddToRegistry(ResultsInner, {
			BackgroundColor3 = 'BackgroundColor';
			BorderColor3 = 'OutlineColor';
		});

		local ResultsList = Library:Create('ScrollingFrame', {
			BackgroundTransparency = 1;
			BorderSizePixel = 0;
			Position = UDim2.new(0, 2, 0, 2);
			Size = UDim2.new(1, -4, 1, -4);
			CanvasSize = UDim2.new(0, 0, 0, 0);
			ScrollBarThickness = 2;
			ZIndex = 31;
			Parent = ResultsInner;
		});

		local ResultsLayout = Library:Create('UIListLayout', {
			FillDirection = Enum.FillDirection.Vertical;
			SortOrder = Enum.SortOrder.LayoutOrder;
			Parent = ResultsList;
		});

		ResultsLayout:GetPropertyChangedSignal('AbsoluteContentSize'):Connect(function()
			ResultsList.CanvasSize = UDim2.fromOffset(0, ResultsLayout.AbsoluteContentSize.Y);
		end);

		local function UpdateResultsPosition()
			-- Left aligned now that search lives on the left edge of the window.
			ResultsOuter.Position = UDim2.fromOffset(
				SearchOuter.AbsolutePosition.X,
				SearchOuter.AbsolutePosition.Y + SearchOuter.AbsoluteSize.Y + 2
			);
		end;

		SearchOuter:GetPropertyChangedSignal('AbsolutePosition'):Connect(UpdateResultsPosition);
		UpdateResultsPosition();

		local Rows = {};
		local TopMatch = nil;

		local function ClearRows()
			for _, Row in next, Rows do
				Row:Destroy();
			end;

			table.clear(Rows);
		end;

		local function HideResults()
			ResultsOuter.Visible = false;
			Library.OpenedFrames[ResultsOuter] = nil;
		end;

		---Walk up from an element's container to work out where it lives.
		---@return table?, string?, table?
		local function ResolveLocation(Entry)
			local Node = Entry.Container;
			local TabInfo, Group, SubTab;

			while Node and Node ~= ScreenGui do
				if (not Group) and Library.GroupboxLookup[Node] then
					Group = Library.GroupboxLookup[Node];
				end;

				if (not SubTab) and Library.SubTabLookup[Node] then
					SubTab = Library.SubTabLookup[Node];
				end;

				if Library.TabLookup[Node] then
					TabInfo = Library.TabLookup[Node];
					break;
				end;

				Node = Node.Parent;
			end;

			return TabInfo, Group, SubTab;
		end;

		---Nearest scrolling ancestor, which is the side column the element sits in.
		local function FindScroller(Object)
			local Node = Object;

			while Node and Node ~= ScreenGui do
				if Node:IsA('ScrollingFrame') then
					return Node;
				end;

				Node = Node.Parent;
			end;
		end;

		---Briefly tint the rows an element occupies so it is easy to spot.
		local function Flash(Entry)
			local Anchor = Entry.Instances[1];
			if (not Anchor) or (not Anchor.Parent) then
				return;
			end;

			local Scroller = FindScroller(Anchor) or TabContainer;
			local Top, Bottom = math.huge, -math.huge;

			for _, Object in next, Entry.Instances do
				if Object.Parent and Object.Visible then
					Top = math.min(Top, Object.AbsolutePosition.Y);
					Bottom = math.max(Bottom, Object.AbsolutePosition.Y + Object.AbsoluteSize.Y);
				end;
			end;

			if Top == math.huge then
				return;
			end;

			-- Clamp to the tab body so the marker never spills out of the window.
			local ClipTop = TabContainer.AbsolutePosition.Y;
			local ClipBottom = ClipTop + TabContainer.AbsoluteSize.Y;

			Top = math.clamp(Top, ClipTop, ClipBottom);
			Bottom = math.clamp(Bottom, ClipTop, ClipBottom);

			if (Bottom - Top) < 2 then
				return;
			end;

			local Marker = Library:Create('Frame', {
				BackgroundColor3 = Library.AccentColor;
				BackgroundTransparency = 0.65;
				BorderSizePixel = 0;
				Position = UDim2.fromOffset(Scroller.AbsolutePosition.X, Top);
				Size = UDim2.fromOffset(Scroller.AbsoluteSize.X, Bottom - Top);
				ZIndex = 29;
				Parent = ScreenGui;
			});

			TweenService:Create(Marker, TweenInfo.new(0.9, Enum.EasingStyle.Quad), {
				BackgroundTransparency = 1;
			}):Play();

			task.delay(1, function()
				Marker:Destroy();
			end);
		end;

		---Reveal the tab / sub tab holding an element, scroll to it, then flash it.
		local function JumpTo(Entry)
			local TabInfo, _, SubTab = ResolveLocation(Entry);

			if TabInfo and TabInfo.Tab then
				TabInfo.Tab:ShowTab();
			end;

			if SubTab and SubTab.Show then
				SubTab:Show();
			end;

			HideResults();
			SearchBox.Text = '';

			-- Layout needs a frame to settle before positions mean anything.
			task.spawn(function()
				RenderStepped:Wait();

				local Anchor = Entry.Instances[1];
				if (not Anchor) or (not Anchor.Parent) then
					return;
				end;

				local Scroller = FindScroller(Anchor);

				if Scroller then
					local Offset = (Anchor.AbsolutePosition.Y - Scroller.AbsolutePosition.Y) + Scroller.CanvasPosition.Y;
					local Goal = math.max(0, Offset - (Scroller.AbsoluteWindowSize.Y * 0.35));

					TweenService:Create(Scroller, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
						CanvasPosition = Vector2.new(0, Goal);
					}):Play();

					task.wait(0.22);
				end;

				Flash(Entry);
			end);
		end;

		---One clickable line in the results list. Entry nil means a plain message.
		local function AddRow(Text, Entry)
			local Row = Library:Create('Frame', {
				BackgroundColor3 = Library.AccentColor;
				BackgroundTransparency = 1;
				BorderSizePixel = 0;
				Size = UDim2.new(1, 0, 0, RowHeight);
				ZIndex = 32;
				Parent = ResultsList;
			});

			local Label = Library:CreateLabel({
				BackgroundTransparency = 1;
				Position = UDim2.new(0, 4, 0, 0);
				Size = UDim2.new(1, -8, 1, 0);
				TextSize = 14;
				Text = Text;
				TextXAlignment = Enum.TextXAlignment.Left;
				TextTruncate = Enum.TextTruncate.AtEnd;
				ZIndex = 33;
				Parent = Row;
			});

			table.insert(Rows, Row);

			if not Entry then
				Library:RemoveFromRegistry(Label);
				Label.TextColor3 = Color3.fromRGB(150, 150, 150);
				return Row;
			end;

			Row.MouseEnter:Connect(function()
				Row.BackgroundTransparency = 0.75;
			end);

			Row.MouseLeave:Connect(function()
				Row.BackgroundTransparency = 1;
			end);

			Row.InputBegan:Connect(function(Input)
				if Input.UserInputType == Enum.UserInputType.MouseButton1 then
					JumpTo(Entry);
				end;
			end);

			return Row;
		end;

		---Rebuild the list from the current query.
		local function BuildRows()
			ClearRows();
			TopMatch = nil;

			local Query = string.lower(SearchBox.Text);

			if Query == '' then
				HideResults();
				return;
			end;

			local Matches = {};

			for _, Entry in next, Library.SearchIndex do
				local Anchor = Entry.Instances[1];

				-- Skip elements whose instances were destroyed by :Remove().
				if Anchor and Anchor.Parent then
					local At = string.find(string.lower(Entry.Name), Query, 1, true);

					if At then
						table.insert(Matches, { Entry = Entry; Rank = At; });
					end;
				end;
			end;

			-- Earlier match position first, then alphabetical.
			table.sort(Matches, function(A, B)
				if A.Rank == B.Rank then
					return A.Entry.Name < B.Entry.Name;
				end;

				return A.Rank < B.Rank;
			end);

			if #Matches == 0 then
				AddRow('No results', nil);
			else
				TopMatch = Matches[1].Entry;
			end;

			for i = 1, math.min(#Matches, 50) do
				local Entry = Matches[i].Entry;
				local TabInfo, Group = ResolveLocation(Entry);
				local Suffix = '';

				if TabInfo then
					Suffix = '  -  ' .. TabInfo.Name .. (Group and (' > ' .. Group) or '');
				end;

				AddRow(Entry.Name .. Suffix, Entry);
			end;

			local Shown = math.clamp(#Rows, 1, 9);

			ResultsOuter.Size = UDim2.fromOffset(ResultsWidth, (Shown * RowHeight) + 4);
			ResultsList.CanvasPosition = Vector2.new(0, 0);
			ResultsOuter.Visible = true;
			Library.OpenedFrames[ResultsOuter] = true;

			UpdateResultsPosition();
		end;

		SearchBox:GetPropertyChangedSignal('Text'):Connect(BuildRows);

		-- Enter takes the top hit.
		SearchBox.FocusLost:Connect(function(Enter)
			if Enter and TopMatch then
				JumpTo(TopMatch);
			end;
		end);

		-- Clicking anywhere that is not the box or the list closes the list.
		Library:BindToInput(Enum.UserInputType.MouseButton1, function()
			if not ResultsOuter.Visible then
				return;
			end;

			if Library:IsMouseOverFrame(ResultsOuter) or Library:IsMouseOverFrame(SearchOuter) then
				return;
			end;

			HideResults();
		end);

		Outer:GetPropertyChangedSignal('Visible'):Connect(function()
			if not Outer.Visible then
				HideResults();
			end;
		end);

		Window.SearchBox = SearchBox;

		---Run a search from code.
		---@param Query string
		function Window:Search(Query)
			SearchBox.Text = tostring(Query or '');
		end;
	end;

	---@param Title string
	---@param ColoredTitle string? suffix drawn in the accent colour
	function Window:SetWindowTitle(Title, ColoredTitle)
		Library.WindowTitle = tostring(Title or '');

		if ColoredTitle ~= nil then
			Library.WindowColoredTitle = tostring(ColoredTitle);
		end;

		LayoutTitleBar();
	end;

	---Set only the accent-coloured suffix, leaving the base title alone.
	---@param Text string
	function Window:SetColoredTitle(Text)
		Library.WindowColoredTitle = tostring(Text or '');
		LayoutTitleBar();
	end;

	---Set the logo shown in the sidebar under the search box. Accepts a bare
	---asset id or a content string; pass nil to drop it and reclaim the space.
	---@param Image string | number | nil
	function Window:SetWindowImage(Image)
		WindowImage.Image = Library:ResolveImage(Image);
		LayoutSidebar();
	end;

	---@param Size number logo height in pixels
	function Window:SetWindowImageSize(Size)
		ImageHeight = math.max(tonumber(Size) or 0, 0);
		LayoutSidebar();
	end;

	-- < Resize >
	local MinSize = Config.MinSize;

	local ResizeGrip = Library:Create('TextButton', {
		Name = 'ResizeGrip';
		BackgroundTransparency = 1;
		AutoButtonColor = false;
		Text = '';
		AnchorPoint = Vector2.new(1, 1);
		Position = UDim2.new(1, -1, 1, -1);
		Size = UDim2.fromOffset(15, 15);
		ZIndex = 50;
		Parent = Inner;
	});

	-- Three diagonal ticks so the corner reads as draggable.
	for Index = 1, 3 do
		local Inset = 2 + ((Index - 1) * 4);
		local Length = 13 - ((Index - 1) * 4);

		Library:AddToRegistry(Library:Create('Frame', {
			BackgroundColor3 = Library.OutlineColor;
			BorderSizePixel = 0;
			AnchorPoint = Vector2.new(0.5, 0.5);
			Position = UDim2.fromOffset(15 - Inset, 15 - Inset);
			Size = UDim2.fromOffset(Length, 1);
			Rotation = -45;
			ZIndex = 51;
			Parent = ResizeGrip;
		}), { BackgroundColor3 = 'OutlineColor' });
	end;

	local Resizing = false;
	local StartMouse, StartSize, StartPos;

	ResizeGrip.InputBegan:Connect(function(Input)
		if Input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return;
		end;

		Resizing = true;
		StartMouse = Vector2.new(Mouse.X, Mouse.Y);
		StartSize = Outer.AbsoluteSize;
		StartPos = Outer.Position;
	end);

	Library:GiveSignal(InputService.InputEnded:Connect(function(Input)
		if Input.UserInputType == Enum.UserInputType.MouseButton1 then
			Resizing = false;
		end;
	end));

	Library:GiveSignal(RenderStepped:Connect(function()
		if not Resizing then
			return;
		end;

		local Delta = Vector2.new(Mouse.X, Mouse.Y) - StartMouse;
		local Width = math.max(MinSize.X, StartSize.X + Delta.X);
		local Height = math.max(MinSize.Y, StartSize.Y + Delta.Y);

		-- Config.Center anchors the window at its middle, so growing it would
		-- pull the corner away from the cursor. Offset the position by the
		-- growth times the anchor to keep the top-left edge pinned instead.
		local Anchor = Outer.AnchorPoint;

		Outer.Size = UDim2.fromOffset(Width, Height);
		Outer.Position = UDim2.new(
			StartPos.X.Scale, StartPos.X.Offset + ((Width - StartSize.X) * Anchor.X),
			StartPos.Y.Scale, StartPos.Y.Offset + ((Height - StartSize.Y) * Anchor.Y)
		);

		Library.UISize = Outer.Size;
	end));

	---Resize the window from code.
	---@param Size UDim2 | Vector2
	function Window:SetSize(Size)
		local Width = typeof(Size) == 'UDim2' and Size.X.Offset or Size.X;
		local Height = typeof(Size) == 'UDim2' and Size.Y.Offset or Size.Y;

		Outer.Size = UDim2.fromOffset(math.max(MinSize.X, Width), math.max(MinSize.Y, Height));
		Library.UISize = Outer.Size;
	end;

	---@return Vector2
	function Window:GetWindowSize()
		return Outer.AbsoluteSize;
	end;

	function Window:AddTab(Name)
		local Tab = {
			Groupboxes = {};
			Tabboxes = {};
		};

		-- Full width row in the vertical strip instead of a text sized pill.
		local TabButton = Library:Create('Frame', {
			BackgroundColor3 = Library.BackgroundColor;
			BorderColor3 = Library.OutlineColor;
			Size = UDim2.new(1, 0, 0, 24);
			ZIndex = 1;
			Parent = TabArea;
		});

		Library:AddToRegistry(TabButton, {
			BackgroundColor3 = 'BackgroundColor';
			BorderColor3 = 'OutlineColor';
		});

		local TabButtonLabel = Library:CreateLabel({
			Position = UDim2.new(0, 10, 0, 0);
			Size = UDim2.new(1, -14, 1, 0);
			Text = Name;
			TextXAlignment = Enum.TextXAlignment.Left;
			ZIndex = 1;
			Parent = TabButton;
		});

		-- The "| main" bar on the left edge that marks the selected tab. Grown
		-- from zero height on select so the marker slides open.
		local Indicator = Library:Create('Frame', {
			Name = 'Indicator';
			BackgroundColor3 = Library.AccentColor;
			BorderSizePixel = 0;
			AnchorPoint = Vector2.new(0, 0.5);
			Position = UDim2.new(0, 1, 0.5, 0);
			Size = UDim2.new(0, 2, 0, 0);
			ZIndex = 3;
			Parent = TabButton;
		});

		Library:AddToRegistry(Indicator, {
			BackgroundColor3 = 'AccentColor';
		});

		local TabFrame = Library:Create('Frame', {
			Name = 'TabFrame',
			BackgroundTransparency = 1;
			Position = UDim2.new(0, 0, 0, 0);
			Size = UDim2.new(1, 0, 1, 0);
			Visible = false;
			ZIndex = 2;
			Parent = TabContainer;
		});

		-- Everything in the tab lives under one holder so the switch animation
		-- is a single GroupTransparency + Position tween instead of a walk over
		-- every descendant. CanvasGroup is not on every client, so fall back to
		-- a plain Frame and slide without the fade.
		local Ok, Holder = pcall(function()
			return Library:Create('CanvasGroup', {
				Name = 'AnimHolder';
				BackgroundTransparency = 1;
				BorderSizePixel = 0;
				Size = UDim2.new(1, 0, 1, 0);
				ZIndex = 2;
				Parent = TabFrame;
			});
		end);

		local CanFade = Ok and Holder ~= nil;

		local AnimHolder = CanFade and Holder or Library:Create('Frame', {
			Name = 'AnimHolder';
			BackgroundTransparency = 1;
			BorderSizePixel = 0;
			Size = UDim2.new(1, 0, 1, 0);
			ZIndex = 2;
			Parent = TabFrame;
		});

		local LeftSide = Library:Create('ScrollingFrame', {
			BackgroundTransparency = 1;
			BorderSizePixel = 0;
			Position = UDim2.new(0, 8 - 1, 0, 8 - 1);
			Size = UDim2.new(0.5, -12 + 2, 1, -14);
			CanvasSize = UDim2.new(0, 0, 0, 0);
			BottomImage = '';
			TopImage = '';
			ScrollBarThickness = 0;
			ZIndex = 2;
			Parent = AnimHolder;
		});

		local RightSide = Library:Create('ScrollingFrame', {
			BackgroundTransparency = 1;
			BorderSizePixel = 0;
			Position = UDim2.new(0.5, 4 + 1, 0, 8 - 1);
			Size = UDim2.new(0.5, -12 + 2, 1, -14);
			CanvasSize = UDim2.new(0, 0, 0, 0);
			BottomImage = '';
			TopImage = '';
			ScrollBarThickness = 0;
			ZIndex = 2;
			Parent = AnimHolder;
		});

		Library:Create('UIListLayout', {
			Padding = UDim.new(0, 8);
			FillDirection = Enum.FillDirection.Vertical;
			SortOrder = Enum.SortOrder.LayoutOrder;
			HorizontalAlignment = Enum.HorizontalAlignment.Center;
			Parent = LeftSide;
		});

		Library:Create('UIListLayout', {
			Padding = UDim.new(0, 8);
			FillDirection = Enum.FillDirection.Vertical;
			SortOrder = Enum.SortOrder.LayoutOrder;
			HorizontalAlignment = Enum.HorizontalAlignment.Center;
			Parent = RightSide;
		});

		for _, Side in next, { LeftSide, RightSide } do
			Side:WaitForChild('UIListLayout'):GetPropertyChangedSignal('AbsoluteContentSize'):Connect(function()
				Side.CanvasSize = UDim2.fromOffset(0, Side.UIListLayout.AbsoluteContentSize.Y);
			end);
		end;

		local IntroTween = nil;
		local IndicatorTween = nil;

		---Fade + slide the tab body in when this tab becomes the active one.
		local function PlayIntro()
			if IntroTween then
				IntroTween:Cancel();
				IntroTween = nil;
			end;

			local Time = tonumber(Library.TabAnimationTime) or 0;

			if Time <= 0 then
				AnimHolder.Position = UDim2.new(0, 0, 0, 0);

				if CanFade then
					AnimHolder.GroupTransparency = 0;
				end;

				return;
			end;

			AnimHolder.Position = UDim2.new(0, 0, 0, tonumber(Library.TabAnimationOffset) or 0);

			local Goal = { Position = UDim2.new(0, 0, 0, 0) };

			if CanFade then
				AnimHolder.GroupTransparency = 1;
				Goal.GroupTransparency = 0;
			end;

			IntroTween = TweenService:Create(AnimHolder, TweenInfo.new(Time, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), Goal);
			IntroTween:Play();
		end;

		function Tab:ShowTab()
			for _, Tab in next, Window.Tabs do
				Tab:HideTab();
			end;

			-- Pull the button into view if the strip is scrolled away from it.
			local ButtonY = (TabButton.AbsolutePosition.Y - TabArea.AbsolutePosition.Y) + TabArea.CanvasPosition.Y;
			local ViewHeight = TabArea.AbsoluteWindowSize.Y;

			if ButtonY < TabArea.CanvasPosition.Y then
				TabArea.CanvasPosition = Vector2.new(0, math.max(0, ButtonY));
			elseif (ButtonY + TabButton.AbsoluteSize.Y) > (TabArea.CanvasPosition.Y + ViewHeight) then
				TabArea.CanvasPosition = Vector2.new(0, math.max(0, ButtonY + TabButton.AbsoluteSize.Y - ViewHeight));
			end;

			TabButton.BackgroundColor3 = Library.MainColor;
			Library.RegistryMap[TabButton].Properties.BackgroundColor3 = 'MainColor';

			if IndicatorTween then
				IndicatorTween:Cancel();
				IndicatorTween = nil;
			end;

			local Time = tonumber(Library.TabAnimationTime) or 0;
			local Grown = UDim2.new(0, 2, 1, -8);

			if Time <= 0 then
				Indicator.Size = Grown;
			else
				IndicatorTween = TweenService:Create(Indicator, TweenInfo.new(Time, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
					Size = Grown;
				});

				IndicatorTween:Play();
			end;

			TabFrame.Visible = true;
			PlayIntro();
		end;

		function Tab:HideTab()
			if IndicatorTween then
				IndicatorTween:Cancel();
				IndicatorTween = nil;
			end;

			TabButton.BackgroundColor3 = Library.BackgroundColor;
			Library.RegistryMap[TabButton].Properties.BackgroundColor3 = 'BackgroundColor';
			Indicator.Size = UDim2.new(0, 2, 0, 0);
			TabFrame.Visible = false;
		end;

		function Tab:SetLayoutOrder(Position)
			TabButton.LayoutOrder = Position;
			TabListLayout:ApplyLayout();
		end;

		function Tab:AddGroupbox(Info)
			local Groupbox = {};

			local BoxOuter = Library:Create('Frame', {
				BackgroundColor3 = Library.BackgroundColor;
				BorderColor3 = Library.OutlineColor;
				BorderMode = Enum.BorderMode.Inset;
				Size = UDim2.new(1, 0, 0, 507 + 2);
				ZIndex = 2;
				Parent = Info.Side == 1 and LeftSide or RightSide;
			});

			Library:AddToRegistry(BoxOuter, {
				BackgroundColor3 = 'BackgroundColor';
				BorderColor3 = 'OutlineColor';
			});

			local BoxInner = Library:Create('Frame', {
				BackgroundColor3 = Library.BackgroundColor;
				BorderColor3 = Color3.new(0, 0, 0);
				-- BorderMode = Enum.BorderMode.Inset;
				Size = UDim2.new(1, -2, 1, -2);
				Position = UDim2.new(0, 1, 0, 1);
				ZIndex = 4;
				Parent = BoxOuter;
			});

			Library:AddToRegistry(BoxInner, {
				BackgroundColor3 = 'BackgroundColor';
			});

			local Highlight = Library:Create('Frame', {
				BackgroundColor3 = Library.AccentColor;
				BorderSizePixel = 0;
				Size = UDim2.new(1, 0, 0, 2);
				ZIndex = 5;
				Parent = BoxInner;
			});

			Library:AddToRegistry(Highlight, {
				BackgroundColor3 = 'AccentColor';
			});

			local GroupboxLabel = Library:CreateLabel({
				Size = UDim2.new(1, 0, 0, 18);
				Position = UDim2.new(0, 4, 0, 2);
				TextSize = 14;
				Text = Info.Name;
				TextXAlignment = Enum.TextXAlignment.Center;
				ZIndex = 5;
				Parent = BoxInner;
			});

			local Container = Library:Create('Frame', {
				BackgroundTransparency = 1;
				Position = UDim2.new(0, 4, 0, 20);
				Size = UDim2.new(1, -4, 1, -20);
				ZIndex = 1;
				Parent = BoxInner;
			});

			Library:Create('UIListLayout', {
				FillDirection = Enum.FillDirection.Vertical;
				SortOrder = Enum.SortOrder.LayoutOrder;
				Parent = Container;
			});

			function Groupbox:Resize()
				local Size = 0;

				for _, Element in next, Groupbox.Container:GetChildren() do
					if (not Element:IsA('UIListLayout')) and Element.Visible then
						Size = Size + Element.Size.Y.Offset;
					end;
				end;

				BoxOuter.Size = UDim2.new(1, 0, 0, 20 + Size + 2 + 2);
			end;

			local Groupboxes = Tab.Groupboxes;
			function Groupbox:Remove()
				table.clear(self);
				BoxOuter:Destroy();
				Groupboxes[Info.Name] = nil;
			end;

			Groupbox.Container = Container;
			Library.GroupboxLookup[Container] = Info.Name;
			setmetatable(Groupbox, BaseGroupbox);

			Groupbox:AddBlank(3);
			Groupbox:Resize();

			Groupboxes[Info.Name] = Groupbox;

			return Groupbox;
		end;

		function Tab:AddLeftGroupbox(Name)
			return self:AddGroupbox({ Side = 1; Name = Name; });
		end;

		function Tab:AddRightGroupbox(Name)
			return self:AddGroupbox({ Side = 2; Name = Name; });
		end;

		function Tab:AddTabbox(Info)
			local Tabbox = {
				Tabs = {};
			};

			local BoxOuter = Library:Create('Frame', {
				BackgroundColor3 = Library.BackgroundColor;
				BorderColor3 = Library.OutlineColor;
				BorderMode = Enum.BorderMode.Inset;
				Size = UDim2.new(1, 0, 0, 0);
				ZIndex = 2;
				Parent = Info.Side == 1 and LeftSide or RightSide;
			});

			Library:AddToRegistry(BoxOuter, {
				BackgroundColor3 = 'BackgroundColor';
				BorderColor3 = 'OutlineColor';
			});

			local BoxInner = Library:Create('Frame', {
				BackgroundColor3 = Library.BackgroundColor;
				BorderColor3 = Color3.new(0, 0, 0);
				-- BorderMode = Enum.BorderMode.Inset;
				Size = UDim2.new(1, -2, 1, -2);
				Position = UDim2.new(0, 1, 0, 1);
				ZIndex = 4;
				Parent = BoxOuter;
			});

			Library:AddToRegistry(BoxInner, {
				BackgroundColor3 = 'BackgroundColor';
			});

			local Highlight = Library:Create('Frame', {
				BackgroundColor3 = Library.AccentColor;
				BorderSizePixel = 0;
				Size = UDim2.new(1, 0, 0, 2);
				ZIndex = 10;
				Parent = BoxInner;
			});

			Library:AddToRegistry(Highlight, {
				BackgroundColor3 = 'AccentColor';
			});

			local TabboxButtons = Library:Create('Frame', {
				BackgroundTransparency = 1;
				Position = UDim2.new(0, 0, 0, 1);
				Size = UDim2.new(1, 0, 0, 18);
				ZIndex = 5;
				Parent = BoxInner;
			});

			Library:Create('UIListLayout', {
				FillDirection = Enum.FillDirection.Horizontal;
				HorizontalAlignment = Enum.HorizontalAlignment.Left;
				SortOrder = Enum.SortOrder.LayoutOrder;
				Parent = TabboxButtons;
			});

			local Tabboxes = Tab.Tabboxes;
			function Tabbox:Remove()
				BoxOuter:Destroy();
				table.clear(Tabbox);
				Tabboxes[Info.Name or ''] = nil;
			end;

			function Tabbox:AddTab(Name)
				local Tab = {};

				local Button = Library:Create('Frame', {
					BackgroundColor3 = Library.MainColor;
					BorderColor3 = Color3.new(0, 0, 0);
					Size = UDim2.new(0.5, 0, 1, 0);
					ZIndex = 6;
					Parent = TabboxButtons;
				});

				Library:AddToRegistry(Button, {
					BackgroundColor3 = 'MainColor';
				});

				local ButtonLabel = Library:CreateLabel({
					Size = UDim2.new(1, 0, 1, 0);
					TextSize = 14;
					Text = Name;
					TextXAlignment = Enum.TextXAlignment.Center;
					ZIndex = 7;
					Parent = Button;
				});

				local Block = Library:Create('Frame', {
					BackgroundColor3 = Library.BackgroundColor;
					BorderSizePixel = 0;
					Position = UDim2.new(0, 0, 1, 0);
					Size = UDim2.new(1, 0, 0, 1);
					Visible = false;
					ZIndex = 9;
					Parent = Button;
				});

				Library:AddToRegistry(Block, {
					BackgroundColor3 = 'BackgroundColor';
				});

				local Container = Library:Create('Frame', {
					BackgroundTransparency = 1;
					Position = UDim2.new(0, 4, 0, 20);
					Size = UDim2.new(1, -4, 1, -20);
					ZIndex = 1;
					Visible = false;
					Parent = BoxInner;
				});

				Library:Create('UIListLayout', {
					FillDirection = Enum.FillDirection.Vertical;
					SortOrder = Enum.SortOrder.LayoutOrder;
					Parent = Container;
				});

				function Tab:Show()
					for _, Tab in next, Tabbox.Tabs do
						Tab:Hide();
					end;

					Container.Visible = true;
					Block.Visible = true;

					Button.BackgroundColor3 = Library.BackgroundColor;
					Library.RegistryMap[Button].Properties.BackgroundColor3 = 'BackgroundColor';

					Tab:Resize();
				end;

				function Tab:Hide()
					Container.Visible = false;
					Block.Visible = false;

					Button.BackgroundColor3 = Library.MainColor;
					Library.RegistryMap[Button].Properties.BackgroundColor3 = 'MainColor';
				end;

				function Tab:Resize()
					local TabCount = 0;

					for _, Tab in next, Tabbox.Tabs do
						TabCount = TabCount + 1;
					end;

					for _, Button in next, TabboxButtons:GetChildren() do
						if not Button:IsA('UIListLayout') then
							Button.Size = UDim2.new(1 / TabCount, 0, 1, 0);
						end;
					end;

					if (not Container.Visible) then
						return;
					end;

					local Size = 0;

					for _, Element in next, Tab.Container:GetChildren() do
						if (not Element:IsA('UIListLayout')) and Element.Visible then
							Size = Size + Element.Size.Y.Offset;
						end;
					end;

					BoxOuter.Size = UDim2.new(1, 0, 0, 20 + Size + 2 + 2);
				end;

				Button.InputBegan:Connect(function(Input)
					if Input.UserInputType == Enum.UserInputType.MouseButton1 and not Library:MouseIsOverOpenedFrame() then
						Tab:Show();
						Tab:Resize();
					end;
				end);

				Tab.Container = Container;

				-- Sub tabs hide their container, so search needs to know how to reveal it.
				Library.GroupboxLookup[Container] = (Info.Name and (Info.Name .. ' / ') or '') .. Name;
				Library.SubTabLookup[Container] = Tab;

				Tabbox.Tabs[Name] = Tab;

				setmetatable(Tab, BaseGroupbox);

				Tab:AddBlank(3);
				Tab:Resize();

				-- Show first tab (number is 2 cus of the UIListLayout that also sits in that instance)
				if #TabboxButtons:GetChildren() == 2 then
					Tab:Show();
				end;

				return Tab;
			end;

			Tabboxes[Info.Name or ''] = Tabbox;

			return Tabbox;
		end;

		function Tab:AddLeftTabbox(Name)
			return self:AddTabbox({ Name = Name, Side = 1; });
		end;

		function Tab:AddRightTabbox(Name)
			return self:AddTabbox({ Name = Name, Side = 2; });
		end;

		function Tab:Remove()
			table.clear(Tab);
			TabFrame:Destroy();
			TabButton:Destroy();
			Window.Tabs[Name] = nil;
		end;

		TabButton.InputBegan:Connect(function(Input)
			if Input.UserInputType == Enum.UserInputType.MouseButton1 then
				Tab:ShowTab();
			end;
		end);

		-- Let the search box find its way into this tab.
		Library.TabLookup[TabFrame] = {
			Name = Name;
			Tab = Tab;
			Left = LeftSide;
			Right = RightSide;
		};

		-- This was the first tab added, so we show it by default.
		if #TabContainer:GetChildren() == 1 then
			Tab:ShowTab();
		end;

		Window.Tabs[Name] = Tab;
		return Tab;
	end;

	local ModalElement = Library:Create('TextButton', {
		BackgroundTransparency = 1;
		Size = UDim2.new(0, 0, 0, 0);
		Visible = true;
		Text = '';
		Modal = false;
		Parent = Library:Create("ScreenGui", {
			Parent = game:GetService("CoreGui");
		});
	});

	local TransparencyCache = {};
	local Toggled = false;
	local Fading = false;


	function Library:Toggle()
		if Fading then
			return;
		end;

		local FadeTime = Config.MenuFadeTime;
		Fading = true;
		Toggled = (not Toggled);
		_UI_IS_VISIBLE = Toggled;

		ModalElement.Modal = Toggled;

		-- Dim and snow follow the menu. Handled here rather than in the
		-- descendant fade below because both overlays live outside Outer.
		Library.MenuFadeTime = FadeTime;
		Library:UpdateBackgroundDim();
		Library:UpdateSnow();

		-- Anything hanging off the menu (popout panels, mostly) follows it.
		for _, Func in next, Library.MenuToggledCallbacks do
			pcall(Func, Toggled);
		end;

		if Toggled then
			-- A bit scuffed, but if we're going from not toggled -> toggled we want to show the frame immediately so that the fade is visible.
			Outer.Visible = true;
		end;

		if (not Config.DontFade) then
			Outer.Parent = ScreenGui;

			for _, Desc in next, Outer:GetDescendants() do
				local Properties = {};

				if Desc:IsA('ImageLabel') then
					table.insert(Properties, 'ImageTransparency');
					table.insert(Properties, 'BackgroundTransparency');
				elseif Desc:IsA('TextLabel') or Desc:IsA('TextBox') then
					table.insert(Properties, 'TextTransparency');
				elseif Desc:IsA('Frame') or Desc:IsA('ScrollingFrame') then
					table.insert(Properties, 'BackgroundTransparency');
				elseif Desc:IsA('UIStroke') then
					table.insert(Properties, 'Transparency');
				end;

				local Cache = TransparencyCache[Desc];

				if (not Cache) then
					Cache = {};
					TransparencyCache[Desc] = Cache;
				end;

				for _, Prop in next, Properties do
					if not Cache[Prop] then
						Cache[Prop] = Desc[Prop];
					end;

					if Cache[Prop] == 1 then
						continue;
					end;

					TweenService:Create(Desc, TweenInfo.new(FadeTime, Enum.EasingStyle.Linear), { [Prop] = Toggled and Cache[Prop] or 1 }):Play();
				end;
			end;
			task.wait(FadeTime);
		end;

		Outer.Visible = Toggled;

		Outer.Parent = Toggled and ScreenGui or nil;

		Fading = false;
	end

	Library:GiveSignal(InputService.InputBegan:Connect(function(Input, Processed)
		if type(Library.ToggleKeybind) == 'table' and Library.ToggleKeybind.Type == 'KeyPicker' then
			if Input.UserInputType == Enum.UserInputType.Keyboard and Input.KeyCode.Name == Library.ToggleKeybind.Value then
				task.spawn(Library.Toggle)
			end
		elseif Input.KeyCode == Enum.KeyCode.RightControl or (Input.KeyCode == Enum.KeyCode.RightShift and (not Processed)) then
			task.spawn(Library.Toggle)
		end
	end))

	if Config.AutoShow then task.spawn(Library.Toggle) end

	Window.Holder = Outer;

	return Window;
end;

-- < Declarative UI API >
-- Describe a whole menu as one table instead of chaining calls by hand. Every
-- path here runs through CreateWindow / AddTab / AddGroupbox, so what it builds
-- still lands in Toggles and Options and still saves through SaveManager. The
-- normal Library API is untouched, this only sits on top of it.
do
	local UIApi = {};
	UIApi.__index = UIApi;

	local Builders = {};

	---Which half of the tab a groupbox belongs on.
	---@param Side any 1, 2, 'Left' or 'Right'
	---@return number
	local function resolveSide(Side)
		if Side == 2 or Side == 'Right' or Side == 'right' then
			return 2;
		end;

		return 1;
	end;

	---Flag the element registers itself under. Idx and Flag are aliases so a
	---config reads the same whichever name the caller is used to.
	---@param Element table
	---@param Fallback string?
	---@return string?
	local function resolveIdx(Element, Fallback)
		return Element.Idx or Element.Flag or Element.Name or Fallback;
	end;

	---Hang any colorpicker / keypicker declared inline on a toggle or label.
	---@param Object table the toggle or label the addon attaches to
	---@param Element table the element description it came from
	---@param UI table
	local function applyAddons(Object, Element, UI)
		if type(Object) ~= 'table' then
			return;
		end;

		local Addons = { ColorPicker = 'AddColorPicker'; KeyPicker = 'AddKeyPicker'; };

		for Key, FuncName in next, Addons do
			local Info = Element[Key];

			if type(Info) == 'table' then
				-- Dot form on purpose, so the call resolves through __index
				-- rather than the metatable's namecall path.
				local Builder = Object[FuncName];

				if Builder then
					local Idx = Info.Idx or Info.Flag or ((resolveIdx(Element, Element.Text) or '') .. Key);
					UI.Elements[Idx] = Builder(Object, Idx, Info);
				end;
			end;
		end;
	end;

	Builders.Toggle = function(Groupbox, Element, UI)
		local Idx = resolveIdx(Element, Element.Text);

		-- A toggle can own a popout panel. Flipping it shows the panel, and the
		-- caller's own callback still runs exactly as it would have.
		local Panel = nil;

		if type(Element.Panel) == 'table' then
			Panel = Library:CreatePanel(Element.Panel);
			UI.Panels[Idx] = Panel;
		end;

		local Toggle = Groupbox:AddToggle(Idx, {
			Text = Element.Text or Element.Name or '';
			Default = Element.Default or false;
			Tooltip = Element.Tooltip;
			Risky = Element.Risky;

			Callback = function(Value)
				if Panel then
					Panel:SetVisible(Value);
				end;

				if Element.Callback then
					Element.Callback(Value);
				end;
			end;
		});

		if Panel then
			Toggle.Panel = Panel;

			-- The panel's own close cross flips the toggle back off, so the two
			-- can never drift out of sync.
			Panel.OnClose = function()
				Toggle:SetValue(false);
			end;

			Panel:SetVisible(Toggle.Value);
		end;

		applyAddons(Toggle, Element, UI);

		return Idx, Toggle;
	end;

	Builders.Slider = function(Groupbox, Element)
		local Idx = resolveIdx(Element, Element.Text);

		return Idx, Groupbox:AddSlider(Idx, {
			Text = Element.Text or Element.Name or '';
			Default = Element.Default or Element.Min or 0;
			Min = Element.Min or 0;
			Max = Element.Max or 100;
			Rounding = Element.Rounding or 0;
			Suffix = Element.Suffix;
			Compact = Element.Compact;
			HideMax = Element.HideMax;
			Increment = Element.Increment;
			Tooltip = Element.Tooltip;
			Callback = Element.Callback;
		});
	end;

	Builders.Dropdown = function(Groupbox, Element)
		local Idx = resolveIdx(Element, Element.Text);

		return Idx, Groupbox:AddDropdown(Idx, {
			Text = Element.Text or Element.Name or '';
			Values = Element.Values or {};
			Default = Element.Default;
			Multi = Element.Multi;
			AllowNull = Element.AllowNull;
			SpecialType = Element.SpecialType;
			Tooltip = Element.Tooltip;
			Callback = Element.Callback;
		});
	end;

	Builders.Input = function(Groupbox, Element)
		local Idx = resolveIdx(Element, Element.Text);

		return Idx, Groupbox:AddInput(Idx, {
			Text = Element.Text or Element.Name or '';
			Default = Element.Default;
			Numeric = Element.Numeric;
			Finished = Element.Finished;
			Placeholder = Element.Placeholder;
			Tooltip = Element.Tooltip;
			Callback = Element.Callback;
		});
	end;

	Builders.Button = function(Groupbox, Element)
		return nil, Groupbox:AddButton({
			Text = Element.Text or Element.Name or '';
			Func = Element.Callback or Element.Func or function() end;
			DoubleClick = Element.DoubleClick;
			Tooltip = Element.Tooltip;
		});
	end;

	Builders.Label = function(Groupbox, Element, UI)
		local Label = Groupbox:AddLabel(Element.Text or Element.Name or '', Element.Wrap);

		-- Colour shorthands, so a config can tint a label without reaching for
		-- the chained call.
		if type(Element.RGB) == 'table' and Label.FromRGB then
			Label:FromRGB(Element.RGB[1], Element.RGB[2], Element.RGB[3]);
		elseif Element.Hex and Label.FromHex then
			Label:FromHex(Element.Hex);
		elseif Element.Color and Label.SetColor then
			Label:SetColor(Element.Color);
		end;

		applyAddons(Label, Element, UI);

		return resolveIdx(Element, nil), Label;
	end;

	Builders.Divider = function(Groupbox)
		return nil, Groupbox:AddDivider();
	end;

	Builders.Blank = function(Groupbox, Element)
		return nil, Groupbox:AddBlank(Element.Size or 5);
	end;

	---Fill one groupbox from its element list.
	---@param Groupbox table
	---@param Elements table?
	---@param UI table
	local function buildElements(Groupbox, Elements, UI)
		for _, Element in ipairs(Elements or {}) do
			local Kind = Element.Type or 'Label';
			local Builder = Builders[Kind];

			if not Builder then
				warn('[Library:CreateUI] unknown element type: ' .. tostring(Kind));
				continue;
			end;

			local Idx, Object = Builder(Groupbox, Element, UI);

			if Idx and Object then
				UI.Elements[Idx] = Object;
			end;
		end;
	end;

	---Build every groupbox and tabbox declared on a tab.
	---@param Tab table
	---@param Config table
	---@param UI table
	local function buildTab(Tab, Config, UI)
		for _, Box in ipairs(Config.Groupboxes or {}) do
			local Name = Box.Name or 'Groupbox';

			local Groupbox = Tab:AddGroupbox({
				Name = Name;
				Side = resolveSide(Box.Side);
			});

			UI.Groupboxes[Name] = Groupbox;
			buildElements(Groupbox, Box.Elements, UI);
		end;

		for _, Box in ipairs(Config.Tabboxes or {}) do
			local Tabbox = Tab:AddTabbox({
				Name = Box.Name;
				Side = resolveSide(Box.Side);
			});

			for _, Sub in ipairs(Box.Tabs or {}) do
				local Name = Sub.Name or 'Tab';
				local SubTab = Tabbox:AddTab(Name);

				UI.Groupboxes[(Box.Name and (Box.Name .. '/') or '') .. Name] = SubTab;
				buildElements(SubTab, Sub.Elements, UI);
			end;
		end;
	end;

	---A small standalone window a toggle can pop up, built from the same element
	---list a groupbox takes. It sizes itself to fit, drags by its title bar and
	---hides with the menu unless FollowMenu is turned off.
	---@param Config table Title, Size, Position, Elements and friends
	---@return table
	function Library:CreatePanel(Config)
		Config = Config or {};

		local Panel = setmetatable({
			Type = 'Panel';
			Tabs = {};
			Groupboxes = {};
			Elements = {};
			Panels = {};

			-- What the owning toggle last asked for, separate from whether the
			-- panel is actually on screen right now.
			Wanted = Config.AutoShow == true;
			FollowMenu = Config.FollowMenu ~= false;
		}, UIApi);

		local Popout = Library:CreatePopout({
			Title = Config.Title or 'Panel';
			Version = Config.Version;
			Size = Config.Size or Vector2.new(300, 200);
			Position = Config.Position;
			Center = Config.Center;
			AutoShow = false;
		});

		Panel.Window = Popout;
		Panel.Holder = Popout.Holder;
		Panel.Container = Popout.Container;

		---Re-evaluate whether the panel should be on screen.
		function Panel:Refresh()
			Popout.Holder.Visible = Panel.Wanted == true
				and ((not Panel.FollowMenu) or Library:IsMenuOpen());
		end;

		---Show or hide the panel.
		---@param Visible boolean
		function Panel:SetVisible(Visible)
			Panel.Wanted = Visible and true or false;
			Panel:Refresh();
			return Panel;
		end;

		function Panel:Show()
			return Panel:SetVisible(true);
		end;

		function Panel:Hide()
			return Panel:SetVisible(false);
		end;

		---Flip the panel. Overrides UIApi:Toggle, which drives the main menu.
		function Panel:Toggle()
			return Panel:SetVisible(not Panel.Wanted);
		end;

		function Panel:IsVisible()
			return Popout.Holder.Visible;
		end;

		---Resize the panel to fit its contents again. Called for you when
		---elements are added, this is for when you change one by hand.
		function Panel:Resize()
			return Popout:Resize();
		end;

		---Destroy the panel and free the flags it registered.
		function Panel:Remove()
			for Idx in next, Panel.Elements do
				Toggles[Idx] = nil;
				Options[Idx] = nil;
			end;

			table.clear(Panel.Elements);
			Popout.Holder:Destroy();
		end;

		-- Close cross in the title bar. Falls back to hiding itself when no
		-- owning toggle claimed it.
		if Config.CloseButton ~= false then
			local Close = Library:Create('TextButton', {
				Name = 'Close';
				BackgroundTransparency = 1;
				AutoButtonColor = false;
				Position = UDim2.new(1, -20, 0, 0);
				Size = UDim2.fromOffset(16, 25);
				Font = Library.Font;
				Text = 'X';
				TextSize = 14;
				TextColor3 = Library.FontColor;
				ZIndex = 6;
				Parent = Popout.Holder;
			});

			Library:AddToRegistry(Close, {
				TextColor3 = 'FontColor';
			});

			Library:OnHighlight(Close, Close,
				{ TextColor3 = 'AccentColor' },
				{ TextColor3 = 'FontColor' }
			);

			Close.MouseButton1Click:Connect(function()
				if Panel.OnClose then
					Panel.OnClose();
				else
					Panel:Hide();
				end;
			end);
		end;

		buildElements(Popout, Config.Elements, Panel);

		Library:OnMenuToggled(function()
			Panel:Refresh();
		end);

		Panel:Refresh();

		return Panel;
	end;

	---Read an element's current value by flag.
	---@param Idx string
	function UIApi:Get(Idx)
		local Object = Toggles[Idx] or Options[Idx] or self.Elements[Idx];
		return Object and Object.Value;
	end;

	---Write an element's value by flag. Fires its callback like a click would.
	---@param Idx string
	---@param Value any
	---@return boolean
	function UIApi:Set(Idx, Value)
		local Object = Toggles[Idx] or Options[Idx] or self.Elements[Idx];

		if Object and Object.SetValue then
			Object:SetValue(Value);
			return true;
		end;

		return false;
	end;

	---Subscribe to an element's changes after the fact.
	---@param Idx string
	---@param Func function
	function UIApi:OnChanged(Idx, Func)
		local Object = Toggles[Idx] or Options[Idx] or self.Elements[Idx];

		if Object and Object.OnChanged then
			Object:OnChanged(Func);
		end;

		return Object;
	end;

	---The raw element object (toggle, slider, dropdown, picker) behind a flag.
	---@param Idx string
	function UIApi:Element(Idx)
		return Toggles[Idx] or Options[Idx] or self.Elements[Idx];
	end;

	---A tab by the name it was declared with.
	---@param Name string
	function UIApi:Tab(Name)
		return self.Tabs[Name];
	end;

	---A groupbox by name, so more elements can be added to it later on.
	---@param Name string
	function UIApi:Groupbox(Name)
		return self.Groupboxes[Name];
	end;

	---The popout panel a toggle owns, by that toggle's flag.
	---@param Idx string
	function UIApi:Panel(Idx)
		return self.Panels[Idx];
	end;

	---Open or close the menu.
	function UIApi:Toggle()
		return Library:Toggle();
	end;

	---Drop only the tabs this UI built, leaving the rest of the menu alone.
	---Use this when a config was built into a window that already existed.
	function UIApi:Remove()
		for _, Panel in next, self.Panels do
			if type(Panel) == 'table' and Panel.Remove then
				Panel:Remove();
			end;
		end;

		for _, Tab in next, self.Tabs do
			if type(Tab) == 'table' and Tab.Remove then
				Tab:Remove();
			end;
		end;

		-- Free the flags back up so the same config can be rebuilt later.
		for Idx in next, self.Elements do
			Toggles[Idx] = nil;
			Options[Idx] = nil;
		end;

		table.clear(self.Tabs);
		table.clear(self.Groupboxes);
		table.clear(self.Elements);
		table.clear(self.Panels);
	end;

	---Tear the whole menu down.
	function UIApi:Unload()
		return Library:Unload();
	end;

	---Add tabs from a config table to a window that already exists. Same Tabs
	---shape CreateUI takes, minus the window options.
	---@param Window table whatever Library:CreateWindow returned
	---@param Config table a table holding a Tabs list
	---@return table
	function Library:BuildUI(Window, Config)
		Config = Config or {};

		local UI = setmetatable({
			Window = Window;
			Tabs = {};
			Groupboxes = {};
			Elements = {};
			Panels = {};
		}, UIApi);

		for Index, TabConfig in ipairs(Config.Tabs or {}) do
			local Name = TabConfig.Name or ('Tab ' .. Index);
			local Tab = Window:AddTab(Name);

			UI.Tabs[Name] = Tab;
			buildTab(Tab, TabConfig, UI);
		end;

		return UI;
	end;

	---Build a menu from one config table.
	---@param Config table window options plus a Tabs list
	---@return table
	function Library:CreateUI(Config)
		Config = Config or {};

		-- Centre only when the caller did not place the window itself.
		local Center = Config.Center;

		if Center == nil then
			Center = Config.Position == nil;
		end;

		local Window = Library:CreateWindow({
			Title = Config.Title or 'Library';
			ColoredTitle = Config.ColoredTitle;
			Version = Config.Version;
			VersionColor = Config.VersionColor;

			Size = Config.Size;
			Position = Config.Position;
			MinSize = Config.MinSize;
			Center = Center;
			AutoShow = Config.AutoShow ~= false;

			TabPadding = Config.TabPadding;
			TabStripWidth = Config.TabStripWidth;
			MenuFadeTime = Config.MenuFadeTime;
			DontFade = Config.DontFade;
			Search = Config.Search;

			Image = Config.Image;
			ImageSize = Config.ImageSize;
			Snow = Config.Snow;
			SnowCount = Config.SnowCount;
			SnowColor = Config.SnowColor;
			CustomCursor = Config.CustomCursor;
			CustomCursorImage = Config.CustomCursorImage;
			BackgroundBrightness = Config.BackgroundBrightness;
			BackgroundDimColor = Config.BackgroundDimColor;
		});

		local UI = Library:BuildUI(Window, Config);

		Library.UI = UI;

		return UI;
	end;
end;

local function OnPlayerChange()
	local PlayerList = GetPlayersString();

	for _, Value in next, Options do
		if Value.Type == 'Dropdown' and Value.SpecialType == 'Player' then
			Value:SetValues(PlayerList);
		end;
	end;
end;

Players.PlayerAdded:Connect(OnPlayerChange);
Players.PlayerRemoving:Connect(OnPlayerChange);

getgenv().Library = Library
return Library
