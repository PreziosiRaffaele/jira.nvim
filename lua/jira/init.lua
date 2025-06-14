local curl = require("plenary.curl")
local Utils = require("jira.utils")

---@class JiraConfig
---@field domain string
---@field token string
---@field key string | string[]
---@field api_version? number
---@field format? fun(issue: table): string[]
local config = {
	domain = vim.env.JIRA_DOMAIN,
	token = vim.env.JIRA_API_TOKEN,
	key = vim.env.JIRA_PROJECT_KEY or { "PM" },
	api_version = 3,
}

---@return string[]
local function get_keys()
	if type(config.key) == "string" then
		return vim.tbl_map(vim.trim, vim.split(config.key, ","))
	end
	return config.key ---@type string[]
end

---@param issue_id string
local function get_issue(issue_id)
	local url = "https://" .. config.domain .. "/rest/api/" .. config.api_version .. "/issue/" .. issue_id
	print("Jira: Requesting URL: " .. url)
	local response = curl.get(url, {
		headers = {
			["Content-Type"] = "application/json",
			["Authorization"] = "Bearer " .. config.token,
		},
	})
	if response.status < 400 then
		print("Jira: Successful response: " .. response.status)
		return vim.fn.json_decode(response.body)
	else
		print("Jira: Error response: " .. response.status)
		print("Jira: Error Body: " .. response.body)
	end
end

-- @param issue table
-- @returns string[]
local function format_issue(issue)
	local assignee = ""
	if issue.fields.assignee ~= vim.NIL then
		local i, j = string.find(issue.fields.assignee.displayName, "%w+")
		if i ~= nil then
			assignee = " - @" .. string.sub(issue.fields.assignee.displayName, i, j)
		end
	end
	local content = {
		issue.fields.summary,
		"---",
		"`" .. issue.fields.status.name .. "`" .. assignee,
		"",
		Utils.adf_to_markdown(issue.fields.description),
	}
	vim.lsp.util.open_floating_preview(content, "markdown", { border = "rounded" })
end

local Jira = {}

function Jira.open_issue()
	local issue_id = Jira.parse_issue() or vim.fn.input("Issue: ")
	local url = "https://" .. config.domain .. "/browse/" .. issue_id

	if vim.ui.open then
		vim.ui.open(url)
		return
	end

	local os_name = vim.loop.os_uname().sysname
	local is_windows = vim.loop.os_uname().version:match("Windows")

	if os_name == "Darwin" then
		os.execute("open " .. url)
	elseif os_name == "Linux" then
		os.execute("xdg-open " .. url)
	elseif is_windows then
		os.execute("start " .. url)
	end
end

function Jira.view_issue()
	local issue_id = Jira.parse_issue() or vim.fn.input("Issue: ")
	print("Jira: view_issue() - issue_id: " .. vim.inspect(issue_id))
	if not issue_id or issue_id == "" then
		print("Jira: No issue ID provided or parsed.")
		return
	end
	local issue = get_issue(issue_id)
	print("Jira: view_issue() - raw issue data: " .. vim.inspect(issue))
	vim.schedule(function()
		if issue == nil then
			print("Jira: Invalid response or issue is nil.")
			return
		end
		local format = config.format or format_issue
		local content = format(issue)
		vim.lsp.util.open_floating_preview(content, "markdown", { border = "rounded" })
	end)
end

---@return string | nil
function Jira.parse_issue()
	local current_word = vim.fn.expand("<cWORD>")
	for _, key in ipairs(get_keys()) do
		local i, j = string.find(current_word, key .. "%-%d+")
		if i ~= nil then
			return string.sub(current_word, i, j)
		end
	end
	return nil
end

---@param opts? JiraConfig
---@return JiraConfig
function Jira.setup(opts)
	opts = opts or {}
	config = vim.tbl_deep_extend("force", config, opts)
	vim.api.nvim_create_user_command("JiraView", Jira.view_issue, {})
	vim.api.nvim_create_user_command("JiraOpen", Jira.open_issue, {})
	return config
end

return Jira
